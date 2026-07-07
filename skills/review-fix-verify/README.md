# review-fix-verify

Multi-model "review → fix → verify → iterate" workflow as a Copilot CLI skill.

> **Source of truth:** [`SKILL.md`](SKILL.md) is the authoritative execution contract
> (phases, prompts, model matrix). This README describes user-facing behavior and
> limitations. When they diverge, `SKILL.md` wins.

## What it does

1. **Fan-out review** — launches 2 `code-review` subagents (3 with `--thorough`) in parallel, each on a different fast model, demanding high-signal findings only (real bugs, races, security issues — no style/nits). Reviewers read surrounding code for context to cut false positives.
2. **Consolidate** — orchestrator deduplicates findings, re-calibrates severity with own judgment, and produces an explicit ACCEPT/REJECT verdict table. Refactoring suggestions from reviewers are surfaced as a non-blocking appendix (not sent to the builder).
3. **Fix** — one `general-purpose` builder subagent applies the accepted fixes and runs the repo's own test suite until green.
4. **Verify** — a `code-review` verifier on a _different_ model than the builder reviews **only the fix diff** (`git diff HEAD`), checking each fix is correct and looking hard for regressions.
5. **Iterate** — if the verifier finds real issues, the orchestrator first tries an inline fix for small/obvious regressions (≤ 10 lines); otherwise loops back to a new builder subagent (max 2 iterations).
6. **Finalize** — runs the full test suite, then stops and summarizes. **Commit is opt-in** — the default is to stop and let you commit manually.

The critical insight: **the verifier reviews the fix diff, not the original code.** In real runs this has caught concurrency regressions that the fix itself introduced.

## When it triggers

- `/review-fix-verify [path|range]`
- "review and fix", "review fix verify", "rfv"
- "multi-model review", "parallel code review"
- "review my changes [and fix them]"

## Model matrix

| Role | Model | Effort |
|------|-------|--------|
| Reviewer A | `claude-sonnet-4.6` | medium |
| Reviewer B | `gpt-5.3-codex` | medium |
| Reviewer C (`--thorough`) | `gemini-3.5-flash` | medium |
| Reviewer (`--fast`) | `gemini-3.5-flash` | low |
| Builder | `claude-sonnet-4.6` | medium |
| Builder (`--thorough`) | `claude-opus-4.8` | high |
| Builder (`--fast`) | `gemini-3.5-flash` | low |
| Verifier | `gpt-5.4-mini` | medium |

**Modes:** default = 2 reviewers + sonnet builder + mini verifier. `--fast` = 1 reviewer, flash builder, no verifier. `--thorough` = 3 reviewers, opus builder. Override any model by stating it in your request.

## Example invocations

```
# Review uncommitted changes
review and fix

# Fast mode (1 reviewer, lighter builder, no verifier)
rfv --fast

# Review specific path
/review-fix-verify src/api/

# Review last 3 commits
/review-fix-verify HEAD~3..HEAD

# With model override
review fix verify, use gemini for the builder

# Full invocation
rfv — focus on src/payments/, use codex as reviewer B
```

## Diff scope (in order of priority)

1. Caller-specified path or range
2. Uncommitted changes (`git diff HEAD`)
3. `git diff HEAD~1..HEAD` if nothing uncommitted and 2+ commits exist

## What success looks like

A successful run produces a summary like:

```
## review-fix-verify — Summary

Scope: uncommitted changes (42 lines)
Iterations: 1

Findings reviewed
| # | file:line      | Severity | Decision |
|---|----------------|----------|----------|
| 1 | src/auth.go:88 | HIGH     | ACCEPT   |
| 2 | src/util.py:12 | LOW      | REJECT   |

Fixes applied
- src/auth.go:88 — added nil check before pointer dereference

Verification
Finding 1: VERIFIED ✓
No regressions found.

Test result
PASS — all 124 tests green
```

The finding table shows every issue each reviewer raised and the orchestrator's
explicit ACCEPT/REJECT decision with reasoning. Style nits and false positives are
rejected before they ever reach the builder.

## Examples of accepted vs rejected findings

**Accepted (real bugs):**
- Nil pointer dereference on an untested code path
- Race condition: shared map written from two goroutines without a lock
- SQL query built with string concatenation (injection risk)
- Error return silently discarded in a critical path

**Rejected (not actionable by this skill):**
- "Consider using `const` instead of `let`" — style preference, not a bug
- "This loop could be rewritten as a `map()`" — refactor suggestion
- "Missing docstring" — documentation, not correctness
- Flagging a nil-check as missing when the caller always provides a non-nil value

## How large is too large?

- **< 200 lines** — ideal. All reviewers get the full diff plus surrounding context.
- **200–800 lines** — manageable. Reviewers will read carefully but may miss edge interactions.
- **> 800 lines** — `rfv-prep.sh` emits `RFV_WARN: large diff`. The skill will warn
  you and offer to scope down. You can proceed, but quality degrades as reviewers
  must skim. Better approach: split by directory (`/review-fix-verify src/api/`) or
  by commit range (`/review-fix-verify HEAD~2..HEAD~1`).

Diff output is also capped at `RFV_MAX_DIFF_LINES` (default 500) in the prompt to
avoid token budget exhaustion. Set the env var to increase the cap if needed.

## When not to use this skill

- **No git history** — the skill requires a git repo with at least one commit.
- **Pure refactors with no behavior change** — reviewers will find nothing meaningful
  to flag. Use a regular code review instead.
- **Trivial one-line fixes** — the overhead of 2–3 model reviews isn't worth it.
- **Diffs containing secrets** — if `.env` files or credential files are in scope,
  remove them from the diff first. See the Security section in `SKILL.md`.
- **Production deployments** — the skill runs tests locally. It does not verify
  behavior in production and must never be used to drive production actions.

## Known limitations

- **Model availability** — if a reviewer model is unavailable at runtime, that reviewer
  is dropped. A single reviewer can still produce useful output.
- **Test detection** — `rfv-prep.sh` auto-detects the test command for 14+ ecosystems,
  but exotic setups (monorepos, custom test harnesses) may need manual override.
- **Binary files** — the diff stat counts binary files as 1 line each for size
  estimation. Large binary changes may be undercounted for the 800-line warning.
- **False negatives** — reviewers use "medium" effort fast models. They may miss
  subtle logic bugs in complex code. The skill reduces defect density; it is not
  a correctness proof.
- **Iteration cap** — the skill stops after 2 fix/verify loops. Persistent issues
  after 2 iterations are reported to you for manual resolution.

## Notes

- Builder does **not** commit and is bounded (max 3 test-fix cycles). Finalize phase gives you the commit choice.
- `rfv-prep.sh` runs once in Phase 0: guards non-repo/empty/large diffs, computes the diff, and auto-detects the test command across ecosystems: Node (`package.json`), Make, Go, Rust, Python (`pyproject.toml`/`setup.py`/`requirements.txt`), Java Maven/Gradle, .NET, Swift, Ruby, PHP (Composer), Elixir.
- The script is located at `${AGENTS_DIR:-$HOME/.agents}/skills/review-fix-verify/rfv-prep.sh`. Set `AGENTS_DIR` if your skills are installed elsewhere.
- Reviewers read surrounding code for context (not just the diff hunk) to cut false positives.
- Iteration is bounded (max 2) and carries prior context so fixes aren't undone.
- If a model is unavailable, drops that reviewer and continues.
- Custom agent personas are optional — the `task` tool's model overrides on built-in agent types cover the same ground. See "Optional: custom agent personas" in `SKILL.md`.
