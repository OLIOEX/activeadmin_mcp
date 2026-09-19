require "spec_helper"

RSpec.describe ActiveadminMcp::ActionCatalog do
  def action(name, mcp:, verb: :post)
    double("controller_action", name: name, http_verb: verb, mcp_options: mcp)
  end

  def batch(name, mcp:, form: nil)
    double("batch_action", sym: name, mcp_options: mcp, inputs: form)
  end

  def config(member: [], collection: [], batch_actions: [], batch_enabled: true, name: "Volunteer")
    double(
      "config",
      resource_class: double("model", name: name),
      member_actions: member,
      collection_actions: collection,
      batch_actions: batch_actions,
      batch_actions_enabled?: batch_enabled
    )
  end

  def stub_resources(*configs)
    entries = configs.map { |c| { name: c.resource_class.name, model: c.resource_class, config: c } }
    allow(ActiveadminMcp::ResourceRegistry).to receive(:resources).and_return(entries)
  end

  it "collects opted-in actions and ignores the rest" do
    stub_resources(config(member: [
      action(:create_warning, mcp: { description: "Record a warning" }),
      action(:undocumented, mcp: nil)
    ]))

    expect(described_class.all.map(&:tool_name)).to eq(["volunteer_create_warning"])
  end

  # Verified against ActiveAdmin 3.5.2: batch_actions_enabled? can be false
  # while batch actions are still registered. Exposing them would surface an
  # action the admin UI itself hides.
  it "skips batch actions when the namespace has them disabled" do
    stub_resources(config(batch_actions: [batch(:suspend, mcp: { description: "Suspend" })],
                          batch_enabled: false))

    expect(described_class.all).to be_empty
  end

  it "includes batch actions when the namespace has them enabled" do
    stub_resources(config(batch_actions: [batch(:suspend, mcp: { description: "Suspend" })]))

    expect(described_class.all.map(&:tool_name)).to eq(["volunteer_suspend"])
  end

  it "refuses a tool name that collides with a built-in tool" do
    stub_resources(config(collection: [action(:resources, mcp: { description: "Clash" })], name: "List"))

    expect(described_class.all).to be_empty
  end

  it "drops invalid declarations rather than exposing them" do
    stub_resources(config(member: [action(:create_warning, mcp: { params: {} })]))

    expect(described_class.all).to be_empty
  end

  it "finds a definition by tool name" do
    stub_resources(config(member: [action(:create_warning, mcp: { description: "Record a warning" })]))

    expect(described_class.find("volunteer_create_warning").action_name).to eq(:create_warning)
    expect(described_class.find("nope")).to be_nil
  end
end
