#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

export NO_COLOR=1

# All usage tests use an isolated HOME so they never touch ~/.agentboard/usage.db

seed_segments() {
  local home="$1" i
  for i in 1 2 3; do
    env HOME="$home" "$TEST_ROOT/bin/agentboard" usage log \
      --provider claude --input 1000 --output 500 \
      --stream pay-flow --type feature >/dev/null
  done
  env HOME="$home" "$TEST_ROOT/bin/agentboard" usage log \
    --provider codex --input 200 --output 100 \
    --stream tiny-fix --type bugfix >/dev/null
  env HOME="$home" "$TEST_ROOT/bin/agentboard" usage log \
    --provider claude --input 800 --output 300 \
    --stream pay-flow --type feature >/dev/null
}

test_impact_needs_minimum_data() {
  local home output
  home="$(mktemp -d)"
  run_and_capture output env HOME="$home" "$TEST_ROOT/bin/agentboard" usage impact
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "impact needs ~5+"
}

test_impact_reports_per_stream_and_trend() {
  local home output
  home="$(mktemp -d)"
  seed_segments "$home"
  run_and_capture output env HOME="$home" "$TEST_ROOT/bin/agentboard" usage impact
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "Tokens per stream"
  assert_contains "$output" "pay-flow"
  assert_contains "$output" "tiny-fix"
  assert_contains "$output" "Avg tokens per segment"
  assert_contains "$output" "feature"
  assert_contains "$output" "bugfix"
  # The reading guide keeps the metric honest
  assert_contains "$output" "Caveats"
}

test_impact_trend_flags_cheaper_months() {
  local home output db
  home="$(mktemp -d)"
  seed_segments "$home"
  db="$home/.agentboard/usage.db"
  # Inject an expensive prior month for the same task type
  sqlite3 "$db" "INSERT INTO usage (timestamp, agent_provider, model, stream_slug, repo, task_type, input_tokens, output_tokens, total_tokens, estimated_cost, note, session_id)
    VALUES (DATETIME('now', '-1 month'), 'claude', '', 'pay-flow', 'x', 'feature', 9000, 3000, 12000, 0, '', '');"
  run_and_capture output env HOME="$home" "$TEST_ROOT/bin/agentboard" usage impact
  assert_status "$RUN_STATUS" 0
  assert_contains "$output" "cheaper"
}

for t in \
  test_impact_needs_minimum_data \
  test_impact_reports_per_stream_and_trend \
  test_impact_trend_flags_cheaper_months; do
  printf 'RUN: %s\n' "$t" >&2
  "$t"
done
