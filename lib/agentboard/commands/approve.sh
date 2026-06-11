# approve.sh — the human gate between plan and execution
#
# The planner model (Opus) writes an `## Execution brief` into the stream
# file; nothing executes until a human flips brief_approved. The bash-guard
# hook intercepts this command in Claude Code, so the approving click is
# always yours — the LLM cannot approve its own plan.

cmd_approve() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  if [[ -z "$slug" || "$slug" == "-h" || "$slug" == "--help" ]]; then
    if [[ "$slug" == "-h" || "$slug" == "--help" ]]; then
      _approve_print_help
      return 0
    fi
    die "Usage: agentboard approve <stream-slug> [--revoke]"
  fi
  shift
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local revoke=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --revoke) revoke=1; shift ;;
      -h|--help) _approve_print_help; return 0 ;;
      *) die "Unknown flag for approve: $1" ;;
    esac
  done

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."
  has_frontmatter "$stream_file" || die "$stream_file has no v1 frontmatter. Run 'agentboard migrate --apply' first."

  grep -q '^## Execution brief' "$stream_file" \
    || die "No '## Execution brief' section in $stream_file — nothing to approve. The planner writes it first."

  local current
  current="$(frontmatter_value "$stream_file" "brief_approved")"

  if (( revoke )); then
    if [[ "$current" != "true" ]]; then
      ok "Brief for ${C_BOLD}${slug}${C_RESET} was not approved — nothing to revoke."
      return 0
    fi
    set_frontmatter_value "$stream_file" "brief_approved" "false"
    replace_frontmatter_line "$stream_file" "updated_at" "$(today)"
    ok "Approval revoked for ${C_BOLD}${slug}${C_RESET}. Execution should stop until re-approved."
    return 0
  fi

  if [[ "$current" == "true" ]]; then
    ok "Brief for ${C_BOLD}${slug}${C_RESET} is already approved."
    return 0
  fi

  set_frontmatter_value "$stream_file" "brief_approved" "true"
  replace_frontmatter_line "$stream_file" "updated_at" "$(today)"
  ok "Execution brief approved for ${C_BOLD}${slug}${C_RESET}."
  say "  ${C_DIM}The executor may now write code — within the brief's do/don't lines.${C_RESET}"
}

_approve_print_help() {
  cat <<'EOF'
Usage: agentboard approve <stream-slug> [--revoke]

Human approval gate for the plan→execute loop:

  1. The planner model (e.g. Opus via the ab-planner agent) researches the
     task and writes an `## Execution brief` into the stream file —
     objective, do/don't lines, files in scope, acceptance criteria —
     and sets brief_approved: false.
  2. A human reviews the brief and runs this command (in Claude Code, the
     bash-guard hook turns it into a yes/no click — the LLM cannot
     self-approve).
  3. The execution model (e.g. Fable 5) implements within the brief.
     `agentboard handoff` shows the gate status to every resuming agent.

Flags:
  --revoke   Set brief_approved back to false (plan changed, stop execution).

The gate is opt-in per stream: streams without an Execution brief are not
gated at all — trivial work flows untouched.
EOF
}
