#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

HOOK="$TEST_ROOT/templates/platform/scripts/hooks/platform-closure-gate.js"

test_hook_blocks_without_human_approval() {
  local dir input output status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"

  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
closure_approved: false
---

## Done criteria
- [x] code complete
EOF

  input=$(cat <<EOF
{"tool_name":"Edit","cwd":"$dir","tool_input":{"file_path":"$dir/.platform/work/ACTIVE.md","old_string":"| auth-fix | bug | active | codex | 2026-04-15 |","new_string":""}}
EOF
)

  set +e
  output="$(printf '%s' "$input" | node "$HOOK" 2>&1)"
  status=$?
  set -e

  assert_status "$status" 2
  assert_contains "$output" "not approved by the owner"
  assert_contains "$output" "agentboard close auth-fix --approve"
}

test_hook_blocks_with_unchecked_done_criteria() {
  local dir input output status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"

  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
closure_approved: true
approved_by: owner
approved_at: 2026-09-14 10:00:00 +0000
---

## Done criteria
- [ ] manual QA
EOF

  input=$(cat <<EOF
{"tool_name":"Edit","cwd":"$dir","tool_input":{"file_path":"$dir/.platform/work/ACTIVE.md","old_string":"| auth-fix | bug | active | codex | 2026-04-15 |","new_string":""}}
EOF
)

  set +e
  output="$(printf '%s' "$input" | node "$HOOK" 2>&1)"
  status=$?
  set -e

  assert_status "$status" 2
  assert_contains "$output" "Unchecked done criteria remain"
}

test_hook_allows_closure_when_approved_and_complete() {
  local dir input status
  dir="$(mktemp -d)"
  mkdir -p "$dir/.platform/work"

  cat > "$dir/.platform/work/auth-fix.md" <<'EOF'
---
closure_approved: true
approved_by: owner
approved_at: 2026-09-14 10:00:00 +0000
---

## Done criteria
- [x] manual QA
EOF

  input=$(cat <<EOF
{"tool_name":"Edit","cwd":"$dir","tool_input":{"file_path":"$dir/.platform/work/ACTIVE.md","old_string":"| auth-fix | bug | active | codex | 2026-04-15 |","new_string":""}}
EOF
)

  set +e
  printf '%s' "$input" | node "$HOOK" >/dev/null 2>&1
  status=$?
  set -e

  assert_status "$status" 0
}

# ── stream-file and archive dispatches ───────────────────────────────────────
# gate_edit <dir> <file> <old> <new>   /  gate_write <dir> <file> <content>
# Both set GATE_STATUS and GATE_OUTPUT.
gate_run() {
  local input="$1"
  set +e
  GATE_OUTPUT="$(printf '%s' "$input" | node "$HOOK" 2>&1)"
  GATE_STATUS=$?
  set -e
}
gate_edit() {
  local dir="$1" file="$2" old="$3" new="$4"
  gate_run "$(node -e 'const [d,f,o,n]=process.argv.slice(1);console.log(JSON.stringify({tool_name:"Edit",cwd:d,tool_input:{file_path:f,old_string:o,new_string:n}}))' "$dir" "$file" "$old" "$new")"
}
gate_write() {
  local dir="$1" file="$2" content="$3"
  gate_run "$(node -e 'const [d,f,c]=process.argv.slice(1);console.log(JSON.stringify({tool_name:"Write",cwd:d,tool_input:{file_path:f,content:c}}))' "$dir" "$file" "$content")"
}
stream_fixture() {  # <dir> <closure_approved value> [extra frontmatter]
  local dir="$1" flag="$2" extra="${3:-}"
  mkdir -p "$dir/.platform/work"
  printf -- '---\nslug: auth-fix\nclosure_approved: %s\n%s---\n\n## Done criteria\n- [ ] unit tests pass\n- [ ] Widget verified in staging by the owner\n\n## Progress log\n2026-09-14 10:00 — started\n' \
    "$flag" "$extra" > "$dir/.platform/work/auth-fix.md"
}

test_edit_that_flips_the_flag_is_blocked() {
  local dir; dir="$(mktemp -d)"; stream_fixture "$dir" false
  gate_edit "$dir" "$dir/.platform/work/auth-fix.md" "closure_approved: false" "closure_approved: true"
  assert_status "$GATE_STATUS" 2
  assert_contains "$GATE_OUTPUT" "only the owner can approve closure"
  assert_contains "$GATE_OUTPUT" "agentboard close auth-fix --approve"
}

test_edit_that_introduces_the_cli_record_is_blocked() {
  local dir; dir="$(mktemp -d)"; stream_fixture "$dir" false
  gate_edit "$dir" "$dir/.platform/work/auth-fix.md" "slug: auth-fix" $'slug: auth-fix\napproved_by: me\napproved_at: now'
  assert_status "$GATE_STATUS" 2
  assert_contains "$GATE_OUTPUT" "only the owner can approve closure"
}

test_write_that_introduces_the_flag_is_blocked() {
  local dir; dir="$(mktemp -d)"; stream_fixture "$dir" false
  gate_write "$dir" "$dir/.platform/work/auth-fix.md" $'---\nslug: auth-fix\nclosure_approved: true\n---\n## Done criteria\n- [x] unit tests pass\n'
  assert_status "$GATE_STATUS" 2
  assert_contains "$GATE_OUTPUT" "only the owner can approve closure"
}

test_write_that_preserves_an_approved_file_is_allowed() {
  local dir; dir="$(mktemp -d)"
  stream_fixture "$dir" true $'approved_by: owner\napproved_at: 2026-09-14 10:00:00 +0000\n'
  local content; content="$(cat "$dir/.platform/work/auth-fix.md")"$'\n2026-09-14 11:00 — more progress\n'
  gate_write "$dir" "$dir/.platform/work/auth-fix.md" "$content"
  assert_status "$GATE_STATUS" 0
}

test_ticking_an_owner_criterion_is_blocked() {
  local dir; dir="$(mktemp -d)"; stream_fixture "$dir" false
  gate_edit "$dir" "$dir/.platform/work/auth-fix.md" "- [ ] Widget verified in staging by the owner" "- [x] Widget verified in staging by the owner"
  assert_status "$GATE_STATUS" 2
  assert_contains "$GATE_OUTPUT" "owner's to verify"
}

test_ticking_a_non_owner_criterion_is_allowed() {
  local dir; dir="$(mktemp -d)"; stream_fixture "$dir" false
  gate_edit "$dir" "$dir/.platform/work/auth-fix.md" "- [ ] unit tests pass" "- [x] unit tests pass"
  assert_status "$GATE_STATUS" 0
}

test_progress_log_edit_is_allowed() {
  local dir; dir="$(mktemp -d)"; stream_fixture "$dir" false
  gate_edit "$dir" "$dir/.platform/work/auth-fix.md" "2026-09-14 10:00 — started" $'2026-09-14 10:30 — checkpoint\n2026-09-14 10:00 — started'
  assert_status "$GATE_STATUS" 0
}

test_write_under_archive_is_blocked() {
  local dir; dir="$(mktemp -d)"; stream_fixture "$dir" false; mkdir -p "$dir/.platform/work/archive"
  gate_write "$dir" "$dir/.platform/work/archive/auth-fix.md" "archived by hand"
  assert_status "$GATE_STATUS" 2
  assert_contains "$GATE_OUTPUT" "work/archive/"
  assert_contains "$GATE_OUTPUT" "agentboard close auth-fix --confirm"
}

test_approval_edit_on_missing_stream_file_is_blocked() {
  local dir; dir="$(mktemp -d)"; mkdir -p "$dir/.platform/work"
  gate_edit "$dir" "$dir/.platform/work/ghost.md" "closure_approved: false" "closure_approved: true"
  assert_status "$GATE_STATUS" 2
}

test_hook_blocks_without_human_approval
test_hook_blocks_with_unchecked_done_criteria
test_hook_allows_closure_when_approved_and_complete
test_edit_that_flips_the_flag_is_blocked
test_edit_that_introduces_the_cli_record_is_blocked
test_write_that_introduces_the_flag_is_blocked
test_write_that_preserves_an_approved_file_is_allowed
test_ticking_an_owner_criterion_is_blocked
test_ticking_a_non_owner_criterion_is_allowed
test_progress_log_edit_is_allowed
test_write_under_archive_is_blocked
test_approval_edit_on_missing_stream_file_is_blocked
