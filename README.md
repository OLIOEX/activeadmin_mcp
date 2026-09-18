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
  library ActiveAdmin uses for filtering. The tool calls `ransack` on the
  model directly rather than going through an ActiveAdmin filter form, so on
  Ransack 4 the model must allowlist the attributes it wants queryable via
  `ransackable_attributes`; without that allowlist, `query` against that
  resource will raise instead of returning an empty result.
- **Reads go through ActiveAdmin too.** `list_resources` and `query` run through
  the same authorization adapter (CanCanCan, Pundit, etc.) as the authenticated
  MCP user: resources the user cannot read are hidden from the listing and
  refused by `query`, and every query is scoped with the adapter's
  `scope_collection`, so the MCP user only ever sees the records they could see
  in the admin UI. With ActiveAdmin's default adapter every check passes, so
  applications without an authorization adapter are unaffected.
- **Writes go through ActiveAdmin.** The `update` tool only writes fields
  allowed by the resource's `permit_params`, refuses resources that don't
  register the `update` action, and runs every change through your
  authorization adapter as the authenticated MCP user.
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
| `list_resources` | List the ActiveAdmin resources the current user may read, along with their attributes. |
| `query` | Query a resource the current user may read, using Ransack syntax, scoped to the records they may access (`limit` defaults to 25, capped at 100). |
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

## Claude Desktop (MCPB bundle)

Claude Code talks to the server over HTTP directly, but **Claude Desktop** cannot:
its remote connector UI has no way to send an API token header. The `mcpb/`
directory solves this with an
[MCP bundle](https://claude.com/docs/connectors/building/mcpb) — a `.mcpb` file
your colleagues install with a double-click.

Inside the bundle is a small Node script that speaks stdio to Claude Desktop and
forwards every message, unchanged, to your server over HTTPS with the token
attached. It has no dependencies and adds no capabilities of its own, so the
tools it exposes are exactly the ones your server exposes.

```
Claude Desktop  ──stdio──▶  mcpb proxy  ──HTTPS + token──▶  your Rails app
```

### Building the bundle

Requires Node 18 or newer. From the repository root:

```bash
cd mcpb
npm test                                   # no dependencies to install
npx @anthropic-ai/mcpb pack . ../activeadmin-mcp.mcpb
```

That writes `activeadmin-mcp.mcpb` (a zip of `manifest.json`, `package.json` and
`server/index.js`) to the repository root, ready to distribute. Bump `version`
in **both** `mcpb/manifest.json` and `mcpb/package.json` before packing a
release — Claude Desktop uses the manifest version to detect upgrades.

CI packs the bundle on every push and attaches it as a build artifact, so you
can also download a build from the Actions tab rather than packing it yourself.

Distribute the file however suits you: an internal file share, a GitHub release
asset, or an S3 bucket. Anyone with the file can install it, but it is inert
without a token.

### Installing

1. **Generate a token.** Sign in to your admin panel, go to **MCP Tokens**, name
   the token after the machine you are installing on (e.g. "Claude Desktop —
   work laptop") and copy it. It is shown only once.
2. **Install the bundle.** Double-click the `.mcpb` file, or drag it onto the
   Claude Desktop window, or use **Settings → Extensions → Advanced settings →
   Install Extension…**.
3. **Fill in the three settings** Claude Desktop prompts for:

   | Setting | Value |
   |---------|-------|
   | Server URL | The full MCP endpoint, e.g. `https://admin.example.com/admin/mcp` |
   | API token | The token from step 1 (stored in the OS keychain, never shown again) |
   | Authentication header | `Authorization`, unless your app sets a custom [`auth_header_name`](#custom-auth-header) |

4. **Check it works.** Start a new chat and ask Claude to list the admin
   resources it can see. You should get back the resources your account can read.

Installation is per-person: each colleague installs the bundle and generates
their own token, so every MCP call is attributed to them and constrained by
their own admin permissions.

### Revoking access

A token is a long-lived credential granting everything that user can do in
admin. Revoke one from the same **MCP Tokens** page — the `Last used` column
shows which tokens are still live. Revoking takes effect immediately; the
installed bundle simply starts reporting an authentication failure.

### Troubleshooting

| Symptom | Cause |
|---------|-------|
| "The server rejected the API token (HTTP 401)" | The token is wrong, revoked, or being sent in the wrong header. Check the **Authentication header** setting matches your `auth_header_name`. |
| "Could not reach …" | The URL is wrong or unreachable from this machine — check VPN, and that the URL includes the full mount path. |
| The extension shows no tools | Claude Desktop only refreshes tools on connect. Toggle the extension off and on in Settings → Extensions. |
| Anything else | Claude Desktop's extension logs carry the proxy's stderr output, each line prefixed `[activeadmin_mcp]`. |

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

### Running the tests

`bundle exec rspec` (or `rake spec`, the default rake task) runs the unit
suite only — it's fast, and it's what CI's `rspec` job runs. It never touches
`spec/e2e`; that directory is excluded via `.rspec`.

The end-to-end suite lives in `spec/e2e` and runs separately:

```bash
bundle exec rake e2e
```

This generates a real Rails 7.2 + ActiveAdmin + Devise application under
`tmp/e2e_app`, installs the gem into it with `path:`, boots it under Puma,
and drives it over real HTTP with a minimal JSON-RPC client — the same way
Claude Code or any other MCP client would. It's how the gem is tested
against ActiveAdmin's and Ransack's actual behaviour rather than mocks.

The generated application is expensive to build (a full `bundle install`
against rubygems.org, and a `gem install rails` if Rails 7.2.2.2 isn't
already on your system) so it's cached in `tmp/e2e_app` between runs, keyed
on the contents of `spec/e2e/support/app_builder.rb`. The first run costs a
few minutes and needs network access; edit that file and the next run
rebuilds from scratch, otherwise reruns are quick. Force a rebuild without
editing anything by setting `E2E_REBUILD=1`:

```bash
E2E_REBUILD=1 bundle exec rake e2e
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
