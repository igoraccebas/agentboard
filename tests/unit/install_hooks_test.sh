#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

GUARD="$TEST_ROOT/templates/platform/scripts/hooks/bash-guard.sh"

# ─── guard script behavior (no project required) ──────────────────────────

_guard_run() {
  local payload="$1"
  printf '%s' "$payload" | bash "$GUARD"
}

test_guard_allows_benign_bash() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}')"
  [[ -z "$out" ]] || fail "expected empty output for benign cmd, got: $out"
}

test_guard_blocks_git_commit() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git commit, got: $out"
}

test_guard_blocks_git_push() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git push, got: $out"
}

test_guard_blocks_git_push_force() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git push --force"
}

test_guard_blocks_git_reset_hard() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git reset --hard"
}

test_guard_blocks_rm_rf() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/whatever"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for rm -rf"
}

test_guard_blocks_git_branch_delete() {
  local out
  out="$(_guard_run '{"tool_name":"Bash","tool_input":{"command":"git branch -D feat/old"}}')"
  [[ "$out" == *'"permissionDecision":"ask"'* ]] \
    || fail "expected ask decision for git branch -D"
}

test_guard_skips_non_bash_tool() {
  local out
  # Even with a destructive command string, if tool is not Bash → allow
  out="$(_guard_run '{"tool_name":"Edit","tool_input":{"command":"git commit -m x"}}')"
  [[ -z "$out" ]] || fail "expected empty output for non-Bash tool"
}

test_guard_empty_input_does_not_block() {
  local out status=0
  out="$(_guard_run '' 2>&1)" || status=$?
  (( status != 2 )) || fail "guard must never block (exit 2) on empty input"
  [[ "$out" != *permissionDecision* ]] || fail "guard emitted a decision for empty input"
}

# ─── install-hooks command behavior ───────────────────────────────────────

_fresh_project() {
  local dir="$1"
  mkdir -p "$dir/.platform"
}

test_install_hooks_writes_both_artifacts() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 0
  [[ -f "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "bash-guard.sh not installed"
  [[ -x "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "bash-guard.sh not executable"
  [[ -f "$dir/.claude/settings.json" ]] \
    || fail ".claude/settings.json not installed"
  assert_file_contains "$dir/.claude/settings.json" "bash-guard.sh"
}

test_install_hooks_idempotent_when_already_present() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 0
  # Re-run: should be no-op on settings.json (bash-guard already referenced)
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "already referenced"
}

test_install_hooks_refuses_to_overwrite_unknown_settings() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  mkdir -p "$dir/.claude"
  printf '{"hooks":{"custom":"user-value"}}\n' > "$dir/.claude/settings.json"

  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "does NOT reference bash-guard"
  assert_contains "$output" "--force"
  # User's file left alone
  assert_file_contains "$dir/.claude/settings.json" "user-value"
  assert_file_not_contains "$dir/.claude/settings.json" "bash-guard.sh"
}

test_install_hooks_force_backs_up_and_overwrites() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  mkdir -p "$dir/.claude"
  printf '{"hooks":{"custom":"user-value"}}\n' > "$dir/.claude/settings.json"

  run_cli_capture output "$dir" install-hooks --force
  assert_status "$RUN_STATUS" 0
  # New content present
  assert_file_contains "$dir/.claude/settings.json" "bash-guard.sh"
  # Backup exists with original content
  local backup=""
  for f in "$dir/.claude/"settings.json.agentboard-backup-*; do
    [[ -f "$f" ]] && { backup="$f"; break; }
  done
  [[ -n "$backup" ]] || fail "no backup created with --force"
  assert_file_contains "$backup" "user-value"
}

test_install_hooks_dry_run_writes_nothing() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  run_cli_capture output "$dir" install-hooks --dry-run
  assert_status "$RUN_STATUS" 0
  [[ ! -f "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "dry-run installed the guard"
  [[ ! -f "$dir/.claude/settings.json" ]] \
    || fail "dry-run installed settings.json"
}

test_install_hooks_fails_without_platform_dir() {
  local dir output
  dir="$(mktemp -d)"
  run_cli_capture output "$dir" install-hooks
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "No .platform"
}

test_install_hooks_help() {
  local dir output
  dir="$(mktemp -d)"
  _fresh_project "$dir"
  run_cli_capture output "$dir" install-hooks --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard install-hooks"
  assert_contains "$output" "bash-guard.sh"
}

test_init_ships_bash_guard_hook_in_settings() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  assert_file_contains "$dir/.claude/settings.json" "bash-guard.sh"
  # And the guard script itself ships
  [[ -f "$dir/.platform/scripts/hooks/bash-guard.sh" ]] \
    || fail "init should ship bash-guard.sh"
}

for t in \
  test_guard_allows_benign_bash \
  test_guard_blocks_git_commit \
  test_guard_blocks_git_push \
  test_guard_blocks_git_push_force \
  test_guard_blocks_git_reset_hard \
  test_guard_blocks_rm_rf \
  test_guard_blocks_git_branch_delete \
  test_guard_skips_non_bash_tool \
  test_guard_empty_input_does_not_block \
  test_install_hooks_writes_both_artifacts \
  test_install_hooks_idempotent_when_already_present \
  test_install_hooks_refuses_to_overwrite_unknown_settings \
  test_install_hooks_force_backs_up_and_overwrites \
  test_install_hooks_dry_run_writes_nothing \
  test_install_hooks_fails_without_platform_dir \
  test_install_hooks_help \
  test_init_ships_bash_guard_hook_in_settings; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
