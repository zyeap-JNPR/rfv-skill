#!/usr/bin/env bats
# Tests for skills/review-fix-verify/rfv-prep.sh
# Requires: bats-core >= 1.5  (https://github.com/bats-core/bats-core)
# Install:  brew install bats-core  |  apt-get install bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/review-fix-verify/rfv-prep.sh"

# ---------- Helpers ----------

# Create a temp git repo, cd into it, and register cleanup.
setup_repo() {
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q
  git config user.email "test@example.com"
  git config user.name  "Test"
}

# Make an initial commit with a dummy file.
make_commit() {
  local msg="${1:-init}"
  echo "$msg" >> dummy.txt
  git add -A
  git commit -q -m "$msg"
}

teardown() {
  if [ -n "${REPO:-}" ]; then
    rm -rf "$REPO"
  fi
}

# ---------- Guard tests ----------

@test "non-repo exits 3 with RFV_ERROR" {
  TMPDIR="$(mktemp -d)"
  cd "$TMPDIR"
  run bash "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"RFV_ERROR: not a git repository"* ]]
  rm -rf "$TMPDIR"
}

@test "unborn branch exits 5 with RFV_ERROR" {
  setup_repo
  run bash "$SCRIPT"
  [ "$status" -eq 5 ]
  [[ "$output" == *"RFV_ERROR: repository has no commits yet"* ]]
}

@test "single commit clean tree exits 4 with RFV_WARN and RFV_ERROR" {
  setup_repo
  make_commit "first"
  run bash "$SCRIPT"
  [ "$status" -eq 4 ]
  [[ "$output" == *"RFV_WARN: only one commit"* ]]
  [[ "$output" == *"RFV_ERROR: empty diff"* ]]
}

# ---------- Scope detection tests ----------

@test "single commit with uncommitted changes uses uncommitted scope" {
  setup_repo
  make_commit "first"
  echo "change" >> dummy.txt
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: uncommitted"* ]]
}

@test "two commits clean tree falls back to last-commit scope" {
  setup_repo
  make_commit "first"
  make_commit "second"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: last-commit"* ]]
  [[ "$output" == *"HEAD~1..HEAD"* ]]
}

@test "staged changes detected as uncommitted" {
  setup_repo
  make_commit "first"
  echo "staged" >> new.txt
  git add new.txt
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: uncommitted"* ]]
}

@test "unstaged changes detected as uncommitted" {
  setup_repo
  make_commit "first"
  echo "unstaged" >> dummy.txt
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: uncommitted"* ]]
}

@test "valid range scope uses range kind" {
  setup_repo
  make_commit "first"
  make_commit "second"
  run bash "$SCRIPT" "HEAD~1..HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: range"* ]]
}

@test "path scope uses path kind" {
  setup_repo
  make_commit "first"
  echo "change" >> dummy.txt
  run bash "$SCRIPT" "dummy.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: path"* ]]
}

@test "filename containing .. is treated as path not range" {
  setup_repo
  make_commit "first"
  # A filename with .. that isn't a valid git range
  echo "x" >> "weird..name.txt"
  git add -A && git commit -q -m "add weird file"
  echo "change" >> "weird..name.txt"
  # This is not a valid git range spec, should be treated as a path
  # (the is_range_spec guard should reject it since the left side won't resolve)
  run bash "$SCRIPT" "weird..name.txt"
  # Either path scope or it fails gracefully — must NOT crash with a git error
  [[ "$output" != *"fatal:"* ]]
}

@test "empty diff for path scope exits 4" {
  setup_repo
  make_commit "first"
  run bash "$SCRIPT" "nonexistent-path/"
  [ "$status" -eq 4 ]
  [[ "$output" == *"RFV_ERROR: empty diff"* ]]
}

# ---------- Size and truncation tests ----------

@test "large diff emits RFV_WARN for large diff" {
  setup_repo
  make_commit "first"
  # Generate a file large enough to exceed 800 changed lines
  python3 -c "print('\n'.join(['line ' + str(i) for i in range(1000)]))" > big.txt
  git add -A && git commit -q -m "add big"
  python3 -c "print('\n'.join(['changed ' + str(i) for i in range(1000)]))" > big.txt
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_WARN: large diff"* ]]
}

@test "diff truncation emits RFV_WARN when over MAX_DIFF_LINES" {
  setup_repo
  make_commit "first"
  python3 -c "print('\n'.join(['line ' + str(i) for i in range(200)]))" > big.txt
  git add -A && git commit -q -m "add"
  python3 -c "print('\n'.join(['x ' + str(i) for i in range(200)]))" > big.txt
  run env RFV_MAX_DIFF_LINES=10 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_WARN: diff truncated"* ]]
}

# ---------- Structured output markers ----------

@test "diff output includes RFV_CHANGED_LINES" {
  setup_repo
  make_commit "first"
  make_commit "second"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_CHANGED_LINES:"* ]]
}

# ---------- Test command detection ----------

@test "package.json with jq emits RFV_TEST_CMD" {
  setup_repo
  echo '{"scripts":{"test":"jest","lint":"eslint ."}}' > package.json
  echo "# helper" > helper.js
  make_commit "add pkg"
  echo "// change" >> helper.js
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_TEST_CMD: npm run test"* ]]
  [[ "$output" == *"RFV_LINT_CMD: npm run lint"* ]]
}

@test "go.mod emits RFV_TEST_CMD and RFV_LINT_CMD" {
  setup_repo
  echo "module example.com/test" > go.mod
  make_commit "add go.mod"
  echo "// change" >> go.mod
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_TEST_CMD: go test ./..."* ]]
  [[ "$output" == *"RFV_LINT_CMD: go vet ./..."* ]]
}

@test "Makefile with test target emits RFV_TEST_CMD" {
  setup_repo
  printf 'test:\n\techo run tests\n' > Makefile
  make_commit "add Makefile"
  echo "# change" >> Makefile
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_TEST_CMD: make test"* ]]
}

@test "Cargo.toml emits RFV_TEST_CMD and RFV_LINT_CMD" {
  setup_repo
  echo '[package]' > Cargo.toml
  make_commit "add cargo"
  echo "version = \"0.1\"" >> Cargo.toml
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_TEST_CMD: cargo test"* ]]
  [[ "$output" == *"RFV_LINT_CMD: cargo clippy"* ]]
}

@test "pyproject.toml with ruff emits RFV_TEST_CMD and RFV_LINT_CMD" {
  setup_repo
  printf '[tool.ruff]\n[tool.pytest.ini_options]\n' > pyproject.toml
  make_commit "add pyproject"
  echo "# change" >> pyproject.toml
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_TEST_CMD: python -m pytest"* ]]
  [[ "$output" == *"RFV_LINT_CMD: python -m ruff"* ]]
}

@test "no project files emits RFV_WARN for no test command" {
  setup_repo
  make_commit "first"
  make_commit "second"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_WARN: no test command detected"* ]]
}
