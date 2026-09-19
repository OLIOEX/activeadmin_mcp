# Releasing

`activeadmin_mcp` is published to [RubyGems.org](https://rubygems.org) via
**Trusted Publishing** (OIDC). No API key is stored in the repo or in GitHub
secrets — RubyGems verifies the `Release` GitHub Actions workflow directly.

Releases are driven by **GitHub Releases**. Publishing a release with a
`vX.Y.Z` tag triggers `.github/workflows/release.yml`, which:

1. Derives the version from the release tag.
2. Writes it into `lib/activeadmin_mcp/version.rb`, `mcpb/manifest.json` and
   `mcpb/package.json`.
3. Runs the specs and the MCPB proxy tests, and packs the Claude Desktop bundle.
4. Builds and publishes the gem to RubyGems via OIDC.
5. Uploads `activeadmin-mcp-X.Y.Z.mcpb` as an asset on the release.
6. Commits the version bumps back to the default branch.

The release tag is the single source of truth for the version — you do not edit
`version.rb` or the bundle's `version` fields by hand, and the gem and the
bundle always carry the same version.

The bundle is packed before the gem is pushed, so a broken bundle stops the
release rather than following a published gem. Uploading the asset uses
`--clobber`, so re-running the workflow on the same release replaces the asset
rather than failing.

## One-time setup (RubyGems side)

Because the gem does not exist on RubyGems yet, register a **pending** trusted
publisher first — this both reserves the name and authorises the workflow:

1. Sign in at <https://rubygems.org> (the account must have MFA enabled — the
   gemspec sets `rubygems_mfa_required`).
2. Go to <https://rubygems.org/profile/oidc/pending_trusted_publishers/new>.
3. Fill in:
   - **RubyGems gem name:** `activeadmin_mcp`
   - **GitHub repository:** `OLIOEX/activeadmin_mcp`
   - **Workflow filename:** `release.yml`
   - **Environment (optional but recommended):** `rubygems`
4. Save.

Then, in the GitHub repo settings, create an **Environment** named `rubygems`
(Settings → Environments → New environment) to match the workflow's
`environment: rubygems`. Add required reviewers there if you want a manual gate
before each publish.

Once the gem has been published the first time, the pending publisher becomes a
regular trusted publisher automatically — no further RubyGems setup is needed.

## Cutting a release

1. Move the relevant `CHANGELOG.md` entries under a new version heading with the
   release date (open a PR and merge to `main` if you want this on the tagged
   commit).
2. On GitHub, go to **Releases → Draft a new release**.
3. Create a new tag `vX.Y.Z` (targeting `main`), give the release a title and
   notes, and click **Publish release**.

Publishing the release triggers `.github/workflows/release.yml`, which bumps
`version.rb` and the bundle manifests to match the tag, runs the specs,
publishes the gem to RubyGems via OIDC, attaches the
`activeadmin-mcp-X.Y.Z.mcpb` bundle to the release, and commits the version
bumps back to `main`.

> **Branch protection:** the workflow pushes the version-bump commit to the
> default branch using the built-in `GITHUB_TOKEN`. If `main` requires pull
> requests or status checks for every push, either allow the
> `github-actions[bot]` actor to bypass protection or remove the commit-back
> step and bump `version.rb` manually before releasing.

## Building locally (optional)

To verify the packaged gem without publishing:

```bash
bundle exec rake build   # writes pkg/activeadmin_mcp-<version>.gem
```

To verify the Claude Desktop bundle without publishing, see
[Building the bundle](README.md#building-the-bundle) in the README.

Do **not** run `rake release` locally — publishing happens only through the
tagged CI workflow.
