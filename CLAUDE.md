# manza-ruby

Ruby SDK for the Manza API (gem `manza`, formerly `zazu-ruby`). **Reference implementation** for the cross-language SDK family — the Ruby SDK records cassettes against `ma.manza.dev` (staging) and ships them as a release tarball. Every other SDK (manza-ts, cli, manza-python, manza-go, …) replays those cassettes.

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
```

- `Manza::Page` — cursor-based pagination, hard cap of 100/page (`MAX_PER_PAGE`)
- 10-class `Manza::Error` hierarchy — discriminate via `is_a?(Manza::ValidationError)`, never status-code matching
- Snake-case wire format — request/response bodies are returned as-is. **No auto-camelCasing.**

## How to work in this codebase

1. **Tests come first.** Every change to `lib/` ships with a spec. Cassette-replay tests are the contract — they enforce the same wire format across Ruby, TS, and future SDKs.
2. **Use the SDK's primitives.** `Manza::Page`, `Manza::Error` subclasses, the `Resources::Base` http_get/post/patch/delete helpers, `encode_path` for URL construction. Don't hand-roll Faraday calls or string-interpolate URLs.
3. **Snake-case stays.** Response keys are wire-format. We don't camelCase them.
4. **Rubocop must be clean.** `bundle exec rubocop` is gated in CI. Don't add `# rubocop:disable` to silence — fix the issue. `Metrics` is intentionally disabled (long methods are sometimes the right answer in a thin SDK); don't fight that.

## Critical rules

- **HTTPX adapter for production, `net_http` for cassette recording.** `lib/manza/client.rb` swaps to `net_http` when `VCR_RECORD` is set because the HTTPX webmock plugin layered with VCR's webmock library hook deadlocks on the first real request. This was painful to find — preserve it.
- **`bundle exec rake default` before every commit.** Runs spec + rubocop. CI runs the same.
- **No long-lived RubyGems API key.** Releases publish via OIDC trusted publishing through the `rubygems` GitHub environment. Verify the binding on https://rubygems.org/profile/me → Trusted publishers if it ever drifts.
- **Cassettes are scrubbed.** `spec/support/vcr.rb` strips `Authorization`, `X-Request-Id`, `Manza-Version`/`Zazu-Version`, and every `ENV["MANZA_FIXTURE_*"]` value. Even if a developer commits a real key by accident, the cassette is clean. Don't disable the scrubbers.
- **Fixture IDs go through `fixture_id()`.** Defined in `spec/support/fixture_ids.rb`. Specs call `fixture_id("MANZA_FIXTURE_X")` which returns `ENV[X]` when set or a deterministic placeholder when not. The placeholder is what VCR scrubs to, so cassettes replay everywhere.
- **Snake-case wire format.** API request/response bodies use snake_case. Don't transform them.
- **No new error classes without updating other SDKs.** The 10-class hierarchy is shared across SDKs. Adding to it means coordinating manza-ruby + manza-ts at minimum.
- **`Dotenv.overload`, not `Dotenv.load`.** A stale shell-exported `MANZA_FIXTURE_*` variable will mask the freshly-seeded value otherwise. Both `spec_helper.rb` and `lib/tasks/fixtures.rake` do this.
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
bundle exec rake fixtures:record               # teardown → seed → record
bundle exec rspec                              # verify replay-only is green

# Release (after PR merge, from a clean, up-to-date main)
bin/release list        # last releases + what patch/minor/major would give
bin/release --dry-run   # version + changes since the last tag, publishes nothing
bin/release minor       # or patch (default), major, an explicit 0.3.0; --force re-creates
# → rake release[X.Y.Z]: bumps version.rb, pushes main, publishes the GH release
# → release.yml: RubyGems publish + sigstore attestation (shared kit file)
# → cassettes.yml: cassette tarball uploaded as a release asset for other-language SDKs
```

## Models

Sessions run on `opus` (Opus 5.5) with `fable` (Fable 5.1) as the advisor (`.claude/settings.json`). Fable is spent where judgment matters most: plans are written on Fable, the advisor is consulted at decision points (before choosing an approach, a schema or public API, a migration, a dependency, anything irreversible, and when a failure repeats), and the `fable-validator` agent checks every finished implementation before its pull request opens (`/lfg`, Phase 6.5). Commands pin their tier by alias, never by full model ID: `opus` for orchestration, security, full PR review, payments and production debugging; `sonnet` for the implementation specialists and TDD; `haiku` for mechanical scans. Every spawned agent names its `model:`; one that does not runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL`), never on the session's model. Plan mode cannot take a model of its own: it runs on Opus and asks the advisor.

## Slash commands

These live in `.claude/commands/` and are available in any Claude Code session:

| Command | When |
|---|---|
| `/lfg <issue or feature>` | Full autonomous workflow with TDD + verification |
| `/github-review-pr <PR#>` | Full PR review pass — failures first, then comments |
| `/github-review-failures <PR#>` | Just fix CI failures on a PR |
| `/github-review-comments <PR#>` | Just respond to reviewer comments on a PR |
| `/coderabbit-review <PR#>` | Specifically address CodeRabbit findings (verify, fix valid, push back on stale/wrong) |

## Cross-SDK contract

This repo is the source of truth:

- Records cassettes against `ma.manza.dev` (staging)
- Ships them as a release tarball (`cassettes-vX.Y.Z.tar.gz`) on each version
- All other SDKs (`manza-ts`, `manza-python`, `manza-go`, `manza-php`, `manza-crystal`, `manza-elixir`, `manza-rust`) replay these cassettes in their own test harness

If the contract breaks (e.g., new request shape), it's a coordinated change across at least two repos: manza-ruby and manza-ts.

## Repository links

- This repo: https://github.com/getmanza/manza-ruby
- RubyGems: https://rubygems.org/gems/manza
- TypeScript SDK: https://github.com/getmanza/manza-ts (https://www.npmjs.com/package/@manza/sdk)
- CLI consumer: https://github.com/getmanza/cli
