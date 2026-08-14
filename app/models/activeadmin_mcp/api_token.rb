# frozen_string_literal: true

require "digest"
require "securerandom"

module ActiveadminMcp
  class ApiToken < ActiveRecord::Base
    self.table_name = "mcp_api_tokens"

    belongs_to :user, class_name: ActiveadminMcp.config.user_class

    attr_accessor :raw_token

    validates :token_digest, presence: true, uniqueness: true
    validates :user_id, presence: true

    before_validation :generate_token, on: :create

    LAST_USED_THROTTLE = 5.minutes

    def self.find_by_raw_token(raw_token)
      return nil if raw_token.blank?

      find_by(token_digest: digest(raw_token))
    end

    def self.digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    def touch_last_used!
      return if last_used_at.present? && last_used_at > LAST_USED_THROTTLE.ago

      update_column(:last_used_at, Time.current)
    end

    private

    def generate_token
      self.raw_token = "aamcp_#{SecureRandom.hex(32)}"
      self.token_digest = self.class.digest(raw_token)
    end
  end
end
