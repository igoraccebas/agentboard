#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

setup_research_fixture() {
  local dir="$1"
  printf '{}\n' > "$dir/package.json"
  make_git_repo "$dir" main
  commit_all "$dir" initial
  init_project_fixture "$dir"
  (
    cd "$dir"
    git add -A
    git commit -m "agentboard init" >/dev/null 2>&1
    "$TEST_ROOT/bin/agentboard" new-domain auth >/dev/null
    "$TEST_ROOT/bin/agentboard" new-stream login \
      --domain auth --base-branch main --branch feat/login >/dev/null
  )
}

# Write a fake codex binary into the fixture. It echoes chatter (to prove the
# live stream passes through), records its argv to $sentinel, and writes a
# fixed final message to the file following -o.
_write_codex_stub() {
  local stub="$1" sentinel="$2"
  cat > "$stub" <<EOF
#!/bin/bash
echo "codex-stub: thinking..."
printf '%s\n' "\$*" > "$sentinel"
out=""
prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$a"
  prev="\$a"
done
[ -n "\$out" ] && printf 'Stub findings: the answer is 42.\n' > "\$out"
exit 0
EOF
  chmod +x "$stub"
}

test_research_appends_notes_and_streams_output() {
  local dir output stream_file stub sentinel
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  stub="$dir/codex-stub" sentinel="$dir/argv.txt"
  _write_codex_stub "$stub" "$sentinel"

  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research login "how does auth work"
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "codex researching login"
  assert_contains "$output" "codex-stub: thinking..."
  assert_contains "$output" "research notes appended"
  assert_file_contains "$stream_file" "## Research notes"
  assert_file_contains "$stream_file" "how does auth work"
  assert_file_contains "$stream_file" "Stub findings: the answer is 42."
  assert_file_contains "$stream_file" "updated_at: $(date +%F)"
}

test_research_second_run_accumulates() {
  local dir output stream_file stub sentinel
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  stub="$dir/codex-stub" sentinel="$dir/argv.txt"
  _write_codex_stub "$stub" "$sentinel"

  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research login "first question"
  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research login "second question"
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$stream_file" "first question"
  assert_file_contains "$stream_file" "second question"
  local section_count
  section_count="$(grep -c '^## Research notes' "$stream_file")"
  [[ "$section_count" -eq 1 ]] || fail "expected exactly 1 '## Research notes' section, got $section_count"
}

test_research_web_flag_sets_config_override() {
  local dir output stub sentinel
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  stub="$dir/codex-stub" sentinel="$dir/argv.txt"
  _write_codex_stub "$stub" "$sentinel"

  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research login "q" --web
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$sentinel" "tools.web_search=true"
  assert_file_contains "$sentinel" "exec -s read-only"
  # No profile by default — codex resolves -p from ~/.codex/config.toml only
  if grep -q '\-p ' "$sentinel"; then
    fail "profile flag present without --profile"
  fi

  rm -f "$sentinel"
  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research login "q" --profile researcher
  assert_status "$RUN_STATUS" 0
  assert_file_contains "$sentinel" "-p researcher"

  rm -f "$sentinel"
  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research login "q"
  assert_status "$RUN_STATUS" 0
  if grep -q "tools.web_search=true" "$sentinel"; then
    fail "web_search override present without --web"
  fi
}

test_research_dry_run_writes_nothing() {
  local dir output stream_file stub sentinel
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  stub="$dir/codex-stub" sentinel="$dir/argv.txt"
  _write_codex_stub "$stub" "$sentinel"

  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research login "q" --dry-run
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "dry-run"
  assert_contains "$output" "exec -s read-only"
  assert_file_not_contains "$stream_file" "## Research notes"
  [[ ! -f "$sentinel" ]] || fail "codex stub was invoked during --dry-run"
}

test_research_missing_codex_dies_actionably() {
  local dir output
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  AGENTBOARD_CODEX_BIN="/nonexistent-codex" run_cli_capture output "$dir" research login "q"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Codex CLI not found"
}

test_research_missing_stream_dies() {
  local dir output stub sentinel
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  stub="$dir/codex-stub" sentinel="$dir/argv.txt"
  _write_codex_stub "$stub" "$sentinel"
  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research no-such-stream "q"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "not found"
}

test_research_help() {
  local dir output
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  run_cli_capture output "$dir" research --help
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Usage: agentboard research"
}

test_research_unknown_flag() {
  local dir output
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  run_cli_capture output "$dir" research login "q" --not-a-flag
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "Unknown flag for research"
}

test_research_failing_codex_writes_nothing() {
  local dir output stream_file stub
  dir="$(mktemp -d)"
  setup_research_fixture "$dir"
  stream_file="$dir/.platform/work/login.md"
  stub="$dir/codex-stub"
  printf '#!/bin/bash\necho "auth error" >&2\nexit 7\n' > "$stub"
  chmod +x "$stub"

  AGENTBOARD_CODEX_BIN="$stub" run_cli_capture output "$dir" research login "q"
  assert_status "$RUN_STATUS" 1
  assert_contains "$output" "codex exec failed (exit 7)"
  assert_file_not_contains "$stream_file" "## Research notes"
}

for t in \
  test_research_appends_notes_and_streams_output \
  test_research_second_run_accumulates \
  test_research_web_flag_sets_config_override \
  test_research_dry_run_writes_nothing \
  test_research_missing_codex_dies_actionably \
  test_research_missing_stream_dies \
  test_research_help \
  test_research_unknown_flag \
  test_research_failing_codex_writes_nothing; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
