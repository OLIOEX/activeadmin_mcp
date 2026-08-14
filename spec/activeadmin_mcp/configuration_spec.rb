# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveadminMcp::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "uses the expected default values" do
      expect(config.authentication_method).to be_nil
      expect(config.user_class).to eq("User")
      expect(config.current_user_method).to eq(:current_admin_user)
      expect(config.menu_parent).to be_nil
      expect(config.mount_path).to eq("/mcp")
      expect(config.mount_strategy).to eq(:prepend)
      expect(config.auth_header_name).to eq("Authorization")
    end
  end

  describe "#mount_strategy=" do
    it "accepts each supported strategy" do
      described_class::MOUNT_STRATEGIES.each do |strategy|
        config.mount_strategy = strategy
        expect(config.mount_strategy).to eq(strategy)
      end
    end

    it "raises ArgumentError for an unsupported strategy" do
      expect { config.mount_strategy = :sideways }
        .to raise_error(ArgumentError, /Invalid mount strategy: sideways/)
    end

    it "lists the valid strategies in the error message" do
      expect { config.mount_strategy = :nope }
        .to raise_error(ArgumentError, /prepend, append, none/)
    end
  end

  describe "#authentication_enabled?" do
    it "is true only when the method is :devise_token" do
      config.authentication_method = :devise_token
      expect(config.authentication_enabled?).to be(true)
    end

    it "is false when no authentication method is set" do
      config.authentication_method = nil
      expect(config.authentication_enabled?).to be(false)
    end

    it "is false for an unrecognised authentication method" do
      config.authentication_method = :something_else
      expect(config.authentication_enabled?).to be(false)
    end
  end
end
