cmd_install_hooks() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local force=0 dry_run=0 git_hooks=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)   force=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --git)     git_hooks=1; shift ;;
      -h|--help) _install_hooks_print_help; return 0 ;;
      *) die "Unknown flag for install-hooks: $1" ;;
    esac
  done

  local guard_src="$TEMPLATES_PLATFORM/scripts/hooks/bash-guard.sh"
  local guard_dst="./.platform/scripts/hooks/bash-guard.sh"
  local settings_src="$TEMPLATES_ROOT/.claude/settings.json"
  local settings_dst="./.claude/settings.json"
  local marker="bash-guard.sh"

  [[ -f "$guard_src" ]] || die "bash-guard.sh template missing at $guard_src"
  [[ -f "$settings_src" ]] || die "settings.json template missing at $settings_src"

  head "Agentboard hooks"

  # 1) Install the hook scripts (idempotent — templates are source of truth)
  local script_src script_dst script_name
  for script_name in bash-guard.sh platform-closure-gate.js platform-bootstrap.sh session-close.sh pre-commit-checkpoint.sh; do
    script_src="$TEMPLATES_PLATFORM/scripts/hooks/$script_name"
    script_dst="./.platform/scripts/hooks/$script_name"
    [[ -f "$script_src" ]] || continue
    if (( dry_run )); then
      printf '  %s+%s would write %s\n' "$C_CYAN" "$C_RESET" "$script_dst"
    else
      mkdir -p "$(dirname "$script_dst")"
      cp "$script_src" "$script_dst"
      chmod +x "$script_dst"
      printf '  %s✓%s %s  %s(executable)%s\n' \
        "$C_GREEN" "$C_RESET" "$script_dst" "$C_DIM" "$C_RESET"
    fi
  done

  (( git_hooks )) && _install_git_precommit_hook "$dry_run"

  # 2) Wire it into Claude Code settings.json
  if [[ ! -f "$settings_dst" ]]; then
    if (( dry_run )); then
      printf '  %s+%s would write %s (new)\n' "$C_CYAN" "$C_RESET" "$settings_dst"
    else
      mkdir -p "$(dirname "$settings_dst")"
      cp "$settings_src" "$settings_dst"
      printf '  %s✓%s %s  %s(new — closure-gate + bash-guard hooks installed)%s\n' \
        "$C_GREEN" "$C_RESET" "$settings_dst" "$C_DIM" "$C_RESET"
    fi
  elif (( force )); then
    # --force always re-syncs from the template (backup kept) — this is how
    # upgraders pick up newly shipped hooks like SessionEnd auto-checkpoint.
    local ts; ts="$(date +%s)"
    local backup="${settings_dst}.agentboard-backup-${ts}"
    if (( dry_run )); then
      printf '  %s+%s would back up existing to %s and overwrite with template\n' \
        "$C_CYAN" "$C_RESET" "$backup"
    else
      cp "$settings_dst" "$backup"
      cp "$settings_src" "$settings_dst"
      printf '  %s✓%s %s  %s(overwrote — backup saved to %s)%s\n' \
        "$C_GREEN" "$C_RESET" "$settings_dst" "$C_DIM" "$backup" "$C_RESET"
    fi
  elif grep -q "$marker" "$settings_dst"; then
    printf '  %s↷%s %s  %s(bash-guard already referenced — no change)%s\n' \
      "$C_YELLOW" "$C_RESET" "$settings_dst" "$C_DIM" "$C_RESET"
  else
      warn "$settings_dst exists and does NOT reference bash-guard.sh."
      say "  ${C_DIM}Two options:${C_RESET}"
      say "    1) Re-run with ${C_BOLD}--force${C_RESET} to back up the existing file and overwrite."
      say "    2) Add this hook entry under ${C_BOLD}hooks.PreToolUse${C_RESET} manually:"
      printf '\n'
      cat <<'JSON'
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"./.platform/scripts/hooks/bash-guard.sh\"",
            "timeout": 5
          }
        ]
      }
JSON
      printf '\n'
      return 1
  fi

  # 3) Nudge upgraders whose settings.json predates the session-close hook
  if [[ -f "$settings_dst" ]] && ! grep -q "session-close.sh" "$settings_dst"; then
    warn "$settings_dst has no SessionEnd auto-checkpoint hook."
    say "  ${C_DIM}Add this under hooks.SessionEnd to capture work state when sessions end:${C_RESET}"
    printf '\n'
    cat <<'JSON'
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"./.platform/scripts/hooks/session-close.sh\"",
            "timeout": 15
          }
        ]
      }
JSON
    printf '\n'
  fi

  if (( dry_run )); then
    say "${C_DIM}Dry run. Re-run without --dry-run to apply.${C_RESET}"
    return 0
  fi

  ok "Hooks installed. Claude Code will ask for approval on git commit / push / reset --hard / rm -rf."
  say "  ${C_DIM}Test: ask Claude to run 'git commit' in this repo — you should see the approval prompt.${C_RESET}"
}

# Install the cross-provider capture fallback as a git pre-commit hook.
# Codex/Gemini have no session-end surface; the commit is where we can gate.
_install_git_precommit_hook() {
  local dry_run="$1"
  local hook_src="$TEMPLATES_PLATFORM/scripts/hooks/pre-commit-checkpoint.sh"
  local hook_marker="agentboard:pre-commit-checkpoint"
  local git_dir hook_dst

  git_dir="$(git rev-parse --git-dir 2>/dev/null)" || {
    warn "--git: not a git repository — skipped pre-commit hook."
    return 0
  }
  hook_dst="$git_dir/hooks/pre-commit"
  [[ -f "$hook_src" ]] || { warn "--git: $hook_src missing — skipped."; return 0; }

  if [[ -f "$hook_dst" ]] && ! grep -q "$hook_marker" "$hook_dst"; then
    warn "--git: $hook_dst already exists and isn't agentboard's."
    say "  ${C_DIM}Chain it manually: add 'bash ./.platform/scripts/hooks/pre-commit-checkpoint.sh || exit 1'${C_RESET}"
    return 0
  fi

  if (( dry_run )); then
    printf '  %s+%s would write %s\n' "$C_CYAN" "$C_RESET" "$hook_dst"
    return 0
  fi
  mkdir -p "$(dirname "$hook_dst")"
  cp "$hook_src" "$hook_dst"
  chmod +x "$hook_dst"
  printf '  %s✓%s %s  %s(blocks commits when no open stream was checkpointed today)%s\n' \
    "$C_GREEN" "$C_RESET" "$hook_dst" "$C_DIM" "$C_RESET"
}

_install_hooks_print_help() {
  cat <<'EOF'
Usage: agentboard install-hooks [--force] [--git] [--dry-run]

Installs the Claude Code hook system that gates destructive shell commands,
enforces stream-closure approval, and auto-captures work state.

What gets installed:
  .platform/scripts/hooks/bash-guard.sh
      PreToolUse hook on the Bash tool. Intercepts `git commit`, `git push`,
      `git reset --hard`, `git checkout --`, `git branch -D`, `rm -rf`,
      `agentboard approve`, `agentboard close --confirm`, and any rm/mv/cp/
      tee/sed -i/redirection touching .platform/work/, and returns
      `permissionDecision: ask` — Claude Code shows its native approval prompt.
      `agentboard close --approve` gets its own prompt text naming what is
      granted: OWNER approval to close a stream.
      Uses node when available; without node a coarse bash match still asks.

  .platform/scripts/hooks/platform-closure-gate.js
      PreToolUse hook on Edit/Write. Blocks: closing or removing an ACTIVE.md
      row unless the CLI recorded the owner's approval and the Done criteria
      are complete; hand edits that grant approval in a stream file; ticking
      a criterion whose text names the owner; any write under work/archive/.

  .platform/scripts/hooks/platform-bootstrap.sh
      SessionStart hook. Prints the platform state (streams, gates, rules).

  .platform/scripts/hooks/session-close.sh
      SessionEnd hook. Auto-runs `agentboard checkpoint --auto` when a
      Claude Code session ends, so work state never goes stale silently.
      Fail-open: never blocks session close.

  .platform/scripts/hooks/pre-commit-checkpoint.sh
      Installed into .git/hooks with --git (see below).

  .claude/settings.json
      Wires the hooks into Claude Code.

Flags:
  --git       Also install the cross-provider fallback: a git pre-commit
              hook that blocks code commits when no open stream was
              checkpointed today. Covers Codex CLI and Gemini CLI, which
              have no session-end hook surface.
              Bypass per-commit: AGENTBOARD_SKIP_CHECKPOINT=1 git commit
  --force     Overwrite existing .claude/settings.json (backup saved with
              a .agentboard-backup-<ts> suffix). Without --force, existing
              unknown settings.json files are left alone and a snippet is
              printed for manual install.
  --dry-run   Print what would change without writing anything.

Notes:
  - Fresh `agentboard init` already writes the full settings.json, so this
    command is mostly for existing projects or re-install.
  - Hook errors (missing runtime, unreadable hook input) are reported and
    never block: commands still run, edits proceed, sessions still close.
    The closure gate blocks only when it cannot establish owner approval
    for a stream row that is being closed or removed.
  - Enforcement coverage is honest, not uniform: Claude Code gets runtime
    hooks; Codex/Gemini get the --git pre-commit fallback at commit time.
EOF
}
