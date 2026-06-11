#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_auto_fixture() {
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

test_auto_detects_stream_and_derives_what() {
  local dir output
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"
  printf 'change\n' > "$dir/dirty.txt"
  run_cli_capture output "$dir" checkpoint --auto
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Checkpoint saved"
  assert_file_contains "$dir/.platform/work/login.md" "auto-checkpoint"
  assert_file_contains "$dir/.platform/work/login.md" "uncommitted file(s)"
}

test_auto_noop_when_tree_clean_and_no_commits_today() {
  local dir output before
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"
  # Make HEAD look old so "commits today" is zero
  (
    cd "$dir"
    git add -A >/dev/null 2>&1
    GIT_COMMITTER_DATE="2020-01-01T10:00:00" git commit --date "2020-01-01T10:00:00" \
      -m "old work" >/dev/null 2>&1
  )
  before="$(cat "$dir/.platform/work/login.md")"
  run_cli_capture output "$dir" checkpoint --auto
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "nothing to record"
  [[ "$before" == "$(cat "$dir/.platform/work/login.md")" ]] || \
    fail "auto checkpoint must not modify the stream when there is nothing to record"
}

test_auto_preserves_existing_next_action() {
  local dir output
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"
  run_cli_capture output "$dir" checkpoint login \
    --what "manual progress" --next "wire the session token refresh"
  printf 'change\n' > "$dir/dirty.txt"
  run_cli_capture output "$dir" checkpoint --auto
  assert_file_contains "$dir/.platform/work/login.md" "wire the session token refresh"
}

test_auto_skips_closed_streams() {
  local dir output
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"
  # Close the only stream, then auto-checkpoint should no-op
  (
    cd "$dir"
    sed -i.bak 's/^status: .*/status: done/' .platform/work/login.md
    rm -f .platform/work/login.md.bak
  )
  printf 'change\n' > "$dir/dirty.txt"
  run_cli_capture output "$dir" checkpoint --auto
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "no active stream"
}

test_explicit_slug_with_auto_still_works() {
  local dir output
  dir="$(mktemp -d)"
  setup_auto_fixture "$dir"
  printf 'change\n' > "$dir/dirty.txt"
  run_cli_capture output "$dir" checkpoint login --auto
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$dir/.platform/work/login.md" "auto-checkpoint"
}

for t in \
  test_auto_detects_stream_and_derives_what \
  test_auto_noop_when_tree_clean_and_no_commits_today \
  test_auto_preserves_existing_next_action \
  test_auto_skips_closed_streams \
  test_explicit_slug_with_auto_still_works; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
