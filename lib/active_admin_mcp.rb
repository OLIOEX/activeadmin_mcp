# frozen_string_literal: true

require_relative "active_admin_mcp/version"
require_relative "active_admin_mcp/configuration"
require_relative "active_admin_mcp/resource_registry"
require_relative "active_admin_mcp/record_updater"
require_relative "active_admin_mcp/request_handler"
require_relative "active_admin_mcp/engine"

module ActiveAdminMcp
  class Error < StandardError; end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end
  end
end
