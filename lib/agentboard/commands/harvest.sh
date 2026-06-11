# harvest.sh — promote Claude Code's machine-local auto-memory into shared facts
#
# Claude Code writes per-project notes to ~/.claude/projects/<munged-cwd>/memory/
# (MEMORY.md index + topic files). Those notes are machine-local and provider-
# local: teammates and other CLIs never see them. `agentboard harvest` lists
# the note lines not yet in .platform/memory/facts/ and, on --accept, writes
# them as shared fact files (committed, cross-provider).
#
# Deliberately opt-in and explicit: private notes can hold machine-specific or
# personal detail. Nothing is written without --accept / --all.

cmd_harvest() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local accept="" take_all=0 dry_run=0 type="learning" stream="—" source_dir=""
  local -a domains=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --accept)  [[ -n "${2:-}" ]] || die "harvest requires a value after --accept";  accept="$2"; shift 2 ;;
      --all)     take_all=1; shift ;;
      --type)    [[ -n "${2:-}" ]] || die "harvest requires a value after --type";    type="$2"; shift 2 ;;
      --domain)  [[ -n "${2:-}" ]] || die "harvest requires a value after --domain";  domains+=("$2"); shift 2 ;;
      --stream)  [[ -n "${2:-}" ]] || die "harvest requires a value after --stream";  stream="$2"; shift 2 ;;
      --source)  [[ -n "${2:-}" ]] || die "harvest requires a value after --source";  source_dir="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help) _harvest_print_help; return 0 ;;
      *) die "Unknown flag for harvest: $1" ;;
    esac
  done
  _fact_valid_type "$type" || die "Invalid fact type: $type"

  [[ -n "$source_dir" ]] || source_dir="$(_harvest_default_source_dir)"
  if [[ ! -d "$source_dir" ]]; then
    say "${C_DIM}  No Claude auto-memory found at:${C_RESET} $source_dir"
    say "${C_DIM}  (Claude Code writes it as you work; check back after a few sessions,${C_RESET}"
    say "${C_DIM}   or pass --source <dir> explicitly.)${C_RESET}"
    return 0
  fi

  local candidates
  candidates="$(_harvest_candidates "$source_dir")"
  if [[ -z "$candidates" ]]; then
    ok "Nothing to harvest — every note in $source_dir is already covered by a fact."
    return 0
  fi

  if [[ -z "$accept" ]] && (( ! take_all )); then
    _harvest_print_candidates "$candidates" "$source_dir"
    return 0
  fi

  local n=0 created=0 src line
  while IFS='|' read -r src line; do
    [[ -n "$line" ]] || continue
    n=$((n + 1))
    if (( ! take_all )); then
      _harvest_index_selected "$n" "$accept" || continue
    fi
    if (( dry_run )); then
      printf '  %swould create fact:%s %s\n' "$C_CYAN" "$C_RESET" "$line"
      created=$((created + 1))
      continue
    fi
    local -a new_args=(--type "$type" --title "$line" --stream "$stream" --quiet
                       --body "$line"$'\n\n'"_Harvested from Claude auto-memory (${src}) on $(today)._")
    local d
    for d in ${domains[@]+"${domains[@]}"}; do new_args+=(--domain "$d"); done
    _fact_new "${new_args[@]}" >/dev/null
    created=$((created + 1))
    ok "Promoted: ${line}"
  done <<< "$candidates"

  if (( dry_run )); then
    say "  ${C_DIM}Dry run — ${created} fact(s) would be created.${C_RESET}"
  elif (( created == 0 )); then
    warn "No candidates matched --accept ${accept}. Run 'agentboard harvest' to see numbering."
  else
    ok "Harvested ${created} note(s) into shared facts. They now travel with the repo."
  fi
}

_harvest_print_help() {
  cat <<'EOF'
Usage: agentboard harvest [--accept <n,m,...> | --all] [flags]

Promotes Claude Code's machine-local auto-memory notes into shared
.platform/memory/facts/ so teammates and other providers inherit them.

Without flags: lists numbered candidate notes (notes not already covered
by an existing fact). Nothing is written.

Flags:
  --accept n,m   Promote only candidates with these numbers (from the list run).
  --all          Promote every candidate.
  --type <t>     Fact type for promoted notes. Default: learning
  --domain <d>   Tag promoted facts with this domain (repeatable).
  --stream <s>   Source stream to record. Default: —
  --source <dir> Override the auto-memory directory (default: Claude Code's
                 ~/.claude/projects/<this-project>/memory/).
  --dry-run      Show what would be created; write nothing.

Numbering note: candidate numbers come from the current list run. Re-check
with a bare `agentboard harvest` before accepting if sessions ran in between.

Privacy: review candidates before accepting — private notes can contain
machine-specific paths or personal context that doesn't belong in the repo.
EOF
}

_harvest_default_source_dir() {
  if [[ -n "${AGENTBOARD_CLAUDE_MEMORY_DIR:-}" ]]; then
    printf '%s\n' "$AGENTBOARD_CLAUDE_MEMORY_DIR"
    return 0
  fi
  local munged candidate lower_munged lower_base
  munged="$(printf '%s' "$PWD" | sed 's|[^A-Za-z0-9]|-|g')"
  if [[ -d "$HOME/.claude/projects/${munged}/memory" ]]; then
    printf '%s\n' "$HOME/.claude/projects/${munged}/memory"
    return 0
  fi
  # macOS paths are case-insensitive but Claude's munged dir name keeps the
  # case it saw — fall back to a case-insensitive scan before giving up.
  lower_munged="$(printf '%s' "$munged" | tr '[:upper:]' '[:lower:]')"
  for candidate in "$HOME/.claude/projects"/*/; do
    [[ -d "$candidate" ]] || continue
    lower_base="$(basename "$candidate" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower_base" == "$lower_munged" && -d "${candidate}memory" ]]; then
      printf '%s\n' "${candidate}memory"
      return 0
    fi
  done
  printf '%s\n' "$HOME/.claude/projects/${munged}/memory"
}

# Emit "source-file|note-line" for every bullet in the auto-memory dir that
# is not already covered by an existing fact (matched on normalized text).
_harvest_candidates() {
  local source_dir="$1" file base line norm
  for file in "$source_dir"/MEMORY.md "$source_dir"/*.md; do
    [[ -f "$file" ]] || continue
    base="$(basename "$file")"
    # MEMORY.md is globbed twice by the pattern above; skip the second pass
    [[ "$base" == "MEMORY.md" && "$file" != "$source_dir/MEMORY.md" ]] && continue
    while IFS= read -r line; do
      line="$(trim "${line#[-*] }")"
      [[ -n "$line" ]] || continue
      # Strip markdown emphasis/links so dedup matching is on plain text
      norm="$(printf '%s' "$line" | sed -E 's/\[\[?([^]|]*)[]|][^]]*\]?/\1/g; s/[*_`]//g')"
      [[ -n "$norm" ]] || continue
      _harvest_already_known "$norm" && continue
      printf '%s|%s\n' "$base" "$norm"
    done < <(grep -E '^[[:space:]]*[-*] ' "$file" 2>/dev/null || true)
  done | unique_nonempty_lines
}

_harvest_already_known() {
  local norm="$1" probe
  # Match on a stable prefix — titles get trimmed when facts are created
  probe="$(printf '%s' "$norm" | cut -c1-60)"
  [[ -d "$FACTS_DIR" ]] || return 1
  grep -riFq -- "$probe" "$FACTS_DIR" 2>/dev/null
}

_harvest_print_candidates() {
  local candidates="$1" source_dir="$2" n=0 src line
  printf '%sClaude auto-memory candidates%s %s(%s)%s\n\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$source_dir" "$C_RESET"
  while IFS='|' read -r src line; do
    [[ -n "$line" ]] || continue
    n=$((n + 1))
    printf '  %2d. %s %s(%s)%s\n' "$n" "$line" "$C_DIM" "$src" "$C_RESET"
  done <<< "$candidates"
  printf '\n'
  say "  ${C_DIM}Promote with: agentboard harvest --accept <n,m> [--type t] [--domain d]${C_RESET}"
  say "  ${C_DIM}Or all of them: agentboard harvest --all — review first; these were private notes.${C_RESET}"
}

_harvest_index_selected() {
  local idx="$1" accept="$2" token
  local -a tokens
  IFS=',' read -r -a tokens <<< "$accept"
  for token in "${tokens[@]}"; do
    token="$(trim "$token")"
    [[ "$token" == "$idx" ]] && return 0
  done
  return 1
}
