#!/usr/bin/env bash
# rfv-prep.sh — pre-flight context for review-fix-verify.
# Usage: rfv-prep.sh [scope]
#   scope: a path, a git range (HEAD~3..HEAD), or empty for uncommitted changes.
# Emits: repo guard, diff stat, the diff itself, and detected test/lint commands.
# The skill runs this ONCE in Phase 0 and inlines the output into subagent prompts.
set -euo pipefail

SCOPE="${1:-}"

# --- Guard: must be a git repo ---
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "RFV_ERROR: not a git repository"
  exit 3
fi

# --- Resolve diff command from scope ---
if [ -z "$SCOPE" ]; then
  # Uncommitted (staged + unstaged). Fall back to last commit if clean.
  if git diff --quiet && git diff --cached --quiet; then
    DIFF_CMD=(git diff HEAD~1..HEAD)
    echo "RFV_SCOPE: no uncommitted changes — using HEAD~1..HEAD"
  else
    DIFF_CMD=(git diff HEAD)
    echo "RFV_SCOPE: uncommitted changes (staged + unstaged)"
  fi
elif echo "$SCOPE" | grep -q '\.\.'; then
  DIFF_CMD=(git diff "$SCOPE")
  echo "RFV_SCOPE: range $SCOPE"
else
  DIFF_CMD=(git diff HEAD -- "$SCOPE")
  echo "RFV_SCOPE: path $SCOPE"
fi

# --- Guard: empty diff ---
STAT="$("${DIFF_CMD[@]}" --stat || true)"
if [ -z "$STAT" ]; then
  echo "RFV_ERROR: empty diff — nothing to review"
  exit 4
fi

# --- Size warning ---
CHANGED_LINES="$("${DIFF_CMD[@]}" --numstat | awk '{a+=$1; d+=$2} END {print a+d+0}')"
echo "RFV_CHANGED_LINES: $CHANGED_LINES"
if [ "${CHANGED_LINES:-0}" -gt 800 ]; then
  echo "RFV_WARN: large diff (${CHANGED_LINES} lines) — consider scoping down per-dir or per-commit"
fi

echo "=== DIFF STAT ==="
echo "$STAT"

echo "=== DIFF ==="
"${DIFF_CMD[@]}"

echo "=== TEST/LINT COMMANDS (detected) ==="
if [ -f package.json ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -r '.scripts // {} | to_entries[] | select(.key|test("^(test|lint|build|check|typecheck)$")) | "\(.key): npm run \(.key)"' package.json 2>/dev/null \
      || echo "RFV_WARN: could not parse package.json — ask the user"
  else
    grep -E '"(test|lint|build|check|typecheck)"' package.json | sed 's/.*"\(test\|lint\|build\|check\|typecheck\)".*/npm run \1/'
  fi
elif [ -f Makefile ]; then
  grep -E '^(test|lint|build|check):' Makefile | head -5
elif [ -f go.mod ]; then
  echo "test: go test ./..."
  echo "lint: go vet ./..."
elif [ -f Cargo.toml ]; then
  echo "test: cargo test"
  echo "lint: cargo clippy"
elif [ -f pyproject.toml ]; then
  # Emit runnable commands, not raw config lines
  echo "test: python -m pytest"
  if grep -qE 'ruff|flake8|mypy' pyproject.toml 2>/dev/null; then
    grep -oE 'ruff|flake8|mypy' pyproject.toml | head -1 | xargs -I{} echo "lint: python -m {}"
  fi
elif [ -f setup.py ] || [ -f setup.cfg ]; then
  echo "test: python -m pytest"
elif [ -f requirements.txt ]; then
  echo "test: python -m pytest"
  echo "RFV_WARN: no pyproject.toml found — verify pytest is installed"
elif [ -f pom.xml ]; then
  if [ -f mvnw ]; then
    echo "test: ./mvnw test"
  else
    echo "test: mvn test"
  fi
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  if [ -f gradlew ]; then
    echo "test: ./gradlew test"
  else
    echo "test: gradle test"
  fi
elif ls ./*.csproj ./*.sln 2>/dev/null | head -1 | grep -q .; then
  echo "test: dotnet test"
elif [ -f Package.swift ]; then
  echo "test: swift test"
elif [ -f Gemfile ]; then
  if [ -f Rakefile ] && grep -q 'rspec\|minitest\|test' Rakefile 2>/dev/null; then
    echo "test: bundle exec rake test"
  else
    echo "test: bundle exec rspec"
  fi
elif [ -f composer.json ]; then
  if command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' composer.json >/dev/null 2>&1; then
    echo "test: composer test"
  else
    echo "test: ./vendor/bin/phpunit"
  fi
elif [ -f mix.exs ]; then
  echo "test: mix test"
else
  echo "RFV_WARN: no test command detected — ask the user"
fi
