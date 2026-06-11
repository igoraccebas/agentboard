cmd_close() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  if [[ -z "$slug" || "${slug:0:2}" == "--" || "$slug" == "-h" ]]; then
    if [[ "$slug" == "-h" || "$slug" == "--help" ]]; then
      _close_print_help
      return 0
    else
      die "Usage: agentboard close <stream-slug> [--confirm] [--dry-run]"
    fi
  fi
  shift
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local confirm=0 dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help) _close_print_help; return 0 ;;
      *) die "Unknown flag for close: $1" ;;
    esac
  done

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."
  has_frontmatter "$stream_file" || die "$stream_file has no v1 frontmatter. Run 'agentboard migrate --apply' first."

  if (( ! confirm )); then
    _close_print_harvest_prompt "$slug" "$stream_file"
    return 0
  fi

  local archive_dir="./.platform/work/archive"
  mkdir -p "$archive_dir"
  local archive_path="$archive_dir/${slug}.md"
  if [[ -e "$archive_path" ]]; then
    local n=2
    while [[ -e "$archive_dir/${slug}-${n}.md" ]]; do n=$((n + 1)); done
    archive_path="$archive_dir/${slug}-${n}.md"
  fi

  if (( dry_run )); then
    printf '%sWould archive%s %s → %s\n' "$C_BOLD" "$C_RESET" "$stream_file" "$archive_path"
    printf '%sWould update frontmatter:%s status=done, closure_approved=true\n' "$C_BOLD" "$C_RESET"
    printf '%sWould append closure row to .platform/memory/log.md%s\n' "$C_BOLD" "$C_RESET"
    return 0
  fi

  local today_str agent
  today_str="$(today)"
  agent="${AGENTBOARD_AGENT:-${USER:-agent}}"

  replace_frontmatter_line "$stream_file" "status" "done"
  replace_frontmatter_line "$stream_file" "closure_approved" "true"
  replace_frontmatter_line "$stream_file" "updated_at" "$today_str"

  mv "$stream_file" "$archive_path"

  _close_append_log "$slug" "$archive_path" "$today_str" "$agent"
  _close_remove_from_active_registry "$slug"

  ok "Stream ${C_BOLD}${slug}${C_RESET} closed and archived → ${C_CYAN}${archive_path}${C_RESET}"
  say "  ${C_DIM}If the harvest step (facts + decisions) wasn't done before --confirm,${C_RESET}"
  say "  ${C_DIM}those insights are now lost from project memory. Re-run without --confirm to see the checklist.${C_RESET}"
}

_close_print_help() {
  cat <<'EOF'
Usage: agentboard close <stream-slug> [--confirm] [--dry-run]

Two-step stream closure. Default run prints the harvest checklist so the
agent can distill this stream's contribution into project memory. Then
run again with --confirm to archive the stream file and log closure.

Step 1 — harvest (no flag):
  Prints a checklist of what to extract from the stream and where to
  append it: gotchas.md, playbook.md, open-questions.md, decisions.md,
  learnings.md. The agent reads the checklist and writes those files
  itself using its Edit/Write tools.

Step 2 — finalize (--confirm):
  Moves the stream file to .platform/work/archive/<slug>.md
  Sets status=done, closure_approved=true
  Appends a closure row to .platform/memory/log.md
  Removes the stream from work/ACTIVE.md

Flags:
  --confirm   Actually archive + log. Run AFTER the harvest step.
  --dry-run   Preview archive actions without writing.

This is the compounding ritual: each close adds durable knowledge to the
project's memory files so the next agent inherits it via `agentboard brief`.
EOF
}

_close_print_harvest_prompt() {
  local slug="$1" stream_file="$2"
  local status
  status="$(frontmatter_value "$stream_file" "status")"

  printf '%s─── Harvest checklist for stream: %s%s%s%s ───%s\n\n' \
    "$C_BOLD" "$C_RESET" "$C_BOLD" "$slug" "$C_BOLD" "$C_RESET"
  printf '%sStream file:%s %s  %s(status=%s)%s\n\n' \
    "$C_DIM" "$C_RESET" "$stream_file" "$C_DIM" "${status:-?}" "$C_RESET"

  cat <<EOF
Before --confirm, distill this stream's contribution into project memory.
One command per durable insight — each becomes a small committed fact file
(no merge conflicts, domain-scoped loading, prunable later):

${C_BOLD}1. GOTCHAS${C_RESET}  — any landmines discovered? (things that'll trip the next agent)
   agentboard fact new --type gotcha --severity red|yellow|green \\
     --domain <slug> --stream ${slug} --title "<one line>"
   🔴 red = never-forget (always surfaced) · 🟡 yellow = usually-matters · 🟢 green = minor

${C_BOLD}2. PLAYBOOK${C_RESET} — any shortcut, command, or ritual worth recording?
   agentboard fact new --type playbook --domain <slug> --stream ${slug} \\
     --title "<practice>" --body "<why / when>"

${C_BOLD}3. OPEN QUESTIONS${C_RESET} — anything still unresolved?
   agentboard fact new --type question --domain <slug> --stream ${slug} --title "<question>"
   If this stream RESOLVED a prior question fact, mark it superseded:
   set 'status: superseded' in its file, then: agentboard fact reindex

${C_BOLD}4. DECISIONS${C_RESET} — locked-in architectural / product / tooling decisions?
   Add a row to .platform/memory/decisions.md ('Locked decisions' table) —
   the registry keeps the why + supersede chain that one-liners lose.

${C_BOLD}5. LEARNINGS${C_RESET} — non-obvious bug root-cause or hard-won pattern?
   agentboard fact new --type learning --domain <slug> --stream ${slug} \\
     --title "<symptom → root cause>" --body "<fix + class of problem>"

${C_BOLD}6. PRIVATE NOTES${C_RESET} — anything Claude learned off the record?
   agentboard harvest        # lists auto-memory notes worth promoting

Tip: a temporary workaround? Add --expires YYYY-MM-DD so \`fact prune\`
flags it when it should die.

When the harvest is done, run:
  ${C_BOLD}agentboard close ${slug} --confirm${C_RESET}

Skipping harvest is fine if the stream produced nothing durable — but once
the stream is archived, its raw context is no longer in active memory. The
only knowledge that survives is what you distilled into facts.
EOF
  printf '\n'
}

_close_append_log() {
  local slug="$1" archive_path="$2" today_str="$3" agent="$4"
  local log="./.platform/memory/log.md"
  [[ -f "$log" ]] || return 0
  local line="${today_str} — closed stream ${slug} → ${archive_path} (by ${agent})"
  local tmp; tmp="$(mktemp)"
  awk -v new="$line" '
    BEGIN { inserted = 0 }
    /^---$/ && !inserted { print; print ""; print new; inserted = 1; next }
    { print }
    END { if (!inserted) { print ""; print new } }
  ' "$log" > "$tmp"
  mv "$tmp" "$log"
}

_close_remove_from_active_registry() {
  local slug="$1"
  local registry="./.platform/work/ACTIVE.md"
  [[ -f "$registry" ]] || return 0
  local tmp; tmp="$(mktemp)"
  grep -v "^| *${slug} *|" "$registry" > "$tmp" || true
  mv "$tmp" "$registry"
}
