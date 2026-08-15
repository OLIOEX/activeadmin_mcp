# frozen_string_literal: true

module ActiveadminMcp
  # Updates a single ActiveAdmin-managed record, enforcing the same three gates
  # the admin UI would: the resource must expose the update action, the current
  # user must be authorized, and only fields the admin form permits are written.
  class RecordUpdater
    UPDATE = :update

    # Raised internally when the resource's permitted params cannot be resolved.
    class PermitError < StandardError; end

    def initialize(resource:, current_user:)
      @resource = resource
      @current_user = current_user
    end

    def call(id:, attributes:)
      config = @resource[:config]

      return error("Resource is not editable: #{@resource[:name]}") unless editable?(config)

      record = @resource[:model].find_by(id: id)
      return error("Record not found: #{@resource[:name]}##{id}") unless record

      unless authorized?(config, record)
        return error("Not authorized to update #{@resource[:name]}##{id}")
      end

      begin
        permitted = permitted_attributes(config, attributes)
      rescue PermitError => e
        return error(e.message)
      end
      return error("No permitted attributes to update") if permitted.empty?

      if record.update(permitted)
        {
          resource: @resource[:name],
          id: record.id,
          updated: permitted.keys,
          record: record.as_json,
        }
      else
        error("Validation failed", details: record.errors.full_messages)
      end
    end

    private

    def editable?(config)
      config.defined_actions.include?(UPDATE)
    end

    def authorized?(config, record)
      adapter_class = config.namespace.authorization_adapter
      adapter_class = adapter_class.constantize if adapter_class.is_a?(String)
      adapter_class.new(config, @current_user).authorized?(UPDATE, record)
    end

    # Resolves the fields we may write, accepting exactly what the admin form
    # accepts. Prefers the resource's own `permit_params` (via the controller's
    # compiled permitted_params); when a resource declares its writable fields
    # through a `form do ... end` block instead — as ActiveAdmin's default
    # permitted_params then returns nil — derives them from the form inputs.
    # Fails closed if neither can be resolved.
    def permitted_attributes(config, attributes)
      from_permit_params(config, attributes) ||
        from_form(config, attributes) ||
        raise(PermitError, "Could not determine permitted attributes: #{@resource[:name]}")
    end

    def from_permit_params(config, attributes)
      param_key = config.param_key.to_sym
      controller = config.controller.new
      return nil unless controller.respond_to?(:permitted_params, true)

      controller.params = ActionController::Parameters.new(param_key => attributes)
      permitted = controller.send(:permitted_params)
      scoped = permitted && permitted[param_key]
      scoped ? scoped.to_h.symbolize_keys : nil
    rescue StandardError
      nil
    end

    def from_form(config, attributes)
      fields = form_fields(config)
      return nil if fields.empty?

      ActionController::Parameters.new(attributes).permit(*fields).to_h.symbolize_keys
    rescue StandardError
      nil
    end

    def form_fields(config)
      return [] unless config.respond_to?(:page_presenters)

      block = config.page_presenters[:form]&.block
      return [] unless block

      FormFieldCollector.new.collect(&block)
    end

    def error(message, details: nil)
      result = { error: message }
      result[:details] = details if details
      result
    end
  end
end
