require "spec_helper"
require "support/active_admin"

RSpec.describe ActiveadminMcp::FormDescription do
  let(:admin) { AdminUser.create!(email: "admin@example.com") }

  after { AdminUser.delete_all }

  def describe_form(resource_name, action: "new")
    resource = ActiveadminMcp::ResourceRegistry.find(resource_name)
    described_class.new(resource: resource, current_user: admin).call(action: action)
  end

  def attribute(result, name)
    result[:attributes].find { |attribute| attribute[:name] == name }
  end

  describe "a resource that declares its own form block" do
    it "says the description was read from the resource's declared form" do
      expect(describe_form("Shift")[:source]).to eq("form")
    end

    it "lists the fields the form declares, in the order the form declares them" do
      expect(describe_form("Shift")[:attributes].map { |attribute| attribute[:name] }).to eq(
        %w[name location starts_at]
      )
    end

    it "carries the hint, label and input type the form declared for each field" do
      result = describe_form("Shift")

      expect(attribute(result, "name")[:hint]).to eq("How the shift appears on the rota")
      expect(attribute(result, "starts_at")[:label]).to eq("Starts")
      expect(attribute(result, "starts_at")[:as]).to eq("datetime_select")
    end

    it "carries the allowed values of a select declared with a literal collection" do
      expect(attribute(describe_form("Shift"), "location")[:collection]).to eq(%w[kitchen warehouse])
    end

    it "annotates each field with the column type the model stores it in" do
      result = describe_form("Shift")

      expect(attribute(result, "name")[:type]).to eq("string")
      expect(attribute(result, "starts_at")[:type]).to eq("datetime")
    end

    # Flattening them would advertise an association's fields as attributes of
    # the record itself, which is not what a client could write.
    it "reports a has_many group as nested rather than as fields of the record itself" do
      result = describe_form("Shift")

      expect(result[:attributes].map { |attribute| attribute[:name] }).not_to include("sightings")
      expect(result[:nested]).to eq([{ name: "sightings", attributes: [{ name: "species" }] }])
    end

    it "marks a field required when the model validates its presence" do
      result = describe_form("Shift")

      expect(attribute(result, "name")[:required]).to be(true)
      expect(attribute(result, "location")).not_to have_key(:required)
    end
  end

  describe "a resource that declares no form block" do
    it "says the description was derived from the resource's permitted params" do
      expect(describe_form("Volunteer")[:source]).to eq("permit_params")
    end

    it "lists the fields the resource's permit_params accepts, and no others" do
      expect(describe_form("Volunteer")[:attributes].map { |attribute| attribute[:name] }).to eq(
        %w[name active]
      )
    end

    it "annotates the derived fields with column types and presence validators just the same" do
      result = describe_form("Volunteer")

      expect(attribute(result, "active")[:type]).to eq("boolean")
      expect(attribute(result, "name")[:required]).to be(true)
    end

    # ActiveAdmin's own default form is a bare `f.inputs`, which Formtastic
    # expands only at render time. A resource writing that out by hand has a
    # form block with nothing in it to read, which is not the same as a form
    # that permits nothing.
    it "falls back to permitted params when the form block declares no inputs of its own" do
      result = describe_form("Roster")

      expect(result[:source]).to eq("permit_params")
      expect(result[:attributes].map { |attribute| attribute[:name] }).to eq(%w[name notes])
    end

    it "resolves a block-form permit_params, which ActiveAdmin evaluates on the controller" do
      result = describe_form("Placement")

      expect(result[:error]).to be_nil
      expect(result[:attributes].map { |attribute| attribute[:name] }).to eq(%w[name notes])
    end

    it "refuses a resource that declares no permit_params either, because nothing may be written" do
      expect(describe_form("Sighting")[:error]).to match(/permit_params/)
    end
  end

  describe "choosing which form to describe" do
    it "describes the new form by default" do
      expect(describe_form("Shift")[:action]).to eq("new")
    end

    it "describes the edit form when asked for it" do
      expect(describe_form("Shift", action: "edit")[:action]).to eq("edit")
    end

    it "refuses an action that is neither new nor edit" do
      expect(describe_form("Shift", action: "destroy")[:error]).to match(/new.*edit/)
    end
  end

  # The form is the interface to a write, so describing one the user could
  # never submit tells them nothing they can act on and discloses the shape of
  # a resource they cannot write.
  describe "authorization" do
    it "refuses the new form of a resource registered without the create action" do
      expect(describe_form("Note")[:error]).to eq("Resource is not creatable: Note")
    end

    it "refuses the edit form of a resource registered without the update action" do
      expect(describe_form("Note", action: "edit")[:error]).to eq("Resource is not editable: Note")
    end

    context "when the authorization adapter denies everything" do
      around do |example|
        namespace = ActiveAdmin.application.namespaces[:admin]
        previous = namespace.authorization_adapter
        namespace.authorization_adapter = DenyingAuthorizationAdapter
        example.run
        namespace.authorization_adapter = previous
      end

      it "refuses to describe the new form" do
        expect(describe_form("Shift")[:error]).to match(/not authorized to create/i)
      end

      it "refuses to describe the edit form" do
        expect(describe_form("Shift", action: "edit")[:error]).to match(/not authorized to update/i)
      end
    end
  end
end
