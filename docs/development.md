# Development

## Testing

The shell script has a behavioral test suite using [bats-core](https://github.com/bats-core/bats-core).

```bash
# Install bats-core
brew install bats-core          # macOS
sudo apt-get install bats       # Debian/Ubuntu

# Run all tests (from repo root)
bats tests/rfv-prep.bats

# Syntax check only
bash -n skills/review-fix-verify/rfv-prep.sh

# Shellcheck (static analysis)
shellcheck -S warning skills/review-fix-verify/rfv-prep.sh
```

CI runs all three checks on every push and PR via GitHub Actions.

---

## Contributing

1. Edit files under `skills/review-fix-verify/` in your clone.
2. Run the test suite: `bats tests/rfv-prep.bats`
3. Run shellcheck: `shellcheck -S warning skills/review-fix-verify/rfv-prep.sh`
4. Commit and push. Consumers pick up changes via `npx skills update` (Method A)
   or `git pull` (Method B).

---

## Versioning

This repo uses [Semantic Versioning](https://semver.org/):

- **Patch** (x.y.**Z**) — bug fixes to `rfv-prep.sh`, doc corrections, test additions.
- **Minor** (x.**Y**.0) — new ecosystem support, new structured output markers, additive SKILL.md changes.
- **Major** (**X**.0.0) — breaking changes to SKILL.md phases, `rfv-prep.sh` exit codes, or structured output format.

`npx skills update` pulls the latest commit from `main`. Pin to a tag if you need
stability: `git checkout v1.2.3` in your Method B clone.
