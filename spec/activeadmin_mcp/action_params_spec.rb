# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveadminMcp::ActionParams do
  def definition(kind: :member, params: {})
    double("definition", kind: kind, params: params)
  end

  def call(definition, arguments)
    described_class.new(definition).call(arguments)
  end

  it "extracts the record id for member actions" do
    result = call(definition(kind: :member), { "id" => "42" })

    expect(result[:record_id]).to eq("42")
    expect(result).not_to have_key(:error)
  end

  it "refuses a member action with no id" do
    expect(call(definition(kind: :member), {})).to eq(error: "id is required")
  end

  it "refuses a batch action with an empty ids list" do
    expect(call(definition(kind: :batch), { "ids" => [] })).to eq(error: "ids is required")
  end

  it "refuses a missing required param" do
    result = call(definition(kind: :collection, params: { reason: { type: :string, required: true } }), {})

    expect(result).to eq(error: "reason is required")
  end

  it "refuses a value outside a binding enum" do
    definition = definition(kind: :collection, params: { severity: { type: :string, enum: %w[low high] } })

    result = call(definition, { "severity" => "urgent" })

    expect(result[:error]).to eq("severity must be one of: low, high")
  end

  it "does not enforce suggestions" do
    definition = definition(kind: :collection, params: { category: { type: :string, suggestions: -> { %w[conduct] } } })

    result = call(definition, { "category" => "something else" })

    expect(result[:params]).to eq(category: "something else")
  end

  it "coerces declared types" do
    definition = definition(kind: :collection, params: {
      count: { type: :integer }, notify: { type: :boolean }
    })

    result = call(definition, { "count" => "3", "notify" => "true" })

    expect(result[:params]).to eq(count: 3, notify: true)
  end

  it "drops arguments that were never declared" do
    result = call(definition(kind: :collection, params: { reason: { type: :string } }),
                  { "reason" => "Late", "admin_override" => "true" })

    expect(result[:params]).to eq(reason: "Late")
  end
end
