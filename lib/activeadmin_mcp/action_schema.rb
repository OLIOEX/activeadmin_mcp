# frozen_string_literal: true

module ActiveadminMcp
  # Builds the JSON Schema an MCP client sees for one opted-in action.
  #
  # The binding/advisory split matters: a static `enum:` is enforced before we
  # dispatch, while `suggestions:` is only ever a hint to the model. A
  # suggestions proc runs application code on every tools/list call, so it is
  # wrapped — a raising proc costs its suggestions, never the whole listing.
  class ActionSchema
    def initialize(definition)
      @definition = definition
    end

    def to_h
      properties = record_properties
      required = properties.keys.map(&:to_s)

      @definition.params.each do |name, spec|
        properties[name] = property_for(spec)
        required << name.to_s if spec[:required]
      end

      { type: "object", properties: properties, required: required.uniq }
    end

    private

    def record_properties
      case @definition.kind
      when :member
        { id: { type: "string", description: "Primary key of the record to act on" } }
      when :batch
        { ids: { type: "array", items: { type: "string" },
                 description: "Primary keys of the records to act on" } }
      else
        {}
      end
    end

    def property_for(spec)
      property = { type: (spec[:type] || :string).to_s }

      descriptions = []
      descriptions << spec[:hint] if spec[:hint]

      property[:enum] = spec[:enum] if spec[:enum].is_a?(Array)

      suggestions = resolve_suggestions(spec[:suggestions])
      if suggestions&.any?
        property[:examples] = suggestions
        descriptions << "Suggested values: #{suggestions.join(', ')}"
      end

      property[:description] = descriptions.join(". ") unless descriptions.empty?
      property
    end

    # Advisory only. A proc that blows up must not take the tool listing with it.
    def resolve_suggestions(suggestions)
      return nil unless suggestions.respond_to?(:call)

      Array(suggestions.call)
    rescue StandardError
      nil
    end
  end
end
