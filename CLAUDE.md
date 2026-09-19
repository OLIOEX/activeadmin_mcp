# CLAUDE.md

Guidance for AI assistants working in this repository.

## What this is

`activeadmin_mcp` is a Rails engine that exposes an application's existing
ActiveAdmin resources over the Model Context Protocol. It speaks JSON-RPC 2.0
over HTTP and is mounted at `/mcp` by default. The tools it offers —
`list_resources`, `query`, `update` — are defined in
`lib/activeadmin_mcp/request_handler.rb`.

## Testing MCP actions

**Every MCP action must be covered by an end-to-end test, not only by unit
specs.** This applies to new tools, new arguments on an existing tool, and any
change to how an existing tool authorizes, filters, or writes data.

The reason is specific to this gem: almost everything it does is a claim about
code it does not own. `permit_params` is resolved by instantiating the real
ActiveAdmin controller and reading its compiled permitted params; authorization
runs through whichever adapter the host application configured; `query` hands
its arguments to Ransack; the engine mounts itself into the host's route set.
A unit spec can only assert that we called a mock the way we expected to — it
cannot show that ActiveAdmin, Ransack, Devise and Rails actually behave that
way when wired together. Several defects in this repository's history were
invisible to the unit suite for exactly that reason.

The e2e suite lives in `spec/e2e/`. It generates a real Rails + ActiveAdmin +
Devise application into `tmp/e2e_app`, installs this gem into it through the
gem's own generator, boots it under Puma, and drives the mounted endpoint over
HTTP with a real API token.

    bundle exec rake spec   # unit specs, fast
    bundle exec rake e2e    # end-to-end suite

`rake e2e` caches the generated application, so only the first run is slow.
`E2E_REBUILD=1` forces a rebuild. See the README's "Running the tests" section.

The application it generates is not written from heredocs: the ActiveAdmin
registrations, models, migrations and seeds it uses are checked in under
`spec/e2e/fixture_app/` and copied into place, so you can read and edit the
thing the suite tests against. Any static file you need to add to that
application belongs there too, not in a heredoc inside the builder.

When you add an e2e example, make sure it can actually fail. Edit the relevant
file under `spec/e2e/fixture_app/` so the behaviour under test is wrong, watch
the example fail, then restore it — editing a fixture invalidates the build
cache, so the next run picks it up. An end-to-end suite that passes regardless
of what the code does is worse than no suite, because it is believed.

Every example starts from the seeded database: a `before` hook restores it from
a snapshot taken after migrating and seeding. So examples must not depend on
what another one left behind, and the suite runs in random order to keep that
honest. Write each one as though it runs alone, because it might.

### Write e2e descriptions out in full

Give e2e examples and their enclosing blocks descriptions verbose enough that
the `--format documentation` output reads as a specification of the MCP
interface on its own, without anyone opening the file. These descriptions are
the closest thing this project has to a written contract for how the server
behaves, and they are what someone debugging a CI failure sees first.

State the behaviour and its condition, not the mechanics:

    # Too terse: names a method, not a behaviour.
    it "filters"

    # Better: someone reading the output learns what the server guarantees.
    it "filters records with Ransack syntax passed straight through to the model"

    # Too terse: gives no clue why refusing is correct.
    it "refuses Author"

    # Better: the reason is the point of the example.
    it "refuses to update a resource registered without the update action"

Prefer a long description to a comment explaining a short one. Favour the
language of the README and the MCP tools — resources, attributes, permitted
params, authorization — over the language of the implementation.
