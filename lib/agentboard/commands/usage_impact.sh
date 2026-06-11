# usage_impact.sh — `agentboard usage impact`
#
# One question: is agentboard paying for itself in tokens? The honest,
# measurable proxy: cost-per-stream, and cost-per-task-type over time.
# If compounding memory works, the same kind of task should get cheaper
# month over month — the agent re-discovers less. If it doesn't, this
# report is where that shows up. No vanity metrics.

cmd_usage_impact() {
  local db="$1"

  local total_rows
  total_rows="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage;" 2>/dev/null || echo 0)"
  if [[ -z "$total_rows" || "$total_rows" -lt 5 ]]; then
    say "${C_DIM}  Only ${total_rows:-0} usage segment(s) logged — impact needs ~5+ to mean anything.${C_RESET}"
    say "${C_DIM}  Log segments via: agentboard checkpoint <slug> --cumulative-in N --cumulative-out N --provider <p>${C_RESET}"
    return 0
  fi

  printf '\n%s%sagentboard usage impact%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%s  Reading guide: if memory compounds, the same task type gets cheaper over\n' "$C_DIM"
  printf '  months (less re-discovery). Flat or rising = the binder is not earning rent.%s\n\n' "$C_RESET"

  _impact_per_stream "$db"
  _impact_type_trend "$db"

  printf '%s  Caveats: token logs are self-reported at checkpoint time; segments without\n' "$C_DIM"
  printf '  a stream slug are excluded from per-stream costs. This measures correlation,\n'
  printf '  not proof — but a falling trend across months is hard to fake.%s\n\n' "$C_RESET"
}

# Cost per stream: where the tokens actually went, stream by stream.
_impact_per_stream() {
  local db="$1"
  printf '%sTokens per stream%s %s(top 12 by total)%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"

  local rows
  rows="$(sqlite3 -separator '|' "$db" "
    SELECT stream_slug,
           COUNT(*),
           SUM(total_tokens),
           MIN(DATE(timestamp)),
           MAX(DATE(timestamp))
    FROM usage
    WHERE stream_slug IS NOT NULL AND stream_slug != ''
    GROUP BY stream_slug
    ORDER BY SUM(total_tokens) DESC
    LIMIT 12;" 2>/dev/null)"

  if [[ -z "$rows" ]]; then
    say "${C_DIM}   (no segments tagged with a stream yet — pass --stream when logging)${C_RESET}"
    say
    return 0
  fi

  printf '   %-28s %8s %12s   %s\n' "stream" "segments" "tokens" "active period"
  local slug segs tokens first last status_mark
  while IFS='|' read -r slug segs tokens first last; do
    [[ -n "$slug" ]] || continue
    status_mark=""
    if [[ -f "./.platform/work/archive/${slug}.md" ]]; then
      status_mark=" ${C_DIM}(closed)${C_RESET}"
    elif [[ ! -f "./.platform/work/${slug}.md" ]]; then
      status_mark=" ${C_DIM}(no stream file)${C_RESET}"
    fi
    printf '   %-28.28s %8s %12s   %s → %s%b\n' \
      "$slug" "$segs" "$(_impact_ktok "$tokens")" "$first" "$last" "$status_mark"
  done <<< "$rows"
  say
}

# Cost per task type per month: the compounding signal.
_impact_type_trend() {
  local db="$1"
  printf '%sAvg tokens per segment, by task type and month%s %s(last 6 months)%s\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"

  local rows
  rows="$(sqlite3 -separator '|' "$db" "
    SELECT strftime('%Y-%m', timestamp),
           COALESCE(NULLIF(task_type, ''), 'untyped'),
           COUNT(*),
           CAST(AVG(total_tokens) AS INTEGER)
    FROM usage
    WHERE timestamp >= DATE('now', '-6 months')
    GROUP BY 1, 2
    ORDER BY 2, 1;" 2>/dev/null)"

  if [[ -z "$rows" ]]; then
    say "${C_DIM}   (no segments in the last 6 months)${C_RESET}"
    say
    return 0
  fi

  printf '   %-8s %-12s %9s %12s   %s\n' "month" "type" "segments" "avg tokens" "trend"
  local month type segs avg prev_type="" prev_avg="" trend
  while IFS='|' read -r month type segs avg; do
    [[ -n "$month" ]] || continue
    trend=""
    if [[ "$type" == "$prev_type" && -n "$prev_avg" && "$prev_avg" -gt 0 ]]; then
      if (( avg * 100 < prev_avg * 85 )); then
        trend="${C_GREEN}cheaper (-$(( (prev_avg - avg) * 100 / prev_avg ))%)${C_RESET}"
      elif (( avg * 100 > prev_avg * 115 )); then
        trend="${C_RED}pricier (+$(( (avg - prev_avg) * 100 / prev_avg ))%)${C_RESET}"
      else
        trend="${C_DIM}flat${C_RESET}"
      fi
    fi
    printf '   %-8s %-12.12s %9s %12s   %b\n' \
      "$month" "$type" "$segs" "$(_impact_ktok "$avg")" "$trend"
    prev_type="$type"
    prev_avg="$avg"
  done <<< "$rows"
  say
}

_impact_ktok() {
  local n="${1:-0}"
  if (( n >= 1000000 )); then
    printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif (( n >= 1000 )); then
    printf '%dk' $(( n / 1000 ))
  else
    printf '%d' "$n"
  fi
}
