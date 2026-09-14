# research.sh — delegate the research phase to a locally-installed Codex CLI
#
# Optional wrapper command: runs `codex exec` read-only and headless, streams
# Codex's live activity to the terminal, and anchors the final findings as a
# dated block under '## Research notes' in the stream file — where ab-planner
# and the executor read them. Codex is NOT a dependency of any other command;
# when the binary is absent this command dies with guidance and nothing else
# in the kit changes behavior (decisions.md — Hard-rule-6 exception).

cmd_research() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'agentboard init' first."

  local slug="" prompt="" web=0 model="" profile="" dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --web) web=1; shift ;;
      --model)
        [[ -n "${2:-}" ]] || die "research requires a value after --model"
        model="$2"; shift 2 ;;
      --profile)
        [[ -n "${2:-}" ]] || die "research requires a value after --profile"
        profile="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help) _research_print_help; return 0 ;;
      -*) die "Unknown flag for research: $1" ;;
      *)
        if [[ -z "$slug" ]]; then slug="$1"
        elif [[ -z "$prompt" ]]; then prompt="$1"
        else die "Unexpected extra argument for research: $1 (quote the prompt)"
        fi
        shift ;;
    esac
  done

  [[ -n "$slug" ]] || die "Usage: agentboard research <slug> \"<question>\" — see 'agentboard research --help'"
  [[ -n "$prompt" ]] || die "research requires a question: agentboard research $slug \"<question>\""

  local stream_file="./.platform/work/${slug}.md"
  [[ -f "$stream_file" ]] || die "$stream_file not found. Create the stream first: agentboard new-stream $slug --domain <d>"

  local codex_bin="${AGENTBOARD_CODEX_BIN:-codex}"
  command -v "$codex_bin" >/dev/null 2>&1 \
    || die "Codex CLI not found ('$codex_bin'). Install it or set AGENTBOARD_CODEX_BIN. 'agentboard research' is optional — no other command needs it."

  local out_file
  out_file="$(mktemp)"
  # Profiles resolve from ~/.codex/config.toml only — never default one, or
  # the command fails on machines that haven't defined it. -s read-only is
  # what guarantees safety, independent of any profile.
  local -a argv=(exec -s read-only --color never --skip-git-repo-check -o "$out_file")
  [[ -n "$profile" ]] && argv+=(-p "$profile")
  [[ -n "$model" ]] && argv+=(-m "$model")
  (( web )) && argv+=(-c "tools.web_search=true")
  argv+=("$prompt")

  if (( dry_run )); then
    say "dry-run — would invoke:"
    say "  $codex_bin ${argv[*]}"
    say "  findings → $stream_file (## Research notes)"
    rm -f "$out_file"
    return 0
  fi

  local web_label=""
  (( web )) && web_label=", web"
  say "${C_CYAN}⟂ codex researching ${slug}${C_RESET} ${C_DIM}(read-only${web_label}) — live output below${C_RESET}"

  # Codex streams its activity on stdout/stderr while -o captures only the
  # final message — let the live stream reach the terminal untouched.
  local started status=0
  started="$(date +%s)"
  "$codex_bin" "${argv[@]}" || status=$?
  if (( status != 0 )); then
    rm -f "$out_file"
    die "codex exec failed (exit $status) — check 'codex login' / network. No findings were written."
  fi

  local findings
  findings="$(cat "$out_file" 2>/dev/null)"
  rm -f "$out_file"
  [[ -n "$findings" ]] || die "codex returned an empty final message — no findings were written."

  with_state_lock _research_commit "$stream_file" "$prompt" "$web" "$findings" || return 1

  local elapsed=$(( $(date +%s) - started ))
  ok "research notes appended → .platform/work/${slug}.md (${elapsed}s)"
}

_research_print_help() {
  cat <<'EOF'
Usage: agentboard research <slug> "<question>" [--web] [--model <m>] [--profile <p>] [--dry-run]

Delegate the research phase to a locally-installed Codex CLI (read-only,
headless). Codex reads the codebase (and the web with --web), its activity
streams live to the terminal, and the final findings are appended as a dated
block under '## Research notes' in .platform/work/<slug>.md — where
ab-planner and the executor consume them.

Agent-invoked by design: sessions run this at the Research stage for medium+
scope work. Humans rarely need to type it.

Flags:
  --web           Enable Codex live web search for this run.
  --model <m>     Override the Codex model for this run.
  --profile <p>   Codex config profile (resolves from ~/.codex/config.toml;
                  none passed by default).
  --dry-run       Print the codex argv + target file; invoke nothing.

Requires the codex binary on PATH (override with AGENTBOARD_CODEX_BIN).
Optional command: no other agentboard command depends on codex.
EOF
}

# _research_append_notes <stream_file> <prompt> <web> <findings>
# Append a dated block to ## Research notes (append-mode — runs accumulate,
# never overwrite). Creates the section before ## Progress log when absent.
_research_commit() {
  local stream_file="$1" staged
  [[ -f "$stream_file" ]] || { warn "Research target was closed or removed; rerun against an active stream."; return 1; }
  staged="$(mktemp "$(dirname "$stream_file")/.research.XXXXXX")" || return 1
  cp -p "$stream_file" "$staged" &&
    _research_append_notes "$staged" "$2" "$3" "$4" &&
    set_frontmatter_value "$staged" updated_at "$(today)" &&
    mv "$staged" "$stream_file" || { rm -f "$staged"; return 1; }
}

_research_append_notes() {
  local stream_file="$1" prompt="$2" web="$3" findings="$4"
  local stamp summary web_tag="" tmp block_file
  stamp="$(date '+%Y-%m-%d %H:%M')"
  summary="$(printf '%.60s' "$prompt")"
  [[ "$web" == "1" ]] && web_tag=" [web]"

  block_file="$(mktemp)" || return 1
  {
    printf '### %s — %s%s\n\n' "$stamp" "$summary" "$web_tag" &&
    printf '%s\n' "$findings"
  } > "$block_file" || { rm -f "$block_file"; return 1; }

  tmp="$(mktemp)" || { rm -f "$block_file"; return 1; }
  if grep -q '^## Research notes[[:space:]]*$' "$stream_file"; then
    # Append at the end of the existing section (before the next ## heading).
    awk -v block_file="$block_file" '
      BEGIN { in_section = 0; inserted = 0 }
      /^## Research notes[[:space:]]*$/ { in_section = 1; print; next }
      in_section && /^## / && !inserted {
        while ((read_status = (getline line < block_file)) > 0) print line
        if (read_status < 0) { failed = 1; exit 1 }
        close(block_file)
        print ""
        inserted = 1; in_section = 0
        print; next
      }
      { print }
      END {
        if (failed) exit 1
        if (in_section && !inserted) {
          while ((read_status = (getline line < block_file)) > 0) print line
          if (read_status < 0) exit 1
        }
      }
    ' "$stream_file" > "$tmp" || return 1
  elif grep -q '^## Progress log[[:space:]]*$' "$stream_file"; then
    awk -v block_file="$block_file" '
      BEGIN { inserted = 0 }
      /^## Progress log[[:space:]]*$/ && !inserted {
        print "## Research notes"
        print ""
        while ((read_status = (getline line < block_file)) > 0) print line
        if (read_status < 0) exit 1
        close(block_file)
        print ""
        inserted = 1
      }
      { print }
    ' "$stream_file" > "$tmp" || return 1
  else
    cat "$stream_file" > "$tmp" || return 1
    printf '\n## Research notes\n\n' >> "$tmp" || return 1
    cat "$block_file" >> "$tmp" || return 1
  fi

  rm -f "$block_file"
  mv "$tmp" "$stream_file"
}
