#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_close_fixture() {
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
    # Model the owner's completed review before testing finalization.
    replace_frontmatter_line .platform/work/login.md closure_approved true
    replace_template_literals .platform/work/login.md '\[ \]' '[x]'
  )
}

test_close_without_confirm_prints_harvest_checklist() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  run_cli_capture output "$dir" close login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Harvest checklist"
  assert_contains "$output" "GOTCHAS"
  assert_contains "$output" "PLAYBOOK"
  assert_contains "$output" "OPEN QUESTIONS"
  assert_contains "$output" "close login --confirm"
  # Stream file should NOT be archived yet
  [[ -f "$dir/.platform/work/login.md" ]] || fail "stream file was archived without --confirm"
}

test_close_confirm_archives_stream() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  run_cli_capture output "$dir" close login --confirm
  assert_status "$RUN_STATUS" 0
  [[ ! -f "$dir/.platform/work/login.md" ]] || fail "stream file still present after --confirm"
  [[ -f "$dir/.platform/work/archive/login.md" ]] || fail "stream was not moved to archive/"
  assert_file_contains "$dir/.platform/work/archive/login.md" "status: done"
  assert_file_contains "$dir/.platform/work/archive/login.md" "closure_approved: true"
}

test_close_confirm_appends_log_entry() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  run_cli_capture output "$dir" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.platform/memory/log.md" "closed stream login"
}

test_close_confirm_removes_from_active_registry() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  # Baseline: active registry lists the stream
  assert_file_contains "$dir/.platform/work/ACTIVE.md" "login"
  run_cli_capture output "$dir" close login --confirm
  assert_status "$RUN_STATUS" 0
  assert_file_not_contains "$dir/.platform/work/ACTIVE.md" "| login |"
}

test_close_dry_run_writes_nothing() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  run_cli_capture output "$dir" close login --confirm --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Would archive"
  [[ -f "$dir/.platform/work/login.md" ]] || fail "dry-run archived the stream file"
}

test_close_rejects_bad_slug() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  run_cli_capture output "$dir" close "Bad_Slug"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "kebab-case"
}

test_close_rejects_missing_stream() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  run_cli_capture output "$dir" close nonexistent
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "not found"
}

test_close_help() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  run_cli_capture output "$dir" close --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard close"
}

test_close_without_confirm_prints_harvest_checklist
test_close_confirm_archives_stream
test_close_confirm_appends_log_entry
test_close_confirm_removes_from_active_registry
test_close_dry_run_writes_nothing
test_close_rejects_bad_slug
test_close_rejects_missing_stream
test_close_help
