#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_legacy_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
  )
  mkdir -p "$dir/.platform/memory"
  cat > "$dir/.platform/memory/gotchas.md" <<'EOF'
# Gotchas

<!-- agentboard:gotchas:begin -->
🔴 [auth] — tokens silently expire after 7d; refresh middleware must run first
🟡 [billing] — sandbox webhooks fire twice
<!-- agentboard:gotchas:end -->
EOF
  cat > "$dir/.platform/memory/playbook.md" <<'EOF'
# Playbook

<!-- agentboard:playbook:begin -->
- **[deploy]** — always run smoke.sh before tagging (catches env drift)
<!-- agentboard:playbook:end -->
EOF
  cat > "$dir/.platform/memory/open-questions.md" <<'EOF'
# Open questions

<!-- agentboard:open-questions:active:begin -->
- 2026-01-15 — [auth] should sessions be revocable server-side?
<!-- agentboard:open-questions:active:end -->
EOF
  cat > "$dir/.platform/memory/learnings.md" <<'EOF'
# Learnings

## L-001 — ghost 401s from clock skew
Date: 2026-02-01 | Repo: backend
Symptom: random 401s in CI only
Root cause: container clock drift breaks JWT iat validation
Fix: added 30s leeway in verify()
Class: time-dependent auth

---
EOF
}

test_dry_run_lists_without_writing() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-memory
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "tokens silently expire"
  assert_contains "$output" "smoke.sh"
  assert_contains "$output" "revocable server-side"
  assert_contains "$output" "ghost 401s from clock skew"
  assert_contains "$output" "would convert"
  [[ ! -d "$dir/.platform/memory/legacy" ]] || fail "dry run must not park files"
  [[ -z "$(ls -A "$dir/.platform/memory/facts" 2>/dev/null)" ]] || fail "dry run must not create facts"
}

test_apply_converts_and_parks_originals() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-memory --apply
  assert_status "$RUN_STATUS" 0

  # 5 entries → 5 facts (2 gotchas, 1 playbook, 1 question, 1 learning)
  run_cli_capture output "$dir" fact list
  assert_contains "$output" "tokens silently expire"
  assert_contains "$output" "sandbox webhooks fire twice"
  assert_contains "$output" "smoke.sh"
  assert_contains "$output" "revocable server-side"
  assert_contains "$output" "ghost 401s from clock skew"

  # Severity + domain inference: [auth] matched a real domain file
  local red_fact
  red_fact="$(grep -rl "tokens silently expire" "$dir/.platform/memory/facts/")"
  assert_file_contains "$red_fact" "severity: red"
  assert_file_contains "$red_fact" "domains: [auth]"
  # [billing] has no domain file — no domain tag, still yellow
  local yellow_fact
  yellow_fact="$(grep -rl "sandbox webhooks" "$dir/.platform/memory/facts/")"
  assert_file_contains "$yellow_fact" "severity: yellow"
  assert_file_contains "$yellow_fact" "domains: []"
  # Learning body survives
  local learning_fact
  learning_fact="$(grep -rl "ghost 401s" "$dir/.platform/memory/facts/")"
  assert_file_contains "$learning_fact" "container clock drift"

  # Originals parked, not deleted
  for f in gotchas playbook open-questions learnings; do
    [[ -f "$dir/.platform/memory/legacy/$f.md" ]] || fail "$f.md not parked in legacy/"
    [[ ! -f "$dir/.platform/memory/$f.md" ]] || fail "$f.md still in memory/ after apply"
  done

  # Doctor accepts the migrated state
  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 0
}

test_apply_is_idempotent() {
  local dir output
  dir="$(mktemp -d)"
  setup_legacy_fixture "$dir"
  run_cli_capture output "$dir" migrate-memory --apply
  # Restore one legacy file as if a partial migration had happened
  cp "$dir/.platform/memory/legacy/gotchas.md" "$dir/.platform/memory/gotchas.md"
  run_cli_capture output "$dir" migrate-memory --apply
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "already covered"
  # No duplicate facts: still exactly one fact about token expiry
  [[ "$(grep -rl "tokens silently expire" "$dir/.platform/memory/facts/" | grep -c .)" -eq 1 ]] \
    || fail "re-run created duplicate facts"
}

test_noop_when_no_legacy_files() {
  local dir output
  dir="$(mktemp -d)"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  run_cli_capture output "$dir" migrate-memory
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "nothing to migrate"
}

for t in \
  test_dry_run_lists_without_writing \
  test_apply_converts_and_parks_originals \
  test_apply_is_idempotent \
  test_noop_when_no_legacy_files; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
