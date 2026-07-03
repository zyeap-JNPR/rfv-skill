---
name: review-fix-verify
description: >
  Multi-model review → fix → verify workflow. Launches 2 (or 3 with --thorough) parallel code-review subagents on different fast models that read surrounding code for context, consolidates findings with orchestrator reasoning, fixes with a bounded builder agent, then verifies the fix diff with a fresh reviewer on a different model. Bounded iteration prevents runaway loops.
  Use when user says "review and fix", "review fix verify", "rfv", "/review-fix-verify", "multi-model review", "parallel code review", or "review my changes".
---

# review-fix-verify Skill

Automates a proven multi-model "review → reason → fix → verify → iterate" workflow. The key insight: the **verifier reviews the fix diff, not the original code** — this catches regressions the builder introduces.

---

## Activation triggers

- `/review-fix-verify [path|range] [--thorough]`
- "review and fix", "review fix verify", "rfv"
- "multi-model review", "parallel code review"
- "review my changes [and fix them]"

`--thorough` (or "be thorough") adds a 3rd reviewer. Default is 2 reviewers.

---

## Model matrix (configurable)

Reviewers scan for patterns — they get **fast** models at medium effort. Builder and
verifier reason deeply — they get **strong** models.

| Role | Default model | Effort | Notes |
|------|--------------|--------|-------|
| Reviewer A | `gemini-3.5-flash` | medium | fast scan |
| Reviewer B | `gpt-5.4-mini` | medium | fast scan |
| Reviewer C | `claude-sonnet-4.6` | — | ONLY on `--thorough` (3rd reviewer) |
| Builder | `claude-opus-4.8` | high | deep reasoning |
| Verifier | `gpt-5.4` | high | MUST differ from builder model |

**Default: 2 reviewers** (A + B). Add reviewer C only when the caller says
`--thorough` or "be thorough" — 3 parallel reviewers cost ~33% more wall-clock for
mostly-overlapping findings.

Override any model by stating it: "use gemini for the builder", "use codex as reviewer B".
If a model is unavailable at runtime, drop that reviewer (a single reviewer still works)
and note it in the summary.

---

## Procedure — execute these phases in order

### Phase 0 — Scope & pre-flight

1. **Run the pre-flight script ONCE** — it computes the diff, its size, and detects
   the test command in a single pass. Reviewers never re-run `git diff` themselves.

   ```bash
   # Resolve script path — respects custom install dir via AGENTS_DIR env var
   "${AGENTS_DIR:-$HOME/.agents}/skills/review-fix-verify/rfv-prep.sh" [scope]
   ```
   - `scope` = a path (`src/api/`), a range (`HEAD~3..HEAD`), or empty for
     uncommitted changes (falls back to `HEAD~1..HEAD` if the tree is clean).

2. **Handle the script's guards:**
   - `RFV_ERROR: not a git repository` → stop, tell the user this skill needs a git repo.
   - `RFV_ERROR: empty diff` → stop, nothing to review.
   - `RFV_WARN: large diff (>800 lines)` → warn the user and offer to scope down
     (per-directory or per-commit) before spending 3 model reviews on it. Proceed
     only if they confirm.

3. **Test command.** Take it from the script's `TEST/LINT COMMANDS` block. Prefer a
   stored memory ("test command", "build command") if one exists. If the script
   detected nothing, ask the user. Confirm the command before Phase 3.

4. **Capture the diff output** from the script into a variable — you will inline it
   as a *starting pointer* in the reviewer prompts (Phase 1). Report scope + line
   count + test command before proceeding.

---

### Phase 1 — Fan-out review (PARALLEL)

Launch **2 `code-review` subagents in parallel** (3 on `--thorough`) in a SINGLE
`task` call block, each pinned to a different model (see matrix) with `effort: medium`.
Inline the diff from Phase 0 into each prompt. Use this template:

> **System role:** You are a senior engineer performing a focused code review. You will NOT modify any code.
>
> **The diff under review (starting pointer — do NOT treat in isolation):**
> ```diff
> {{DIFF_FROM_PHASE_0}}
> ```
>
> **CRITICAL — read for context before flagging.** A diff alone produces false
> positives. For any suspected issue, OPEN the surrounding file(s) and read the
> enclosing function, its callers, and nearby invariants. Confirm the bug is real
> *in context* — e.g., check there is no upstream nil-guard, no caller-side lock,
> no validation that already handles it. Only report issues you have confirmed
> against the actual code, not just the diff hunk.
>
> **Your job — HIGH SIGNAL ONLY:**
> Report ONLY: real bugs, logic errors, race conditions, security vulnerabilities, correctness failures, resource leaks, null/panic risks, and broken invariants.
>
> **Explicitly forbidden:** style, formatting, naming conventions, whitespace, "consider using X instead of Y" suggestions, performance micro-optimizations without a concrete bottleneck, or anything that doesn't risk incorrect behavior or a crash.
>
> **For each finding, provide:**
> 1. `file:line` (exact location)
> 2. Severity: CRITICAL / HIGH / MEDIUM / LOW
> 3. Category: bug / race / security / correctness / resource-leak / other
> 4. Problem: one sentence, specific
> 5. Concrete fix: the minimal code change that resolves it
> 6. Context checked: one phrase on what surrounding code you read to confirm it's real
>
> Number your findings. If you find nothing that meets the bar, say "NO FINDINGS".

Collect all reviewer responses. If ALL reviewers return "NO FINDINGS", skip to Phase 6.

---

### Phase 2 — Consolidate & reason

**YOU (orchestrator) own this step.** Do not delegate.

1. **Deduplicate.** Group findings that describe the same issue (same file:line or same root cause). Pick the clearest description.

2. **Re-calibrate severity.** For each unique finding:
   - Does it actually cause incorrect behavior in a realistic code path?
   - Could it be a false positive (e.g., intentional design, handled upstream)?
   - How many of the 3 reviewers flagged it? (agreement → higher confidence)

3. **Render a verdict table:**

```
| # | file:line | Category | Your Severity | Reviewers | Decision | Reason |
|---|-----------|----------|--------------|-----------|----------|--------|
| 1 | src/x.go:42 | race | HIGH | A,B | ACCEPT | ... |
| 2 | src/y.py:11 | style | LOW | C only | REJECT | false pos: intentional |
```

4. **Produce the accepted findings list** — numbered, with exact file:line and the concrete fix — this becomes the builder's spec.

If zero findings accepted: report to user, skip to Phase 6 (no fix needed).

---

### Phase 3 — Fix

Launch **ONE `general-purpose` builder subagent** (`model: claude-opus-4.8`, `reasoning_effort: high`). Use this prompt template:

> **Your mission:** Fix the following verified bugs in the codebase. Edit code, add/update tests if needed, then run the test suite until green.
>
> **DO NOT commit or push anything.**
>
> **Findings to fix (numbered spec — fix ALL of them):**
> {{ACCEPTED_FINDINGS_LIST}}
>
> **Test command:** `{{TEST_COMMAND}}`
>
> **Rules:**
> - Fix exactly what is specified. Do not refactor unrelated code.
> - If a fix requires a design decision (e.g., which concurrency primitive), prefer the simplest correct approach and note it.
> - Run `{{TEST_COMMAND}}` after all edits. **Bound: max 3 test-fix cycles.** If tests are still red after 3 attempts, STOP and report exactly which tests fail and your best diagnosis — do not keep guessing or disable/skip tests to force green.
> - If the suite was already broken before your changes (pre-existing failures), note that separately — do not try to fix unrelated pre-existing failures.
> - Report: which findings you fixed, what you changed (file:line → what), and the final test output.

Wait for builder to complete. Capture the summary.

---

### Phase 4 — Verify

Launch **ONE `code-review` verifier subagent** (`model: gpt-5.4` — MUST differ from builder model). Use this prompt template:

> **Scope:** The uncommitted fix diff — run `git diff` to get it. Review ONLY the changes in that diff.
>
> **Your job:**
> 1. **Verify each fix:** Confirm the original finding (listed below) is actually resolved. If a fix is incomplete or wrong, say so.
> 2. **Check for regressions:** Did the fix introduce any new bugs, races, security issues, or broken invariants? This is the primary goal — look hard.
>
> **Original findings that were fixed:**
> {{ACCEPTED_FINDINGS_LIST}}
>
> **Builder's change summary:**
> {{BUILDER_SUMMARY}}
>
> **High signal only.** Same bar as the initial review — no style, no nits. Number your findings.
>
> Output format:
> - For each original finding: "Finding N: VERIFIED ✓" or "Finding N: INCOMPLETE — [reason]"
> - New issues found (if any): same format as initial review (file:line, severity, problem, fix)

Collect verifier response.

---

### Phase 5 — Iterate (bounded)

Track iteration count (starts at 0, max = 2).

**If verifier reports new real issues OR unresolved findings:**
- If iteration count < max: increment count, go back to Phase 3. The new builder is
  **stateless** — it does not remember the prior iteration. In its prompt you MUST include:
  1. The new/unresolved findings as the numbered spec.
  2. A **"Prior work" section**: the previous builder's change summary + the verifier's
     critique, so it does not undo or re-litigate earlier correct fixes.
  3. Instruction: "Build on the existing uncommitted changes — do NOT revert them
     unless the verifier explicitly says a prior fix was wrong."
- If iteration count == max: stop. Report to user: "Max iterations reached. Remaining issues: [list]."

**If verifier confirms all fixes and finds no regressions:** proceed to Phase 6.

---

### Phase 6 — Finalize

1. **Full test suite.** Only re-run `{{TEST_COMMAND}}` if an iteration occurred
   (Phase 5 looped) OR the builder did not clearly report green. If the builder just
   reported a green full-suite run and no iteration happened, skip this — don't burn a
   redundant suite run. Report pass/fail either way.

2. **Commit choice** — ask the user (default is NO commit):

> The fixes are verified and tests pass. Should I:
> - (A) **Summarize and stop** (default) — you commit manually
> - (B) **Commit now** — I'll write a commit message following the repo's conventions

If user chooses commit: write a commit message following the repo's observed conventions (check git log for style). Include a short body listing the findings fixed. Apply the `Co-authored-by` trailer only if it matches the repo's normal practice.

3. **Print final summary:**

```
## review-fix-verify — Summary

**Scope:** <diff scope>
**Iterations:** <N>

### Findings reviewed
| # | file:line | Severity | Decision |
|---|-----------|----------|----------|

### Fixes applied
<list of changes>

### Verification
<verifier verdict>

### Test result
<pass/fail + output tail>
```

---

## Optional: custom agent personas

The Copilot CLI task tool already supports `model` overrides on built-in agent types (`code-review`, `general-purpose`). This skill uses that directly — no separate agent definition files needed.

If you want named reviewer/verifier personas (e.g., to reuse across other skills), you can define them in your agents directory (`${AGENTS_DIR:-$HOME/.agents}/agents/`) when that directory is supported by your CLI version. Check the `manage-plugins` skill or `/help` for the current agent definition format. If that directory isn't supported by your install, the skill-only approach here is sufficient.

---

## Notes

- Verifier always uses a model **different** from the builder to avoid shared blind spots.
- Verifier reviews **only the fix diff**, not the full codebase — keeps scope tight.
- Reviewers read surrounding code for context (not just the diff hunk) to avoid false positives.
- Reviewers use fast models at medium effort; builder/verifier use strong models at high effort.
- `rfv-prep.sh` runs once in Phase 0 and computes the diff + test command — reviewers never re-run git.
- The builder is bounded (max 3 test-fix cycles) and must NOT commit. Orchestrator owns the commit decision.
- Iteration is bounded (max 2) and carries prior builder+verifier context so fixes aren't undone.
