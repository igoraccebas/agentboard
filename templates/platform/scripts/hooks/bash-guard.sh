#!/usr/bin/env bash
# bash-guard.sh — Claude Code PreToolUse hook for the Bash tool.
#
# Intercepts destructive commands (git commit/push/reset --hard/checkout --/
# branch -D, rm -rf) and returns `permissionDecision: ask`. Claude Code shows
# the user an approval prompt; the LLM cannot bypass it.
#
# Input:  JSON on stdin. Shape: {"tool_name":"Bash","tool_input":{"command":"..."},...}
# Output: If destructive, JSON with permissionDecision. Otherwise, exit 0 silent.
#
# Fail-open by design: if parsing fails or the tool is not Bash, allow the
# default behavior. This is a guard-rail, not a firewall — the worst case is
# one extra approval click, not a blocked workflow.

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

# Filter by tool name. The input is JSON; grep-match is sufficient because the
# string "tool_name":"Bash" appears verbatim regardless of whitespace variants.
if ! printf '%s' "$INPUT" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Bash"'; then
  exit 0
fi

# Destructive patterns. Substring match against the whole JSON blob — the
# command string appears raw in any JSON encoding, so escape rules don't
# interfere with substring detection. Overmatching (e.g. a command that echoes
# "git commit") is acceptable: extra click vs. lost work is the right tradeoff.
# `agentboard approve` is in the list for a different reason: the approval
# click in Claude Code IS the human gate of the plan->approve->execute loop.
DESTRUCTIVE_RE='git[[:space:]]+(commit|push|reset[[:space:]]+--hard|checkout[[:space:]]+--|branch[[:space:]]+-D)|rm[[:space:]]+-[rfRF]+|git[[:space:]]+push[[:space:]]+--force|agentboard[[:space:]]+approve'

if printf '%s' "$INPUT" | grep -qE "$DESTRUCTIVE_RE"; then
  reason='Agentboard guard: this command requires user approval (your click IS the approval).'
  # Emit a compact permission decision. Claude Code shows the approval UI.
  printf '{"permissionDecision":"ask","permissionDecisionReason":"%s"}\n' "$reason"
fi

exit 0
