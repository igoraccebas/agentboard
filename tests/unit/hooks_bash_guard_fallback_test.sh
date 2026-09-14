#!/usr/bin/env bash
# bash-guard must keep asking for review, and never block everything, on a
# machine without node. Exit 2 from a PreToolUse hook blocks every Bash call.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

guard="$TEST_ROOT/templates/platform/scripts/hooks/bash-guard.sh"

# A PATH that holds only the utilities the fallback needs — and no node.
nonode_bin="$(mktemp -d)"
for tool in bash cat grep; do
  ln -s "$(command -v "$tool")" "$nonode_bin/$tool"
done
if PATH="$nonode_bin" bash -c 'command -v node' >/dev/null 2>&1; then
  fail 'node is still resolvable in the no-node PATH'
fi

run_guard() {
  PATH="$nonode_bin" bash "$guard" <<< "$1"
}

test_fallback_asks_for_sensitive_commands() {
  local command output
  for command in 'git commit -m x' 'git -C /tmp/repo push origin main' 'git reset HEAD --hard' \
    'git checkout -- file.txt' 'git branch feature -D' 'rm -rf ./build' \
    'agentboard approve abc' 'agentboard close abc --confirm'; do
    output="$(run_guard "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}")"
    assert_contains "$output" '"permissionDecision":"ask"'
    assert_contains "$output" '"hookEventName":"PreToolUse"'
  done
}

test_fallback_stays_silent_for_ordinary_commands() {
  local command output
  for command in 'git status' 'ls -la' 'rm ./one-file.txt' 'agentboard close abc'; do
    output="$(run_guard "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"}}")"
    assert_eq "$output" ''
  done
  output="$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"x"}}')"
  assert_eq "$output" ''
}

test_fallback_never_blocks_when_node_is_missing() {
  local status=0
  PATH="$nonode_bin" bash "$guard" <<< 'not json' >/dev/null || status=$?
  assert_status "$status" 0
  status=0
  PATH="$nonode_bin" bash "$guard" </dev/null >/dev/null || status=$?
  assert_status "$status" 0
}

for test_case in test_fallback_asks_for_sensitive_commands test_fallback_stays_silent_for_ordinary_commands test_fallback_never_blocks_when_node_is_missing; do
  printf 'RUN: %s\n' "$test_case"
  "$test_case"
done
