#!/usr/bin/env bash
# Behavioral eval primitives: scaffold a throwaway agentboard project, drive
# one headless Claude Code session in it, and assert on the transcript and the
# resulting files. Sourced by run.sh and by every scenario's setup/assert/break.
# Assertions never abort: each prints one PASS/FAIL row with its evidence.
set -euo pipefail
BEHAVIOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BEHAVIOR_ROOT/../helpers.sh"

: "${ABE_MODEL:=haiku}"
: "${ABE_MAX_TURNS:=12}"
: "${ABE_ALLOWED_TOOLS:=Read Edit Write Grep Glob Skill Bash}"
: "${ABE_RUNNER:=claude}"   # provider seam; only "claude" is implemented
: "${ABE_SANDBOX:=1}"       # 0 disables Claude Code's Bash sandbox for the child (not recommended)
# Claude Code's built-in sandbox confines Bash writes to the fixture. Verified
# 2026-09-14: `touch ~/x` → "Operation not permitted", `touch ./x` succeeds.
BH_SANDBOX_SETTINGS='{"sandbox":{"enabled":true,"autoAllowBashIfSandboxed":true}}'
: "${BH_LABEL:=?}"          # "<scenario>.<variant>" set by run.sh for report rows
BH_FAILED=0

# ── fixture ──────────────────────────────────────────────────────────────────
# bh_fixture <dir>: git repo + `agentboard init`, then drop the template's
# "activate this project" sentence so the session works instead of onboarding.
bh_fixture() {
  local dir="$1" tmp
  make_git_repo "$dir" main || return 1
  init_project_fixture "$dir" || return 1
  [[ -f "$dir/CLAUDE.md" && -f "$dir/.claude/settings.json" ]] || return 1
  tmp="$(mktemp)" || return 1
  awk '/^Scaffolded on .*Say "activate this project"/ { skip = 2 }
       skip > 0 { skip--; next } { print }' "$dir/CLAUDE.md" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$dir/CLAUDE.md" || return 1
  mkdir -p "$dir/.baseline" || return 1
  printf '.baseline/\n' >> "$dir/.gitignore" || return 1
}

# bh_save_baseline <dir> <relative-file>: copy for later changed/unchanged checks.
bh_save_baseline() {
  local dir="$1" rel="$2" name
  name="$(printf '%s' "$rel" | tr '/' '_')"
  cp "$dir/$rel" "$dir/.baseline/$name"
}
bh_baseline() { printf '%s/.baseline/%s' "$1" "$(printf '%s' "$2" | tr '/' '_')"; }

# ── session ──────────────────────────────────────────────────────────────────
# bh_session <fixture> <prompt-file> <out.jsonl>: one headless Claude run.
# The prompt goes on stdin: --allowedTools is variadic and swallows a trailing
# positional prompt. Nested-session env must be unset or the child refuses.
bh_session() {
  local dir="$1" prompt_file="$2" out="$3" status=0
  if [[ "$ABE_RUNNER" != claude ]]; then
    printf 'ABE_RUNNER=%s is a documented seam, not an implementation\n' "$ABE_RUNNER" >&2
    return 2
  fi
  (
    cd "$dir" || exit 1
    export PATH="$TEST_ROOT/bin:$PATH"
    local var
    for var in $(env | cut -d= -f1 | grep -E '^(CLAUDECODE|CLAUDE_CODE_[A-Z0-9_]*|CLAUDE_PID|CLAUDE_EFFORT)$' || true); do
      unset "$var" 2>/dev/null || true
    done
    local -a sandbox=()
    (( ABE_SANDBOX )) && sandbox=(--settings "$BH_SANDBOX_SETTINGS")
    # shellcheck disable=SC2086  # ABE_ALLOWED_TOOLS is a space-separated list by contract
    claude -p --model "$ABE_MODEL" --max-turns "$ABE_MAX_TURNS" \
      --output-format stream-json --verbose --include-hook-events \
      ${sandbox[@]+"${sandbox[@]}"} \
      --allowedTools $ABE_ALLOWED_TOOLS < "$prompt_file" > "$out"
  ) || status=$?
  return "$status"
}

# ── containment ──────────────────────────────────────────────────────────────
# A fixture session gets unrestricted Bash. A model has already written a fake
# binary into ~/.local/bin during an eval, so every run scans the places a
# stray write would matter and turns any new file into a failing row.
BH_LEAK_PATHS="$HOME/.local/bin $HOME/bin $HOME/.local/share $HOME/.config /usr/local/bin /opt/homebrew/bin"
bh_leak_marker() { local marker="$1"; : > "$marker"; }
# bh_leak_scan <marker> <fixture>: list files newer than the marker outside the fixture.
bh_leak_scan() {
  local marker="$1" fixture="$2" dir found=""
  for dir in $BH_LEAK_PATHS; do
    [[ -d "$dir" ]] || continue
    found="$found$(find "$dir" -maxdepth 2 -type f -newer "$marker" -not -path "$fixture/*" 2>/dev/null)"$'\n'
  done
  found="$found$(find "$HOME" -maxdepth 1 -type f -newer "$marker" -not -name '.claude*' -not -name '.zsh*' -not -name '.bash*' -not -name '.DS_Store' 2>/dev/null)"$'\n'
  printf '%s' "$found" | grep -v '^$' || true
}

# ── transcript readers (node only; no jq, no python) ─────────────────────────
BH_TRANSCRIPT_JS='
const fs = require("fs");
const [file, mode, arg] = process.argv.slice(-3);
const events = fs.readFileSync(file, "utf8").split(/\r?\n/).filter(Boolean)
  .map(line => { try { return JSON.parse(line); } catch (error) { return null; } }).filter(Boolean);
const result = events.filter(e => e.type === "result").pop();
if (mode === "tool_uses") {
  let index = 0;
  for (const e of events) {
    if (e.type !== "assistant") continue;
    for (const part of (e.message && e.message.content) || []) {
      if (part.type !== "tool_use") continue;
      const input = part.input || {};
      const target = input.file_path || input.command || input.skill || input.pattern || input.path || "";
      console.log(index++ + " " + part.name + " " + String(target).replace(/\s+/g, " ").slice(0, 200));
    }
  }
} else if (mode === "final_text") {
  process.stdout.write(result ? String(result.result || "") : "");
} else if (mode === "all_text") {
  const parts = [];
  for (const e of events) {
    if (e.type !== "assistant") continue;
    for (const part of (e.message && e.message.content) || []) if (part.type === "text") parts.push(part.text);
  }
  process.stdout.write(parts.join("\n\n"));
} else if (mode === "result_field") {
  const value = result ? result[arg] : undefined;
  process.stdout.write(value === undefined ? "" : typeof value === "object" ? JSON.stringify(value) : String(value));
} else if (mode === "hook_blocks") {
  for (const e of events) {
    if (e.type !== "system") continue;
    if (e.subtype === "hook_response" && e.exit_code === 2)
      console.log("hook_block " + e.hook_name + " " + String(e.stderr || e.output || "").split("\n")[0].slice(0, 200));
    if (e.subtype === "permission_denied")
      console.log("permission_denied " + e.tool_name + " " + String(e.decision_reason || e.message || "").slice(0, 200));
  }
} else { console.error("unknown transcript mode: " + mode); process.exit(2); }
'
bh_transcript()   { node -e "$BH_TRANSCRIPT_JS" -- "$1" "$2" "${3:-}"; }
bh_tool_uses()    { bh_transcript "$1" tool_uses; }       # "<index> <Tool> <file|command>"
bh_final_text()   { bh_transcript "$1" final_text; }    # the last assistant message only
bh_all_text()     { bh_transcript "$1" all_text; }      # every assistant message, in order
bh_result_field() { bh_transcript "$1" result_field "$2"; }
bh_hook_blocks()  { bh_transcript "$1" hook_blocks; }

# bh_budget <jsonl>: one line of measured cost for the report.
bh_budget() {
  local jsonl="$1" turns cost ms
  turns="$(bh_result_field "$jsonl" num_turns)"
  cost="$(bh_result_field "$jsonl" total_cost_usd)"
  ms="$(bh_result_field "$jsonl" duration_ms)"
  printf 'model=%s max_turns=%s turns=%s cost_usd=%s wall_s=%s' "$ABE_MODEL" "$ABE_MAX_TURNS" \
    "${turns:-?}" "$(printf '%s' "${cost:-0}" | awk '{ printf "%.4f", $1 }')" \
    "$(printf '%s' "${ms:-0}" | awk '{ printf "%.0f", $1 / 1000 }')"
}

# ── reporting ────────────────────────────────────────────────────────────────
# bh_check <name> <status> <evidence>: 0 = PASS, anything else = FAIL.
bh_check() {
  local name="$1" status="$2" evidence="$3" verdict=PASS
  if (( status != 0 )); then verdict=FAIL; BH_FAILED=$((BH_FAILED + 1)); fi
  printf '| %s | %s | %s | %s |\n' "$verdict" "$BH_LABEL" "$name" "$(printf '%s' "$evidence" | tr '\n|' '  ')"
}
bh_info() { printf '| INFO | %s | %s | %s |\n' "$BH_LABEL" "$1" "$(printf '%s' "$2" | tr '\n|' '  ')"; }
bh_finish() { (( BH_FAILED == 0 )); }

# ── assertions ───────────────────────────────────────────────────────────────
# bh_assert_order <name> <jsonl> <earlier-ere> <later-ere>: first tool use
# matching <earlier> must come before the first matching <later>.
bh_assert_order() {
  local name="$1" jsonl="$2" earlier="$3" later="$4" uses first_a first_b
  uses="$(bh_tool_uses "$jsonl")"
  first_a="$(printf '%s\n' "$uses" | grep -E -m1 -- "$earlier" || true)"
  first_b="$(printf '%s\n' "$uses" | grep -E -m1 -- "$later" || true)"
  if [[ -z "$first_a" || -z "$first_b" ]]; then
    bh_check "$name" 1 "missing tool use: earlier=[${first_a:-none}] later=[${first_b:-none}]"
  elif (( ${first_a%% *} < ${first_b%% *} )); then
    bh_check "$name" 0 "#${first_a} before #${first_b}"
  else
    bh_check "$name" 1 "#${first_a} not before #${first_b}"
  fi
}

# bh_assert_final <name> <jsonl> <ere> / bh_assert_final_not: case-insensitive ERE
# against the session's final message.
bh_assert_final() {
  local name="$1" jsonl="$2" ere="$3" text hit
  text="$(bh_final_text "$jsonl")"
  hit="$(printf '%s\n' "$text" | grep -E -i -o -m1 -- "$ere" || true)"
  if [[ -n "$hit" ]]; then bh_check "$name" 0 "matched: $hit"
  else bh_check "$name" 1 "no match for /$ere/ in final text (${#text} chars)"; fi
}
bh_assert_final_not() {
  local name="$1" jsonl="$2" ere="$3" text hit
  text="$(bh_final_text "$jsonl")"
  hit="$(printf '%s\n' "$text" | grep -E -i -o -m1 -- "$ere" || true)"
  if [[ -z "$hit" ]]; then bh_check "$name" 0 "no match for /$ere/"
  else bh_check "$name" 1 "matched: $hit"; fi
}

# bh_assert_text <name> <jsonl> <ere> / bh_assert_text_not: same, over every
# assistant message. Use for report structure the skill mandates mid-session;
# use the final_* forms for the conclusion the user is left with.
bh_assert_text() {
  local name="$1" jsonl="$2" ere="$3" text hit
  text="$(bh_all_text "$jsonl")"
  hit="$(printf '%s\n' "$text" | grep -E -i -o -m1 -- "$ere" || true)"
  if [[ -n "$hit" ]]; then bh_check "$name" 0 "matched: $hit"
  else bh_check "$name" 1 "no match for /$ere/ in any assistant text (${#text} chars)"; fi
}
bh_assert_text_not() {
  local name="$1" jsonl="$2" ere="$3" text hit
  text="$(bh_all_text "$jsonl")"
  hit="$(printf '%s\n' "$text" | grep -E -i -o -m1 -- "$ere" || true)"
  if [[ -z "$hit" ]]; then bh_check "$name" 0 "no match for /$ere/ in any assistant text"
  else bh_check "$name" 1 "matched: $hit"; fi
}

bh_assert_file_has() {
  if [[ ! -f "$2" ]]; then bh_check "$1" 1 "missing file: $2"
  elif grep -Fq -- "$3" "$2"; then bh_check "$1" 0 "$2 contains: $3"
  else bh_check "$1" 1 "$2 lacks: $3"; fi
}
bh_assert_file_lacks() {
  if [[ ! -f "$2" ]]; then bh_check "$1" 0 "missing file: $2"
  elif grep -Fq -- "$3" "$2"; then bh_check "$1" 1 "$2 contains: $3"
  else bh_check "$1" 0 "$2 lacks: $3"; fi
}
bh_assert_exists()     { [[ -e "$2" ]] && bh_check "$1" 0 "exists: $2" || bh_check "$1" 1 "missing: $2"; }
bh_assert_missing()    { [[ -e "$2" ]] && bh_check "$1" 1 "exists: $2" || bh_check "$1" 0 "absent: $2"; }
bh_assert_changed()    { cmp -s "$2" "$3" && bh_check "$1" 1 "$2 identical to baseline" || bh_check "$1" 0 "$2 differs from baseline"; }
bh_assert_unchanged()  { cmp -s "$2" "$3" && bh_check "$1" 0 "$2 identical to baseline" || bh_check "$1" 1 "$2 differs from baseline"; }

# bh_assert_cmd <name> <dir> <command...>: passes when the command exits 0.
bh_assert_cmd() {
  local name="$1" dir="$2" out status=0
  shift 2
  out="$( cd "$dir" && "$@" 2>&1 )" || status=$?
  bh_check "$name" "$status" "exit=$status last line: $(printf '%s\n' "$out" | sed -n '$p')"
}
