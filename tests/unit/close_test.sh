#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1
export AGENTBOARD_APPROVER=owner-test

# A registered stream with nothing approved yet.
setup_stream_fixture() {
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

# The owner ticks the criteria in their editor, then records approval through
# the CLI — the only path that writes the approval record.
setup_close_fixture() {
  local dir="$1"
  setup_stream_fixture "$dir"
  (
    cd "$dir"
    replace_template_literals .platform/work/login.md '\[ \]' '[x]'
    "$TEST_ROOT/bin/agentboard" close login --approve >/dev/null
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
  assert_contains "$output" "--approve"
}

test_close_approve_records_the_cli_pair() {
  local dir
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  assert_file_contains "$dir/.platform/work/login.md" "closure_approved: true"
  assert_file_contains "$dir/.platform/work/login.md" "approved_by: owner-test"
  grep -Eq '^approved_at: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' "$dir/.platform/work/login.md" \
    || fail "approved_at was not recorded"
}

test_close_approve_refuses_unchecked_criteria() {
  local dir output
  dir="$(mktemp -d)"
  setup_stream_fixture "$dir"
  run_cli_capture output "$dir" close login --approve
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unchecked done criteria"
  assert_contains "$output" "_TODO: measurable acceptance criterion_"
  assert_file_contains "$dir/.platform/work/login.md" "closure_approved: false"
  assert_file_not_contains "$dir/.platform/work/login.md" "approved_by:"
}

test_close_confirm_refuses_a_hand_forged_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_stream_fixture "$dir"
  (
    cd "$dir"
    replace_template_literals .platform/work/login.md '\[ \]' '[x]'
    replace_frontmatter_line .platform/work/login.md closure_approved true
  )
  run_cli_capture output "$dir" close login --confirm
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "not recorded by the CLI"
  assert_contains "$output" "close login --approve"
  [[ -f "$dir/.platform/work/login.md" ]] || fail "a forged flag archived the stream"
}

test_close_approve_revoke_clears_the_record() {
  local dir output
  dir="$(mktemp -d)"
  setup_close_fixture "$dir"
  run_cli_capture output "$dir" close login --approve --revoke
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.platform/work/login.md" "closure_approved: false"
  assert_file_not_contains "$dir/.platform/work/login.md" "approved_by:"
  assert_file_not_contains "$dir/.platform/work/login.md" "approved_at:"
  run_cli_capture output "$dir" close login --confirm
  assert_status "$RUN_STATUS" 1
}

test_close_without_confirm_prints_harvest_checklist
test_close_confirm_archives_stream
test_close_confirm_appends_log_entry
test_close_confirm_removes_from_active_registry
test_close_dry_run_writes_nothing
test_close_rejects_bad_slug
test_close_rejects_missing_stream
test_close_help
test_close_approve_records_the_cli_pair
test_close_approve_refuses_unchecked_criteria
test_close_confirm_refuses_a_hand_forged_flag
test_close_approve_revoke_clears_the_record
