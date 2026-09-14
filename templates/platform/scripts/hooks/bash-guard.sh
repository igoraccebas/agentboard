#!/usr/bin/env bash
# Claude PreToolUse guardrail. Parse only tool_input.command and request a
# native approval prompt for sensitive commands. Shell pattern matching is
# conservative, not a security boundary; sandbox/permission policies still apply.
# Exit 2 would block every Bash call, so hook errors report (exit 1) instead.
set -uo pipefail
ask_for_review() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Agentboard guard: review this command before approving."}}\n'
}
if ! command -v node >/dev/null 2>&1; then
  # Without node, exit 2 would block every Bash call. Degrade to a coarse
  # match on the raw JSON: still ask for sensitive commands, let the rest pass.
  input="$(cat 2>/dev/null || true)"
  grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Bash"' <<< "$input" || exit 0
  # Flags must be whole words: "one-file.txt" is not "rm -f". A word ends at
  # whitespace, the JSON closing quote, a JSON escape, or the end of input.
  end='([[:space:]]|"|\\\\|$)'
  sensitive="git[^;&|]*[[:space:]](commit|push)$end|git[^;&|]*[[:space:]]reset[^;&|]*--hard$end|git[^;&|]*[[:space:]]checkout[^;&|]*[[:space:]]--$end|git[^;&|]*[[:space:]]branch[^;&|]*[[:space:]]-D$end|rm[[:space:]]+([^;&|]*[[:space:]])?-[rfRF]+$end|agentboard[[:space:]]+(approve$end|close[^;&|]*[[:space:]]--confirm$end)"
  if grep -Eq "$sensitive" <<< "$input"; then ask_for_review; fi
  exit 0
fi
node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);
    if (data.tool_name !== "Bash") return;
    const command = data.tool_input?.command;
    if (typeof command !== "string") throw new Error("Missing command");
    // Allow arguments between git and its subcommand, and flags in either order.
    // Overmatching commands which echo these strings is intentional.
    const git = /\bgit\b[^;\n&|]*\b(commit|push)\b|\bgit\b[^;\n&|]*\breset\b[^;\n&|]*--hard\b|\bgit\b[^;\n&|]*\bcheckout\b[^;\n&|]*--(?:\s|$)|\bgit\b[^;\n&|]*\bbranch\b[^;\n&|]*-D\b/;
    const removal = /\brm\s+[^;\n&|]*-[rfRF]+\b/;
    const approval = /\bagentboard\s+(?:approve\b|close\b[^;\n&|]*--confirm\b)/;
    if (git.test(command) || removal.test(command) || approval.test(command)) {
      process.stdout.write(JSON.stringify({hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: "Agentboard guard: review this command before approving."
      }}) + "\n");
    }
  } catch (error) {
    process.stderr.write("Agentboard guard could not read hook input: " + error.message + "\n");
    process.exitCode = 1;
  }
});
'
