# Usage monitoring — SQLite-backed token tracking across all projects

_usage_db="$HOME/.agentboard/usage.db"

_init_usage_db() {
  if [[ ! -f "$_usage_db" ]]; then
    mkdir -p "$HOME/.agentboard"
    sqlite3 "$_usage_db" "CREATE TABLE IF NOT EXISTS usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        agent_provider TEXT NOT NULL,
        model TEXT,
        stream_slug TEXT,
        repo TEXT,
        task_type TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        total_tokens INTEGER,
        estimated_cost REAL,
        note TEXT,
        session_id TEXT
    );"
  else
    sqlite3 "$_usage_db" \
      "ALTER TABLE usage ADD COLUMN note TEXT;" 2>/dev/null || true
  fi
}

# Sum a column for rows matching a session key.
# Session key format: "<stream>|<provider>|<YYYY-MM-DD>". Rows are matched by
# stream_slug + agent_provider + calendar day (DATE(timestamp) in local zone).
_usage_session_sum() {
  local db="$1" key="$2" column="$3"
  # Parse key (fields separated by |)
  local stream provider day
  stream="$(printf '%s' "$key" | awk -F'|' '{print $1}')"
  provider="$(printf '%s' "$key" | awk -F'|' '{print $2}')"
  day="$(printf '%s' "$key" | awk -F'|' '{print $3}')"
  # Empty day means caller gave non-standard session key; fall back to matching
  # the key exactly on stream_slug + provider with any timestamp.
  if [[ -z "$day" ]]; then
    sqlite3 "$db" "SELECT COALESCE(SUM($column), 0) FROM usage
      WHERE stream_slug = '$stream' AND agent_provider = '$provider';"
    return 0
  fi
  sqlite3 "$db" "SELECT COALESCE(SUM($column), 0) FROM usage
    WHERE stream_slug = '$stream'
      AND agent_provider = '$provider'
      AND DATE(timestamp, 'localtime') = '$day';"
}

# Analyse patterns and emit findings + recommendations
# Returns lines of the form: FINDING|RECOMMENDATION|SAVING
_analyse_patterns() {
  local db="$1"

  # ── Model overkill: Opus used for cheap tasks ──────────────────────────────
  # Threshold: opus segments averaging < 20k tokens  (≥3 samples)
  while IFS='|' read -r task_type avg_tokens segments; do
    [[ -z "$task_type" ]] && continue
    printf 'MODEL_OVERKILL|%s|%.0f|%s\n' "$task_type" "$avg_tokens" "$segments"
  done < <(sqlite3 "$db" "
    SELECT task_type, AVG(total_tokens) AS avg, COUNT(*) AS n
    FROM usage
    WHERE model LIKE '%opus%' AND total_tokens > 0
    GROUP BY task_type
    HAVING n >= 3 AND avg < 20000
    ORDER BY avg ASC;
  ")

  # ── Research bloat: research tasks averaging > 60k ────────────────────────
  while IFS='|' read -r repo avg_tokens segments; do
    [[ -z "$repo" ]] && continue
    printf 'RESEARCH_BLOAT|%s|%.0f|%s\n' "$repo" "$avg_tokens" "$segments"
  done < <(sqlite3 "$db" "
    SELECT repo, AVG(total_tokens) AS avg, COUNT(*) AS n
    FROM usage
    WHERE task_type = 'research' AND total_tokens > 0
    GROUP BY repo
    HAVING n >= 3 AND avg > 60000
    ORDER BY avg DESC;
  ")

  # ── Debug drain: debug tasks averaging > 80k ──────────────────────────────
  while IFS='|' read -r repo avg_tokens segments; do
    [[ -z "$repo" ]] && continue
    printf 'DEBUG_DRAIN|%s|%.0f|%s\n' "$repo" "$avg_tokens" "$segments"
  done < <(sqlite3 "$db" "
    SELECT repo, AVG(total_tokens) AS avg, COUNT(*) AS n
    FROM usage
    WHERE task_type = 'debug' AND total_tokens > 0
    GROUP BY repo
    HAVING n >= 3 AND avg > 80000
    ORDER BY avg DESC;
  ")

  # ── Hot repo: one repo consuming >60% of total tokens ─────────────────────
  while IFS='|' read -r repo repo_total global_pct; do
    [[ -z "$repo" ]] && continue
    printf 'HOT_REPO|%s|%s|%.0f\n' "$repo" "$repo_total" "$global_pct"
  done < <(sqlite3 "$db" "
    SELECT repo,
           SUM(total_tokens) AS repo_total,
           100.0 * SUM(total_tokens) / (SELECT SUM(total_tokens) FROM usage) AS pct
    FROM usage
    WHERE total_tokens > 0
    GROUP BY repo
    HAVING pct > 60
    ORDER BY repo_total DESC
    LIMIT 1;
  ")

  # ── Context thrash: stream with >4 segments ───────────────────────────────
  while IFS='|' read -r stream segments total; do
    [[ -z "$stream" ]] && continue
    printf 'CONTEXT_THRASH|%s|%s|%s\n' "$stream" "$segments" "$total"
  done < <(sqlite3 "$db" "
    SELECT stream_slug, COUNT(*) AS n, SUM(total_tokens) AS total
    FROM usage
    WHERE stream_slug IS NOT NULL AND stream_slug != '' AND total_tokens > 0
    GROUP BY stream_slug
    HAVING n > 4
    ORDER BY n DESC
    LIMIT 5;
  ")
}

cmd_usage() {
  command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required for usage monitoring. Install it first."

  _init_usage_db
  local db="$_usage_db"
  local sub="${1:-summary}"
  shift || true

  case "$sub" in
    log)
      local provider="" model="" stream="" input=0 output=0 repo="" type="chore" note=""
      local cum_in="" cum_out="" session_key=""
      repo="$(basename "$(pwd)")"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --provider) provider="$2"; shift 2 ;;
          --model)    model="$2";    shift 2 ;;
          --stream)   stream="$2";   shift 2 ;;
          --repo)     repo="$2";     shift 2 ;;
          --type)     type="$2";     shift 2 ;;
          --input)    input="$2";    shift 2 ;;
          --output)   output="$2";   shift 2 ;;
          --cumulative-in)  cum_in="$2";  shift 2 ;;
          --cumulative-out) cum_out="$2"; shift 2 ;;
          --session-key)    session_key="$2"; shift 2 ;;
          --note)     note="$2";     shift 2 ;;
          *) shift ;;
        esac
      done
      [[ -n "$provider" ]] || die "Usage: agentboard usage log --provider <name> (--input <N> --output <N> | --cumulative-in <N> --cumulative-out <N>) [--model <M>] [--stream <S>] [--session-key <K>] [--repo <R>] [--type <T>] [--note <text>]"

      # Cumulative mode: Claude/Codex/Gemini report running session totals, not
      # per-segment deltas. Compute delta = cumulative - sum-logged-so-far for
      # this session, so each log row stores the actual segment usage.
      if [[ -n "$cum_in" || -n "$cum_out" ]]; then
        [[ -n "$cum_in" && -n "$cum_out" ]] \
          || die "--cumulative-in and --cumulative-out must be used together"
        [[ "$cum_in" =~ ^[0-9]+$ && "$cum_out" =~ ^[0-9]+$ ]] \
          || die "--cumulative-in/--cumulative-out must be non-negative integers"

        # Default session scope: same stream + same provider + same calendar day.
        # Users can override with --session-key for custom grouping.
        local default_key="${stream}|${provider}|$(date +%Y-%m-%d)"
        local key="${session_key:-$default_key}"

        local prev_in prev_out
        prev_in="$(_usage_session_sum "$db" "$key" input_tokens)"
        prev_out="$(_usage_session_sum "$db" "$key" output_tokens)"
        [[ -z "$prev_in" ]] && prev_in=0
        [[ -z "$prev_out" ]] && prev_out=0

        local delta_in=$(( cum_in - prev_in ))
        local delta_out=$(( cum_out - prev_out ))

        # Negative delta = session reset (new CLI session with fresh counter).
        # Log the cumulative as-is — it represents a full fresh session.
        local reset_note=""
        if (( delta_in < 0 || delta_out < 0 )); then
          delta_in="$cum_in"
          delta_out="$cum_out"
          reset_note=" (session reset detected — logging cumulative as fresh segment)"
        fi

        input="$delta_in"
        output="$delta_out"
        printf '  %scumulative: %s in / %s out · session-so-far: %s in / %s out · delta: %s in / %s out%s%s\n' \
          "$C_DIM" "$cum_in" "$cum_out" "$prev_in" "$prev_out" \
          "$delta_in" "$delta_out" "$reset_note" "$C_RESET"
      fi

      local total=$((input + output))
      sqlite3 "$db" "INSERT INTO usage (agent_provider, model, stream_slug, repo, task_type, input_tokens, output_tokens, total_tokens, note)
        VALUES ('$provider', '$model', '$stream', '$repo', '$type', $input, $output, $total, '$note');"
      ok "Logged $total tokens  (provider=$provider repo=$repo stream=${stream:-none} type=$type)"
      [[ -n "$note" ]] && printf '  note: %s\n' "$note" || true
      ;;

    stream)
      local target_stream="${1:-}"
      [[ -n "$target_stream" ]] || die "Usage: agentboard usage stream <stream-slug>"
      printf '\n%s%sStream: %s%s\n\n' "$C_BOLD" "$C_CYAN" "$target_stream" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT timestamp, agent_provider AS Provider, model AS Model,
               input_tokens AS Input, output_tokens AS Output,
               total_tokens AS Total, note AS Note
        FROM usage WHERE stream_slug = '$target_stream' ORDER BY timestamp ASC;
      "
      say
      sqlite3 -header -column "$db" "
        SELECT agent_provider AS Provider, model AS Model,
               COUNT(*) AS Segments,
               SUM(input_tokens) AS Total_Input, SUM(output_tokens) AS Total_Output,
               SUM(total_tokens) AS Grand_Total
        FROM usage WHERE stream_slug = '$target_stream'
        GROUP BY agent_provider, model ORDER BY Grand_Total DESC;
      "
      say
      sqlite3 "$db" "
        SELECT '  STREAM TOTAL: ' || SUM(total_tokens) || ' tokens across '
               || COUNT(*) || ' context segment(s)'
        FROM usage WHERE stream_slug = '$target_stream';
      "
      ;;

    summary)
      printf '\n%s%sGlobal Token Usage — Last 30 Days%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT agent_provider AS Provider, model AS Model,
               SUM(total_tokens) AS Total_Tokens, COUNT(*) AS Segments,
               CAST(SUM(total_tokens) AS REAL) / COUNT(*) AS Avg_Per_Segment
        FROM usage WHERE timestamp > date('now', '-30 days')
        GROUP BY agent_provider, model ORDER BY Total_Tokens DESC;
      "
      say
      printf '%sBy Repository:%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT repo AS Repository, SUM(total_tokens) AS Total, COUNT(*) AS Segments
        FROM usage WHERE timestamp > date('now', '-30 days')
        GROUP BY repo ORDER BY Total DESC;
      "
      say
      printf '%sBy Task Type:%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT task_type AS Type, SUM(total_tokens) AS Total,
               AVG(total_tokens) AS Avg_Per_Segment, COUNT(*) AS Segments
        FROM usage WHERE timestamp > date('now', '-30 days')
        GROUP BY task_type ORDER BY Total DESC;
      "
      ;;

    history)
      sqlite3 -header -column "$db" \
        "SELECT timestamp, repo, agent_provider, model, task_type, stream_slug, total_tokens, note
         FROM usage ORDER BY timestamp DESC LIMIT 20;"
      ;;

    optimize)
      printf '\n%s%sOptimization Insights%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
      printf '%sMost expensive task types:%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT task_type AS Type, AVG(total_tokens) AS Avg_Per_Segment,
               MAX(total_tokens) AS Worst_Segment, COUNT(*) AS Segments
        FROM usage GROUP BY task_type ORDER BY Avg_Per_Segment DESC;
      "
      say
      printf '%sMost expensive streams (all providers + clears combined):%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT stream_slug AS Stream, SUM(total_tokens) AS Total,
               COUNT(DISTINCT agent_provider) AS Providers, COUNT(*) AS Segments
        FROM usage WHERE stream_slug IS NOT NULL AND stream_slug != ''
        GROUP BY stream_slug ORDER BY Total DESC LIMIT 10;
      "
      say
      printf '%sProvider efficiency comparison:%s\n' "$C_DIM" "$C_RESET"
      sqlite3 -header -column "$db" "
        SELECT agent_provider AS Provider, model AS Model,
               AVG(total_tokens) AS Avg_Per_Segment,
               SUM(total_tokens) AS Total, COUNT(*) AS Segments
        FROM usage GROUP BY agent_provider, model ORDER BY Avg_Per_Segment DESC;
      "
      ;;

    learn)
      local apply=0
      [[ "${1:-}" == "--apply" ]] && apply=1

      printf '\n%s%sUsage Learning Analysis%s\n\n' "$C_BOLD" "$C_CYAN" "$C_RESET"

      local total_rows
      total_rows="$(sqlite3 "$db" "SELECT COUNT(*) FROM usage WHERE total_tokens > 0;")"
      if [[ "$total_rows" -lt 5 ]]; then
        warn "Not enough data yet ($total_rows segments logged). Need at least 5 to generate learnings."
        say
        printf '%sKeep logging with: agentboard usage log --provider ... --input ... --output ...%s\n' "$C_DIM" "$C_RESET"
        return 0
      fi

      local findings=() recommendations=() new_learnings=()
      local kind a b c

      while IFS='|' read -r kind a b c; do
        case "$kind" in
          MODEL_OVERKILL)
            local task_type="$a" avg="$b" segs="$c"
            local rec="Use Sonnet (or Haiku for tasks <5k tokens) instead of Opus for '${task_type}' tasks — avg ${avg} tokens over ${segs} segments is below Opus's value threshold."
            local learning="Opus is over-specified for '${task_type}' tasks (avg ${avg} tokens, ${segs} samples). Default to claude-sonnet-4-6 for this task type."
            printf '  %s⚠ MODEL_OVERKILL%s  %s tasks — Opus averaging %s tokens (%s segs)\n' \
              "$C_YELLOW" "$C_RESET" "$task_type" "$avg" "$segs"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
          RESEARCH_BLOAT)
            local repo="$a" avg="$b" segs="$c"
            local rec="In '${repo}': research tasks avg ${avg} tokens. Use targeted reads (grep/glob + line ranges) instead of full-file reads. Load only files listed in work/BRIEF.md § Relevant context."
            local learning="Research tasks in '${repo}' are expensive (avg ${avg} tokens, ${segs} samples). Enforce scoped context loading: read only files listed in BRIEF.md, use line-range reads."
            printf '  %s⚠ RESEARCH_BLOAT%s  %s — research avg %s tokens (%s segs)\n' \
              "$C_YELLOW" "$C_RESET" "$repo" "$avg" "$segs"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
          DEBUG_DRAIN)
            local repo="$a" avg="$b" segs="$c"
            local rec="In '${repo}': debug tasks avg ${avg} tokens. Run /ab-debug (hypothesis-first, max 3 reads before testing) rather than broad exploration."
            local learning="Debug sessions in '${repo}' are expensive (avg ${avg} tokens, ${segs} samples). Enforce hypothesis-first debugging: state hypothesis, read ≤3 files, test, iterate."
            printf '  %s⚠ DEBUG_DRAIN%s  %s — debug avg %s tokens (%s segs)\n' \
              "$C_YELLOW" "$C_RESET" "$repo" "$avg" "$segs"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
          HOT_REPO)
            local repo="$a" total="$b" pct="$c"
            local rec="'${repo}' is consuming ${pct}% of all tokens. Check conventions/ for that repo — context may be loading too many files at session start."
            local learning="'${repo}' dominates token spend (${pct}% of total). Audit session start context loading — reduce files loaded by default in ONBOARDING.md or BRIEF.md."
            printf '  %s⚠ HOT_REPO%s  %s — %s%% of all token spend (%s total tokens)\n' \
              "$C_YELLOW" "$C_RESET" "$repo" "$pct" "$total"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
          CONTEXT_THRASH)
            local stream="$a" segs="$b" total="$c"
            local rec="Stream '${stream}' needed ${segs} context clears (${total} total tokens). Break this type of work into smaller focused streams, or load less context per session."
            local learning="Stream '${stream}' required ${segs} context resets (${total} tokens total). For similar tasks: pre-scope the domain, load only 1-2 reference files, keep stream focused."
            printf '  %s⚠ CONTEXT_THRASH%s  %s — %s context segments, %s total tokens\n' \
              "$C_YELLOW" "$C_RESET" "$stream" "$segs" "$total"
            printf '    → %s\n\n' "$rec"
            new_learnings+=("$learning")
            ;;
        esac
      done < <(_analyse_patterns "$db")

      if [[ ${#new_learnings[@]} -eq 0 ]]; then
        ok "No significant inefficiencies detected in current data."
        say
        printf '%sRun again after more sessions are logged.%s\n' "$C_DIM" "$C_RESET"
        return 0
      fi

      printf '%s%d finding(s) detected.%s\n' "$C_BOLD" "${#new_learnings[@]}" "$C_RESET"

      if (( apply )); then
        if [[ ! -d "./.platform" ]]; then
          warn "No .platform/ found in current directory. Run from inside a project."
          return 1
        fi
        say
        local entry
        for entry in "${new_learnings[@]}"; do
          # Only write if not already covered by an existing fact
          if ! _harvest_already_known "$(printf '%s' "$entry" | cut -c1-60)"; then
            _fact_new --type learning --quiet \
              --title "[token-optimization] ${entry}" \
              --body "${entry}"$'\n\n'"_Generated by \`agentboard usage learn\` on $(today)._" >/dev/null
            ok "Fact written: ${entry:0:80}..."
          else
            printf '  %s↷%s Already a fact — skipped\n' "$C_DIM" "$C_RESET"
          fi
        done
        say
        ok "Learning facts written. They surface via \`agentboard brief\` and INDEX.md."
      else
        say
        printf '%sRun with --apply to write these findings as learning facts (.platform/memory/facts/)%s\n' \
          "$C_DIM" "$C_RESET"
        printf '%sThe LLM picks them up from INDEX.md / brief at the next session start.%s\n' \
          "$C_DIM" "$C_RESET"
      fi
      ;;

    dashboard)
      local period_days=30 period_label="Last 30 Days"
      for arg in "$@"; do
        case "$arg" in
          --today) period_days=1;  period_label="Today"        ;;
          --week)  period_days=7;  period_label="Last 7 Days"  ;;
          --month) period_days=30; period_label="Last 30 Days" ;;
        esac
      done
      local where="timestamp > datetime('now', '-${period_days} days')"

      local tw; tw="$(tput cols 2>/dev/null || printf '80')"
      (( tw > 120 )) && tw=120; (( tw < 60 )) && tw=60
      local bar_w=$(( tw - 52 ))
      (( bar_w < 14 )) && bar_w=14; (( bar_w > 40 )) && bar_w=40

      _db_ktok() {
        local n="${1:-0}"
        (( n == 0 )) && { printf '%7s' '—'; return; }
        if   (( n >= 1000000 )); then printf '%4d.%dM' "$((n/1000000))" "$((n%1000000/100000))"
        elif (( n >= 1000 ));    then printf '%4d.%dk' "$((n/1000))"    "$((n%1000/100))"
        else                          printf '%7d' "$n"; fi
      }

      # _db_cbar: filled █ in $clr, empty ░ in dark gray, then reset
      # Use printf octal \033 to embed ESC reliably on bash 3.x
      _db_cbar() {
        local val="$1" max="$2" width="$3" clr="$4"
        (( max <= 0 )) && max=1
        local f=$(( val * width / max ))
        (( f > width )) && f=$width; (( f < 0 )) && f=0
        local e=$(( width - f )) fb='' eb=''
        (( f > 0 )) && fb="$(printf '%.0s█' $(seq 1 "$f"))"
        (( e > 0 )) && eb="$(printf '%.0s░' $(seq 1 "$e"))"
        printf '%s%s\033[38;5;238m%s\033[0m' "$clr" "$fb" "$eb"
      }

      # bash 3.x-safe lowercase via tr (${1,,} requires bash 4+)
      _db_pclr() {
        case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
          claude|anthropic) printf '\033[38;5;87m'  ;;
          codex|openai)     printf '\033[38;5;114m' ;;
          gemini|google)    printf '\033[38;5;220m' ;;
          *)                printf '\033[38;5;252m' ;;
        esac
      }

      # Heat colour: green (small/cheap) → yellow → orange → red (large/expensive)
      _db_heat() {
        local val="$1" max="$2"
        (( max <= 0 )) && max=1
        local pct=$(( val * 100 / max ))
        if   (( pct < 15 )); then printf '\033[38;5;82m'
        elif (( pct < 35 )); then printf '\033[38;5;148m'
        elif (( pct < 60 )); then printf '\033[38;5;214m'
        elif (( pct < 80 )); then printf '\033[38;5;208m'
        else                      printf '\033[38;5;196m'
        fi
      }

      _db_row() {
        local lbl="$1" val="$2" max="$3" clr="$4"
        (( max <= 0 )) && max=1
        local pct=$(( val * 100 / max ))
        printf '  %-22.22s  ' "$lbl"
        _db_cbar "$val" "$max" "$bar_w" "$clr"
        printf '  %s%s%s  %s%3d%%%s\n' \
          "$C_BOLD" "$(_db_ktok "$val")" "$C_RESET" "$C_DIM" "$pct" "$C_RESET"
      }

      _db_section() {
        local title="$1"
        local dashes=$(( tw - ${#title} - 4 ))
        (( dashes < 1 )) && dashes=1
        printf '\n%s%s━━ %s%s %s' "$C_BOLD" "$C_CYAN" "$title" "$C_RESET" "$C_DIM"
        (( dashes > 0 )) && printf '%.0s━' $(seq 1 "$dashes")
        printf '%s\n\n' "$C_RESET"
      }

      # ── Totals ──────────────────────────────────────────────────────────────
      local tt=0 ts=0 tp=0 tr=0
      IFS='|' read -r tt ts tp tr < <(sqlite3 "$db" \
        "SELECT COALESCE(SUM(total_tokens),0), COUNT(*),
                COUNT(DISTINCT agent_provider), COUNT(DISTINCT repo)
         FROM usage WHERE $where;") || true
      tt="${tt:-0}"; ts="${ts:-0}"; tp="${tp:-0}"; tr="${tr:-0}"

      # ── Header ──────────────────────────────────────────────────────────────
      printf '\n%s%s' "$C_BOLD" "$C_CYAN"
      printf '%.0s═' $(seq 1 "$tw")
      printf '%s\n' "$C_RESET"
      printf '  %s%s⚡ AGENTBOARD TOKEN DASHBOARD%s   %s%s%s\n' \
        "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" "$period_label" "$C_RESET"
      printf '  %s%s tokens%s  ·  %s%s segs%s  ·  %s%s providers%s  ·  %s%s repos%s\n' \
        "$C_BOLD" "$(_db_ktok "$tt")" "$C_RESET" \
        "$C_BOLD" "$ts" "$C_RESET" \
        "$C_BOLD" "$tp" "$C_RESET" \
        "$C_BOLD" "$tr" "$C_RESET"
      printf '%s%s' "$C_BOLD" "$C_CYAN"
      printf '%.0s═' $(seq 1 "$tw")
      printf '%s\n' "$C_RESET"

      # ── By Provider & Model ─────────────────────────────────────────────────
      _db_section "BY PROVIDER & MODEL"
      local _found=0
      while IFS='|' read -r prov model tok; do
        [[ -z "$prov" ]] && continue; (( tok > 0 )) || continue
        _found=1
        printf '\n'
        _db_row "${prov} · ${model}" "$tok" "$tt" "$(_db_heat "$tok" "$tt")"
      done < <(sqlite3 "$db" \
        "SELECT agent_provider, COALESCE(model,'?'), SUM(total_tokens) AS t
         FROM usage WHERE $where AND total_tokens > 0
         GROUP BY agent_provider, model ORDER BY t DESC;")
      (( _found == 0 )) && printf '  %s(no data for this period)%s\n' "$C_DIM" "$C_RESET"

      # ── By Repository ───────────────────────────────────────────────────────
      _db_section "BY REPOSITORY"
      while IFS='|' read -r repo tok; do
        [[ -z "$repo" ]] && continue; (( tok > 0 )) || continue
        printf '\n'
        _db_row "$repo" "$tok" "$tt" "$(_db_heat "$tok" "$tt")"
      done < <(sqlite3 "$db" \
        "SELECT COALESCE(repo,'unknown'), SUM(total_tokens) AS t
         FROM usage WHERE $where AND total_tokens > 0
         GROUP BY repo ORDER BY t DESC;")

      # ── By Task Type with model breakdown (who did the work) ────────────────
      _db_section "BY TASK TYPE  ·  WHO DID THE WORK"
      local _prev_ttype="" _task_tot=0
      local sub_bw=$(( bar_w - 4 )); (( sub_bw < 10 )) && sub_bw=10

      while IFS='|' read -r ttype prov model row_tok type_total; do
        [[ -z "$ttype" ]] && continue
        row_tok="${row_tok:-0}"; type_total="${type_total:-1}"
        (( row_tok > 0 )) || continue

        if [[ "$ttype" != "$_prev_ttype" ]]; then
          _prev_ttype="$ttype"
          _task_tot=$type_total
          printf '\n'
          _db_row "$ttype" "$type_total" "$tt" "$(_db_heat "$type_total" "$tt")"
        fi

        local _tdenom=$_task_tot; (( _tdenom <= 0 )) && _tdenom=1
        local sub_pct=$(( row_tok * 100 / _tdenom ))
        printf '    %-20.20s  ' "${prov}·${model}"
        _db_cbar "$row_tok" "$_task_tot" "$sub_bw" "$(_db_pclr "$prov")"
        printf '  %s%s%s  %s%3d%%%s\n' \
          "$C_DIM" "$(_db_ktok "$row_tok")" "$C_RESET" "$C_DIM" "$sub_pct" "$C_RESET"
      done < <(sqlite3 "$db" "
        WITH totals AS (
          SELECT COALESCE(task_type,'chore') AS tt, SUM(total_tokens) AS type_total
          FROM usage WHERE $where AND total_tokens > 0
          GROUP BY task_type
        )
        SELECT COALESCE(u.task_type,'chore'), u.agent_provider, COALESCE(u.model,'?'),
               SUM(u.total_tokens), t.type_total
        FROM usage u
        JOIN totals t ON COALESCE(u.task_type,'chore') = t.tt
        WHERE $where AND u.total_tokens > 0
        GROUP BY u.task_type, u.agent_provider, u.model
        ORDER BY t.type_total DESC, SUM(u.total_tokens) DESC;
      ")

      # ── Daily Activity ──────────────────────────────────────────────────────
      _db_section "DAILY ACTIVITY"
      local chart_days=$period_days; (( chart_days > 14 )) && chart_days=14
      local day_bw=$(( bar_w + 8 )); (( day_bw > 36 )) && day_bw=36

      local max_day=0
      max_day="$(sqlite3 "$db" \
        "SELECT COALESCE(MAX(s),0) FROM
           (SELECT SUM(total_tokens) AS s FROM usage
            WHERE $where AND total_tokens > 0 GROUP BY date(timestamp));")"
      max_day="${max_day:-0}"

      local peak_date=''
      peak_date="$(sqlite3 "$db" \
        "SELECT date(timestamp) FROM usage WHERE $where AND total_tokens > 0
         GROUP BY date(timestamp) ORDER BY SUM(total_tokens) DESC LIMIT 1;")"

      while IFS='|' read -r d day_tok; do
        local dlbl="${d:5}"
        day_tok="${day_tok:-0}"
        if (( day_tok == 0 )); then
          printf '  %s%s%s  ' "$C_DIM" "$dlbl" "$C_RESET"
          printf '%s' "$C_DIM"; printf '%.0s·' $(seq 1 "$day_bw"); printf '%s\n' "$C_RESET"
        else
          printf '  %s%s%s  ' "$C_BOLD" "$dlbl" "$C_RESET"
          _db_cbar "$day_tok" "$max_day" "$day_bw" "$(_db_heat "$day_tok" "$max_day")"
          local pk=''
          [[ "$d" == "$peak_date" ]] && pk="$(printf '  \033[38;5;220m▲\033[0m')"
          printf '  %s%s%s%s\n' "$C_BOLD" "$(_db_ktok "$day_tok")" "$C_RESET" "$pk"
        fi
      done < <(sqlite3 "$db" "
        WITH RECURSIVE dates(d) AS (
          SELECT date('now', '-$((chart_days - 1)) days')
          UNION ALL
          SELECT date(d, '+1 day') FROM dates WHERE d < date('now')
        )
        SELECT d, COALESCE((
          SELECT SUM(total_tokens) FROM usage
          WHERE date(timestamp) = d AND total_tokens > 0
        ), 0) FROM dates ORDER BY d;
      ")

      printf '\n'
      ;;

    impact)
      cmd_usage_impact "$db"
      ;;

    *)
      die "Unknown usage subcommand: $sub. Options: summary | log | stream <slug> | history | optimize | learn [--apply] | dashboard [--today|--week|--month] | impact"
      ;;
  esac
}
