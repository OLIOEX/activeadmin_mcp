# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- ActiveAdmin `member_action`, `collection_action` and `batch_action`
  definitions can be exposed as MCP tools by adding an `mcp:` option to them.
  Actions are opt-in: nothing is exposed without that option. Execution runs
  through the real ActiveAdmin controller, so `before_action` chains,
  authorization and callbacks all apply, and an optional `permission:` proc can
  narrow access further.

### Changed

- **Breaking:** the minimum supported Ruby is now 4.0 and the minimum Rails is
  7.2, and ActiveAdmin is constrained to `~> 3.5`. Applications outside those
  must stay on the previous release until they upgrade. Rails 7.2 is the oldest
  release this gem's end-to-end suite runs on Ruby 4; the ActiveAdmin
  constraint pins the gem to the 3.5 series it is tested against, and will need
  raising deliberately for ActiveAdmin 4. CI and the release workflow now run
  on Ruby 4.0.7.

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
