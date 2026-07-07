---
name: review-fix-verify
description: >
  Multi-model review → fix → verify workflow. Launches 2 parallel code-review subagents (claude-sonnet-4.6 + gpt-5.3-codex) that read surrounding code for context, consolidates findings with orchestrator reasoning, fixes with a bounded builder agent (claude-sonnet-4.6), then verifies the fix diff with a fresh reviewer (gpt-5.4-mini). --fast: 1 reviewer, cheapest builder, no verifier. --thorough: 3 reviewers, opus builder. Bounded iteration prevents runaway loops.
  Use when user says "review and fix", "review fix verify", "rfv", "/review-fix-verify", "multi-model review", "parallel code review", or "review my changes".
---

# review-fix-verify Skill

Automates a proven multi-model "review → reason → fix → verify → iterate" workflow. The key insight: the **verifier reviews the fix diff, not the original code** — this catches regressions the builder introduces.

---

## Activation triggers

- `/review-fix-verify [path|range] [--thorough] [--fast]`
- "review and fix", "review fix verify", "rfv"
- "multi-model review", "parallel code review"
- "review my changes [and fix them]"

`--thorough` (or "be thorough") adds a 3rd reviewer. Default is 2 reviewers.

`--fast` (or "be fast", "quick review") uses 1 reviewer, a lighter builder model, and skips the verifier phase. Best for solo devs reviewing small, low-risk changes.

---

## Model matrix (configurable)

| Role | Model | Effort | Notes |
|------|-------|--------|-------|
| Reviewer A | `claude-sonnet-4.6` | low | medium on `--thorough` |
| Reviewer B | `gpt-5.3-codex` | low | medium on `--thorough` |
| Reviewer C (`--thorough`) | `gemini-3.5-flash` | low | cheap 3rd reviewer |
| Reviewer (`--fast`) | `gemini-3.5-flash` | low | sole reviewer in fast mode |
| Builder | `claude-sonnet-4.6` | medium | default |
| Builder (`--thorough`) | `claude-opus-4.8` | high | deep reasoning for complex fixes |
| Builder (`--fast`) | `gemini-3.5-flash` | low | cheapest, for trivial fixes |
| Verifier | `gpt-5.4-mini` | low | fix diffs are small; MUST differ from builder |

**Modes:** default = 2 reviewers + sonnet builder + mini verifier. `--fast` = 1 reviewer, flash builder, no verifier. `--thorough` = 3 reviewers, opus builder.

Override any model by stating it: "use opus for the builder", "use codex as reviewer A".
If a model is unavailable at runtime, drop that reviewer (a single reviewer still works) and note it in the summary.

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
   - `RFV_ERROR: repository has no commits yet` → stop, tell the user to make an initial commit.
   - `RFV_ERROR: empty diff` → stop, nothing to review.
   - `RFV_WARN: large diff (>800 lines)` → warn the user and offer to scope down
     (per-directory or per-commit) before spending 3 model reviews on it. Proceed
     only if they confirm.

3. **Test command.** Parse the `RFV_TEST_CMD:` structured marker from the script
   output — this is the authoritative pass/fail gate. `RFV_LINT_CMD:` and
   `RFV_BUILD_CMD:` are advisory (run them, report failures, but do not block the
   workflow on lint alone). Prefer a stored memory ("test command") if one exists.
   If no `RFV_TEST_CMD:` line is present, ask the user. Confirm before Phase 3.

4. **Capture the diff output** from the script into a variable — you will inline it
   as a *starting pointer* in the reviewer prompts (Phase 1). Report scope + line
   count + test command before proceeding.

5. **Pre-capture file context for reviewers.** If `RFV_CHANGED_LINES` ≤ 400, also
   capture the full content of each changed file (from `git diff --name-only`) and
   store it. Cap at 5 files × 300 lines each. Inline this as `{{FILE_CONTEXT}}` in
   Phase 1 reviewer prompts so reviewers don't need to open files themselves — this
   eliminates per-reviewer file I/O tool calls and speeds up Phase 1 significantly.
   If the diff is large (> 400 lines) or there are > 5 changed files, skip this step
   and keep the "read surrounding files" instruction in the reviewer prompt instead.

---

### Phase 1 — Fan-out review (PARALLEL)

Launch **2 `code-review` subagents in parallel** (3 on `--thorough`, 1 on `--fast`) in a SINGLE
`task` call block. Use the model matrix above — default reviewers use `effort: low`; `--thorough`
uses `effort: medium`. Inline the diff and file context from Phase 0. Use this template:

> You are a senior engineer doing a focused code review. Do NOT modify any code.
>
> **Diff:**
> ```diff
> {{DIFF_FROM_PHASE_0}}
> ```
>
> **Full file context (changed files — use this instead of opening files yourself):**
> {{FILE_CONTEXT}}
> *(If FILE_CONTEXT is "(not pre-captured — read surrounding files as needed)", open the relevant files before flagging.)*
>
> **CRITICAL:** Confirm every suspected issue is real in context before reporting. A diff alone produces false positives.
>
> **Report ONLY:** bugs, logic errors, races, security vulnerabilities, correctness failures, resource leaks, null/panic risks, broken invariants. Nothing else — no style, naming, whitespace, micro-optimizations, or "consider X instead of Y".
>
> If nothing meets the bar: say "NO FINDINGS".
>
> **Output — one block per finding:**
> ```
> Finding N
> Location: <file>:<line>
> Severity: CRITICAL|HIGH|MEDIUM|LOW
> Category: bug|race|security|correctness|resource-leak|other
> Problem: <one sentence>
> Fix: <minimal code change>
> ```

Collect all reviewer responses. If ALL reviewers return "NO FINDINGS", skip to Phase 6.

---

### Phase 2 — Consolidate & reason

**YOU (orchestrator) own this step.** Do not delegate.

1. **Deduplicate.** Group findings that describe the same issue (same file:line or same root cause). Pick the clearest description.

2. **Re-calibrate severity.** For each unique finding:
   - Does it actually cause incorrect behavior in a realistic code path?
   - Could it be a false positive (e.g., intentional design, handled upstream)?
   - How many reviewers flagged it? (agreement → higher confidence)

3. **Render a verdict table:**

```
| # | file:line | Category | Your Severity | Reviewers | Decision | Reason |
|---|-----------|----------|--------------|-----------|----------|--------|
| 1 | src/x.go:42 | race | HIGH | A,B | ACCEPT | ... |
| 2 | src/y.py:11 | style | LOW | C only | REJECT | false pos: intentional |
```

4. **Produce the accepted findings list** — numbered, with exact file:line and the concrete fix — this becomes the builder's spec.

If zero findings accepted: report to user, skip to Phase 6 (no fix needed).

5. **Refactor suggestions (optional appendix).** If any REJECTED findings were improvement or
   refactoring suggestions (not bugs), collect them in a short non-blocking table shown to the
   user at the end of Phase 2. Do NOT pass these to the builder. Format:

```
### Suggestions (not actioned by this run)
| # | file:line | Suggestion |
|---|-----------|------------|
```

   Skip this table entirely if no refactor suggestions surfaced.

---

### Phase 3 — Fix

Launch **ONE `general-purpose` builder subagent** (use model matrix: `claude-sonnet-4.6` medium by default, `claude-opus-4.8` high on `--thorough`, `gemini-3.5-flash` low on `--fast`). Use this prompt template:

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
> - Run `{{TEST_COMMAND}}` after all edits. **This is the authoritative pass/fail gate.**
>   `{{LINT_COMMAND}}` (if provided) is advisory — run it and report failures, but do not
>   block on lint alone. **Bound: max 3 test-fix cycles.** If tests are still red after 3
>   attempts, STOP and report exactly which tests fail and your best diagnosis — do not keep
>   guessing or disable/skip tests to force green.
> - If the suite was already broken before your changes (pre-existing failures), note that separately — do not try to fix unrelated pre-existing failures.
> - **DO NOT:** install new dependencies, widen scope beyond the accepted findings, run
>   deployment commands, or use production credentials. If a fix requires a new dependency,
>   document it and ask rather than adding it silently.
> - Report: which findings you fixed, what you changed (file:line → what), and the final test output.

Wait for builder to complete. Capture the summary.

---

### Phase 4 — Verify

**In `--fast` mode: skip this phase entirely. Proceed directly to Phase 6.**

After the builder reports done, run `git diff HEAD` yourself and capture the fix diff. Then
launch **ONE `code-review` verifier subagent** (`model: gpt-5.4-mini`, `effort: low` — MUST
differ from builder model). Use this prompt template:

> **Fix diff (review ONLY these changes):**
> ```diff
> {{FIX_DIFF_FROM_ORCHESTRATOR}}
> ```
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

**Fast path — orchestrator inline fix:** If the new/unresolved issues are small (≤ 10 lines total,
clearly isolated, no design ambiguity), the orchestrator MAY apply the fix directly using its own
edit tools, then re-run `{{TEST_COMMAND}}` to confirm green, and skip spawning a new builder subagent.
This avoids a full builder cycle for trivial regressions. If tests go red or the fix is unclear,
fall through to the full builder path below.

**Full builder path:**
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

2. **Commit — explicit opt-in only.** Ask the user. Default is **NO commit** — stop and
   summarize so the user can review and commit manually. Only commit if they explicitly
   choose option B:

> The fixes are verified and tests pass. Should I:
> - **(A) Summarize and stop** ← **default** — review changes yourself, then commit manually
> - (B) Commit now — I'll write a commit message following the repo's conventions

   If user chooses commit: write a commit message following the repo's observed conventions
   (check `git log` for style). Include a short body listing the findings fixed. Apply the
   `Co-authored-by` trailer only if it matches the repo's normal practice. Never push.

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

## Security & Safety constraints

These apply to the orchestrator and all subagents throughout the workflow.

**Data handling**
- Never include `.env` file contents, secret values, API keys, tokens, or PII in any prompt or summary — even if the diff touches those files.
- If the diff reveals a secret accidentally committed, flag it as a CRITICAL finding and stop the fix phase. Direct the user to rotate the secret and use `git filter-repo` to remove it.

**Scope constraints**
- The builder operates only in the local working tree. It must NOT: run deployment scripts, push to remote, modify CI configuration to disable checks, or widen scope beyond the accepted findings list.
- Lint and type-check failures are advisory — report them, do not auto-fix unrelated issues to satisfy them.

**Dependency policy**
- The builder must NOT add, remove, or upgrade dependencies without explicit user approval. If a fix requires a new dependency, document the name and purpose, stop, and ask.

**Production safety**
- Local and staging test execution is allowed. Production credentials, production databases, and production API endpoints are out of scope. If the test command would touch production, stop and report.

**Breaking changes**
- If an accepted finding requires changing a public interface or removing a symbol, the builder must note this explicitly and suggest a deprecation path rather than a silent removal.

