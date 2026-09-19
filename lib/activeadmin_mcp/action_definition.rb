module ActiveadminMcp
  # One ActiveAdmin action that an application has opted in to MCP, normalised
  # so the rest of the engine does not care whether it came from a
  # member_action, a collection_action or a batch_action.
  #
  # Batch actions are the special case: ActiveAdmin already knows their input
  # names and widget types via `form:`, so those become param types and the
  # `mcp:` declaration only layers descriptions and hints on top.
  class ActionDefinition
    KINDS = %i[member collection batch].freeze

    # MCP tool names are referenced by clients as identifiers, so keep them to
    # what every client can quote without escaping.
    TOOL_NAME = /\A[a-z0-9][a-z0-9_-]*\z/

    # JSON Schema scalar types an application may declare.
    TYPES = %i[string integer number boolean array object].freeze

    # ActiveAdmin batch action form widgets -> JSON Schema types.
    FORM_TYPES = {
      text: :string,
      string: :string,
      select: :string,
      datepicker: :string,
      number: :number,
      checkbox: :boolean,
    }.freeze

    attr_reader :config, :action, :kind, :errors

    def self.build(config:, action:, kind:, current_user: nil)
      options = action.mcp_options
      return nil unless options.is_a?(Hash)

      new(config: config, action: action, kind: kind, options: options, current_user: current_user)
    end

    def initialize(config:, action:, kind:, options:, current_user: nil)
      @config = config
      @action = action
      @kind = kind
      @options = options
      @current_user = current_user
      @errors = []
      validate!
    end

    def action_name
      (@kind == :batch ? @action.sym : @action.name).to_sym
    end

    def resource_name
      @config.resource_class.name
    end

    # A declaration may choose its own name: an action shared by a concern can
    # need a different one on each resource, and an action exposed once per
    # verb needs a distinct name per tool.
    def tool_name
      declared = @options[:tool_name]
      return declared.to_s if declared

      derived_tool_name
    end

    # Squeezed down to the characters a tool name may carry, because an action
    # name is not always tame: ActiveAdmin derives a batch action's symbol from
    # a String title and can leave punctuation in it. A resource may still
    # choose its own name with tool_name:, which is validated rather than
    # squeezed, since a name someone typed deliberately should not be silently
    # rewritten.
    def derived_tool_name
      "#{resource_name.underscore.tr('/', '_')}_#{action_name}"
        .downcase
        .gsub(/[^a-z0-9_-]+/, "_")
        .squeeze("_")
        .delete_suffix("_")
    end

    def description
      @options[:description]
    end

    def permission
      @options[:permission]
    end

    # ActiveAdmin's own `:if` proc on a batch action, which decides whether the
    # admin UI offers it at all. Returned rather than evaluated: like a
    # `permission:` proc it belongs in controller context, which only the
    # caller can build.
    def display_if
      return nil unless @kind == :batch
      return nil unless @action.respond_to?(:display_if_block)

      @action.display_if_block
    end

    # ActiveAdmin always posts a batch action, whatever a declaration says.
    # Otherwise a declaration may pick among the verbs the action answers to —
    # `method: [:post, :delete]` is one action with two meanings, and without
    # this only the first would ever be reachable.
    def http_verb
      return :post if @kind == :batch

      declared = @options[:http_verb]&.to_sym
      return declared if declared

      action_verbs.first || :get
    end

    def action_verbs
      Array(@action.http_verb).compact.map(&:to_sym)
    end

    # Declared params, with batch actions inheriting their types from the
    # ActiveAdmin `form:` hash underneath anything the declaration says.
    def params
      @params ||= inherited_params.merge(declared_params) do |_key, inherited, declared|
        inherited.merge(declared)
      end
    end

    def valid?
      @errors.empty?
    end

    private

    def declared_params
      raw = @options[:params]
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) { |(name, spec), acc| acc[name.to_sym] = spec }
    end

    def inherited_params
      return {} unless @kind == :batch

      resolved_form.each_with_object({}) do |(name, widget), acc|
        acc[name.to_sym] = { type: form_type(widget) }
      end
    end

    # A form: entry is usually a widget name, but ActiveAdmin also accepts an
    # array of options, which it renders as a select. There is no type to read
    # off that, and its values are not treated as a binding enum: they were
    # resolved once, at listing time, and a declaration wanting to offer them
    # should say so with suggestions:, which is advisory by design.
    def form_type(widget)
      return :string unless widget.respond_to?(:to_sym)

      FORM_TYPES.fetch(widget.to_sym, :string)
    end

    # ActiveAdmin lets `form:` be a proc and evaluates it in controller context
    # at render time, which is the only way a concern shared across resources
    # can vary its options. Evaluated here the same way, so a proc form still
    # contributes its param types.
    #
    # Deliberately lazy: this runs application code, so it must not happen
    # while the catalog is merely being built, before the caller has checked
    # the user is authorized for the action at all. Same posture as
    # `suggestions:`.
    def resolved_form
      return @resolved_form if defined?(@resolved_form)

      @resolved_form = resolve_form || {}
    end

    def resolve_form
      return nil unless @action.respond_to?(:inputs)

      form = @action.inputs
      return form if form.is_a?(Hash)
      return nil unless form.is_a?(Proc)

      evaluate_form(form)
    end

    def evaluate_form(form)
      controller = ControllerDispatcher.new(config: @config, current_user: @current_user)
                                       .controller_with_mcp_user
      evaluated = ::MethodOrProcHelper.render_in_context(controller, form)
      evaluated.is_a?(Hash) ? evaluated : nil
    rescue StandardError => e
      # The tool keeps whatever the declaration said; it just inherits nothing.
      warn("[activeadmin_mcp] evaluating the #{tool_name} form: proc raised #{e.class}: #{e.message}")
      nil
    end

    def validate!
      @errors << "#{tool_name}: mcp declaration needs a description" if description.to_s.strip.empty?
      @errors << "#{tool_name}: unknown kind #{@kind}" unless KINDS.include?(@kind)

      reserved = reserved_param_name
      form_keys = batch_form_keys
      # Declared params only. Inherited ones come from ActiveAdmin's own form:
      # hash and are always well formed, and reading them would mean evaluating
      # a proc form here — the one place it must not happen.
      declared_params.each do |name, spec|
        unless spec.is_a?(Hash)
          @errors << "#{tool_name}: param #{name} must be a Hash"
          next
        end

        @errors << "#{tool_name}: param #{name} is reserved" if name == reserved

        # ActiveAdmin's own batch_action controller method slices the submitted
        # inputs down to the keys of the batch action's `inputs` (its `form:`
        # hash) before calling the block: `inputs.slice(*valid_keys)`. When
        # there is no `form:` at all, `inputs` is nil, so `valid_keys` is nil,
        # and `slice(*nil)` is `slice()` — which drops EVERY input, not none.
        # So a form-less batch action permits nothing, and any declared param
        # is a declaration error. A Proc form is evaluated by ActiveAdmin in
        # controller context (MethodOrProcHelper.render_in_context), so we
        # cannot know its keys here and skip the check rather than guess.
        case form_keys
        when :unknown_proc_form
          nil
        when :no_form
          @errors << "#{tool_name}: param #{name} cannot be declared because this batch action " \
                     "has no form: hash, so ActiveAdmin drops every input before the action runs"
        when nil
          nil # not a batch action, or no `inputs` method at all: no rule applies
        else
          unless form_keys.include?(name)
            @errors << "#{tool_name}: param #{name} is not among the batch action's declared " \
                       "form: keys, so ActiveAdmin would drop it before the action runs"
          end
        end

        type = spec[:type]
        @errors << "#{tool_name}: param #{name} has unknown type #{type}" if type && !TYPES.include?(type.to_sym)
      end

      @errors << "#{tool_name}: permission must be callable" if permission && !permission.respond_to?(:call)

      validate_tool_name!
      validate_http_verb!
    end

    def validate_tool_name!
      return if tool_name.match?(TOOL_NAME)

      @errors << "#{tool_name}: tool_name must match #{TOOL_NAME.source}"
    end

    # Dispatching a verb the action never declared would reach nothing, or
    # worse, the wrong branch of the action's own body.
    def validate_http_verb!
      declared = @options[:http_verb]&.to_sym
      return if declared.nil? || @kind == :batch

      verbs = action_verbs
      return if verbs.empty? || verbs.include?(declared)

      @errors << "#{tool_name}: http_verb #{declared} is not one the action answers to (#{verbs.join(', ')})"
    end

    # The permitted param keys for a batch action's `inputs` (its `form:`
    # hash), distinguishing three outcomes the caller must treat differently:
    #
    # * not a batch action, or the action has no `inputs` method at all ->
    #   nil, the batch form: rule does not apply.
    # * `inputs` is a Hash -> its keys, the permitted set ActiveAdmin will
    #   slice submitted params down to.
    # * `inputs` is nil (no `form:` declared) -> :no_form. ActiveAdmin still
    #   slices, against a nil key list, which yields an EMPTY permitted set
    #   (`hash.slice(*nil)` is `hash.slice()` == `{}`), so every declared
    #   param here is a declaration error.
    # * `inputs` is a Proc -> :unknown_proc_form. ActiveAdmin evaluates it in
    #   controller context via `render_in_context`, so we cannot know its
    #   keys at declaration time. We skip the check rather than guess.
    def batch_form_keys
      return nil unless @kind == :batch
      return nil unless @action.respond_to?(:inputs)

      form = @action.inputs
      return form.keys.map(&:to_sym) if form.is_a?(Hash)
      return :unknown_proc_form if form.is_a?(Proc)

      :no_form
    end

    def reserved_param_name
      case @kind
      when :member
        :id
      when :batch
        :ids
      else
        nil
      end
    end
  end
end
