cmd_version() { say "agentboard $VERSION"; }

cmd_help() {
  cat <<'EOF'
agentboard — shared work-state for multi-provider AI workflows

Scaffolds a .platform/ pack plus provider-neutral entry files (CLAUDE.md,
AGENTS.md, GEMINI.md) so Claude Code, Codex CLI, and Gemini CLI each load
the same project truth and can resume the same workstreams across sessions.
Agentboard does NOT move chat history between providers — it shares files,
not conversations.

USAGE
  agentboard <command> [args]

COMMANDS
  install [--dir ...]        Install agentboard onto your PATH via a symlink
  init                       Scaffold a .platform/ pack in the current directory.
                             After init, open the project in an AI CLI and say
                             "activate this project" — the LLM scans your code
                             and fills in the context pack based on what it finds.

  update [--dry-run]         Update process files to the latest agentboard version.
                             Replaces: workflow.md, ONBOARDING.md, ACTIVATE.md,
                               conventions/*.md, domains/TEMPLATE.md,
                               scripts/sync-context.sh
                             Adds if missing: BACKLOG.md, memory/INDEX.md
                             Never touches: architecture.md, decisions.md, log.md,
                               STATUS*.md, repos.md, work/*, domains/*
                               except domains/TEMPLATE.md

  sync [--apply|--list]      Sync AGENTS.md + GEMINI.md from CLAUDE.md (default: check)
  bootstrap [--apply-domains] Discover repos, infer starter domains, and suggest streams
  migrate [--apply]          Upgrade legacy stream/domain files to metadata v1
  migrate-layout [--apply]   Upgrade .platform/ layout — move decisions/learnings/
                             log/gotchas/playbook/open-questions/BACKLOG into
                             .platform/memory/. Cleans up empty sessions/.
                             Default is --dry-run; pass --apply to perform.
  brief-upgrade [slug] ...   Rewrite legacy BRIEF.md for one target stream
  migrate-memory [--apply]   Convert legacy category memory files (gotchas/
                             playbook/open-questions/learnings) into facts;
                             originals parked in memory/legacy/
  doctor                     Validate active .platform state and metadata
  new-domain <slug> ...      Create a domain file from the shared template
  new-stream <slug> ...      Create a stream file and register it in work/ACTIVE.md
                             --domain <slug>  (repeatable, required)
                             --base-branch <b> branch to fork from (prompts if omitted)
                             --branch <name>  git branch name for this stream
                             --type <t>       stream type (default: feature)
                             --agent <a>      agent owner (default: codex)
                             --repo <id>      (repeatable)
  resolve <target>           Resolve a stream, domain, or repo by canonical id
  handoff [stream-slug]      Print a low-token provider handoff packet.
                             Shows Resume state (from stream file), warns if
                             stale, appends a "for the agent reading this"
                             footer. Flags:
                             --budget <N|Nk>   cap estimated load-order tokens;
                                               drops secondary domains when tight
  checkpoint <stream-slug>   Save compact "where we are" state before handoff.
                             Overwrites the stream's ## Resume state block,
                             prepends a Progress log entry, trims to last 10.
                             Run this before ending a session or switching CLIs.
                             --what "<text>"   required: what just happened
                             --next "<text>"   required: the single next action
                             --blocker "<t>"   current blocker (default: none)
                             --focus "<t>"     file:line or topic in focus
                             --diff            also append git diff --stat
                             --auto            unattended mode (used by the
                                               SessionEnd hook): slug optional,
                                               derives state from git, no-ops
                                               on a clean tree
                             --dry-run         print changes without writing
                             --tokens-in N --tokens-out N --provider <p>
                             [--model <m>] [--complexity <c>]
                                               auto-log a usage segment
  approve <stream-slug>      Human gate of the plan→approve→execute loop.
                             The ab-planner agent (Opus) writes an
                             ## Execution brief into the stream file; this
                             command flips brief_approved: true so the
                             execution model (e.g. Fable 5) may write code.
                             In Claude Code the bash-guard turns it into a
                             yes/no click — the LLM cannot self-approve.
                             --revoke          plan changed: stop execution
  close <stream-slug>        Finalize a stream. Two-step ritual:
                             1. bare run prints the harvest checklist —
                                distill gotchas/learnings into facts via
                                `agentboard fact new`; decisions go to
                                memory/decisions.md (the registry).
                             2. --confirm archives the stream and logs closure.
                             --dry-run         preview --confirm actions
  brief                      Print the compact project briefing — active
                             streams, gotchas, facts in scope (domain-scoped),
                             open questions, usage pattern. Read at session start.
                             --all             show all gotchas/facts/questions
  fact <sub>                 One-fact-per-file project memory (no merge
                             conflicts, domain-scoped loading, prunable).
                             new      — create a fact + reindex
                               --type gotcha|learning|playbook|question
                               --title "<one line>" [--domain d]... [--stream s]
                               [--severity red|yellow|green] [--body "<text>"]
                               [--expires YYYY-MM-DD]
                             list     — [--type t] [--domain d] [--status s|all]
                             reindex  — regenerate .platform/memory/INDEX.md
                             prune    — flag/expire facts past their date (--apply)
  harvest                    Promote Claude Code's machine-local auto-memory
                             notes into shared committed facts. Lists numbered
                             candidates; nothing is written without --accept.
                             --accept n,m  --all  --dry-run  --type <t>
                             --domain <d>  --stream <s>  --source <dir>
  tui                        Read-only dashboard of the stream registry:
                             one colored row per stream (status | owner |
                             updated | branch). Auto-refreshes; never writes.
                             --status <s>      filter by status
                             --owner <name>    filter by agent owner
                             --interval N      refresh every N s (default 5)
                             --once            single render, then exit
  research <slug> "<q>"      Delegate research to the local Codex CLI
                             (read-only, headless). Activity streams live;
                             findings append to the stream's
                             ## Research notes. Optional — needs codex
                             on PATH (or AGENTBOARD_CODEX_BIN).
                             --web             enable Codex web search
                             --model <m>       override Codex model
                             --profile <p>     ~/.codex config profile
                                               (none by default)
                             --dry-run         print argv, invoke nothing
  watch                      Background poller that auto-checkpoints when
                             ≥1 tracked file has changed since last poll.
                             Use during long Codex/Gemini sessions so state
                             stays current without manual checkpoints.
                             --interval N      poll every N min (default 10)
                             --threshold N     min changed files (default 1)
                             --stream <slug>   target stream (default: auto)
                             --once            single poll, then exit
                             --stop            stop the running watcher
  install-hooks              Install hook guards. Claude Code gets PreToolUse
                             (blocks git commit/push/reset --hard/rm -rf) and
                             SessionEnd (auto-checkpoint on session close).
                             LLM cannot bypass. Safe on re-install.
                             --git             also install the git pre-commit
                                               fallback for Codex/Gemini: blocks
                                               code commits when no open stream
                                               was checkpointed today
                             --force           overwrite existing settings.json
                             --dry-run         preview without writing
  progress <stream-slug>     Append a git-diff summary to the stream's
                             ## Progress log section (uses base_branch from
                             frontmatter). Flags:
                             --base <branch>   override recorded base branch
                             --note "<text>"   one-line note to attach
                             --dry-run         print block instead of writing
  status                     Print .platform/STATUS.md to stdout
  add-repo <path>            Copy per-repo entry file templates to a new repo
                             Refuses to overwrite existing entry files.
  usage [subcommand]         Track token consumption across all projects (SQLite).
                             summary       — totals by provider/model/repo/type
                             log           — record a context segment
                               --provider <name> --input <N> --output <N>
                               [--model <M>] [--stream <S>] [--repo <R>]
                               [--type <T>] [--note <text>]
                             stream <slug> — full breakdown for one stream
                             history       — last 20 segments
                             optimize      — most expensive streams/types/providers
                             learn         — detect inefficiencies and generate rules
                             learn --apply — write rules as learning facts
                             dashboard     — visual bar-chart dashboard
                               [--today|--week|--month]
                             impact        — is agentboard paying for itself?
                               tokens per stream + per-task-type monthly trend
                             One entry = one context segment. Log at every
                             context clear, provider switch, or stream closure.
  version                    Print version
  help                       Show this help

PHILOSOPHY
  No stack pre-picking. No assumptions. The LLM decides what conventions to
  write based on your actual codebase during activation.
EOF
}

