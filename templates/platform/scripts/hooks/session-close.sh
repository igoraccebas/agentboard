#!/bin/bash
# session-close.sh — SessionEnd hook (Claude Code)
# The capture safety net: when a session ends, save an automatic checkpoint
# so no day's work leaves the stream file stale. Targets the most recently
# updated open stream; a clean tree with no commits today is a silent no-op.
#
# Fail-open by design: if agentboard is missing or anything errors, the
# session still closes normally. Worst case: no auto-checkpoint. Exit 0 always.

[ -d ".platform/work" ] || exit 0

if command -v agentboard >/dev/null 2>&1; then
  AGENTBOARD_BIN="agentboard"
elif [ -x "./bin/agentboard" ]; then
  # Dogfood case: running inside the agentboard repo itself
  AGENTBOARD_BIN="./bin/agentboard"
else
  exit 0
fi

"$AGENTBOARD_BIN" checkpoint --auto 2>/dev/null || true

exit 0
