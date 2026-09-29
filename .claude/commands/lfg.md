---
description: "Executes full autonomous engineering workflow with verification. Use when implementing complete features, tackling GitHub issues, or running end-to-end development cycles."
model: opus
argument-hint: "GitHub issue number/URL or feature description"
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(bundle exec:*), Bash(bundle install:*), Bash(rake:*), Bash(git:*), Read, Write, Edit, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskList
---

# LFG — full autonomous workflow

Execute a complete engineering workflow with verification at each phase. The phases below exist because skipping any one of them has caused a production bug at least once — the checklist is load-bearing.

## Phase 0: Branch setup

1. `git branch --show-current`
2. If not on `main`: `git checkout main`
3. `git pull origin main`
4. `git checkout -b issue-{number}-{brief-description}` (or `feature/{description}` if no issue)

## Phase 1: Understand

If `$ARGUMENTS` is a GitHub issue number/URL:

```bash
gh issue view <number> --json title,body,labels,assignees,comments
```

Define explicit acceptance criteria (GIVEN / WHEN / THEN). Don't proceed until you can articulate them.

**Comprehension gate** — answer all five before writing code:

1. State the problem in one sentence.
2. Why is it needed?
3. What changes from the user's perspective?
4. What edge cases aren't explicit?
5. What data flow / code path is involved?

Use `TaskCreate` to record steps; update with `TaskUpdate` as you go.

## Phase 2: Explore

1. Find related files (Glob/Grep, or the Explore agent, `model: haiku`, for broad searches).
2. Read existing patterns in `lib/zazu/`. The reference implementation is conservative — match it.
3. Check existing test coverage in `spec/zazu/`.
4. If touching cassettes: read `spec/support/vcr.rb` and `spec/support/fixture_ids.rb` first.

## Phase 3: Plan

1. List files to modify.
2. List new files to create.
3. Plan test coverage (tests first).
4. Update the task list.

## Phase 4: Implement (TDD)

For each logical unit:

### 4.1 Failing test first

Add a new spec under `spec/zazu/`. Confirm it fails for the right reason:

```bash
bundle exec rspec path/to/spec.rb
```

### 4.2 Minimum implementation

Project conventions:

| Use | Instead of |
|-----|-----------|
| `Resources::Base` http_get/post/patch/delete helpers | direct `Faraday` calls |
| `encode_path("api/foo", id)` | string interpolation in URLs |
| `Page` from `lib/zazu/page.rb` | manual cursor loop |
| Specific error subclasses (`Zazu::ValidationError` etc.) | rescuing `Zazu::Error` and matching status |
| `fixture_id("ZAZU_FIXTURE_X")` in specs | `ENV.fetch("ZAZU_FIXTURE_X", "fallback")` |
| Snake-case wire format | re-mapping keys |
| `Dotenv.overload` (already wired in spec_helper) | `dotenv/load` |

### 4.3 Refactor

Once green, refactor with tests still passing.

### 4.4 Validate

```bash
bundle exec rspec                  # all specs
bundle exec rubocop -A             # auto-fix style
bundle exec rake default           # spec + rubocop
```

### 4.5 Repeat

Move to the next unit. Mark task items complete as you finish them.

## Phase 5: Deep root-cause analysis (bug fixes only)

For bug fixes, investigate before implementing:

- **Trace the data lifecycle** — where was the value created, how did it reach the failure point, what assumption broke?
- **Use git history** — `git log --oneline -20 <file>`, `git blame <file>`. Was a guard there before?
- **Map callers** — grep for callers of the failing method; does the bug only show up in one context?
- **Five whys** — keep asking "why" until you reach a meaningful fix point.

**Fix-location principle**: the best fix is rarely where the error is raised. Ask "where is the earliest point I could prevent this error?" Fix there.

**Superficial fixes to avoid**:
- `&.` chaining without understanding why nil occurs
- `rescue nil` to silence an exception
- Changing `find` to `find_by` to swap an exception for a nil
- `if value.present?` guards added because the value was unexpectedly missing

## Phase 6: Verify

All must pass before committing:

```bash
bundle exec rspec                  # tests
bundle exec rubocop                # style + performance + rake + rspec cops
bundle exec rake default           # convenience: spec + rubocop together
```

If you re-recorded cassettes (`bundle exec rake fixtures:record`), also verify replay-only is green:

```bash
bundle exec rspec                  # without VCR_RECORD; must replay clean
```

Re-read the original requirements: would the requester consider this fully resolved? Have you addressed the root cause? Do the tests prove the fix?

## Phase 6.5: Fable validation

Spawn the `fable-validator` agent (it is pinned to Fable) with the issue, the acceptance criteria from Phase 1 and the base branch. On **BLOCK**, fix every blocker (back to Phase 4 for code, with a failing test first), re-verify, and run the validator again. On **PASS WITH NOTES**, fix the risks you agree with and list the rest in the pull request under "Accepted risks". If those fixes change the diff, re-verify and run the validator again. Put the validator's one-line verdict and its "Not verified" list in the pull request body. Do not open the pull request before a PASS or PASS WITH NOTES.

## Phase 7: Commit and PR

**Backticks in PR bodies pass through `<<'EOF'` heredocs verbatim — do NOT escape them with `` \` ``.** See the "PR descriptions" section in `CLAUDE.md`.

```bash
git add <specific_files>
git commit -m "$(cat <<'EOF'
feat(scope): brief description

## Summary
[What changed and why]

## Test Coverage
- spec 1: validates requirement X
- spec 2: validates edge case Y

## Verification
- [x] bundle exec rspec
- [x] bundle exec rubocop
EOF
)"

git push -u origin $(git branch --show-current)

gh pr create --title "feat(scope): brief description" --body "$(cat <<'EOF'
## Summary
- Key change 1 — uses `Page#next` from the SDK
- Key change 2

Closes #<issue_number>

## Test plan
- [ ] Scenario 1
- [ ] Scenario 2
EOF
)"
```

If you typed `` \` `` anywhere in the body, delete the backslash. The single-quoted EOF delimiter is doing all the shell-escaping work.

## Verification checklist

- [ ] All acceptance criteria met.
- [ ] Tests written before implementation.
- [ ] `bundle exec rspec` passes.
- [ ] `bundle exec rubocop` passes (no offenses).
- [ ] Cassettes (if recorded) replay clean.
- [ ] Public API unchanged unless intentional.
- [ ] `fable-validator` verdict is PASS or PASS WITH NOTES (Phase 6.5), and it is in the PR body.
- [ ] PR created with description.

## Karpathy guidelines (always)

These reduce common LLM coding mistakes. Apply on every change, not just LFG runs:

1. **Think before coding** — surface assumptions, push back on overcomplication, ask when unclear.
2. **Simplicity first** — minimum code that solves the problem, no speculative abstractions.
3. **Surgical changes** — touch only what you must; clean up your own orphans, not pre-existing dead code.
4. **Goal-driven execution** — define success criteria as a verifiable test, loop until verified.
