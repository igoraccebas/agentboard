#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_watch_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add -A
    git commit -m "agentboard init" >/dev/null 2>&1
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
    git add -A
    git commit -m "new stream" >/dev/null 2>&1
  )
}

# Backdate the stream file's mtime past the 5-min skip window so watch will
# actually process it. Otherwise new-stream just created it and watch skips.
_age_stream_file() {
  local stream_file="$1"
  # Set mtime to 10 minutes ago — well outside the 5-minute skip window.
  if [[ "$(uname)" == "Darwin" ]]; then
    touch -A -001000 "$stream_file" 2>/dev/null || touch -t "$(date -v -10M +%Y%m%d%H%M)" "$stream_file"
  else
    touch -d "10 minutes ago" "$stream_file"
  fi
}

test_watch_help() {
  local dir output
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  run_cli_capture output "$dir" watch --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard watch"
  assert_contains "$output" "--interval"
  assert_contains "$output" "--threshold"
  assert_contains "$output" "--stop"
}

test_watch_once_no_changes_does_nothing() {
  local dir output stream_file
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  _age_stream_file "$stream_file"

  run_cli_capture output "$dir" watch --once
  assert_status "$RUN_STATUS" 0
  # No "auto-watch" line should be in the resume state
  assert_file_not_contains "$stream_file" "(auto-watch)"
}

test_watch_once_with_change_auto_checkpoints() {
  local dir output stream_file
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  _age_stream_file "$stream_file"

  # Introduce a tracked-file change
  (
    cd "$dir"
    printf 'change\n' >> package.json
  )

  run_cli_capture output "$dir" watch --once
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$stream_file" "(auto-watch)"
  assert_file_contains "$stream_file" "package.json"
}

test_watch_once_skips_when_stream_fresh() {
  local dir output stream_file
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  # Stream was JUST created (fresh mtime) — watch should skip

  (
    cd "$dir"
    printf 'change\n' >> package.json
  )

  run_cli_capture output "$dir" watch --once
  assert_status "$RUN_STATUS" 0
  # Skipped → no auto-watch content written
  assert_file_not_contains "$stream_file" "(auto-watch)"
}

test_watch_rejects_unknown_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  run_cli_capture output "$dir" watch --not-a-flag
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown flag"
}

test_watch_stop_with_no_running_watcher() {
  local dir output
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  run_cli_capture output "$dir" watch --stop
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No watcher running"
}

test_watch_auto_detects_single_active_stream() {
  local dir output stream_file
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  _age_stream_file "$stream_file"
  (
    cd "$dir"
    printf 'change\n' >> package.json
  )

  # No --stream flag — should auto-pick 'login' since it's the only active one
  run_cli_capture output "$dir" watch --once
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$stream_file" "(auto-watch)"
}

test_watch_once_all_active_streams() {
  local dir output stream1 stream2
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  stream1="$dir/.platform/work/login.md"
  # Create a second active stream
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" new-stream payments \
      --domain auth --base-branch main --branch feat/payments >/dev/null
    git add -A
    git commit -m "new stream payments" >/dev/null 2>&1
  )
  stream2="$dir/.platform/work/payments.md"
  _age_stream_file "$stream1"
  _age_stream_file "$stream2"

  (
    cd "$dir"
    printf 'change\n' >> package.json
  )

  # No --stream flag — should auto-pick both active streams and checkpoint both
  run_cli_capture output "$dir" watch --once
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$stream1" "(auto-watch)"
  assert_file_contains "$stream2" "(auto-watch)"
}

test_watch_fails_when_no_active_stream() {
  local dir output
  dir="$(mktemp -d)"
  setup_watch_fixture "$dir"
  # Close/archive the only active stream so auto-detect has nothing to pick
  (
    cd "$dir"
    replace_template_literals .platform/work/login.md '\[ \]' '[x]'
    "$TEST_ROOT/bin/agentboard" close login --approve >/dev/null
    "$TEST_ROOT/bin/agentboard" close login --confirm >/dev/null
  )
  run_cli_capture output "$dir" watch --once
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "auto-detect"
}

for t in \
  test_watch_help \
  test_watch_once_no_changes_does_nothing \
  test_watch_once_with_change_auto_checkpoints \
  test_watch_once_skips_when_stream_fresh \
  test_watch_rejects_unknown_flag \
  test_watch_stop_with_no_running_watcher \
  test_watch_auto_detects_single_active_stream \
  test_watch_once_all_active_streams \
  test_watch_fails_when_no_active_stream; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
