#!/usr/bin/env bash

set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TEST_ROOT/bin/agentboard"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

RUN_STATUS=0

assert_eq() {
  local actual="$1" expected="$2"
  [[ "$actual" == "$expected" ]] || fail "expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output to not contain: $needle"
}

assert_file_contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_file_not_contains() {
  local file="$1" needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    fail "expected $file to not contain: $needle"
  fi
}

assert_status() {
  local actual="$1" expected="$2"
  [[ "$actual" -eq "$expected" ]] || fail "expected status $expected, got $actual"
}

make_git_repo() {
  local dir="$1" branch="${2:-main}"
  git_init_branch "$dir" "$branch"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Agentboard Test"
}

# git < 2.28 has no `init -b`; fall back to pointing HEAD by hand so the
# suite still runs on older stock-macOS git installs.
git_init_branch() {
  local dir="$1" branch="${2:-main}"
  if ! git -C "$dir" init -b "$branch" >/dev/null 2>&1; then
    git -C "$dir" init >/dev/null 2>&1
    git -C "$dir" symbolic-ref HEAD "refs/heads/$branch" >/dev/null 2>&1
  fi
}

commit_all() {
  local dir="$1" message="${2:-initial}"
  git -C "$dir" add .
  git -C "$dir" commit -m "$message" >/dev/null 2>&1
}

init_project_fixture() {
  local dir="$1"
  (
    cd "$dir"
    printf '\n\n' | "$TEST_ROOT/bin/agentboard" init >/dev/null 2>&1
  )
}

init_hub_fixture() {
  local dir="$1"
  (
    cd "$dir"
    printf '\n\nY\n' | "$TEST_ROOT/bin/agentboard" init >/dev/null 2>&1
  )
}

run_and_capture() {
  local __resultvar="$1"
  shift
  local tmp status captured
  tmp="$(mktemp)"
  set +e
  "$@" >"$tmp" 2>&1
  status=$?
  captured="$(cat "$tmp")"
  rm -f "$tmp"
  set -e
  RUN_STATUS="$status"
  printf -v "$__resultvar" '%s' "$captured"
  return 0
}

run_cli_capture() {
  local __resultvar="$1" dir="$2"
  shift 2
  local tmp captured status
  tmp="$(mktemp)"
  set +e
  (
    cd "$dir" || exit 1
    "$TEST_ROOT/bin/agentboard" "$@"
  ) >"$tmp" 2>&1
  status=$?
  captured="$(cat "$tmp")"
  rm -f "$tmp"
  set -e
  RUN_STATUS="$status"
  printf -v "$__resultvar" '%s' "$captured"
  return 0
}
