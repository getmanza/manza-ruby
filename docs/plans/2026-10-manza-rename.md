# Plan 2 — Rename zazu → manza (1.0.0 under new names)

Status: **proposed, not started**. Starts after Plan 1 (`2026-10-api-sync.md`) has shipped 0.3.0 everywhere.

## Decisions taken

- Scheme: the `@getmanza` npm scope (the npm org is `getmanza`) and plain `manza` names elsewhere.
- New packages start at **1.0.0**.
- Old packages get one final `0.3.x` deprecation release that points at the new name.

## Target names

GitHub org is already `getmanza` (`getzazu/*` redirects).

| Repo (now → new) | Registry id (now → new) | Namespace (now → new) |
|---|---|---|
| `zazu-ruby` → `manza-ruby` | gem `zazu-ruby` → `manza` | `require "zazu"`/`Zazu::` → `require "manza"`/`Manza::` |
| `zazu-ts` → `manza-ts` | npm `@getzazu/sdk` → `@getmanza/sdk` | `Zazu`, `ZazuError`… → `Manza`, `ManzaError`… |
| `zazu-python` → `manza-python` | PyPI `zazu-sdk` → `manza` | `zazu_sdk` → `manza` |
| `zazu-go` → `manza-go` | module `github.com/getzazu/zazu-go` → `github.com/getmanza/manza-go` | `package zazu` → `package manza` |
| `zazu-php` → `manza-php` | Packagist `getzazu/zazu-php` → `manza/manza-php` | `Zazu\` → `Manza\` |
| `zazu-rust` → `manza-rust` | crate `zazu-sdk` → `manza` | `zazu_sdk::` → `manza::` |
| `zazu-crystal` → `manza-crystal` | shard `zazu` → `manza` | `Zazu::` → `Manza::` |
| `zazu-elixir` → `manza-elixir` | Hex `zazu` → `manza` | `Zazu.` → `Manza.`, app `:zazu` → `:manza` |
| `cli` (unchanged) | npm `@getzazu/cli` + 4 arch pkgs → `@getmanza/cli` + `@getmanza/cli-<arch>` | binary `zazu` → `manza` |
| `homebrew-tap` (unchanged) | `Formula/zazu.rb` → `Formula/manza.rb` | |

## Wire and runtime renames (all SDKs + CLI)

| Item | Now | New | Compat |
|---|---|---|---|
| Version header | `Zazu-Version` | `Manza-Version` | Server already accepts both and prefers Manza |
| Default base URL | `https://zazu.ma` | `https://ma.manza.finance` | Both are served. Keep MA as the default; document `za.manza.finance` |
| Sandbox | `staging.zazu.ma` | `ma.manza.dev` | Both are served |
| Env vars | `ZAZU_API_KEY`, `ZAZU_BASE_URL`, `ZAZU_API_VERSION`, `ZAZU_TIMEOUT[_MS]` | `MANZA_API_KEY`, `MANZA_BASE_URL`, `MANZA_API_VERSION`, `MANZA_TIMEOUT[_MS]` | Read `MANZA_*` first and fall back to `ZAZU_*` with a one-time deprecation warning, for all of 1.x. The server docs already say `MANZA_API_KEY` (they currently say `MANZA_API_BASE`, so align: pick `MANZA_BASE_URL` and fix the app docs) |
| CLI-only env | `ZAZU_VERSION` (the CLI's odd name) | `MANZA_API_VERSION` | Same fallback |
| User-Agent | `zazu-<lang>/x` (Python: `zazu-sdk`) | `manza-<lang>/x` everywhere | The server logs only the first token. Tell the app team so the SDK usage metrics map both |
| Fixture env | `ZAZU_FIXTURE_*`, `ZAZU_STAGING_*` | `MANZA_FIXTURE_*`, `MANZA_STAGING_*` | No fallback (dev-only) |
| Cassette placeholders | `<ZAZU_API_KEY>`, `<ZAZU_VERSION>` | `<MANZA_API_KEY>`, `<MANZA_VERSION>` | All harnesses change in lockstep |
| CLI config | `~/.config/zazu/config.json` | `~/.config/manza/config.json` | Read the new path, else the old one. On first write, migrate (copy) and leave the old file. `CLAUDE.md` requires backwards compatibility |
| Webhook verifier | not shipped | not shipped | Out of scope. If one is added later, accept `X-Manza-*` with `X-Zazu-*` as a fallback |

## Phase 0 — prerequisites (manual, you)

1. Claim the names: npm org `getmanza` (scope `@getmanza`), Packagist vendor `manza`, and do a first-publish reservation on gem / PyPI / crate / Hex `manza`. **All were free on 2026-10-02**; claim them early.
2. Configure the trusted publishers. Nothing renames in place, so each one is a new binding:
   - RubyGems (`manza`, repo `getmanza/manza-ruby`, env `rubygems`)
   - npm `@getmanza/sdk`
   - npm `@getmanza/cli` plus the 4 arch packages
   - PyPI `manza` (pending publisher, env `pypi`)
   - crates.io `manza` (env `crates-io`)
   - Hex: a new `HEX_API_KEY` for the `manza` package
   - Packagist: submit `getmanza/manza-php`
3. Rename the GitHub repos `getmanza/zazu-*` → `getmanza/manza-*`. Redirects keep old clones and release-asset URLs working, but **the Go module path must change in `go.mod` regardless**.
4. App: confirm `ma.manza.dev` sandbox parity with `staging.zazu.ma`. It must be the same entity, keys and flags, or else move the Plan 1 staging setup over.

## Phase 1 — manza-ruby 1.0.0 (reference, one PR)

1. `git mv lib/zazu lib/manza`, `lib/zazu.rb` → `lib/manza.rb`, and `zazu-ruby.gemspec` → `manza.gemspec`. Then `Zazu` → `Manza` throughout lib, spec, Rakefile and `lib/tasks`.
2. Client:
   - `DEFAULT_BASE_URL = "https://ma.manza.finance"`
   - `Manza-Version` header
   - `USER_AGENT = "manza-ruby/…"`
   - Env lookup `MANZA_*` → `ZAZU_*` fallback with a deprecation warning. Spec each fallback path.
3. VCR:
   - Placeholders `<MANZA_API_KEY>` and `<MANZA_VERSION>`.
   - Scrub both version response headers.
   - Fixture env renamed to `MANZA_FIXTURE_*`.
4. **Re-record all cassettes against `https://ma.manza.dev`** (`rake fixtures:record`). Every cassette's `uri:` changes host, and that is the contract change for the other SDKs.
5. `fixtures:pack` names the tarball `cassettes-v1.0.0.tar.gz` (same name scheme, new repo URL).
6. README, CHANGELOG (with a migration guide section: old → new require/class/env), `CLAUDE.md`, `.claude/commands/*`, `LICENSE` holder, package metadata URIs and email (`hello@get-manza.com` in every package manifest).
7. `release.yml`: rename the gem globs and artifact names.
8. Release `manza` 1.0.0.

## Phase 2 — deprecation release of `zazu-ruby` (0.3.1)

- Ship from a `zazu-legacy` branch: `post_install_message` plus a `warn` on `require "zazu"` pointing to `manza`.
- Same pattern for each old package: npm `npm deprecate @getzazu/sdk "moved to @getmanza/sdk"` (no release needed), PyPI 0.3.1 with a warning, crates.io `cargo yank` is *not* used (only a README notice plus a 0.3.1 with a warning), Hex `mix hex.retire zazu 0.3.0 renamed --message`, Packagist mark abandoned → `manza/manza-php`, Go: add `// Deprecated: use github.com/getmanza/manza-go` to the old module's package doc and tag v0.3.1.

## Phase 3 — consumer SDKs 1.0.0 (parallel, one PR each, after manza-ruby 1.0.0)

Per repo:

1. Rename the package and module as in the table.
   - Go: `go.mod` path plus every import.
   - PHP: `composer.json` PSR-4 plus `namespace`.
   - Rust: `Cargo.toml` name and lib name, plus the `"zazu: "` → `"manza: "` error prefixes.
   - Elixir: `mix.exs` app, the modules and the `zazu-version` header.
   - Python: rename the `src/zazu_sdk` directory → `src/manza`.
2. Default URL, `Manza-Version`, User-Agent, and env fallback, with tests for the fallback.
3. Fetch script: `REPO="getmanza/manza-ruby"`. Pin to `v1.0.0` for the first PR to avoid racing old tags. Unpinning afterwards is optional; consider keeping a pin, since the unpinned latest-tag behaviour is how Plan 1 can break all CIs at once.
4. Replay harness: the new placeholders (`<MANZA_API_KEY>`, `<MANZA_VERSION>`) and the `MANZA_FIXTURE_*` names.
5. Release workflow: package globs, tarball names, environment bindings.
6. README, CHANGELOG migration notes, `CLAUDE.md`, and the package manifest email (`hello@get-manza.com`). Also fix the stale User-Agent version constants if Plan 1 didn't.
7. Release 1.0.0, then the deprecation step from Phase 2 on the old name.

## Phase 4 — CLI 1.0.0

- Depends on `@getmanza/sdk` ^1.0.0. Imports `Manza`/`ManzaError`.
- Binary `manza`. Update `scripts/build`, `scripts/npm-publish`, the `release.yml` awk patterns and `test/cli.test.js`. **Keep a `zazu` shim** in `package.json` `bin` for 1.x that prints a deprecation notice and execs `manza`.
- Config path migration (above). `MANZA_*` env with fallback, and `MANZA_STAGING_*`.
- Homebrew: a new `Formula/manza.rb`. Keep `Formula/zazu.rb` as a deprecated formula pointing to `manza` (`deprecate!`).
- Help text "Manza CLI". Update the README and SECURITY/CONTRIBUTING.
- `npm deprecate` on `@getzazu/cli*`.

## Phase 5 — app follow-ups (getmanza/app, separate PRs)

- Docs (`market_examples.rb`, `clients.rb`, `testing.rb`): use the new package names and `MANZA_*` env, and `MANZA_BASE_URL` rather than `MANZA_API_BASE`.
- OpenAPI `servers:` lists the `manza.finance` / `manza.dev` hosts. Drop the stale `api.zazu.africa` in `docs_kit.rb`.
- The SDK usage metric maps the `manza-*` User-Agent tokens.

## Order and gating

Phase 0 (manual), then Phase 1 → 2 (Ruby), then Phase 3 (7 SDKs in parallel), then Phase 4 (CLI), then Phase 5.

## Verification

- Every repo: CI green replaying `cassettes-v1.0.0` from `getmanza/manza-ruby`.
- `grep -rIi zazu` returns only intentional hits: the env fallback, the CLI shim, config migration, CHANGELOG history and migration docs.
- Install smoke test from each registry under the new name, in a clean environment (`gem install manza`, `npm i @getmanza/sdk`, `pip install manza`, `go get github.com/getmanza/manza-go@v1.0.0`, `composer require manza/manza-php`, `cargo add manza`, `mix` dep `{:manza, "~> 1.0"}`, shard `github: getmanza/manza-crystal`, `brew install getmanza/tap/manza`).
- Old names: an install shows the deprecation notice.

## Open questions (non-blocking; answer before Phase 1)

1. Confirm that the default base URL is `ma.manza.finance` (decided above). It is served today, even though `ZAZU_WEB_HOST` has not cut over yet (#2894).

