#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_facts_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" new-domain billing >/dev/null
  )
}

test_fact_new_creates_file_and_index() {
  local dir
  dir="$(mktemp -d)"
  setup_facts_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" fact new --type gotcha --severity red \
      --domain billing --stream pay-flow \
      --title "stripe webhooks replay on retry" >/dev/null
  )
  local fact_file
  fact_file="$(ls "$dir/.platform/memory/facts/"F-001-*.md)"
  [[ -f "$fact_file" ]] || fail "fact file not created"
  assert_file_contains "$fact_file" "fact_id: F-001"
  assert_file_contains "$fact_file" "type: gotcha"
  assert_file_contains "$fact_file" "severity: red"
  assert_file_contains "$fact_file" "domains: [billing]"
  assert_file_contains "$fact_file" "source_stream: pay-flow"
  assert_file_contains "$fact_file" "status: active"
  assert_file_contains "$dir/.platform/memory/INDEX.md" "F-001"
  assert_file_contains "$dir/.platform/memory/INDEX.md" "stripe webhooks replay on retry"
}

test_fact_ids_increment() {
  local dir
  dir="$(mktemp -d)"
  setup_facts_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" fact new --type learning --title "first" >/dev/null
    "$TEST_ROOT/bin/agentboard" fact new --type learning --title "second" >/dev/null
  )
  assert_file_contains "$dir/.platform/memory/INDEX.md" "F-001"
  assert_file_contains "$dir/.platform/memory/INDEX.md" "F-002"
}

test_fact_new_rejects_bad_type_and_severity() {
  local dir output
  dir="$(mktemp -d)"
  setup_facts_fixture "$dir"
  run_cli_capture output "$dir" fact new --type vibe --title "x"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Invalid fact type"
  run_cli_capture output "$dir" fact new --type learning --severity red --title "x"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "--severity only applies to gotchas"
}

test_fact_list_filters_by_domain_and_type() {
  local dir output
  dir="$(mktemp -d)"
  setup_facts_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" fact new --type gotcha --domain billing --title "billing trap" >/dev/null
    "$TEST_ROOT/bin/agentboard" fact new --type learning --title "general note" >/dev/null
  )
  output="$(cd "$dir" && "$TEST_ROOT/bin/agentboard" fact list --domain billing)"
  assert_contains "$output" "billing trap"
  assert_not_contains "$output" "general note"
  output="$(cd "$dir" && "$TEST_ROOT/bin/agentboard" fact list --type learning)"
  assert_contains "$output" "general note"
  assert_not_contains "$output" "billing trap"
}

test_fact_prune_expires_past_dated_facts() {
  local dir output fact_file
  dir="$(mktemp -d)"
  setup_facts_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" fact new --type gotcha --title "old temp workaround" \
      --expires 2020-01-01 >/dev/null
    "$TEST_ROOT/bin/agentboard" fact new --type gotcha --title "keeper" >/dev/null
  )
  output="$(cd "$dir" && "$TEST_ROOT/bin/agentboard" fact prune)"
  assert_contains "$output" "old temp workaround"
  assert_not_contains "$output" "keeper"
  (cd "$dir" && "$TEST_ROOT/bin/agentboard" fact prune --apply >/dev/null)
  fact_file="$(ls "$dir/.platform/memory/facts/"F-001-*.md)"
  assert_file_contains "$fact_file" "status: expired"
  # Expired facts leave the index but keep their file
  assert_file_not_contains "$dir/.platform/memory/INDEX.md" "old temp workaround"
  assert_file_contains "$dir/.platform/memory/INDEX.md" "keeper"
}

for t in \
  test_fact_new_creates_file_and_index \
  test_fact_ids_increment \
  test_fact_new_rejects_bad_type_and_severity \
  test_fact_list_filters_by_domain_and_type \
  test_fact_prune_expires_past_dated_facts; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
