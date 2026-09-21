module ActiveadminMcp
  # Reads an ActiveAdmin `form do ... end` block and reports what each input
  # tells a client about how to fill the field in.
  #
  # ActiveAdmin form blocks are arbitrary Formtastic DSL — `input`, `inputs`,
  # `actions`, application helpers, conditionals — so the block is run against
  # this stand-in form builder rather than parsed. Every `input :field` is
  # recorded; every other message (including helpers that would need a view
  # context we do not have) is swallowed and returns self, so the block runs to
  # completion outside a request.
  #
  # Only the options that describe the field to whoever is filling it in are
  # kept. Presentation options (`input_html:`, `wrapper_html:` and the rest)
  # say nothing an MCP client can act on and are dropped.
  class FormFieldCollector
    DESCRIBED_TEXT_OPTIONS = %i[label hint].freeze

    def initialize
      @inputs = []
    end

    def collect(&block)
      instance_exec(self, &block)
      @inputs
    end

    def input(name, *_args, **options, &_block)
      return self unless name.respond_to?(:to_sym)
      return self if declared?(name.to_sym)

      @inputs << describe(name.to_sym, options)
      self
    end

    # `inputs for: :author` scopes its fields to an association, the same way
    # has_many does; only an unscoped `inputs` groups fields of the record
    # itself. Descending into a scoped one would advertise the associated
    # record's fields as attributes of the record being written.
    def inputs(*_args, **options, &block)
      association = options[:for]
      return nest(association, &block) if association

      instance_exec(self, &block) if block
      self
    end

    # Recorded as a group of its own rather than descended into, so a client
    # can tell an association's fields from the record's own. Flattening them
    # would advertise `body` as an attribute of the parent record.
    def has_many(name, *_args, **_opts, &block)
      nest(name, &block)
    end

    def method_missing(_name, *_args, **_opts, &block)
      instance_exec(self, &block) if block
      self
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end

    private

    # `for:` may name the association or give it as [name, object]; only the
    # name says anything to a client.
    def nest(association, &block)
      name = association.is_a?(Array) ? association.first : association
      return self unless name.respond_to?(:to_sym)
      return self if declared?(name.to_sym)

      @inputs << { name: name.to_sym, nested: block ? self.class.new.collect(&block) : [] }
      self
    end

    def declared?(name)
      @inputs.any? { |input| input[:name] == name }
    end

    def describe(name, options)
      described = { name: name }

      described[:as] = options[:as].to_sym if scalar_name?(options[:as])
      described[:required] = options[:required] if [true, false].include?(options[:required])

      DESCRIBED_TEXT_OPTIONS.each do |key|
        described[key] = options[key].to_s if scalar_name?(options[key])
      end

      values = allowed_values(options[:collection])
      described[:collection] = values if values

      described
    end

    # A helper the collector swallowed comes back as the collector itself, so
    # anything that is not plain text is not something to report as a label.
    def scalar_name?(value)
      value.is_a?(String) || value.is_a?(Symbol)
    end

    # Only a literal array is resolved. A relation would mean firing a query
    # from what is meant to be a description, and can be arbitrarily large; a
    # proc usually needs the view context this collector does not have. Either
    # is omitted rather than evaluated.
    def allowed_values(collection)
      return nil unless collection.is_a?(Array)

      values = collection.map { |entry| entry.is_a?(Array) ? entry.last : entry }
      return nil unless values.all? { |value| scalar_name?(value) || value.is_a?(Numeric) }

      values
    end
  end
end
