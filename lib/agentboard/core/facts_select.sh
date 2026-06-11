# facts_select.sh — the read path for fact memory.
#
# One idea: decide WHICH facts a session should load. Selection is domain-
# scoped (a billing stream never pays tokens for auth gotchas) with one
# override: red gotchas always surface, that's what "never-forget" means.
# Writing facts lives in commands/facts.sh; this file only reads.

# active_stream_domains — union of domain_slugs across all open streams,
# one per line. Used by brief to decide which facts are "relevant today".
active_stream_domains() {
  local file status
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    has_frontmatter "$file" || continue
    status="$(frontmatter_value "$file" "status")"
    case "$status" in done|archived|closed) continue ;; esac
    inline_array_items "$(frontmatter_value "$file" "domain_slugs")"
  done < <(stream_files) | unique_nonempty_lines
}

# fact_domains_intersect <fact-domains-inline> <relevant-domains-newline>
# True when the fact is untagged (applies everywhere) or shares a domain.
fact_domains_intersect() {
  local fact_domains="$1" relevant="$2" d
  local items
  items="$(inline_array_items "$fact_domains")"
  [[ -z "$items" ]] && return 0
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    printf '%s\n' "$relevant" | grep -qx "$d" && return 0
  done <<< "$items"
  return 1
}

# facts_relevant_to_domains <relevant-domains-newline>
# Emits fact rows (same shape as _fact_rows) that a session working on those
# domains should know: red gotchas unconditionally, everything else only on
# domain intersection.
facts_relevant_to_domains() {
  local relevant="$1"
  local fid ftype ftitle fdomains fsev fstatus fexpires ffile
  while IFS='|' read -r fid ftype ftitle fdomains fsev fstatus fexpires ffile; do
    [[ -n "$fid" ]] || continue
    if [[ "$ftype" == "gotcha" && "$fsev" == "red" ]]; then
      printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$fid" "$ftype" "$ftitle" "$fdomains" "$fsev" "$fstatus" "$fexpires" "$ffile"
      continue
    fi
    fact_domains_intersect "$fdomains" "$relevant" || continue
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$fid" "$ftype" "$ftitle" "$fdomains" "$fsev" "$fstatus" "$fexpires" "$ffile"
  done < <(_fact_rows active)
}

# _handoff_relevant_facts <stream_file> <budget> <running_tokens>
# Prints the "Relevant facts" block of a handoff packet: facts scoped to the
# stream's domains, cheapest-context-first, trimmed when a budget is set.
_handoff_relevant_facts() {
  local stream_file="$1" budget="$2" running_tokens="$3"
  local relevant
  relevant="$(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")"

  local fid ftype ftitle fdomains fsev fstatus fexpires ffile
  local fact_tokens shown=0 skipped=0
  local rows
  rows="$(facts_relevant_to_domains "$relevant")"
  [[ -n "$rows" ]] || return 0

  printf '%sRelevant facts%s %s(.platform/memory/INDEX.md has the full list)%s\n' \
    "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  while IFS='|' read -r fid ftype ftitle fdomains fsev fstatus fexpires ffile; do
    [[ -n "$fid" ]] || continue
    fact_tokens="$(estimate_tokens_for_file "$ffile")"
    if (( budget > 0 )) && (( running_tokens + fact_tokens > budget )); then
      skipped=$((skipped + 1))
      continue
    fi
    running_tokens=$(( running_tokens + fact_tokens ))
    printf '  - %s %s [%s] %s%s\n' \
      "$fid" "$(_fact_severity_emoji "$fsev")" "$ftype" "$ftitle" \
      "$( (( budget > 0 )) && printf '  (~%d)' "$fact_tokens" )"
    shown=$((shown + 1))
  done <<< "$rows"
  (( skipped > 0 )) && printf '  %s... %d more trimmed by budget — see INDEX.md%s\n' \
    "$C_DIM" "$skipped" "$C_RESET"
  say
}
