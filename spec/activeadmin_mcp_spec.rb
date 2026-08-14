# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveadminMcp do
  describe ".config" do
    it "returns a Configuration instance" do
      expect(described_class.config).to be_a(ActiveadminMcp::Configuration)
    end

    it "memoizes the same instance across calls" do
      expect(described_class.config).to be(described_class.config)
    end
  end

  describe ".configure" do
    it "yields the configuration object" do
      expect { |b| described_class.configure(&b) }
        .to yield_with_args(described_class.config)
    end

    it "persists changes made in the block" do
      described_class.configure { |c| c.mount_path = "/custom" }
      expect(described_class.config.mount_path).to eq("/custom")
    end
  end
end
