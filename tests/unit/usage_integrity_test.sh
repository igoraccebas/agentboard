#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"
export NO_COLOR=1
unset AGENTBOARD_SESSION_ID

usage_log_fixture() {
  env HOME="$usage_home" "$TEST_ROOT/bin/agentboard" usage log --provider codex --stream login "$@" >/dev/null
}

test_legacy_reset_updates_baseline() {
  local usage_home; usage_home="$(mktemp -d)"
  usage_log_fixture --cumulative-in 100 --cumulative-out 10
  usage_log_fixture --cumulative-in 50 --cumulative-out 5
  usage_log_fixture --cumulative-in 80 --cumulative-out 8
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT SUM(input_tokens), SUM(output_tokens) FROM usage;')" '180|18'
}

test_explicit_sessions_and_stale_observations() {
  local usage_home; usage_home="$(mktemp -d)"
  usage_log_fixture --session-id first --cumulative-in 100 --cumulative-out 10
  usage_log_fixture --session-id second --cumulative-in 150 --cumulative-out 15
  usage_log_fixture --session-id second --cumulative-in 120 --cumulative-out 12
  usage_log_fixture --session-id second --cumulative-in 180 --cumulative-out 18
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT SUM(input_tokens), SUM(output_tokens), COUNT(DISTINCT session_id) FROM usage;')" '280|28|2'
}

test_environment_session_and_legacy_key_alias() {
  local usage_home; usage_home="$(mktemp -d)"
  AGENTBOARD_SESSION_ID=environment usage_log_fixture --cumulative-in 100 --cumulative-out 10
  usage_log_fixture --session-id environment --cumulative-in 120 --cumulative-out 12
  usage_log_fixture --session-key custom --cumulative-in 200 --cumulative-out 20
  usage_log_fixture --session-key custom --cumulative-in 220 --cumulative-out 22
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT SUM(input_tokens), SUM(output_tokens), COUNT(DISTINCT session_id) FROM usage;')" '340|34|2'
}

test_project_identity_is_not_repo_basename() {
  local usage_home; usage_home="$(mktemp -d)"
  mkdir -p "$usage_home/one/project" "$usage_home/two/project"
  (cd "$usage_home/one/project" && usage_log_fixture --session-id same --cumulative-in 100 --cumulative-out 10)
  (cd "$usage_home/two/project" && usage_log_fixture --session-id same --cumulative-in 120 --cumulative-out 12)
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT SUM(input_tokens), SUM(output_tokens) FROM usage;')" '220|22'
}

test_partial_counter_drop_does_not_reset() {
  local usage_home; usage_home="$(mktemp -d)"
  usage_log_fixture --cumulative-in 100 --cumulative-out 10
  usage_log_fixture --cumulative-in 90 --cumulative-out 12
  usage_log_fixture --cumulative-in 120 --cumulative-out 15
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT SUM(input_tokens), SUM(output_tokens) FROM usage;')" '120|15'
}

test_quoted_fields_round_trip_and_stream_query_is_safe() {
  local usage_home value actual result; usage_home="$(mktemp -d)"
  value=$'O\x27Brien; DROP TABLE usage; --\nsecond line "quoted"'
  usage_log_fixture --provider "$value" --model "$value" --stream "$value" --repo "$value" --type "$value" --note "$value" --session-id "$value" --input 8 --output 2
  for column in agent_provider model stream_slug repo task_type note session_id; do
    actual="$(sqlite3 "$usage_home/.agentboard/usage.db" "SELECT $column FROM usage;")"
    assert_eq "$actual" "$value"
  done
  result="$(env HOME="$usage_home" "$TEST_ROOT/bin/agentboard" usage stream "$value")"
  assert_contains "$result" 'STREAM TOTAL: 10'
  env HOME="$usage_home" "$TEST_ROOT/bin/agentboard" usage stream "'; DROP TABLE usage; --" >/dev/null
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT COUNT(*) FROM usage;')" 1
}

test_concurrent_cumulative_updates_are_atomic() {
  local usage_home pid pids=() n; usage_home="$(mktemp -d)"
  for n in 100 200 300 400 500 600; do
    usage_log_fixture --session-id concurrent --cumulative-in "$n" --cumulative-out "$((n / 10))" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || fail 'concurrent writer failed'; done
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT SUM(input_tokens), SUM(output_tokens) FROM usage;')" '600|60'
}

test_database_failure_propagates_inside_conditional() {
  local usage_home result status; usage_home="$(mktemp -d)"
  result="$(
    _usage_db="$usage_home/unwritable.db"
    _init_usage_db() { return 0; }
    sqlite3() { return 1; }
    if cmd_usage log --provider codex --input 1 --output 2; then
      printf 'unexpected success'
    else
      printf 'expected failure'
    fi
  )"
  assert_contains "$result" 'expected failure'
  assert_not_contains "$result" 'Logged'
}

test_invalid_delta_tokens_are_rejected() {
  local usage_home result; usage_home="$(mktemp -d)"
  run_and_capture result env HOME="$usage_home" "$TEST_ROOT/bin/agentboard" usage log --provider codex --input -2 --output 1
  [[ "$RUN_STATUS" != 0 ]] || fail 'negative input accepted'
}

test_mixed_reports_share_the_same_baseline() {
  local usage_home; usage_home="$(mktemp -d)"
  usage_log_fixture --session-id mixed --input 100 --output 10
  usage_log_fixture --session-id mixed --cumulative-in 150 --cumulative-out 15
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT SUM(input_tokens),SUM(output_tokens) FROM usage;')" '150|15'
  usage_log_fixture --session-id mixed --input 20 --output 2
  usage_log_fixture --session-id mixed --cumulative-in 180 --cumulative-out 18
  assert_eq "$(sqlite3 "$usage_home/.agentboard/usage.db" 'SELECT SUM(input_tokens),SUM(output_tokens) FROM usage;')" '180|18'
}

failed=0
for test_case in test_mixed_reports_share_the_same_baseline test_legacy_reset_updates_baseline test_explicit_sessions_and_stale_observations test_environment_session_and_legacy_key_alias test_project_identity_is_not_repo_basename test_partial_counter_drop_does_not_reset test_quoted_fields_round_trip_and_stream_query_is_safe test_concurrent_cumulative_updates_are_atomic test_database_failure_propagates_inside_conditional test_invalid_delta_tokens_are_rejected; do
  printf 'RUN: %s\n' "$test_case"
  ("$test_case") || failed=$((failed + 1))
done
[[ "$failed" == 0 ]] || fail "$failed usage integrity regressions"
