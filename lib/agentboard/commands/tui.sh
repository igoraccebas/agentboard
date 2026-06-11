# tui.sh — read-only terminal dashboard for the stream registry
#
# Renders .platform/work/*.md stream files as a colored table. Strictly
# read-only: no stream file, registry, or frontmatter is ever written.

cmd_tui() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local status_filter="" owner_filter="" interval=5 once=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status)
        [[ -n "${2:-}" ]] || die "tui requires a value after --status"
        status_filter="$2"; shift 2 ;;
      --owner)
        [[ -n "${2:-}" ]] || die "tui requires a value after --owner"
        owner_filter="$2"; shift 2 ;;
      --interval)
        [[ -n "${2:-}" ]] || die "tui requires a value after --interval"
        [[ "$2" =~ ^[0-9]+$ ]] || die "Invalid --interval: $2 (seconds, integer)"
        interval="$2"; shift 2 ;;
      --once) once=1; shift ;;
      -h|--help) _tui_print_help; return 0 ;;
      *) die "Unknown flag for tui: $1" ;;
    esac
  done

  if (( once )); then
    _tui_render "$status_filter" "$owner_filter"
    return 0
  fi

  trap 'printf "\n"; exit 0' INT TERM
  while true; do
    clear
    _tui_render "$status_filter" "$owner_filter"
    printf '%srefreshing every %ss — Ctrl-C to exit%s\n' "$C_DIM" "$interval" "$C_RESET"
    sleep "$interval"
  done
}

_tui_print_help() {
  cat <<'EOF'
Usage: agentboard tui [--status <s>] [--owner <name>] [--interval N] [--once]

Read-only terminal dashboard of the stream registry: one row per stream
file in .platform/work/ (stream | type | status | owner | updated | branch).

Flags:
  --status <s>    Show only streams with this status (case-insensitive).
  --owner <name>  Show only streams owned by this agent (case-insensitive).
  --interval N    Refresh every N seconds (default 5).
  --once          Render once and exit (no loop, no clear).

Colors: in-progress green · planning/blocked yellow · done/closed dim.
Strictly read-only — tui never writes to .platform/.
EOF
}

_tui_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

_tui_status_color() {
  case "$(_tui_lower "$1")" in
    in-progress|active)        printf '%s' "$C_GREEN" ;;
    planning|blocked|paused)   printf '%s' "$C_YELLOW" ;;
    done|closed|archived)      printf '%s' "$C_DIM" ;;
    *)                         printf '%s' "$C_RESET" ;;
  esac
}

# _tui_cell <value> <width> — fixed-width cell, truncated with no deps
_tui_cell() {
  local value="${1:-—}" width="$2"
  [[ -z "$value" ]] && value="—"
  printf '%-*.*s' "$width" "$width" "$value"
}

_tui_render() {
  local status_filter="$1" owner_filter="$2"
  local file slug type status owner updated branch
  local count=0 shown=0
  local -a rows=()

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    has_frontmatter "$file" || continue
    count=$((count + 1))
    slug="$(frontmatter_value "$file" "slug")"
    [[ -n "$slug" ]] || slug="$(basename "$file" .md)"
    type="$(frontmatter_value "$file" "type")"
    status="$(frontmatter_value "$file" "status")"
    owner="$(frontmatter_value "$file" "agent_owner")"
    updated="$(frontmatter_value "$file" "updated_at")"
    branch="$(frontmatter_value "$file" "git_branch")"
    is_placeholder_value "$branch" && branch="—"

    if [[ -n "$status_filter" ]] && \
       [[ "$(_tui_lower "$status")" != "$(_tui_lower "$status_filter")" ]]; then
      continue
    fi
    if [[ -n "$owner_filter" ]] && \
       [[ "$(_tui_lower "$owner")" != "$(_tui_lower "$owner_filter")" ]]; then
      continue
    fi

    rows+=("$(printf '  %s  %s  %s%s%s  %s  %s  %s' \
      "$(_tui_cell "$slug" 24)" \
      "$(_tui_cell "$type" 8)" \
      "$(_tui_status_color "$status")" "$(_tui_cell "$status" 12)" "$C_RESET" \
      "$(_tui_cell "$owner" 12)" \
      "$(_tui_cell "$updated" 10)" \
      "$(_tui_cell "$branch" 28)")")
    shown=$((shown + 1))
  done < <(stream_files)

  printf '%s%sagentboard tui%s %s%s%s\n\n' \
    "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" "$(today)" "$C_RESET"
  printf '%s  %s  %s  %s  %s  %s  %s%s\n' "$C_BOLD" \
    "$(_tui_cell "stream" 24)" \
    "$(_tui_cell "type" 8)" \
    "$(_tui_cell "status" 12)" \
    "$(_tui_cell "owner" 12)" \
    "$(_tui_cell "updated" 10)" \
    "$(_tui_cell "branch" 28)" "$C_RESET"

  if (( shown == 0 )); then
    if (( count == 0 )); then
      printf '%s  (no streams — run `agentboard new-stream` to start)%s\n' "$C_DIM" "$C_RESET"
    else
      printf '%s  (no streams match the filter — %d total)%s\n' "$C_DIM" "$count" "$C_RESET"
    fi
  else
    local row
    for row in "${rows[@]}"; do printf '%s\n' "$row"; done
  fi
  printf '\n%s  %d shown / %d stream(s)%s\n' "$C_DIM" "$shown" "$count" "$C_RESET"
}
