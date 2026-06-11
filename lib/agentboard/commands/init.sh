cmd_init() {
  require_templates

  printf '\n%s%sagentboard init%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf '%sScaffolds a %s.platform/%s%s context pack + activation prompt.%s\n' \
    "$C_DIM" "$C_RESET$C_CYAN$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"

  local target; target="$(pwd)"
  printf '%s  target:%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_CYAN" "$target" "$C_RESET"

  if [[ -d "$target/.platform" ]]; then
    say
    warn "$target/.platform already exists."
    ask_yes_no "Overwrite it? (contents will be deleted)" || die "aborted."
    rm -rf "$target/.platform"
  fi

  # -------------------------------------------------------------------------
  # Empty-folder / hub detection
  #
  # If the folder looks empty for agentboard purposes (no code, no manifests,
  # no source dirs), ask the user whether this is a "platform brains hub"
  # coordinating sibling repos rather than a single project. If the folder
  # contains only sibling repos (each with its own .git/ or manifest), treat
  # that as a strong hub signal and default the prompt to YES.
  # -------------------------------------------------------------------------
  local hub_mode=0
  local folder_kind
  folder_kind="$(detect_folder_kind "$target")"

  if [[ "$folder_kind" == "hub-candidate" ]]; then
    head "Platform brains hub detected"
    printf '  %sThis folder contains only subdirectories that look like their own repos%s\n' "$C_DIM" "$C_RESET"
    printf '  %s(each has a %s.git/%s%s or its own manifest). That usually means this is a%s\n' "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
    printf '  %sparent folder holding %s.platform/%s%s for several sibling repos, not a single project.%s\n' "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
    say
    if ask_yes_no_default \
      'Is this a platform brains hub coordinating sibling repos?' \
      'Y' \
      'Answering YES configures .platform/repos.md for multi-repo mode and skips the single-project CLAUDE.md stub. Answering NO falls back to the normal project flow.'; then
      hub_mode=1
    fi
  elif [[ "$folder_kind" == "empty" ]]; then
    head "Empty folder detected"
    printf '  %sThis folder looks empty (no code files, no manifests, no source subdirectories).%s\n' "$C_DIM" "$C_RESET"
    say
    if ask_yes_no_default \
      'Is this going to be a platform brains hub coordinating sibling repos?' \
      'N' \
      'A hub is a parent folder that holds .platform/ for several sibling repos (e.g. backend + frontend + widget), rather than a single codebase. Answer NO if you plan to write code directly in this folder.'; then
      hub_mode=1
    fi
  fi

  head "Project info"
  if (( hub_mode )); then
    printf '  %sI will ask 2 quick questions. Press %sEnter%s%s to accept the default in [brackets].%s\n' \
      "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
  else
    printf '  %sI will ask 2 quick questions. Press %sEnter%s%s to accept the default in [brackets].%s\n' \
      "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
  fi

  local project_name project_desc
  project_name="$(ask \
    'Project name' \
    "$(basename "$target")" \
    'Used in the platform pack headers and log entries. The folder name is usually fine.')"

  if (( hub_mode )); then
    project_desc="$(ask \
      'Short description (1 sentence)' \
      'Platform brains hub — coordinates context for sibling repos' \
      'A brief sentence describing what this hub coordinates — e.g. "Backend + admin + widget for SaaS X", "Mobile app + API + analytics pipeline". The LLM will refine this during activation, so rough is fine. Press Enter to skip.')"
  else
    project_desc="$(ask \
      'Short description (1 sentence)' \
      'TBD — will be filled during activation' \
      'A brief sentence describing the project — e.g. "iOS app for meal planning", "Rust CLI for log parsing", "marketing landing page for SaaS X". The LLM will refine this during activation, so rough is fine. Press Enter to skip.')"
  fi

  head "Scaffolding .platform/"
  mkdir -p "$target/.platform"
  cp -R "$TEMPLATES_PLATFORM/." "$target/.platform/"
  ok "Copied platform skeleton → $C_CYAN$target/.platform/$C_RESET"

  # Hub vs. project: swap in the hub-mode repos.md and ACTIVATE-HUB.md and
  # remove the single-project variants the hub doesn't use. In project mode,
  # strip out the hub-only files so they don't confuse the LLM during
  # activation.
  if (( hub_mode )); then
    if [[ -f "$target/.platform/repos.hub.md" ]]; then
      mv "$target/.platform/repos.hub.md" "$target/.platform/repos.md"
    fi
    # Single-project ACTIVATE.md is not used in hub mode — the hub uses
    # ACTIVATE-HUB.md which scans sibling repo paths instead of this folder.
    rm -f "$target/.platform/ACTIVATE.md"
  else
    rm -f "$target/.platform/repos.hub.md"
    rm -f "$target/.platform/ACTIVATE-HUB.md"
  fi

  # Substitute placeholders in the skeletal files
  for f in \
    "$target/.platform/ACTIVATE.md" \
    "$target/.platform/ACTIVATE-HUB.md" \
    "$target/.platform/STATUS.md" \
    "$target/.platform/memory/log.md" \
    "$target/.platform/memory/decisions.md" \
    "$target/.platform/architecture.md" \
    "$target/.platform/repos.md" \
    "$target/.platform/work/ACTIVE.md" \
    "$target/.platform/work/BRIEF.md"; do
    [[ -f "$f" ]] || continue
    substitute "$f" \
      PROJECT_NAME "$project_name" \
      DESCRIPTION  "$project_desc" \
      TODAY        "$(today)"
  done
  ok "Substituted project name + description into skeleton files"
  if (( hub_mode )); then
    ok "Installed → $C_CYAN$target/.platform/ACTIVATE-HUB.md$C_RESET (the hub-mode activation protocol)"
  else
    ok "Installed → $C_CYAN$target/.platform/ACTIVATE.md$C_RESET (the activation protocol)"
  fi

  # Make sync script executable
  if [[ -f "$target/.platform/scripts/sync-context.sh" ]]; then
    chmod +x "$target/.platform/scripts/sync-context.sh"
  fi

  # Root CLAUDE.md — only written if there's no existing one. Existing files
  # are NEVER touched by init; the LLM handles them during activation (Step 4
  # of .platform/ACTIVATE.md) by prepending its section and preserving the
  # original content underneath.
  head "Root entry files (CLAUDE.md / AGENTS.md / GEMINI.md)"
  printf '  %sagentboard %snever%s%s touches existing root entry files during init.%s\n' \
    "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
  printf '  %sIf you already have one, the LLM will prepend its section during activation,%s\n' \
    "$C_DIM" "$C_RESET"
  printf '  %spreserving every line of your original content. No deletions, no backups.%s\n' \
    "$C_DIM" "$C_RESET"
  say

  local existing_any=0
  local f_name existing_list=""
  for f_name in CLAUDE.md AGENTS.md GEMINI.md; do
    if [[ -f "$target/$f_name" ]]; then
      existing_any=1
      existing_list="${existing_list:+$existing_list, }$f_name"
    fi
  done

  if [[ -f "$target/CLAUDE.md" ]]; then
    # Prepend a minimal activation notice so the AI reading CLAUDE.md knows
    # agentboard is installed and what to do. Purely additive — original content
    # is preserved in full below the notice. Skip if notice already present
    # (idempotent re-runs).
    if grep -q "<!-- agentboard installed" "$target/CLAUDE.md" 2>/dev/null; then
      printf '  %s↷%s Activation notice already present in %s%s/CLAUDE.md%s — skipping\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$target" "$C_RESET"
    else
      local ab_notice
      ab_notice="$(cat <<NOTICE
<!-- agentboard installed $(today) -->
> **agentboard is installed** in \`.platform/\`. When the user says "activate this project" (or "fill in the platform pack", "run agentboard activation"), read \`.platform/ACTIVATE.md\` and follow its 6-step protocol. It covers scanning the project, interviewing the user, filling \`.platform/\`, and prepending a steady-state section to this file (without deleting any existing content).

---

NOTICE
)"
      local original_content
      original_content="$(cat "$target/CLAUDE.md")"
      printf '%s%s' "$ab_notice" "$original_content" > "$target/CLAUDE.md"
      printf '  %s↷%s Prepended activation notice → %s%s/CLAUDE.md%s (original content preserved below)\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$target" "$C_RESET"
    fi
  else
    # Hub mode uses a specialized "platform brains hub" stub pointing at
    # ACTIVATE-HUB.md. Single-project mode uses the normal stub pointing at
    # ACTIVATE.md.
    local root_template=""
    local root_activate_ref=""
    if (( hub_mode )); then
      if [[ -f "$TEMPLATES_ROOT/CLAUDE.md.hub.template" ]]; then
        root_template="$TEMPLATES_ROOT/CLAUDE.md.hub.template"
        root_activate_ref=".platform/ACTIVATE-HUB.md"
      fi
    else
      if [[ -f "$TEMPLATES_ROOT/CLAUDE.md.template" ]]; then
        root_template="$TEMPLATES_ROOT/CLAUDE.md.template"
        root_activate_ref=".platform/ACTIVATE.md"
      fi
    fi
    if [[ -n "$root_template" ]]; then
      cp "$root_template" "$target/CLAUDE.md"
      substitute "$target/CLAUDE.md" \
        PROJECT_NAME "$project_name" \
        DESCRIPTION  "$project_desc" \
        TODAY        "$(today)"
      if (( hub_mode )); then
        ok "Wrote → $C_CYAN$target/CLAUDE.md$C_RESET (hub stub pointing at $root_activate_ref)"
      else
        ok "Wrote → $C_CYAN$target/CLAUDE.md$C_RESET (short stub pointing at $root_activate_ref)"
      fi
    fi
  fi

  for f_name in AGENTS.md GEMINI.md; do
    if [[ -f "$target/$f_name" ]]; then
      printf '  %s↷%s Kept existing %s%s/%s%s (will be updated during activation)\n' \
        "$C_YELLOW" "$C_RESET" "$C_CYAN" "$target" "$f_name" "$C_RESET"
    else
      local f_template="$TEMPLATES_ROOT/$f_name.template"
      if [[ -f "$f_template" ]]; then
        cp "$f_template" "$target/$f_name"
        substitute "$target/$f_name" \
          PROJECT_NAME "$project_name" \
          DESCRIPTION  "$project_desc" \
          TODAY        "$(today)"
        ok "Wrote → $C_CYAN$target/$f_name$C_RESET (stub — Codex/Gemini entry point)"
      fi
    fi
  done

  # Install project-level Claude Code settings (.claude/settings.json)
  # Contains enforcement hooks: closure gate (blocks premature stream closure) +
  # session bootstrap (structured state report on every session start).
  # Additive-safe: only created if no existing .claude/settings.json is present.
  head "Enforcement hooks (.claude/settings.json)"
  local settings_template="$TEMPLATES_ROOT/.claude/settings.json"
  local settings_target="$target/.claude/settings.json"
  if [[ -f "$settings_target" ]]; then
    printf '  %s↷%s Kept existing %s%s/.claude/settings.json%s (hooks already configured)\n' \
      "$C_YELLOW" "$C_RESET" "$C_CYAN" "$target" "$C_RESET"
  elif [[ -f "$settings_template" ]]; then
    mkdir -p "$target/.claude"
    cp "$settings_template" "$settings_target"
    ok "Wrote → $C_CYAN$target/.claude/settings.json$C_RESET (closure gate + session bootstrap hooks)"
  fi

  # Install Claude Code agents (e.g. ab-planner pinned to a planning model).
  # Additive: existing agents with the same name are kept.
  if [[ -d "$TEMPLATES_ROOT/.claude/agents" ]]; then
    local agent_src agent_dst
    mkdir -p "$target/.claude/agents"
    for agent_src in "$TEMPLATES_ROOT/.claude/agents"/*.md; do
      [[ -f "$agent_src" ]] || continue
      agent_dst="$target/.claude/agents/$(basename "$agent_src")"
      if [[ -f "$agent_dst" ]]; then
        printf '  %s↷%s Kept existing %s\n' "$C_YELLOW" "$C_RESET" "$agent_dst"
      else
        cp "$agent_src" "$agent_dst"
        ok "Wrote → ${C_CYAN}${agent_dst}${C_RESET} (plan→approve→execute planner)"
      fi
    done
  fi
  say

  # Install skills additively — never overwrite existing skills
  # Skills are installed to BOTH .claude/skills/ (Claude Code) and .agents/skills/
  # (Codex CLI + Gemini CLI) so all three providers have the full lifecycle skill set.
  head "Installing skills (.claude/skills/ + .agents/skills/)"
  printf '  %sAdditive install — any pre-existing skill with the same name is left untouched.%s\n' "$C_DIM" "$C_RESET"
  printf '  %sInstalled to both .claude/skills/ (Claude Code) and .agents/skills/ (Codex + Gemini).%s\n' "$C_DIM" "$C_RESET"
  say
  if [[ -d "$TEMPLATES_SKILLS" ]]; then
    local skills_target_claude="$target/.claude/skills"
    local skills_target_agents="$target/.agents/skills"
    mkdir -p "$skills_target_claude" "$skills_target_agents"
    local installed=0 skipped=0 skill_name skill_desc
    for skill_dir in "$TEMPLATES_SKILLS"/*/; do
      skill_name="$(basename "$skill_dir")"
      skill_desc="$(skill_description "$skill_dir/SKILL.md")"
      local installed_here=0
      # Install to .claude/skills/ (Claude Code)
      if [[ -e "$skills_target_claude/$skill_name" ]]; then
        skipped=$((skipped + 1))
        printf '    %s↷%s %s%-16s%s %s%s%s\n' \
          "$C_YELLOW" "$C_RESET" "$C_BOLD" "$skill_name" "$C_RESET" \
          "$C_DIM" "(claude: exists — kept)" "$C_RESET"
      else
        cp -R "$skill_dir" "$skills_target_claude/$skill_name"
        installed_here=1
      fi
      # Install to .agents/skills/ (Codex + Gemini)
      if [[ -e "$skills_target_agents/$skill_name" ]]; then
        skipped=$((skipped + 1))
        printf '    %s↷%s %s%-16s%s %s%s%s\n' \
          "$C_YELLOW" "$C_RESET" "$C_BOLD" "$skill_name" "$C_RESET" \
          "$C_DIM" "(agents: exists — kept)" "$C_RESET"
      else
        cp -R "$skill_dir" "$skills_target_agents/$skill_name"
        installed_here=1
      fi
      if (( installed_here )); then
        installed=$((installed + 1))
        printf '    %s+%s %s%-16s%s %s%s%s\n' \
          "$C_GREEN" "$C_RESET" "$C_BOLD" "$skill_name" "$C_RESET" \
          "$C_DIM" "$skill_desc" "$C_RESET"
      fi
    done
    say
    ok "Skills: $C_BOLD$installed installed$C_RESET to both .claude/skills/ and .agents/skills/, $skipped skipped"
  fi

  # Scaffold .codex/ for Codex CLI subagent dispatch
  # Additive-safe: only created if .codex/ does not already exist.
  head "Codex subagent config (.codex/)"
  local codex_templates="$AGENTBOARD_ROOT/templates/codex"
  local codex_target="$target/.codex"
  if [[ -d "$codex_target" ]]; then
    printf '  %s↷%s .codex/ already exists — skipped\n' "$C_YELLOW" "$C_RESET"
  elif [[ -d "$codex_templates" ]]; then
    cp -R "$codex_templates/." "$codex_target/"
    ok "Wrote → ${C_CYAN}.codex/config.toml${C_RESET} + ${C_CYAN}.codex/agents/${C_RESET} (researcher / coder / auditor / mapper)"
    printf '  %sCustomize agent roles + model IDs after activation.%s\n' "$C_DIM" "$C_RESET"
  fi
  say

  say
  if (( hub_mode )); then
    printf '%s%s━━━ Platform brains hub initialized ━━━%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  1. Edit %s.platform/repos.md%s and list each sibling repo %s(path, stack, deep-reference file)%s.\n' \
      "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
    printf '     %sOr run %sagentboard add-repo <path>%s%s from this hub for each sibling to scaffold its entry files.%s\n' \
      "$C_DIM" "$C_BOLD" "$C_RESET$C_DIM" "$C_DIM" "$C_RESET"
    printf '  2. Open this hub in your AI CLI %s(Claude Code / Codex CLI / Gemini CLI)%s\n' "$C_DIM" "$C_RESET"
    printf '  3. Say: %s%s"activate this project"%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  4. The LLM will read %s.platform/ACTIVATE-HUB.md%s, %sscan each sibling repo%s,\n' \
      "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_RESET"
    printf '     %sask 5–8 targeted questions%s, and fill in %s.platform/%s based on what it finds.\n' \
      "$C_BOLD" "$C_RESET" "$C_CYAN" "$C_RESET"
    if [[ $existing_any -eq 1 ]]; then
      printf '  5. Your existing %s%s%s will be %spreserved%s — the LLM prepends its section to the top.\n' \
        "$C_CYAN" "$existing_list" "$C_RESET" "$C_BOLD" "$C_RESET"
    fi
    say
    dim "  This is a hub, not a code repo. The LLM will scan sibling repo paths, not this folder."
    say
  else
    printf '%s%s━━━ Next step: activate ━━━%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  1. Open this project in your AI CLI %s(Claude Code / Codex CLI / Gemini CLI)%s\n' "$C_DIM" "$C_RESET"
    printf '  2. Say: %s%s"activate this project"%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '  3. The LLM will read %s.platform/ACTIVATE.md%s, %sscan%s your codebase,\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_RESET"
    printf '     %sask 5–8 targeted questions%s, and fill in %s.platform/%s based on what it finds.\n' "$C_BOLD" "$C_RESET" "$C_CYAN" "$C_RESET"
    if [[ $existing_any -eq 1 ]]; then
      printf '  4. Your existing %s%s%s will be %spreserved%s — the LLM prepends its section to the top.\n' \
        "$C_CYAN" "$existing_list" "$C_RESET" "$C_BOLD" "$C_RESET"
    else
      printf '  4. %sCLAUDE.md%s, %sAGENTS.md%s, and %sGEMINI.md%s are already present with\n' "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
      printf '     mandatory protocols pre-loaded. Activation replaces them with project-specific content.\n'
    fi
    say
    dim "  No stack picking. No assumptions. No deletions. The LLM decides based on your actual code."
    say
  fi
}

