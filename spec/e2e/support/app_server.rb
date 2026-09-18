# frozen_string_literal: true

require "fileutils"
require "net/http"
require "socket"
require "timeout"

module E2E
  # Boots the generated application under Puma and tears it down again.
  class AppServer
    BOOT_TIMEOUT = 60
    LOG_PATH = File.join(AppBuilder::APP_PATH, "log", "e2e.log")

    MINT_SCRIPT = <<~RUBY
      user = AdminUser.find_by!(email: "#{AppBuilder::ADMIN_EMAIL}")
      puts ActiveadminMcp::ApiToken.create!(user: user, name: "e2e").raw_token
    RUBY

    class BootError < StandardError; end

    attr_reader :port, :pid

    class << self
      attr_reader :instance

      def start!
        @instance ||= new.tap(&:start!)
      end

      def stop!
        @instance&.stop!
        @instance = nil
      end

      # Creates an API token for the seeded admin user and returns the raw
      # value, which the model only exposes at creation time.
      def mint_token!
        output = AppBuilder.run!(["bin/rails", "runner", MINT_SCRIPT])
        token = output[/aamcp_[0-9a-f]{64}/]

        raise BootError, "Could not mint an API token:\n\n#{output}" unless token

        token
      end
    end

    def initialize
      @port = free_port
    end

    def start!
      FileUtils.mkdir_p(File.dirname(LOG_PATH))
      FileUtils.rm_f(LOG_PATH)

      Bundler.with_unbundled_env do
        @pid = Process.spawn(
          { "RAILS_ENV" => "development" },
          "bin/rails", "server", "-p", port.to_s, "-b", "127.0.0.1",
          chdir: AppBuilder::APP_PATH,
          out: [LOG_PATH, "a"],
          err: [:child, :out]
        )
      end

      at_exit { stop! }
      wait_for_boot!
      self
    end

    def stop!
      return unless @pid

      Process.kill("TERM", @pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil # Already gone.
    ensure
      @pid = nil
    end

    def base_url
      "http://127.0.0.1:#{port}"
    end

    def mcp_url
      "#{base_url}/mcp"
    end

    private

    def free_port
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1].tap { server.close }
    end

    # Polls the mount point rather than the root path: a 401 or a JSON-RPC
    # error both mean the engine is mounted and answering, which is all the
    # suite needs to know before it starts. Rails booting but the engine
    # failing to mount also answers HTTP requests (with an HTML 404), so a
    # response alone is not enough evidence — it must look like the engine,
    # not just like a webserver.
    def wait_for_boot!
      Timeout.timeout(BOOT_TIMEOUT) do
        loop do
          begin
            response = Net::HTTP.post(URI(mcp_url), "{}", "Content-Type" => "application/json")
            return if engine_response?(response)

            sleep 0.5
          rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, EOFError, SocketError
            sleep 0.5
          end
        end
      end
    rescue Timeout::Error
      raise BootError, "Server did not boot within #{BOOT_TIMEOUT}s. Log tail:\n\n#{log_tail}"
    end

    def engine_response?(response)
      return true if response.code == "401"

      response.code == "200" && response["Content-Type"].to_s.include?("application/json")
    end

    def log_tail
      return "(no log at #{LOG_PATH})" unless File.exist?(LOG_PATH)

      File.readlines(LOG_PATH).last(40).join
    end
  end
end
