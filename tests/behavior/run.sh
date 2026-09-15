#!/usr/bin/env bash
# On-demand behavioral evals: prove the shipped ab-* skills change what an
# agent does. Each scenario runs a real headless Claude session in a fresh
# `agentboard init` fixture; --proof also runs a deliberately broken copy of
# the skill and requires that run to fail. Lives outside tests/unit on purpose:
# it calls a live model and costs money, so it is never part of the merge gate.
set -euo pipefail
BEHAVIOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BEHAVIOR_ROOT/lib.sh"

usage() {
  cat <<'USAGE'
Usage: bash tests/behavior/run.sh [--only <scenario>] [--variant base|heldout|both] [--proof] [--keep]

  --only <scenario>   run one scenario directory under tests/behavior/scenarios/
  --variant <v>       base, heldout, or both (default both; --proof uses base)
  --proof             red/green: shipped skill must pass, broken copy must fail
  --keep              keep the throwaway fixtures for inspection

Exit 0 = every assertion passed; 1 = an assertion or proof failed;
3 = a session was BLOCKED (quota, max turns, empty transcript) and nothing failed.
Artifacts: tests/behavior/runs/<UTC stamp>/{report.md,*.jsonl}
USAGE
}

only="" variant=both proof=0 keep=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)    [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; only="$2"; shift 2 ;;
    --variant) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; variant="$2"; shift 2 ;;
    --proof)   proof=1; shift ;;
    --keep)    keep=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
case "$variant" in base|heldout|both) ;; *) usage >&2; exit 2 ;; esac
command -v claude >/dev/null 2>&1 || { printf 'behavior evals need the claude CLI on PATH\n' >&2; exit 2; }
command -v node >/dev/null 2>&1 || { printf 'behavior evals need node on PATH\n' >&2; exit 2; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="$BEHAVIOR_ROOT/runs/$stamp"
[[ -e "$run_dir" ]] && run_dir="$run_dir-$$"   # two runners in the same second
mkdir -p "$run_dir"
report="$run_dir/report.md"
fixture_list="$run_dir/.fixtures"
: > "$fixture_list"

cleanup() {
  (( keep )) && return 0
  local fixture
  while IFS= read -r fixture; do
    [[ -n "$fixture" && -d "$fixture" && "$fixture" != "$TEST_ROOT"* ]] && rm -rf "$fixture"
  done < "$fixture_list"
  rm -f "$fixture_list"
}
trap cleanup EXIT

emit() { printf '%s\n' "$*" | tee -a "$report"; }

# run_one <scenario> <variant> <broken 0|1>: setup → (break) → session → assert.
# Prints report rows. Returns 0 pass, 1 assertion failed, 3 blocked/setup error.
run_one() {
  local scenario="$1" variant="$2" broken="$3"
  local dir="$BEHAVIOR_ROOT/scenarios/$scenario" label="$scenario.$variant" fixture jsonl prompt
  (( broken )) && label="$label.broken"
  fixture="$(mktemp -d)" || return 3
  printf '%s\n' "$fixture" >> "$fixture_list"
  jsonl="$run_dir/$label.jsonl"
  # shellcheck source=/dev/null
  source "$dir/meta.env"
  if ! bash "$dir/setup.sh" "$fixture" "$variant" >"$run_dir/$label.setup.log" 2>&1; then
    emit "| ERROR | $label | setup | setup.sh failed — see $label.setup.log |"; return 3
  fi
  if (( broken )) && ! bash "$dir/break.sh" "$fixture" >"$run_dir/$label.break.log" 2>&1; then
    emit "| ERROR | $label | break | break.sh failed — see $label.break.log |"; return 3
  fi
  prompt="$dir/prompt.txt"
  [[ "$variant" == heldout ]] && prompt="$dir/prompt.heldout.txt"
  local session_status=0 subtype leaks
  bh_leak_marker "$run_dir/$label.marker"
  bh_session "$fixture" "$prompt" "$jsonl" || session_status=$?
  leaks="$(bh_leak_scan "$run_dir/$label.marker" "$fixture")"
  if [[ -n "$leaks" ]]; then
    emit "| LEAK | $label | containment | session wrote outside the fixture: $(printf '%s' "$leaks" | tr '\n' ' ') — remove these files by hand |"
  fi
  subtype="$(bh_result_field "$jsonl" subtype 2>/dev/null || true)"
  if [[ "$subtype" == error_max_turns ]]; then
    # The agent used its whole budget without concluding. That is behavior,
    # not an outage: score what it did and say the budget ran out.
    emit "| INFO | $label | session | max turns exhausted ($ABE_MAX_TURNS) — scored on the partial transcript |"
  elif [[ "$subtype" != success ]]; then
    emit "| BLOCKED | $label | session | result=${subtype:-none} claude_exit=$session_status — not a failing assertion |"
    return 3
  fi
  local rows status=0
  rows="$(BH_LABEL="$label" bash "$dir/assert.sh" "$fixture" "$jsonl" "$variant")" || status=$?
  emit "$rows"
  emit "| BUDGET | $label | session | $(bh_budget "$jsonl") |"
  [[ -z "$leaks" ]] || status=1
  return "$status"
}

{
  printf '# Behavior eval report — %s\n\n' "$stamp"
  printf 'Command: run.sh %s\n\n' "${*:-}"
  printf '| Verdict | Run | Check | Evidence |\n|---|---|---|---|\n'
} > "$report"

failed=0 blocked=0
for dir in "$BEHAVIOR_ROOT"/scenarios/*/; do
  scenario="$(basename "$dir")"
  [[ -z "$only" || "$only" == "$scenario" ]] || continue
  if (( proof )); then
    shipped=0 mutated=0
    run_one "$scenario" base 0 || shipped=$?
    run_one "$scenario" base 1 || mutated=$?
    if (( shipped == 3 || mutated == 3 )); then
      emit "| PROOF | $scenario | red/green | BLOCKED — a session did not complete |"; blocked=$((blocked + 1))
    elif (( shipped != 0 )); then
      emit "| PROOF | $scenario | red/green | shipped skill FAILS its own scenario — see rows above |"; failed=$((failed + 1))
    elif (( mutated == 0 )); then
      emit "| PROOF | $scenario | red/green | NO ENFORCEMENT PROVEN — the broken copy still passes |"; failed=$((failed + 1))
    else
      emit "| PROOF | $scenario | red/green | confirmed: shipped passes, broken copy fails |"
    fi
    continue
  fi
  for v in base heldout; do
    [[ "$variant" == both || "$variant" == "$v" ]] || continue
    status=0
    run_one "$scenario" "$v" 0 || status=$?
    case "$status" in 0) ;; 3) blocked=$((blocked + 1)) ;; *) failed=$((failed + 1)) ;; esac
  done
done

printf '\nReport: %s\n' "$report"
if (( failed > 0 )); then exit 1; fi
if (( blocked > 0 )); then exit 3; fi
exit 0
