# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Version numbers follow [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- Initial public release of `review-fix-verify` skill
- `rfv-prep.sh` with structured `RFV_*` output markers
- Bats test suite (20 tests) for `rfv-prep.sh`
- GitHub Actions CI (shellcheck + bats)
- `RFV_MAX_DIFF_LINES` env var for diff truncation control
- `RFV_SCOPE_KIND` structured output for downstream parsing
- `RFV_TEST_CMD` / `RFV_LINT_CMD` / `RFV_BUILD_CMD` structured markers
- Security & Safety constraints section in SKILL.md
- Builder "Do Not" list in Phase 3
- Ecosystem support: Node, Make, Go, Rust, Python, Java Maven/Gradle, .NET, Swift, Ruby, PHP, Elixir

### Fixed
- Initial-commit guard: repos with a single commit and clean tree no longer fall back to a failing `HEAD~1` diff
- Range detection now validates both sides with `git rev-parse --verify` — filenames containing `..` are no longer misclassified as git ranges
- Binary files in `--numstat` output no longer produce undercounts (counted as 1 line each)
- `jq` parse failures on malformed `package.json` are now handled gracefully
- `set -e` false exits from `&&`-guarded conditions in `detect_commands`
- `.csproj`/`.sln` detection uses `compgen -G` instead of `ls | grep` (shellcheck SC2010)

---

## How to add entries

When you make a change, add an entry under `[Unreleased]` before tagging a release.
Categories: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.

When releasing:
1. Replace `[Unreleased]` with the version and date: `## [1.0.0] — 2026-01-01`
2. Add a new empty `[Unreleased]` section above it.
3. Tag the commit: `git tag v1.0.0 && git push origin v1.0.0`
