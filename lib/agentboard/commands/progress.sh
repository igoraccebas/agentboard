cmd_progress() {
  with_state_lock _cmd_progress "$@"
}

_cmd_progress() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "Usage: agentboard progress <stream-slug> [--base <branch>] [--note \"<text>\"] [--dry-run]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local base_override="" note="" dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base)
        [[ -n "${2:-}" ]] || die "progress requires a value after --base"
        base_override="$2"; shift 2 ;;
      --note)
        [[ -n "${2:-}" ]] || die "progress requires a value after --note"
        note="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      *) die "Unknown flag for progress: $1" ;;
    esac
  done

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found. Create the stream first (agentboard new-stream)."

  git rev-parse --git-dir >/dev/null 2>&1 || die "Not inside a git repository. 'agentboard progress' needs git to compute the diff."

  local base_branch
  if [[ -n "$base_override" ]]; then
    base_branch="$base_override"
  else
    base_branch="$(frontmatter_value "$stream_file" "base_branch")"
  fi
  if is_placeholder_value "$base_branch" || [[ -z "$base_branch" ]]; then
    die "No base branch recorded in $stream_file. Pass --base <branch> or set base_branch in the stream frontmatter."
  fi

  local base_ref=""
  if git rev-parse --verify --quiet "$base_branch" >/dev/null; then
    base_ref="$base_branch"
  elif git rev-parse --verify --quiet "origin/$base_branch" >/dev/null; then
    base_ref="origin/$base_branch"
    warn "Local branch '$base_branch' not found; using 'origin/$base_branch'."
  else
    die "Base branch '$base_branch' not found locally or on origin."
  fi

  local head_branch
  head_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'HEAD')"

  local stat_raw stat_block
  stat_raw="$(git diff --stat "$base_ref"...HEAD 2>/dev/null || true)"
  if [[ -z "$(printf '%s' "$stat_raw" | tr -d ' \t\n')" ]]; then
    ok "No changes on $head_branch vs $base_ref — nothing to record."
    return 0
  fi
  stat_block="$(printf '%s\n' "$stat_raw" | sed 's/^/    /')"

  local ts block
  ts="$(date '+%Y-%m-%d %H:%M')"
  block="${ts} — diff ${head_branch} vs ${base_ref}"$'\n'"${stat_block}"
  if [[ -n "$note" ]]; then
    block="${block}"$'\n'"    note: ${note}"
  fi

  if (( dry_run )); then
    printf '%sWould append to %s → ## Progress log:%s\n\n' "$C_BOLD" "$stream_file" "$C_RESET"
    printf '%s\n' "$block"
    return 0
  fi

  grep -q '^## Progress log[[:space:]]*$' "$stream_file" \
    || die "$stream_file has no '## Progress log' section. Is this a v1 stream file?"

  local tmp block_file
  tmp="$(mktemp)"
  block_file="$(mktemp)"
  printf '%s\n' "$block" > "$block_file"

  awk -v block_file="$block_file" '
    BEGIN { in_log = 0; inserted = 0 }
    /^## Progress log[[:space:]]*$/ { in_log = 1; print; next }
    in_log && /^## / && !inserted {
      while ((getline line < block_file) > 0) print line
      close(block_file)
      print ""
      inserted = 1
      in_log = 0
      print
      next
    }
    { print }
    END {
      if (in_log && !inserted) {
        while ((getline line < block_file) > 0) print line
        close(block_file)
      }
    }
  ' "$stream_file" > "$tmp"

  rm -f "$block_file"
  mv "$tmp" "$stream_file"

  local today_str
  today_str="$(today)"
  if has_frontmatter "$stream_file"; then
    replace_frontmatter_line "$stream_file" "updated_at" "$today_str"
  fi

  ok "Appended progress block to $stream_file"
}
