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
- **Writes go through ActiveAdmin.** The `create` and `update` tools dispatch
  the resource's real ActiveAdmin controller action, so `permit_params`, your
  `before_save`/`after_update` callbacks, the controller's `before_action`
  chain and your authorization adapter all apply exactly as they do when
  someone clicks Save in the admin UI. Resources that don't register the
  action are refused, and `describe_form` will tell a client what a given
  resource's form accepts before it tries.
- **Authentication is optional but built in.** Enable Bearer-token auth and the
  installer adds an "MCP Tokens" management page to your ActiveAdmin panel.

## Requirements

- Ruby >= 4.0
- Rails >= 7.2
- ActiveAdmin ~> 3.5

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
| `create` | Create a new record through the resource's ActiveAdmin create action, honouring its permitted params, callbacks and authorization. |
| `update` | Update an existing record through the resource's ActiveAdmin update action, honouring its permitted params, callbacks and authorization. |
| `describe_form` | Describe the fields of a resource's form — input types, labels, hints, allowed values, column types and which are required — so a `create` or `update` call need not guess them. |
| *(per action)* | Any ActiveAdmin member, collection or batch action the application has opted in with an `mcp:` option, exposed as its own tool. |

### Query examples

```
Query users whose email contains "example.com"
→ query(resource: "User", q: { email_cont: "example.com" })

Find active posts created since the start of the month
→ query(resource: "Post", q: { status_eq: "active", created_at_gt: "2026-08-01" })
```

### Creating and updating records

```
Create a user
→ create(resource: "User", attributes: { name: "Ada", email: "ada@example.com" })

Update a user's name
→ update(resource: "User", id: 42, attributes: { name: "New name" })
```

Both tools dispatch the resource's own ActiveAdmin `create` or `update`
action, so a write from MCP is the same write the admin UI makes:

- **Registered actions only** — resources registered without the action
  (e.g. `actions :index, :show`) are refused.
- **Authorization** — the write runs through the resource namespace's
  authorization adapter for the authenticated MCP user, both before dispatch
  and again inside the controller, so it can only write what that user is
  allowed to write in admin.
- **Permitted fields only** — attributes are filtered through the resource's
  `permit_params`; fields the admin form doesn't accept are silently dropped.
  A resource that declares no `permit_params` at all is refused outright, with
  a message saying so — ActiveAdmin cannot write such a resource through its
  own forms either.
- **Your callbacks run** — ActiveAdmin's `before_build`, `before_create`,
  `before_save`, `after_update` and friends all fire, because the controller
  action is what fires them.

A write rejected by the model comes back as a `Validation failed` error with
the model's own messages in `details`, and nothing is written.

### Describing a form

```
What can I set when creating a post?
→ describe_form(resource: "Post")
→ describe_form(resource: "Post", action: "edit")
```

`describe_form` reads the resource's own `form do ... end` block when it
declares one, reporting each input's `as:`, `label:`, `hint:` and — when the
`collection:` is a literal array — its allowed values. Resources that declare
no form block get a description derived from their `permit_params` instead:
ActiveAdmin renders a bare `f.inputs` for those, which Formtastic only expands
at render time, so there is nothing to read. The response's `source` says which
of the two you are looking at.

Either way every field is annotated from the model with the column type it is
stored in and whether the model validates its presence. `has_many` blocks are
reported under `nested` rather than flattened in with the record's own fields.

`action:` selects the gate, not the shape — ActiveAdmin uses one form block for
both. `"new"` (the default) requires the resource to register `create` and pass
`create` authorization; `"edit"` requires `update`. Describing a form you could
never submit tells you nothing you can act on, so it is refused with the same
messages `create` and `update` use.

Two limits worth knowing:

- A `collection:` that is an `ActiveRecord::Relation` or a proc is omitted
  rather than evaluated. Describing a form should not fire a query, and a
  relation can be arbitrarily large. Use an action's
  [`suggestions:`](#running-member-collection-and-batch-actions) when you want
  dynamic values.
- A field a form block declares but `permit_params` omits is described and then
  silently dropped on write. This cannot arise on the `permit_params` fallback
  path.

### Running member, collection and batch actions

ActiveAdmin actions are **not** exposed by default. An action becomes an MCP
tool only when you add an `mcp:` option to it:

```ruby
ActiveAdmin.register Volunteer do
  member_action :create_warning, method: :post, mcp: {
    description: "Record a warning against a volunteer",
    permission: ->(volunteer) { volunteer.active? && can?(:warn, volunteer) },
    params: {
      reason:   { type: :string, required: true,
                  hint: "Short free-text summary shown to the volunteer" },
      severity: { type: :string, enum: %w[low medium high] },
      category: { type: :string,
                  suggestions: -> { WarningCategory.pluck(:name) } }
    }
  } do
    # your existing action body, unchanged
  end
end
```

That registers a `volunteer_create_warning` tool. Batch actions opt in the same
way, and inherit their param types from the `form:` hash you already declare:

```ruby
batch_action :suspend, form: { reason: :text },
                       mcp: { description: "Suspend the selected volunteers" } do |ids, inputs|
  # ...
end
```

**Declaring params**

- `type:` — one of `:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object`.
- `required:` — refuses the call when the value is missing.
- `hint:` — static guidance shown to the agent. Always a plain string.
- `enum:` — **binding**. A value outside the list is refused before dispatch.
- `suggestions:` — a proc evaluated when tools are listed. **Advisory only**,
  never enforced, so use it for live values from the database. If it raises,
  the tool is still listed without suggestions.

On a batch action, every declared param must also appear in the action's `form:`
hash. ActiveAdmin slices submitted inputs down to the declared `form:` keys
before calling the block, so a param declared only under `mcp:` would be
advertised to the client and then dropped; the declaration is refused instead.

**Authorization**

`permission:` is an *additional* gate, never a replacement. Every call first
passes your ActiveAdmin authorization adapter exactly as `query` and `update`
do; the proc can only narrow access further, never widen it. It is evaluated in
controller context, so `current_admin_user`, `can?` and the usual admin helpers
are available. Return `false` to refuse, or a `String` to refuse with a reason
the agent can act on.

Tools are also listed per user: an action whose resource the adapter refuses is
left out of `tools/list` entirely, and a `permission:` proc that takes no
arguments is evaluated at listing time (in the same controller context) so the
tool is hidden rather than offered and then refused.

For **batch actions** the adapter check is necessarily resource-level — there is
no single record to authorize — so it is `authorized?(:<action>, YourModel)`
rather than a per-record policy evaluation. To stop that being a hole, the ids
the client submits are run back through the adapter's `scope_collection`, and
the whole call is refused if any of them falls outside the scope. Nothing is
narrowed silently: the call either acts on every id you asked for or on none.

One caveat on authentication. Dispatch neutralises the namespace's
`authentication_method` callback, because the MCP request has already
authenticated by bearer token and that callback would otherwise redirect to a
login page. If your `authentication_method` is a *combined* authentication-and-
authorization method — one that also, say, rejects non-superusers — then
neutralising it disables that authorization half too. Resource-level
authorization still runs through the adapter, but the "we only skip
authentication" framing is not universal; keep authorization in the adapter,
not in the authentication callback.

**What you get back**

Actions are executed through your real ActiveAdmin controller, so the action's
`before_action` chain, authorization and callbacks all run. The tool returns the
response status, the redirect target and any flash messages — not the rendered
HTML. Redirect-style (submit-side) actions are the supported case; a `GET`
action that renders a full admin view is best-effort and may fail for want of a
view context.

### Actions declared somewhere you can't add `mcp:`

An action declared by a shared concern, or by another gem, has no declaration
you can hang an `mcp:` key on — and if it did, every resource including it
would get the same description, params and `permission:` proc. Annotate it by
name from the registration instead, with `mcp_action`:

```ruby
module Flaggable
  def self.included(dsl)
    dsl.send(:member_action, :flag, method: [:post, :delete]) { ... }
    dsl.send(:batch_action, :flag, form: proc { { reason: :text } }) { |ids, inputs| ... }
  end
end

ActiveAdmin.register Volunteer do
  include Flaggable

  mcp_action :flag, kind: :batch, tool_name: "volunteer_bulk_flag",
    description: "Flag the selected volunteers",
    params: { reason: { type: :string, required: true } }

  mcp_action :flag, kind: :member, tool_name: "volunteer_flag",
    description: "Flag a volunteer",
    params: { reason: { type: :string, required: true } }

  mcp_action :flag, kind: :member, http_verb: :delete, tool_name: "volunteer_unflag",
    description: "Remove a volunteer's flag"
end
```

`mcp_action` takes everything `mcp:` takes, plus:

| Option | Meaning |
|--------|---------|
| `kind:` | `:member`, `:collection` or `:batch`. Optional; needed only when one name belongs to more than one action, which is refused rather than guessed. |
| `tool_name:` | The MCP tool name, in place of the derived `<resource>_<action>`. |
| `http_verb:` | Which verb to dispatch, for an action declared with several (`method: [:post, :delete]`). A verb the action does not answer to is a declaration error. |

It **annotates**; it never declares. Naming an action the resource does not
have warns and skips. It is resolved when the tool list is built, not when it
is called, so it may appear above or below the `include`.

An annotation **replaces** an inline `mcp:` declaration rather than merging
into it, so a shared generic declaration and a per-resource one cannot
half-combine into something neither author wrote.

An action may carry more than one annotation, each producing its own tool —
which is how an action answering to two verbs, one undoing the other, becomes
two tools.

**Opting in is still per resource.** Two resources including the same concern
share the actions, not the exposure: whichever does not annotate exposes
nothing.

**Names must not collide.** A tool name carries no kind, so a `member_action`
and a `batch_action` of the same name derive the same one. Rather than let one
silently shadow the other, both are hidden until a `tool_name:` tells them
apart.

**Batch actions declared with a String title** — the ones applications generate
in loops from data — may be annotated by that title, rather than by the symbol
ActiveAdmin derives from it by titleizing and underscoring, which can carry
punctuation. The derived tool name has that punctuation squeezed out.

**ActiveAdmin's `:if` proc is honoured.** A batch action the admin UI hides
because its `:if` refuses is neither listed nor runnable over MCP. ActiveAdmin
itself consults `:if` only when rendering, so this is stricter than ActiveAdmin
is — deliberately: MCP should not be the way round a gate the admin enforces by
not offering the button. A proc that raises, typically because it reads request
state a tool listing cannot supply, hides the tool and says so in the log.

**A proc `form:` is evaluated** in controller context, the way ActiveAdmin
evaluates it, so a batch action whose form varies by resource still contributes
its param types. Like `suggestions:`, this runs application code, and is never
evaluated for a user the resource's authorization adapter refuses.

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
`server/index.js`) to the repository root. You do not bump the bundle's
`version` by hand: publishing a GitHub Release writes the release tag into
`mcpb/manifest.json` and `mcpb/package.json`, packs the bundle from that, and
attaches `activeadmin-mcp-<version>.mcpb` to the release — so the bundle
version Claude Desktop uses to detect upgrades always matches the gem version.
See [RELEASING.md](RELEASING.md).

So the bundle for any released version is on that release's page, and CI packs
the bundle on every push and attaches it as a build artifact if you want an
unreleased build from the Actions tab.

Distribute the file however suits you — pointing colleagues at the release
asset, an internal file share, or an S3 bucket. Anyone with the file can
install it, but it is inert without a token.

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
