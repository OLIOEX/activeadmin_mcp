module ActiveadminMcp
  # Creates and updates ActiveAdmin-managed records by dispatching the
  # resource's own create and update actions, so a write from an MCP client
  # goes through the same permitted params, callbacks, before_action chain and
  # authorization as the same write made by clicking Save in the admin UI.
  #
  # Three gates run before anything is dispatched: the resource must expose the
  # action, the authorization adapter must allow it, and the resource must
  # declare what may be written. The controller then applies all three again,
  # against the record it builds or loads.
  class RecordWriter
    CREATE = :create
    UPDATE = :update

    def initialize(resource:, current_user:)
      @resource = resource
      @current_user = current_user
      @config = resource[:config]
    end

    def create(attributes:)
      return error("Resource is not creatable: #{resource_name}") unless exposes?(CREATE)

      permitted = resolve_permitted(attributes)
      refusal = permit_refusal(permitted)
      return refusal if refusal
      return error("Not authorized to create #{resource_name}") unless authorized?(CREATE, @config.resource_class)

      write(
        action: CREATE,
        verb: :post,
        path: @config.route_collection_path,
        attributes: attributes,
        written: permitted.keys,
        written_key: :created,
        description: "Create #{resource_name}"
      )
    end

    def update(id:, attributes:)
      return error("Resource is not editable: #{resource_name}") unless exposes?(UPDATE)

      record = @resource[:model].find_by(id: id)
      return error("Record not found: #{resource_name}##{id}") unless record

      permitted = resolve_permitted(attributes)
      refusal = permit_refusal(permitted)
      return refusal if refusal
      return error("Not authorized to update #{resource_name}##{id}") unless authorized?(UPDATE, record)

      write(
        action: UPDATE,
        verb: :patch,
        path: @config.route_instance_path(record),
        attributes: attributes,
        written: permitted.keys,
        written_key: :updated,
        path_params: { id: record.to_param },
        description: "Update #{resource_name}##{id}"
      )
    end

    private

    def write(action:, verb:, path:, attributes:, written:, written_key:, description:, path_params: {})
      record = nil

      outcome = ControllerDispatcher.new(config: @config, current_user: @current_user).call(
        action: action,
        verb: verb,
        path: path,
        params: { @config.param_key => attributes },
        path_params: path_params
      ) { |controller| record = controller.send(:get_resource_ivar) }

      return rejection(record, description, outcome) unless saved?(record)

      {
        resource: resource_name,
        id: record.id,
        written_key => written,
        record: without_sensitive_attributes(record),
      }
    end

    def saved?(record)
      !record.nil? && record.persisted? && record.errors.empty?
    end

    # The controller declined to save. Validation messages are the usual
    # reason, and they are read off the record rather than the response
    # because a rejected write re-renders the admin form — a render the
    # synthesized request may well not survive, leaving the dispatch itself
    # reported as a failure even though the record knows exactly what was
    # wrong with it.
    #
    # With no record and no validation messages, anything the controller put
    # in the flash is the best account left of what the admin UI would have
    # told the user.
    def rejection(record, description, outcome)
      messages = record ? record.errors.full_messages : []
      return error("Validation failed", details: messages) if messages.any?
      return outcome if outcome[:error]

      error("#{description} failed", details: Array(outcome[:flash]&.values).presence)
    end

    def exposes?(action)
      @config.defined_actions.include?(action)
    end

    def authorized?(action, subject)
      Authorization.for(@config, @current_user).authorized?(action, subject)
    end

    # Turns what the controller says it would permit into a refusal, or nil to
    # go ahead. The answer is not used to filter the write — dispatch means
    # ActiveAdmin applies permit_params itself — but to refuse early, and with
    # a reason, in the two cases where dispatching would otherwise fail
    # obscurely: a resource that never declared permit_params, and a call whose
    # every attribute would be dropped.
    #
    # A resource with no permit_params cannot be written through ActiveAdmin's
    # own forms either — Rails raises ForbiddenAttributesError on the
    # unpermitted params — so refusing it says what the admin UI would.
    def permit_refusal(permitted)
      if permitted.nil?
        return error("Resource declares no permit_params, so nothing may be written: #{resource_name}")
      end

      error("No permitted attributes to write") if permitted.empty?
    end

    # Asks the resource's own controller what it would permit, or nil when it
    # has nothing to say because permit_params was never declared.
    def resolve_permitted(attributes)
      param_key = @config.param_key.to_sym
      controller = @config.controller.new
      controller.params = ActionController::Parameters.new(param_key => attributes)
      permitted = controller.send(:permitted_params)
      scoped = permitted && permitted[param_key]
      scoped&.to_h&.symbolize_keys
    rescue StandardError
      nil
    end

    def without_sensitive_attributes(record)
      record.as_json.except(*ResourceRegistry.sensitive_attributes)
    end

    def resource_name
      @resource[:name]
    end

    def error(message, details: nil)
      result = { error: message }
      result[:details] = details if details
      result
    end
  end
end
