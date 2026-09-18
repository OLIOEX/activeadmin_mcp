# frozen_string_literal: true

require "rspec"

require_relative "support/app_builder"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.disable_monkey_patching!
  config.order = :defined

  config.before(:suite) do
    E2E::AppBuilder.build!
  end
end
