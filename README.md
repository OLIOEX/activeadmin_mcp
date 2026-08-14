# ActiveadminMcp

> **Status: Experimental / work in progress**

`activeadmin_mcp` turns the resources you have already registered with
[ActiveAdmin](https://activeadmin.info/) into a
[Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server, so AI
assistants such as Claude Code can list, query, and update your admin data —
while respecting the exact same forms, permitted parameters, and authorization
rules as your ActiveAdmin UI.

The server is a Rails engine mounted inside your application (by default at
`/mcp`) and speaks MCP over HTTP (JSON-RPC 2.0, protocol revision
`2025-06-18`).

## How it works

- **Nothing new to describe.** The engine reads your existing ActiveAdmin
  registrations, so the resources, attributes, and permitted fields it exposes
  are the ones you have already configured.
- **Queries use Ransack.** The `query` tool passes its arguments straight to
  [Ransack](https://activerecord-hackery.github.io/ransack/), the same search
  library ActiveAdmin uses for filtering.
- **Writes go through ActiveAdmin.** The `update` tool only writes fields
  allowed by the resource's `permit_params`, refuses resources that don't
  register the `update` action, and runs every change through your
  authorization adapter (CanCanCan, Pundit, etc.) as the authenticated MCP
  user.
- **Authentication is optional but built in.** Enable Bearer-token auth and the
  installer adds an "MCP Tokens" management page to your ActiveAdmin panel.

## Requirements

- Ruby >= 3.0
- Rails >= 6.1
- ActiveAdmin >= 2.0

## Installation

Add the gem to your Gemfile:

```ruby
gem "activeadmin_mcp"
```

Install it and run the generator:

```bash
bundle install
rails generate activeadmin_mcp:install
```

The MCP server is mounted at `/mcp` automatically. That's all you need for a
read/query setup without authentication.

## Available tools

| Tool | Description |
|------|-------------|
| `list_resources` | List every ActiveAdmin resource along with its attributes. |
| `query` | Query a resource using Ransack syntax (`limit` defaults to 25, capped at 100). |
| `update` | Update an existing record, honouring ActiveAdmin's permitted params and authorization. |

### Query examples

```
Query users whose email contains "example.com"
→ query(resource: "User", q: { email_cont: "example.com" })

Find active posts created since the start of the month
→ query(resource: "Post", q: { status_eq: "active", created_at_gt: "2026-08-01" })
```

### Updating records

```
Update a user's name
→ update(resource: "User", id: 42, attributes: { name: "New name" })
```

The `update` tool applies the same rules as the ActiveAdmin UI:

- **Editable resources only** — resources registered without the `update`
  action (e.g. `actions :index, :show`) are refused.
- **Authorization** — the change runs through the resource namespace's
  authorization adapter for the authenticated MCP user, so it can only update
  what that user is allowed to update in admin.
- **Permitted fields only** — attributes are filtered through the resource's
  `permit_params`; fields the admin form doesn't accept are silently dropped.

## Connecting a client

`activeadmin_mcp` has been tested with **Claude Code** (Anthropic) over the
HTTP transport.

```bash
claude mcp add --transport http my-app http://localhost:3000/mcp/
```

Or add it to your `.mcp.json`:

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

## Authentication

To protect the MCP endpoint with API-token authentication, run the installer
with the `devise_token` strategy and migrate:

```bash
rails generate activeadmin_mcp:install --auth devise_token
rails db:migrate
```

This will:

- Create the `mcp_api_tokens` table.
- Add an "MCP Tokens" page to your ActiveAdmin panel (`app/admin/` by default).
- Enable token authentication in the initializer.

### Generator options

| Option | Default | Description |
|--------|---------|-------------|
| `--auth` | none | Authentication method to use (e.g. `devise_token`). |
| `--admin-path` | `app/admin` | Directory for the ActiveAdmin page file. |

Example with a custom admin path:

```bash
rails generate activeadmin_mcp:install --auth devise_token --admin-path app/admin/mcp
```

### Managing tokens

1. Log in to your ActiveAdmin panel (`/admin`).
2. Navigate to **MCP Tokens** (or **Settings > MCP Tokens** if you set a
   `menu_parent`).
3. Create a token and copy it — it is only shown once.

### Connecting with a token

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

### Custom auth header

If your application sits behind a reverse proxy that strips the standard
`Authorization` header (e.g. AWS Verified Access), configure a custom header
name and pass the token through it instead:

```ruby
ActiveadminMcp.configure do |config|
  config.authentication_method = :devise_token
  config.auth_header_name = "X-MCP-Authorization"
end
```

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

## Configuration

The generator writes an initializer to
`config/initializers/activeadmin_mcp.rb`:

```ruby
ActiveadminMcp.configure do |config|
  config.authentication_method = :devise_token
  config.user_class = "User" # your Devise model class
end
```

| Option | Default | Description |
|--------|---------|-------------|
| `authentication_method` | `nil` | Set to `:devise_token` to enable Bearer-token auth. |
| `user_class` | `"User"` | The Devise model class name. |
| `current_user_method` | `:current_admin_user` | Controller method returning the current user. |
| `menu_parent` | `nil` | Parent menu for the MCP Tokens page (e.g. `"Settings"`). |
| `mount_path` | `"/mcp"` | Path where the MCP server is mounted. |
| `mount_strategy` | `:prepend` | Route mounting strategy: `:prepend`, `:append`, or `:none`. |
| `auth_header_name` | `"Authorization"` | HTTP header to read the Bearer token from. |

### Route mounting

By default the engine prepends its route to the top of your application's route
table. This suits most setups, but can cause problems when your admin routes
use constraints (e.g. hostname-based routing), because a prepended mount sits
outside any constraint blocks.

| Strategy | Behaviour |
|----------|-----------|
| `:prepend` | **(default)** Mounts at the top of the route table via `routes.prepend`. |
| `:append` | Mounts at the bottom of the route table via `routes.append`. |
| `:none` | Skips automatic mounting — you mount the engine yourself. |

To mount inside a constraint block, set `mount_strategy` to `:none` and mount
the engine manually:

```ruby
# config/initializers/activeadmin_mcp.rb
ActiveadminMcp.configure do |config|
  config.mount_path = "/admin/mcp"
  config.mount_strategy = :none
end
```

```ruby
# config/routes.rb (or a drawn route file)
constraints AdminConstraint.new do
  ActiveAdmin.routes(self)
  mount ActiveadminMcp::Engine => ActiveadminMcp.config.mount_path
end
```

## Development

After checking out the repo, install dependencies and run the test suite:

```bash
bundle install
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub.

## Credits

This project was forked from
[betacraft/active_admin_mcp](https://github.com/betacraft/active_admin_mcp),
originally created by [harunkumars](https://github.com/harunkumars), and has
been extended from there.

## License

Released under the [MIT License](LICENSE.txt).
