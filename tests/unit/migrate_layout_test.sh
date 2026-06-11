#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# migrate-layout should be safe to run on a fresh init (already correct layout)
# and should move legacy root-level memory files into .platform/memory/.

setup_legacy_fixture() {
  local dir="$1"
  mkdir -p "$dir/.platform/sessions"
  local f
  for f in decisions learnings log gotchas playbook open-questions BACKLOG; do
    printf 'old %s content\n' "$f" > "$dir/.platform/$f.md"
  done
}

test_dry_run_moves_nothing() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-layout
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Dry run"
  assert_contains "$output" "decisions.md → "
  # Legacy files still at old location, nothing in memory/
  [[ -f "$dir/.platform/decisions.md" ]] || fail "dry-run moved decisions.md"
  [[ ! -d "$dir/.platform/memory" ]] || fail "dry-run created memory/"
  [[ -d "$dir/.platform/sessions" ]] || fail "dry-run removed sessions/"
}

test_apply_moves_all_memory_files() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Migration applied"

  local f
  for f in decisions learnings log gotchas playbook open-questions BACKLOG; do
    [[ ! -f "$dir/.platform/$f.md" ]] || fail "$f.md still at root after --apply"
    [[ -f "$dir/.platform/memory/$f.md" ]] || fail "$f.md not moved into memory/"
  done
  assert_file_contains "$dir/.platform/memory/decisions.md" "old decisions content"
}

test_apply_removes_empty_sessions() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  [[ ! -d "$dir/.platform/sessions" ]] || fail "empty sessions/ was not removed"
}

test_apply_keeps_non_empty_sessions() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  printf 'user content\n' > "$dir/.platform/sessions/some-file.md"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  [[ -d "$dir/.platform/sessions" ]] || fail "non-empty sessions/ was removed"
  [[ -f "$dir/.platform/sessions/some-file.md" ]] || fail "sessions file deleted"
}

test_idempotent_apply_is_noop() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  # Run again — should do nothing
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "already current"
}

test_dry_run_on_clean_layout_is_clean() {
  local dir output
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/memory"
  run_cli_capture output "$dir" migrate-layout
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "already current"
}

test_keeps_both_when_memory_has_real_user_content() {
  # When memory/X.md contains user-written content (not a shipped placeholder),
  # don't clobber it. Leave the root file alone and warn.
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  mkdir -p "$dir/.platform/memory"
  printf 'real user content, not a placeholder\n' > "$dir/.platform/memory/decisions.md"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "both have content"
  [[ -f "$dir/.platform/decisions.md" ]] || fail "old decisions.md deleted despite conflict"
  assert_file_contains "$dir/.platform/memory/decisions.md" "real user content"
}

test_overwrites_unchanged_placeholder_in_memory() {
  # When memory/X.md is byte-identical to the shipped template (e.g. an empty
  # placeholder from `agentboard update`), migrate-layout should overwrite it
  # with the real content at root instead of keeping both.
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  mkdir -p "$dir/.platform/memory"
  # Copy the shipped placeholder verbatim into memory/ to simulate `update`.
  # (BACKLOG.md — learnings/gotchas/etc. are no longer shipped; facts replaced them.)
  cp "$TEST_ROOT/templates/platform/memory/BACKLOG.md" "$dir/.platform/memory/BACKLOG.md"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "overwrote untouched placeholder"
  [[ ! -f "$dir/.platform/BACKLOG.md" ]] || fail "root BACKLOG.md still present after overwrite"
  assert_file_contains "$dir/.platform/memory/BACKLOG.md" "old BACKLOG content"
}

test_rewrites_stale_refs_in_user_content() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  # Seed a conventions file with the old path
  mkdir -p "$dir/.platform/conventions"
  printf 'See .platform/log.md and .platform/decisions.md for details.\n' \
    > "$dir/.platform/conventions/pm.md"
  # Seed an active stream with old path
  mkdir -p "$dir/.platform/work"
  printf '%s\n' '- [ ] .platform/log.md appended' > "$dir/.platform/work/login.md"
  # Seed an archived stream — MUST NOT be rewritten
  mkdir -p "$dir/.platform/work/archive"
  printf '%s\n' '- [x] .platform/log.md appended' > "$dir/.platform/work/archive/old-stream.md"

  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Stale path references in user content"
  assert_file_contains "$dir/.platform/conventions/pm.md" ".platform/memory/log.md"
  assert_file_contains "$dir/.platform/conventions/pm.md" ".platform/memory/decisions.md"
  assert_file_contains "$dir/.platform/work/login.md" ".platform/memory/log.md"
  # Archive left untouched (historical)
  assert_file_not_contains "$dir/.platform/work/archive/old-stream.md" ".platform/memory/log.md"
  assert_file_contains "$dir/.platform/work/archive/old-stream.md" ".platform/log.md"
}

test_stale_ref_sweep_is_idempotent() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  mkdir -p "$dir/.platform/conventions"
  printf 'Already migrated: see .platform/memory/log.md\n' \
    > "$dir/.platform/conventions/ok.md"
  run_cli_capture output "$dir" migrate-layout --apply
  assert_status "$RUN_STATUS" 0
  # Should not double-rewrite into .platform/memory/memory/log.md
  assert_file_not_contains "$dir/.platform/conventions/ok.md" "memory/memory"
  assert_file_contains "$dir/.platform/conventions/ok.md" ".platform/memory/log.md"
}

test_help() {
  local dir output
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform"
  run_cli_capture output "$dir" migrate-layout --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard migrate-layout"
  assert_contains "$output" "memory/"
}

for t in \
  test_dry_run_moves_nothing \
  test_apply_moves_all_memory_files \
  test_apply_removes_empty_sessions \
  test_apply_keeps_non_empty_sessions \
  test_idempotent_apply_is_noop \
  test_dry_run_on_clean_layout_is_clean \
  test_keeps_both_when_memory_has_real_user_content \
  test_overwrites_unchanged_placeholder_in_memory \
  test_rewrites_stale_refs_in_user_content \
  test_stale_ref_sweep_is_idempotent \
  test_help; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
