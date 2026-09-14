# SQLite CLI values are encoded as hex text literals, never executable SQL.
_usage_text() {
  local hex
  hex="$(printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n')" || return 1
  printf "CAST(X'%s' AS TEXT)" "$hex"
}

_usage_sql() {
  sqlite3 -batch -bail -cmd '.timeout 10000' "$@"
}

_init_usage_db() {
  mkdir -p "$(dirname "$_usage_db")" || return 1
  _usage_sql "$_usage_db" "CREATE TABLE IF NOT EXISTS usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    agent_provider TEXT NOT NULL, model TEXT, stream_slug TEXT, repo TEXT,
    task_type TEXT, input_tokens INTEGER, output_tokens INTEGER,
    total_tokens INTEGER, estimated_cost REAL, note TEXT, session_id TEXT
  );" || return 1
  local columns column
  columns="$(_usage_sql "$_usage_db" 'PRAGMA table_info(usage);')" || return 1
  for column in note session_id; do
    if ! printf '%s\n' "$columns" | cut -d '|' -f2 | grep -qx "$column"; then
      # A concurrent initializer may add the column first. Recheck on failure.
      _usage_sql "$_usage_db" "ALTER TABLE usage ADD COLUMN $column TEXT;" 2>/dev/null || {
        columns="$(_usage_sql "$_usage_db" 'PRAGMA table_info(usage);')" || return 1
        printf '%s\n' "$columns" | cut -d '|' -f2 | grep -qx "$column" || return 1
      }
    fi
  done
  _usage_sql "$_usage_db" "CREATE TABLE IF NOT EXISTS usage_counters (
    project TEXT NOT NULL, provider TEXT NOT NULL, stream TEXT NOT NULL,
    session TEXT NOT NULL, input INTEGER NOT NULL, output INTEGER NOT NULL,
    PRIMARY KEY (project, provider, stream, session)
  );" || return 1
}

_usage_log() {
  local db="$1"; shift
  local provider="" model="" stream="" input=0 output=0 type=chore note=""
  local repo cum_in="" cum_out="" session="${AGENTBOARD_SESSION_ID:-}"
  local explicit_delta=0
  repo="$(basename "$(pwd)")"
  while [[ $# -gt 0 ]]; do
    [[ $# -ge 2 ]] || { warn "Missing value after $1"; return 1; }
    case "$1" in
      --provider) provider="$2" ;; --model) model="$2" ;;
      --stream) stream="$2" ;; --repo) repo="$2" ;; --type) type="$2" ;;
      --input) input="$2"; explicit_delta=1 ;;
      --output) output="$2"; explicit_delta=1 ;;
      --cumulative-in) cum_in="$2" ;; --cumulative-out) cum_out="$2" ;;
      --session-id|--session-key) session="$2" ;;
      --note) note="$2" ;;
      *) warn "Unknown usage log flag: $1"; return 1 ;;
    esac
    shift 2
  done
  [[ -n "$provider" ]] || { warn "usage log requires --provider"; return 1; }
  local mode=delta legacy=0
  if [[ -n "$cum_in" || -n "$cum_out" ]]; then
    [[ -n "$cum_in" && -n "$cum_out" ]] || {
      warn "--cumulative-in and --cumulative-out must be used together"; return 1;
    }
    (( ! explicit_delta )) || { warn "Use delta OR cumulative counters, not both"; return 1; }
    mode=cumulative; input="$cum_in"; output="$cum_out"
  fi
  # Bound before shell arithmetic and SQL interpolation; counters are decimal.
  [[ "$input" =~ ^[0-9]{1,15}$ && "$output" =~ ^[0-9]{1,15}$ ]] || {
    warn "Token counts must be non-negative integers (at most 15 digits)"; return 1;
  }
  input=$((10#$input)); output=$((10#$output))
  if [[ -z "$session" ]]; then
    session="legacy:$(date +%Y-%m-%d)"; legacy=1
  fi
  local project
  project="$(git rev-parse --show-toplevel 2>/dev/null)" || project="$(pwd -P)"
  local qp qm qs qr qt qn qi qproject
  qp="$(_usage_text "$provider")" && qm="$(_usage_text "$model")" &&
    qs="$(_usage_text "$stream")" && qr="$(_usage_text "$repo")" &&
    qt="$(_usage_text "$type")" && qn="$(_usage_text "$note")" &&
    qi="$(_usage_text "$session")" && qproject="$(_usage_text "$project")" || return 1
  local result total
  if [[ "$mode" == cumulative ]]; then
    # Serialize baseline read, segment insert and baseline advance. Explicit
    # sessions use high-water marks, making duplicates/out-of-order reports safe.
    # Legacy mode can detect drops, but cannot distinguish resets from old reports.
    result="$(_usage_sql "$db" "BEGIN IMMEDIATE;
      INSERT OR IGNORE INTO usage_counters VALUES ($qproject,$qp,$qs,$qi,0,0);
      CREATE TEMP TABLE observation AS
        SELECT input AS previous_input, output AS previous_output,
          ($legacy = 1 AND $input <= input AND $output <= output
            AND ($input < input OR $output < output)) AS reset
        FROM usage_counters WHERE project=$qproject AND provider=$qp AND stream=$qs AND session=$qi;
      CREATE TEMP TABLE delta AS SELECT
        CASE WHEN reset THEN $input ELSE MAX(0,$input-previous_input) END AS di,
        CASE WHEN reset THEN $output ELSE MAX(0,$output-previous_output) END AS dout
        FROM observation;
      INSERT INTO usage (agent_provider,model,stream_slug,repo,task_type,input_tokens,output_tokens,total_tokens,note,session_id)
        SELECT $qp,$qm,$qs,$qr,$qt,di,dout,di+dout,$qn,$qi FROM delta;
      UPDATE usage_counters SET
        input=CASE WHEN (SELECT reset FROM observation) THEN $input ELSE MAX(input,$input) END,
        output=CASE WHEN (SELECT reset FROM observation) THEN $output ELSE MAX(output,$output) END
        WHERE project=$qproject AND provider=$qp AND stream=$qs AND session=$qi;
      SELECT di+dout FROM delta;
      COMMIT;")" || { warn "Usage database write failed; no segment recorded"; return 1; }
    total="$result"
    printf '  cumulative: %s in / %s out (session %s; delta %s tokens)\n' "$input" "$output" "$session" "$total"
  else
    total=$((input + output))
    # Delta reports advance the same baseline so a later cumulative observation
    # does not record those tokens again. Delta reports themselves are additive.
    _usage_sql "$db" "BEGIN IMMEDIATE;
      INSERT OR IGNORE INTO usage_counters VALUES ($qproject,$qp,$qs,$qi,0,0);
      INSERT INTO usage (agent_provider,model,stream_slug,repo,task_type,input_tokens,output_tokens,total_tokens,note,session_id)
        VALUES ($qp,$qm,$qs,$qr,$qt,$input,$output,$total,$qn,$qi);
      UPDATE usage_counters SET input=input+$input,output=output+$output
        WHERE project=$qproject AND provider=$qp AND stream=$qs AND session=$qi;
      COMMIT;" || {
      warn "Usage database write failed; no segment recorded"; return 1;
    }
  fi
  ok "Logged $total tokens  (provider=$provider repo=$repo stream=${stream:-none} type=$type)"
  [[ -z "$note" ]] || printf '  note: %s\n' "$note"
  return 0
}
