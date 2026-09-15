cmd_update() {
  local dry_run=0
  for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && dry_run=1
  done

  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."
  require_templates

  printf '\n%s%sagentboard update%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  if (( dry_run )); then
    printf '%s  Dry-run mode — no files will be changed.%s\n' "$C_DIM" "$C_RESET"
  fi
  say

  local updated=0 added=0 skipped=0

  # -------------------------------------------------------------------------
  # PROCESS FILES — always replace with latest template version.
  # These contain only workflow/process instructions — zero project-specific
  # data. Safe to overwrite on every update.
  # -------------------------------------------------------------------------
  head "Process files (replace with latest)"

  local pf
  for pf in \
    "workflow.md" \
    "ONBOARDING.md" \
    "ACTIVATE.md" \
    "ACTIVATE-HUB.md" \
    "work/TEMPLATE.md" \
    "domains/TEMPLATE.md"; do
    local src="$TEMPLATES_PLATFORM/$pf"
    local dst="./.platform/$pf"
    [[ -f "$src" ]] || continue  # template doesn't have this file
    [[ -f "$dst" ]] || continue  # project doesn't have this file (e.g. hub-only)
    if (( dry_run )); then
      printf '  %s~%s %s\n' "$C_YELLOW" "$C_RESET" "$pf"
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      printf '  %s↻%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$pf" "$C_RESET"
    fi
    updated=$((updated + 1))
  done

  # conventions/*.md — upsert: update existing AND add new ones
  if [[ -d "$TEMPLATES_PLATFORM/conventions" ]]; then
    local csrc
    for csrc in "$TEMPLATES_PLATFORM/conventions"/*.md; do
      [[ -f "$csrc" ]] || continue  # glob matched nothing (empty dir) — skip
      local cfname; cfname="$(basename "$csrc")"
      local cdst="./.platform/conventions/$cfname"
      local conv_is_new=0
      [[ -f "$cdst" ]] || conv_is_new=1
      if (( dry_run )); then
        if (( conv_is_new )); then
          printf '  %s+%s conventions/%s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$cfname" "$C_DIM" "$C_RESET"
        else
          printf '  %s~%s conventions/%s\n' "$C_YELLOW" "$C_RESET" "$cfname"
        fi
      else
        mkdir -p "./.platform/conventions"
        cp "$csrc" "$cdst"
        if (( conv_is_new )); then
          printf '  %s+%s %sconventions/%s%s  %s(new)%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$cfname" "$C_RESET" "$C_DIM" "$C_RESET"
        else
          printf '  %s↻%s %sconventions/%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$cfname" "$C_RESET"
        fi
      fi
      updated=$((updated + 1))
    done
  fi

  # agents/*.md — upsert: update existing AND add new ones (agentboard-global protocol files)
  if [[ -d "$TEMPLATES_PLATFORM/agents" ]]; then
    local asrc
    for asrc in "$TEMPLATES_PLATFORM/agents"/*.md; do
      [[ -f "$asrc" ]] || continue  # glob matched nothing (empty dir) — skip
      local afname; afname="$(basename "$asrc")"
      local adst="./.platform/agents/$afname"
      local agent_is_new=0
      [[ -f "$adst" ]] || agent_is_new=1
      if (( dry_run )); then
        if (( agent_is_new )); then
          printf '  %s+%s agents/%s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$afname" "$C_DIM" "$C_RESET"
        else
          printf '  %s~%s agents/%s\n' "$C_YELLOW" "$C_RESET" "$afname"
        fi
      else
        mkdir -p "./.platform/agents"
        cp "$asrc" "$adst"
        if (( agent_is_new )); then
          printf '  %s+%s %sagents/%s%s  %s(new)%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$afname" "$C_RESET" "$C_DIM" "$C_RESET"
        else
          printf '  %s↻%s %sagents/%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$afname" "$C_RESET"
        fi
      fi
      updated=$((updated + 1))
    done
  fi

  # skills — always replace (pure protocol content; project-specific work lives in .platform/)
  local skills_dir_claude="./.claude/skills"
  local skills_dir_agents="./.agents/skills"
  local skills_dir_codex="./.codex/skills"
  if [[ -d "$TEMPLATES_SKILLS" ]] && { [[ -d "$skills_dir_claude" ]] || [[ -d "$skills_dir_agents" ]] || [[ -d "$skills_dir_codex" ]]; }; then
    local sk_src sk_name sk_dst_c sk_dst_a sk_dst_x
    for sk_src in "$TEMPLATES_SKILLS"/*/; do
      sk_name="$(basename "$sk_src")"
      sk_dst_c="$skills_dir_claude/$sk_name"
      sk_dst_a="$skills_dir_agents/$sk_name"
      sk_dst_x="$skills_dir_codex/$sk_name"
      local skill_updated=0
      for sk_dst in "$sk_dst_c" "$sk_dst_a" "$sk_dst_x"; do
        # Refresh a skill the project has; add one it lacks (a skills dir that
        # exists means the project opted into the pack — new skills join it).
        [[ -d "$(dirname "$sk_dst")" ]] || continue
        if (( dry_run )); then
          if [[ -d "$sk_dst" ]]; then
            printf '  %s~%s skills/%s\n' "$C_YELLOW" "$C_RESET" "$sk_name"
          else
            printf '  %s+%s skills/%s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$sk_name" "$C_DIM" "$C_RESET"
          fi
        else
          if [[ -d "$sk_dst" ]]; then
            cp -R "$sk_src/." "$sk_dst/"
            printf '  %s↻%s %sskills/%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$sk_name" "$C_RESET"
          else
            mkdir -p "$sk_dst" && cp -R "$sk_src/." "$sk_dst/"
            printf '  %s+%s %sskills/%s%s  %s(new)%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$sk_name" "$C_RESET" "$C_DIM" "$C_RESET"
          fi
        fi
        skill_updated=1
        updated=$((updated + 1))
      done
      # avoid double-counting when more than one skills dir exists
      if [[ $skill_updated -eq 1 ]]; then
        local skill_dir_count=0
        [[ -d "$skills_dir_claude" ]] && skill_dir_count=$((skill_dir_count + 1))
        [[ -d "$skills_dir_agents" ]] && skill_dir_count=$((skill_dir_count + 1))
        [[ -d "$skills_dir_codex" ]] && skill_dir_count=$((skill_dir_count + 1))
        if (( skill_dir_count > 1 )); then
          updated=$((updated - (skill_dir_count - 1)))
        fi
      fi
    done
  fi

  # scripts/sync-context.sh
  local sc_src="$TEMPLATES_PLATFORM/scripts/sync-context.sh"
  local sc_dst="./.platform/scripts/sync-context.sh"
  local repos_file="./.platform/repos.md"
  if [[ -f "$sc_src" ]] && [[ -f "$sc_dst" ]]; then
    if (( dry_run )); then
      printf '  %s~%s scripts/sync-context.sh\n' "$C_YELLOW" "$C_RESET"
    else
      cp "$sc_src" "$sc_dst"
      chmod +x "$sc_dst"
      if [[ -f "$repos_file" ]]; then
        local sync_paths="" repo_row repo_id repo_path repo_stack repo_ref repo_abs repo_name current_repo
        current_repo="$(pwd)"
        while IFS='|' read -r repo_id repo_path repo_stack repo_ref repo_abs repo_name; do
          [[ -n "$repo_abs" ]] || continue
          [[ "$repo_abs" == "$current_repo" ]] && continue
          sync_paths="${sync_paths}${repo_abs}"$'\n'
        done < <(concrete_repo_rows "$repos_file")
        if [[ -n "$sync_paths" ]]; then
          write_sync_repos_array "$sc_dst" "$sync_paths"
        fi
      fi
      printf '  %s↻%s %sscripts/sync-context.sh%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$C_RESET"
    fi
    updated=$((updated + 1))
  fi

  # scripts/hooks/ — always upsert (no project-specific content; propagate bug fixes)
  if [[ -d "$TEMPLATES_PLATFORM/scripts/hooks" ]]; then
    local hook_src hook_dst hname
    for hook_src in "$TEMPLATES_PLATFORM/scripts/hooks"/*; do
      hname="$(basename "$hook_src")"
      hook_dst="./.platform/scripts/hooks/$hname"
      if (( dry_run )); then
        if [[ -f "$hook_dst" ]]; then
          printf '  %s~%s scripts/hooks/%s\n' "$C_YELLOW" "$C_RESET" "$hname"
        else
          printf '  %s+%s scripts/hooks/%s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$hname" "$C_DIM" "$C_RESET"
        fi
      else
        local hook_is_new=0
        [[ -f "$hook_dst" ]] || hook_is_new=1
        mkdir -p "./.platform/scripts/hooks"
        cp "$hook_src" "$hook_dst"
        chmod +x "$hook_dst"
        if (( hook_is_new )); then
          printf '  %s+%s %sscripts/hooks/%s%s  %s(new)%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$hname" "$C_RESET" "$C_DIM" "$C_RESET"
        else
          printf '  %s↻%s %sscripts/hooks/%s%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$hname" "$C_RESET"
        fi
      fi
      updated=$((updated + 1))
    done
  fi

  # -------------------------------------------------------------------------
  # ADD-IF-MISSING FILES — copy from template only if the project doesn't
  # have them yet. These may accumulate project-specific entries over time
  # (L-001, L-002, backlog items), so existing files are never overwritten.
  # -------------------------------------------------------------------------
  head "New files (add if missing)"

  local af
  # gotchas/playbook/open-questions/learnings are no longer shipped — facts
  # replaced them (agentboard migrate-memory converts existing entries).
  for af in "memory/BACKLOG.md" "memory/INDEX.md" "domains/TEMPLATE.md"; do
    local src="$TEMPLATES_PLATFORM/$af"
    local dst="./.platform/$af"
    [[ -f "$src" ]] || continue

    # Pre-layout guard: if this is a memory/* file and the user still has the
    # legacy root-level version, don't create the empty placeholder (that
    # would force migrate-layout into a conflict). Direct them to run
    # migrate-layout first.
    if [[ "$af" == memory/* ]]; then
      local basename="${af#memory/}"
      local legacy="./.platform/$basename"
      if [[ -f "$legacy" && ! -f "$dst" ]]; then
        printf '  %s↷%s %s%s%s  %s(legacy %s present at root — run `agentboard migrate-layout --apply` first)%s\n' \
          "$C_YELLOW" "$C_RESET" "$C_CYAN" "$af" "$C_RESET" "$C_DIM" "$basename" "$C_RESET"
        skipped=$((skipped + 1))
        continue
      fi
    fi

    if [[ -f "$dst" ]]; then
      printf '  %s↷%s %s%s%s  %s(exists — kept as-is)%s\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$af" "$C_RESET" "$C_DIM" "$C_RESET"
      skipped=$((skipped + 1))
    else
      if (( dry_run )); then
        printf '  %s+%s %s  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$af" "$C_DIM" "$C_RESET"
      else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        printf '  %s+%s %s%s%s  %s(new)%s\n' \
          "$C_GREEN" "$C_RESET" "$C_CYAN" "$af" "$C_RESET" "$C_DIM" "$C_RESET"
      fi
      added=$((added + 1))
    fi
  done

  # .claude/settings.json — add-if-missing (user may have custom hooks; don't clobber)
  local settings_src="$TEMPLATES_ROOT/.claude/settings.json"
  local settings_dst="./.claude/settings.json"
  if [[ -f "$settings_src" ]]; then
    if [[ -f "$settings_dst" ]]; then
      printf '  %s↷%s %s.claude/settings.json%s  %s(exists — kept as-is)%s\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
      skipped=$((skipped + 1))
    else
      if (( dry_run )); then
        printf '  %s+%s .claude/settings.json  %s(would add)%s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$C_RESET"
      else
        mkdir -p "./.claude"
        cp "$settings_src" "$settings_dst"
        printf '  %s+%s %s.claude/settings.json%s  %s(new)%s\n' \
          "$C_GREEN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
      fi
      added=$((added + 1))
    fi
  fi

  # .claude/agents/*.md — add-if-missing (e.g. ab-planner for the
  # plan→approve→execute loop; user may have customized theirs)
  if [[ -d "$TEMPLATES_ROOT/.claude/agents" ]]; then
    local agent_src agent_name
    for agent_src in "$TEMPLATES_ROOT/.claude/agents"/*.md; do
      [[ -f "$agent_src" ]] || continue
      agent_name="$(basename "$agent_src")"
      if [[ -f "./.claude/agents/$agent_name" ]]; then
        printf '  %s↷%s %s.claude/agents/%s%s  %s(exists — kept as-is)%s\n' \
          "$C_YELLOW" "$C_RESET" "$C_CYAN" "$agent_name" "$C_RESET" "$C_DIM" "$C_RESET"
        skipped=$((skipped + 1))
      else
        if (( dry_run )); then
          printf '  %s+%s .claude/agents/%s  %s(would add)%s\n' \
            "$C_GREEN" "$C_RESET" "$agent_name" "$C_DIM" "$C_RESET"
        else
          mkdir -p "./.claude/agents"
          cp "$agent_src" "./.claude/agents/$agent_name"
          printf '  %s+%s %s.claude/agents/%s%s  %s(new)%s\n' \
            "$C_GREEN" "$C_RESET" "$C_CYAN" "$agent_name" "$C_RESET" "$C_DIM" "$C_RESET"
        fi
        added=$((added + 1))
      fi
    done
  fi

  # -------------------------------------------------------------------------
  # Summary
  # -------------------------------------------------------------------------
  say
  if (( dry_run )); then
    printf '%s%s━━━ Dry-run complete ━━━%s\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
    printf '  Would update %s%d%s, add %s%d%s, keep %s%d%s\n' \
      "$C_BOLD" "$updated" "$C_RESET" \
      "$C_BOLD" "$added"   "$C_RESET" \
      "$C_BOLD" "$skipped" "$C_RESET"
    say
    printf '  %sRun without --dry-run to apply.%s\n' "$C_DIM" "$C_RESET"
  else
    printf '%s%s━━━ Update complete ━━━%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
    printf '  %s↻%s updated: %s%d%s   %s+%s added: %s%d%s   %s↷%s kept: %s%d%s\n' \
      "$C_GREEN" "$C_RESET" "$C_BOLD" "$updated" "$C_RESET" \
      "$C_GREEN" "$C_RESET" "$C_BOLD" "$added"   "$C_RESET" \
      "$C_YELLOW" "$C_RESET" "$C_BOLD" "$skipped" "$C_RESET"
    say
    printf '  %sNever touched:%s architecture.md, decisions.md, log.md, STATUS*.md,\n' "$C_DIM" "$C_RESET"
    printf '  %s              repos.md, work/ACTIVE.md, work/BRIEF.md, work/*.md, domains/*.md%s\n' "$C_DIM" "$C_RESET"
    printf '  %s              %s(except domains/TEMPLATE.md)%s\n' "$C_DIM" "$C_YELLOW" "$C_RESET"

    # Post-update next steps update can't do safely by itself
    local hinted=0
    if [[ -f "./.claude/settings.json" ]] && ! grep -q "session-close.sh" "./.claude/settings.json"; then
      (( hinted )) || { say; printf '%sNext steps:%s\n' "$C_BOLD" "$C_RESET"; hinted=1; }
      printf '  %s→%s your settings.json predates the SessionEnd auto-checkpoint hook —\n' "$C_CYAN" "$C_RESET"
      printf '     run %sagentboard install-hooks --force%s (backup kept) and %s--git%s for the pre-commit gate\n' \
        "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
    fi
    if [[ -f "./.platform/memory/gotchas.md" || -f "./.platform/memory/learnings.md" || \
          -f "./.platform/memory/playbook.md" || -f "./.platform/memory/open-questions.md" ]]; then
      (( hinted )) || { say; printf '%sNext steps:%s\n' "$C_BOLD" "$C_RESET"; hinted=1; }
      printf '  %s→%s legacy memory files detected — run %sagentboard migrate-memory --apply%s to convert them to facts\n' \
        "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_RESET"
    fi
  fi
  say
}

