# frozen_string_literal: true

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
