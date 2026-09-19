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

  it "coerces a value before checking enum (Finding 1: string '1' should match integer enum [1, 2, 3])" do
    definition = definition(kind: :collection, params: { count: { type: :integer, enum: [1, 2, 3] } })

    result = call(definition, { "count" => "1" })

    expect(result[:params]).to eq(count: 1)
  end

  it "refuses a coerced value outside enum" do
    definition = definition(kind: :collection, params: { count: { type: :integer, enum: [1, 2, 3] } })

    result = call(definition, { "count" => "9" })

    expect(result[:error]).to eq("count must be one of: 1, 2, 3")
  end

  it "refuses a value that cannot be coerced to integer (Finding 2: 'abc' for :integer)" do
    definition = definition(kind: :collection, params: { count: { type: :integer } })

    result = call(definition, { "count" => "abc" })

    expect(result[:error]).to eq("count must be a integer")
  end

  it "coerces the string 'false' to boolean false" do
    definition = definition(kind: :collection, params: { active: { type: :boolean } })

    result = call(definition, { "active" => "false" })

    expect(result[:params]).to eq(active: false)
  end

  it "refuses a value that cannot be coerced to boolean" do
    definition = definition(kind: :collection, params: { active: { type: :boolean } })

    result = call(definition, { "active" => "wibble" })

    expect(result[:error]).to eq("active must be a boolean")
  end

  it "accepts a required boolean param sent as false (not treated as missing)" do
    definition = definition(kind: :collection, params: { active: { type: :boolean, required: true } })

    result = call(definition, { "active" => false })

    expect(result[:params]).to eq(active: false)
    expect(result).not_to have_key(:error)
  end
end
