# frozen_string_literal: true

module ActiveadminMcp
  # Runs one opted-in ActiveAdmin action for an MCP client.
  #
  # Two gates gate every call, in this order, both before anything is
  # dispatched:
  #
  #   1. ActiveAdmin's own authorization adapter - the same check `query` and
  #      `update` make today.
  #   2. The action's optional `permission:` proc.
  #
  # The proc can only ever narrow access. A record the MCP user cannot touch
  # stays untouchable whether or not a proc is declared, and the controller's
  # own before_action chain runs again during dispatch regardless.
  class ActionRunner
    def initialize(definition:, current_user:)
      @definition = definition
      @current_user = current_user
    end

    def call(arguments)
      parsed = ActionParams.new(@definition).call(arguments)
      return parsed if parsed[:error]

      record = find_record(parsed[:record_id])
      return { error: "Record not found: #{@definition.resource_name}##{parsed[:record_id]}" } if record_missing?(record, parsed)

      subject = record || @definition.config.resource_class
      return { error: "Not authorized to run #{@definition.tool_name}" } unless authorized?(subject)

      dispatcher = ControllerDispatcher.new(config: @definition.config, current_user: @current_user)

      refusal = permission_refusal(dispatcher, record, parsed)
      return { error: refusal } if refusal

      dispatcher.call(
        action: dispatch_action,
        path: path_for(record, parsed),
        verb: @definition.http_verb,
        params: dispatch_params(parsed),
        path_params: path_params(parsed)
      )
    end

    private

    def find_record(id)
      return nil unless id

      @definition.config.resource_class.find_by(id: id)
    end

    def record_missing?(record, parsed)
      parsed.key?(:record_id) && record.nil?
    end

    def authorized?(subject)
      Authorization.for(@definition.config, @current_user)
                   .authorized?(@definition.action_name, subject)
    end

    # Evaluated the way ActiveAdmin evaluates batch action `:if` procs, so
    # current_admin_user, can? and the usual admin helpers are in scope.
    # Returns a refusal message, or nil when the proc allows the call.
    def permission_refusal(dispatcher, record, parsed)
      permission = @definition.permission
      return nil unless permission

      controller = dispatcher.send(:build_controller)
      outcome = ::MethodOrProcHelper.render_in_context(controller, permission, *permission_args(permission, record, parsed))

      return outcome if outcome.is_a?(String)
      return nil if outcome

      "Not permitted to run #{@definition.tool_name}"
    rescue StandardError => e
      "Permission check failed for #{@definition.tool_name}: #{e.message}"
    end

    # render_in_context instance_execs the proc AND passes args along, so a
    # zero-arity lambda would raise ArgumentError if we always handed it a
    # record. Match what the proc actually accepts.
    def permission_args(permission, record, parsed)
      return [] if permission.respond_to?(:arity) && permission.arity.zero?

      case @definition.kind
      when :member then [record]
      when :batch then [parsed[:record_ids]]
      else []
      end
    end

    # Batch actions enter through ActiveAdmin's own batch_action controller
    # method, so its slicing of inputs to the declared form: keys applies
    # exactly as it does in the admin UI.
    def dispatch_action
      @definition.kind == :batch ? :batch_action : @definition.action_name
    end

    def dispatch_params(parsed)
      return parsed[:params] unless @definition.kind == :batch

      {
        batch_action: @definition.action_name.to_s,
        collection_selection: parsed[:record_ids],
        batch_action_inputs: JSON.generate(parsed[:params]),
      }
    end

    def path_params(parsed)
      parsed[:record_id] ? { id: parsed[:record_id] } : {}
    end

    def path_for(record, parsed)
      config = @definition.config

      case @definition.kind
      when :member then config.route_member_action_path(@definition.action_name, record)
      # RouteBuilder#batch_action_path calls `.permit!` on the params it is
      # given, which a plain Hash (its own default argument) does not
      # respond to. Pass ActionController::Parameters explicitly to avoid
      # tripping over ActiveAdmin's own default.
      when :batch then config.route_batch_action_path(ActionController::Parameters.new)
      else config.route_collection_path
      end
    end
  end
end
