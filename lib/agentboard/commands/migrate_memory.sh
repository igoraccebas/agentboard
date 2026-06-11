# migrate_memory.sh — convert legacy category memory files into facts
#
# Pre-facts projects accumulated memory in four append-files (gotchas.md,
# playbook.md, open-questions.md, learnings.md) that merge-conflict between
# parallel sessions and load all-or-nothing. This converts each entry into a
# fact file and parks the originals under memory/legacy/ — nothing is deleted.
# decisions.md is NOT migrated: it's a curated registry with supersede
# semantics (seeded during activation), not an append pile.

cmd_migrate_memory() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local apply=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1; shift ;;
      -h|--help) _migrate_memory_print_help; return 0 ;;
      *) die "Unknown flag for migrate-memory: $1" ;;
    esac
  done

  local mem="./.platform/memory" converted=0 skipped=0 found_any=0

  printf '\n%s%sagentboard migrate-memory%s %s(%s)%s\n\n' \
    "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" \
    "$( (( apply )) && echo 'applying' || echo 'dry run — pass --apply to write' )" "$C_RESET"

  if [[ -f "$mem/gotchas.md" ]]; then
    found_any=1
    _mm_convert_lines "$mem/gotchas.md" gotcha \
      "agentboard:gotchas:begin" "agentboard:gotchas:end" "$apply"
  fi
  if [[ -f "$mem/playbook.md" ]]; then
    found_any=1
    _mm_convert_lines "$mem/playbook.md" playbook \
      "agentboard:playbook:begin" "agentboard:playbook:end" "$apply"
  fi
  if [[ -f "$mem/open-questions.md" ]]; then
    found_any=1
    _mm_convert_lines "$mem/open-questions.md" question \
      "agentboard:open-questions:active:begin" "agentboard:open-questions:active:end" "$apply"
  fi
  if [[ -f "$mem/learnings.md" ]]; then
    found_any=1
    _mm_convert_learnings "$mem/learnings.md" "$apply"
  fi

  if (( ! found_any )); then
    ok "No legacy memory files present — nothing to migrate."
    return 0
  fi

  say
  if (( apply )); then
    ok "Converted ${converted} entr(ies) into facts; ${skipped} already covered."
    say "  ${C_DIM}Originals parked in .platform/memory/legacy/ — nothing deleted.${C_RESET}"
    say "  ${C_DIM}From now on: agentboard fact new / agentboard brief reads facts.${C_RESET}"
  else
    say "  ${C_DIM}${converted} entr(ies) would convert; ${skipped} already covered. Run with --apply.${C_RESET}"
  fi
}

_migrate_memory_print_help() {
  cat <<'EOF'
Usage: agentboard migrate-memory [--apply]

Converts legacy category memory files into one-fact-per-file storage:

  memory/gotchas.md         → gotcha facts   (severity from 🔴/🟡/🟢)
  memory/playbook.md        → playbook facts
  memory/open-questions.md  → question facts (active section only)
  memory/learnings.md       → learning facts (one per L-NNN block)

Not migrated: memory/decisions.md (curated registry — stays canonical),
memory/log.md and memory/BACKLOG.md (event log / backlog, not facts).

After --apply, each converted source file moves to .platform/memory/legacy/
so it can't silently collect new entries. Conversion is idempotent: entries
whose text already matches an existing fact are skipped, so a re-run after
a partial migration is safe.

Default is a dry run. Pass --apply to write.
EOF
}

# Convert one-line-per-entry files (gotchas, playbook, open questions).
# Increments caller's converted/skipped (bash dynamic scope).
_mm_convert_lines() {
  local file="$1" type="$2" begin="$3" end="$4" apply="$5"
  local line title severity domain file_converted=0

  printf '%s%s%s\n' "$C_BOLD" "$file" "$C_RESET"
  while IFS= read -r line; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    [[ "$line" == \<!--* ]] && continue
    title="$line"
    severity=""
    if [[ "$type" == "gotcha" ]]; then
      case "$line" in
        *🔴*) severity="red" ;;
        *🟡*) severity="yellow" ;;
        *🟢*) severity="green" ;;
        *)    severity="yellow" ;;
      esac
      title="$(printf '%s' "$title" | sed 's/[🔴🟡🟢]//g')"
    fi
    # Strip leading bullet/date noise so the fact title reads clean
    title="$(trim "$(printf '%s' "$title" | sed -E 's/^- //; s/^[0-9]{4}-[0-9]{2}-[0-9]{2} *[—-] *//')")"
    [[ -z "$title" ]] && continue

    if _harvest_already_known "$(printf '%s' "$title" | cut -c1-60)"; then
      skipped=$((skipped + 1))
      printf '  %s↷%s %s %s(already a fact)%s\n' "$C_YELLOW" "$C_RESET" "${title:0:70}" "$C_DIM" "$C_RESET"
      continue
    fi

    domain="$(_mm_guess_domain "$title")"
    if (( apply )); then
      local -a args=(--type "$type" --title "$title" --quiet
                     --body "$title"$'\n\n'"_Migrated from $(basename "$file") on $(today)._")
      [[ -n "$severity" ]] && args+=(--severity "$severity")
      [[ -n "$domain" ]] && args+=(--domain "$domain")
      _fact_new "${args[@]}" >/dev/null
      printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "${title:0:70}"
    else
      printf '  %s+%s %s%s\n' "$C_CYAN" "$C_RESET" "${title:0:70}" \
        "${domain:+ ${C_DIM}[$domain]$C_RESET}"
    fi
    converted=$((converted + 1))
    file_converted=$((file_converted + 1))
  done < <(_extract_between_markers "$file" "$begin" "$end")

  (( file_converted == 0 )) && printf '  %s(no entries)%s\n' "$C_DIM" "$C_RESET"
  (( apply )) && _mm_park_legacy "$file"
  return 0
}

# Convert learnings.md L-NNN blocks into learning facts with full bodies.
_mm_convert_learnings() {
  local file="$1" apply="$2"
  local block="" title="" file_converted=0

  printf '%s%s%s\n' "$C_BOLD" "$file" "$C_RESET"

  _mm_flush_learning() {
    [[ -n "$title" ]] || return 0
    if _harvest_already_known "$(printf '%s' "$title" | cut -c1-60)"; then
      skipped=$((skipped + 1))
      printf '  %s↷%s %s %s(already a fact)%s\n' "$C_YELLOW" "$C_RESET" "${title:0:70}" "$C_DIM" "$C_RESET"
    else
      if (( apply )); then
        _fact_new --type learning --title "$title" --quiet \
          --body "${block}"$'\n\n'"_Migrated from learnings.md on $(today)._" >/dev/null
        printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "${title:0:70}"
      else
        printf '  %s+%s %s\n' "$C_CYAN" "$C_RESET" "${title:0:70}"
      fi
      converted=$((converted + 1))
      file_converted=$((file_converted + 1))
    fi
    title=""
    block=""
  }

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^##[[:space:]]+L-[0-9]+ ]]; then
      _mm_flush_learning
      title="$(trim "$(printf '%s' "$line" | sed -E 's/^## *L-[0-9]+ *[—-]* *//')")"
      [[ -z "$title" ]] && title="$(trim "${line#\#\#}")"
      block=""
    elif [[ -n "$title" ]]; then
      [[ "$line" == "---"* ]] && { _mm_flush_learning; continue; }
      block="${block}${block:+$'\n'}${line}"
    fi
  done < "$file"
  _mm_flush_learning

  (( file_converted == 0 )) && printf '  %s(no entries)%s\n' "$C_DIM" "$C_RESET"
  (( apply )) && _mm_park_legacy "$file"
  return 0
}

# Guess a domain tag: first [token] in the title that matches a domain file.
_mm_guess_domain() {
  local title="$1" token
  token="$(printf '%s' "$title" | sed -nE 's/^\[([a-z0-9-]+)([/.][^]]*)?\].*/\1/p')"
  [[ -n "$token" && -f "./.platform/domains/${token}.md" ]] && printf '%s' "$token"
  return 0
}

# Park a migrated source file under memory/legacy/ so it stops collecting
# new entries. Content preserved verbatim.
_mm_park_legacy() {
  local file="$1" legacy_dir="./.platform/memory/legacy"
  mkdir -p "$legacy_dir"
  mv "$file" "$legacy_dir/$(basename "$file")"
  printf '  %s→%s parked at %s/%s\n' "$C_DIM" "$C_RESET" "$legacy_dir" "$(basename "$file")"
}
