# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveadminMcp::Authorization do
  # Records the arguments it is constructed and called with, so the specs can
  # assert the wrapper wires ActiveAdmin's adapter contract correctly.
  let(:adapter_class) do
    Class.new do
      attr_reader :resource, :user

      def initialize(resource, user)
        @resource = resource
        @user = user
      end

      def authorized?(action, subject)
        [:authorized?, action, subject]
      end

      def scope_collection(collection, action)
        [:scope_collection, collection, action]
      end
    end
  end

  def config_for(adapter)
    namespace = double("namespace", authorization_adapter: adapter)
    double("config", namespace: namespace)
  end

  describe ".for" do
    it "instantiates the namespace's adapter class with the config and current user" do
      config = config_for(adapter_class)

      authorization = described_class.for(config, :current_user)

      expect(authorization.authorized?(:read, :subject)).to eq([:authorized?, :read, :subject])
    end

    it "constantizes a string adapter class name" do
      stub_const("StubAuthAdapter", adapter_class)
      config = config_for("StubAuthAdapter")

      authorization = described_class.for(config, :current_user)

      expect(authorization.authorized?(:read, :subject)).to eq([:authorized?, :read, :subject])
    end
  end

  describe "#scope_collection" do
    it "delegates to the adapter with the given action" do
      authorization = described_class.for(config_for(adapter_class), :user)

      expect(authorization.scope_collection(:collection, :update))
        .to eq([:scope_collection, :collection, :update])
    end

    it "defaults the action to :read" do
      authorization = described_class.for(config_for(adapter_class), :user)

      expect(authorization.scope_collection(:collection))
        .to eq([:scope_collection, :collection, :read])
    end
  end
end
