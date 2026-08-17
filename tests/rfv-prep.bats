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

@test "invalid RFV_MAX_DIFF_LINES exits 2 with RFV_ERROR" {
  setup_repo
  local value
  for value in zero 0 00 -1; do
    run env RFV_MAX_DIFF_LINES="$value" bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"RFV_ERROR: RFV_MAX_DIFF_LINES must be a positive integer"* ]]
  done
}

@test "multiple scope arguments exit 2" {
  setup_repo
  make_commit "first"
  run bash "$SCRIPT" "one" "two"
  [ "$status" -eq 2 ]
  [[ "$output" == *"RFV_ERROR: expected at most one path or range"* ]]
}

@test "scope with a line break exits 2" {
  setup_repo
  make_commit "first"
  run bash "$SCRIPT" $'bad\nscope'
  [ "$status" -eq 2 ]
  [[ "$output" == *"RFV_ERROR: scope must not contain line breaks"* ]]
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

@test "untracked files must be staged before review" {
  setup_repo
  make_commit "first"
  echo "untracked" > new.txt
  run bash "$SCRIPT"
  [ "$status" -eq 6 ]
  [[ "$output" == *"RFV_ERROR: untracked files are excluded from Git diff"* ]]
}

@test "untracked sensitive files are never recommended for staging" {
  setup_repo
  make_commit "first"
  echo "SECRET=value" > .env
  run bash "$SCRIPT"
  [ "$status" -eq 7 ]
  [[ "$output" == *"RFV_ERROR: sensitive untracked file must remain untracked"* ]]
  [[ "$output" != *"stage before review"* ]]
  [[ "$output" != *"SECRET=value"* ]]
}

@test "ignored untracked files do not block review" {
  setup_repo
  printf 'ignored.txt\n' > .gitignore
  make_commit "first"
  echo "ignored" > ignored.txt
  echo "change" >> dummy.txt
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: uncommitted"* ]]
}

@test "path scope ignores unrelated untracked files" {
  setup_repo
  make_commit "first"
  echo "untracked" > unrelated.txt
  echo "change" >> dummy.txt
  run bash "$SCRIPT" "dummy.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: path"* ]]
}

@test "range scope ignores working-tree untracked files" {
  setup_repo
  make_commit "first"
  make_commit "second"
  echo "untracked" > unrelated.txt
  run bash "$SCRIPT" "HEAD~1..HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: range"* ]]
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
  [[ "$output" == *"RFV_CHANGED_LINES: 1"* ]]
  [[ "$output" == *"RFV_CHANGED_FILE: dummy.txt"* ]]
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
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_SCOPE_KIND: path"* ]]
  [[ "$output" != *"fatal:"* ]]
}

@test "path scope preserves leading and trailing spaces" {
  setup_repo
  make_commit "first"
  echo "x" > " spaced.txt "
  git add -A && git commit -q -m "add spaced file"
  echo "change" >> " spaced.txt "
  run bash "$SCRIPT" " spaced.txt "
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_CHANGED_FILE:  spaced.txt "* ]]
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
  awk 'BEGIN { for (i = 0; i < 1000; i++) print "line " i }' > big.txt
  git add -A && git commit -q -m "add big"
  awk 'BEGIN { for (i = 0; i < 1000; i++) print "changed " i }' > big.txt
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_WARN: large diff"* ]]
}

@test "diff truncation emits RFV_WARN when over MAX_DIFF_LINES" {
  setup_repo
  make_commit "first"
  awk 'BEGIN { for (i = 0; i < 200; i++) print "line " i }' > big.txt
  git add -A && git commit -q -m "add"
  awk 'BEGIN { for (i = 0; i < 200; i++) print "x " i }' > big.txt
  run env RFV_MAX_DIFF_LINES=10 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_WARN: diff truncated"* ]]
  [[ "$output" == *"=== END DIFF ==="* ]]
}

@test "binary file counts as one changed line" {
  setup_repo
  make_commit "first"
  printf '\x00\x01' > binary.dat
  git add -A && git commit -q -m "add binary"
  printf '\x00\x02' > binary.dat
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_CHANGED_LINES: 1"* ]]
}

@test "mode-only changes remain reviewable" {
  setup_repo
  make_commit "first"
  chmod +x dummy.txt
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_CHANGED_LINES: 0"* ]]
  [[ "$output" == *"RFV_CHANGED_FILE: dummy.txt"* ]]
  [[ "$output" == *"old mode 100644"* ]]
}

@test "sensitive env files stop before diff output" {
  setup_repo
  make_commit "first"
  echo "SECRET=value" > .env
  git add .env
  run bash "$SCRIPT"
  [ "$status" -eq 7 ]
  [[ "$output" == *"RFV_ERROR: sensitive file requires manual review"* ]]
  [[ "$output" != *"SECRET=value"* ]]
  [[ "$output" != *"=== DIFF ==="* ]]
}

@test "sensitive package auth files are rejected" {
  setup_repo
  make_commit "first"
  echo "//registry.example/:_authToken=value" > .npmrc
  git add .npmrc
  run bash "$SCRIPT"
  [ "$status" -eq 7 ]
  [[ "$output" == *"RFV_ERROR: sensitive file requires manual review"* ]]
  [[ "$output" != *"_authToken=value"* ]]
}

@test "renamed sensitive files are rejected by their old path" {
  setup_repo
  echo "SECRET=value" > .env
  make_commit "commit fixture"
  git mv .env config.txt
  run bash "$SCRIPT"
  [ "$status" -eq 7 ]
  [[ "$output" == *"RFV_ERROR: sensitive file requires manual review"* ]]
  [[ "$output" == *".env"* ]]
  [[ "$output" != *"SECRET=value"* ]]
}

@test "line-break paths stop before sensitive content is emitted" {
  setup_repo
  make_commit "first"
  local dir=$'odd\nname'
  mkdir "$dir"
  echo "SECRET=value" > "$dir/.env"
  git add "$dir/.env"
  run bash "$SCRIPT"
  [ "$status" -eq 6 ]
  [[ "$output" == *"RFV_ERROR: file paths with line breaks are unsupported"* ]]
  [[ "$output" != *"SECRET=value"* ]]
  [[ "$output" != *"=== DIFF ==="* ]]
}

@test "env example files remain reviewable" {
  setup_repo
  make_commit "first"
  echo "NAME=value" > .env.example
  git add .env.example
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_CHANGED_FILE: .env.example"* ]]
}

@test "external diff helpers and forced color are disabled" {
  setup_repo
  make_commit "first"
  cat > diff-helper.sh <<'EOF'
#!/usr/bin/env bash
touch helper-called
EOF
  chmod +x diff-helper.sh
  git add diff-helper.sh && git commit -q -m "add helper"
  echo "change" >> dummy.txt
  git config color.ui always
  run env GIT_EXTERNAL_DIFF="$REPO/diff-helper.sh" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e helper-called ]
  [[ "$output" != *$'\033'* ]]
}

@test "temporary path inventory is removed on exit" {
  setup_repo
  make_commit "first"
  echo "change" >> dummy.txt
  local inventory_dir
  inventory_dir="$(mktemp -d)"
  run env TMPDIR="$inventory_dir" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$(find "$inventory_dir" -name 'rfv-paths.*' -print -quit)" ]
  rm -rf "$inventory_dir"
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

@test "diff output includes RFV_CHANGED_FILE" {
  setup_repo
  make_commit "first"
  echo "change" >> dummy.txt
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_CHANGED_FILE: dummy.txt"* ]]
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
  [[ "$output" != *$'\ntest: npm run test'* ]]
}

@test "packageManager selects pnpm commands" {
  setup_repo
  echo '{"packageManager":"pnpm@10.0.0","scripts":{"test":"vitest","typecheck":"tsc"}}' > package.json
  echo "# helper" > helper.js
  make_commit "add package"
  echo "// change" >> helper.js
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_TEST_CMD: pnpm run test"* ]]
  [[ "$output" == *"RFV_TYPECHECK_CMD: pnpm run typecheck"* ]]
}

@test "nested directory detects root package commands" {
  setup_repo
  echo '{"scripts":{"test":"jest"}}' > package.json
  mkdir -p src/nested
  echo "source" > src/nested/file.js
  make_commit "add package"
  echo "// change" >> src/nested/file.js
  cd src/nested
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_REPO_ROOT: $REPO"* ]]
  [[ "$output" == *"RFV_COMMAND_DIR: $REPO"* ]]
  [[ "$output" == *"RFV_TEST_CMD: npm run test"* ]]
}

@test "file scope detects nearest monorepo package commands" {
  setup_repo
  echo '{"scripts":{"test":"root-test"}}' > package.json
  mkdir -p packages/app/src
  echo '{"packageManager":"pnpm@10.0.0","scripts":{"test":"app-test"}}' > packages/app/package.json
  echo "source" > packages/app/src/file.js
  make_commit "add monorepo"
  echo "// change" >> packages/app/src/file.js
  run bash "$SCRIPT" "packages/app/src/file.js"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_COMMAND_DIR: $REPO/packages/app"* ]]
  [[ "$output" == *"RFV_TEST_CMD: pnpm run test"* ]]
}

@test "deleted file scope retains nearest monorepo package commands" {
  setup_repo
  echo '{"scripts":{"test":"root-test"}}' > package.json
  mkdir -p packages/app/src
  echo '{"packageManager":"pnpm@10.0.0","scripts":{"test":"app-test"}}' > packages/app/package.json
  echo "source" > packages/app/src/file.js
  make_commit "add monorepo"
  rm packages/app/src/file.js
  run bash "$SCRIPT" "packages/app/src/file.js"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_COMMAND_DIR: $REPO/packages/app"* ]]
  [[ "$output" == *"RFV_TEST_CMD: pnpm run test"* ]]
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
  printf 'test:\n\techo run tests\ntypecheck:\n\techo check types\n' > Makefile
  make_commit "add Makefile"
  echo "# change" >> Makefile
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_TEST_CMD: make test"* ]]
  [[ "$output" == *"RFV_TYPECHECK_CMD: make typecheck"* ]]
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

@test "pyproject without a test runner emits warning only" {
  setup_repo
  printf '[project]\nname = "example"\n' > pyproject.toml
  make_commit "add pyproject"
  echo "# change" >> pyproject.toml
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_WARN: no Python test runner detected"* ]]
  [[ "$output" != *"RFV_TEST_CMD:"* ]]
}

@test "composer project without tests emits warning only" {
  setup_repo
  echo '{"require":{"php":"^8.3"}}' > composer.json
  make_commit "add composer"
  echo " " >> composer.json
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_WARN: no Composer test command detected"* ]]
  [[ "$output" != *"RFV_TEST_CMD:"* ]]
}

@test "no project files emits RFV_WARN for no test command" {
  setup_repo
  make_commit "first"
  make_commit "second"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RFV_WARN: no test command detected"* ]]
}
