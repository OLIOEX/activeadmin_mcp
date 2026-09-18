# frozen_string_literal: true

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
        # inputs down to the declared form: keys before calling the block, so a
        # param declared only under mcp: would be advertised, validated, sent —
        # and then silently dropped. Refuse it at declaration time instead.
        if form_keys && !form_keys.include?(name)
          @errors << "#{tool_name}: param #{name} is not in the batch action's form: hash, " \
                     "so ActiveAdmin would drop it before the action runs"
        end

        type = spec[:type]
        @errors << "#{tool_name}: param #{name} has unknown type #{type}" if type && !TYPES.include?(type.to_sym)
      end

      @errors << "#{tool_name}: permission must be callable" if permission && !permission.respond_to?(:call)
    end

    # The declared form: keys of a batch action, or nil when this is not a batch
    # action or the batch action declares no form at all (in which case
    # ActiveAdmin passes inputs through unsliced).
    def batch_form_keys
      return nil unless @kind == :batch
      return nil unless @action.respond_to?(:inputs)

      form = @action.inputs
      return nil unless form.is_a?(Hash)

      form.keys.map(&:to_sym)
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
