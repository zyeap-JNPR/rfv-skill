#!/usr/bin/env bash
# rfv-prep.sh — pre-flight context for review-fix-verify.
# Usage: rfv-prep.sh [scope]
#   scope: a path, a git range (HEAD~3..HEAD), or empty for uncommitted changes.
#
# Structured output (machine-parseable, one value per line):
#   RFV_SCOPE_KIND: uncommitted | last-commit | range | path
#   RFV_SCOPE:      human description
#   RFV_CHANGED_LINES: <N>
#   RFV_TEST_CMD:   <runnable command>
#   RFV_LINT_CMD:   <runnable command>
#   RFV_BUILD_CMD:  <runnable command>
#   RFV_WARN:       <advisory message>
#   RFV_ERROR:      <fatal message>  (script exits non-zero)
#
# Human-readable sections use === ... === delimiters.
# Set RFV_MAX_DIFF_LINES to cap emitted diff size (default: 500).
set -euo pipefail

SCOPE="${1:-}"
# Trim leading/trailing whitespace
SCOPE="${SCOPE#"${SCOPE%%[![:space:]]*}"}"
SCOPE="${SCOPE%"${SCOPE##*[![:space:]]}"}"
MAX_DIFF_LINES="${RFV_MAX_DIFF_LINES:-500}"

# ---------- Guard: must be a git repo ----------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "RFV_ERROR: not a git repository"
  exit 3
fi

# ---------- Git state helpers ----------
has_head()   { git rev-parse --verify HEAD   >/dev/null 2>&1; }
has_parent() { git rev-parse --verify HEAD~1 >/dev/null 2>&1; }

# Returns 0 only when both sides of a ".." spec resolve to real git objects.
# Anything with ".." that doesn't validate is treated as a path, not a range.
is_range_spec() {
  local spec="$1"
  echo "$spec" | grep -q '\.\.' || return 1
  local left right
  if echo "$spec" | grep -q '\.\.\.'; then
    left="${spec%%\.\.\.*}"
    right="${spec##*\.\.\.}"
  else
    left="${spec%%\.\.*}"
    right="${spec##*\.\.}"
  fi
  # Require non-empty left side; bare "..HEAD" would be an unusual path
  [ -n "$left" ] || return 1
  git rev-parse --verify "$left"           >/dev/null 2>&1 || return 1
  git rev-parse --verify "${right:-HEAD}"  >/dev/null 2>&1 || return 1
}

# ---------- Guard: unborn branch (no commits yet) ----------
if ! has_head; then
  echo "RFV_ERROR: repository has no commits yet — make at least one commit first"
  exit 5
fi

# ---------- Resolve diff command from scope ----------
if [ -z "$SCOPE" ]; then
  if git diff --quiet && git diff --cached --quiet; then
    if has_parent; then
      DIFF_CMD=(git diff HEAD~1..HEAD)
      echo "RFV_SCOPE_KIND: last-commit"
      echo "RFV_SCOPE: no uncommitted changes — using HEAD~1..HEAD"
    else
      echo "RFV_WARN: only one commit and working tree is clean — nothing to compare"
      echo "RFV_ERROR: empty diff — nothing to review"
      exit 4
    fi
  else
    DIFF_CMD=(git diff HEAD)
    echo "RFV_SCOPE_KIND: uncommitted"
    echo "RFV_SCOPE: uncommitted changes (staged + unstaged)"
  fi
elif is_range_spec "$SCOPE"; then
  DIFF_CMD=(git diff "$SCOPE")
  echo "RFV_SCOPE_KIND: range"
  echo "RFV_SCOPE: range $SCOPE"
else
  DIFF_CMD=(git diff HEAD -- "$SCOPE")
  echo "RFV_SCOPE_KIND: path"
  echo "RFV_SCOPE: path $SCOPE"
fi

# ---------- Guard: empty diff ----------
STAT="$("${DIFF_CMD[@]}" --stat 2>/dev/null || true)"
if [ -z "$STAT" ]; then
  echo "RFV_ERROR: empty diff — nothing to review"
  exit 4
fi

# ---------- Size check ----------
# Binary files report '-' in --numstat; count them as 1 line each rather than 0
# to avoid undercounting large binary-heavy diffs.
CHANGED_LINES="$("${DIFF_CMD[@]}" --numstat 2>/dev/null | awk '
  { a = ($1 ~ /^[0-9]+$/) ? $1+0 : 1
    d = ($2 ~ /^[0-9]+$/) ? $2+0 : 1
    total += a + d }
  END { print total+0 }')"
echo "RFV_CHANGED_LINES: ${CHANGED_LINES:-0}"
if [ "${CHANGED_LINES:-0}" -gt 800 ]; then
  echo "RFV_WARN: large diff (${CHANGED_LINES} lines) — consider scoping down per-dir or per-commit"
fi

# ---------- Diff output (capped at MAX_DIFF_LINES) ----------
echo "=== DIFF STAT ==="
echo "$STAT"

echo "=== DIFF ==="
DIFF_OUTPUT="$("${DIFF_CMD[@]}" 2>/dev/null || true)"
DIFF_LINE_COUNT="$(printf '%s\n' "$DIFF_OUTPUT" | wc -l | tr -d ' \t')"
if [ "${DIFF_LINE_COUNT:-0}" -gt "${MAX_DIFF_LINES}" ]; then
  printf '%s\n' "$DIFF_OUTPUT" | head -n "${MAX_DIFF_LINES}"
  echo "RFV_WARN: diff truncated at ${MAX_DIFF_LINES} lines (${DIFF_LINE_COUNT} total) — set RFV_MAX_DIFF_LINES to increase"
else
  printf '%s\n' "$DIFF_OUTPUT"
fi

# ---------- Test / lint / build command detection ----------

# emit_cmd <kind> <command>
#   Prints a human-readable "<kind>: <cmd>" line AND a structured
#   RFV_<KIND>_CMD: marker on the next line for downstream parsing.
emit_cmd() {
  local kind="$1" cmd="$2"
  echo "${kind}: ${cmd}"
  local upper
  upper="$(printf '%s' "$kind" | tr '[:lower:]' '[:upper:]')"
  echo "RFV_${upper}_CMD: ${cmd}"
}

detect_commands() {
  # Node.js
  if [ -f package.json ]; then
    if command -v jq >/dev/null 2>&1; then
      local jq_out found=0
      jq_out="$(jq -r '.scripts // {} | to_entries[]
          | select(.key | test("^(test|lint|build|check|typecheck)$"))
          | "\(.key): npm run \(.key)"' package.json 2>/dev/null)" || {
        echo "RFV_WARN: could not parse package.json — ask the user"
        return
      }
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local kind cmd
        kind="${line%%: *}"
        cmd="${line#*: }"
        emit_cmd "$kind" "$cmd"
        found=1
      done <<< "$jq_out"
      if [ "$found" -eq 0 ]; then echo "RFV_WARN: package.json has no recognised test/lint/build/check/typecheck scripts"; fi
    else
      echo "RFV_WARN: jq not found — install jq for reliable package.json parsing"
    fi
    return
  fi

  # Make
  if [ -f Makefile ]; then
    while IFS= read -r line; do
      local target="${line%%:*}"
      emit_cmd "$target" "make $target"
    done < <(grep -E '^(test|lint|build|check):' Makefile | head -5)
    return
  fi

  # Go
  if [ -f go.mod ]; then
    emit_cmd "test" "go test ./..."
    emit_cmd "lint" "go vet ./..."
    return
  fi

  # Rust
  if [ -f Cargo.toml ]; then
    emit_cmd "test" "cargo test"
    emit_cmd "lint" "cargo clippy"
    return
  fi

  # Python — pyproject, setup, or requirements
  if [ -f pyproject.toml ]; then
    emit_cmd "test" "python -m pytest"
    if grep -qE '\b(ruff|flake8|mypy)\b' pyproject.toml 2>/dev/null; then
      local linter
      linter="$(grep -oE 'ruff|flake8|mypy' pyproject.toml | head -1)"
      emit_cmd "lint" "python -m ${linter}"
    fi
    return
  fi
  if [ -f setup.py ] || [ -f setup.cfg ]; then
    emit_cmd "test" "python -m pytest"
    return
  fi
  if [ -f requirements.txt ]; then
    emit_cmd "test" "python -m pytest"
    echo "RFV_WARN: no pyproject.toml found — verify pytest is installed"
    return
  fi

  # Java — Maven (prefer wrapper)
  if [ -f pom.xml ]; then
    local mvn_cmd="mvn"
    [ -f mvnw ] && mvn_cmd="./mvnw"
    emit_cmd "test" "${mvn_cmd} test"
    return
  fi

  # Java — Gradle (prefer wrapper)
  if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    local gradle_cmd="gradle"
    [ -f gradlew ] && gradle_cmd="./gradlew"
    emit_cmd "test" "${gradle_cmd} test"
    return
  fi

  # .NET
  if compgen -G "./*.csproj" > /dev/null 2>&1 || compgen -G "./*.sln" > /dev/null 2>&1; then
    emit_cmd "test" "dotnet test"
    return
  fi

  # Swift
  if [ -f Package.swift ]; then
    emit_cmd "test" "swift test"
    return
  fi

  # Ruby
  if [ -f Gemfile ]; then
    if [ -f Rakefile ] && grep -qE 'rspec|minitest|test' Rakefile 2>/dev/null; then
      emit_cmd "test" "bundle exec rake test"
    else
      emit_cmd "test" "bundle exec rspec"
    fi
    return
  fi

  # PHP
  if [ -f composer.json ]; then
    if command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' composer.json >/dev/null 2>&1; then
      emit_cmd "test" "composer test"
    else
      emit_cmd "test" "./vendor/bin/phpunit"
    fi
    return
  fi

  # Elixir
  if [ -f mix.exs ]; then
    emit_cmd "test" "mix test"
    return
  fi

  echo "RFV_WARN: no test command detected — ask the user"
}

echo "=== TEST/LINT COMMANDS (detected) ==="
detect_commands
