# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- An `mcp_action` DSL, for exposing actions declared somewhere an `mcp:` key
  cannot be added — a shared concern, or another gem. The resource annotates
  the action by name from its own registration, so resources sharing an action
  can describe it differently, and whichever does not annotate exposes nothing.
  Annotations are resolved when the tool list is built rather than when they
  are declared, so they may appear either side of the `include`.

  Alongside `mcp:`'s own options it takes `kind:` (needed only to disambiguate
  a name belonging to more than one action, which is refused rather than
  guessed), `tool_name:`, and `http_verb:` (which verb to dispatch for an
  action declared with several, such as `method: [:post, :delete]`). An action
  may carry more than one annotation, each producing its own tool. An
  annotation replaces an inline `mcp:` declaration wholesale rather than
  merging into it.

  A batch action declared with a String title — the ones applications generate
  in loops from data — may be annotated by that title, rather than by the
  symbol ActiveAdmin derives from it, which can carry punctuation.

- A `describe_form` tool, which describes the fields behind a resource's create
  or update form so a client need not guess them from column names. It reads
  the resource's own `form do ... end` block when it declares one — reporting
  each input's `as:`, `label:`, `hint:`, and its allowed values when the
  `collection:` is a literal array — and otherwise derives the description from
  the resource's `permit_params`, which is what `create` and `update` enforce
  anyway. The response says which of the two it used. Every field is annotated
  from the model with its column type and whether the model validates its
  presence, and `has_many` groups are reported as nested rather than flattened
  into the record's own fields.

  `action:` selects the gate rather than the shape, since ActiveAdmin uses one
  form block for both: `"new"` requires the resource to register `create` and
  pass `create` authorization, `"edit"` requires `update`. A form the user
  could never submit is refused with the same messages `create` and `update`
  give.

  A `collection:` that is a relation or a proc is omitted rather than
  evaluated: describing a form should not fire a query, and a relation can be
  arbitrarily large.

- A `create` tool, which creates a record by dispatching the resource's own
  ActiveAdmin `create` action. Resources registered without that action are
  refused, `permit_params` decides what may be written, the namespace's
  authorization adapter is consulted before dispatch and again inside the
  controller, and every ActiveAdmin callback (`before_build`, `before_create`,
  `before_save`, …) fires. A record the model rejects comes back as a
  `Validation failed` error carrying the model's own messages.

- ActiveAdmin `member_action`, `collection_action` and `batch_action`
  definitions can be exposed as MCP tools by adding an `mcp:` option to them.
  Actions are opt-in: nothing is exposed without that option. Execution runs
  through the real ActiveAdmin controller, so `before_action` chains,
  authorization and callbacks all apply, and an optional `permission:` proc can
  narrow access further.

  `tools/list` is user-specific: an action is advertised only when the
  authenticated MCP user passes the resource's authorization adapter, and a
  zero-argument `permission:` proc is evaluated at listing time in controller
  context (so `current_admin_user` and `can?` work there as they do at call
  time). A param's `suggestions:` proc, which runs application code against the
  database, is never evaluated for a user who is not authorized for the action.

  Batch action calls additionally run the submitted ids through the adapter's
  `scope_collection` and refuse the entire call if any id falls outside it,
  rather than silently acting on fewer records than the client asked for.

  A batch action param declared under `mcp:` but missing from the action's
  ActiveAdmin `form:` hash is now a declaration error. ActiveAdmin slices
  submitted inputs to the `form:` keys, so such a param was advertised,
  required and validated, and then silently dropped before the block ran.

  Action failures return a generic error naming the resource and action; the
  underlying exception message is written to the log instead of being sent to
  the MCP client, where it could disclose SQL, table names or file paths.

- Publishing a GitHub Release now attaches the Claude Desktop bundle to it as
  `activeadmin-mcp-X.Y.Z.mcpb`, so installing the bundle no longer means
  digging a build artifact out of the Actions tab.

### Fixed

- A resource whose `permit_params` is a block was refused by `create`, `update`
  and `describe_form` with `Resource declares no permit_params, so nothing may
  be written`, which was not merely unhelpful but wrong. ActiveAdmin
  `instance_exec`s such a block on the controller, and the gem resolved it
  against a bare controller instance, so a block reading `current_admin_user`
  raised `NameError` — and the rescue that exists to recognise a resource with
  no `permit_params` at all swallowed it. The block is now resolved against a
  controller carrying the MCP user, as a dispatched call gets.

- `describe_form` reported no writable attributes at all for a resource whose
  `form` block declares none of its own — `form do |f| f.inputs; f.actions end`,
  the shape of ActiveAdmin's own default form, where Formtastic expands the
  inputs only at render time. There is nothing in such a block to read, so the
  description now falls back to the resource's permitted params, as it already
  did for a resource with no `form` block.

- `describe_form` reported the fields of an `inputs for: :association` block as
  attributes of the record being described, rather than as a nested group.
  They belong to the associated record and `create` and `update` will drop
  them. `has_many` was already handled this way; both routes into an
  association's fields now behave the same.

### Changed

- A batch action's own ActiveAdmin `:if` proc is now honoured: one the admin UI
  hides because `:if` refuses is neither listed nor runnable over MCP. This is
  stricter than ActiveAdmin, which consults `:if` only when rendering and will
  dispatch such an action regardless — deliberately so, since MCP should not be
  the way round a gate the admin enforces by not offering the button. A proc
  that raises, typically because it reads request state a listing cannot
  supply, hides the tool and says so in the log.

- A batch action whose `form:` is a proc rather than a hash now contributes its
  param types, by evaluating the proc in controller context exactly as
  ActiveAdmin does. Previously proc forms were skipped and inherited nothing.
  Like `suggestions:`, this runs application code, and is never evaluated for a
  user the resource's authorization adapter refuses.

- Two actions that would be exposed under the same tool name are now both
  hidden, with a declaration error naming the clash, rather than one silently
  shadowing the other. A tool name carries no kind, so a `member_action` and a
  `batch_action` of the same name derived the same one, and only the member one
  was ever reachable. Give all but one an explicit `tool_name:`.

- **Behaviour change:** `update` now dispatches the resource's real ActiveAdmin
  `update` action instead of calling `record.update` directly. Everything the
  admin UI runs on a save now runs on an MCP update too: the controller's
  `before_action` chain, ActiveAdmin's `before_update` / `after_update` /
  `before_save` / `after_save` callbacks, and the controller's own
  authorization check. Applications whose callbacks have side effects —
  auditing, notifications, derived columns, background jobs — will see those
  fire for MCP updates where previously they were silently skipped.

  Two smaller consequences of the same change: a write rejected by the model
  now reports `Validation failed` with the model's messages in `details`
  rather than reporting whatever `record.update` returned, and the record
  echoed back in the result has the same sensitive attributes stripped from it
  (`encrypted_password`, `password_digest`, `reset_password_token`, `api_key`,
  `secret`) that `list_resources` and `query` already omit.

- The release tag is now the source of truth for the bundle's version too: the
  release workflow writes it into `mcpb/manifest.json` and `mcpb/package.json`
  before packing, and commits the bump back alongside `version.rb`. The gem and
  the bundle can no longer drift apart, and nobody has to remember the manual
  bump the README used to ask for.

- **Breaking:** the minimum supported Ruby is now 4.0 and the minimum Rails is
  7.2, and ActiveAdmin is constrained to `~> 3.5`. Applications outside those
  must stay on the previous release until they upgrade. Rails 7.2 is the oldest
  release this gem's end-to-end suite runs on Ruby 4; the ActiveAdmin
  constraint pins the gem to the 3.5 series it is tested against, and will need
  raising deliberately for ActiveAdmin 4. CI and the release workflow now run
  on Ruby 4.0.7.

- The generated initializer now carries `mount_strategy` alongside the other
  options, commented out like them. It was documented in the README but absent
  from the file, so nobody reading their own initializer would have learnt it
  exists.

- The README's examples are now written against the same `Post`, `Author`,
  `Review` and `Tag` registrations the end-to-end suite builds and drives,
  which are checked in under `spec/e2e/fixture_app/`. They previously used
  resources that exist nowhere in the repository, so there was no way to read
  a documented claim next to the example that exercises it.

### Removed

- The fallback that derived writable fields from a resource's `form do ... end`
  block when it declared no `permit_params`. Now that writes dispatch through
  the real controller, ActiveAdmin resolves permitted params itself, and the
  fallback turns out to have been granting MCP clients a write the admin UI
  does not grant: a resource with no `permit_params` cannot be saved through
  ActiveAdmin's own forms at all, because Rails raises
  `ActiveModel::ForbiddenAttributesError` on the unpermitted params. Such a
  resource is now refused with a message naming the missing `permit_params`,
  rather than being written to.

### Security

- Enforce ActiveAdmin authorization on reads. `list_resources` and `query`
  previously ignored the resource namespace's authorization adapter, so any
  authenticated MCP user could list and Ransack-query every registered resource
  regardless of their admin abilities. Both tools now run through the same
  adapter as the admin UI: unreadable resources are hidden and refused, and
  query results are scoped with `scope_collection`. `query` also now strips the
  same sensitive attributes (`encrypted_password`, `password_digest`,
  `reset_password_token`, `api_key`, `secret`) from returned records that
  `list_resources` already omits. Applications using ActiveAdmin's default
  authorization adapter are unaffected.

## [0.1.0] - Unreleased

Initial release.

### Added

- MCP server mounted as a Rails engine (default `/mcp`), speaking JSON-RPC 2.0
  over HTTP.
- `list_resources`, `query` (Ransack), and `update` tools driven by your
  existing ActiveAdmin registrations.
- Optional `devise_token` Bearer-token authentication with an install
  generator, an "MCP Tokens" ActiveAdmin page, and configurable auth header.
- Configurable mount strategy (`:prepend`, `:append`, `:none`) and mount path.

[Unreleased]: https://github.com/OLIOEX/activeadmin_mcp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/OLIOEX/activeadmin_mcp/releases/tag/v0.1.0
