# CLAUDE.md

Guidance for AI assistants working in this repository.

## What this is

`activeadmin_mcp` is a Rails engine that exposes an application's existing
ActiveAdmin resources over the Model Context Protocol. It speaks JSON-RPC 2.0
over HTTP and is mounted at `/mcp` by default. The tools it offers —
`list_resources`, `query`, `update` — are defined in
`lib/activeadmin_mcp/request_handler.rb`.

## Ruby version

This gem requires Ruby 4.0 and CI runs 4.0.7. There is no `.ruby-version`, so
if your shell defaults to an older Ruby every `bundle` command fails with a
resolution error that does not mention the Ruby version as the cause. Prefix
commands with the version rather than debugging the symptom:

    RBENV_VERSION=4.0.7 bundle exec rake spec
    RBENV_VERSION=4.0.7 bundle exec rake e2e

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

### Cover the declaration shapes, not only the behaviours

The rule above asks for an e2e test per MCP action. That is necessary and it is
not sufficient, because it is organised around what this gem does rather than
around what the applications it reads look like. Nearly every defect found in
review so far has been the same thing: a shape of ActiveAdmin declaration that
no fixture used, so no test could fail on it.

So, for any ActiveAdmin construct this gem reads, enumerate the forms
ActiveAdmin accepts and make sure a fixture exists for each. For example
`permit_params` may be a list, a block, a block that reaches for controller
state, absent entirely, or set on the namespace; a `form` block may declare
inputs, declare none and leave Formtastic to expand a bare `f.inputs`, or nest
with `has_many` or `inputs for:`; a `batch_action` may be named with a symbol
or a String title, and its `form:` may be a hash or a proc.

**When you read ActiveAdmin's source to answer a question, enumerate the
branches you did not take.** Two of those defects were in lines already quoted
in the notes justifying the change — `block ? instance_exec(&block) : args` and
a bare `f.inputs` in ActiveAdmin's own default form. The information was not
missing; the question "what else does this line permit?" was never asked.

**Mutation checking does not cover this, and can disguise it.** Breaking a
fixture and watching the example fail proves the test is sensitive to that
fixture. It says nothing about a shape no fixture has, and no mutation of the
existing fixtures will ever reveal one. Treat a passing mutation check as
evidence about test sensitivity, and never describe it as evidence of coverage.

When the shapes are invented rather than observed, they tend to match whatever
was just built. Prefer shapes taken from real applications or from ActiveAdmin's
own source and test suite.

### Writing an e2e example

`E2E::McpClient` speaks the protocol: `tools_list` returns the `tools/list`
result, and `call_tool(name, arguments)` unwraps both layers of a tool result
— the JSON-RPC envelope and the pretty-printed JSON inside the text content
block — and hands back the payload. A tool that refuses returns a hash with an
`"error"` key rather than raising, so assert on that key.

**Assert the side effect, not only the response.** An example that checks a
refusal came back has not shown the action was prevented: the same assertion
passes whether the call was refused before dispatch or ran and then reported
an error. Read the record back with `query` and assert it is unchanged. The
same applies in reverse for a successful call — assert the change landed, not
merely that no error came back.

**When an example is about which records were affected, assert an untouched
control record.** A batch example that only checks the selected rows changed
cannot tell "acted on the ones I asked for" from "acted on everything". Seed
or pick a record that must not change, and assert it did not.

**Prefer `include` to exact lists when asserting on the tool listing.** The
fixture application opts actions in to MCP, so the listing legitimately grows
when someone adds one; `contain_exactly` there turns an unrelated addition
into a failure in a file that has nothing to do with it.

**Environment variables set for seeding are not set for the running server.**
The seeds read credentials from the environment, but the application boots as
a separate process without them. A fixture that needs the seeded admin's
identity at request time has to hard-code it to match `AppBuilder`, not read
`ENV`.

Things this suite has caught that the unit specs structurally could not: that
Rails' forgery protection refuses the synthesized request every non-GET action
depends on, and that a `permission:` proc evaluated outside controller context
raises `NameError` and silently hides a tool. Both looked fine against mocks.

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

# Guidelines

* ALWAYS use descriptive method and variable names instead of comments. Don't add comments to code — names should carry the meaning
* ALWAYS use British English everywhere — strings, comments, identifiers, method/variable names, commit messages. (favourite, colour, organisation.)
* ALWAYS use inclusive language. Avoid gendered pronouns and acronyms
* NEVER run the full test suite locally. Push the branch and let the GitHub Actions run cover it. Locally, run only the specs for the files you touched plus what they cascade into.
