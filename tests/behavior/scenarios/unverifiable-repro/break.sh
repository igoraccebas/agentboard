#!/usr/bin/env bash
# Red/green mutation, inside the fixture only: strip ab-debug's honesty rules —
# the Step 2 "mark the cause unconfirmed" sentence (reverting to the old
# "the bug is environmental" claim), the "a mock is not a reproduction"
# paragraph, the "user certainty is a hypothesis" paragraph, the Step 8
# reporting sentences, the "### Repro status:" output line, the matching red
# flag, and the honest wording of hard rule 1.
set -euo pipefail
fixture="$1"
skill="$fixture/.claude/skills/ab-debug/SKILL.md"
[[ -f "$skill" ]] || { printf 'missing %s\n' "$skill" >&2; exit 1; }
before="$(wc -l < "$skill")"
tmp="$(mktemp)"
awk '
  /^If you can.t reproduce locally, record the attempted steps/ {
    print "If you can'\''t reproduce locally, the bug is environmental — investigate the difference between environments first (config, data, versions, feature flags)."; next }
  /^A mock, stub, fake binary, or fixture you write yourself/ { next }
  /^The user.s certainty about the cause/ { next }
  /^Report each check as passed, failed, or not run/ { next }
  /^When the original repro could not run:/ { next }
  /^### Repro status:/ { print "### Repro status: <CONFIRMED locally / NOT REPRODUCED>"; next }
  /^- status: <verified against the real repro/ { next }
  /^End your final message with this block\. A summary may come before it, never instead of it\. If any Verification/ { print "End your final message with this block."; next }
  /^7\. \*\*A mock proves the mock\.\*\*/ { next }
  /^- \*\*You can.t reproduce locally\.\*\*/ { next }
  /^1\. \*\*Repro before fix\.\*\*/ { print "1. **Repro before fix.** No repro, no fix."; next }
  { print }
' "$skill" > "$tmp"
mv "$tmp" "$skill"
after="$(wc -l < "$skill")"
(( before - after >= 6 )) || { printf 'mutation removed only %s lines — template drift?\n' "$((before - after))" >&2; exit 1; }
! grep -q 'NOT RUN — name the real dependency' "$skill" || { printf 'honest repro-status enum still present\n' >&2; exit 1; }
! grep -q 'is \*\*not\*\* a reproduction' "$skill" || { printf 'mock paragraph still present\n' >&2; exit 1; }
grep -q 'the bug is environmental' "$skill" || { printf 'Step 2 reversion did not apply\n' >&2; exit 1; }
[[ -d "$fixture/.agents/skills/ab-debug" ]] && cp "$skill" "$fixture/.agents/skills/ab-debug/SKILL.md"
printf 'ab-debug mutated: %s -> %s lines\n' "$before" "$after"
