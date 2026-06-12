#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

HOOK="$TEST_ROOT/templates/platform/scripts/hooks/platform-bootstrap.sh"

setup_gate_fixture() {
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
  )
}

# Insert a brief_approved line into the stream frontmatter, after closure_approved.
_set_brief_flag() {
  local file="$1" value="$2"
  awk -v val="$value" '{print} /^closure_approved:/{print "brief_approved: " val}' \
    "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

run_hook_capture() {
  local __resultvar="$1" dir="$2"
  local tmp captured status
  tmp="$(mktemp)"
  set +e
  (
    cd "$dir" || exit 1
    bash "$HOOK"
  ) >"$tmp" 2>&1
  status=$?
  captured="$(cat "$tmp")"
  rm -f "$tmp"
  set -e
  RUN_STATUS="$status"
  printf -v "$__resultvar" '%s' "$captured"
  return 0
}

test_brief_gate_no_brief_yet() {
  local dir output
  dir="$(mktemp -d)"
  setup_gate_fixture "$dir"
  run_hook_capture output "$dir"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "brief:   — no brief yet"
}

test_brief_gate_not_approved() {
  local dir output
  dir="$(mktemp -d)"
  setup_gate_fixture "$dir"
  _set_brief_flag "$dir/.platform/work/login.md" false
  run_hook_capture output "$dir"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "brief:   ⛔ not approved"
  assert_not_contains "$output" "brief:   ✓ approved"
}

test_brief_gate_approved() {
  local dir output
  dir="$(mktemp -d)"
  setup_gate_fixture "$dir"
  _set_brief_flag "$dir/.platform/work/login.md" true
  run_hook_capture output "$dir"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "brief:   ✓ approved"
  assert_not_contains "$output" "brief:   ⛔ not approved"
}

test_brief_gate_hard_rule_with_streams() {
  local dir output
  dir="$(mktemp -d)"
  setup_gate_fixture "$dir"
  run_hook_capture output "$dir"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "⛔ medium+ scope work requires an approved Execution brief before execution"
}

test_brief_gate_hard_rule_no_streams() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  # Minimal registry with no stream rows — exercises the empty-registry branch.
  # (The shipped ACTIVE.md's lifecycle table trips the known F-005 phantom-row
  # parse, which is out of scope here — keep the fixture to just the header.)
  printf '| Stream | Type | Status | Agent | Last updated |\n|---|---|---|---|---|\n' \
    > "$dir/.platform/work/ACTIVE.md"
  run_hook_capture output "$dir"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Active streams: none"
  assert_contains "$output" "⛔ medium+ scope work requires an approved Execution brief before execution"
}

test_live_copy_matches_template() {
  diff "$HOOK" "$TEST_ROOT/.platform/scripts/hooks/platform-bootstrap.sh" >/dev/null \
    || fail "live .platform hook copy differs from template"
}

for t in \
  test_brief_gate_no_brief_yet \
  test_brief_gate_not_approved \
  test_brief_gate_approved \
  test_brief_gate_hard_rule_with_streams \
  test_brief_gate_hard_rule_no_streams \
  test_live_copy_matches_template; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
