require "spec_helper"
require "support/active_admin"

RSpec.describe ActiveadminMcp::RecordWriter do
  let(:admin) { AdminUser.create!(email: "admin@example.com") }
  let(:volunteers) { ActiveadminMcp::ResourceRegistry.find("Volunteer") }
  let(:notes) { ActiveadminMcp::ResourceRegistry.find("Note") }
  let(:sightings) { ActiveadminMcp::ResourceRegistry.find("Sighting") }

  after do
    Placement.delete_all
    Volunteer.delete_all
    Sighting.delete_all
    AdminUser.delete_all
  end

  def writer(resource)
    described_class.new(resource: resource, current_user: admin)
  end

  describe "creating a record" do
    it "creates the record and hands back its id and attributes" do
      result = writer(volunteers).create(attributes: { "name" => "Ann", "active" => false })

      expect(result[:error]).to be_nil
      expect(result[:record]).to include("name" => "Ann", "active" => false)
      expect(Volunteer.find(result[:id]).name).to eq("Ann")
    end

    it "reports which of the submitted attributes the admin form permitted" do
      result = writer(volunteers).create(attributes: { "name" => "Ann" })

      expect(result[:created]).to eq([:name])
    end

    it "runs ActiveAdmin's own callbacks, which only fire through the controller" do
      result = writer(volunteers).create(attributes: { "name" => "  Ann  " })

      expect(Volunteer.find(result[:id]).name).to eq("Ann")
    end

    it "drops an attribute the resource's permit_params does not accept" do
      result = writer(volunteers).create(attributes: { "name" => "Ann", "id" => 4321 })

      expect(result[:id]).not_to eq(4321)
      expect(Volunteer.exists?(4321)).to be(false)
    end

    # A rejected write re-renders the admin form, which the synthesized
    # request does not survive here; the dispatcher logs that and the writer
    # falls back to the record's own errors, which is the point of the example.
    it "returns the validation messages when the record is rejected" do
      allow_any_instance_of(ActiveadminMcp::ControllerDispatcher).to receive(:warn)

      result = writer(volunteers).create(attributes: { "name" => "" })

      expect(result[:error]).to match(/validation/i)
      expect(result[:details]).to include("Name can't be blank")
      expect(Volunteer.count).to eq(0)
    end

    it "refuses a resource registered without the create action" do
      result = writer(notes).create(attributes: { "body" => "Nope" })

      expect(result[:error]).to match(/not creatable/i)
      expect(Note.count).to eq(0)
    end

    it "refuses a resource that declares no permitted params" do
      result = writer(sightings).create(attributes: { "species" => "Kestrel" })

      expect(result[:error]).to match(/permit_params/)
      expect(Sighting.count).to eq(0)
    end

    it "refuses when none of the submitted attributes are permitted" do
      result = writer(volunteers).create(attributes: { "nonsense" => 1 })

      expect(result[:error]).to match(/no permitted attributes/i)
      expect(Volunteer.count).to eq(0)
    end

    it "omits sensitive attributes from the record it returns" do
      allow(ActiveadminMcp::ResourceRegistry).to receive(:sensitive_attributes).and_return(%w[name])

      result = writer(volunteers).create(attributes: { "name" => "Ann" })

      expect(result[:record]).not_to have_key("name")
    end
  end

  # ActiveAdmin instance_execs a block-form permit_params on the controller, so
  # resolving it needs the same controller context a dispatched call gets. A
  # bare controller instance cannot answer current_admin_user, and a resolution
  # that rescues the resulting NameError reports the resource as declaring no
  # permitted params at all.
  describe "a resource whose permit_params is a block reading controller state" do
    let(:placements) { ActiveadminMcp::ResourceRegistry.find("Placement") }

    it "creates the record, writing every attribute the block permitted" do
      result = writer(placements).create(attributes: { "name" => "Ann", "notes" => "Weekends" })

      expect(result[:error]).to be_nil
      expect(Placement.find(result[:id])).to have_attributes(name: "Ann", notes: "Weekends")
    end

    it "updates the record rather than refusing it for want of permitted params" do
      placement = Placement.create!(name: "Ann")

      result = writer(placements).update(id: placement.id, attributes: { "notes" => "Weekends" })

      expect(result[:error]).to be_nil
      expect(placement.reload.notes).to eq("Weekends")
    end
  end

  describe "updating a record" do
    let!(:volunteer) { Volunteer.create!(name: "Ann", active: true) }

    it "writes the permitted attributes and hands back the updated record" do
      result = writer(volunteers).update(id: volunteer.id, attributes: { "name" => "Bea" })

      expect(result[:error]).to be_nil
      expect(result[:updated]).to eq([:name])
      expect(result[:record]).to include("name" => "Bea")
      expect(volunteer.reload.name).to eq("Bea")
    end

    it "runs ActiveAdmin's own callbacks, which only fire through the controller" do
      writer(volunteers).update(id: volunteer.id, attributes: { "name" => "  Bea  " })

      expect(volunteer.reload.name).to eq("Bea")
    end

    it "drops an attribute the resource's permit_params does not accept" do
      writer(volunteers).update(id: volunteer.id, attributes: { "name" => "Bea", "created_at" => "1999-01-01" })

      expect(volunteer.reload.name).to eq("Bea")
      expect(volunteer.created_at.year).not_to eq(1999)
    end

    it "returns the validation messages and leaves the record alone when rejected" do
      allow_any_instance_of(ActiveadminMcp::ControllerDispatcher).to receive(:warn)

      result = writer(volunteers).update(id: volunteer.id, attributes: { "name" => "" })

      expect(result[:error]).to match(/validation/i)
      expect(result[:details]).to include("Name can't be blank")
      expect(volunteer.reload.name).to eq("Ann")
    end

    it "refuses a resource registered without the update action" do
      note = Note.create!(body: "Untouched")

      result = writer(notes).update(id: note.id, attributes: { "body" => "Tampered" })

      expect(result[:error]).to match(/not editable/i)
      expect(note.reload.body).to eq("Untouched")
    ensure
      Note.delete_all
    end

    it "refuses a resource that declares no permitted params" do
      sighting = Sighting.create!(species: "Kestrel")

      result = writer(sightings).update(id: sighting.id, attributes: { "species" => "Merlin" })

      expect(result[:error]).to match(/permit_params/)
      expect(sighting.reload.species).to eq("Kestrel")
    end

    it "refuses when none of the submitted attributes are permitted" do
      result = writer(volunteers).update(id: volunteer.id, attributes: { "nonsense" => 1 })

      expect(result[:error]).to match(/no permitted attributes/i)
      expect(volunteer.reload.name).to eq("Ann")
    end

    it "reports a record that does not exist rather than raising" do
      result = writer(volunteers).update(id: 999_999, attributes: { "name" => "Bea" })

      expect(result[:error]).to eq("Record not found: Volunteer#999999")
    end

    it "omits sensitive attributes from the record it returns" do
      allow(ActiveadminMcp::ResourceRegistry).to receive(:sensitive_attributes).and_return(%w[name])

      result = writer(volunteers).update(id: volunteer.id, attributes: { "name" => "Bea" })

      expect(result[:record]).not_to have_key("name")
    end
  end

  # Neutralising the namespace's authentication_method must not neutralise
  # authorization: a user the adapter refuses must not be able to write.
  describe "when the authorization adapter denies everything" do
    around do |example|
      namespace = ActiveAdmin.application.namespaces[:admin]
      previous = namespace.authorization_adapter
      namespace.authorization_adapter = DenyingAuthorizationAdapter
      example.run
      namespace.authorization_adapter = previous
    end

    it "refuses to create the record" do
      result = writer(volunteers).create(attributes: { "name" => "Ann" })

      expect(result[:error]).to match(/not authorized/i)
      expect(Volunteer.count).to eq(0)
    end

    it "refuses to update the record" do
      volunteer = Volunteer.create!(name: "Ann")

      result = writer(volunteers).update(id: volunteer.id, attributes: { "name" => "Bea" })

      expect(result[:error]).to match(/not authorized/i)
      expect(volunteer.reload.name).to eq("Ann")
    end
  end
end
