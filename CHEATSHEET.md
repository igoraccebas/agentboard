# Agentboard Cheat Sheet

Shared work-state and project-truth across Claude Code, Codex CLI, and Gemini
CLI. Agentboard shares files, not chat history — each CLI loads the same
`.platform/` pack on its own.

## Setup

```bash
agentboard install                   # symlink to ~/bin (adds to PATH)
agentboard init                      # scaffold .platform/ into current project
```

---

## Project lifecycle

```bash
agentboard update [--dry-run]        # pull in newer shipped files (keeps project truth)
agentboard sync [--apply|--list]     # sync AGENTS.md / GEMINI.md from CLAUDE.md
agentboard bootstrap [--apply-domains]  # discover repos, suggest domains & streams
agentboard migrate [--apply]         # upgrade legacy stream/domain files to v1 metadata
agentboard migrate-memory [--apply]  # convert legacy gotchas/playbook/questions/learnings into facts
agentboard brief-upgrade <slug> [--apply]  # rewrite legacy BRIEF.md to single-stream format
agentboard doctor                    # validate .platform/ state, metadata, domain refs
agentboard status                    # print .platform/STATUS.md
agentboard version
agentboard help
```

---

## Domains & Streams

```bash
# Create a domain
agentboard new-domain <slug> [--repo <id>]

# Create a stream
agentboard new-stream <slug> \
  --domain <domain-slug> \
  [--type feature|bug|audit|chore] \
  [--agent codex|claude|gemini] \
  [--repo <id>] \
  [--base-branch develop] \
  [--branch feature/<slug>]

# Inspect
agentboard resolve <stream-slug|domain-slug|repo-id>
agentboard handoff [stream-slug] [--budget <N|Nk>]
                                     # load order + Resume state + branch hint.
                                     # Warns if state is stale; footer tells the
                                     # next agent what to do. --budget drops
                                     # secondary domains when tokens run tight.
agentboard checkpoint <slug> --what "..." --next "..." [--blocker "..."] [--focus "..."] [--diff]
       [--cumulative-in N --cumulative-out N --provider <p> [--model <m>] [--complexity <c>]]
       [--tokens-in N --tokens-out N]   # alt: per-segment deltas instead of cumulative
                                     # save compact "where we are" before handoff.
                                     # Overwrites stream's ## Resume state block,
                                     # prepends Progress log entry, trims to last 10.
                                     # Run before ending session or switching CLI.
                                     # --cumulative-in/out: pass the CLI's running
                                     # session totals (e.g. Claude Code's context
                                     # counter). Agentboard computes the delta so
                                     # mid-session logging never double-counts.
agentboard approve <slug>            # human gate: approve the ## Execution brief
                                     # written by ab-planner (Opus) so the
                                     # execution model may write code. In Claude
                                     # Code this is a yes/no click (bash-guard).
agentboard approve <slug> --revoke   # plan changed: stop execution, re-plan
agentboard close <slug>              # step 1: print harvest checklist — distill
                                     # gotchas/playbook/questions/learnings into
                                     # facts; decisions into memory/decisions.md.
agentboard close <slug> --confirm    # step 2: archive stream, log closure, set
                                     # status=done. Run AFTER the harvest step.
agentboard brief [--all]             # compact project briefing (session start):
                                     # active streams, recent gotchas, open
                                     # questions, top usage pattern.
agentboard tui [--status <s>] [--owner <o>] [--once]
                                     # read-only live dashboard of all streams
                                     # (status colored, refreshes every 5s)
agentboard research <slug> "<q>" [--web] [--dry-run]
                                     # delegate research to local Codex CLI
                                     # (read-only, live output); findings append
                                     # to the stream's ## Research notes.
                                     # optional — needs codex on PATH.
agentboard watch [--interval 10] [--threshold 1] [--stream <slug>] [--once|--stop]
                                     # background poller. every N min, if any
                                     # tracked file changed via git status,
                                     # auto-checkpoints the active stream so
                                     # state stays current during long Codex/
                                     # Gemini sessions. Skips ticks when a
                                     # manual checkpoint happened <5 min ago.
                                     # Typical: `agentboard watch &` at day start.
agentboard install-hooks [--force] [--dry-run]
                                     # Installs Claude Code PreToolUse guard.
                                     # Blocks `git commit`, `git push`,
                                     # `git reset --hard`, `rm -rf` etc. with
                                     # an approval prompt. LLM cannot bypass.
                                     # Fresh `agentboard init` already ships
                                     # the guard — use this on existing projects
                                     # or to re-install after edits.
agentboard progress <slug> [--base <b>] [--note "<text>"] [--dry-run]
                                     # append git diff --stat to stream's Progress log
```

---

## Memory (facts, harvest, capture hooks)

```bash
# One fact per file under .platform/memory/facts/ + generated INDEX.md
agentboard fact new --type gotcha --severity red --domain auth \
  --stream login --title "session cookies need SameSite=Lax"
agentboard fact new --type learning --title "..." --body "..."   # also: playbook | question (decisions → memory/decisions.md)
agentboard fact new --type gotcha --title "temp workaround" --expires 2026-09-01
agentboard fact list [--type t] [--domain d] [--status all]
agentboard fact reindex                  # regenerate INDEX.md
agentboard fact prune                    # list facts past expiry
agentboard fact prune --apply            # mark them expired + reindex (files kept)

# Promote Claude Code's machine-local auto-memory into shared facts
agentboard harvest                       # list candidates (writes nothing)
agentboard harvest --accept 1,3 --type gotcha --domain auth
agentboard harvest --all --dry-run

# Capture that doesn't rely on obedience
agentboard checkpoint --auto             # unattended: picks freshest open stream, derives state from git
agentboard install-hooks                 # Claude Code: PreToolUse guard + SessionEnd auto-checkpoint
agentboard install-hooks --git           # + pre-commit gate for Codex/Gemini (no commit w/o today's checkpoint)
AGENTBOARD_SKIP_CHECKPOINT=1 git commit  # bypass the pre-commit gate once
```

Reading is domain-scoped: `brief` and `handoff` surface red gotchas always,
other facts only when their domains intersect the active work. Full list:
`.platform/memory/INDEX.md`.

---

## Token usage tracking

### Log a segment (run before every context clear or provider switch)

```bash
agentboard usage log \
  --provider claude \
  --model claude-sonnet-4-6 \
  --input 45000 --output 8000 \
  --stream <stream-slug> \
  --type implementation \
  --repo <repo-name> \
  --note "segment 2 — added webhook handler"
```

`--provider` `claude` | `codex` | `gemini`
`--type`     `research` | `implementation` | `debug` | `audit` | `hardening` | `chore`
`--repo`     auto-detected from cwd if omitted
`--note`     optional but recommended

### View & analyse

```bash
agentboard usage summary             # global 30-day totals by provider/model/repo/type
agentboard usage history             # last 20 raw entries
agentboard usage stream <slug>       # all segments for one stream + per-provider totals
agentboard usage dashboard           # visual bar charts (all time)
agentboard usage dashboard --today   # today only
agentboard usage dashboard --week    # last 7 days
agentboard usage dashboard --month   # last 30 days
agentboard usage optimize            # most expensive task types and streams
agentboard usage learn               # detect patterns (MODEL_OVERKILL, RESEARCH_BLOAT …)
agentboard usage learn --apply       # write findings as learning facts
agentboard usage impact              # is agentboard paying for itself? tokens/stream + monthly trend
```

### Direct SQLite queries

```bash
sqlite3 ~/.agentboard/usage.db "
  SELECT stream_slug, SUM(total_tokens) AS total, COUNT(*) AS segments
  FROM usage GROUP BY stream_slug ORDER BY total DESC LIMIT 10;"
```

---

## Multi-repo hub

```bash
agentboard add-repo <path>           # scaffold thin entry files into a sibling repo
```

---

## Token estimation guide

| Session weight | Input estimate | Output estimate |
|---|---|---|
| Light (few reads, short answers) | 10k–25k | 2k–5k |
| Medium (several files, some code) | 25k–60k | 5k–15k |
| Heavy (many files, long impl) | 60k–120k | 15k–40k |
| Context nearly full | 150k–200k | 20k–50k |

Output is typically 10–30% of input. Lean toward over-estimating input.

---

## Usage DB location

```
~/.agentboard/usage.db
```
