# Agentboard

**Shared work-state and project-truth for multi-provider AI workflows.** Agentboard gives Claude Code, Codex CLI, and Gemini CLI a common `.platform/` pack so each provider loads the same project truth, tracks the same workstreams, and can pick up work another provider started.

```bash
cd /path/to/your/project
agentboard init
# then open the project in your AI CLI and say:
# > activate this project
```

Agentboard scaffolds a `.platform/` pack plus root entry files, then hands off to the LLM to scan the actual codebase, ask a few targeted questions, and write project-specific context. No stack picker. No static React/Django/Vite templates pretending to know your repo. The LLM reads the repo and decides.

> **Status:** actively evolving from a proven internal setup used across multi-repo product work. The kit is stack-agnostic; the project-specific intelligence is generated during activation.

---

## How it actually works

Agentboard does **not** move chat history, tool-call state, or in-session memory between providers — nothing does, and pretending otherwise would be dishonest. What Agentboard ships is:

1. **A shared project-truth format** — `.platform/` holds architecture, decisions, domains, conventions, and a live work-stream registry. Plain markdown, readable by any LLM.
2. **Provider-neutral entry files** — `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` at the repo root point each CLI at the same `.platform/` pack. Claude Code, Codex CLI, and Gemini CLI each auto-load their own entry file on session start.
3. **A deterministic handoff packet** — `agentboard handoff <stream>` prints the minimum load order (brief → stream → domains → repos) plus the git branch hint, so the next provider can resume without a full re-brief.
4. **A persistent work layer** — streams registered in `work/ACTIVE.md` survive context compaction, session death, and provider switches. What doesn't survive: the chat. What does: the work state.

Result: start a stream in Claude Code, resume it in Codex CLI, finish it in Gemini CLI — each session loads the same files in the same order, with the same stream metadata, and with git as the cross-session edit log.

---

## The problem

Every new AI session starts half-blind:

- The agent re-discovers decisions you already made
- The agent loads the wrong files and misses cross-layer constraints
- Parallel sessions collide because there is no shared task registry
- Useful context disappears when the session ends

Agentboard solves that by shipping a reusable **process layer** and leaving **project truth** to be written from your codebase during activation.

---

## What Agentboard actually is

Agentboard is not just a prompt stub. It gives a project:

- Root entry files: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`
- A shared `.platform/` reference pack
- Workflow skills installed for multiple providers
- Workstream tracking that survives context loss
- Domain-first context files so agents load the right slice of the system
- Optional hub mode for multi-repo platforms

The design split is deliberate:

- **Generic, shipped verbatim:** workflow rules, onboarding path, sync script, work tracking protocol, repo templates, hooks
- **Project-specific, written during activation:** architecture, decisions, repos, domain files, conventions, current priorities

---

## Quick start

### Single repo

```bash
cd /path/to/project
agentboard init
```

Then open the repo in Claude Code, Codex CLI, or Gemini CLI and say:

```text
activate this project
```

### Multi-repo platform hub

If you run `agentboard init` in an empty parent folder or a folder that only contains sibling repos, Agentboard can switch to **hub mode**.

In hub mode:

1. `.platform/` lives in the hub folder
2. `.platform/repos.md` lists the sibling repos
3. `agentboard add-repo <path>` scaffolds thin entry files into each sibling repo
4. activation scans the sibling repos, not the hub folder itself

---

## CI and merge protection

Agentboard now ships a GitHub Actions merge-gate workflow in `.github/workflows/ci.yml`.

It runs on:

- pull requests targeting `develop`
- pull requests targeting `main`
- direct pushes to `develop`
- direct pushes to `main`

The workflow runs:

- `unit-tests` → `bash tests/unit.sh`
- `integration-tests` → `bash tests/integration.sh`
- `ci-gate` → final required gate that depends on both jobs

Important: **GitHub Actions alone does not block merges.**
To actually prevent merges when tests fail, you must configure GitHub branch protection or rulesets for both `develop` and `main` and mark these checks as required:

- `unit-tests`
- `integration-tests`
- `ci-gate`

Recommended rules for both branches:

- require a pull request before merging
- require status checks to pass before merging
- require branches to be up to date before merging
- include administrators if you want the rule to apply to everyone

If you later add a deploy workflow, make it depend on the same green checks or only allow deploys from protected branches.

---

The behavior suite in `tests/behavior/` is deliberately **not** a required
check: it calls a live model and costs money, so it runs on demand.

## What `agentboard init` does

`init` is intentionally small and generic. It does **not** make stack-specific decisions.

It:

1. Asks 2 questions: project name and one-line description
2. Copies the `.platform/` skeleton
3. Writes root entry stubs if they do not already exist
4. Preserves existing `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md`
5. Installs shared skills into `.claude/skills/` and `.agents/skills/`
6. Installs `.claude/settings.json` if absent, so Claude Code can enforce closure hooks

If a root entry file already exists, `init` does not overwrite it. Activation later prepends the Agentboard section and preserves the original content below.

---

## What activation does

When you say `activate this project`, the root entry file tells the agent to read `.platform/ACTIVATE.md` or `.platform/ACTIVATE-HUB.md` and follow the activation protocol.

The activation flow is:

1. **Scan** the repo or sibling repos: tree, manifests, README, env examples, git history, source entry points
2. **Interview** the user with 5-8 targeted questions
3. **Fill** the project truth into the `.platform/` pack
4. **Install or merge** the steady-state root entry files without deleting user content
5. **Sync** `AGENTS.md` and `GEMINI.md` from `CLAUDE.md` where safe
6. **Confirm** what was written and what still needs review

The agent writes project-specific files from what it actually finds, including:

- `.platform/STATUS.md`
- `.platform/architecture.md`
- `.platform/memory/decisions.md`
- `.platform/repos.md`
- `.platform/domains/*.md`
- `.platform/conventions/*.md`
- `.platform/work/BRIEF.md` when there is an active focus area

---

## Domain-first context

A key design choice is that feature context is **domain-first**, not repo-first.

Instead of forcing every agent to read:

- `backend.md`
- `frontend.md`
- `widget.md`

for one feature, activation creates focused files like:

- `.platform/domains/auth.md`
- `.platform/domains/orders.md`
- `.platform/domains/billing.md`

Each domain file is cross-layer. It can cover backend, frontend, widget, and API contract for that concern in one place. Repo-wide docs still exist, but they are for conventions and navigation, not feature briefings.

This keeps context small and makes multi-agent work much more reliable.

---

## Active work model

Agentboard ships a persistent work layer under `.platform/work/`:

- `BRIEF.md` — what the current active feature is, why it matters, what context to load
- `ACTIVE.md` — registry of live workstreams
- `TEMPLATE.md` — template for a new workstream
- `archive/` — completed workstreams

Streams and domains are meant to carry lightweight metadata so tooling can validate state without turning `.platform/` into a database.

The workflow expects non-trivial work to be registered before execution:

1. check `work/ACTIVE.md`
2. ensure a domain file exists
3. create `work/<stream>.md`
4. add the stream to `ACTIVE.md`
5. update `BRIEF.md`

This is what makes work resumable after context compaction or handoff to another agent.

---

## Compounding memory

Native AI-CLI memory (Claude Code auto-memory, Codex transcripts, Gemini
checkpoints) is **per-machine and per-provider** — your teammate's agent and
your other CLI never see it. Agentboard's memory layer is the opposite:
small markdown files committed to the repo, readable by any LLM, shared
through git.

Four mechanisms make it compound instead of rot:

**1. Facts — one per file.** `agentboard fact new` writes each gotcha,
learning, playbook entry, or open question as its own small file
under `.platform/memory/facts/`, with a generated `INDEX.md`. Parallel
sessions stop colliding in git (two sessions append two different files),
and each fact carries domains, a source stream, and an optional expiry.

**2. Capture that doesn't rely on obedience.** Claude Code gets a SessionEnd
hook that auto-runs `agentboard checkpoint --auto` when a session ends — work
state is captured when the hook runs successfully. For providers without an installed session hook,
`agentboard install-hooks --git` installs a pre-commit fallback that blocks
code commits when no open stream was checkpointed today
(`AGENTBOARD_SKIP_CHECKPOINT=1` bypasses). Enforcement coverage is honest:
session hooks where installed, with a commit-time fallback across providers.

**3. Harvest — private notes become team truth.** Claude Code writes its own
machine-local notes as you work. `agentboard harvest` lists the notes not yet
in the shared binder and promotes the ones you accept into committed facts.
Review before accepting — private notes can contain machine-specific detail.

**4. Right-dose reading.** `brief` and `handoff` load facts scoped to the
domains of the work at hand: red (never-forget) gotchas always surface;
everything else only when its domain is active. `handoff --budget 8k` trims
the pack to a token budget. The full list stays one `INDEX.md` away.

And one honest meter: `agentboard usage impact` reports tokens-per-stream and
the per-task-type monthly trend. If compounding memory works, the same kind of
task gets cheaper over months. If it doesn't, this is where you find out.

---

## Plan → approve → execute (split-model workflow)

Strong execution models are expensive per token; strong planning models are
cheaper. Agentboard ships an opt-in gate that splits the work:

1. **Plan** — the shipped `ab-planner` Claude Code agent (pinned to a
   planning model like Opus) researches the repo and writes an
   `## Execution brief` into the stream file: objective, Do / Do NOT lines,
   files in scope, acceptance criteria. It never writes code.
2. **Approve** — a human runs `agentboard approve <slug>`. In Claude Code
   the bash-guard requests native approval for recognized commands. Local
   metadata remains editable: this is a workflow guardrail, not proof of
   human identity. Native sandbox and permission settings still apply.
3. **Execute** — the execution model (your strongest available coder)
   implements within the brief. `handoff` and `brief` show the gate status
   to every resuming agent; an unapproved brief reads as "do not write code".

The gate exists only on streams that have a brief — trivial work is never
taxed. `usage impact` tells you whether the split actually saves tokens.

## Reliable state and provider configuration

Codex roles inherit the user's selected model. Role config paths are relative
to `.codex/config.toml`; research roles are read-only and coding uses
`workspace-write`. Existing customized configs are not overwritten automatically.
For older generated configs, change `.codex/agents/name.toml` to `agents/name.toml`,
replace `sandbox_mode = "full"` with `"workspace-write"`, and remove obsolete
model pins. `agentboard install-hooks --force` refreshes Claude settings with
a backup; review the diff and retain any custom hooks.

`close --confirm` requires recorded `closure_approved: true` after owner sign-off
and no unchecked items in `## Done criteria`. It archives the stream, updates
the registry and log, and clears BRIEF if that was the primary stream.
Lifecycle writers (`new-stream`, `checkpoint`, `research`, `approve`, `progress`,
and `close`) serialize their state updates. Multi-file closure and
stream creation retain recovery snapshots until the operation succeeds.
Direct editor writes and memory/index maintenance do not participate in this lock.
If a process is
force-killed, inspect `.platform/.transaction.*` and its `targets` manifest
before removing the empty `.platform/.state.lock` directory and retrying.

For cumulative usage, pass `--session-id <stable-id>` to `usage log` or
`checkpoint`, or set `AGENTBOARD_SESSION_ID` once per provider session.
Accounting is isolated by canonical project path, provider, stream and
session, and duplicate/out-of-order observations cannot double-count that session.
Incremental reports advance the same baseline, so later cumulative reports do
not recount them. Incremental reports are additive, not retry-idempotent: use
cumulative counters when retrying a report that may already have succeeded.
`--session-key` remains an alias. Without an ID, a daily compatibility mode
detects counter drops and saves the new baseline; it cannot distinguish a
new session from an old report. Start a new explicit session after upgrading
from legacy accounting. Historical records are preserved, not retroactively corrected.

Entry-file sync updates only the block delimited by
`<!-- agentboard:root-entry:begin v=1 -->` and
`<!-- agentboard:root-entry:end v=1 -->`. Put shared rules inside that block
in CLAUDE.md and provider-specific instructions outside it. Unmarked targets
retain their content below a new block. Unmarked or malformed sources require
manual boundary selection; sync never guesses which instructions may be replaced.

---

## Skills

`agentboard init` installs a shared skill pack for all providers:

- `ab-triage`
- `ab-workflow`
- `ab-research`
- `ab-pm`
- `ab-architect`
- `ab-test-writer`
- `ab-security`
- `ab-qa`
- `ab-review`
- `ab-debug`

Install behavior is additive:

- Claude Code gets `.claude/skills/`
- Codex CLI and Gemini workflows get `.agents/skills/`
- existing skills with the same name are kept during `init`

Each skill has a `SKILL.md` and uses progressive disclosure: the name and description are visible at session start, and the full protocol loads on demand.

---

### Do the skills actually work?

Unit tests prove the CLI. `tests/behavior/` proves the skills: it runs real
headless Claude sessions in throwaway `agentboard init` projects and checks,
mechanically, that the agent wrote the regression test before the fix, admitted
when it could not reproduce, and refused to close a stream without your
approval. `--proof` shows a broken skill copy failing. See `tests/behavior/README.md`.

## What ships in the kit

```text
your-project/
├── CLAUDE.md
├── AGENTS.md
├── GEMINI.md
├── .claude/
│   └── settings.json
├── .agents/
│   └── skills/
└── .platform/
    ├── ACTIVATE.md / ACTIVATE-HUB.md
    ├── ONBOARDING.md
    ├── workflow.md
    ├── STATUS.md
    ├── architecture.md
    ├── decisions.md
    ├── repos.md
    ├── log.md
    ├── BACKLOG.md
    ├── learnings.md
    ├── agents/
    ├── domains/
    │   └── TEMPLATE.md
    ├── work/
    │   ├── BRIEF.md
    │   ├── ACTIVE.md
    │   ├── TEMPLATE.md
    │   └── archive/
    ├── sessions/
    │   └── ACTIVE.md
    ├── scripts/
    │   ├── sync-context.sh
    │   └── hooks/
    └── templates/
        └── repo/
```

After activation, the agent also creates project-specific directories and files such as:

- `.platform/conventions/*.md`
- `.platform/domains/*.md`
- `.platform/domains/TEMPLATE.md`
- per-repo deep references in hub mode

So the shipped scaffold is the operational shell; activation fills in the project-specific content.

---

## Commands

```bash
agentboard install
agentboard init
agentboard update [--dry-run]
agentboard sync [--apply|--list]
agentboard bootstrap [--apply-domains]
agentboard migrate [--apply]
agentboard migrate-memory [--apply]
agentboard brief-upgrade [stream-slug] [--apply]
agentboard doctor
agentboard new-domain <slug> [repo-id ...] [--repo <repo-id>]
agentboard new-stream <slug> --domain <domain-slug> [--domain <domain-slug> ...] [--type feature] [--agent codex] [--repo repo-primary] [--repo <repo-id> ...]
agentboard resolve <stream-slug|stream-id|domain-slug|domain-id|repo-id>
agentboard fact new --type <gotcha|learning|playbook|question> --title "..." [--domain <d>] [--stream <s>] [--severity red|yellow|green] [--expires YYYY-MM-DD]
agentboard fact list [--type <t>] [--domain <d>] [--status <s>|all]
agentboard fact reindex
agentboard fact prune [--apply]
agentboard harvest [--accept <n,m>|--all] [--type <t>] [--domain <d>] [--dry-run]
agentboard handoff [stream-slug]
agentboard approve <stream-slug> [--revoke]
agentboard progress <stream-slug> [--base <branch>] [--note "<text>"] [--dry-run]
agentboard status
agentboard tui [--status <s>] [--owner <name>] [--interval N] [--once]
agentboard research <stream-slug> "<question>" [--web] [--model <m>] [--profile <p>] [--dry-run]
agentboard add-repo <path>
agentboard usage log --provider <name> --input <N> --output <N> [--model <M>] [--stream <S>] [--repo <R>] [--type <T>] [--note <text>]
agentboard usage summary
agentboard usage history
agentboard usage stream <stream-slug>
agentboard usage dashboard [--today|--week|--month]
agentboard usage impact
agentboard usage learn [--apply]
agentboard version
agentboard help
```

### Command notes

- `install` creates a symlink for `agentboard` in your user bin directory and prints the PATH snippet to add if needed
- `init` scaffolds the kit into the current directory
- `update` refreshes shipped process files and skill protocols without touching project-specific docs
- `sync` keeps `AGENTS.md` and `GEMINI.md` aligned with `CLAUDE.md`
- `bootstrap` discovers repo layout, fills `repos.md`, scaffolds missing deep-reference files, infers broad repo roles plus optional stack hints, ingests local project artifacts into repo refs, suggests starter domains from repo structure, suggests stream commands from git branch state and dirty worktree semantics, and syncs hub repo paths into `sync-context.sh`; use `--apply-domains` to create the inferred domain stubs
- `migrate` upgrades legacy pre-frontmatter stream/domain files to metadata v1 when Agentboard can infer the missing fields safely
- `brief-upgrade` rewrites a legacy multi-stream `work/BRIEF.md` into the newer single-stream format for one chosen stream
- `doctor` validates active `.platform/` state, stream/domain metadata, domain references, and repo IDs against the repo registry
- `new-domain` bootstraps a domain file with metadata and can assign multiple repo IDs up front
- `new-stream` bootstraps a stream file, registers it in `work/ACTIVE.md`, and seeds `work/BRIEF.md` when the brief is still a placeholder; repeat `--domain` and `--repo` when the stream spans multiple areas or repos
- `resolve` turns a canonical stream/domain/repo reference into the exact file or repo record to load
- `handoff` prints the minimum file load order, repo scope, and current-state summary another LLM needs to resume a stream without a full re-brief
- `progress` appends a git-diff summary (`git diff --stat <base>...HEAD`) to the stream's `## Progress log` section, stamped with timestamp and branch; use this instead of hand-typing what changed
- `tui` renders a read-only auto-refreshing dashboard of all streams; `--once` for a single render
- `research` delegates the research phase to a locally-installed Codex CLI (read-only, headless): activity streams live to the terminal, final findings append as a dated block under the stream's `## Research notes`; `--web` enables Codex web search. Optional — requires `codex` on PATH (or `AGENTBOARD_CODEX_BIN`); no other command depends on it. Agent-invoked by design: sessions run it at the Research stage, humans rarely type it
- `status` prints `.platform/STATUS.md`
- `add-repo` scaffolds entry files into a sibling repo in hub mode and refuses to overwrite existing root entry files
- `usage log` records a token segment to `~/.agentboard/usage.db`; `usage summary/history/stream/dashboard/learn` aggregate and visualise the data — see `CHEATSHEET.md` for the full reference

---

## Updating existing installs

As Agentboard evolves, `agentboard update` lets a project pull in newer process files without clobbering project truth.

For older projects that still use the legacy framework shape, use the dedicated migration flow in [MIGRATION_GUIDE.md](/Users/danilulmashev/Documents/GitHub/agentboard/MIGRATION_GUIDE.md).

It updates things like:

- `workflow.md`
- `ONBOARDING.md`
- `ACTIVATE*.md`
- `.platform/agents/*.md`
- shipped convention templates if the kit includes them
- `scripts/sync-context.sh`
- shipped skills

It does **not** overwrite project-authored operational state such as:

- `architecture.md`
- `decisions.md`
- `repos.md`
- `STATUS.md`
- `log.md`
- `work/*`
- `domains/*`

### Migrating older projects

If a project already has an older `.platform/` layout, the current upgrade path is:

```bash
agentboard update
agentboard migrate
agentboard migrate --apply
agentboard brief-upgrade <stream-slug> --apply
agentboard doctor
```

Use `brief-upgrade <stream-slug>` without `--apply` first if you want to preview the rewritten BRIEF before writing it.

The full step-by-step guide lives in [MIGRATION_GUIDE.md](/Users/danilulmashev/Documents/GitHub/agentboard/MIGRATION_GUIDE.md).

---

## Single repo vs hub mode

### Single repo

- `.platform/` lives beside the app code
- activation scans the current repo
- `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` live at the repo root

### Hub mode

- the hub folder holds `.platform/` and shared cross-repo truth
- sibling repos get thin entry stubs
- activation scans all listed sibling repos
- per-repo deep references can point agents back into the shared platform pack

Hub mode is useful when your system is split across backend, frontend, mobile, widget, or infra repos but you still want one shared context brain.

---

## Why no stack pre-picking

Traditional scaffolding asks: React or Vue? Django or FastAPI? Postgres or MongoDB?

Agentboard does not, for three reasons:

1. The stack is already visible in the repo
2. Static stack templates go stale quickly
3. The LLM can write rules for the actual project, not generic best practice

The point of the kit is to scaffold the **structure** and let activation generate the **truth**.

---

## Install

```bash
git clone https://github.com/[you]/agentboard ~/code/agentboard
~/code/agentboard/bin/agentboard install
```

By default, `agentboard install` symlinks into your user bin directory such as `~/.local/bin/agentboard` and tells you what to add to your shell config if that directory is not already on your `PATH`.

You can also preview or override the target:

```bash
~/code/agentboard/bin/agentboard install --dry-run
~/code/agentboard/bin/agentboard install --dir ~/bin
```

---

## License

MIT
