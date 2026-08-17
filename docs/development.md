# Development

## Validate

From the repository root:

```bash
make lint test
```

Install test tools with `brew install bats-core jq shellcheck` on macOS or
`apt-get install bats jq shellcheck` on Debian/Ubuntu. The Make targets run
syntax, ShellCheck, and all Bats tests; CI uses the same command.

## Preflight protocol

`rfv-prep.sh [path|range]` emits line-oriented markers:

- scope: `RFV_REPO_ROOT`, `RFV_COMMAND_DIR`, `RFV_SCOPE_KIND`, `RFV_SCOPE`
- size/files: `RFV_CHANGED_LINES`, repeated `RFV_CHANGED_FILE`
- commands: `RFV_TEST_CMD` plus advisory `RFV_*_CMD`
- status: `RFV_WARN`, `RFV_ERROR`
- diff: content between `=== DIFF ===` and `=== END DIFF ===`

Repository, scope, and changed-file values must fit one line; paths containing CR
or LF are rejected before diff content is emitted.

Exit codes:

| Code | Meaning |
|------|---------|
| 2 | Invalid input or configuration |
| 3 | Not a Git repository |
| 4 | Empty diff |
| 5 | No commit history |
| 6 | Incomplete input or Git/diff failure |
| 7 | Sensitive path rejected |

Changing markers, delimiters, exit codes, or workflow phases is a compatibility
change. Update `SKILL.md`, user docs, and Bats coverage together.
