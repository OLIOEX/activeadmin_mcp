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

  # Actions declared in a shared concern cannot carry an mcp: key of their own,
  # so the resource annotates them by name instead.
  describe "the mcp_action DSL" do
    let(:shift_config) do
      ActiveAdmin.application.namespaces[:admin].resources.find { |r| r.resource_class == Shift }
    end

    it "records an annotation against the resource for an action declared elsewhere" do
      expect(shift_config.mcp_annotations).to include(
        hash_including(
          action_name: :flag,
          kind: :batch,
          options: hash_including(description: "Flag the selected shifts")
        )
      )
    end

    it "records one annotation per declaration, so an action can become more than one tool" do
      member = shift_config.mcp_annotations.select { |a| a[:kind] == :member }

      expect(member.map { |a| a[:options][:tool_name] }).to eq(%w[shift_flag shift_unflag])
    end

    it "carries the tool_name and http_verb a declaration chose" do
      unflag = shift_config.mcp_annotations.find { |a| a[:options][:tool_name] == "shift_unflag" }

      expect(unflag[:options][:http_verb]).to eq(:delete)
    end

    it "leaves a resource that annotates nothing with no annotations" do
      expect(McpSpec::ActiveAdminHarness.volunteer_config.mcp_annotations).to eq([])
    end
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
