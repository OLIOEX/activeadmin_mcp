# frozen_string_literal: true

require "active_record"

# Spin up an in-memory SQLite database with just the tables the ApiToken
# model needs. Loaded only by specs that exercise the ActiveRecord model.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

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

# The ApiToken belongs_to :user, class_name: ActiveAdminMcp.config.user_class
# (defaults to "User"), so a matching constant must exist.
class User < ActiveRecord::Base
end

# The model lives under app/ and is normally loaded by Rails eager-loading;
# require it explicitly for the specs.
require_relative "../../app/models/active_admin_mcp/api_token"
