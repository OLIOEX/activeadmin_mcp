# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveAdminMcp::ResourceRegistry do
  # Builds a stand-in ActiveAdmin resource model class. `ransackable` and
  # `table` toggle whether it looks queryable/backed to the registry.
  def build_model(name:, columns: %w[id], ransackable: true, table: true)
    Class.new do
      define_singleton_method(:name) { name }
      define_singleton_method(:table_name) { name.tableize }
      define_singleton_method(:column_names) { columns }
      define_singleton_method(:table_exists?) { table }
      define_singleton_method(:ransack) { |*| } if ransackable
    end
  end

  def stub_active_admin(models)
    resources = models.map { |m| double("resource", resource_class: m) }
    namespace = double("namespace", resources: resources)
    application = double("application", namespaces: { admin: namespace })
    stub_const("ActiveAdmin", double("ActiveAdmin", application: application))
  end

  context "when ActiveAdmin is not defined" do
    it "returns an empty list of resources" do
      hide_const("ActiveAdmin")
      expect(described_class.all).to eq([])
    end

    it "finds nothing" do
      hide_const("ActiveAdmin")
      expect(described_class.find("User")).to be_nil
    end
  end

  describe ".all" do
    it "returns name, table and non-sensitive attributes for each resource" do
      stub_active_admin([
        build_model(name: "User", columns: %w[id email encrypted_password api_key]),
      ])

      expect(described_class.all).to eq([
        { name: "User", table: "users", attributes: %w[id email] },
      ])
    end

    it "filters out sensitive attributes" do
      stub_active_admin([
        build_model(name: "Account",
                    columns: %w[id password_digest reset_password_token secret name]),
      ])

      attributes = described_class.all.first[:attributes]
      expect(attributes).to eq(%w[id name])
    end

    it "skips resources whose backing table does not exist" do
      stub_active_admin([
        build_model(name: "User"),
        build_model(name: "Ghost", table: false),
      ])

      expect(described_class.all.map { |r| r[:name] }).to eq(["User"])
    end

    it "skips resources whose model is not Ransack-searchable" do
      stub_active_admin([
        build_model(name: "User"),
        build_model(name: "Legacy", ransackable: false),
      ])

      expect(described_class.all.map { |r| r[:name] }).to eq(["User"])
    end

    it "returns an empty list when there is no :admin namespace" do
      application = double("application", namespaces: {})
      stub_const("ActiveAdmin", double("ActiveAdmin", application: application))

      expect(described_class.all).to eq([])
    end
  end

  describe ".find" do
    it "returns the name and model class for a known resource" do
      user = build_model(name: "User")
      stub_active_admin([user])

      expect(described_class.find("User")).to eq(name: "User", model: user)
    end

    it "returns nil for an unknown resource" do
      stub_active_admin([build_model(name: "User")])

      expect(described_class.find("Nope")).to be_nil
    end

    it "does not find resources whose table does not exist" do
      stub_active_admin([build_model(name: "Ghost", table: false)])

      expect(described_class.find("Ghost")).to be_nil
    end
  end
end
