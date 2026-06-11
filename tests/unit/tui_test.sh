#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_tui_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --agent claude \
      --base-branch main --branch feat/login >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream billing-fix \
      --domain auth --agent codex \
      --base-branch main --branch fix/billing >/dev/null
  )
}

test_tui_renders_header_and_rows() {
  local dir output
  dir="$(mktemp -d)"
  setup_tui_fixture "$dir"
  run_cli_capture output "$dir" tui --once
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "stream"
  assert_contains "$output" "status"
  assert_contains "$output" "branch"
  assert_contains "$output" "login"
  assert_contains "$output" "billing-fix"
  assert_contains "$output" "feat/login"
  assert_contains "$output" "2 shown / 2 stream(s)"
}

test_tui_status_filter() {
  local dir output
  dir="$(mktemp -d)"
  setup_tui_fixture "$dir"
  # Flip one stream's status so the filter has something to split on
  sed -i.bak 's/^status: .*/status: in-progress/' "$dir/.platform/work/login.md"
  rm -f "$dir/.platform/work/login.md.bak"
  run_cli_capture output "$dir" tui --once --status in-progress
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "login"
  assert_not_contains "$output" "billing-fix"
  assert_contains "$output" "1 shown / 2 stream(s)"
}

test_tui_owner_filter() {
  local dir output
  dir="$(mktemp -d)"
  setup_tui_fixture "$dir"
  run_cli_capture output "$dir" tui --once --owner codex
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "billing-fix"
  assert_not_contains "$output" "feat/login"
}

test_tui_filter_with_no_matches() {
  local dir output
  dir="$(mktemp -d)"
  setup_tui_fixture "$dir"
  run_cli_capture output "$dir" tui --once --status done
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "no streams match the filter"
}

test_tui_help_and_unknown_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_tui_fixture "$dir"
  run_cli_capture output "$dir" tui --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard tui"
  run_cli_capture output "$dir" tui --sideways
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown flag for tui"
}

test_tui_is_read_only() {
  local dir output before after
  dir="$(mktemp -d)"
  setup_tui_fixture "$dir"
  before="$(cat "$dir/.platform/work/login.md" "$dir/.platform/work/ACTIVE.md")"
  run_cli_capture output "$dir" tui --once
  after="$(cat "$dir/.platform/work/login.md" "$dir/.platform/work/ACTIVE.md")"
  [[ "$before" == "$after" ]] || fail "tui modified stream state — it must be read-only"
}

for t in \
  test_tui_renders_header_and_rows \
  test_tui_status_filter \
  test_tui_owner_filter \
  test_tui_filter_with_no_matches \
  test_tui_help_and_unknown_flag \
  test_tui_is_read_only; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
