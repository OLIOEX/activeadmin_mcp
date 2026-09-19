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

  # How the engine adds its route: :prepend (default), :append, or :none.
  # Set it to :none when you want to mount the engine yourself, for instance
  # inside a constraints block your admin routes already sit in.
  # config.mount_strategy = :prepend

  # HTTP header used to read the Bearer token from.
  # Useful when a reverse proxy (e.g. AWS Verified Access) strips the
  # standard Authorization header.
  # config.auth_header_name = "Authorization"
end
