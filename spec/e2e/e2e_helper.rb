# frozen_string_literal: true

require "rspec"

require_relative "../../lib/activeadmin_mcp/version"
require_relative "support/app_builder"
require_relative "support/app_server"
require_relative "support/mcp_client"

module E2E
  class << self
    attr_accessor :token
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.disable_monkey_patching!
  config.order = :defined

  config.before(:suite) do
    E2E::AppBuilder.build!
    E2E::AppServer.start!
    E2E.token = E2E::AppServer.mint_token!
  end

  config.after(:suite) do
    E2E::AppServer.stop!
  end
end
