# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveadminMcp::ActionSchema do
  def definition(kind: :member, params: {})
    double("definition", kind: kind, params: params)
  end

  it "requires an id for member actions" do
    schema = described_class.new(definition(kind: :member)).to_h

    expect(schema[:properties]).to include(:id)
    expect(schema[:required]).to include("id")
  end

  it "requires an ids array for batch actions" do
    schema = described_class.new(definition(kind: :batch)).to_h

    expect(schema[:properties][:ids]).to include(type: "array")
    expect(schema[:required]).to include("ids")
  end

  it "adds no record key for collection actions" do
    schema = described_class.new(definition(kind: :collection)).to_h

    expect(schema[:properties]).to be_empty
    expect(schema[:required]).to be_empty
  end

  it "maps declared params, hints and required-ness" do
    schema = described_class.new(
      definition(kind: :collection, params: {
        reason: { type: :string, required: true, hint: "Shown to the volunteer" }
      })
    ).to_h

    expect(schema[:properties][:reason]).to eq(type: "string", description: "Shown to the volunteer")
    expect(schema[:required]).to eq(["reason"])
  end

  it "emits a static enum as a binding enum" do
    schema = described_class.new(
      definition(kind: :collection, params: { severity: { type: :string, enum: %w[low high] } })
    ).to_h

    expect(schema[:properties][:severity][:enum]).to eq(%w[low high])
  end

  it "emits a suggestions proc as advisory examples" do
    schema = described_class.new(
      definition(kind: :collection, params: { category: { type: :string, suggestions: -> { %w[lateness conduct] } } })
    ).to_h

    expect(schema[:properties][:category][:examples]).to eq(%w[lateness conduct])
    expect(schema[:properties][:category]).not_to have_key(:enum)
    expect(schema[:properties][:category][:description]).to include("lateness")
  end

  it "keeps the tool usable when a suggestions proc raises" do
    schema = described_class.new(
      definition(kind: :collection, params: { category: { type: :string, suggestions: -> { raise "boom" } } })
    ).to_h

    expect(schema[:properties][:category]).to eq(type: "string")
  end

  it "ensures no duplicate required entries even if a colliding param somehow reaches it" do
    # ActionDefinition rejects this upstream, but to_h should never emit duplicates regardless
    schema = described_class.new(
      definition(kind: :member, params: { id: { type: :integer, required: true } })
    ).to_h

    expect(schema[:required]).to eq(["id"])
    expect(schema[:required].uniq).to eq(schema[:required])
  end
end
