#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

fixture() {
  local dir="$1"
  mkdir -p "$dir/.platform/work" "$dir/.platform/memory"
  printf '%s\n' '---' 'slug: sample' 'stream_id: stream-sample' 'status: awaiting-verification' 'closure_approved: false' 'updated_at: 2026-09-12' '---' '## Done criteria' '- [x] verified' > "$dir/.platform/work/sample.md"
  printf '%s\n' '| Stream | Type | Status | Agent | Last updated |' '|---|---|---|---|---|' '| sample | bug | awaiting-verification | codex | today |' '---' > "$dir/.platform/work/ACTIVE.md"
  printf '%s\n' '**Stream file:** `work/sample.md`' > "$dir/.platform/work/BRIEF.md"
  printf '%s\n' '# Log' '---' > "$dir/.platform/memory/log.md"
}

test_unapproved_close_has_no_side_effects() {
  local dir output; dir="$(mktemp -d)"; fixture "$dir"
  run_cli_capture output "$dir" close sample --confirm
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" 'closure_approved'
  [[ -f "$dir/.platform/work/sample.md" ]] || fail 'unapproved stream archived'
  assert_file_contains "$dir/.platform/work/ACTIVE.md" '| sample |'
  [[ ! -d "$dir/.platform/work/archive" ]] || fail 'unapproved closure wrote archive'
}

test_approved_close_rejects_unfinished_criteria() {
  local dir output; dir="$(mktemp -d)"; fixture "$dir"
  replace_frontmatter_line "$dir/.platform/work/sample.md" closure_approved true
  printf '%s\n' '- [ ] manual verification' >> "$dir/.platform/work/sample.md"
  run_cli_capture output "$dir" close sample --confirm
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" 'Unchecked done criteria'
}

test_closure_refreshes_brief_and_dry_run_is_read_only() {
  local dir output; dir="$(mktemp -d)"; fixture "$dir"
  replace_frontmatter_line "$dir/.platform/work/sample.md" closure_approved true
  run_cli_capture output "$dir" close sample --confirm --dry-run
  assert_status "$RUN_STATUS" 0
  [[ ! -d "$dir/.platform/work/archive" ]] || fail 'dry-run created archive'
  run_cli_capture output "$dir" close sample --confirm
  assert_status "$RUN_STATUS" 0
  assert_file_not_contains "$dir/.platform/work/BRIEF.md" 'work/sample.md'
  assert_file_not_contains "$dir/.platform/work/ACTIVE.md" '| sample |'
  assert_file_contains "$dir/.platform/work/archive/sample.md" 'status: done'
  brief_is_placeholder "$dir/.platform/work/BRIEF.md" || fail 'closed brief cannot be reused by new-stream'
}

test_transaction_restores_files_on_error() {
  local dir; dir="$(mktemp -d)"; fixture "$dir"
  (
    cd "$dir"
    change_then_fail() { printf 'damaged\n' > .platform/work/sample.md; return 1; }
    if with_state_lock state_transaction change_then_fail .platform/work/sample.md; then
      fail 'failed transaction succeeded'
    fi
    assert_file_contains .platform/work/sample.md 'closure_approved: false'
    [[ ! -d .platform/.state.lock ]] || fail 'lock leaked after error'
  )
}

test_concurrent_checkpoints_preserve_every_entry() {
  local dir pids=() pid n; dir="$(mktemp -d)"; fixture "$dir"
  for n in 1 2 3 4; do
    (cd "$dir" && "$TEST_ROOT/bin/agentboard" checkpoint sample --what "writer-$n" --next review >/dev/null) &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || fail 'checkpoint failed'; done
  for n in 1 2 3 4; do assert_file_contains "$dir/.platform/work/sample.md" "writer-$n"; done
  [[ ! -d "$dir/.platform/.state.lock" ]] || fail 'lock leaked'
}

test_failed_restore_keeps_backup_indexes_aligned() {
  local dir; dir="$(mktemp -d)"; fixture "$dir"
  (
    cd "$dir"
    mkdir .platform/first .platform/second
    printf 'first original\n' > .platform/first/state
    printf 'second original\n' > .platform/second/state
    mktemp() {
      case "$*" in *first/.restore.*) return 1 ;; esac
      command mktemp "$@"
    }
    change_then_fail() {
      printf 'damaged\n' > .platform/first/state
      printf 'damaged\n' > .platform/second/state
      return 1
    }
    if with_state_lock state_transaction change_then_fail .platform/first/state .platform/second/state; then
      fail 'failed transaction succeeded'
    fi
    assert_file_contains .platform/second/state 'second original'
    local journals=(.platform/.transaction.*)
    assert_file_contains "${journals[0]}/0" 'first original'
    assert_file_contains "${journals[0]}/1" 'second original'
  )
}

test_late_closure_failure_restores_every_state_file() (
  local dir file; dir="$(mktemp -d)"; fixture "$dir"
  replace_frontmatter_line "$dir/.platform/work/sample.md" closure_approved true
  cd "$dir"
  mkdir before
  for file in sample ACTIVE BRIEF; do cp ".platform/work/$file.md" "before/$file.md"; done
  cp .platform/memory/log.md before/log.md
  _close_refresh_brief() { return 1; }
  if cmd_close sample --confirm; then fail 'late closure failure accepted'; fi
  for file in sample ACTIVE BRIEF; do cmp -s ".platform/work/$file.md" "before/$file.md" || fail "$file not restored"; done
  cmp -s .platform/memory/log.md before/log.md || fail 'closure log not restored'
  [[ ! -e .platform/work/archive/sample.md ]] || fail 'partial archive survived'
  [[ ! -d .platform/.state.lock ]] || fail 'closure lock leaked'
)

test_concurrent_stream_creation_preserves_registry() (
  local dir n pid pids=(); dir="$(mktemp -d)"; fixture "$dir"
  cp "$TEST_ROOT/templates/platform/work/TEMPLATE.md" "$dir/.platform/work/TEMPLATE.md"
  mkdir "$dir/.platform/domains"
  printf 'domain\n' > "$dir/.platform/domains/example.md"
  cd "$dir"
  for n in 1 2 3; do
    "$TEST_ROOT/bin/agentboard" new-stream "writer-$n" --domain example --base-branch main --branch "feature/writer-$n" >/dev/null 2>&1 &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || fail 'concurrent new-stream failed'; done
  for n in 1 2 3; do
    assert_file_contains .platform/work/ACTIVE.md "| writer-$n |"
    assert_file_contains ".platform/work/writer-$n.md" "slug: writer-$n"
  done
)

test_checkpoint_succeeds_when_usage_logging_fails() {
  local dir output; dir="$(mktemp -d)"; fixture "$dir"
  # An unusable HOME makes the usage database uninitializable.
  HOME=/dev/null/no-home run_cli_capture output "$dir" checkpoint sample \
    --what usage-failure --next review --provider codex --tokens-in 1 --tokens-out 2
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" 'Checkpoint saved'
  assert_contains "$output" 'usage logging failed'
  assert_file_contains "$dir/.platform/work/sample.md" 'usage-failure'
}

test_checkpoint_succeeds_when_usage_logging_fails
test_unapproved_close_has_no_side_effects
test_approved_close_rejects_unfinished_criteria
test_closure_refreshes_brief_and_dry_run_is_read_only
test_transaction_restores_files_on_error
test_failed_restore_keeps_backup_indexes_aligned
test_late_closure_failure_restores_every_state_file
test_concurrent_stream_creation_preserves_registry
test_concurrent_checkpoints_preserve_every_entry
