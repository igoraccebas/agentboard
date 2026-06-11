# facts.sh — one-fact-per-file project memory under .platform/memory/facts/
#
# Why facts instead of big category files: two agents appending to the same
# learnings.md collide in git; one file per fact never conflicts. INDEX.md is
# the cheap always-loaded view; fact bodies load only when relevant.

FACTS_DIR="./.platform/memory/facts"
FACTS_INDEX="./.platform/memory/INDEX.md"
# Decisions are deliberately NOT a fact type — memory/decisions.md is the
# curated registry with supersede semantics, seeded during activation.
FACT_TYPES="gotcha learning playbook question"

cmd_fact() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    new)      _fact_new "$@" ;;
    list)     _fact_list "$@" ;;
    reindex)  _fact_reindex "$@" ;;
    prune)    _fact_prune "$@" ;;
    -h|--help|help) _fact_print_help ;;
    *) die "Unknown fact subcommand: $sub. Try: new, list, reindex, prune" ;;
  esac
}

_fact_print_help() {
  cat <<'EOF'
Usage: agentboard fact <new|list|reindex|prune> [flags]

One fact per file under .platform/memory/facts/, plus a generated INDEX.md.
Small files = no git merge conflicts between parallel sessions; the index
keeps the always-loaded surface cheap.

fact new --type <t> --title "..." [flags]
  --type      gotcha | learning | playbook | question
              (decisions go in memory/decisions.md — the curated registry)
  --title     One line. The index shows exactly this.
  --domain    Domain slug. Repeat for multiple. Default: []
  --stream    Source stream slug. Default: —
  --severity  gotcha only: red | yellow | green. Default: yellow
  --body      Longer context (optional; title is reused when omitted)
  --expires   YYYY-MM-DD after which `prune` flags this fact
  --quiet     Print only the created file path

fact list [--type t] [--domain d] [--status s]
  Tabular view. Default shows status=active; --status all shows everything.

fact reindex
  Regenerate INDEX.md from the facts directory.

fact prune [--apply]
  Flags facts past their expiry date. With --apply, sets status: expired
  and reindexes. Never deletes files — expired facts stay greppable.
EOF
}

_fact_valid_type() {
  local t needle="$1"
  for t in $FACT_TYPES; do [[ "$t" == "$needle" ]] && return 0; done
  return 1
}

_fact_next_id() {
  local max=0 n file
  if [[ -d "$FACTS_DIR" ]]; then
    for file in "$FACTS_DIR"/F-*.md; do
      [[ -e "$file" ]] || continue
      n="$(basename "$file" | sed -nE 's/^F-([0-9]+).*/\1/p')"
      [[ -n "$n" ]] || continue
      n=$((10#$n))
      (( n > max )) && max=$n
    done
  fi
  printf 'F-%03d\n' $(( max + 1 ))
}

_fact_severity_emoji() {
  case "$1" in
    red)    printf '🔴' ;;
    yellow) printf '🟡' ;;
    green)  printf '🟢' ;;
    *)      printf '·' ;;
  esac
}

_fact_new() {
  local type="" title="" stream="—" severity="" body="" expires="—" quiet=0
  local -a domains=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)     [[ -n "${2:-}" ]] || die "fact new requires a value after --type";   type="$2"; shift 2 ;;
      --title)    [[ -n "${2:-}" ]] || die "fact new requires a value after --title";  title="$2"; shift 2 ;;
      --domain)   [[ -n "${2:-}" ]] || die "fact new requires a value after --domain"; domains+=("$2"); shift 2 ;;
      --stream)   [[ -n "${2:-}" ]] || die "fact new requires a value after --stream"; stream="$2"; shift 2 ;;
      --severity) [[ -n "${2:-}" ]] || die "fact new requires a value after --severity"; severity="$2"; shift 2 ;;
      --body)     [[ -n "${2:-}" ]] || die "fact new requires a value after --body";   body="$2"; shift 2 ;;
      --expires)  [[ -n "${2:-}" ]] || die "fact new requires a value after --expires"; expires="$2"; shift 2 ;;
      --quiet)    quiet=1; shift ;;
      -h|--help)  _fact_print_help; return 0 ;;
      *) die "Unknown flag for fact new: $1" ;;
    esac
  done

  [[ -n "$type" ]] || die "fact new requires --type (gotcha|learning|playbook|question)"
  _fact_valid_type "$type" || die "Invalid fact type: $type"
  [[ -n "$title" ]] || die "fact new requires --title \"<one line>\""
  title="${title//$'\n'/ }"

  if [[ "$type" == "gotcha" ]]; then
    [[ -n "$severity" ]] || severity="yellow"
    case "$severity" in red|yellow|green) ;; *) die "Invalid --severity: $severity (red|yellow|green)" ;; esac
  else
    [[ -z "$severity" ]] || die "--severity only applies to gotchas"
    severity="—"
  fi
  if [[ "$expires" != "—" ]]; then
    [[ "$expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "Invalid --expires: $expires (YYYY-MM-DD)"
  fi

  local domain domains_inline
  for domain in ${domains[@]+"${domains[@]}"}; do
    [[ -f "./.platform/domains/${domain}.md" ]] \
      || warn "Domain '${domain}' has no file at .platform/domains/${domain}.md (fact created anyway)"
  done
  domains_inline="$(printf '%s\n' ${domains[@]+"${domains[@]}"} | frontmatter_inline_array)"

  mkdir -p "$FACTS_DIR"
  local fact_id fact_file today_str
  fact_id="$(_fact_next_id)"
  today_str="$(today)"
  fact_file="$FACTS_DIR/${fact_id}-$(slugify "$title" | cut -c1-48).md"
  [[ -n "$body" ]] || body="$title"

  cat > "$fact_file" <<EOF
---
fact_id: ${fact_id}
type: ${type}
title: ${title}
domains: ${domains_inline}
source_stream: ${stream}
severity: ${severity}
status: active
created_at: ${today_str}
expires: ${expires}
---

${body}
EOF

  _fact_reindex --quiet
  if (( quiet )); then
    printf '%s\n' "$fact_file"
  else
    ok "Fact ${fact_id} (${type}) → ${fact_file}"
    say "  ${C_DIM}Index updated: ${FACTS_INDEX}${C_RESET}"
  fi
}

# _fact_rows [status-filter|all] — "id|type|title|domains|severity|status|expires|file"
_fact_rows() {
  local want_status="${1:-active}" file fid ftype ftitle fdomains fsev fstatus fexpires
  [[ -d "$FACTS_DIR" ]] || return 0
  for file in "$FACTS_DIR"/F-*.md; do
    [[ -e "$file" ]] || continue
    has_frontmatter "$file" || continue
    fstatus="$(frontmatter_value "$file" "status")"
    [[ "$want_status" == "all" || "$fstatus" == "$want_status" ]] || continue
    fid="$(frontmatter_value "$file" "fact_id")"
    ftype="$(frontmatter_value "$file" "type")"
    ftitle="$(frontmatter_value "$file" "title")"
    fdomains="$(frontmatter_value "$file" "domains")"
    fsev="$(frontmatter_value "$file" "severity")"
    fexpires="$(frontmatter_value "$file" "expires")"
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$fid" "$ftype" "$ftitle" "$fdomains" "$fsev" "$fstatus" "$fexpires" "$file"
  done
}

_fact_list() {
  local type_filter="" domain_filter="" status_filter="active"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)   [[ -n "${2:-}" ]] || die "fact list requires a value after --type";   type_filter="$2"; shift 2 ;;
      --domain) [[ -n "${2:-}" ]] || die "fact list requires a value after --domain"; domain_filter="$2"; shift 2 ;;
      --status) [[ -n "${2:-}" ]] || die "fact list requires a value after --status"; status_filter="$2"; shift 2 ;;
      -h|--help) _fact_print_help; return 0 ;;
      *) die "Unknown flag for fact list: $1" ;;
    esac
  done

  local count=0 fid ftype ftitle fdomains fsev fstatus fexpires ffile
  while IFS='|' read -r fid ftype ftitle fdomains fsev fstatus fexpires ffile; do
    [[ -n "$fid" ]] || continue
    [[ -z "$type_filter" || "$ftype" == "$type_filter" ]] || continue
    if [[ -n "$domain_filter" ]]; then
      inline_array_items "$fdomains" | grep -qx "$domain_filter" || continue
    fi
    printf '  %s %s %-8s %-22s %s%s%s\n' \
      "$fid" "$(_fact_severity_emoji "$fsev")" "$ftype" "$fdomains" "$C_BOLD" "$ftitle" "$C_RESET"
    count=$((count + 1))
  done < <(_fact_rows "$status_filter")

  if (( count == 0 )); then
    say "${C_DIM}  (no matching facts — create one with \`agentboard fact new\`)${C_RESET}"
  fi
}

_fact_reindex() {
  local quiet=0
  [[ "${1:-}" == "--quiet" ]] && quiet=1
  mkdir -p "$(dirname "$FACTS_INDEX")"

  local tmp count=0 fid ftype ftitle fdomains fsev fstatus fexpires ffile
  tmp="$(mktemp)"
  {
    printf '# Memory index\n\n'
    printf '_Generated by `agentboard fact reindex` — one line per active fact._\n'
    printf '_Always load this file; open an individual fact only when its domains match your work._\n\n'
  } > "$tmp"
  while IFS='|' read -r fid ftype ftitle fdomains fsev fstatus fexpires ffile; do
    [[ -n "$fid" ]] || continue
    printf -- '- %s %s [%s] %s — %s\n' \
      "$fid" "$(_fact_severity_emoji "$fsev")" "$ftype" "$fdomains" "$ftitle" >> "$tmp"
    count=$((count + 1))
  done < <(_fact_rows active)
  (( count == 0 )) && printf -- '_(no active facts yet)_\n' >> "$tmp"

  mv "$tmp" "$FACTS_INDEX"
  (( quiet )) || ok "Reindexed ${count} active fact(s) → ${FACTS_INDEX}"
}

# fact_validate_all — emit "E|message" / "W|message" lines for doctor.
# Errors: structural problems that would mislead the next session.
# Warnings: hygiene issues (unknown domain tags, stale index).
fact_validate_all() {
  local file fid ftype ftitle fstatus fsev fexpires d
  [[ -d "$FACTS_DIR" ]] || return 0
  for file in "$FACTS_DIR"/F-*.md; do
    [[ -e "$file" ]] || continue
    if ! has_frontmatter "$file"; then
      printf 'E|fact %s has no frontmatter\n' "$file"
      continue
    fi
    fid="$(frontmatter_value "$file" "fact_id")"
    ftype="$(frontmatter_value "$file" "type")"
    ftitle="$(frontmatter_value "$file" "title")"
    fstatus="$(frontmatter_value "$file" "status")"
    fsev="$(frontmatter_value "$file" "severity")"
    fexpires="$(frontmatter_value "$file" "expires")"
    [[ -n "$fid" ]]    || printf 'E|fact %s is missing fact_id\n' "$file"
    [[ -n "$ftitle" ]] || printf 'E|fact %s is missing title\n' "$file"
    if [[ -z "$ftype" ]] || ! _fact_valid_type "$ftype"; then
      printf 'E|fact %s has invalid type: %s\n' "$file" "${ftype:-<empty>}"
    fi
    case "$fstatus" in
      active|superseded|expired) ;;
      *) printf 'E|fact %s has invalid status: %s\n' "$file" "${fstatus:-<empty>}" ;;
    esac
    if [[ "$ftype" == "gotcha" ]]; then
      case "$fsev" in
        red|yellow|green) ;;
        *) printf 'E|fact %s (gotcha) has invalid severity: %s\n' "$file" "${fsev:-<empty>}" ;;
      esac
    fi
    if [[ -n "$fexpires" && "$fexpires" != "—" ]] && \
       [[ ! "$fexpires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      printf 'E|fact %s has malformed expires date: %s\n' "$file" "$fexpires"
    fi
    while IFS= read -r d; do
      [[ -z "$d" ]] && continue
      [[ -f "./.platform/domains/${d}.md" ]] || \
        printf 'W|fact %s references unknown domain: %s\n' "$file" "$d"
    done < <(inline_array_items "$(frontmatter_value "$file" "domains")")
  done
  if ls "$FACTS_DIR"/F-*.md >/dev/null 2>&1 && [[ ! -f "$FACTS_INDEX" ]]; then
    printf 'W|facts exist but INDEX.md is missing — run agentboard fact reindex\n'
  fi
}

_fact_prune() {
  local apply=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1; shift ;;
      -h|--help) _fact_print_help; return 0 ;;
      *) die "Unknown flag for fact prune: $1" ;;
    esac
  done

  local today_str flagged=0 fid ftype ftitle fdomains fsev fstatus fexpires ffile
  today_str="$(today)"
  while IFS='|' read -r fid ftype ftitle fdomains fsev fstatus fexpires ffile; do
    [[ -n "$fid" ]] || continue
    [[ "$fexpires" != "—" && -n "$fexpires" ]] || continue
    # String compare works for ISO dates
    [[ "$fexpires" < "$today_str" || "$fexpires" == "$today_str" ]] || continue
    flagged=$((flagged + 1))
    if (( apply )); then
      replace_frontmatter_line "$ffile" "status" "expired"
      ok "Expired ${fid} — ${ftitle} ${C_DIM}(expired ${fexpires})${C_RESET}"
    else
      printf '  %s %s — %s %s(expires %s)%s\n' "$fid" "$ftype" "$ftitle" "$C_DIM" "$fexpires" "$C_RESET"
    fi
  done < <(_fact_rows active)

  if (( flagged == 0 )); then
    say "${C_DIM}  Nothing to prune — no active facts past expiry.${C_RESET}"
    return 0
  fi
  if (( apply )); then
    _fact_reindex --quiet
    ok "Pruned ${flagged} fact(s). Files kept (status: expired) — still greppable."
  else
    say "  ${C_DIM}${flagged} fact(s) past expiry. Run \`agentboard fact prune --apply\` to mark expired.${C_RESET}"
  fi
}
