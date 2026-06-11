#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_brief_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add .platform .claude CLAUDE.md
    git commit -m "agentboard init" >/dev/null 2>&1
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
}

test_init_scaffolds_memory_files() {
  local dir
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  [[ -f "$dir/.platform/memory/decisions.md" ]] || fail "memory/decisions.md not scaffolded by init"
  [[ -f "$dir/.platform/memory/log.md" ]] || fail "memory/log.md not scaffolded by init"
  [[ -f "$dir/.platform/memory/BACKLOG.md" ]] || fail "memory/BACKLOG.md not scaffolded by init"
  [[ -f "$dir/.platform/memory/INDEX.md" ]] || fail "memory/INDEX.md not scaffolded by init"
  # Legacy category files are no longer shipped — facts replaced them
  [[ ! -f "$dir/.platform/memory/gotchas.md" ]] || fail "legacy gotchas.md still scaffolded"
  [[ ! -f "$dir/.platform/memory/playbook.md" ]] || fail "legacy playbook.md still scaffolded"
  [[ ! -f "$dir/.platform/memory/open-questions.md" ]] || fail "legacy open-questions.md still scaffolded"
  [[ ! -f "$dir/.platform/memory/learnings.md" ]] || fail "legacy learnings.md still scaffolded"
}

test_brief_shows_active_stream() {
  local dir output
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  run_cli_capture output "$dir" brief
  if (( RUN_STATUS != 0 )); then
    printf 'brief output (status=%s):\n%s\n' "$RUN_STATUS" "$output" >&2
  fi
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Active streams"
  assert_contains "$output" "login"
}

test_brief_shows_gotchas_when_present() {
  # Pre-migration projects still have a legacy gotchas.md — brief must keep
  # reading it until migrate-memory runs.
  local dir output
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  cat > "$dir/.platform/memory/gotchas.md" <<'EOF'
# Gotchas

<!-- agentboard:gotchas:begin -->
🔴 [auth] — never refactor middleware without running integration suite (mocks lie)
<!-- agentboard:gotchas:end -->
EOF
  run_cli_capture output "$dir" brief
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Gotchas"
  assert_contains "$output" "never refactor middleware"
  assert_contains "$output" "migrate-memory"
}

test_brief_reports_empty_state_gracefully() {
  local dir output
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  run_cli_capture output "$dir" brief
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Active streams"
  # No legacy files and no facts yet: those sections stay silent, no errors
  assert_not_contains "$output" "Gotchas"
  assert_not_contains "$output" "Facts in scope"
}

test_brief_help() {
  local dir output
  dir="$(mktemp -d)"
  setup_brief_fixture "$dir"
  run_cli_capture output "$dir" brief --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard brief"
}

for t in \
  test_init_scaffolds_memory_files \
  test_brief_shows_active_stream \
  test_brief_shows_gotchas_when_present \
  test_brief_reports_empty_state_gracefully \
  test_brief_help; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
