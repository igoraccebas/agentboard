#!/bin/bash
# pre-commit-checkpoint.sh — git pre-commit hook (cross-provider fallback)
# Codex CLI and Gemini CLI have no session-end hook surface, so the commit
# is the last reliable moment to enforce capture: if open streams exist and
# code is being committed, require that some open stream was checkpointed
# today. Claude Code users get the tighter SessionEnd hook instead; this one
# catches everything else.
#
# Bypass for genuine exceptions:  AGENTBOARD_SKIP_CHECKPOINT=1 git commit ...
# Installed by: agentboard install-hooks --git
# agentboard:pre-commit-checkpoint  (marker — do not remove)

[ -n "$AGENTBOARD_SKIP_CHECKPOINT" ] && exit 0
[ -d ".platform/work" ] || exit 0

# Only gate commits that touch real work (something outside .platform/)
CODE_STAGED=$(git diff --cached --name-only | grep -v '^\.platform/' | head -1)
[ -z "$CODE_STAGED" ] && exit 0

TODAY=$(date +%F)
FRESH=""
for f in .platform/work/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in ACTIVE.md|BRIEF.md|TEMPLATE.md) continue ;; esac
  STATUS=$(awk -F': *' '/^status:/ { print $2; exit }' "$f")
  case "$STATUS" in done|archived|closed) continue ;; esac
  UPDATED=$(awk -F': *' '/^updated_at:/ { print $2; exit }' "$f")
  if [ "$UPDATED" = "$TODAY" ]; then
    FRESH=1
    break
  fi
done

[ -n "$FRESH" ] && exit 0

echo ""
echo "  ✖ agentboard: no open stream was checkpointed today."
echo "    Work state would go stale for whoever resumes (or whichever AI picks this up)."
echo ""
echo "    Fix:    agentboard checkpoint --auto       (10 seconds, derives state from git)"
echo "    Better: agentboard checkpoint <slug> --what \"...\" --next \"...\""
echo "    Bypass: AGENTBOARD_SKIP_CHECKPOINT=1 git commit ..."
echo ""
exit 1
