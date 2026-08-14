# frozen_string_literal: true

ActiveadminMcp.configure do |config|
  # Uncomment to enable API token authentication.
  # Requires running the auth migration first:
  #   rails generate activeadmin_mcp:install --auth
  #
  # config.authentication_method = :devise_token

  # The Devise model class used for authentication.
  # config.user_class = "User"

  # The controller method that returns the current user.
  # config.current_user_method = :current_admin_user

  # Parent menu for the MCP Tokens page in ActiveAdmin.
  # config.menu_parent = "Settings"

  # Path where the MCP server is mounted.
  # config.mount_path = "/mcp"

  # HTTP header used to read the Bearer token from.
  # Useful when a reverse proxy (e.g. AWS Verified Access) strips the
  # standard Authorization header.
  # config.auth_header_name = "Authorization"
end
