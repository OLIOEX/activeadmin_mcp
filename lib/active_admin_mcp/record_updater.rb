# frozen_string_literal: true

module ActiveAdminMcp
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

    # Runs the incoming attributes through the resource controller's own
    # permitted_params (compiled from `permit_params`), so we accept exactly what
    # the admin form accepts. Fails closed if that cannot be resolved.
    def permitted_attributes(config, attributes)
      param_key = config.param_key.to_sym
      controller = config.controller.new

      unless controller.respond_to?(:permitted_params, true)
        raise PermitError, "Resource does not declare permit_params: #{@resource[:name]}"
      end

      controller.params = ActionController::Parameters.new(param_key => attributes)
      permitted = controller.send(:permitted_params)[param_key]
      permitted ? permitted.to_h.symbolize_keys : {}
    rescue PermitError
      raise
    rescue StandardError => e
      raise PermitError, "Could not determine permitted attributes: #{e.message}"
    end

    def error(message, details: nil)
      result = { error: message }
      result[:details] = details if details
      result
    end
  end
end
