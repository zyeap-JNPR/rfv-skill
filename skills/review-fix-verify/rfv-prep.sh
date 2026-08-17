#!/usr/bin/env bash
# Emit bounded Git diff context and repository commands for review-fix-verify.
# Usage: rfv-prep.sh [path|range]
set -euo pipefail

error() {
  printf 'RFV_ERROR: %s\n' "$1"
  exit "$2"
}

warn() {
  printf 'RFV_WARN: %s\n' "$1"
}

if [ "$#" -gt 1 ]; then
  error "expected at most one path or range" 2
fi

SCOPE="${1:-}"
MAX_DIFF_LINES="${RFV_MAX_DIFF_LINES:-500}"

[[ "$MAX_DIFF_LINES" =~ ^[1-9][0-9]*$ ]] ||
  error "RFV_MAX_DIFF_LINES must be a positive integer" 2
case "$SCOPE" in
  *$'\n'*|*$'\r'*) error "scope must not contain line breaks" 2 ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  error "not a git repository" 3

REPO_ROOT="$(git rev-parse --show-toplevel)"
case "$REPO_ROOT" in
  *$'\n'*|*$'\r'*) error "repository path must not contain line breaks" 2 ;;
esac
GIT_DIFF=(git diff --no-ext-diff --no-textconv --no-color)
PATHS_FILE="$(mktemp "${TMPDIR:-/tmp}/rfv-paths.XXXXXX")" ||
  error "could not create temporary path inventory" 6
trap 'rm -f "$PATHS_FILE"' EXIT

has_head() {
  git rev-parse --verify HEAD >/dev/null 2>&1
}

has_parent() {
  git rev-parse --verify HEAD~1 >/dev/null 2>&1
}

is_range_spec() {
  local spec="$1" left right
  [[ "$spec" == *..* ]] || return 1

  if [[ "$spec" == *...* ]]; then
    left="${spec%%\.\.\.*}"
    right="${spec##*\.\.\.}"
  else
    left="${spec%%\.\.*}"
    right="${spec##*\.\.}"
  fi

  [ -n "$left" ] || return 1
  case "$left" in -*) return 1 ;; esac
  case "$right" in -*) return 1 ;; esac
  git rev-parse --verify "$left" >/dev/null 2>&1 || return 1
  git rev-parse --verify "${right:-HEAD}" >/dev/null 2>&1
}

is_sensitive_path() {
  local path="$1"
  case "$path" in
    *.example|*.sample|*.template)
      return 1
      ;;
    .env|*/.env|.env/*|*/.env/*|.env.*|*/.env.*|.envrc|*/.envrc|.npmrc|*/.npmrc|\
    .pypirc|*/.pypirc|.netrc|*/.netrc|.aws/credentials|*/.aws/credentials|\
    *.pem|*.PEM|*.key|*.KEY|*.p12|*.pfx|*.jks|*.keystore|*.crt|*.cer|\
    id_rsa|*/id_rsa|id_dsa|*/id_dsa|id_ecdsa|*/id_ecdsa|id_ed25519|*/id_ed25519|\
    credentials.json|*/credentials.json|application_default_credentials.json|\
    */application_default_credentials.json|token.json|*/token.json)
      return 0
      ;;
  esac
  return 1
}

has_project_marker() {
  local dir="$1"
  [ -f "$dir/package.json" ] ||
    [ -f "$dir/Makefile" ] ||
    [ -f "$dir/go.mod" ] ||
    [ -f "$dir/Cargo.toml" ] ||
    [ -f "$dir/pyproject.toml" ] ||
    [ -f "$dir/setup.py" ] ||
    [ -f "$dir/setup.cfg" ] ||
    [ -f "$dir/pytest.ini" ] ||
    [ -f "$dir/tox.ini" ] ||
    [ -f "$dir/noxfile.py" ] ||
    [ -f "$dir/manage.py" ] ||
    [ -f "$dir/pom.xml" ] ||
    [ -f "$dir/build.gradle" ] ||
    [ -f "$dir/build.gradle.kts" ] ||
    [ -f "$dir/Package.swift" ] ||
    [ -f "$dir/Gemfile" ] ||
    [ -f "$dir/composer.json" ] ||
    [ -f "$dir/mix.exs" ] ||
    compgen -G "$dir/requirements*.txt" >/dev/null 2>&1 ||
    compgen -G "$dir/*.csproj" >/dev/null 2>&1 ||
    compgen -G "$dir/*.sln" >/dev/null 2>&1
}

find_command_dir() {
  local dir="$1"
  while :; do
    if has_project_marker "$dir"; then
      printf '%s\n' "$dir"
      return
    fi
    [ "$dir" = "$REPO_ROOT" ] && break
    dir="${dir%/*}"
    [ -n "$dir" ] || dir="/"
  done
  printf '%s\n' "$REPO_ROOT"
}

emit_cmd() {
  local kind="$1" cmd="$2" upper
  upper="$(printf '%s' "$kind" | tr '[:lower:]' '[:upper:]')"
  printf 'RFV_%s_CMD: %s\n' "$upper" "$cmd"
}

has_head || error "repository has no commits yet; make an initial commit" 5

IS_RANGE=0
if [ -n "$SCOPE" ] && is_range_spec "$SCOPE"; then
  IS_RANGE=1
fi

# Git diff omits untracked files, so refuse incomplete working-tree reviews.
if [ "$IS_RANGE" -eq 0 ]; then
  if [ -n "$SCOPE" ]; then
    if ! git ls-files --others --exclude-standard -z -- "$SCOPE" > "$PATHS_FILE"; then
      error "could not inspect untracked files" 6
    fi
  elif ! git ls-files --others --exclude-standard -z > "$PATHS_FILE"; then
    error "could not inspect untracked files" 6
  fi

  UNTRACKED_FILE=""
  while IFS= read -r -d '' file; do
    case "$file" in
      *$'\n'*|*$'\r'*) error "file paths with line breaks are unsupported" 6 ;;
    esac
    if is_sensitive_path "$file"; then
      error "sensitive untracked file must remain untracked and be removed from scope: $file" 7
    fi
    [ -n "$UNTRACKED_FILE" ] || UNTRACKED_FILE="$file"
  done < "$PATHS_FILE"

  if [ -n "$UNTRACKED_FILE" ]; then
    error "untracked files are excluded from Git diff; stage before review: $UNTRACKED_FILE" 6
  fi
fi

if [ -z "$SCOPE" ]; then
  if "${GIT_DIFF[@]}" --quiet && "${GIT_DIFF[@]}" --cached --quiet; then
    has_parent || error "empty diff; repository has only one clean commit" 4
    DIFF_ARGS=(HEAD~1..HEAD)
    SCOPE_KIND="last-commit"
    SCOPE_LABEL="no uncommitted changes; using HEAD~1..HEAD"
  else
    DIFF_ARGS=(HEAD)
    SCOPE_KIND="uncommitted"
    SCOPE_LABEL="uncommitted changes (staged and unstaged)"
  fi
elif [ "$IS_RANGE" -eq 1 ]; then
  DIFF_ARGS=("$SCOPE")
  SCOPE_KIND="range"
  SCOPE_LABEL="range $SCOPE"
else
  DIFF_ARGS=(HEAD -- "$SCOPE")
  SCOPE_KIND="path"
  SCOPE_LABEL="path $SCOPE"
fi

COMMAND_SEARCH_DIR="$(pwd -P)"
if [ "$SCOPE_KIND" = "path" ]; then
  if [ -d "$SCOPE" ]; then
    COMMAND_SEARCH_DIR="$(cd "$SCOPE" && pwd -P)"
  else
    SCOPE_DIR="${SCOPE%/*}"
    [ "$SCOPE_DIR" = "$SCOPE" ] && SCOPE_DIR="."
    [ -n "$SCOPE_DIR" ] || SCOPE_DIR="/"
    if [ -d "$SCOPE_DIR" ]; then
      COMMAND_SEARCH_DIR="$(cd "$SCOPE_DIR" && pwd -P)"
    fi
  fi
  case "$COMMAND_SEARCH_DIR" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) ;;
    *) COMMAND_SEARCH_DIR="$(pwd -P)" ;;
  esac
fi
COMMAND_DIR="$(find_command_dir "$COMMAND_SEARCH_DIR")"

if ! "${GIT_DIFF[@]}" --name-only --no-renames -z "${DIFF_ARGS[@]}" > "$PATHS_FILE" 2>/dev/null; then
  error "could not list changed files" 6
fi
[ -s "$PATHS_FILE" ] || error "empty diff; nothing to review" 4

while IFS= read -r -d '' file; do
  case "$file" in
    *$'\n'*|*$'\r'*) error "file paths with line breaks are unsupported" 6 ;;
  esac
  if is_sensitive_path "$file"; then
    error "sensitive file requires manual review and must be removed from scope: $file" 7
  fi
done < "$PATHS_FILE"

if ! NUMSTAT="$("${GIT_DIFF[@]}" --numstat "${DIFF_ARGS[@]}" 2>/dev/null)"; then
  error "could not calculate diff size" 6
fi
CHANGED_LINES="$(printf '%s\n' "$NUMSTAT" | awk '
  $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { total += $1 + $2; next }
  NF { total += 1 }
  END { print total + 0 }
')"

printf 'RFV_REPO_ROOT: %s\n' "$REPO_ROOT"
printf 'RFV_COMMAND_DIR: %s\n' "$COMMAND_DIR"
printf 'RFV_SCOPE_KIND: %s\n' "$SCOPE_KIND"
printf 'RFV_SCOPE: %s\n' "$SCOPE_LABEL"
printf 'RFV_CHANGED_LINES: %s\n' "$CHANGED_LINES"
while IFS= read -r -d '' file; do
  printf 'RFV_CHANGED_FILE: %s\n' "$file"
done < "$PATHS_FILE"

if [ "$CHANGED_LINES" -gt 800 ]; then
  warn "large diff ($CHANGED_LINES lines); consider a directory or commit scope"
fi

printf '%s\n' '=== DIFF ==='
if ! "${GIT_DIFF[@]}" "${DIFF_ARGS[@]}" 2>/dev/null | awk -v max="$MAX_DIFF_LINES" '
  NR <= max { print }
  { lines++ }
  END {
    print "=== END DIFF ==="
    if (lines > max) {
      printf "RFV_WARN: diff truncated at %d lines (%d total); set RFV_MAX_DIFF_LINES to increase\n", max, lines
    }
  }
'; then
  error "could not generate diff" 6
fi

detect_node_commands() {
  local runner scripts kind found=0

  command -v jq >/dev/null 2>&1 || {
    warn "jq not found; cannot parse package.json reliably"
    return
  }

  if ! runner="$(jq -r '.packageManager // empty | split("@")[0]' package.json 2>/dev/null)"; then
    warn "could not parse package.json"
    return
  fi
  case "$runner" in
    npm|pnpm|yarn|bun) ;;
    *)
      if [ -f pnpm-lock.yaml ]; then
        runner="pnpm"
      elif [ -f yarn.lock ]; then
        runner="yarn"
      elif [ -f bun.lock ] || [ -f bun.lockb ]; then
        runner="bun"
      else
        runner="npm"
      fi
      ;;
  esac

  if ! scripts="$(jq -r '
    (.scripts // {}) as $scripts
    | ["test", "lint", "typecheck", "check", "build"][] as $name
    | select($scripts[$name] != null)
    | $name
  ' package.json 2>/dev/null)"; then
    warn "could not parse package.json scripts"
    return
  fi

  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    emit_cmd "$kind" "$runner run $kind"
    found=1
  done <<< "$scripts"
  [ "$found" -eq 1 ] ||
    warn "package.json has no test, lint, typecheck, check, or build script"
}

detect_commands() {
  local targets target linter

  if [ -f package.json ]; then
    detect_node_commands
    return
  fi

  if [ -f Makefile ]; then
    targets="$(awk -F: '
      $1 ~ /^(test|lint|typecheck|check|build)$/ && !seen[$1]++ { print $1 }
    ' Makefile)"
    while IFS= read -r target; do
      [ -n "$target" ] && emit_cmd "$target" "make $target"
    done <<< "$targets"
    [ -n "$targets" ] || warn "Makefile has no recognized test or check target"
    return
  fi

  if [ -f go.mod ]; then
    emit_cmd test "go test ./..."
    emit_cmd lint "go vet ./..."
    return
  fi

  if [ -f Cargo.toml ]; then
    emit_cmd test "cargo test"
    emit_cmd lint "cargo clippy"
    return
  fi

  if [ -f pyproject.toml ]; then
    if grep -qE 'pytest|tool\.pytest' pyproject.toml 2>/dev/null ||
      [ -f pytest.ini ] || [ -f conftest.py ]; then
      emit_cmd test "python -m pytest"
    elif [ -f tox.ini ]; then
      emit_cmd test "tox"
    elif [ -f noxfile.py ]; then
      emit_cmd test "nox"
    elif [ -f manage.py ]; then
      emit_cmd test "python manage.py test"
    else
      warn "no Python test runner detected"
    fi
    for linter in ruff flake8; do
      if grep -q "$linter" pyproject.toml 2>/dev/null; then
        emit_cmd lint "python -m $linter"
        break
      fi
    done
    if grep -q "mypy" pyproject.toml 2>/dev/null; then
      emit_cmd typecheck "python -m mypy ."
    fi
    return
  fi

  if [ -f setup.py ] || [ -f setup.cfg ] ||
    compgen -G './requirements*.txt' >/dev/null 2>&1; then
    if grep -q "pytest" setup.py setup.cfg requirements*.txt 2>/dev/null ||
      [ -f pytest.ini ] || [ -f conftest.py ]; then
      emit_cmd test "python -m pytest"
    elif [ -f tox.ini ]; then
      emit_cmd test "tox"
    elif [ -f manage.py ]; then
      emit_cmd test "python manage.py test"
    else
      warn "no Python test runner detected"
    fi
    return
  fi

  if [ -f tox.ini ]; then
    emit_cmd test "tox"
    return
  fi

  if [ -f noxfile.py ]; then
    emit_cmd test "nox"
    return
  fi

  if [ -f pytest.ini ] || [ -f conftest.py ]; then
    emit_cmd test "python -m pytest"
    return
  fi

  if [ -f manage.py ]; then
    emit_cmd test "python manage.py test"
    return
  fi

  if [ -f pom.xml ]; then
    if [ -x mvnw ]; then emit_cmd test "./mvnw test"; else emit_cmd test "mvn test"; fi
    return
  fi

  if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    if [ -x gradlew ]; then emit_cmd test "./gradlew test"; else emit_cmd test "gradle test"; fi
    return
  fi

  if compgen -G './*.csproj' >/dev/null 2>&1 ||
    compgen -G './*.sln' >/dev/null 2>&1; then
    emit_cmd test "dotnet test"
    return
  fi

  if [ -f Package.swift ]; then
    emit_cmd test "swift test"
    return
  fi

  if [ -f Gemfile ]; then
    if grep -q "rspec" Gemfile 2>/dev/null; then
      emit_cmd test "bundle exec rspec"
    elif [ -f Rakefile ] && grep -qE '(^|[[:space:]])task[[:space:]]+:?test' Rakefile 2>/dev/null; then
      emit_cmd test "bundle exec rake test"
    else
      warn "no Ruby test command detected"
    fi
    return
  fi

  if [ -f composer.json ]; then
    if command -v jq >/dev/null 2>&1; then
      if ! jq -e . composer.json >/dev/null 2>&1; then
        warn "could not parse composer.json"
      elif jq -e '.scripts.test' composer.json >/dev/null 2>&1; then
        emit_cmd test "composer test"
      elif grep -q "phpunit" composer.json 2>/dev/null; then
        emit_cmd test "./vendor/bin/phpunit"
      else
        warn "no Composer test command detected"
      fi
    elif grep -q "phpunit" composer.json 2>/dev/null; then
      emit_cmd test "./vendor/bin/phpunit"
    else
      warn "jq not found and no Composer test command detected"
    fi
    return
  fi

  if [ -f mix.exs ]; then
    emit_cmd test "mix test"
    return
  fi

  warn "no test command detected; ask the user"
}

printf '%s\n' '=== COMMANDS ==='
(
  cd "$COMMAND_DIR"
  detect_commands
)
