# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"

module E2E
  # Generates a real Rails + ActiveAdmin application with the gem under test
  # installed into it, and caches the result between runs.
  #
  # The application is cached on a fingerprint of this file, so editing the
  # build recipe forces a rebuild. Editing the gem's own library code does
  # not, and must not: the application references the gem with `path:`, so it
  # always loads the current working tree.
  class AppBuilder
    RAILS_VERSION = "7.2.2.2"
    REPO_ROOT = File.expand_path("../../..", __dir__)
    APP_PATH = File.join(REPO_ROOT, "tmp", "e2e_app")
    FINGERPRINT_PATH = File.join(APP_PATH, ".e2e_fingerprint")

    ADMIN_EMAIL = "admin@example.com"
    ADMIN_PASSWORD = "password"

    GEMFILE_ADDITIONS = <<~RUBY
      gem "activeadmin", "~> 3.2"
      gem "devise"
      gem "sassc-rails"
      gem "activeadmin_mcp", path: "GEM_PATH"
    RUBY

    class BuildError < StandardError; end

    class << self
      def build!
        new.build!
      end

      # Runs a command with the gem's own bundler environment stripped out, so
      # the generated application resolves against its own Gemfile. Raises with
      # the combined output on failure: a silent build failure here surfaces
      # much later as an inscrutable boot error.
      def run!(command, chdir: APP_PATH)
        output = nil
        status = nil

        Bundler.with_unbundled_env do
          output, status = Open3.capture2e(*command, chdir: chdir)
        end

        return output if status.success?

        raise BuildError, "Command failed: #{command.join(' ')}\n\n#{output}"
      end
    end

    def build!
      return APP_PATH if cached?

      FileUtils.rm_rf(APP_PATH)
      FileUtils.mkdir_p(File.dirname(APP_PATH))

      generate_app
      write_gemfile
      bundle_install
      install_active_admin
      generate_fixture_models
      write_model_overrides
      write_admin_registrations
      install_mcp
      configure_mcp
      migrate
      seed

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
      Digest::SHA256.hexdigest([RAILS_VERSION, File.read(__FILE__)].join("\n"))
    end

    def run!(command, chdir: APP_PATH)
      self.class.run!(command, chdir: chdir)
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
      File.open(File.join(APP_PATH, "Gemfile"), "a") do |f|
        f.puts
        f.puts GEMFILE_ADDITIONS.gsub("GEM_PATH", REPO_ROOT)
      end
    end

    def bundle_install
      run!(["bundle", "install"])
    end

    def install_active_admin
      run!(["bin/rails", "generate", "active_admin:install"])
    end

    def generate_fixture_models
      run!(["bin/rails", "generate", "model", "Author", "name:string", "email:string"])
      run!(["bin/rails", "generate", "model", "Post", "title:string", "body:text", "slug:string"])
    end

    # Ransack 4 (used by ActiveAdmin 3.x, and called directly by the gem's
    # `query` tool) refuses to filter on any attribute not listed in a
    # model's ransackable_attributes allowlist. Without this override every
    # `query` example against these fixtures would fail with a Ransack
    # error rather than exercising the gem.
    def write_model_overrides
      File.write(File.join(APP_PATH, "app/models/post.rb"), <<~RUBY)
        # frozen_string_literal: true

        class Post < ApplicationRecord
          def self.ransackable_attributes(_auth_object = nil)
            column_names
          end
        end
      RUBY

      File.write(File.join(APP_PATH, "app/models/author.rb"), <<~RUBY)
        # frozen_string_literal: true

        class Author < ApplicationRecord
          def self.ransackable_attributes(_auth_object = nil)
            column_names
          end
        end
      RUBY
    end

    # Post is fully editable but permits only title and body, so the suite can
    # prove an unpermitted attribute (slug) is dropped rather than written.
    # Author registers no update action, so the suite can prove update refuses
    # a resource the admin UI would not let you edit either.
    def write_admin_registrations
      File.write(File.join(APP_PATH, "app/admin/posts.rb"), <<~RUBY)
        # frozen_string_literal: true

        ActiveAdmin.register Post do
          permit_params :title, :body
        end
      RUBY

      File.write(File.join(APP_PATH, "app/admin/authors.rb"), <<~RUBY)
        # frozen_string_literal: true

        ActiveAdmin.register Author do
          actions :index, :show
        end
      RUBY
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

    def seed
      run!(["bin/rails", "runner", SEED_SCRIPT])
    end

    SEED_SCRIPT = <<~RUBY
      AdminUser.find_or_create_by!(email: "#{ADMIN_EMAIL}") do |user|
        user.password = "#{ADMIN_PASSWORD}"
        user.password_confirmation = "#{ADMIN_PASSWORD}"
      end

      Author.find_or_create_by!(email: "ursula@example.com") { |a| a.name = "Ursula" }
      Author.find_or_create_by!(email: "terry@example.com") { |a| a.name = "Terry" }

      Post.find_or_create_by!(slug: "a-wizard-of-earthsea") do |p|
        p.title = "A Wizard of Earthsea"
        p.body = "The first."
      end
      Post.find_or_create_by!(slug: "the-tombs-of-atuan") do |p|
        p.title = "The Tombs of Atuan"
        p.body = "The second."
      end
      Post.find_or_create_by!(slug: "small-gods") do |p|
        p.title = "Small Gods"
        p.body = "Unrelated."
      end
    RUBY
  end
end
