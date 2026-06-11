cmd_doctor() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local errors=0 warnings=0
  local brief="./.platform/work/BRIEF.md"
  local active="./.platform/work/ACTIVE.md"
  local domains_dir="./.platform/domains"
  local sync_script="./.platform/scripts/sync-context.sh"
  local root_claude="./CLAUDE.md"
  local repos_file="./.platform/repos.md"
  local is_hub=0
  local repo_rows=""

  if [[ -f "$root_claude" ]] && grep -q "PLATFORM BRAINS HUB" "$root_claude"; then
    is_hub=1
  fi

  if [[ -f "$repos_file" ]]; then
    repo_rows="$(repo_rows_from_registry "$repos_file")"
  fi

  printf '\n%s%sagentboard doctor%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"

  if [[ -f "$brief" ]]; then
    ok "work/BRIEF.md present"
  else
    warn "Missing .platform/work/BRIEF.md"
    errors=$((errors + 1))
  fi

  if [[ -f "$active" ]]; then
    ok "work/ACTIVE.md present"
  else
    warn "Missing .platform/work/ACTIVE.md"
    errors=$((errors + 1))
  fi

  if [[ -d "$domains_dir" ]]; then
    ok "domains/ directory present"
  else
    warn "Missing .platform/domains/"
    errors=$((errors + 1))
  fi

  if [[ -f "$root_claude" ]] && grep -q "NOT YET ACTIVATED" "$root_claude"; then
    ok "Activation stub detected — sync check skipped until activation"
  elif [[ -x "$sync_script" ]]; then
    local sync_output=""
    if sync_output="$("$sync_script" 2>&1)"; then
      ok "Root entry files in sync"
    else
      warn "Entry file drift detected by sync-context.sh"
      printf '%s\n' "$sync_output" >&2
      warnings=$((warnings + 1))
    fi
  else
    warn "sync-context.sh missing or not executable"
    warnings=$((warnings + 1))
  fi

  local seen_stream_ids="" seen_domain_ids=""
  local stream_file stream_slug stream_id
  while IFS= read -r stream_file; do
    [[ -n "$stream_file" ]] || continue
    stream_slug="$(basename "$stream_file" .md)"

    if is_legacy_stream_file "$stream_file"; then
      warn "Stream '$stream_slug' uses the legacy pre-frontmatter format. Add metadata when you touch it next."
      warnings=$((warnings + 1))
      continue
    fi

    stream_id="$(frontmatter_value "$stream_file" "stream_id")"

    if is_placeholder_value "$stream_id"; then
      warn "Stream '$stream_slug' is missing frontmatter key 'stream_id'"
      errors=$((errors + 1))
      continue
    fi

    if [[ "$stream_id" != "$(canonical_stream_id "$stream_slug")" ]]; then
      warn "Stream '$stream_slug' has non-canonical stream_id '$stream_id' (expected '$(canonical_stream_id "$stream_slug")')"
      errors=$((errors + 1))
    fi

    if printf '%s\n' "$seen_stream_ids" | grep -Fxq "$stream_id"; then
      warn "Duplicate stream_id '$stream_id' detected"
      errors=$((errors + 1))
    else
      seen_stream_ids="${seen_stream_ids}"$'\n'"$stream_id"
    fi
  done < <(stream_files)

  local domain_file domain_slug domain_id
  while IFS= read -r domain_file; do
    [[ -n "$domain_file" ]] || continue
    domain_slug="$(basename "$domain_file" .md)"

    if is_legacy_domain_file "$domain_file"; then
      warn "Domain '$domain_slug' uses the legacy pre-frontmatter format. Add metadata when you touch it next."
      warnings=$((warnings + 1))
      continue
    fi

    domain_id="$(frontmatter_value "$domain_file" "domain_id")"

    if is_placeholder_value "$domain_id"; then
      warn "Domain '$domain_slug' is missing frontmatter key 'domain_id'"
      errors=$((errors + 1))
      continue
    fi

    if [[ "$domain_id" != "$(canonical_domain_id "$domain_slug")" ]]; then
      warn "Domain '$domain_slug' has non-canonical domain_id '$domain_id' (expected '$(canonical_domain_id "$domain_slug")')"
      errors=$((errors + 1))
    fi

    if printf '%s\n' "$seen_domain_ids" | grep -Fxq "$domain_id"; then
      warn "Duplicate domain_id '$domain_id' detected"
      errors=$((errors + 1))
    else
      seen_domain_ids="${seen_domain_ids}"$'\n'"$domain_id"
    fi
  done < <(domain_files)

  if [[ -f "$active" ]]; then
    local stream_rows=""
    stream_rows="$(stream_rows_from_active "$active" | awk -F'|' '{ printf "%s|%s|%s|%s\n", $1, $2, $3, $4 }')"

    if [[ -z "$stream_rows" ]]; then
      ok "No active streams registered"
    else
      local slug row_type row_status row_agent stream_file value
      while IFS='|' read -r slug row_type row_status row_agent; do
        [[ -z "$slug" ]] && continue
        stream_file="./.platform/work/${slug}.md"

        if [[ ! -f "$stream_file" ]]; then
          warn "Active stream '$slug' is missing file .platform/work/${slug}.md"
          errors=$((errors + 1))
          continue
        fi

        ok "Found stream file for '$slug'"

        if is_legacy_stream_file "$stream_file"; then
          local legacy_type legacy_status legacy_agent
          legacy_type="$(legacy_stream_value "$stream_file" "Type")"
          legacy_status="$(legacy_stream_value "$stream_file" "Status")"
          legacy_agent="$(legacy_stream_value "$stream_file" "Agent")"

          [[ -n "$legacy_type" && "$legacy_type" != "$row_type" ]] && {
            warn "Legacy stream '$slug' type mismatch: ACTIVE.md='$row_type' stream='$legacy_type'"
            warnings=$((warnings + 1))
          }
          [[ -n "$legacy_status" && "$legacy_status" != "$row_status" ]] && {
            warn "Legacy stream '$slug' status mismatch: ACTIVE.md='$row_status' stream='$legacy_status'"
            warnings=$((warnings + 1))
          }
          [[ -n "$legacy_agent" && "$legacy_agent" != "$row_agent" ]] && {
            warn "Legacy stream '$slug' agent mismatch: ACTIVE.md='$row_agent' stream='$legacy_agent'"
            warnings=$((warnings + 1))
          }
          continue
        fi

        local stream_keys=(stream_id slug type status agent_owner domain_slugs repo_ids created_at updated_at closure_approved)
        local key
        for key in "${stream_keys[@]}"; do
          value="$(frontmatter_value "$stream_file" "$key")"
          case "$key" in
            domain_slugs|repo_ids)
              if [[ -z "$(inline_array_items "$value")" ]]; then
                warn "Stream '$slug' is missing non-empty frontmatter key '$key'"
                errors=$((errors + 1))
              fi
              ;;
            closure_approved)
              if [[ "$value" != "true" && "$value" != "false" ]]; then
                warn "Stream '$slug' has invalid closure_approved value '$value'"
                errors=$((errors + 1))
              fi
              ;;
            *)
              if is_placeholder_value "$value"; then
                warn "Stream '$slug' is missing frontmatter key '$key'"
                errors=$((errors + 1))
              fi
              ;;
          esac
        done

        value="$(frontmatter_value "$stream_file" "slug")"
        if [[ -n "$value" && "$value" != "$slug" ]]; then
          warn "Stream '$slug' has slug '$value' in frontmatter"
          errors=$((errors + 1))
        fi

        value="$(frontmatter_value "$stream_file" "status")"
        if [[ -n "$value" && "$value" != "$row_status" ]]; then
          warn "Stream '$slug' status mismatch: ACTIVE.md='$row_status' stream='$value'"
          errors=$((errors + 1))
        fi

        value="$(frontmatter_value "$stream_file" "agent_owner")"
        if [[ -n "$row_agent" && "$row_agent" != "—" && -n "$value" && "$value" != "$row_agent" ]]; then
          warn "Stream '$slug' agent mismatch: ACTIVE.md='$row_agent' stream='$value'"
          warnings=$((warnings + 1))
        fi

        local repo_id repo_row
        while IFS= read -r repo_id; do
          [[ -z "$repo_id" ]] && continue
          repo_row="$(repo_row_for_id "$repo_rows" "$repo_id")"
          if [[ -n "$repo_row" ]]; then
            continue
          fi
          if (( is_hub )) || [[ "$repo_id" != "repo-primary" ]]; then
            warn "Stream '$slug' references repo_id '$repo_id' that is not defined in .platform/repos.md"
            errors=$((errors + 1))
          fi
        done < <(inline_array_items "$(frontmatter_value "$stream_file" "repo_ids")")

        local domain_slug domain_file domain_value
        while IFS= read -r domain_slug; do
          [[ -z "$domain_slug" ]] && continue
          domain_file="./.platform/domains/${domain_slug}.md"
          if [[ ! -f "$domain_file" ]]; then
            warn "Stream '$slug' references missing domain file .platform/domains/${domain_slug}.md"
            errors=$((errors + 1))
            continue
          fi

          local domain_keys=(domain_id slug status repo_ids created_at updated_at)
          for key in "${domain_keys[@]}"; do
            domain_value="$(frontmatter_value "$domain_file" "$key")"
            case "$key" in
              repo_ids)
                if [[ -z "$(inline_array_items "$domain_value")" ]]; then
                  warn "Domain '$domain_slug' is missing non-empty frontmatter key '$key'"
                  errors=$((errors + 1))
                fi
                ;;
              *)
                if is_placeholder_value "$domain_value"; then
                  warn "Domain '$domain_slug' is missing frontmatter key '$key'"
                  errors=$((errors + 1))
                fi
                ;;
            esac
          done

          domain_value="$(frontmatter_value "$domain_file" "slug")"
          if [[ -n "$domain_value" && "$domain_value" != "$domain_slug" ]]; then
            warn "Domain '$domain_slug' has slug '$domain_value' in frontmatter"
            errors=$((errors + 1))
          fi

          while IFS= read -r repo_id; do
            [[ -z "$repo_id" ]] && continue
            repo_row="$(repo_row_for_id "$repo_rows" "$repo_id")"
            if [[ -n "$repo_row" ]]; then
              continue
            fi
            if (( is_hub )) || [[ "$repo_id" != "repo-primary" ]]; then
              warn "Domain '$domain_slug' references repo_id '$repo_id' that is not defined in .platform/repos.md"
              errors=$((errors + 1))
            fi
          done < <(inline_array_items "$(frontmatter_value "$domain_file" "repo_ids")")
        done < <(inline_array_items "$(frontmatter_value "$stream_file" "domain_slugs")")
      done <<< "$stream_rows"
    fi
  fi

  if [[ -f "$brief" ]] && ! brief_is_placeholder "$brief"; then
    if is_legacy_brief_file "$brief"; then
      warn "work/BRIEF.md uses the legacy multi-stream format. Keep using it for now, or run 'agentboard brief-upgrade <stream-slug> --apply' when you settle on one active feature brief."
      warnings=$((warnings + 1))
    else
    local brief_stream=""
    brief_stream="$(sed -n 's/^\*\*Stream file:\*\* `work\/\([^`]*\)\.md`$/\1/p' "$brief")"
    brief_stream="${brief_stream%%$'\n'*}"
    if [[ -z "$brief_stream" ]]; then
      warn "work/BRIEF.md is missing a valid Stream file reference"
      warnings=$((warnings + 1))
    elif [[ ! -f "./.platform/work/${brief_stream}.md" ]]; then
      warn "work/BRIEF.md references missing stream file .platform/work/${brief_stream}.md"
      errors=$((errors + 1))
    fi

    local brief_domain_count=0
    local brief_domain
    while IFS= read -r brief_domain; do
      [[ -z "$brief_domain" ]] && continue
      brief_domain_count=$((brief_domain_count + 1))
      if [[ ! -f "./.platform/domains/${brief_domain}.md" ]]; then
        warn "work/BRIEF.md references missing domain file .platform/domains/${brief_domain}.md"
        errors=$((errors + 1))
      fi
    done < <(sed -n 's/^- `\.platform\/domains\/\([^` ]*\)\.md`.*$/\1/p' "$brief")

    if (( brief_domain_count == 0 )); then
      warn "work/BRIEF.md has no concrete domain references"
      warnings=$((warnings + 1))
    fi
    fi
  fi

  if (( is_hub )) && [[ -f "$repos_file" ]]; then
    if [[ -z "$repo_rows" ]]; then
      warn "Hub mode detected but .platform/repos.md has no repo rows"
      errors=$((errors + 1))
    else
      local seen_repo_ids=""
      local repo_name repo_path repo_stack repo_ref resolved_path
      while IFS='|' read -r repo_name repo_path repo_stack repo_ref; do
        [[ -z "$repo_name" ]] && continue

        if [[ "$repo_name" =~ ^_repo- || "$repo_path" =~ \.\./repo- ]]; then
          warn "Hub repos.md still contains placeholder row '$repo_name'"
          errors=$((errors + 1))
          continue
        fi

        if [[ ! "$repo_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
          warn "Hub repo id '$repo_name' must be kebab-case"
          errors=$((errors + 1))
        fi

        if printf '%s\n' "$seen_repo_ids" | grep -Fxq "$repo_name"; then
          warn "Duplicate repo id '$repo_name' in .platform/repos.md"
          errors=$((errors + 1))
        else
          seen_repo_ids="${seen_repo_ids}"$'\n'"$repo_name"
        fi

        resolved_path="$(resolve_repo_path "$repos_file" "$repo_path" 2>/dev/null)" || resolved_path=""
        if [[ -z "$resolved_path" || ! -d "$resolved_path" ]]; then
          warn "Hub repo path '$repo_path' for '$repo_name' does not exist"
          errors=$((errors + 1))
          continue
        fi

        if is_placeholder_value "$repo_ref"; then
          warn "Hub repo '$repo_name' is missing a concrete deep reference file"
          warnings=$((warnings + 1))
        elif [[ ! -f "./.platform/$repo_ref" ]]; then
          warn "Hub repo '$repo_name' deep reference file .platform/$repo_ref does not exist"
          warnings=$((warnings + 1))
        fi

        if [[ -x "$sync_script" ]] && ! grep -Fq "\"$repo_path\"" "$sync_script" && ! grep -Fq "\"$resolved_path\"" "$sync_script"; then
          warn "Hub repo '$repo_name' is not listed in scripts/sync-context.sh REPOS array"
          warnings=$((warnings + 1))
        fi
      done <<< "$repo_rows"
    fi
  fi

  if [[ -d "./.platform/memory/facts" ]]; then
    local fact_kind fact_msg fact_issues=0
    while IFS='|' read -r fact_kind fact_msg; do
      [[ -n "$fact_kind" ]] || continue
      fact_issues=$((fact_issues + 1))
      warn "$fact_msg"
      if [[ "$fact_kind" == "E" ]]; then
        errors=$((errors + 1))
      else
        warnings=$((warnings + 1))
      fi
    done < <(fact_validate_all)
    (( fact_issues == 0 )) && ok "memory/facts validate (frontmatter, enums, domain refs)"
  fi

  say
  if (( errors > 0 )); then
    printf '%s%sDoctor found issues%s\n' "$C_BOLD" "$C_RED" "$C_RESET"
    printf '  errors: %s%d%s   warnings: %s%d%s\n' \
      "$C_BOLD" "$errors" "$C_RESET" \
      "$C_BOLD" "$warnings" "$C_RESET"
    say
    return 1
  fi

  printf '%s%sDoctor passed%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
  printf '  errors: %s0%s   warnings: %s%d%s\n' \
    "$C_BOLD" "$C_RESET" \
    "$C_BOLD" "$warnings" "$C_RESET"
  say
}

