#!/usr/bin/env bash
# Did the agent reproduce first, write the failing test before the fix, leave
# the harness green, and report verification the way ab-debug says to?
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
fixture="$1" jsonl="$2" variant="${3:-base}"
src='src/slugify\.sh'
[[ "$variant" == heldout ]] && src='src/truncate\.sh'
bh_assert_order "repro-run-before-source-edit" "$jsonl" '^[0-9]+ Bash .*tests/run\.sh' "^[0-9]+ (Edit|Write) .*$src"
bh_assert_order "test-edit-before-source-edit" "$jsonl" '^[0-9]+ (Edit|Write) .*/tests/' "^[0-9]+ (Edit|Write) .*$src"
bh_assert_changed "harness-gained-a-case" "$fixture/tests/run.sh" "$(bh_baseline "$fixture" tests/run.sh)"
bh_assert_cmd "harness-green-after-fix" "$fixture" bash tests/run.sh
# The skill's report is emitted while working; the last message is often a
# summary table. Read the whole conversation, and accept the status however
# it is punctuated (":" / "|" / bold) as long as it is stated.
bh_assert_text "verification-block-reported" "$jsonl" '### Verification'
bh_assert_text "regression-test-status-reported" "$jsonl" 'regression test[^a-z]{0,12}(passed|pass|failed|fail|not run)'
bh_finish
