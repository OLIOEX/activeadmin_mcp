require "spec_helper"
require "support/active_admin"

# Authorizes every action at the class level but scopes collections down to
# active records, the shape a real CanCanCan or Pundit adapter has: gate 1
# passes for a batch action (its subject is the resource class), and only
# scope_collection knows which records are actually reachable.
class ActiveOnlyAuthorizationAdapter < ActiveAdmin::AuthorizationAdapter
  def authorized?(_action, _subject = nil)
    true
  end

  def scope_collection(collection, _action = :read)
    collection.where(active: true)
  end
end

RSpec.describe ActiveadminMcp::ActionRunner do
  let(:config) { McpSpec::ActiveAdminHarness.volunteer_config }
  let(:admin) { AdminUser.create!(email: "admin@example.com") }
  let!(:volunteer) { Volunteer.create!(name: "Ann") }

  after do
    Volunteer.delete_all
    AdminUser.delete_all
  end

  # Memoised deliberately: ActionCatalog.all rebuilds definitions on every
  # call, so re-deriving one per example would stub a different object than the
  # one under test.
  def find_definition(name, kind)
    ActiveadminMcp::ActionCatalog.all.find do |d|
      d.action_name == name && d.kind == kind
    end
  end

  let(:definition) { find_definition(:create_warning, :member) }
  let(:batch_definition) { find_definition(:suspend, :batch) }

  def run(definition, arguments, current_user: admin)
    described_class.new(definition: definition, current_user: current_user).call(arguments)
  end

  it "runs an authorized member action" do
    result = run(definition, { "id" => volunteer.id.to_s, "reason" => "Late again" })

    expect(result[:status]).to eq(302)
    expect(volunteer.reload.name).to eq("Late again")
  end

  it "refuses before dispatching when ActiveAdmin authorization says no" do
    deny = double("authorization")
    allow(deny).to receive(:authorized?).and_return(false)
    allow(ActiveadminMcp::Authorization).to receive(:for).and_return(deny)

    result = run(definition, { "id" => volunteer.id.to_s, "reason" => "Late again" })

    expect(result[:error]).to include("Not authorized")
    expect(volunteer.reload.name).to eq("Ann")
  end

  it "refuses when the record does not exist" do
    result = run(definition, { "id" => "999999", "reason" => "Late" })

    expect(result[:error]).to include("not found")
  end

  it "surfaces a validation error from ActionParams without dispatching" do
    result = run(definition, { "id" => volunteer.id.to_s })

    expect(result).to eq(error: "reason is required")
    expect(volunteer.reload.name).to eq("Ann")
  end

  it "refuses when the permission proc returns false" do
    allow(definition).to receive(:permission).and_return(->(_record) { false })

    result = run(definition, { "id" => volunteer.id.to_s, "reason" => "Late" })

    expect(result[:error]).to include("Not permitted")
    expect(volunteer.reload.name).to eq("Ann")
  end

  it "uses a string returned by the permission proc as the refusal reason" do
    allow(definition).to receive(:permission).and_return(->(_record) { "Volunteer is suspended" })

    result = run(definition, { "id" => volunteer.id.to_s, "reason" => "Late" })

    expect(result[:error]).to eq("Volunteer is suspended")
  end

  it "keeps a raising permission proc's message out of the refusal" do
    allow(definition).to receive(:permission).and_return(
      ->(_record) { raise "SQLite3::SQLException: no such table: nope_secret" }
    )
    messages = []
    allow_any_instance_of(described_class).to receive(:warn) { |_, message| messages << message }

    result = run(definition, { "id" => volunteer.id.to_s, "reason" => "Late" })

    expect(result[:error]).to eq("Permission check failed for volunteer_create_warning")
    expect(messages.join).to include("nope_secret")
  end

  it "runs the permission proc in controller context" do
    seen = nil
    allow(definition).to receive(:permission).and_return(proc { |record| seen = [record, current_active_admin_user]; true })

    run(definition, { "id" => volunteer.id.to_s, "reason" => "Late" })

    expect(seen).to eq([volunteer, admin])
  end

  it "runs a batch action over the selected records" do
    other = Volunteer.create!(name: "Bea")
    unselected = Volunteer.create!(name: "Cee")

    result = run(batch_definition,
                 { "ids" => [volunteer.id.to_s, other.id.to_s], "reason" => "No shows" })

    expect(result[:status]).to eq(302)
    expect(result[:flash]["notice"]).to eq("2 suspended: No shows")
    expect(volunteer.reload.name).to eq("Suspended: No shows")
    expect(other.reload.name).to eq("Suspended: No shows")
    expect(unselected.reload.name).to eq("Cee")
  end

  describe "collection-kind permission proc" do
    let(:collection_definition) { find_definition(:export, :collection) }

    it "dispatches when a zero-arity permission proc returns true" do
      allow(collection_definition).to receive(:permission).and_return(-> { true })

      result = run(collection_definition, {})

      expect(result[:status]).to eq(302)
      expect(result[:flash]["notice"]).to eq("Exported")
    end

    it "refuses generically when a zero-arity permission proc returns false" do
      allow(collection_definition).to receive(:permission).and_return(-> { false })

      result = run(collection_definition, {})

      expect(result[:error]).to include("Not permitted")
      expect(result[:flash]).to be_nil
    end

    it "uses a string returned by the permission proc as the refusal reason" do
      allow(collection_definition).to receive(:permission).and_return(-> { "Exports are disabled" })

      result = run(collection_definition, {})

      expect(result[:error]).to eq("Exports are disabled")
    end
  end

  # Gate 1 can only authorize the resource class for a batch action, so without
  # an explicit id-scope check a client could name records the adapter excludes
  # and ActiveAdmin would happily mutate them.
  describe "batch ids outside the authorized scope" do
    around do |example|
      namespace = ActiveAdmin.application.namespaces[:admin]
      previous = namespace.authorization_adapter
      namespace.authorization_adapter = ActiveOnlyAuthorizationAdapter
      example.run
      namespace.authorization_adapter = previous
    end

    it "refuses the whole call and mutates nothing when one id is out of scope" do
      hidden = Volunteer.create!(name: "Hidden", active: false)

      result = run(batch_definition,
                   { "ids" => [volunteer.id.to_s, hidden.id.to_s], "reason" => "No shows" })

      expect(result[:error]).to include("Not authorized", hidden.id.to_s)
      expect(volunteer.reload.name).to eq("Ann")
      expect(hidden.reload.name).to eq("Hidden")
    end

    it "refuses ids that do not exist at all" do
      result = run(batch_definition, { "ids" => ["999999"], "reason" => "No shows" })

      expect(result[:error]).to include("999999")
    end

    it "still runs when every id is inside the scope" do
      other = Volunteer.create!(name: "Bea")

      result = run(batch_definition,
                   { "ids" => [volunteer.id.to_s, other.id.to_s], "reason" => "No shows" })

      expect(result[:status]).to eq(302)
      expect(volunteer.reload.name).to eq("Suspended: No shows")
    end
  end
end
