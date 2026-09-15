cmd_close() {
  with_state_lock _cmd_close "$@"
}

_cmd_close() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  if [[ -z "$slug" || "${slug:0:2}" == "--" || "$slug" == "-h" ]]; then
    if [[ "$slug" == "-h" || "$slug" == "--help" ]]; then
      _close_print_help
      return 0
    else
      die "Usage: agentboard close <stream-slug> [--approve [--revoke]] [--confirm] [--dry-run]"
    fi
  fi
  shift
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local confirm=0 dry_run=0 approve=0 revoke=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --confirm) confirm=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --approve) approve=1; shift ;;
      --revoke)  revoke=1; shift ;;
      -h|--help) _close_print_help; return 0 ;;
      *) die "Unknown flag for close: $1" ;;
    esac
  done

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."
  has_frontmatter "$stream_file" || die "$stream_file has no v1 frontmatter. Run 'agentboard migrate --apply' first."

  if (( revoke && ! approve )); then
    die "--revoke only makes sense with --approve: agentboard close $slug --approve --revoke"
  fi
  if (( approve )); then
    (( ! confirm )) || die "Run --approve and --confirm as two separate commands."
    _close_record_approval "$slug" "$stream_file" "$revoke"
    return $?
  fi

  if (( ! confirm )); then
    _close_print_harvest_prompt "$slug" "$stream_file"
    return 0
  fi

  local archive_dir="./.platform/work/archive"
  local archive_path="$archive_dir/${slug}.md"
  if [[ -e "$archive_path" ]]; then
    local n=2
    while [[ -e "$archive_dir/${slug}-${n}.md" ]]; do n=$((n + 1)); done
    archive_path="$archive_dir/${slug}-${n}.md"
  fi

  if (( dry_run )); then
    printf '%sWould archive%s %s → %s\n' "$C_BOLD" "$C_RESET" "$stream_file" "$archive_path"
    printf '%sWould update frontmatter:%s status=done (requires recorded closure approval and completed criteria)\n' "$C_BOLD" "$C_RESET"
    printf '%sWould append closure row to .platform/memory/log.md%s\n' "$C_BOLD" "$C_RESET"
    return 0
  fi

  if [[ "$(frontmatter_value "$stream_file" closure_approved)" != true ||
        -z "$(frontmatter_value "$stream_file" approved_by)" ||
        -z "$(frontmatter_value "$stream_file" approved_at)" ]]; then
    die "Closure approval was not recorded by the CLI. The owner runs: agentboard close $slug --approve"
  fi
  if [[ -n "$(_close_unchecked_criteria "$stream_file")" ]]; then
    die "Unchecked done criteria remain. Finish verification before closing."
  fi

  local today_str agent
  today_str="$(today)"
  agent="${AGENTBOARD_AGENT:-${USER:-agent}}"

  _close_commit() {
    mkdir -p "$archive_dir" || return 1
    cp -p "$stream_file" "$archive_path" || return 1
    replace_frontmatter_line "$archive_path" "status" "done" || return 1
    replace_frontmatter_line "$archive_path" "updated_at" "$today_str" || return 1
    _close_append_log "$slug" "$archive_path" "$today_str" "$agent" || return 1
    _close_remove_from_active_registry "$slug" || return 1
    _close_refresh_brief "$slug" || return 1
    rm "$stream_file" || return 1
  }
  state_transaction _close_commit "$stream_file" "$archive_path" \
    ./.platform/work/ACTIVE.md ./.platform/work/BRIEF.md ./.platform/memory/log.md || return 1

  ok "Stream ${C_BOLD}${slug}${C_RESET} closed and archived → ${C_CYAN}${archive_path}${C_RESET}"
  say "  ${C_DIM}If the harvest step (facts + decisions) wasn't done before --confirm,${C_RESET}"
  say "  ${C_DIM}those insights are now lost from project memory. Re-run without --confirm to see the checklist.${C_RESET}"
}

_close_print_help() {
  cat <<'EOF'
Usage: agentboard close <stream-slug> [--approve [--revoke]] [--confirm] [--dry-run]

Three-step stream closure. The default run prints the harvest checklist so
the agent can distill this stream's contribution into project memory. The
OWNER then records approval with --approve. Finally --confirm archives the
stream file and logs closure.

Step 1 — harvest (no flag):
  Prints a checklist of what to extract from the stream and where to
  append it: gotchas.md, playbook.md, open-questions.md, decisions.md,
  learnings.md. The agent reads the checklist and writes those files
  itself using its Edit/Write tools.

Step 2 — approve (--approve, run by the OWNER):
  Refuses while any Done criterion is unchecked and lists the open ones —
  the owner ticks them in their editor; the agent never does.
  Records the approval in the stream file with who approved and when.
  In Claude Code the bash guard turns this command into a native prompt
  that names what is being granted. Agents must not run it on the
  owner's behalf; "close it" in chat is a request, not this approval.
  --approve --revoke withdraws a recorded approval.

Step 3 — finalize (--confirm):
  Requires the approval recorded by --approve and no unchecked done criteria
  Moves the stream file to .platform/work/archive/<slug>.md — the only
  archival path; never mv the file or edit ACTIVE.md by hand
  Sets status=done, appends a closure row to .platform/memory/log.md,
  removes the stream from work/ACTIVE.md, clears BRIEF.md if it pointed here

Honest limit: an editable file cannot prove identity. The hooks make the
approval impossible to grant by accident or by following instructions, and
the owner sees one native prompt for the one command that grants it.
Codex and Gemini have no hook surface: there, only the --confirm check
stands between an agent and the archive.

Flags:
  --approve   Record the owner's approval (owner runs this).
  --revoke    With --approve: withdraw the recorded approval.
  --confirm   Actually archive + log. Run AFTER harvest and approval.
  --dry-run   Preview archive actions without writing.

This is the compounding ritual: each close adds durable knowledge to the
project's memory files so the next agent inherits it via `agentboard brief`.
EOF
}

# _close_unchecked_criteria <stream_file>: prints the unchecked Done criteria.
_close_unchecked_criteria() {
  awk '/^## Done criteria[[:space:]]*$/ { in_section=1; next }
    in_section && /^## / { exit }
    in_section && /^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]/ { print }' "$1"
}

# _close_record_approval <slug> <stream_file> <revoke 0|1>
# The owner's act: the only writer of the approval record. Single-file write
# under the state lock; refuses to approve past open criteria.
_close_record_approval() {
  local slug="$1" stream_file="$2" revoke="$3" open_items key
  if (( revoke )); then
    set_frontmatter_value "$stream_file" closure_approved false || return 1
    for key in approved_by approved_at; do
      _close_drop_frontmatter_key "$stream_file" "$key" || return 1
    done
    set_frontmatter_value "$stream_file" updated_at "$(today)" || return 1
    ok "Closure approval for ${C_BOLD}${slug}${C_RESET} withdrawn."
    return 0
  fi
  open_items="$(_close_unchecked_criteria "$stream_file")"
  if [[ -n "$open_items" ]]; then
    printf '%s\n' "$open_items" >&2
    die "Unchecked done criteria remain in $stream_file — tick them in your editor, then approve again."
  fi
  set_frontmatter_value "$stream_file" closure_approved true || return 1
  set_frontmatter_value "$stream_file" approved_by "${AGENTBOARD_APPROVER:-${USER:-unknown}}" || return 1
  set_frontmatter_value "$stream_file" approved_at "$(date '+%Y-%m-%d %H:%M:%S %z')" || return 1
  set_frontmatter_value "$stream_file" updated_at "$(today)" || return 1
  ok "Closure approved for ${C_BOLD}${slug}${C_RESET} by ${AGENTBOARD_APPROVER:-${USER:-unknown}}. Criteria approved:"
  awk '/^## Done criteria[[:space:]]*$/ { in_section=1; next }
    in_section && /^## / { exit }
    in_section && /^[[:space:]]*[-*][[:space:]]+\[[xX]\]/ { print "    " $0 }' "$stream_file"
  say "  ${C_DIM}Next: agentboard close ${slug} --confirm${C_RESET}"
}

# _close_drop_frontmatter_key <file> <key>: remove a key from the leading
# frontmatter block only; body text is never touched.
_close_drop_frontmatter_key() {
  local file="$1" key="$2" tmp
  tmp="$(mktemp "$(dirname "$file")/.close.XXXXXX")" || return 1
  awk -v key="$key" '
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; print; next }
    in_fm && /^---[[:space:]]*$/ { in_fm = 0; print; next }
    in_fm && (index($0, key ": ") == 1 || $0 == key ":") { next }
    { print }' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file"
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
  local tmp; tmp="$(mktemp "$(dirname "$log")/.log.XXXXXX")" || return 1
  awk -v new="$line" '
    BEGIN { inserted = 0 }
    /^---$/ && !inserted { print; print ""; print new; inserted = 1; next }
    { print }
    END { if (!inserted) { print ""; print new } }
  ' "$log" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$log"
}

_close_remove_from_active_registry() {
  local slug="$1"
  local registry="./.platform/work/ACTIVE.md"
  [[ -f "$registry" ]] || return 0
  local tmp; tmp="$(mktemp "$(dirname "$registry")/.active.XXXXXX")" || return 1
  awk -F '|' -v slug="$slug" '{ key=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", key); if (key != slug) print }' \
    "$registry" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$registry"
}

_close_refresh_brief() {
  local slug="$1" brief="./.platform/work/BRIEF.md" tmp
  [[ -f "$brief" ]] || return 0
  grep -qF "\`work/${slug}.md\`" "$brief" || return 0
  tmp="$(mktemp "$(dirname "$brief")/.brief.XXXXXX")" || return 1
  printf '%s\n' '# Project brief' '' 'No primary stream selected.' \
    'Run `agentboard brief` for active work and `agentboard handoff <slug>` to resume it.' \
    'See `work/ACTIVE.md` for the stream registry.' > "$tmp" || return 1
  mv "$tmp" "$brief"
}
