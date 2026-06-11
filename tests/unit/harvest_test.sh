#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_harvest_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
}

make_auto_memory() {
  local mem_dir="$1"
  mkdir -p "$mem_dir"
  cat > "$mem_dir/MEMORY.md" <<'EOF'
# Project memory

- the build needs node 20, nvm use 20 before anything
- payments tests hit the live sandbox unless STRIPE_MOCK=1

## Notes
not a bullet, should be ignored
EOF
  cat > "$mem_dir/debugging.md" <<'EOF'
- prod logs are in datadog, not cloudwatch
EOF
}

test_harvest_lists_candidates_without_writing() {
  local dir mem output
  dir="$(mktemp -d)"
  mem="$(mktemp -d)"
  setup_harvest_fixture "$dir"
  make_auto_memory "$mem"
  run_cli_capture output "$dir" harvest --source "$mem"
  assert_contains "$output" "the build needs node 20"
  assert_contains "$output" "payments tests hit the live sandbox"
  assert_contains "$output" "prod logs are in datadog"
  assert_not_contains "$output" "not a bullet"
  [[ ! -d "$dir/.platform/memory/facts" ]] || \
    [[ -z "$(ls -A "$dir/.platform/memory/facts" 2>/dev/null)" ]] || \
    fail "bare harvest must not create facts"
}

test_harvest_accept_promotes_selected_note() {
  local dir mem output
  dir="$(mktemp -d)"
  mem="$(mktemp -d)"
  setup_harvest_fixture "$dir"
  make_auto_memory "$mem"
  run_cli_capture output "$dir" harvest --source "$mem" --accept 2 --type gotcha
  assert_contains "$output" "Promoted: payments tests hit the live sandbox"
  local fact_file
  fact_file="$(ls "$dir/.platform/memory/facts/"F-001-*.md)"
  assert_file_contains "$fact_file" "type: gotcha"
  assert_file_contains "$fact_file" "payments tests hit the live sandbox"
  assert_file_contains "$fact_file" "Harvested from Claude auto-memory"
  # Only the accepted note was promoted
  run_cli_capture output "$dir" fact list
  assert_not_contains "$output" "node 20"
}

test_harvest_dedupes_against_existing_facts() {
  local dir mem output
  dir="$(mktemp -d)"
  mem="$(mktemp -d)"
  setup_harvest_fixture "$dir"
  make_auto_memory "$mem"
  run_cli_capture output "$dir" fact new --type learning \
    --title "the build needs node 20, nvm use 20 before anything"
  run_cli_capture output "$dir" harvest --source "$mem"
  assert_not_contains "$output" " 1. the build needs node 20"
  assert_contains "$output" "payments tests hit the live sandbox"
}

test_harvest_all_dry_run_writes_nothing() {
  local dir mem output
  dir="$(mktemp -d)"
  mem="$(mktemp -d)"
  setup_harvest_fixture "$dir"
  make_auto_memory "$mem"
  run_cli_capture output "$dir" harvest --source "$mem" --all --dry-run
  assert_contains "$output" "would create fact"
  [[ -z "$(ls -A "$dir/.platform/memory/facts" 2>/dev/null)" ]] || \
    fail "dry-run must not create facts"
}

test_harvest_missing_source_is_graceful() {
  local dir output
  dir="$(mktemp -d)"
  setup_harvest_fixture "$dir"
  run_cli_capture output "$dir" harvest --source "$dir/does-not-exist"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "No Claude auto-memory found"
}

for t in \
  test_harvest_lists_candidates_without_writing \
  test_harvest_accept_promotes_selected_note \
  test_harvest_dedupes_against_existing_facts \
  test_harvest_all_dry_run_writes_nothing \
  test_harvest_missing_source_is_graceful; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
