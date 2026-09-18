# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveadminMcp::ActionDefinition do
  def build_config(name: "Volunteer")
    double("config", resource_class: double("model", name: name))
  end

  def member_action(name, mcp:, verb: :post)
    double("controller_action", name: name, http_verb: verb, mcp_options: mcp)
  end

  def batch_action(name, mcp:, form: nil)
    double("batch_action", sym: name, mcp_options: mcp, inputs: form)
  end

  it "returns nil when the action did not opt in" do
    action = member_action(:undocumented, mcp: nil)

    expect(described_class.build(config: build_config, action: action, kind: :member)).to be_nil
  end

  it "exposes the declared metadata and a namespaced tool name" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { reason: { type: :string, required: true } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).to have_attributes(
      kind: :member,
      action_name: :create_warning,
      resource_name: "Volunteer",
      tool_name: "volunteer_create_warning",
      description: "Record a warning",
      http_verb: :post
    )
    expect(definition.params).to eq(reason: { type: :string, required: true })
    expect(definition).to be_valid
  end

  it "inherits batch action param types from the ActiveAdmin form hash" do
    action = batch_action(:suspend, mcp: { description: "Suspend" }, form: { reason: :text, notify: :checkbox })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition.params).to eq(
      reason: { type: :string },
      notify: { type: :boolean }
    )
  end

  it "lets the mcp declaration layer hints over an inherited batch form type" do
    action = batch_action(:suspend, form: { reason: :text }, mcp: {
      description: "Suspend",
      params: { reason: { hint: "Shown to the volunteer" } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition.params).to eq(reason: { type: :string, hint: "Shown to the volunteer" })
  end

  it "is invalid when a param declares an unrecognised type" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { reason: { type: :wibble } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).not_to be_valid
    expect(definition.errors.first).to include("wibble")
  end

  it "is invalid without a description" do
    action = member_action(:create_warning, mcp: { params: {} })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).not_to be_valid
    expect(definition.errors.first).to include("description")
  end
end
