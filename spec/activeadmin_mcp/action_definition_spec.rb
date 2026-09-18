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

  it "properly handles acronyms and namespaced resource names in tool names" do
    action_acronym = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: {}
    })
    action_namespaced = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: {}
    })

    definition_acronym = described_class.build(
      config: build_config(name: "APIKey"),
      action: action_acronym,
      kind: :member
    )
    definition_namespaced = described_class.build(
      config: build_config(name: "Admin::Volunteer"),
      action: action_namespaced,
      kind: :member
    )

    expect(definition_acronym.tool_name).to eq("api_key_create_warning")
    expect(definition_namespaced.tool_name).to eq("admin_volunteer_create_warning")
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

  it "is invalid when a member action declares a param named id" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { id: { type: :integer } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).not_to be_valid
    expect(definition.errors).to include(match(/param id is reserved/))
  end

  it "is invalid when a batch action declares a param named ids" do
    action = batch_action(:suspend, mcp: {
      description: "Suspend",
      params: { ids: { type: :array } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).not_to be_valid
    expect(definition.errors).to include(match(/param ids is reserved/))
  end

  # ActiveAdmin's batch_action controller method slices submitted inputs down
  # to the declared form: keys, so a param declared only under mcp: would be
  # advertised, required, validated, encoded — and then dropped before the
  # block ever saw it.
  it "is invalid when a batch param is missing from the ActiveAdmin form hash" do
    action = batch_action(:suspend, form: { reason: :text }, mcp: {
      description: "Suspend",
      params: { reason: { hint: "Why" }, notify_manager: { type: :boolean, required: true } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).not_to be_valid
    expect(definition.errors).to include(match(/param notify_manager is not in the batch action's form/))
  end

  it "is valid when every batch param is in the form hash" do
    action = batch_action(:suspend, form: { reason: :text, notify: :checkbox }, mcp: {
      description: "Suspend",
      params: { reason: { hint: "Why" } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).to be_valid
  end

  # No form: hash means ActiveAdmin slices nothing, so there is nothing to drop.
  it "allows declared params on a batch action with no form hash" do
    action = batch_action(:suspend, form: nil, mcp: {
      description: "Suspend",
      params: { reason: { type: :string } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :batch)

    expect(definition).to be_valid
  end

  it "does not apply the batch form rule to member actions" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { reason: { type: :string } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).to be_valid
  end

  it "is valid when a collection action declares a param named id" do
    action = double("controller_action", name: :process, http_verb: :post, mcp_options: {
      description: "Process something",
      params: { id: { type: :string } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :collection)

    expect(definition).to be_valid
  end

  it "is valid when a member action declares a param named ids" do
    action = member_action(:create_warning, mcp: {
      description: "Record a warning",
      params: { ids: { type: :array } }
    })

    definition = described_class.build(config: build_config, action: action, kind: :member)

    expect(definition).to be_valid
  end
end
