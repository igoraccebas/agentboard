cmd_brief() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local show_all=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) show_all=1; shift ;;
      -h|--help)
        cat <<'EOF'
Usage: agentboard brief [--all]

Prints a compact project-state view for a fresh agent. Two screens max:
  - Active streams + next actions
  - Recent gotchas (🔴 never-forget first, then top 🟡)
  - Active open questions
  - Latest usage pattern finding (if any)

Read this first at session start — it's the "20-year employee" briefing.

Flags:
  --all  Show all gotchas/questions (no truncation)
EOF
        return 0 ;;
      *) die "Unknown flag for brief: $1" ;;
    esac
  done

  local project_name="" today_str
  today_str="$(today)"
  if [[ -f "./.platform/STATUS.md" ]]; then
    project_name="$(awk 'NR==1 { sub(/^# */, ""); print; exit }' "./.platform/STATUS.md")"
  fi
  [[ -n "$project_name" ]] || project_name="$(basename "$(pwd)")"

  printf '%s%s Project brief — %s%s\n' "$C_BOLD" "$C_CYAN" "$project_name" "$C_RESET"
  printf '%s   as of %s%s\n\n' "$C_DIM" "$today_str" "$C_RESET"

  _brief_active_streams
  _brief_gotchas "$show_all"
  _brief_facts "$show_all"
  _brief_open_questions "$show_all"
  _brief_usage_insight
}

# Facts scoped to today's work: red gotchas always; everything else only when
# its domains intersect an open stream's domains. The full list stays in
# INDEX.md — brief is the always-loaded surface, so it stays cheap.
_brief_facts() {
  local show_all="$1" limit=7
  (( show_all )) && limit=99999
  [[ -d "./.platform/memory/facts" ]] || return 0

  local relevant rows
  relevant="$(active_stream_domains)"
  rows="$(facts_relevant_to_domains "$relevant")"
  [[ -n "$rows" ]] || return 0

  printf '%s📌 Facts in scope%s %s(full list: .platform/memory/INDEX.md)%s\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  local printed=0 total=0 fid ftype ftitle fdomains fsev fstatus fexpires ffile
  while IFS='|' read -r fid ftype ftitle fdomains fsev fstatus fexpires ffile; do
    [[ -n "$fid" ]] || continue
    total=$((total + 1))
    (( printed < limit )) || continue
    printf '   %s %s [%s] %s\n' "$fid" "$(_fact_severity_emoji "$fsev")" "$ftype" "$ftitle"
    printed=$((printed + 1))
  done <<< "$rows"
  if (( printed < total )); then
    printf '%s   ... %d more — `agentboard brief --all` or INDEX.md%s\n' \
      "$C_DIM" $(( total - printed )) "$C_RESET"
  fi
  printf '\n'
}

_brief_active_streams() {
  local file count=0
  local -a rows=()
  while IFS= read -r file; do
    local status slug agent next
    status="$(frontmatter_value "$file" "status")"
    case "$status" in done|archived|closed) continue ;; esac
    slug="$(frontmatter_value "$file" "slug")"
    agent="$(frontmatter_value "$file" "agent_owner")"
    next="$(stream_next_action "$file")"
    [[ -z "$next" ]] && next="—"
    local gate=""
    if grep -q '^## Execution brief' "$file" && \
       [[ "$(frontmatter_value "$file" "brief_approved")" != "true" ]]; then
      gate="  ${C_RED}⛔ brief awaiting approval${C_RESET}"
    fi
    rows+=("$(printf '   %s%s%s  (%s, %s)  → %s%s' \
      "$C_BOLD" "$slug" "$C_RESET" "${status:-?}" "${agent:-?}" "$next" "$gate")")
    count=$((count + 1))
  done < <(stream_files)

  printf '%s🔥 Active streams (%d)%s\n' "$C_BOLD" "$count" "$C_RESET"
  if (( count == 0 )); then
    printf '%s   (none — run `agentboard new-stream` to start)%s\n\n' "$C_DIM" "$C_RESET"
    return 0
  fi
  if (( ${#rows[@]} > 0 )); then
    local row
    for row in "${rows[@]}"; do printf '%s\n' "$row"; done
  fi
  printf '\n'
}

_brief_gotchas() {
  local show_all="$1" file="./.platform/memory/gotchas.md" limit=5
  (( show_all )) && limit=99999

  # Legacy surface: only projects that haven't run migrate-memory still have
  # this file. New projects record gotchas as facts (shown in Facts in scope).
  [[ -f "$file" ]] || return 0
  printf '%s⚠️  Gotchas (legacy gotchas.md — run `agentboard migrate-memory`)%s\n' "$C_BOLD" "$C_RESET"

  local -a red=() yellow=() green=()
  local line
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*\<!-- ]] && continue
    case "$line" in
      *🔴*) red+=("$line") ;;
      *🟡*) yellow+=("$line") ;;
      *🟢*) green+=("$line") ;;
    esac
  done < <(_extract_between_markers "$file" "agentboard:gotchas:begin" "agentboard:gotchas:end")

  local total=$(( ${#red[@]} + ${#yellow[@]} + ${#green[@]} ))
  if (( total == 0 )); then
    printf '%s   (none yet — gotchas accumulate as streams close via `agentboard close`)%s\n\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  local printed=0 item
  if (( ${#red[@]} > 0 )); then
    for item in "${red[@]}"; do
      (( printed < limit )) || break
      printf '   %s\n' "$item"
      printed=$((printed + 1))
    done
  fi
  if (( ${#yellow[@]} > 0 )); then
    for item in "${yellow[@]}"; do
      (( printed < limit )) || break
      printf '   %s\n' "$item"
      printed=$((printed + 1))
    done
  fi
  if (( printed < total )); then
    printf '%s   ... %d more — `agentboard brief --all` to see them%s\n' \
      "$C_DIM" $(( total - printed )) "$C_RESET"
  fi
  printf '\n'
}

_brief_open_questions() {
  local show_all="$1" file="./.platform/memory/open-questions.md" limit=3
  (( show_all )) && limit=99999

  # Legacy surface — question facts cover this for migrated/new projects.
  [[ -f "$file" ]] || return 0
  printf '%s❓ Open questions (legacy open-questions.md)%s\n' "$C_BOLD" "$C_RESET"

  local -a questions=()
  local line
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*\<!-- ]] && continue
    questions+=("$line")
  done < <(_extract_between_markers "$file" "agentboard:open-questions:active:begin" "agentboard:open-questions:active:end")

  if (( ${#questions[@]} == 0 )); then
    printf '%s   (none active)%s\n\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  local printed=0 item
  if (( ${#questions[@]} > 0 )); then
    for item in "${questions[@]}"; do
      (( printed < limit )) || break
      printf '   %s\n' "$item"
      printed=$((printed + 1))
    done
  fi
  if (( printed < ${#questions[@]} )); then
    printf '%s   ... %d more%s\n' "$C_DIM" $(( ${#questions[@]} - printed )) "$C_RESET"
  fi
  printf '\n'
}

_brief_usage_insight() {
  local db="${AGENTBOARD_USAGE_DB:-$HOME/.agentboard/usage.db}"
  printf '%s💡 Usage pattern%s\n' "$C_BOLD" "$C_RESET"
  if ! command -v sqlite3 >/dev/null 2>&1 || [[ ! -f "$db" ]]; then
    printf '%s   (no usage data yet — run `agentboard usage learn` once data accumulates)%s\n\n' \
      "$C_DIM" "$C_RESET"
    return 0
  fi
  local count
  count="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage;" 2>/dev/null || echo 0)"
  if [[ -z "$count" || "$count" -lt 5 ]]; then
    printf '%s   (only %s segments logged — need ~5+ for pattern detection)%s\n\n' \
      "$C_DIM" "${count:-0}" "$C_RESET"
    return 0
  fi
  local top_model top_type
  top_model="$(sqlite3 "$db" \
    "SELECT model FROM usage WHERE model != '' GROUP BY model ORDER BY SUM(total_tokens) DESC LIMIT 1;" \
    2>/dev/null || true)"
  top_type="$(sqlite3 "$db" \
    "SELECT type FROM usage WHERE type != '' GROUP BY type ORDER BY COUNT(*) DESC LIMIT 1;" \
    2>/dev/null || true)"
  if [[ -n "$top_model" && -n "$top_type" ]]; then
    printf '   Most tokens spent: %s%s%s on %s%s%s tasks (run `agentboard usage learn` for details)\n\n' \
      "$C_BOLD" "$top_model" "$C_RESET" "$C_BOLD" "$top_type" "$C_RESET"
  else
    printf '%s   (data present — run `agentboard usage learn` for findings)%s\n\n' \
      "$C_DIM" "$C_RESET"
  fi
}

_extract_between_markers() {
  local file="$1" begin_marker="$2" end_marker="$3"
  awk -v b="$begin_marker" -v e="$end_marker" '
    index($0, b) > 0 { in_block = 1; next }
    index($0, e) > 0 { in_block = 0; next }
    in_block { print }
  ' "$file"
}
