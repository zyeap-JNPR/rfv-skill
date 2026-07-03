# Contributing

Thanks for considering a contribution. This guide covers the development workflow,
coding standards, and how to validate your changes.

---

## Prerequisites

- `bash` ≥ 4.0
- `git` ≥ 2.0
- [bats-core](https://github.com/bats-core/bats-core) (`brew install bats-core` / `apt install bats`)
- [shellcheck](https://www.shellcheck.net/) (`brew install shellcheck` / `apt install shellcheck`)
- `jq` (optional but recommended for full test coverage of Node.js detection)

---

## Development workflow

```bash
# Clone and set up symlink dev-mode (edits are live immediately)
git clone https://github.com/zyeap-JNPR/rfv-skill.git ~/work/github/rfv-skill
ln -s ~/work/github/rfv-skill/skills/review-fix-verify \
      ~/.agents/skills/review-fix-verify

# Make your changes
cd ~/work/github/rfv-skill
# ... edit files ...

# Validate
bash -n skills/review-fix-verify/rfv-prep.sh        # syntax
shellcheck -S warning skills/review-fix-verify/rfv-prep.sh  # static analysis
bats tests/rfv-prep.bats                             # behavioral tests

# Commit
git add -A && git commit -m "fix: describe what you fixed"
```

---

## Shell script standards (`rfv-prep.sh`)

- Target `bash` ≥ 4.0. Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Use `if/fi` rather than `&&`/`||` chains for multi-line conditions — avoids
  unintentional `set -e` exits when the condition is simply false.
- All structured output lines must start with `RFV_` and match the schema in the
  script header comment.
- New ecosystem detectors: add a block in `detect_commands()` in the same
  `elif [...]; then ... return; fi` pattern. Emit commands with `emit_cmd`.
- `compgen -G` instead of `ls | grep` for glob existence checks (SC2010).
- No hardcoded paths — use `${AGENTS_DIR:-$HOME/.agents}` where needed.

---

## Tests

Tests live in `tests/rfv-prep.bats`. Each test creates a fresh temp git repo,
runs the script, and asserts structured output.

When adding a new feature to `rfv-prep.sh`, add at least one test that:
1. Covers the happy path (correct output produced)
2. Covers the error/guard path (exit code and `RFV_ERROR` message)

Use the `setup_repo` / `make_commit` helpers already defined at the top of the
test file to keep tests consistent.

---

## Documentation consistency

| File | Owns |
|------|------|
| `SKILL.md` | Authoritative execution contract: phases, prompts, model matrix, guardrails |
| `skills/review-fix-verify/README.md` | User-facing behavior, examples, limitations |
| `README.md` (root) | Installation, compatibility, security, maintenance |

If you change the model matrix, `rfv-prep.sh` output format, or phase logic, update
`SKILL.md` first. Then check whether `README.md` or the skill `README.md` reference
the changed detail — update those too.

---

## Adding a dependency

This project currently has **no runtime dependencies** beyond standard shell tools
and an optional `jq`. If you want to add a dependency:

1. Document: name, version, license (must be MIT-compatible), and why it's needed.
2. Verify the license is acceptable (MIT, Apache-2.0, BSD, ISC are all fine).
3. Check the dependency's security posture (recent CVEs, active maintenance).
4. Add an entry to `CHANGELOG.md` under the appropriate category.

Do not add dependencies to satisfy lint preferences or to replace portable POSIX
shell constructs.

---

## Changelog

Add an entry under `[Unreleased]` in `CHANGELOG.md` for every meaningful change.
See the format guidance at the bottom of that file.

---

## Pull request checklist

- [ ] `bash -n skills/review-fix-verify/rfv-prep.sh` passes
- [ ] `shellcheck -S warning skills/review-fix-verify/rfv-prep.sh` clean
- [ ] `bats tests/rfv-prep.bats` — all tests pass
- [ ] New behavior has at least one new bats test
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `SKILL.md` updated if phases, prompts, or model matrix changed
- [ ] No secrets, credentials, or PII in the diff
