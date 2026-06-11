#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_approve_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
}

# Simulate what the ab-planner agent writes: an Execution brief section.
write_brief() {
  local dir="$1"
  cat >> "$dir/.platform/work/login.md" <<'EOF'

## Execution brief
_Written by ab-planner (opus) on 2026-06-13._

**Objective:** add session refresh middleware

**Do:**
- implement refresh in src/auth/middleware.py

**Do NOT:**
- touch the billing module

**Acceptance criteria:**
- [ ] tests pass
EOF
}

test_approve_requires_a_brief() {
  local dir output
  dir="$(mktemp -d)"
  setup_approve_fixture "$dir"
  run_cli_capture output "$dir" approve login
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "nothing to approve"
}

test_approve_inserts_and_flips_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_approve_fixture "$dir"
  write_brief "$dir"
  # Key absent from frontmatter (planner may forget) — approve inserts it
  run_cli_capture output "$dir" approve login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "approved"
  assert_file_contains "$dir/.platform/work/login.md" "brief_approved: true"
  # Idempotent
  run_cli_capture output "$dir" approve login
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "already approved"
}

test_revoke_sets_false() {
  local dir output
  dir="$(mktemp -d)"
  setup_approve_fixture "$dir"
  write_brief "$dir"
  run_cli_capture output "$dir" approve login
  run_cli_capture output "$dir" approve login --revoke
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "revoked"
  assert_file_contains "$dir/.platform/work/login.md" "brief_approved: false"
}

test_handoff_shows_gate_status() {
  local dir output
  dir="$(mktemp -d)"
  setup_approve_fixture "$dir"
  write_brief "$dir"
  run_cli_capture output "$dir" handoff login
  assert_contains "$output" "awaiting approval"
  assert_contains "$output" "do NOT write code"
  run_cli_capture output "$dir" approve login
  run_cli_capture output "$dir" handoff login
  assert_contains "$output" "approved"
  assert_not_contains "$output" "awaiting approval"
}

test_brief_marks_ungated_vs_gated_streams() {
  local dir output
  dir="$(mktemp -d)"
  setup_approve_fixture "$dir"
  # No execution brief → no gate marker
  run_cli_capture output "$dir" brief
  assert_not_contains "$output" "brief awaiting approval"
  write_brief "$dir"
  run_cli_capture output "$dir" brief
  assert_contains "$output" "brief awaiting approval"
  run_cli_capture output "$dir" approve login
  run_cli_capture output "$dir" brief
  assert_not_contains "$output" "brief awaiting approval"
}

test_bash_guard_intercepts_approve() {
  local guard="$TEST_ROOT/templates/platform/scripts/hooks/bash-guard.sh"
  local output
  output="$(printf '{"tool_name":"Bash","tool_input":{"command":"agentboard approve login"}}' | bash "$guard")"
  assert_contains "$output" '"permissionDecision":"ask"'
  # Innocent commands stay silent
  output="$(printf '{"tool_name":"Bash","tool_input":{"command":"agentboard brief"}}' | bash "$guard")"
  [[ -z "$output" ]] || fail "guard should stay silent for non-gated commands"
}

test_init_installs_planner_agent() {
  local dir
  dir="$(mktemp -d)"
  setup_approve_fixture "$dir"
  [[ -f "$dir/.claude/agents/ab-planner.md" ]] || fail "ab-planner.md not installed by init"
  assert_file_contains "$dir/.claude/agents/ab-planner.md" "model: opus"
}

for t in \
  test_approve_requires_a_brief \
  test_approve_inserts_and_flips_flag \
  test_revoke_sets_false \
  test_handoff_shows_gate_status \
  test_brief_marks_ungated_vs_gated_streams \
  test_bash_guard_intercepts_approve \
  test_init_installs_planner_agent; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
