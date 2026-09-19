module ActiveadminMcp
  # Validates and coerces a tool call's arguments against its ActionDefinition
  # before anything reaches the controller.
  #
  # Undeclared arguments are dropped rather than passed through: the declaration
  # is the contract, and forwarding unknown keys into a controller action would
  # let a client reach parameters the application never opted in to.
  class ActionParams
    class CoercionError < StandardError; end

    def initialize(definition)
      @definition = definition
    end

    def call(arguments)
      arguments ||= {}
      result = { params: {} }

      case @definition.kind
      when :member
        id = arguments["id"]
        return { error: "id is required" } if id.nil? || id.to_s.empty?

        result[:record_id] = id.to_s
      when :batch
        ids = Array(arguments["ids"]).reject { |id| id.to_s.empty? }
        return { error: "ids is required" } if ids.empty?

        result[:record_ids] = ids.map(&:to_s)
      end

      @definition.params.each do |name, spec|
        value = arguments[name.to_s]

        if value.nil? || value.to_s.empty?
          return { error: "#{name} is required" } if spec[:required]

          next
        end

        begin
          coerced_value = coerce(value, spec[:type])
        rescue CoercionError
          return { error: "#{name} must be a #{spec[:type]}" }
        end

        if spec[:enum].is_a?(Array) && !spec[:enum].include?(coerced_value)
          return { error: "#{name} must be one of: #{spec[:enum].join(', ')}" }
        end

        result[:params][name] = coerced_value
      end

      result
    end

    private

    def coerce(value, type)
      case type&.to_sym
      when :integer
        Integer(value)
      when :number
        Float(value)
      when :boolean
        case value
        when true, "true", "1", 1 then true
        when false, "false", "0", 0 then false
        else raise CoercionError, "invalid boolean value"
        end
      else
        value
      end
    rescue ArgumentError, TypeError => e
      raise CoercionError, e.message
    end
  end
end
