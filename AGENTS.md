# manza-ruby

Ruby SDK for the Manza API (gem `manza`, formerly `zazu-ruby`). **Reference implementation** for the cross-language SDK family — the Ruby SDK records cassettes against `ma.manza.dev` (staging) and ships them as a release tarball. Every other SDK (manza-ts, cli, manza-python, manza-go, …) replays those cassettes.

Project instructions for every agent: Claude Code (`CLAUDE.md` imports this file); other agents read this file directly. Claude's workflow comes from the `flow` plugin (`.claude/settings.json`), which acts on the facts in `## Workflow` below.

## Stack

| Concern | Tool | Notes |
|---|---|---|
| Language | Ruby ≥ 3.3 (matrix: 3.3, 3.4, 4.0) | `manza.gemspec` `required_ruby_version` |
| HTTP | Faraday + HTTPX adapter (replay uses `:net_http`) | `lib/manza/client.rb` — see "Critical rules" |
| Tests | RSpec | `spec/` |
| Cassettes | VCR + WebMock | `spec/support/vcr.rb` |
| Lint | Rubocop + rubocop-rspec + rubocop-performance + rubocop-rake | `.rubocop.yml` |
| Build / package mgmt | Bundler | `Gemfile`, `bundle install` |
| Release | `bin/release` | zoolutions release kit (`bin/release` + `rakelib/release.rake`, synced from docs-kit — never edit in place); OIDC trusted publishing |

## Public API surface

```ruby
manza = Manza::Client.new(api_key: "sk_live_...")

manza.entity.get
manza.accounts.list(currency_code: "MAD")
manza.accounts.list_transactions(account_id)
manza.customers.list(q: "Acme")
manza.customers.create(...)
manza.invoices.list
manza.payment_links.cancel(id)
manza.webhook_endpoints.list
manza.checkout_sessions.create(...)
manza.beneficiaries.list
manza.payee_trust_requests.create(external_account_ids: [...])
manza.transfer_drafts.create(...)
```

- `Manza::Page` — cursor-based pagination, hard cap of 100/page (`MAX_PER_PAGE`)
- 10-class `Manza::Error` hierarchy — discriminate via `is_a?(Manza::ValidationError)`, never status-code matching
- Snake-case wire format — request/response bodies are returned as-is. **No auto-camelCasing.**

## How to work in this codebase

1. **Tests come first.** Every change to `lib/` ships with a spec. Cassette-replay tests are the contract — they enforce the same wire format across Ruby, TS, and future SDKs.
2. **Use the SDK's primitives.** `Manza::Page`, `Manza::Error` subclasses, the `Resources::Base` http_get/post/patch/delete helpers, `encode_path` for URL construction. Don't hand-roll Faraday calls or string-interpolate URLs.
3. **Snake-case stays.** Response keys are wire-format. We don't camelCase them.
4. **Rubocop must be clean.** `bundle exec rubocop` is gated in CI. Don't add `# rubocop:disable` to silence — fix the issue. `Metrics` is intentionally disabled (long methods are sometimes the right answer in a thin SDK); don't fight that. A `Metrics` offense means an inline `# rubocop:enable Metrics/…` crept in.

## Critical rules

- **HTTPX adapter for production, `net_http` for cassette recording.** `lib/manza/client.rb` swaps to `net_http` when `VCR_RECORD` is set because the HTTPX webmock plugin layered with VCR's webmock library hook deadlocks on the first real request. This was painful to find — preserve it.
- **`bundle exec rake default` before every commit.** Runs spec + rubocop. CI runs the same.
- **No long-lived RubyGems API key.** Releases publish via OIDC trusted publishing through the `rubygems` GitHub environment. Verify the binding on https://rubygems.org/profile/me → Trusted publishers if it ever drifts (a publish 404 means repo, workflow `release.yml` or environment no longer match exactly).
- **Cassettes are scrubbed.** `spec/support/vcr.rb` strips `Authorization`, `X-Request-Id`, `Manza-Version`/`Zazu-Version`, and every `ENV["MANZA_FIXTURE_*"]` value. Even if a developer commits a real key by accident, the cassette is clean. Don't disable the scrubbers.
- **Fixture IDs go through `fixture_id()`.** Defined in `spec/support/fixture_ids.rb`. Specs call `fixture_id("MANZA_FIXTURE_X")` which returns `ENV[X]` when set or a deterministic placeholder when not. The placeholder is what VCR scrubs to, so cassettes replay everywhere. A new fixture env var goes into that file's `IDS` table.
- **A replay mismatch is fixed, never silenced.** Read `spec/support/vcr.rb` and `spec/support/fixture_ids.rb` before touching cassettes. Re-record (`rake fixtures:record`) or fix the matcher in `vcr.rb`; never a `record: :new_episodes` override, and never mocks in place of cassettes (the other SDKs replay the same files).
- **Snake-case wire format.** API request/response bodies use snake_case. Don't transform them.
- **No new error classes without updating other SDKs.** The 10-class hierarchy is shared across SDKs. Adding to it means coordinating manza-ruby + manza-ts at minimum.
- **Public API breaks are deliberate.** A change that breaks the gem's public API or its compatibility with the Manza API is made only on purpose, named in `CHANGELOG.md` and released as a major version.
- **`Dotenv.overload`, not `Dotenv.load`.** A stale shell-exported `MANZA_FIXTURE_*` variable will mask the freshly-seeded value otherwise. Both `spec_helper.rb` and `lib/tasks/fixtures.rake` do this.
- **Staging fixture state is agents' to fix, never production.** Before `rake fixtures:record`, bring MA staging to the declared state yourself ("Staging fixture state" below) without asking. The `sdk_fixtures_*` tools exist on staging only; never point any of it at a production host.
- **Never escape backticks in PR bodies.** With `<<'EOF'` (single-quoted heredoc) the shell passes everything through verbatim. Typing `` \` `` produces literal `` \` `` in the rendered PR. See "PR descriptions" below.

## PR descriptions

Write PR description bodies in plain Markdown. **Do not escape backticks** with `` \` `` — GitHub renders `` \` `` literally as a backslash followed by a backtick, producing output like `` \`Manza::Page\` `` instead of the monospace `Manza::Page` the reader expects.

The usual cause is writing the description inside a bash heredoc (`gh pr create --body "$(cat <<'EOF' ... EOF)"`) and then reflexively escaping every backtick because of shell-quoting muscle memory. With `<<'EOF'` (single-quoted delimiter) the shell does NOT interpret anything inside the heredoc — backticks, dollars, and backslashes all pass through verbatim. So write them exactly as you want them rendered:

```bash
# Good — renders as `Manza::Page` in monospace
gh pr create --body "$(cat <<'EOF'
Uses the `Manza::Page` helper.
EOF
)"

# Bad — renders as \`Manza::Page\` literally in the PR body
gh pr create --body "$(cat <<'EOF'
Uses the \`Manza::Page\` helper.
EOF
)"
```

Same rule for code blocks — write triple-backticks unescaped. The single-quoted heredoc delimiter is doing all the shell-escaping work. If you find yourself typing `` \` `` inside a PR body, stop and remove the backslash.

## Striving for excellence

These are the Karpathy guidelines we apply on every change. They reduce common LLM coding mistakes.

### 1. Think before coding

Don't assume. Don't hide confusion. Surface tradeoffs.

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity first

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Senior engineer test: would they call this overcomplicated?

### 3. Surgical changes

Touch only what you must. Clean up only your own mess.

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/methods that *your* changes orphaned. Don't remove pre-existing dead code unless asked.

### 4. Goal-driven execution

Define success criteria. Loop until verified.

- "Add validation" → "Write specs for invalid inputs, then make them pass"
- "Fix the bug" → "Write a spec that reproduces it, then make it pass"
- "Refactor X" → "Ensure specs pass before and after"

For multi-step tasks, state a brief plan with verification at each step.

## Development workflow

```bash
# One-time setup
bundle install
bin/rename-env-vars    # existing .env from before 1.0: ZAZU_* → MANZA_* (backup in .env.bak)
cp .env.example .env   # fresh setup only; then fill in MANZA_STAGING_API_KEY for cassette recording

# Daily loop
bundle exec rspec spec/manza/path/to_spec.rb    # while iterating
bundle exec rspec                              # full suite
bundle exec rubocop                            # lint
bundle exec rake default                       # spec + rubocop, the canonical pre-commit check

# Re-record cassettes (only when the wire format actually changed)
# First bring staging to the declared state: "Staging fixture state" below
bundle exec rake fixtures:record               # preflight → teardown → seed → record
bundle exec rspec                              # verify replay-only is green

# Release (after PR merge, from a clean, up-to-date main)
bin/release list        # last releases + what patch/minor/major would give
bin/release --dry-run   # version + changes since the last tag, publishes nothing
bin/release minor       # or patch (default), major, an explicit 0.3.0; --force re-creates
# → rake release[X.Y.Z]: bumps version.rb, pushes main, publishes the GH release
# → release.yml: RubyGems publish + sigstore attestation (shared kit file)
# → cassettes.yml: cassette tarball uploaded as a release asset for other-language SDKs
```

## Staging fixture state

`rake fixtures:record` needs the MA staging fixture entity in a declared state: API flags on, both keys with their scopes and this machine's addresses allowlisted, the transfer authorizer active with its limits and the new-payee toggle on. The declared state is `lib/tasks/staging_fixture_state.json` (not in the gem). Staging drifts (a suspended authorizer, a toggle off, a key without an allowlist); fixing it is the agent's job.

The `manza` MCP server (`.mcp.json`, the gateway at `https://mcp.manza.work/mcp`) exposes the staging-only `sdk_fixtures_*` tools (runbook: getmanza/app `docs/runbooks/sdk-fixtures.md`). Auth is the staff member's Google sign-in, once per machine via `/mcp`; `.claude/settings.json` enables the project server (`enabledMcpjsonServers`), which Claude Code honours once the workspace is trusted: a fresh clone asks to trust the folder first, then needs no separate server approval. There is no MCP token, and none goes in `.env`. Call the `ma_staging` tools (`mcp__manza__ma_staging__sdk_fixtures_*`), never `za_staging`.

Before every `rake fixtures:record`:

1. `bundle exec rake fixtures:staging:ensure_arguments` prints the `sdk_fixtures_ensure` arguments as JSON: both 16-character `key_prefix`es from `.env`, `desired` from the JSON file, and this machine's public IPv4 `/32` and IPv6 `/64` (looked up through ipify) on both keys. The lookup is best effort: a family that fails (no IPv6 on this network, ipify down) is left out with a warning on stderr, and the task aborts only when both fail. Check `desired.creator_key_cidrs` holds what this machine records from, and pass `CIDR=<a>[,<b>]` to replace the lookup when it does not. Never print more than 16 characters of a key.
2. `sdk_fixtures_status` with the two prefixes from step 1, to see the drift. Its `observed_ip` is the gateway's egress, not this machine: never allowlist it.
3. `sdk_fixtures_ensure` with the JSON from step 1; `dry_run: true` first if anything looks off. Every line `unchanged` or `changed` is done.
4. A `failed` `authorizer.secret_expires_at` line: `sdk_fixtures_rotate_secret`, write the returned secret to `.env` as `MANZA_STAGING_AUTHORIZER_SECRET` with an edit, without echoing it, then ensure again.
5. Any other `failed` line: follow its `fix`. When the tools do not cover it, use `bin/dash app exec -d ma-staging -p -r web --reuse "bin/rails runner '…'"` from `~/Code/manza/app` (its `.ruby-version` Ruby), checking that the destination is `*-staging`, and file a getmanza/app issue to add the gap to the toolset. The same path runs the app's `sdk_fixtures:status` / `sdk_fixtures:ensure` rake tasks when the session has no `manza` MCP tools.
6. `bundle exec rake fixtures:record`. Its `fixtures:preflight` (also run by `fixtures:seed`) reads `GET /api/transfer_authorizer` with the authorizer key and aborts before teardown deletes anything unless the authorizer is `active`. It cannot see the new-payee toggle; ensure covers that.

The one human step left is enrolling the transfer authorizer in the app (OTP). A trusted payee for `MANZA_FIXTURE_BENEFICIARY_ID` is `sdk_fixtures_trust_payee`.

## Workflow

- **Verify:** `bundle exec rake default` (rspec + rubocop, as in CI) · after `rake fixtures:record`: `bundle exec rspec` with `VCR_RECORD` unset
- **Specs:** fast loop `bundle exec rspec <file>`; full suite `bundle exec rspec` (replay: no network, no `.env`); two worktrees at once: yes, one `rake fixtures:record` at a time (it re-seeds the shared staging fixtures)
- **CI:** required none; jobs `test (3.3)` `test (3.4)` `test (4.0)` (`ci.yml`), check `cubic · AI code reviewer`; full suite on the PR; failure report none
- **Review bot:** cubic; push back, citing this file, on mocks instead of cassettes, camelCased wire keys, "method too long" (`Metrics` is off), speculative abstractions
- **Merge:** squash — `gh pr merge <PR> --squash --delete-branch`; fallback after the gate: `--admin` for the required approving review
- **PR contract:** `## Summary` (`Closes #N`), `## Fable validation` (verdict, Not verified), `## Test plan`; backticks unescaped; labels none; screenshots none
- **Conflicts:** `CHANGELOG.md` — both sides under `## [Unreleased]`, main's first; `lib/manza/version.rb` — main's; `spec/fixtures/cassettes/**` — one side whole, or re-record; `bin/release` `rakelib/release.rake`, `release.yml` outside its `test` job — main's (release kit)
- **Worktree setup:** `bundle install` (`Gemfile.lock` is gitignored); undo none
- **Release:** `bin/release [patch|minor|major|X.Y.Z]` from a clean, current main (prompts y/N; unattended `bundle exec rake "release[X.Y.Z]"`) → `release.yml` publishes, `cassettes.yml` attaches `rake fixtures:pack`'s tarball; changelog `CHANGELOG.md`, `[Unreleased]` headed `## [X.Y.Z]` by hand; lockfiles none
- **Main health:** `gh run list --workflow ci.yml --branch main --event push --limit 1 --json conclusion,headSha`
- **Upstream:** libraries we own `getmanza/*`, `zoolutions/*` (release kit); scrub none

## Agent commands

Plugin (`.claude/settings.json`): `/flow:lfg`, `/flow:plan`, `/flow:follow-through`, `/flow:finish-prs`,
`/flow:github-review-pr` (`-failures`, `-comments`; cubic's threads included), `/flow:review-pr`,
`/flow:tdd`, `/flow:debug-flaky`, the `flow:fable-validator` agent. No local commands.

**Models.** Sessions run on `opus` with `fable` as the advisor (`.claude/settings.json`); consult it
before choosing an approach, a schema or public API, a migration, a dependency, anything
irreversible, and when a failure repeats. Every spawned agent names its `model:`; one that does not
runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL`), never on the session's model.

## Cross-SDK contract

This repo is the source of truth:

- Records cassettes against `ma.manza.dev` (staging)
- Ships them as a release tarball (`cassettes-vX.Y.Z.tar.gz`) on each version
- All other SDKs (`manza-ts`, `manza-python`, `manza-go`, `manza-php`, `manza-crystal`, `manza-elixir`, `manza-rust`) replay these cassettes in their own test harness

If the contract breaks (e.g., new request shape), it's a coordinated change across at least two repos: manza-ruby and manza-ts.

## Repository links

- This repo: https://github.com/getmanza/manza-ruby
- RubyGems: https://rubygems.org/gems/manza
- TypeScript SDK: https://github.com/getmanza/manza-ts (https://www.npmjs.com/package/@getmanza/sdk)
- CLI consumer: https://github.com/getmanza/cli
