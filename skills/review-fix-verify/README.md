# review-fix-verify

Multi-model review -> fix -> verify workflow for Git changes.
[`SKILL.md`](SKILL.md) is the execution contract; this file is user-facing.

## Workflow

1. **Preflight** - scopes and caps the diff, rejects incomplete or sensitive input,
   and detects repository commands.
2. **Review** - runs Sonnet and Terra reviewers in parallel; correctness findings
   only.
3. **Consolidate** - validates, deduplicates, and accepts or rejects each finding.
4. **Fix** - runs one bounded Sonnet builder against accepted findings.
5. **Verify** - compares the worktree to a pre-fix snapshot so Terra reviews only
   changes made by the fix cycle.
6. **Iterate** - retries at most twice, then summarizes. Commit is opt-in; push is
   never automatic.

## Invocation

```text
review and fix
rfv --fast
/review-fix-verify src/api/
/review-fix-verify HEAD~3..HEAD
rfv src/payments/ --thorough
```

Triggers also include "review fix verify", "multi-model review", "parallel code
review", and "review my changes".

## Modes

| Mode | Review | Builder | Verify |
|------|--------|---------|--------|
| Default | Sonnet + Terra, low | Sonnet, medium | Terra, low |
| `--fast` | Terra, low | Sonnet, low | skipped |
| `--thorough` | Sonnet + Terra, medium | Sonnet, high | Terra, low |

Models: `claude-sonnet-5` and `gpt-5.6-terra`. Explicit overrides are resolved
before review and rejected if builder and verifier would match. `--fast` and
`--thorough` cannot be combined.

## Diff scope

Priority:

1. Explicit path or Git range
2. Staged and unstaged tracked changes
3. `HEAD~1..HEAD` when the working tree is clean

Untracked files are absent from `git diff`. Working-tree reviews stop and name the
first relevant untracked file; stage it before rerunning. Explicit ranges ignore
untracked working-tree files.

The preflight rejects common sensitive paths such as `.env`, private keys,
credential files, and package-manager auth files before emitting diff contents.
Template suffixes (`.example`, `.sample`, `.template`) remain reviewable.

## Size and context

- Under 200 changed lines: ideal.
- 200-800: supported; reviewers open only code needed to validate findings.
- Over 800: RFV asks whether to narrow by directory or commit.

Prompt diff output is capped by `RFV_MAX_DIFF_LINES` (default `500`). The value
must be a positive integer. Increase it only when the extra context is necessary.

## Command detection

`rfv-prep.sh` finds the nearest project root for the invocation or path scope and
emits `RFV_COMMAND_DIR` plus structured `RFV_*_CMD` markers. `RFV_TEST_CMD` is
authoritative; lint, typecheck, check, and build commands are advisory.

Supported roots:

- Node (`package.json`; npm, pnpm, Yarn, or Bun)
- Make
- Go, Rust, Python
- Maven, Gradle, .NET, Swift
- Ruby, PHP Composer, Elixir

Node parsing uses `jq`. Monorepos, polyglot roots, and custom test harnesses may
need an explicit test command.

## Review standard

Accepted findings must be real bugs, correctness failures, races, vulnerabilities,
resource leaks, panic/null risks, or broken invariants. Style, naming,
documentation, speculative refactors, and micro-optimizations are rejected.

The builder gets only accepted findings and is instructed not to commit, push,
deploy, alter dependencies, bypass checks, or use production credentials. Tests
get at most three fix cycles; fix/verify gets at most two iterations.

## Result

```text
## review-fix-verify - Summary
Scope: uncommitted changes
Iterations: 1

Findings reviewed
| # | file:line | Severity | Decision |

Fixes applied
...

Verification
...

Test result
PASS - concise output
```

If reviewers find nothing, RFV stops without running tests or asking to commit.

## Limitations

- A single remaining reviewer can continue if the other model is unavailable.
- Binary changes count as one changed line for sizing.
- Model review reduces defect risk; it is not a proof of correctness.
- Production commands and diffs containing secrets or PII remain out of scope.
