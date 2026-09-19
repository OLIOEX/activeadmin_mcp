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

    def self.build(config:, action:, kind:)
      options = action.mcp_options
      return nil unless options.is_a?(Hash)

      new(config: config, action: action, kind: kind, options: options)
    end

    def initialize(config:, action:, kind:, options:)
      @config = config
      @action = action
      @kind = kind
      @options = options
      @errors = []
      validate!
    end

    def action_name
      (@kind == :batch ? @action.sym : @action.name).to_sym
    end

    def resource_name
      @config.resource_class.name
    end

    def tool_name
      "#{resource_name.underscore.tr('/', '_')}_#{action_name}"
    end

    def description
      @options[:description]
    end

    def permission
      @options[:permission]
    end

    def http_verb
      return :post if @kind == :batch

      Array(@action.http_verb).first&.to_sym || :get
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
      return {} unless @action.respond_to?(:inputs)

      form = @action.inputs
      return {} unless form.is_a?(Hash)

      form.each_with_object({}) do |(name, widget), acc|
        acc[name.to_sym] = { type: FORM_TYPES.fetch(widget.to_sym, :string) }
      end
    end

    def validate!
      @errors << "#{tool_name}: mcp declaration needs a description" if description.to_s.strip.empty?
      @errors << "#{tool_name}: unknown kind #{@kind}" unless KINDS.include?(@kind)

      reserved = reserved_param_name
      form_keys = batch_form_keys
      params.each do |name, spec|
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
