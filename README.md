# ActiveAdminMcp

> **Status: Experimental / WIP**

Minimal MCP (Model Context Protocol) server for Rails apps with ActiveAdmin.

## Tested Clients

- **Claude Code** (Anthropic) - HTTP transport

## Installation

Add to your Gemfile:

```ruby
gem "active_admin_mcp"
```

Then run:

```bash
bundle install
rails generate active_admin_mcp:install
```

The MCP server is automatically mounted at `/mcp`.

## Route Mounting

By default, the engine prepends its route to the top of your application's route table. This works well for most setups, but can cause issues when your routes use constraints (e.g. hostname-based routing for admin servers), as the prepended mount sits outside any constraint blocks.

The `mount_strategy` option controls how the engine registers its route:

| Strategy | Behaviour |
|----------|-----------|
| `:prepend` | **(default)** Mounts at the top of the route table via `routes.prepend` |
| `:append` | Mounts at the bottom of the route table via `routes.append` |
| `:none` | Skips automatic mounting — you mount the engine yourself |

### Manual mounting

If your admin routes are wrapped in constraints, set `mount_strategy` to `:none` and mount the engine inside your route file:

```ruby
# config/initializers/active_admin_mcp.rb
ActiveAdminMcp.configure do |config|
  config.mount_path = "/admin/mcp"
  config.mount_strategy = :none
end
```

```ruby
# config/routes.rb (or a drawn route file)
constraints AdminConstraint.new do
  ActiveAdmin.routes(self)
  mount ActiveAdminMcp::Engine => ActiveAdminMcp.config.mount_path
end
```

## Authentication

To protect your MCP endpoint with API token authentication:

```bash
rails generate active_admin_mcp:install --auth devise_token
rails db:migrate
```

This will:
- Create the `mcp_api_tokens` table
- Add an "MCP Tokens" page to your ActiveAdmin panel (`app/admin/` by default)
- Enable token authentication in the initializer

#### Generator Options

| Option | Default | Description |
|--------|---------|-------------|
| `--auth` | none | Authentication method to use (e.g., `devise_token`) |
| `--admin-path` | `app/admin` | Directory for the ActiveAdmin page file |

Example with a custom admin path:

```bash
rails generate active_admin_mcp:install --auth devise_token --admin-path app/admin/mcp
```

### Managing Tokens

1. Log in to your ActiveAdmin panel (`/admin`)
2. Navigate to **Settings > MCP Tokens**
3. Create a new token and copy it — it will only be shown once

### Connecting with a Token

```bash
claude mcp add --transport http \
  --header 'Authorization: Bearer YOUR_TOKEN' \
  my-app http://localhost:3000/mcp/
```

Or in `.mcp.json`:

```json
{
  "mcpServers": {
    "my-app": {
      "type": "http",
      "url": "http://localhost:3000/mcp/",
      "headers": {
        "Authorization": "Bearer YOUR_TOKEN"
      }
    }
  }
}
```

### Configuration

The initializer at `config/initializers/active_admin_mcp.rb`:

```ruby
ActiveAdminMcp.configure do |config|
  config.authentication_method = :devise_token
  config.user_class = "User"  # your Devise model class
end
```

| Option | Default | Description |
|--------|---------|-------------|
| `authentication_method` | `nil` | Set to `:devise_token` to enable Bearer token auth |
| `user_class` | `"User"` | The Devise model class name |
| `current_user_method` | `:current_admin_user` | Controller method that returns the current user |
| `menu_parent` | `nil` | Parent menu for the MCP Tokens page (e.g., `"Settings"`) |
| `mount_path` | `"/mcp"` | Path where the MCP server is mounted |
| `mount_strategy` | `:prepend` | Route mounting strategy: `:prepend`, `:append`, or `:none` |
| `auth_header_name` | `"Authorization"` | HTTP header to read the Bearer token from |

### Custom Auth Header

If your application sits behind a reverse proxy that strips the standard `Authorization` header (e.g. AWS Verified Access), you can configure a custom header name:

```ruby
ActiveAdminMcp.configure do |config|
  config.authentication_method = :devise_token
  config.auth_header_name = "X-MCP-Authorization"
end
```

Then pass the token via the custom header in `.mcp.json`:

```json
{
  "mcpServers": {
    "my-app": {
      "type": "http",
      "url": "https://admin.example.com/admin/mcp/",
      "headers": {
        "X-MCP-Authorization": "Bearer YOUR_TOKEN"
      }
    }
  }
}
```

## Usage with Claude Code

```bash
claude mcp add --transport http my-app http://localhost:3000/mcp/
```

Or add to your `.mcp.json`:

```json
{
  "mcpServers": {
    "my-app": {
      "type": "http",
      "url": "http://localhost:3000/mcp/"
    }
  }
}
```

## Available Tools

| Tool | Description |
|------|-------------|
| `list_resources` | List all ActiveAdmin resources with their attributes |
| `query` | Query a resource using Ransack syntax |
| `update` | Update an existing record, respecting ActiveAdmin's form and authorization rules |

### Query Examples

```
Query users where email contains "example.com"
→ query(resource: "User", q: { email_cont: "example.com" })

Find active posts from last week
→ query(resource: "Post", q: { status_eq: "active", created_at_gt: "2025-12-01" })
```

### Updating Records

```
Update a user's name
→ update(resource: "User", id: 42, attributes: { name: "New name" })
```

The `update` tool applies the same rules as the ActiveAdmin UI:

- **Editable resources only** — resources registered without the `update` action
  (e.g. `actions :index, :show`) are refused.
- **Authorization** — the update is run through the resource namespace's
  authorization adapter for the authenticated MCP user (CanCanCan, Pundit, etc.),
  so a user can only update what they're allowed to in admin.
- **Permitted fields only** — attributes are filtered through the resource's
  `permit_params`, so only fields the admin form accepts are written; anything
  else is silently dropped.

## Original Project

We forked this project from [https://github.com/betacraft/active_admin_mcp] originally and have continued to extend from there.

## License

MIT
