# frozen_string_literal: true

require "spec_helper"
require "support/active_admin"

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
end
