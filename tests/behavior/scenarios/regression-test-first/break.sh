#!/usr/bin/env bash
# Red/green mutation, applied inside the throwaway fixture only: remove the
# "regression test before the fix" rule from the fixture's ab-debug copy —
# Step 6, hard rule 4, the Step 5 hand-off to Step 6, and the ### Verification
# block of the output format. Fails loudly if the template text has drifted.
set -euo pipefail
fixture="$1"
skill="$fixture/.claude/skills/ab-debug/SKILL.md"
[[ -f "$skill" ]] || { printf 'missing %s\n' "$skill" >&2; exit 1; }
before="$(wc -l < "$skill")"
tmp="$(mktemp)"
awk '
  /^### Step 6 — Write the regression test/ { drop = 1 }
  /^### Step 7 — Fix the root cause/ { drop = 0 }
  /^### Verification$/ { drop = 1 }
  /^### Logged to / { drop = 0 }
  drop { next }
  /^4\. \*\*Regression test before fix\.\*\*/ { next }
  /^- \*\*If CONFIRMED:\*\*/ { print "- **If CONFIRMED:** you found the cause. Skip to Step 7."; next }
  { print }
' "$skill" > "$tmp"
mv "$tmp" "$skill"
after="$(wc -l < "$skill")"
(( before - after >= 8 )) || { printf 'mutation removed only %s lines — template drift?\n' "$((before - after))" >&2; exit 1; }
! grep -q 'Regression test before fix' "$skill" || { printf 'hard rule 4 still present\n' >&2; exit 1; }
! grep -q '^### Verification' "$skill" || { printf 'verification block still present\n' >&2; exit 1; }
[[ -d "$fixture/.agents/skills/ab-debug" ]] && cp "$skill" "$fixture/.agents/skills/ab-debug/SKILL.md"
printf 'ab-debug mutated: %s -> %s lines\n' "$before" "$after"
