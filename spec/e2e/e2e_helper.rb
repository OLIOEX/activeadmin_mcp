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

  # Every example starts from the seeded database, so no example depends on
  # what another one left behind and the order is free to vary.
  config.order = :random
  Kernel.srand config.seed

  config.before(:suite) do
    E2E::AppBuilder.build!
    E2E::AppServer.start!
    E2E.token = E2E::AppServer.mint_token!
  end

  # Restoring the seeded rows is a transaction against the live database
  # rather than a Rails boot, so paying it per example costs milliseconds.
  config.before do
    E2E::AppBuilder.reset_database!
  end

  config.after(:suite) do
    E2E::AppServer.stop!
  end
end
