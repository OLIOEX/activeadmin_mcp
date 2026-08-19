# frozen_string_literal: true

require_relative "activeadmin_mcp/version"
require_relative "activeadmin_mcp/configuration"
require_relative "activeadmin_mcp/authorization"
require_relative "activeadmin_mcp/resource_registry"
require_relative "activeadmin_mcp/form_field_collector"
require_relative "activeadmin_mcp/record_updater"
require_relative "activeadmin_mcp/request_handler"
require_relative "activeadmin_mcp/engine"

module ActiveadminMcp
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
