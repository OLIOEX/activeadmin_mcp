module ActiveadminMcp
  # Describes the form behind a resource's create or update action richly
  # enough that an MCP client stops guessing field types and allowed values
  # from column names.
  #
  # The description is read from the resource's own `form do ... end` block
  # when it declares one. When it does not, ActiveAdmin renders a bare
  # `f.inputs` that Formtastic only expands at render time — there is nothing
  # to introspect — so the description is derived from the resource's
  # `permit_params` instead, which is what `create` and `update` enforce
  # anyway. The payload says which of the two it is.
  #
  # Either way each field is annotated from the model: the column type it is
  # stored in, and whether the model validates its presence.
  class FormDescription
    WRITE_ACTIONS = { "new" => :create, "edit" => :update }.freeze
    REFUSALS = { create: "is not creatable", update: "is not editable" }.freeze

    def initialize(resource:, current_user:)
      @resource = resource
      @current_user = current_user
      @config = resource[:config]
    end

    def call(action: "new")
      write_action = WRITE_ACTIONS[action.to_s]
      return error(%(Unknown form action: #{action} (expected "new" or "edit"))) unless write_action

      refusal = write_refusal(write_action)
      return refusal if refusal

      declared = declared_inputs
      return describe(action, "form", declared) if declared

      permitted = permitted_inputs
      return permit_params_refusal unless permitted

      describe(action, "permit_params", permitted)
    end

    private

    def describe(action, source, inputs)
      fields, groups = inputs.partition { |input| !input.key?(:nested) }

      {
        resource: @resource[:name],
        action: action.to_s,
        source: source,
        attributes: fields.map { |field| attribute(field) },
        nested: groups.map { |group| nested_group(group) },
      }
    end

    # An association's own fields are reported as the form declared them and
    # are not annotated from a model: they belong to the associated record, not
    # to the one being written.
    def nested_group(group)
      { name: group[:name].to_s, attributes: group[:nested].map { |field| stringify(field) } }
    end

    def attribute(field)
      described = stringify(field)
      described[:type] = column_type(field[:name]) if column_type(field[:name])
      described[:required] = true if !described.key?(:required) && presence_validated?(field[:name])
      described
    end

    def stringify(field)
      field.each_with_object({}) do |(key, value), described|
        described[key] = value.is_a?(Symbol) ? value.to_s : value
      end
    end

    def column_type(name)
      @resource[:model].columns_hash[name.to_s]&.type&.to_s
    end

    def presence_validated?(name)
      @resource[:model].validators_on(name).any? do |validator|
        validator.is_a?(ActiveModel::Validations::PresenceValidator)
      end
    rescue StandardError
      false
    end

    def declared_inputs
      block = form_block
      return nil unless block

      FormFieldCollector.new.collect(&block)
    rescue StandardError => e
      # A form block that will not run outside a request describes nothing, but
      # the resource's permitted params still can.
      warn("[activeadmin_mcp] reading the #{@resource[:name]} form raised #{e.class}: #{e.message}")
      nil
    end

    def form_block
      return nil unless @config.respond_to?(:page_presenters)

      @config.page_presenters[:form]&.block
    end

    # ActiveAdmin stores no list of the params it permits, only a method that
    # filters against them, so the permitted names are recovered by offering it
    # every column the model has and seeing which survive. A resource that
    # never declared permit_params has no such method to answer, and is
    # reported as unwritable rather than described.
    def permitted_inputs
      names = permitted_names
      return nil unless names

      names.map { |name| { name: name } }
    end

    def permitted_names
      param_key = @config.param_key.to_sym
      controller = @config.controller.new
      controller.params = ActionController::Parameters.new(
        param_key => @resource[:model].column_names.index_with { nil }
      )
      permitted = controller.send(:permitted_params)
      scoped = permitted && permitted[param_key]
      scoped&.keys&.map(&:to_sym)
    rescue StandardError
      nil
    end

    def write_refusal(write_action)
      unless @config.defined_actions.include?(write_action)
        return error("Resource #{REFUSALS[write_action]}: #{@resource[:name]}")
      end

      return if Authorization.for(@config, @current_user)
                             .authorized?(write_action, @config.resource_class)

      error("Not authorized to #{write_action} #{@resource[:name]}")
    end

    def permit_params_refusal
      error("Resource declares no permit_params, so nothing may be written: #{@resource[:name]}")
    end

    def error(message)
      { error: message }
    end
  end
end
