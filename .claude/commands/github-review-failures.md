---
description: "Use when CI checks are failing on a PR — fetches failure logs, diagnoses root causes, implements fixes, pushes until CI is green."
model: opus
argument-hint: "PR number (e.g., 1690 or #1690)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(gh run view:*), Bash(git log:*), Bash(git diff:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(bundle exec:*), Bash(bundle install:*), Bash(rake:*), Read, Write, Edit, Glob, Grep, Agent
---

# Fix GitHub CI Failures: $ARGUMENTS

Diagnose and fix CI failures. Work systematically: identify failures → read logs → diagnose root cause → fix locally → verify → push.

## Phase 0: Determine the PR

Number → PR. `#N` → strip `#`. Empty → current branch (`gh pr view --json number`).

## Phase 1: Inventory failures

```bash
gh pr checks <PR>
```

For each failing check, get the run id and load the failed logs:

```bash
gh run view <run-id> --log-failed
```

Categorize:
- **Spec failures** — assertion failed, VCR replay mismatch, fixture-id mismatch
- **Rubocop failures** — style or new-cop violation
- **Cassette replay failures** — VCR rejected an unmatched request (URL or body drift)
- **Release / publish failures** — RubyGems trusted publishing OIDC, sigstore
- **Ruby version matrix** — 3.3 / 3.4 / 4.0 mismatch

## Phase 2: Diagnose

Read the actual error message, not the surrounding noise. The first line that points at our code is usually the culprit.

For each failure:

### Reproduce locally

```bash
# Spec
bundle exec rspec path/to/spec.rb

# Rubocop
bundle exec rubocop

# Full pipeline
bundle exec rake default

# Cassette re-record (only if a real API change happened)
bundle exec rake fixtures:record    # then verify replay
bundle exec rspec
```

If you can't reproduce locally, the failure is environmental (CI-only):
- Different Ruby version → check `.tool-versions` and the workflow `ruby-version`
- Missing dependency → did `bundle install` actually run?
- Network → external service (RubyGems registry, staging API) hiccup
- Secret missing → e.g. trusted-publishing OIDC environment, MANZA_STAGING_* secrets
- Concurrency → fixture seeder colliding with a parallel run

### Find the root cause

Apply the five-whys ladder until you reach a fix point that prevents the same class of failure recurring. Don't:

- Skip the failing spec with `xit`
- Add a `# rubocop:disable` to silence the linter (use the right idiom instead)
- Change `find` to `find_by` so the NotFoundError stops surfacing
- Set `record: :new_episodes` to silence a VCR mismatch

These hide the failure; the underlying bug returns elsewhere.

## Phase 3: Fix and verify

### 3.1 Implement the fix

Touch only what the failure cites, plus what the fix requires.

### 3.2 Run the equivalent local check

The CI step that failed has a local equivalent — run it, get green:

| CI step | Local equivalent |
|---|---|
| `bundle exec rspec` | `bundle exec rspec` |
| `bundle exec rubocop` | `bundle exec rubocop` |
| `bundle exec rake default` | `bundle exec rake default` |
| Trusted-publishing publish | requires OIDC environment — verify via release workflow |
| Cassette tarball pack | `bundle exec rake fixtures:pack` |

### 3.3 Run the full pipeline

```bash
bundle exec rake default
```

### 3.4 Commit + push

```bash
git add <files>
git commit -m "fix(ci): <what was failing>

<root cause and how this addresses it>"
git push origin <branch>
```

Use `fix:` for prod fixes, `chore(ci):` for workflow / config changes.

## Phase 4: Watch the next run

```bash
gh pr checks <PR> --watch
# or
gh run watch <run-id> --exit-status
```

Track until green. If the same step fails again with a different error, repeat. If it fails the same way, your fix is wrong — revert and rethink.

## Phase 5: Verify and document

```bash
gh pr checks <PR>            # all green
gh pr view <PR> --json mergeable,reviewDecision
```

If the failure was CI-config drift (workflow YAML out of sync with reality), also update relevant docs:
- `.tool-versions`
- `manza.gemspec` `required_ruby_version`
- `CLAUDE.md` if a convention changed

## Common patterns and fixes

### VCR rejected an unmatched request

The recorded URL or body drifted from what the SDK now sends. Either:
- Re-record cassettes via `bundle exec rake fixtures:record` (and ship a new release if the wire format changed)
- Adjust the matcher in `spec/support/vcr.rb`
- Check `spec/support/fixture_ids.rb` — if a new env var is needed, add it to the canonical table

### Trusted-publishing returned 404 from RubyGems

The trusted-publisher binding on rubygems.org must match `(repo, workflow, environment)` exactly. Check https://rubygems.org/profile/me → Trusted publishers.

### `Metrics/ClassLength` after refactor

We deliberately disable Metrics in `.rubocop.yml`. If a rubocop run flags it, something has re-enabled the cop locally — check that no inline `# rubocop:enable Metrics/...` is in the file.

## Karpathy guidelines

- **Think before coding** — read the actual error, don't pattern-match on the first guess.
- **Goal-driven execution** — the green CI check is the verification.
- **Surgical changes** — fix the failing class of error, not adjacent things.
