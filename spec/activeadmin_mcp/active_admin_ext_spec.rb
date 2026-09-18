# frozen_string_literal: true

require "spec_helper"
require "support/active_admin"

RSpec.describe ActiveadminMcp::ActiveAdminExt do
  let(:config) { McpSpec::ActiveAdminHarness.volunteer_config }

  def member_action(name)
    config.member_actions.find { |action| action.name.to_sym == name }
  end

  before { described_class.apply! }

  it "reads the mcp option off a member action" do
    expect(member_action(:create_warning).mcp_options).to eq(
      description: "Record a warning against a volunteer",
      params: { reason: { type: :string, required: true } }
    )
  end

  it "returns nil for an action that did not opt in" do
    expect(member_action(:undocumented).mcp_options).to be_nil
  end

  it "reads the mcp option off a batch action" do
    suspend = config.batch_actions.find { |action| action.sym == :suspend }

    expect(suspend.mcp_options).to eq(description: "Suspend the selected volunteers")
  end

  # Guard spec. If a future ActiveAdmin starts validating or stripping unknown
  # option keys, this fails loudly here rather than silently in a user's admin.
  it "confirms ActiveAdmin carries unknown action option keys through untouched" do
    options = member_action(:create_warning).instance_variable_get(:@options)

    expect(options).to include(method: :post)
    expect(options).to have_key(:mcp)
  end

  # If ActiveAdmin ever renames these classes, ActionCatalog's respond_to?
  # guard makes every opted-in tool vanish from tools/list with nothing said
  # anywhere. A warning is the only signal an operator would get.
  describe "when ActiveAdmin does not provide the expected classes" do
    it "warns and returns false rather than failing silently" do
      allow(described_class).to receive(:applicable?).and_return(false)
      messages = []
      allow(described_class).to receive(:warn) { |message| messages << message }

      expect(described_class.apply!).to be(false)
      expect(messages.join).to include("no opted-in actions will be exposed")
    end
  end
end
