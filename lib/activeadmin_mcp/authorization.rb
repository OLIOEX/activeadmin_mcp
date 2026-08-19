# frozen_string_literal: true

module ActiveadminMcp
  # Applies a resource's ActiveAdmin authorization adapter to MCP tool calls, so
  # reads, listings and writes obey the same rules as the admin UI.
  #
  # ActiveAdmin's default adapter authorizes every action and returns collections
  # unchanged, so applications without an authorization adapter are unaffected.
  # Applications that configure one (CanCanCan via `cancan_ability_class`, Pundit,
  # a custom adapter, ...) get their policy enforced on every path.
  class Authorization
    READ = :read

    def self.for(config, current_user)
      adapter_class = config.namespace.authorization_adapter
      adapter_class = adapter_class.constantize if adapter_class.is_a?(String)
      new(adapter_class.new(config, current_user))
    end

    def initialize(adapter)
      @adapter = adapter
    end

    def authorized?(action, subject)
      @adapter.authorized?(action, subject)
    end

    def scope_collection(collection, action = READ)
      @adapter.scope_collection(collection, action)
    end
  end
end
