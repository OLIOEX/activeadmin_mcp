# frozen_string_literal: true

RSpec.describe "the generated host application" do
  let(:app_path) { E2E::AppBuilder::APP_PATH }

  it "has ActiveAdmin installed" do
    expect(File).to exist(File.join(app_path, "config/initializers/active_admin.rb"))
    expect(File).to exist(File.join(app_path, "app/admin/dashboard.rb"))
  end

  # The user_class substitution isn't asserted here: AppBuilder#configure_mcp
  # already raises BuildError at build time if it fails, so an assertion on
  # its result here could never fail independently of the builder. The
  # authentication_method line below is a genuine assertion on the
  # installer's own `gsub_file` behaviour, so it stays.
  it "has the gem's initializer, with devise_token authentication enabled" do
    initializer = File.read(File.join(app_path, "config/initializers/activeadmin_mcp.rb"))

    expect(initializer).to include("config.authentication_method = :devise_token")
  end

  it "has the token migration and the MCP Tokens admin page from the installer" do
    migrations = Dir[File.join(app_path, "db/migrate/*_create_mcp_api_tokens.rb")]

    expect(migrations).not_to be_empty
    expect(File).to exist(File.join(app_path, "app/admin/mcp_api_tokens.rb"))
  end

  it "has migrated the fixture tables" do
    schema = File.read(File.join(app_path, "db/schema.rb"))

    expect(schema).to include('create_table "posts"')
    expect(schema).to include('create_table "authors"')
    expect(schema).to include('create_table "mcp_api_tokens"')
  end
end
