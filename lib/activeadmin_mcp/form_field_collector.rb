# frozen_string_literal: true

module ActiveadminMcp
  # Records the field names declared by an ActiveAdmin `form do ... end` block.
  #
  # ActiveAdmin form blocks are arbitrary Formtastic DSL — `input`, `inputs`,
  # `actions`, helper calls, conditionals — so the block is run against this
  # stand-in form builder. Every `input :field` records `:field`; every other
  # message (including unknown helpers) is swallowed and returns self, so the
  # block executes without a real view context. Nested `has_many` associations
  # are intentionally not descended into: the updater only writes flat
  # attributes, and descending would record association fields as top-level.
  class FormFieldCollector
    attr_reader :fields

    def initialize
      @fields = []
    end

    def collect(&block)
      instance_exec(self, &block)
      @fields.uniq
    end

    def input(name, *_args, **_opts, &_block)
      @fields << name.to_sym if name.respond_to?(:to_sym)
      self
    end

    def inputs(*_args, **_opts, &block)
      instance_exec(self, &block) if block
      self
    end

    def has_many(*_args, **_opts)
      self
    end

    def method_missing(_name, *_args, **_opts, &block)
      instance_exec(self, &block) if block
      self
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end
end
