require "active_record"

# Spin up an in-memory SQLite database with just the tables the ApiToken
# model needs. Loaded only by specs that exercise the ActiveRecord model.
#
# Uses a shared-cache URI rather than a bare ":memory:" database. Both this
# file and spec/support/active_admin.rb call establish_connection, which
# replaces ActiveRecord::Base's connection pool wholesale; with two distinct
# anonymous ":memory:" databases, whichever support file loads last would
# silently strand the other's tables for the rest of the suite. A shared
# in-memory database lets both support files add their tables to the same
# underlying store regardless of load order.
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3", database: "file:activeadmin_mcp_test?mode=memory&cache=shared"
)

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :email
    t.timestamps
  end

  create_table :mcp_api_tokens, force: true do |t|
    t.references :user, null: false
    t.string :token_digest, null: false
    t.string :name
    t.datetime :last_used_at
    t.timestamps
  end

  add_index :mcp_api_tokens, :token_digest, unique: true
end

# The ApiToken belongs_to :user, class_name: ActiveadminMcp.config.user_class
# (defaults to "User"), so a matching constant must exist.
class User < ActiveRecord::Base
end

# The model lives under app/ and is normally loaded by Rails eager-loading;
# require it explicitly for the specs.
require_relative "../../app/models/activeadmin_mcp/api_token"
