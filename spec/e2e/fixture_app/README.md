# Fixture application

These files are copied over the Rails application the e2e suite generates
into `tmp/e2e_app`, replacing what the Rails and ActiveAdmin generators
produce. They are checked in rather than written from heredocs in
`../support/app_builder.rb` so that you can read, diff and edit the thing the
suite actually tests against.

The layout mirrors the generated application, so a file here lands at the same
path there.

Each one exists to give a claim in the README something to bite on:

- `app/admin/posts.rb` permits `title` and `body` but **not** `slug`, so the
  suite can prove an unpermitted attribute is dropped rather than written. It
  also carries the MCP action fixtures:
  - `member_action :publish` is opted in via `mcp:` with a required
    `visibility` param bound to a static `enum:`, so the suite can prove a
    value outside the enum is refused before dispatch and a permitted value
    runs against the real controller.
  - `member_action :archive` has no `mcp:` key at all, so the suite can prove
    the opt-in guarantee: an action that exists in the admin UI is not
    automatically exposed as a tool.
  - `batch_action :set_status` is opted in via `mcp:` with only a
    description — its param type is inherited from `form:` — so the suite can
    prove a batch action applies to exactly the selected records and leaves
    the rest untouched.
  - `member_action :explode` raises from its body, so the suite can prove a
    failing action comes back as a generic error naming the resource and
    action, with the exception's own message — which can carry SQL, table
    names and file paths — kept away from the MCP client.
  - `member_action :feature` carries a `permission:` proc that takes the
    record and returns a refusal *string* for a draft post, so the suite can
    prove a record-aware proc keeps its tool advertised (it cannot be resolved
    at listing time), refuses at call time with the proc's own wording, and
    allows the call once the record satisfies it.
  - `collection_action :purge_drafts` is opted in via `mcp:` with a
    zero-argument `permission:` proc that calls `current_admin_user`, so the
    suite can prove the proc is evaluated in controller context at
    `tools/list` time rather than raising `NameError` and silently hiding the
    tool.
- `app/admin/authors.rb` registers `actions :index, :show`, so the suite can
  prove `update` refuses a resource the admin UI would not let you edit.
- `app/admin/newsletters.rb` declares its `permit_params` in the **block**
  form, and the block reads `current_admin_user`, so the suite can prove the
  permitted set is resolved in controller context. Asked of a bare controller
  instance the block raises `NameError`, which reads as "this resource
  declared no `permit_params`" and refuses `create`, `update` and
  `describe_form` outright. Its `secret_note` is permitted to nobody, so
  there is something the block withholds as well as something it grants.
- `app/admin/bulletins.rb` declares a form block containing a bare `f.inputs`
  and nothing else — legal, because Formtastic expands it against the model
  at render time — so the suite can prove `describe_form` falls back to
  `permit_params` rather than reporting a form with no fields at all.
- `app/admin/dispatches.rb` declares a form block whose second `f.inputs`
  names an association with `for:`, so the suite can prove the associated
  record's fields are reported as a `nested` group rather than flattened in
  with the dispatch's own — where a client would read them as attributes a
  write against a dispatch could set, and `create` and `update` would drop
  them.
- `app/models/*.rb` allowlist `ransackable_attributes`, which Ransack 4
  requires before it will filter on an attribute at all.
- `db/migrate/*.rb` create the `authors` and `posts` tables, and add the
  `status` column `posts` needs for the MCP action fixtures. They are checked
  in with fixed version numbers rather than produced by `rails generate model`,
  so the schema under test is visible and does not change from run to run.
- `db/seeds.rb` is restorative: it resets existing rows rather than only
  creating missing ones, because the suite's `update` examples mutate a post,
  the MCP action examples mutate a post's `status` (directly and via a batch
  action), and the generated application is cached between runs. It reads the
  admin credentials from the environment so that they are defined in exactly
  one place, `AppBuilder`.

Two files here are not copied into the application:

- `README.md`, this file.
- `Gemfile.deps`, which is appended to the Gemfile the Rails generator wrote
  rather than replacing it. `GEM_PATH` in it is substituted with the
  repository root.

Editing anything here except this README changes the builder's cache
fingerprint, so the next `rake e2e` rebuilds the application rather than
silently reusing a stale one. That is what makes these files safe to
experiment with: break one deliberately, run the suite, and watch the example
that covers it fail.

After migrating and seeding, the builder snapshots the SQLite database to
`storage/seeded.sqlite3` inside the generated application. Restoring from that
snapshot is a transaction against the live database rather than a Rails boot,
so the suite can afford to do it before every single example — which is why
examples here never have to undo their own writes.
