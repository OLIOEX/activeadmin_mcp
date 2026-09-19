require "spec_helper"
require "support/active_admin"

# The whole annotation path against real ActiveAdmin objects: a concern in the
# shape applications actually use, declaring its actions in self.included so
# none of them can carry an mcp: key, and the resource annotating them by name.
RSpec.describe "an ActiveAdmin action annotated with mcp_action" do
  let(:admin) { AdminUser.create!(email: "admin@example.com") }

  before { ActiveadminMcp::ActiveAdminExt.apply! }

  after { AdminUser.delete_all }

  def definitions
    ActiveadminMcp::ActionCatalog.all(current_user: admin)
  end

  def definition(tool_name)
    definitions.find { |candidate| candidate.tool_name == tool_name }
  end

  it "exposes an action a shared concern declared, which could carry no mcp: key of its own" do
    expect(definitions.map(&:tool_name)).to include("shift_bulk_flag", "shift_flag", "shift_unflag")
  end

  it "leaves actions the resource did not annotate unexposed, so the opt-in still holds" do
    expect(definitions.map(&:tool_name)).not_to include("volunteer_undocumented")
  end

  it "exposes one tool per declaration when a member action answers to more than one verb" do
    expect(definition("shift_flag").http_verb).to eq(:post)
    expect(definition("shift_unflag").http_verb).to eq(:delete)
  end

  it "tells a member and a batch action of the same name apart by the kind the declaration named" do
    expect(definition("shift_bulk_flag").kind).to eq(:batch)
    expect(definition("shift_flag").kind).to eq(:member)
  end

  # ActiveAdmin allows form: to be a proc and evaluates it in controller
  # context; a concern shared across resources needs one, because its options
  # depend on the resource. Reading it statically is not possible, so the gem
  # evaluates it the same way ActiveAdmin does.
  describe "a batch action whose form: is a proc rather than a hash" do
    it "inherits the param types the proc declares" do
      params = definition("shift_bulk_flag").params

      expect(params[:reason]).to include(type: :string)
      expect(params[:notify]).to eq(type: :boolean)
    end

    it "keeps what the declaration says about a param it also inherits" do
      expect(definition("shift_bulk_flag").params[:reason]).to include(required: true)
    end
  end
end
