cmd_checkpoint() {
  with_state_lock _cmd_checkpoint "$@"
}

_cmd_checkpoint() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  if [[ -z "$slug" || "${slug:0:2}" == "--" || "$slug" == "-h" ]]; then
    slug=""
  else
    shift
  fi
  if [[ -n "$slug" ]]; then
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."
  fi

  local what="" next_action="" blocker="" focus="" include_diff=0 dry_run=0 auto=0
  local explicit_blocker=0 explicit_focus=0
  local tokens_in="" tokens_out="" provider="" model="" complexity=""
  local cum_in="" cum_out="" session_id="${AGENTBOARD_SESSION_ID:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --what)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --what"
        what="$2"; shift 2 ;;
      --next)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --next"
        next_action="$2"; shift 2 ;;
      --blocker)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --blocker"
        blocker="$2"; explicit_blocker=1; shift 2 ;;
      --focus)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --focus"
        focus="$2"; explicit_focus=1; shift 2 ;;
      --diff) include_diff=1; shift ;;
      --auto) auto=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --tokens-in)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --tokens-in"
        tokens_in="$2"; shift 2 ;;
      --tokens-out)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --tokens-out"
        tokens_out="$2"; shift 2 ;;
      --cumulative-in)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --cumulative-in"
        cum_in="$2"; shift 2 ;;
      --cumulative-out)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --cumulative-out"
        cum_out="$2"; shift 2 ;;
      --provider)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --provider"
        provider="$2"; shift 2 ;;
      --model)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --model"
        model="$2"; shift 2 ;;
      --complexity)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --complexity"
        complexity="$2"; shift 2 ;;
      --session-id)
        [[ -n "${2:-}" ]] || die "checkpoint requires a value after --session-id"
        session_id="$2"; shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage: agentboard checkpoint <stream-slug> --what "..." --next "..." [flags]

Overwrites the stream file's `## Resume state` block so the next agent has
compact, current context. Also prepends a dated entry to `## Progress log`
and trims the log to the last 10 entries.

Required:
  --what "<1-2 lines>"     What just happened in this session.
  --next "<one sentence>"  The single next action for whoever resumes.

Optional:
  --blocker "<text>"       Current blocker. Defaults to "none".
  --focus "<file:line|topic>"  What file/topic is in focus. Defaults to "—".
  --diff                   Also append `git diff --stat` to Progress log.
  --auto                   Unattended mode (for session-end hooks): when the
                           slug is omitted, targets the most recently updated
                           open stream; derives --what from git state and
                           keeps the previous next action. No-op when the
                           tree is clean and nothing was committed today.
  --dry-run                Print what would change; don't write.

Usage tracking (auto-log a token segment when provider + tokens given):
  --tokens-in N            Input tokens consumed THIS segment only (delta).
  --tokens-out N           Output tokens produced THIS segment only (delta).
  --cumulative-in N        Running TOTAL input tokens since session start.
                           CLI computes delta automatically — safe for
                           mid-session logging without double-counting.
  --cumulative-out N       Running TOTAL output tokens since session start.
  --provider <name>        claude | codex | gemini  (or $AGENTBOARD_PROVIDER)
  --session-id <id>        Stable ID for this provider session (or $AGENTBOARD_SESSION_ID).
  --model <name>           model id (or $AGENTBOARD_MODEL)
  --complexity <t>         trivial | normal | heavy  (helps 'learn' detect overkill)

  Use --tokens-in/out OR --cumulative-in/out, not both.

After running, the next agent (Claude/Codex/Gemini) can resume by running
`agentboard handoff <stream-slug>` and reading Resume state first.
EOF
        return 0 ;;
      *) die "Unknown flag for checkpoint: $1" ;;
    esac
  done

  # Env-var fallbacks for provider/model so agents can set them once per shell
  [[ -z "$provider" ]] && provider="${AGENTBOARD_PROVIDER:-}"
  [[ -z "$model" ]] && model="${AGENTBOARD_MODEL:-}"

  if (( auto )); then
    if [[ -z "$slug" ]]; then
      slug="$(_checkpoint_detect_stream)" || {
        say "${C_DIM}auto-checkpoint: no active stream — nothing to do.${C_RESET}"
        return 0
      }
    fi
    _checkpoint_fill_auto_fields "$slug" || return 0
  fi

  if [[ -z "$slug" ]]; then
    die "Usage: agentboard checkpoint <stream-slug> --what \"...\" --next \"...\" [--blocker \"...\"] [--focus \"...\"] [--diff] [--auto] [--dry-run]"
  fi
  [[ -n "$what" ]] || die "checkpoint requires --what \"<1-2 lines>\""
  [[ -n "$next_action" ]] || die "checkpoint requires --next \"<one sentence>\""

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found. Create the stream first (agentboard new-stream)."
  has_frontmatter "$stream_file" || die "$stream_file has no v1 frontmatter. Run 'agentboard migrate --apply' first."

  local today_str ts agent
  today_str="$(today)"
  ts="$(date '+%Y-%m-%d %H:%M')"
  agent="${AGENTBOARD_AGENT:-${USER:-agent}}"

  (( explicit_blocker )) || blocker="none"
  (( explicit_focus )) || focus="—"

  # Sanitize single-line fields: no newlines, no pipe tricks
  what="${what//$'\n'/ }"
  next_action="${next_action//$'\n'/ }"
  blocker="${blocker//$'\n'/ }"
  focus="${focus//$'\n'/ }"

  # Build new Resume state block
  local resume_block
  resume_block="$(cat <<EOF
## Resume state
_Overwritten by \`agentboard checkpoint\` — the compact payload the next agent reads first. Keep this block under ~10 lines._

- **Last updated:** ${today_str} by ${agent}
- **What just happened:** ${what}
- **Current focus:** ${focus}
- **Next action:** ${next_action}
- **Blockers:** ${blocker}
EOF
  )"

  # Build new Progress log entry
  local log_entry
  log_entry="${ts} — ${what}"
  if (( include_diff )); then
    if git rev-parse --git-dir >/dev/null 2>&1; then
      local base_branch base_ref head_branch stat_raw
      base_branch="$(frontmatter_value "$stream_file" "base_branch")"
      if ! is_placeholder_value "$base_branch" && [[ -n "$base_branch" ]]; then
        if git rev-parse --verify --quiet "$base_branch" >/dev/null; then
          base_ref="$base_branch"
        elif git rev-parse --verify --quiet "origin/$base_branch" >/dev/null; then
          base_ref="origin/$base_branch"
        fi
        if [[ -n "$base_ref" ]]; then
          head_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'HEAD')"
          stat_raw="$(git diff --stat "$base_ref"...HEAD 2>/dev/null || true)"
          if [[ -n "$(printf '%s' "$stat_raw" | tr -d ' \t\n')" ]]; then
            log_entry="${log_entry}"$'\n'"    diff ${head_branch} vs ${base_ref}:"$'\n'"$(printf '%s\n' "$stat_raw" | sed 's/^/      /')"
          fi
        fi
      fi
    fi
  fi

  if (( dry_run )); then
    printf '%sWould update %s%s\n\n' "$C_BOLD" "$stream_file" "$C_RESET"
    printf '%sResume state:%s\n' "$C_BOLD" "$C_RESET"
    printf '%s\n\n' "$resume_block"
    printf '%sProgress log entry (prepended, kept latest 10):%s\n' "$C_BOLD" "$C_RESET"
    printf '%s\n' "$log_entry"
    return 0
  fi

  _checkpoint_commit() {
    local staged
    staged="$(mktemp "$(dirname "$stream_file")/.checkpoint.XXXXXX")" || return 1
    cp -p "$stream_file" "$staged" &&
      _checkpoint_write_resume_state "$staged" "$resume_block" &&
      _checkpoint_prepend_progress_entry "$staged" "$log_entry" &&
      replace_frontmatter_line "$staged" "updated_at" "$today_str" &&
      mv "$staged" "$stream_file" || { rm -f "$staged"; return 1; }
  }
  _checkpoint_commit || return 1

  ok "Checkpoint saved to $stream_file"
  say "  ${C_DIM}next:${C_RESET} ${next_action}"
  say "  ${C_DIM}Ready for handoff — run: agentboard handoff ${slug}${C_RESET}"

  _checkpoint_auto_log_usage "$slug" "$tokens_in" "$tokens_out" "$cum_in" "$cum_out" "$provider" "$model" "$complexity" "$what"
}

# Pick the stream an unattended checkpoint should target: the not-closed
# stream with the newest updated_at. Returns 1 when no stream qualifies.
_checkpoint_detect_stream() {
  local file status updated best_file="" best_date=""
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    has_frontmatter "$file" || continue
    status="$(frontmatter_value "$file" "status")"
    case "$status" in done|archived|closed) continue ;; esac
    updated="$(frontmatter_value "$file" "updated_at")"
    [[ -n "$updated" ]] || updated="0000-00-00"
    if [[ -z "$best_file" || "$updated" > "$best_date" ]]; then
      best_file="$file"
      best_date="$updated"
    fi
  done < <(stream_files)
  [[ -n "$best_file" ]] || return 1
  basename "$best_file" .md
}

# Derive --what/--next for an unattended checkpoint from git state. Sets the
# caller's what/next_action (bash dynamic scope). Returns 1 when there is
# nothing worth recording — callers (hooks) treat that as a clean no-op.
_checkpoint_fill_auto_fields() {
  local slug="$1" stream_file="./.platform/work/${slug}.md"
  local dirty=0 commits_today=0 branch="" last_subject=""

  if git rev-parse --git-dir >/dev/null 2>&1; then
    dirty="$(git status --porcelain 2>/dev/null | grep -c . || true)"
    commits_today="$(git log --since=midnight --oneline 2>/dev/null | grep -c . || true)"
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    last_subject="$(git log -1 --format=%s 2>/dev/null || true)"
  fi

  if (( dirty == 0 && commits_today == 0 )); then
    say "${C_DIM}auto-checkpoint: working tree clean, no commits today — nothing to record.${C_RESET}"
    return 1
  fi

  if [[ -z "$what" ]]; then
    what="auto-checkpoint (${branch}): ${dirty} uncommitted file(s), ${commits_today} commit(s) today"
    [[ -n "$last_subject" ]] && what="${what}; last commit: ${last_subject}"
  fi
  if [[ -z "$next_action" ]]; then
    next_action="$([[ -f "$stream_file" ]] && stream_next_action "$stream_file" || true)"
    [[ -n "$next_action" ]] || next_action="review auto-checkpoint and set the real next action"
  fi
  return 0
}

# Auto-log a usage segment when token counts + provider are provided.
# Silently skips if any required field is missing — usage tracking stays optional.
# Supports two modes: delta (--tokens-in/out) or cumulative (--cumulative-in/out
# — CLI computes the delta).
_checkpoint_auto_log_usage() {
  local slug="$1" tokens_in="$2" tokens_out="$3" cum_in="$4" cum_out="$5"
  local provider="$6" model="$7" complexity="$8" what="$9"
  [[ -n "$provider" ]] || return 0

  local mode=""
  if [[ -n "$cum_in" || -n "$cum_out" ]]; then
    [[ -n "$cum_in" && -n "$cum_out" ]] || {
      warn "Checkpoint: --cumulative-in and --cumulative-out must be passed together; skipping usage log"
      return 0
    }
    [[ "$cum_in" =~ ^[0-9]+$ && "$cum_out" =~ ^[0-9]+$ ]] || {
      warn "Checkpoint: --cumulative-in/--cumulative-out must be non-negative integers; skipping usage log"
      return 0
    }
    if [[ -n "$tokens_in" || -n "$tokens_out" ]]; then
      warn "Checkpoint: use --tokens-in/out OR --cumulative-in/out, not both; skipping usage log"
      return 0
    fi
    mode="cumulative"
  elif [[ -n "$tokens_in" && -n "$tokens_out" ]]; then
    [[ "$tokens_in" =~ ^[0-9]+$ && "$tokens_out" =~ ^[0-9]+$ ]] || {
      warn "Checkpoint: --tokens-in/--tokens-out must be integers; skipping usage log"
      return 0
    }
    mode="delta"
  else
    return 0
  fi

  command -v cmd_usage >/dev/null 2>&1 || return 0

  local -a usage_args=(
    log
    --provider "$provider"
    --stream "$slug"
  )
  if [[ "$mode" == "cumulative" ]]; then
    usage_args+=(--cumulative-in "$cum_in" --cumulative-out "$cum_out")
  else
    usage_args+=(--input "$tokens_in" --output "$tokens_out")
  fi
  [[ -n "$model" ]] && usage_args+=(--model "$model")
  [[ -n "$complexity" ]] && usage_args+=(--type "$complexity")
  [[ -n "${session_id:-}" ]] && usage_args+=(--session-id "$session_id")
  local note="checkpoint: ${what:0:80}"
  usage_args+=(--note "$note")

  if cmd_usage "${usage_args[@]}" >/dev/null; then
    if [[ "$mode" == "cumulative" ]]; then
      say "  ${C_DIM}usage logged: ${provider}${model:+/$model} — cumulative ${cum_in} in / ${cum_out} out (delta auto-computed)${C_RESET}"
    else
      say "  ${C_DIM}usage logged: ${provider}${model:+/$model} — ${tokens_in} in / ${tokens_out} out${C_RESET}"
    fi
  else
    warn "Checkpoint saved, but usage logging failed. Retry the usage log separately."
    return 0
  fi
}

# Overwrite or insert the ## Resume state section. If the section exists, it's
# replaced in place (preserving everything before and after). If it's missing,
# insert before ## Progress log, or before ## Next action, or append.
_checkpoint_write_resume_state() {
  local file="$1" new_block="$2"
  local tmp block_file
  tmp="$(mktemp)" || return 1
  block_file="$(mktemp)" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$new_block" > "$block_file" || { rm -f "$tmp" "$block_file"; return 1; }

  if grep -q '^## Resume state[[:space:]]*$' "$file"; then
    awk -v block_file="$block_file" '
      BEGIN { in_section = 0; printed = 0 }
      /^## Resume state[[:space:]]*$/ {
        if (!printed) {
          while ((read_status = (getline line < block_file)) > 0) print line
          if (read_status < 0) exit 1
          close(block_file)
          printed = 1
        }
        in_section = 1
        next
      }
      in_section && /^## / { in_section = 0; print ""; print; next }
      in_section { next }
      { print }
    ' "$file" > "$tmp" || return 1
  elif grep -q '^## Progress log[[:space:]]*$' "$file"; then
    awk -v block_file="$block_file" '
      BEGIN { inserted = 0 }
      /^## Progress log[[:space:]]*$/ && !inserted {
        while ((read_status = (getline line < block_file)) > 0) print line
        if (read_status < 0) exit 1
        close(block_file)
        print ""
        inserted = 1
      }
      { print }
    ' "$file" > "$tmp" || return 1
  elif grep -q '^## Next action[[:space:]]*$' "$file"; then
    awk -v block_file="$block_file" '
      BEGIN { inserted = 0 }
      /^## Next action[[:space:]]*$/ && !inserted {
        while ((read_status = (getline line < block_file)) > 0) print line
        if (read_status < 0) exit 1
        close(block_file)
        print ""
        inserted = 1
      }
      { print }
    ' "$file" > "$tmp" || return 1
  else
    cat "$file" > "$tmp" || return 1
    printf '\n' >> "$tmp" || return 1
    cat "$block_file" >> "$tmp" || return 1
    printf '\n' >> "$tmp" || return 1
  fi

  rm -f "$block_file"
  mv "$tmp" "$file"
}

# Prepend a dated entry to ## Progress log (creating the section if absent),
# then keep only the 10 most-recent entries. Entries are delimited by leading
# date lines (YYYY-MM-DD ...) at column 0.
_checkpoint_prepend_progress_entry() {
  local file="$1" entry="$2"
  local tmp entry_file
  tmp="$(mktemp)" || return 1
  entry_file="$(mktemp)" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$entry" > "$entry_file" || { rm -f "$tmp" "$entry_file"; return 1; }

  if ! grep -q '^## Progress log[[:space:]]*$' "$file"; then
    {
      cat "$file" &&
      printf '\n## Progress log\n_Append-only. Auto-trimmed by `agentboard checkpoint` to last 10 entries._\n\n' &&
      cat "$entry_file" &&
      printf '\n'
    } > "$tmp" || return 1
    rm -f "$entry_file"
    mv "$tmp" "$file"
    return $?
  fi

  awk -v entry_file="$entry_file" '
    BEGIN { in_log = 0; inserted = 0; count = 0 }
    /^## Progress log[[:space:]]*$/ {
      print
      in_log = 1
      next
    }
    in_log && !inserted && (/^_.*_[[:space:]]*$/ || /^[[:space:]]*$/) {
      print
      next
    }
    in_log && !inserted {
      # Insert the new entry before existing log lines. The entry starts with
      # a YYYY-MM-DD date line so it counts as entry 1 for the 10-entry cap.
      while ((read_status = (getline line < entry_file)) > 0) print line
      if (read_status < 0) { failed = 1; exit 1 }
      close(entry_file)
      print ""
      inserted = 1
      count = 1
      # fall through to process current line
    }
    in_log && /^## / {
      in_log = 0
    }
    in_log {
      # Count entry headers (YYYY-MM-DD ... at column 0, non-indented)
      if ($0 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
        count++
        if (count > 10) { skipping = 1 }
        else            { skipping = 0 }
      }
      if (skipping) next
    }
    { print }
    END {
      if (failed) exit 1
      if (in_log && !inserted) {
        while ((read_status = (getline line < entry_file)) > 0) print line
        if (read_status < 0) exit 1
        close(entry_file)
      }
    }
  ' "$file" > "$tmp" || return 1

  rm -f "$entry_file"
  mv "$tmp" "$file"
}
