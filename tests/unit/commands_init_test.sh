#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_project_init_writes_single_repo_pack() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"

  run_and_capture output bash -lc "cd '$dir' && printf '\n\n' | '$TEST_ROOT/bin/agentboard' init"
  assert_file_contains "$dir/CLAUDE.md" "activate this project"
  [[ -f "$dir/.platform/ACTIVATE.md" ]] || fail "expected ACTIVATE.md in single-repo init"
  [[ ! -f "$dir/.platform/ACTIVATE-HUB.md" ]] || fail "did not expect ACTIVATE-HUB.md in single-repo init"
  [[ -f "$dir/.claude/settings.json" ]] || fail "expected .claude/settings.json"
}

test_hub_init_writes_hub_pack() {
  local dir output
  dir="$(mktemp -d)"
  mkdir -p "$dir/backend" "$dir/frontend"
  printf '{}\n' > "$dir/backend/package.json"
  printf '{}\n' > "$dir/frontend/package.json"

  run_and_capture output bash -lc "cd '$dir' && printf '\n\n\n' | '$TEST_ROOT/bin/agentboard' init"
  [[ -f "$dir/.platform/ACTIVATE-HUB.md" ]] || fail "expected ACTIVATE-HUB.md in hub init"
  [[ ! -f "$dir/.platform/ACTIVATE.md" ]] || fail "did not expect ACTIVATE.md in hub init"
  assert_file_contains "$dir/CLAUDE.md" "PLATFORM BRAINS HUB"
  assert_file_contains "$dir/.platform/repos.md" "Repo ID"
}

test_init_installs_ab_verify_to_both_skill_dirs() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  run_and_capture output bash -lc "cd '$dir' && printf '\n\n' | '$TEST_ROOT/bin/agentboard' init"
  [[ -f "$dir/.claude/skills/ab-verify/SKILL.md" ]] || fail "ab-verify not installed to .claude/skills"
  [[ -f "$dir/.agents/skills/ab-verify/SKILL.md" ]] || fail "ab-verify not installed to .agents/skills"
  assert_file_contains "$dir/.claude/skills/ab-verify/SKILL.md" "## Launch"
  assert_file_contains "$dir/.platform/domains/TEMPLATE.md" "## Verify (optional)"
}

test_project_init_writes_single_repo_pack
test_hub_init_writes_hub_pack
test_init_installs_ab_verify_to_both_skill_dirs
