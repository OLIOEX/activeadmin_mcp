# frozen_string_literal: true

require "spec_helper"
require "support/active_record"

RSpec.describe ActiveAdminMcp::ApiToken do
  let(:user) { User.create!(email: "admin@example.com") }

  after do
    described_class.delete_all
    User.delete_all
  end

  describe ".digest" do
    it "returns the SHA256 hex digest of the raw token" do
      expect(described_class.digest("secret"))
        .to eq(Digest::SHA256.hexdigest("secret"))
    end
  end

  describe "token generation on create" do
    subject(:token) { described_class.create!(user: user) }

    it "assigns a raw token with the aamcp_ prefix" do
      expect(token.raw_token).to match(/\Aaamcp_[0-9a-f]{64}\z/)
    end

    it "stores only the digest of the raw token, never the raw value" do
      expect(token.token_digest).to eq(described_class.digest(token.raw_token))
      expect(token.reload.read_attribute(:token_digest)).not_to include(token.raw_token)
    end
  end

  describe "validations" do
    it "requires a user" do
      record = described_class.new
      expect(record).not_to be_valid
      expect(record.errors[:user_id]).to be_present
    end

    it "rejects a duplicate token digest" do
      # Force both records to generate the same raw token (and therefore the
      # same digest) so the uniqueness validation has something to reject.
      allow(SecureRandom).to receive(:hex).and_return("f" * 64)

      described_class.create!(user: user)
      duplicate = described_class.new(user: user)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token_digest]).to be_present
    end
  end

  describe ".find_by_raw_token" do
    it "finds the token matching the raw value" do
      token = described_class.create!(user: user)
      expect(described_class.find_by_raw_token(token.raw_token)).to eq(token)
    end

    it "returns nil for an unknown raw token" do
      described_class.create!(user: user)
      expect(described_class.find_by_raw_token("aamcp_unknown")).to be_nil
    end

    it "returns nil for a blank token without querying" do
      expect(described_class.find_by_raw_token("")).to be_nil
      expect(described_class.find_by_raw_token(nil)).to be_nil
    end
  end

  describe "#touch_last_used!" do
    subject(:token) { described_class.create!(user: user) }

    it "sets last_used_at when it has never been used" do
      expect { token.touch_last_used! }
        .to change { token.reload.last_used_at }.from(nil)
    end

    it "refreshes last_used_at when the throttle window has passed" do
      token.update_column(:last_used_at, 10.minutes.ago)

      expect { token.touch_last_used! }
        .to(change { token.reload.last_used_at })
    end

    it "does not update within the throttle window" do
      recent = 1.minute.ago
      token.update_column(:last_used_at, recent)

      expect { token.touch_last_used! }
        .not_to(change { token.reload.last_used_at })
    end
  end
end
