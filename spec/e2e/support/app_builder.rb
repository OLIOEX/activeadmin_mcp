require "bundler"
require "digest"
require "fileutils"
require "open3"
require "sqlite3"

module E2E
  # Generates a real Rails + ActiveAdmin application with the gem under test
  # installed into it, and caches the result between runs.
  #
  # The application is cached on a fingerprint of this file and of everything
  # under `../fixture_app`, so editing either the build recipe or a fixture
  # forces a rebuild. Editing the gem's own library code does not, and must
  # not: the application references the gem with `path:`, so it always loads
  # the current working tree.
  class AppBuilder
    RAILS_VERSION = "7.2.2.2"
    REPO_ROOT = File.expand_path("../../..", __dir__)
    APP_PATH = File.join(REPO_ROOT, "tmp", "e2e_app")
    FINGERPRINT_PATH = File.join(APP_PATH, ".e2e_fingerprint")

    # Checked-in files copied over the generated application. Kept as real
    # files rather than heredocs so they can be read and edited directly.
    FIXTURE_APP_PATH = File.expand_path("../fixture_app", __dir__)

    # Documentation, not part of the application.
    FIXTURE_DOCS = "README.md"

    # Appended to the generated Gemfile rather than copied into place.
    FIXTURE_GEMFILE = "Gemfile.deps"

    DATABASE_PATH = "storage/development.sqlite3"

    # A copy of the database taken immediately after migrating and seeding.
    # Restoring from it costs milliseconds; re-seeding is a full Rails boot,
    # which is what makes it affordable to reset between examples.
    DATABASE_SNAPSHOT_PATH = "storage/seeded.sqlite3"

    # Tables holding state created after the snapshot was taken, which a reset
    # must therefore leave alone. The API token is minted once the server is
    # up, so restoring this table would revoke it and every subsequent request
    # would come back 401.
    SESSION_TABLES = %w[mcp_api_tokens].freeze

    ADMIN_EMAIL = "admin@example.com"
    ADMIN_PASSWORD = "password"

    class BuildError < StandardError; end

    class << self
      def build!
        new.build!
      end

      def snapshot_exists?
        File.exist?(File.join(APP_PATH, DATABASE_SNAPSHOT_PATH))
      end

      # Puts the seeded rows back, table by table, through SQLite itself.
      #
      # Copying the snapshot file over the database would be simpler but is
      # not safe here: the application server holds the database open, and
      # swapping the file underneath its page cache invites it to read a
      # mixture of the old and new images. Going through a transaction on the
      # live connection takes SQLite's locks and leaves every reader
      # consistent, which is what makes this usable between examples rather
      # than only between runs.
      def reset_database!
        snapshot = File.join(APP_PATH, DATABASE_SNAPSHOT_PATH)
        raise BuildError, "No database snapshot at #{snapshot}" unless File.exist?(snapshot)

        SQLite3::Database.new(File.join(APP_PATH, DATABASE_PATH)) do |db|
          db.execute("ATTACH DATABASE ? AS seed", [snapshot])

          begin
            db.transaction { restore_tables(db) }
          ensure
            db.execute("DETACH DATABASE seed")
          end
        end
      end

      # Runs a command with the gem's own bundler environment stripped out, so
      # the generated application resolves against its own Gemfile. Raises with
      # the combined output on failure: a silent build failure here surfaces
      # much later as an inscrutable boot error.
      def run!(command, chdir: APP_PATH, env: {})
        output = nil
        status = nil

        Bundler.with_unbundled_env do
          output, status = Open3.capture2e(env, *command, chdir: chdir)
        end

        return output if status.success?

        raise BuildError, "Command failed: #{command.join(' ')}\n\n#{output}"
      end

      private

      def restore_tables(db)
        tables = db.execute(
          "SELECT name FROM seed.sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        ).flatten - SESSION_TABLES

        tables.each do |table|
          db.execute("DELETE FROM main.\"#{table}\"")
          db.execute("INSERT INTO main.\"#{table}\" SELECT * FROM seed.\"#{table}\"")
        end
      end
    end

    def build!
      if cached?
        # The bundle lives inside the cached directory (vendor/bundle), but a
        # cache restore does not guarantee it is satisfied for this machine.
        bundle_install

        # The previous run's `update` examples mutated the seed data, so the
        # database has to be put back. Fall back to re-seeding when there is
        # no snapshot, which is the case for a cache saved before snapshots
        # existed.
        self.class.snapshot_exists? ? self.class.reset_database! : seed
        return APP_PATH
      end

      FileUtils.rm_rf(APP_PATH)
      FileUtils.mkdir_p(File.dirname(APP_PATH))

      generate_app
      write_gemfile
      vendor_bundle_path
      bundle_install
      install_active_admin
      copy_fixture_app
      install_mcp
      configure_mcp
      migrate
      seed
      snapshot_database

      File.write(FINGERPRINT_PATH, fingerprint)
      APP_PATH
    end

    private

    def cached?
      return false if ENV["E2E_REBUILD"]
      return false unless File.exist?(FINGERPRINT_PATH)

      File.read(FINGERPRINT_PATH).strip == fingerprint
    end

    def fingerprint
      Digest::SHA256.hexdigest([RAILS_VERSION, File.read(__FILE__), fixture_digest].join("\n"))
    end

    # Hashes every fixture's path and contents, so editing one invalidates the
    # cache. Without this the fixtures would move out of this file's digest and
    # an edited fixture would be silently ignored on the next run.
    def fixture_digest
      paths = Dir.glob(File.join(FIXTURE_APP_PATH, "**", "*"))
                 .select { |path| File.file?(path) }
                 .reject { |path| File.basename(path) == FIXTURE_DOCS }

      paths.sort.map { |path| "#{path.delete_prefix(FIXTURE_APP_PATH)}\n#{File.read(path)}" }.join("\n")
    end

    def run!(command, chdir: APP_PATH, env: {})
      self.class.run!(command, chdir: chdir, env: env)
    end

    def generate_app
      ensure_rails_installed

      run!(
        [
          "rails", "_#{RAILS_VERSION}_", "new", APP_PATH,
          "--database=sqlite3",
          "--asset-pipeline=sprockets",
          "--skip-git",
          "--skip-test",
          "--skip-system-test",
          "--skip-javascript",
          "--skip-hotwire",
          "--skip-action-cable",
          "--skip-action-mailbox",
          "--skip-action-text",
          "--skip-active-storage",
          "--skip-jbuilder",
          "--skip-bootsnap",
        ],
        chdir: REPO_ROOT
      )
    end

    def ensure_rails_installed
      _, status = Bundler.with_unbundled_env do
        Open3.capture2e("gem", "list", "-i", "rails", "-v", RAILS_VERSION)
      end
      return if status.success?

      self.class.run!(["gem", "install", "rails", "-v", RAILS_VERSION, "--no-document"], chdir: REPO_ROOT)
    end

    def write_gemfile
      additions = File.read(File.join(FIXTURE_APP_PATH, FIXTURE_GEMFILE)).gsub("GEM_PATH", REPO_ROOT)

      File.open(File.join(APP_PATH, "Gemfile"), "a") do |f|
        f.puts
        f.puts additions
      end
    end

    # Vendors the generated app's gems inside APP_PATH itself, rather than the
    # system gem home, so that caching tmp/e2e_app (as CI does) actually
    # caches a runnable app. Without this, Bundler.with_unbundled_env strips
    # BUNDLE_* and the gems installed by `bundle_install` land outside
    # whatever directory gets cached.
    def vendor_bundle_path
      run!(["bundle", "config", "set", "--local", "path", "vendor/bundle"])
    end

    def bundle_install
      run!(["bundle", "install"])
    end

    def install_active_admin
      run!(["bin/rails", "generate", "active_admin:install"])
    end

    # Copies the checked-in fixture application over what the generators
    # produced: the ActiveAdmin registrations, the model allowlists, and the
    # seeds. See spec/e2e/fixture_app/README.md for what each file proves.
    def copy_fixture_app
      fixture_entries.each do |entry|
        FileUtils.cp_r(File.join(FIXTURE_APP_PATH, entry), APP_PATH)
      end
    end

    # Everything in the fixture directory that belongs in the application:
    # not the README, and not the Gemfile fragment, which is appended to the
    # generated Gemfile rather than copied over it.
    def fixture_entries
      (Dir.children(FIXTURE_APP_PATH) - [FIXTURE_DOCS, FIXTURE_GEMFILE]).sort
    end

    def install_mcp
      run!(["bin/rails", "generate", "activeadmin_mcp:install", "--auth", "devise_token"])
    end

    # ActiveAdmin's installer creates AdminUser, but the gem defaults
    # user_class to "User"; without this the ApiToken association never
    # resolves and every authenticated request fails.
    def configure_mcp
      path = File.join(APP_PATH, "config/initializers/activeadmin_mcp.rb")
      contents = File.read(path).sub('# config.user_class = "User"', 'config.user_class = "AdminUser"')

      unless contents.include?('config.user_class = "AdminUser"')
        raise BuildError, "Could not set user_class in #{path}"
      end

      File.write(path, contents)
    end

    def migrate
      run!(["bin/rails", "db:migrate"])
    end

    # Safe to copy the database file directly: the seeding process has
    # exited by this point, so SQLite has checkpointed its write-ahead log
    # into the main file and removed it.
    def snapshot_database
      FileUtils.cp(File.join(APP_PATH, DATABASE_PATH), File.join(APP_PATH, DATABASE_SNAPSHOT_PATH))
    end

    def seed
      run!(
        ["bin/rails", "db:seed"],
        env: { "E2E_ADMIN_EMAIL" => ADMIN_EMAIL, "E2E_ADMIN_PASSWORD" => ADMIN_PASSWORD }
      )
    end
  end
end
