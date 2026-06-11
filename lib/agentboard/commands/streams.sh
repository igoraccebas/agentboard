cmd_new_domain() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."
  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "Usage: agentboard new-domain <domain-slug> [repo-id ...] [--repo <repo-id>]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Domain slug must be kebab-case."

  local -a repo_ids=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ -n "${2:-}" ]] || die "new-domain requires a value after --repo"
        repo_ids+=("$2")
        shift 2
        ;;
      *)
        repo_ids+=("$1")
        shift
        ;;
    esac
  done
  ((${#repo_ids[@]})) || repo_ids=("repo-primary")

  local repo_ids_text repo_id repo_ids_literal
  repo_ids_text="$(printf '%s\n' "${repo_ids[@]}" | unique_nonempty_lines)"
  while IFS= read -r repo_id; do
    [[ -n "$repo_id" ]] || continue
    [[ "$repo_id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Repo ID '$repo_id' must be kebab-case."
  done <<< "$repo_ids_text"
  repo_ids_literal="$(frontmatter_inline_array <<< "$repo_ids_text")"

  local template="./.platform/domains/TEMPLATE.md"
  local target="./.platform/domains/${slug}.md"

  [[ -f "$template" ]] || die "$template not found. Update agentboard templates first."
  [[ ! -e "$target" ]] || die "$target already exists."

  mkdir -p "./.platform/domains"
  cp "$template" "$target"
  replace_template_literals "$target" \
    "<domain-slug>" "$slug" \
    "YYYY-MM-DD" "$(today)"
  replace_frontmatter_line "$target" "repo_ids" "$repo_ids_literal"

  ok "Created domain: .platform/domains/${slug}.md"
}

cmd_new_stream() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="${1:-}"
  shift || true
  [[ -n "$slug" ]] || die "Usage: agentboard new-stream <stream-slug> --domain <domain-slug> [--domain <domain-slug> ...] [--type feature] [--agent codex] [--repo repo-primary] [--repo <repo-id> ...]"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Stream slug must be kebab-case."

  local -a domain_slugs=()
  local stream_type="feature"
  local agent_owner="codex"
  local -a repo_ids=()
  local base_branch="" git_branch=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --domain"
        domain_slugs+=("$2")
        shift 2
        ;;
      --type)
        stream_type="${2:-}"
        shift 2
        ;;
      --agent)
        agent_owner="${2:-}"
        shift 2
        ;;
      --repo)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --repo"
        repo_ids+=("$2")
        shift 2
        ;;
      --base-branch)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --base-branch"
        base_branch="$2"
        shift 2
        ;;
      --branch)
        [[ -n "${2:-}" ]] || die "new-stream requires a value after --branch"
        git_branch="$2"
        shift 2
        ;;
      *)
        die "Unknown flag for new-stream: $1"
        ;;
    esac
  done

  ((${#domain_slugs[@]})) || die "new-stream requires at least one --domain <domain-slug>"
  ((${#repo_ids[@]})) || repo_ids=("repo-primary")

  # ── Branch resolution ────────────────────────────────────────────────────
  if [[ -z "$base_branch" || -z "$git_branch" ]]; then
    local _current_branch
    _current_branch="$(git -C . rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

    if [[ -t 0 ]]; then
      # Interactive: ask the user
      printf '\n  %s?%s %sBranch context for stream %s"%s"%s\n' \
        "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_RESET" "$slug" "$C_RESET" >&2
      [[ -n "$_current_branch" ]] && \
        printf '    %sCurrent branch: %s%s\n' "$C_DIM" "$_current_branch" "$C_RESET" >&2
      [[ -z "$base_branch" ]] && \
        base_branch="$(ask "Base branch to fork from" "${_current_branch:-develop}")"
      [[ -z "$git_branch" ]] && \
        git_branch="$(ask "New git branch name for this stream" "feature/${slug}")"
    else
      # Non-interactive: use current branch as base, feature/<slug> as branch
      [[ -z "$base_branch" ]] && base_branch="${_current_branch:-develop}"
      [[ -z "$git_branch" ]] && git_branch="feature/${slug}"
    fi
  fi

  local stream_template="./.platform/work/TEMPLATE.md"
  local stream_target="./.platform/work/${slug}.md"
  local active="./.platform/work/ACTIVE.md"
  local brief="./.platform/work/BRIEF.md"
  local project_name
  project_name="$(basename "$(pwd)")"

  [[ -f "$stream_template" ]] || die "$stream_template not found."
  [[ -f "$active" ]] || die "$active not found."
  [[ ! -e "$stream_target" ]] || die "$stream_target already exists."

  local domain_slugs_text domain_slug domain_file
  domain_slugs_text="$(printf '%s\n' "${domain_slugs[@]}" | unique_nonempty_lines)"
  while IFS= read -r domain_slug; do
    [[ -n "$domain_slug" ]] || continue
    [[ "$domain_slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Domain slug '$domain_slug' must be kebab-case."
    domain_file="./.platform/domains/${domain_slug}.md"
    [[ -f "$domain_file" ]] || die "$domain_file does not exist. Create the domain first."
  done <<< "$domain_slugs_text"

  local repo_ids_text repo_id
  repo_ids_text="$(printf '%s\n' "${repo_ids[@]}" | unique_nonempty_lines)"
  while IFS= read -r repo_id; do
    [[ -n "$repo_id" ]] || continue
    [[ "$repo_id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Repo ID '$repo_id' must be kebab-case."
  done <<< "$repo_ids_text"

  local domain_slugs_literal repo_ids_literal
  domain_slugs_literal="$(frontmatter_inline_array <<< "$domain_slugs_text")"
  repo_ids_literal="$(frontmatter_inline_array <<< "$repo_ids_text")"

  cp "$stream_template" "$stream_target"
  replace_template_literals "$stream_target" \
    "<stream-slug>" "$slug" \
    "type: feature" "type: $stream_type" \
    "agent_owner: claude-code" "agent_owner: $agent_owner" \
    "status: planning" "status: planning" \
    "YYYY-MM-DD" "$(today)"
  replace_frontmatter_line "$stream_target" "domain_slugs" "$domain_slugs_literal"
  replace_frontmatter_line "$stream_target" "repo_ids" "$repo_ids_literal"
  replace_frontmatter_line "$stream_target" "base_branch" "$base_branch"
  replace_frontmatter_line "$stream_target" "git_branch" "$git_branch"

  local row="| $slug | $stream_type | planning | $agent_owner | $(today) |"
  if grep -qF "| _(none)_ | — | — | — | — |" "$active"; then
    local tmp
    tmp="$(mktemp)"
    awk -v row="$row" '
      $0 == "| _(none)_ | — | — | — | — |" { print row; next }
      { print }
    ' "$active" > "$tmp"
    mv "$tmp" "$active"
  elif grep -qF "| $slug |" "$active"; then
    die "work/ACTIVE.md already has a row for '$slug'"
  else
    local tmp
    tmp="$(mktemp)"
    awk -v row="$row" '
      /^---$/ && !inserted { print row; inserted=1 }
      { print }
    ' "$active" > "$tmp"
    mv "$tmp" "$active"
  fi

  if brief_is_placeholder "$brief"; then
    write_brief_stub "$brief" "$project_name" "$slug" "$domain_slugs_text" "planning"
    ok "Updated work/BRIEF.md with a starter brief"
  else
    warn "work/BRIEF.md already has content. Stream created, but BRIEF.md was left untouched."
  fi

  ok "Created stream: .platform/work/${slug}.md"
  ok "Registered stream in .platform/work/ACTIVE.md"
}

cmd_resolve() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local target="${1:-}"
  [[ -n "$target" ]] || die "Usage: agentboard resolve <stream-slug|stream-id|domain-slug|domain-id|repo-id>"

  local repos_file="./.platform/repos.md"
  local repo_rows=""
  [[ -f "$repos_file" ]] && repo_rows="$(repo_rows_from_registry "$repos_file")"

  local stream_file=""
  if [[ -f "./.platform/work/${target}.md" ]]; then
    stream_file="./.platform/work/${target}.md"
  else
    stream_file="$(stream_file_by_id "$target" 2>/dev/null || true)"
  fi

  if [[ -n "$stream_file" ]]; then
    local slug type stream_id repo_ids domain_slugs
    slug="$(basename "$stream_file" .md)"
    type="$(frontmatter_value "$stream_file" "type")"
    stream_id="$(frontmatter_value "$stream_file" "stream_id")"
    repo_ids="$(frontmatter_value "$stream_file" "repo_ids")"
    domain_slugs="$(frontmatter_value "$stream_file" "domain_slugs")"

    printf '\n%s%sagentboard resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "stream"
    printf '  id:   %s\n' "${stream_id:-$(canonical_stream_id "$slug")}"
    printf '  slug: %s\n' "$slug"
    printf '  file: .platform/work/%s.md\n' "$slug"
    printf '  kind: %s\n' "${type:-unknown}"
    if [[ -n "$(inline_array_items "$domain_slugs")" ]]; then
      printf '  domains: %s\n' "$(inline_array_items "$domain_slugs" | join_lines_comma)"
    fi
    if [[ -n "$(inline_array_items "$repo_ids")" ]]; then
      printf '  repos:   %s\n' "$(inline_array_items "$repo_ids" | join_lines_comma)"
    fi
    say
    return 0
  fi

  local domain_file=""
  if [[ -f "./.platform/domains/${target}.md" ]]; then
    domain_file="./.platform/domains/${target}.md"
  else
    domain_file="$(domain_file_by_id "$target" 2>/dev/null || true)"
  fi

  if [[ -n "$domain_file" ]]; then
    local slug domain_id repo_ids
    slug="$(basename "$domain_file" .md)"
    domain_id="$(frontmatter_value "$domain_file" "domain_id")"
    repo_ids="$(frontmatter_value "$domain_file" "repo_ids")"

    printf '\n%s%sagentboard resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "domain"
    printf '  id:   %s\n' "${domain_id:-$(canonical_domain_id "$slug")}"
    printf '  slug: %s\n' "$slug"
    printf '  file: .platform/domains/%s.md\n' "$slug"
    if [[ -n "$(inline_array_items "$repo_ids")" ]]; then
      printf '  repos: %s\n' "$(inline_array_items "$repo_ids" | join_lines_comma)"
    fi
    say
    return 0
  fi

  local repo_row=""
  repo_row="$(repo_row_for_id "$repo_rows" "$target" 2>/dev/null || true)"
  if [[ -n "$repo_row" ]]; then
    local repo_name repo_path repo_stack repo_ref
    IFS='|' read -r repo_name repo_path repo_stack repo_ref <<< "$repo_row"

    printf '\n%s%sagentboard resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "repo"
    printf '  id:   %s\n' "$repo_name"
    printf '  path: %s\n' "${repo_path:-unknown}"
    printf '  stack:%s %s\n' "${repo_stack:+ }" "${repo_stack:-unknown}"
    if [[ -n "$repo_ref" ]] && ! is_placeholder_value "$repo_ref"; then
      printf '  deep reference: .platform/%s\n' "$repo_ref"
    fi
    say
    return 0
  fi

  if [[ "$target" == "repo-primary" ]]; then
    printf '\n%s%sagentboard resolve%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  type: %s\n' "repo"
    printf '  id:   %s\n' "repo-primary"
    printf '  path: %s\n' "."
    printf '  stack: %s\n' "(see .platform/repos.md or activation output)"
    say
    return 0
  fi

  die "Could not resolve '$target' as a stream, domain, or repo id."
}

cmd_handoff() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local requested_slug="" budget_arg="" budget=0
  if [[ -n "${1:-}" && "${1:0:2}" != "--" ]]; then
    requested_slug="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --budget)
        [[ -n "${2:-}" ]] || die "handoff requires a value after --budget"
        budget_arg="$2"
        budget="$(parse_token_budget "$2")" || die "Invalid --budget '$2' (use e.g. 4000 or 4k)"
        shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage: agentboard handoff [<stream-slug>] [--budget <N|Nk>]

Prints the load order for the next agent's context pack.
--budget trims secondary domains when the estimated token total exceeds the
limit. Estimation uses bytes/4 as a rough heuristic (zero dependencies).
EOF
        return 0 ;;
      *) die "Unknown flag for handoff: $1" ;;
    esac
  done

  local active="./.platform/work/ACTIVE.md"
  local brief="./.platform/work/BRIEF.md"
  local repos_file="./.platform/repos.md"
  [[ -f "$active" ]] || die "$active not found."
  [[ -f "$brief" ]] || die "$brief not found."

  local rows
  rows="$(stream_rows_from_active "$active")"
  local repo_rows=""
  [[ -f "$repos_file" ]] && repo_rows="$(repo_rows_from_registry "$repos_file")"

  local slug="" type="" status="" agent="" updated=""
  if [[ -n "$requested_slug" ]]; then
    local matched_row=""
    matched_row="$(printf '%s\n' "$rows" | awk -F'|' -v slug="$requested_slug" '$1 == slug { print; exit }')"
    if [[ -n "$matched_row" ]]; then
      IFS='|' read -r slug type status agent updated <<< "$matched_row"
    else
      local stream_file="./.platform/work/${requested_slug}.md"
      [[ -f "$stream_file" ]] || die "Stream '$requested_slug' is not active and .platform/work/${requested_slug}.md does not exist."
      slug="$requested_slug"
      type="$(frontmatter_value "$stream_file" "type")"
      status="$(frontmatter_value "$stream_file" "status")"
      agent="$(frontmatter_value "$stream_file" "agent_owner")"
      updated="$(frontmatter_value "$stream_file" "updated_at")"
    fi
  else
    local count=0
    [[ -n "$rows" ]] && count="$(printf '%s\n' "$rows" | awk 'NF { c++ } END { print c + 0 }')"
    if (( count == 0 )); then
      die "No active streams found. Use 'agentboard new-stream ...' or update .platform/work/ACTIVE.md first."
    elif (( count > 1 )); then
      warn "Multiple active streams found:"
      printf '%s\n' "$rows" | awk -F'|' '{ printf "  - %s (%s, %s)\n", $1, $2, $3 }' >&2
      die "Usage: agentboard handoff <stream-slug>"
    else
      IFS='|' read -r slug type status agent updated <<< "$rows"
    fi
  fi

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found."

  local next_action
  next_action="$(stream_next_action "$stream_file")"
  [[ -n "$next_action" ]] || next_action="(not set)"

  local build_excerpt current_excerpt do_not_load
  build_excerpt="$(markdown_section_excerpt "$brief" "## What we're building")"
  current_excerpt="$(markdown_section_excerpt "$brief" "## Current state")"
  do_not_load="$(sed -n 's/^\*\*Do not load:\*\* //p' "$brief")"
  do_not_load="${do_not_load%%$'\n'*}"

  printf '\n%s%sagentboard handoff%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '  stream: %s%s%s\n' "$C_BOLD" "$slug" "$C_RESET"
  printf '  id:     %s\n' "$(frontmatter_value "$stream_file" "stream_id")"
  printf '  type:   %s\n' "${type:-unknown}"
  printf '  status: %s\n' "${status:-unknown}"
  printf '  owner:  %s\n' "${agent:-unknown}"
  printf '  updated:%s %s\n' "${updated:+ }" "${updated:-unknown}"

  local _today _stream_updated
  _today="$(today)"
  _stream_updated="$(frontmatter_value "$stream_file" "updated_at")"
  if [[ -n "$_stream_updated" && "$_stream_updated" != "$_today" ]] && ! is_placeholder_value "$_stream_updated"; then
    printf '  %s⚠%s  %sStream state last updated %s — run %sagentboard checkpoint %s%s before handoff%s\n' \
      "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$_stream_updated" "$C_BOLD" "$slug" "$C_RESET$C_YELLOW" "$C_RESET"
  fi

  local _git_branch _base_branch
  _git_branch="$(frontmatter_value "$stream_file" "git_branch")"
  _base_branch="$(frontmatter_value "$stream_file" "base_branch")"
  if [[ -n "$_git_branch" ]] && ! is_placeholder_value "$_git_branch"; then
    printf '  branch: %s%s%s' "$C_BOLD" "$_git_branch" "$C_RESET"
    [[ -n "$_base_branch" ]] && ! is_placeholder_value "$_base_branch" && \
      printf '  %s(forked from %s)%s' "$C_DIM" "$_base_branch" "$C_RESET"
    printf '\n'
    printf '  %s⚡ git checkout %s%s\n' "$C_DIM" "$_git_branch" "$C_RESET"
  fi
  say

  local brief_tokens stream_tokens running_tokens
  brief_tokens="$(estimate_tokens_for_file "$brief")"
  stream_tokens="$(estimate_tokens_for_file "$stream_file")"
  running_tokens=$(( brief_tokens + stream_tokens ))

  local -a included_domains=() skipped_domains=()
  local -a domain_token_cache=()
  local domain_slug domain_file domain_tokens first_domain=1
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    domain_file="./.platform/domains/${domain_slug}.md"
    domain_tokens="$(estimate_tokens_for_file "$domain_file")"
    if (( budget > 0 )) && (( first_domain == 0 )) && (( running_tokens + domain_tokens > budget )); then
      skipped_domains+=("${domain_slug}|${domain_tokens}")
    else
      included_domains+=("${domain_slug}|${domain_tokens}")
      running_tokens=$(( running_tokens + domain_tokens ))
      first_domain=0
    fi
  done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")

  if (( budget > 0 )); then
    printf '%sLoad in this order%s %s(budget %s tokens, using ~%d)%s\n' \
      "$C_BOLD" "$C_RESET" "$C_DIM" "$budget_arg" "$running_tokens" "$C_RESET"
  else
    printf '%sLoad in this order:%s\n' "$C_BOLD" "$C_RESET"
  fi
  printf '  1. .platform/work/BRIEF.md%s\n' "$( (( budget > 0 )) && printf '  (~%d)' "$brief_tokens" )"
  printf '  2. .platform/work/%s.md%s\n' "$slug" "$( (( budget > 0 )) && printf '  (~%d)' "$stream_tokens" )"
  local entry idx=3 e_slug e_tokens
  for entry in "${included_domains[@]}"; do
    e_slug="${entry%%|*}"; e_tokens="${entry#*|}"
    printf '  %d. .platform/domains/%s.md%s\n' "$idx" "$e_slug" \
      "$( (( budget > 0 )) && printf '  (~%d)' "$e_tokens" )"
    idx=$((idx + 1))
  done
  say

  if (( ${#skipped_domains[@]} > 0 )); then
    printf '%sSkipped (budget tight):%s\n' "$C_BOLD" "$C_RESET"
    for entry in "${skipped_domains[@]}"; do
      e_slug="${entry%%|*}"; e_tokens="${entry#*|}"
      printf '  - .platform/domains/%s.md  %s(~%d tokens)%s\n' \
        "$e_slug" "$C_DIM" "$e_tokens" "$C_RESET"
    done
    say
  fi

  _handoff_relevant_facts "$stream_file" "$budget" "$running_tokens"

  local repo_scope=""
  repo_scope="$(inline_array_items "$(frontmatter_value "$stream_file" "repo_ids")")"
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    local domain_file="./.platform/domains/${domain_slug}.md"
    [[ -f "$domain_file" ]] || continue
    repo_scope="${repo_scope}"$'\n'"$(inline_array_items "$(frontmatter_value "$domain_file" "repo_ids")")"
  done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")
  repo_scope="$(printf '%s\n' "$repo_scope" | awk 'NF && !seen[$0]++')"

  if [[ -n "$repo_scope" ]]; then
    local repo_id repo_row repo_name repo_path repo_stack repo_ref
    printf '%sRepos in scope:%s\n' "$C_BOLD" "$C_RESET"
    while IFS= read -r repo_id; do
      [[ -z "$repo_id" ]] && continue
      repo_row="$(repo_row_for_id "$repo_rows" "$repo_id")"
      if [[ -n "$repo_row" ]]; then
        IFS='|' read -r repo_name repo_path repo_stack repo_ref <<< "$repo_row"
        if [[ -n "$repo_ref" ]] && ! is_placeholder_value "$repo_ref"; then
          printf '  - %s -> %s (%s; deep ref: .platform/%s)\n' "$repo_id" "${repo_path:-unknown path}" "${repo_stack:-unknown stack}" "$repo_ref"
        else
          printf '  - %s -> %s (%s)\n' "$repo_id" "${repo_path:-unknown path}" "${repo_stack:-unknown stack}"
        fi
      elif [[ "$repo_id" == "repo-primary" ]]; then
        printf '  - %s -> . (current repo)\n' "$repo_id"
      else
        printf '  - %s -> (not found in .platform/repos.md)\n' "$repo_id"
      fi
    done <<< "$repo_scope"
    say
  fi

  local r_updated r_what r_focus r_next r_blockers
  r_updated="$(stream_resume_field "$stream_file" "Last updated")"
  r_what="$(stream_resume_field "$stream_file" "What just happened")"
  r_focus="$(stream_resume_field "$stream_file" "Current focus")"
  r_next="$(stream_resume_field "$stream_file" "Next action")"
  r_blockers="$(stream_resume_field "$stream_file" "Blockers")"

  _is_resume_placeholder() {
    local v="$1"
    [[ -z "$v" ]] && return 0
    [[ "$v" == "—" ]] && return 0
    [[ "$v" == "_not set_" ]] && return 0
    [[ "$v" == "— by —" ]] && return 0
    return 1
  }

  if ! _is_resume_placeholder "$r_what" || ! _is_resume_placeholder "$r_next"; then
    printf '%sResume state%s %s(from %s.md § Resume state)%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$slug" "$C_RESET"
    _is_resume_placeholder "$r_updated" || printf '  Last updated:       %s\n' "$r_updated"
    _is_resume_placeholder "$r_what"    || printf '  What just happened: %s\n' "$r_what"
    _is_resume_placeholder "$r_focus"   || printf '  Current focus:      %s\n' "$r_focus"
    _is_resume_placeholder "$r_next"    || printf '  Next action:        %s%s%s\n' "$C_BOLD" "$r_next" "$C_RESET"
    _is_resume_placeholder "$r_blockers" || printf '  Blockers:           %s\n' "$r_blockers"
    say
  else
    printf '%sNext action:%s %s\n' "$C_BOLD" "$C_RESET" "$next_action"
    if [[ -n "$build_excerpt" ]]; then
      say
      printf '%sWhat we are building:%s\n' "$C_BOLD" "$C_RESET"
      printf '%s\n' "$build_excerpt"
    fi
    if [[ -n "$current_excerpt" ]]; then
      say
      printf '%sCurrent state:%s\n' "$C_BOLD" "$C_RESET"
      printf '%s\n' "$current_excerpt"
    fi
    if [[ -n "$do_not_load" && "$do_not_load" != "_TODO_" ]]; then
      say
      printf '%sDo not load:%s %s\n' "$C_BOLD" "$C_RESET" "$do_not_load"
    fi
    say
  fi

  printf '%sFor the agent reading this:%s\n' "$C_BOLD" "$C_RESET"
  printf '  1. Load the files above in that order. Stop once the job is clear.\n'
  printf '  2. Read the stream file and its "## Resume state" block first — it is the compact "where we are".\n'
  printf '  3. Confirm you understand Next action, then continue from there.\n'
  printf '  4. Before ending your session or switching providers, run:\n'
  printf '     %sagentboard checkpoint %s --what "..." --next "..."%s\n' "$C_BOLD" "$slug" "$C_RESET"
  say
}

