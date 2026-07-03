# review-fix-verify

Multi-model "review → fix → verify → iterate" workflow as a Copilot CLI skill.

## What it does

1. **Fan-out review** — launches 2 `code-review` subagents (3 with `--thorough`) in parallel, each on a different fast model, demanding high-signal findings only (real bugs, races, security issues — no style/nits). Reviewers read surrounding code for context to cut false positives.
2. **Consolidate** — orchestrator deduplicates findings, re-calibrates severity with own judgment, and produces an explicit ACCEPT/REJECT verdict table.
3. **Fix** — one `general-purpose` builder subagent applies the accepted fixes and runs the repo's own test suite until green.
4. **Verify** — a `code-review` verifier on a _different_ model than the builder reviews **only the fix diff**, checking each fix is correct and looking hard for regressions.
5. **Iterate** — if the verifier finds real issues, loops back to Fix (max 2 iterations).
6. **Finalize** — runs the full test suite, then stops and summarizes (or commits — your choice).

The critical insight: **the verifier reviews the fix diff, not the original code.** In real runs this has caught concurrency regressions that the fix itself introduced.

## When it triggers

- `/review-fix-verify [path|range]`
- "review and fix", "review fix verify", "rfv"
- "multi-model review", "parallel code review"
- "review my changes [and fix them]"

## Model matrix

Reviewers get fast models (they scan); builder/verifier get strong models (they reason).

| Role | Default model | Effort |
|------|--------------|--------|
| Reviewer A | `gemini-3.5-flash` | medium |
| Reviewer B | `gpt-5.4-mini` | medium |
| Reviewer C (`--thorough` only) | `claude-sonnet-4.6` | — |
| Builder | `claude-opus-4.8` | high |
| Verifier | `gpt-5.4` | high |

Default is **2 reviewers**; add `--thorough` for a 3rd. Verifier model is always
different from the builder. Override any model by stating it in your request.

## Example invocations

```
# Review uncommitted changes
review and fix

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
2. Uncommitted changes (`git diff`)
3. `git diff HEAD~1..HEAD` if nothing uncommitted

## Notes

- Builder does **not** commit and is bounded (max 3 test-fix cycles). Finalize phase gives you the commit choice.
- `rfv-prep.sh` runs once in Phase 0: guards non-repo/empty/large diffs, computes the diff, and auto-detects the test command across ecosystems: Node (`package.json`), Make, Go, Rust, Python (`pyproject.toml`/`setup.py`/`requirements.txt`), Java Maven/Gradle, .NET, Swift, Ruby, PHP (Composer), Elixir.
- The script is located at `${AGENTS_DIR:-$HOME/.agents}/skills/review-fix-verify/rfv-prep.sh`. Set `AGENTS_DIR` if your skills are installed elsewhere.
- Reviewers read surrounding code for context (not just the diff hunk) to cut false positives.
- Iteration is bounded (max 2) and carries prior context so fixes aren't undone.
- If a model is unavailable, drops that reviewer and continues.
- Custom agent personas are optional — the `task` tool's model overrides on built-in agent types cover the same ground. See "Optional: custom agent personas" in `SKILL.md`.
