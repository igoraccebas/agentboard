#!/usr/bin/env bash
# The verification recipe: doctor checks its shape, the skill ships the
# five-part contract with attribution, the domain template carries Verify.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"
export NO_COLOR=1

recipe_fixture() {  # <dir>: fresh init with no recipe
  printf '{}\n' > "$1/package.json"
  init_project_fixture "$1"
}
full_recipe='# Verification recipe

## Launch
None — the CLI runs per command.

## Doctor
`agentboard doctor` exits 0.

## Drive
See the Verify rows in `domains/*.md`.

## Evidence
Terminal output and file state under `.platform/evidence/`.

## Cleanup
Remove the temp fixture; keep `.platform/evidence/`.
'

test_doctor_notes_a_missing_recipe_without_warning() {
  local dir output; dir="$(mktemp -d)"; recipe_fixture "$dir"
  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "no verification recipe"
  assert_contains "$output" "warnings: 0"
}

test_doctor_accepts_a_complete_recipe() {
  local dir output; dir="$(mktemp -d)"; recipe_fixture "$dir"
  mkdir -p "$dir/.platform/conventions"
  printf '%s' "$full_recipe" > "$dir/.platform/conventions/verification.md"
  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "all five recipe parts"
  assert_contains "$output" "warnings: 0"
}

test_doctor_warns_on_a_missing_part_but_keeps_exit_zero() {
  local dir output; dir="$(mktemp -d)"; recipe_fixture "$dir"
  mkdir -p "$dir/.platform/conventions"
  printf '%s' "$full_recipe" | sed '/^## Cleanup/,$d' > "$dir/.platform/conventions/verification.md"
  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "missing recipe part"
  assert_contains "$output" "Cleanup"
  assert_contains "$output" "warnings: 1"
}

test_doctor_warns_on_unfilled_placeholders() {
  local dir output; dir="$(mktemp -d)"; recipe_fixture "$dir"
  mkdir -p "$dir/.platform/conventions"
  printf '%s' "$full_recipe" | sed 's/agentboard doctor/{{DOCTOR_COMMAND}}/' > "$dir/.platform/conventions/verification.md"
  run_cli_capture output "$dir" doctor
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "unfilled"
  assert_contains "$output" "warnings: 1"
}

test_skill_ships_the_five_part_contract_with_attribution() {
  local skill="$TEST_ROOT/templates/skills/ab-verify/SKILL.md" part
  [[ -f "$skill" ]] || fail "templates/skills/ab-verify/SKILL.md missing"
  for part in Launch Doctor Drive Evidence Cleanup; do
    assert_file_contains "$skill" "## $part"
  done
  assert_file_contains "$skill" "MIT"
  assert_file_contains "$skill" "pstack"
  assert_file_contains "$skill" "poteto"
  assert_file_contains "$skill" "create"
  assert_file_contains "$skill" "maintain"
  assert_file_not_contains "$skill" "{{"
  (( $(wc -l < "$skill") <= 220 )) || fail "ab-verify SKILL.md is over the size tripwire"
}

test_domain_template_has_the_verify_table() {
  local tpl="$TEST_ROOT/templates/platform/domains/TEMPLATE.md"
  assert_file_contains "$tpl" "## Verify (optional)"
  assert_file_contains "$tpl" "| Feature | Drive"
  assert_file_contains "$tpl" "Expected observable result"
  assert_file_contains "$tpl" "Evidence"
}

for test_case in test_doctor_notes_a_missing_recipe_without_warning test_doctor_accepts_a_complete_recipe \
  test_doctor_warns_on_a_missing_part_but_keeps_exit_zero test_doctor_warns_on_unfilled_placeholders \
  test_skill_ships_the_five_part_contract_with_attribution test_domain_template_has_the_verify_table; do
  printf 'RUN: %s\n' "$test_case"
  "$test_case"
done
