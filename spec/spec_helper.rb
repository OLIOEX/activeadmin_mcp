require "rails"
require "active_record"
require "action_controller"
require "activeadmin_mcp"
require "sqlite3"

# spec/support/active_admin.rb and spec/support/active_record.rb each define
# their own tables against a shared in-memory SQLite database (see the
# comments in those files for why it must be shared rather than two separate
# ":memory:" databases). A SQLite shared-cache database is destroyed the
# moment its last connection closes, and ActiveRecord::Base.establish_connection
# closes whatever pool it replaces — so without a connection held open
# independently of ActiveRecord for the life of the process, the database
# (and every table in it) would vanish the first time either support file's
# pool got replaced. This constant just keeps one connection open so that
# never happens.
KEEPALIVE_SQLITE_CONNECTION = SQLite3::Database.new("file:activeadmin_mcp_test?mode=memory&cache=shared")

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Reset the memoized global configuration between examples so that
  # config-touching specs don't leak state into one another.
  config.after do
    ActiveadminMcp.instance_variable_set(:@config, nil)
  end
end
