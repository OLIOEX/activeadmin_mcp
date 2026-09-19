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

When you add an e2e example, make sure it can actually fail. Change the
generated application so the behaviour under test is wrong, watch the example
fail, then restore it. An end-to-end suite that passes regardless of what the
code does is worse than no suite, because it is believed.
