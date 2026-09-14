#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

fixture() {
  mkdir -p "$dir/.platform/work" "$dir/.platform/domains"
  printf '%s\n' '---' 'updated_at: old' '---' '## Resume state' 'Original resume' \
    '## Progress log' '2026-09-12 Original progress' > "$dir/stream.md"
  cp "$dir/stream.md" "$dir/original.md"
}

test_failed_payload_write_is_not_published() (
  local dir operation; dir="$(mktemp -d)"; fixture
  printf() {
    [[ "${2:-}" != 'FAILED-PAYLOAD' ]] || return 1
    builtin printf "$@"
  }
  for operation in resume progress research; do
    case "$operation" in
      resume) if _checkpoint_write_resume_state "$dir/stream.md" FAILED-PAYLOAD; then fail 'resume accepted failed payload'; fi ;;
      progress) if _checkpoint_prepend_progress_entry "$dir/stream.md" FAILED-PAYLOAD; then fail 'progress accepted failed payload'; fi ;;
      research) if _research_append_notes "$dir/stream.md" prompt 0 FAILED-PAYLOAD; then fail 'research accepted failed payload'; fi ;;
    esac
    cmp -s "$dir/stream.md" "$dir/original.md" || fail "$operation changed source after write failure"
  done
)

test_failed_getline_is_not_published() (
  local dir operation; dir="$(mktemp -d)"; fixture
  awk() {
    local arg args=()
    for arg in "$@"; do
      case "$arg" in block_file=*|entry_file=*) arg="${arg%%=*}=$dir/nonexistent-payload" ;; esac
      args+=("$arg")
    done
    command awk "${args[@]}"
  }
  for operation in resume progress research research_end; do
    if [[ "$operation" == research_end ]]; then
      builtin printf '%s\n' '## Research notes' 'Existing findings' > "$dir/stream.md"
      cp "$dir/stream.md" "$dir/original.md"
    fi
    case "$operation" in
      resume) if _checkpoint_write_resume_state "$dir/stream.md" replacement; then fail 'resume accepted failed getline'; fi ;;
      progress) if _checkpoint_prepend_progress_entry "$dir/stream.md" replacement; then fail 'progress accepted failed getline'; fi ;;
      research*) if _research_append_notes "$dir/stream.md" prompt 0 findings; then fail "$operation accepted failed getline"; fi ;;
    esac
    cmp -s "$dir/stream.md" "$dir/original.md" || fail "$operation changed source after getline failure"
  done
)

test_new_stream_copy_failure_rolls_back_under_conditional() (
  local dir; dir="$(mktemp -d)"; fixture
  cp "$TEST_ROOT/templates/platform/work/TEMPLATE.md" "$dir/.platform/work/TEMPLATE.md"
  printf '%s\n' domain > "$dir/.platform/domains/sample.md"
  printf '%s\n' '| _(none)_ | — | — | — | — |' > "$dir/.platform/work/ACTIVE.md"
  printf '%s\n' 'Existing project brief' > "$dir/.platform/work/BRIEF.md"
  cp "$dir/.platform/work/ACTIVE.md" "$dir/active-before.md"
  cd "$dir"
  cp() {
    [[ "$1" != './.platform/work/TEMPLATE.md' ]] || return 1
    command cp "$@"
  }
  if cmd_new_stream sample --domain sample --base-branch main --branch feature/sample; then
    fail 'new-stream accepted failed template copy'
  fi
  [[ ! -e .platform/work/sample.md ]] || fail 'partial stream survived'
  cmp -s .platform/work/ACTIVE.md active-before.md || fail 'registry changed after failed creation'
  [[ ! -d .platform/.state.lock ]] || fail 'lock leaked'
)

test_failed_temp_creation_preserves_source() (
  local dir; dir="$(mktemp -d)"; fixture
  mktemp() { return 1; }
  if _checkpoint_write_resume_state "$dir/stream.md" replacement; then fail 'resume accepted failed mktemp'; fi
  if _checkpoint_prepend_progress_entry "$dir/stream.md" replacement; then fail 'progress accepted failed mktemp'; fi
  if _research_append_notes "$dir/stream.md" prompt 0 findings; then fail 'research accepted failed mktemp'; fi
  cmp -s "$dir/stream.md" "$dir/original.md" || fail 'source changed after failed mktemp'
)

for test_case in test_failed_temp_creation_preserves_source test_failed_payload_write_is_not_published test_failed_getline_is_not_published test_new_stream_copy_failure_rolls_back_under_conditional; do
  printf 'RUN: %s\n' "$test_case"
  "$test_case"
done
