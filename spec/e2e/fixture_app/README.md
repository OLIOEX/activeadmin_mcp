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
  suite can prove an unpermitted attribute is dropped rather than written.
- `app/admin/authors.rb` registers `actions :index, :show`, so the suite can
  prove `update` refuses a resource the admin UI would not let you edit.
- `app/models/*.rb` allowlist `ransackable_attributes`, which Ransack 4
  requires before it will filter on an attribute at all.
- `db/migrate/*.rb` create the `authors` and `posts` tables. They are checked
  in with fixed version numbers rather than produced by `rails generate model`,
  so the schema under test is visible and does not change from run to run.
- `db/seeds.rb` is restorative: it resets existing rows rather than only
  creating missing ones, because the suite's `update` examples mutate a post
  and the generated application is cached between runs. It reads the admin
  credentials from the environment so that they are defined in exactly one
  place, `AppBuilder`.

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
