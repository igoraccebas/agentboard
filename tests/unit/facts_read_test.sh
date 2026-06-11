#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_read_fixture() {
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
    "$TEST_ROOT/bin/agentboard" new-domain billing >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
}

test_brief_shows_red_gotcha_from_unrelated_domain() {
  local dir output
  dir="$(mktemp -d)"
  setup_read_fixture "$dir"
  run_cli_capture output "$dir" fact new --type gotcha --severity red \
    --domain billing --title "stripe keys rotate monthly"
  run_cli_capture output "$dir" brief
  assert_contains "$output" "stripe keys rotate monthly"
}

test_brief_scopes_yellow_facts_to_active_domains() {
  local dir output
  dir="$(mktemp -d)"
  setup_read_fixture "$dir"
  # active stream is on auth; billing yellow fact should stay off the brief
  run_cli_capture output "$dir" fact new --type gotcha --severity yellow \
    --domain billing --title "billing cron is flaky at midnight"
  run_cli_capture output "$dir" fact new --type gotcha --severity yellow \
    --domain auth --title "session cookies need SameSite=Lax"
  run_cli_capture output "$dir" brief
  assert_contains "$output" "session cookies need SameSite=Lax"
  assert_not_contains "$output" "billing cron is flaky at midnight"
}

test_brief_shows_untagged_facts() {
  local dir output
  dir="$(mktemp -d)"
  setup_read_fixture "$dir"
  run_cli_capture output "$dir" fact new --type learning \
    --title "repo uses conventional commits"
  run_cli_capture output "$dir" brief
  assert_contains "$output" "repo uses conventional commits"
}

test_handoff_lists_domain_matching_facts() {
  local dir output
  dir="$(mktemp -d)"
  setup_read_fixture "$dir"
  run_cli_capture output "$dir" fact new --type learning --domain auth \
    --title "auth middleware caches tokens for 5m"
  run_cli_capture output "$dir" fact new --type learning --domain billing \
    --title "billing only fact"
  run_cli_capture output "$dir" handoff login
  assert_contains "$output" "Relevant facts"
  assert_contains "$output" "auth middleware caches tokens for 5m"
  assert_not_contains "$output" "billing only fact"
}

test_doctor_flags_invalid_fact() {
  local dir output fact_file
  dir="$(mktemp -d)"
  setup_read_fixture "$dir"
  run_cli_capture output "$dir" fact new --type gotcha --severity red \
    --domain auth --title "valid fact"
  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "memory/facts validate"
  # Corrupt the fact: invalid status enum
  fact_file="$(ls "$dir/.platform/memory/facts/"F-001-*.md)"
  sed -i.bak 's/^status: .*/status: maybe/' "$fact_file" && rm -f "$fact_file.bak"
  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "invalid status"
}

test_doctor_warns_on_unknown_domain_tag() {
  local dir output fact_file
  dir="$(mktemp -d)"
  setup_read_fixture "$dir"
  run_cli_capture output "$dir" fact new --type learning --title "tagged oddly"
  fact_file="$(ls "$dir/.platform/memory/facts/"F-001-*.md)"
  sed -i.bak 's/^domains: .*/domains: [ghosts]/' "$fact_file" && rm -f "$fact_file.bak"
  run_cli_capture output "$dir" doctor
  # Unknown domain is a warning, not an error
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "unknown domain: ghosts"
}

for t in \
  test_brief_shows_red_gotcha_from_unrelated_domain \
  test_brief_scopes_yellow_facts_to_active_domains \
  test_brief_shows_untagged_facts \
  test_handoff_lists_domain_matching_facts \
  test_doctor_flags_invalid_fact \
  test_doctor_warns_on_unknown_domain_tag; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
