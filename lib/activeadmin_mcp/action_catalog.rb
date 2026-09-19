module ActiveadminMcp
  # Finds every ActiveAdmin action an application has opted in to MCP.
  #
  # Nothing is cached: ActiveAdmin reloads resources in development, and a
  # stale catalog would advertise tools that no longer exist.
  module ActionCatalog
    # Tool names the engine reserves for itself, including names Phase 2 and 3
    # will take, so an application cannot silently shadow one later.
    RESERVED = %w[list_resources query update create describe_form].freeze

    class << self
      def all
        ResourceRegistry.resources.flat_map { |entry| definitions_for(entry[:config]) }
      end

      def find(tool_name)
        all.find { |definition| definition.tool_name == tool_name }
      end

      private

      def definitions_for(config)
        candidates(config).filter_map do |action, kind|
          definition = ActionDefinition.build(config: config, action: action, kind: kind)
          next unless definition

          next warn_and_skip(definition.errors.join("; ")) unless definition.valid?
          next warn_and_skip("#{definition.tool_name} collides with a built-in tool") if reserved?(definition)

          definition
        end
      end

      def candidates(config)
        pairs = []
        pairs.concat(safe_actions(config, :member_actions).map { |a| [a, :member] })
        pairs.concat(safe_actions(config, :collection_actions).map { |a| [a, :collection] })
        pairs.concat(safe_actions(config, :batch_actions).map { |a| [a, :batch] }) if batch_enabled?(config)
        pairs.select { |action, _kind| action.respond_to?(:mcp_options) }
      end

      def safe_actions(config, reader)
        config.respond_to?(reader) ? Array(config.public_send(reader)) : []
      end

      # ActiveAdmin keeps registered batch actions even when the namespace has
      # batch actions switched off, and hides them in the UI. Match that.
      def batch_enabled?(config)
        return false unless config.respond_to?(:batch_actions_enabled?)

        config.batch_actions_enabled?
      end

      def reserved?(definition)
        RESERVED.include?(definition.tool_name)
      end

      def warn_and_skip(message)
        warn("[activeadmin_mcp] ignoring action: #{message}")
        nil
      end
    end
  end
end
