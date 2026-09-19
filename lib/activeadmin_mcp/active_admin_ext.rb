module ActiveadminMcp
  # Every patch this gem applies to ActiveAdmin lives in this one file, so the
  # coupling has a single place to check when ActiveAdmin is upgraded.
  #
  # ActiveAdmin stores an action's option hash but exposes only the keys it
  # uses itself (:method, :title, :form, :if, ...). MCP metadata is declared as
  # an extra `mcp:` key on that same hash, which ActiveAdmin carries through
  # untouched, so all we need is a reader to get it back out.
  module ActiveAdminExt
    module ActionOptions
      def mcp_options
        options = instance_variable_get(:@options)
        options.is_a?(Hash) ? options[:mcp] : nil
      end
    end

    # Records MCP annotations declared against a resource for actions it does
    # not declare inline — typically because a shared concern declares them,
    # and one description could not suit every resource that includes it.
    #
    # They live on the resource config rather than on the action, so a
    # declaration may appear above or below the `include` that brings the
    # action in, and so they are discarded with the config when ActiveAdmin
    # reloads in development.
    module ResourceAnnotations
      def mcp_annotations
        @mcp_annotations ||= []
      end
    end

    module McpActionDsl
      # Annotates an already-declared action so it is exposed as an MCP tool.
      # Never declares the action itself: naming one that does not exist is
      # reported when the catalog is built, not here, because the action may
      # legitimately be declared after this call.
      def mcp_action(name, kind: nil, **options)
        config.mcp_annotations << {
          action_name: name.to_sym,
          kind: kind&.to_sym,
          options: options,
        }
      end
    end

    # Installed separately from, and earlier than, apply!. A registration block
    # calls mcp_action while ActiveAdmin loads its resources, which is before
    # ActiveAdmin.after_load fires — so waiting for that hook would mean the
    # method did not exist at the only moment anybody calls it.
    #
    # ActiveAdmin::Resource and ActiveAdmin::ResourceDSL both exist as soon as
    # ActiveAdmin is required, so there is nothing to wait for. Idempotent:
    # including a module twice is a no-op.
    def self.apply_dsl!
      return false unless defined?(::ActiveAdmin::Resource) && defined?(::ActiveAdmin::ResourceDSL)

      ::ActiveAdmin::Resource.include(ResourceAnnotations)
      ::ActiveAdmin::ResourceDSL.include(McpActionDsl)
      true
    end

    # ActiveAdmin::BatchAction only exists once ActiveAdmin's before_load hooks
    # have run, so this is called from ActiveAdmin.after_load rather than at
    # require time.
    def self.apply!
      unless applicable?
        # Without these readers every opted-in action silently vanishes from
        # tools/list, because ActionCatalog can no longer see an mcp: option
        # anywhere. Say so rather than shipping a feature that is quietly off.
        warn("[activeadmin_mcp] ActiveAdmin::ControllerAction / ActiveAdmin::BatchAction not found: " \
             "MCP action options cannot be read, so no opted-in actions will be exposed as tools.")
        return false
      end

      ::ActiveAdmin::ControllerAction.include(ActionOptions)
      ::ActiveAdmin::BatchAction.include(ActionOptions)
      true
    end

    def self.applicable?
      defined?(::ActiveAdmin::ControllerAction) && defined?(::ActiveAdmin::BatchAction) ? true : false
    end
  end
end
