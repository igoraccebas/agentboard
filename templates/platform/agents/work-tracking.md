# Work Tracking Convention

## Purpose

Lightweight "current work" signal that survives context clears and parallel AI sessions.
Lives in `.platform/work/`. Complements `.platform/STATUS.md` (project-level feature status)
— `work/` is what you're touching *this session*, not what's shipped or planned long-term.

## Directory layout

```
.platform/work/
├── ACTIVE.md           ← registry; read every session start
├── <slug>.md           ← one file per active workstream
└── archive/
    └── <slug>.md       ← completed workstreams (grep-able history)
```

## Session start protocol (mandatory)

Read in order — stop as soon as you have enough to orient:

1. **`work/BRIEF.md`** — narrative brief: what we're building, why, current state, and which reference docs to load (§ "Relevant context")
2. **`work/ACTIVE.md`** — stream registry:
   - **0 streams** → proceed normally, ask user what to work on
   - **1 stream** → confirm: "Resuming **<stream>** — next: <next action>. Continue?"
   - **2+ streams** → ask user which one
3. Load `work/<slug>.md` only when you need full detail

## Scoped context loading (mandatory)

**Only load the reference files listed in `work/BRIEF.md` § "Relevant context".** Do not load the full `.platform/` pack.

- If the feature touches the backend → load `backend.md`. Not the frontend docs.
- If the feature touches one widget → load that widget's doc. Not the other widgets'.
- If the feature is UI-only → load the UI doc. Not the backend doc.
- **Never read `work/archive/*`** — completed work is irrelevant to the current feature.

This keeps context windows lean and prevents agents from being briefed on work that has nothing to do with their task. One feature = one reading list.

## Starting a new workstream

> **Hard rule: register before you work.** Do not run a single search, write a single line of code, or make a single proposal until the stream file exists and `ACTIVE.md` has the row. If the context is cleared mid-task, the stream file is the only way to resume. Skipping registration = zero traceability = unrecoverable lost context.

1. **Check for a domain file.** Does `.platform/domains/<feature>.md` exist for this feature?
   - **Yes** → continue
   - **No** → create it first (see `agents/context-organization.md`). A workstream without a domain file has no focused context for the next agent to load.
2. **Update `work/BRIEF.md`** — replace with the new feature brief; set `## Relevant context` to the domain file(s) this workstream touches.
3. Copy `TEMPLATE.md` to `work/<stream-slug>.md`
4. Fill in the frontmatter first: `stream_id`, `slug`, `type`, `status`, `agent_owner`, `domain_slugs`, `repo_ids`, `created_at`, `updated_at`
   `stream_id` should stay canonical: `stream-<slug>`.
5. Fill in: scope (3–5 bullets), done criteria (measurable), next action
6. Add a row to `ACTIVE.md`

If you want a fast, valid bootstrap instead of hand-editing, use:

```bash
agentboard new-domain <domain-slug> [repo-id ...] [--repo <repo-id>]
agentboard new-stream <stream-slug> --domain <domain-slug> [--domain <domain-slug> ...] [--type feature] [--agent codex] [--repo repo-primary] [--repo <repo-id> ...]
agentboard resolve <stream-slug|stream-id|domain-slug|domain-id|repo-id>
```

Stream slug: short-kebab-case, e.g. `stripe-webhook-retry` or `menu-banner-bug`.

## Adding a missing domain file (rescan)

When you discover a feature that exists in the codebase but has no domain file:

1. Grep the backend for the relevant app/model names
2. Find the admin feature section and RTK Query endpoints
3. Identify which widgets (if any) touch this domain
4. Write `.platform/domains/<feature>.md` following the structure in `context-organization.md`
5. Fill in the frontmatter: `domain_id`, `slug`, `status`, `repo_ids`, `related_domain_slugs`, `created_at`, `updated_at`

To audit ALL missing domains at once: read the feature list from `STATUS.md` (or ask the user "what are all the features in this app?"), list the existing files in `.platform/domains/`, and write a domain file for each feature that doesn't have one. Keep each under 150 lines.

## During work

- Append to **Progress log** after each significant step (commit, test run, decision)
- Keep **Next action** current — this is what the next session resumes from
- Append to **Key decisions** when you make an architectural or product choice
- Update **Status** when it changes

## Concurrent AI sessions (Claude Code + Codex + Gemini)

No hard locks. The `Agent` column in `ACTIVE.md` is a soft signal:
- Set it to `claude-code`, `codex`, or `gemini` when you pick up a stream
- If you see a different agent owns a stream, check with the user before touching it
- Multiple agents CAN work different streams simultaneously — each has its own file

## Done ritual (agent-proposed, user-confirmed)

When all done criteria are met:
1. Agent sets status → `awaiting-verification`
2. Agent posts done-criteria checklist with ✅/❌ for each item and runs `agentboard close <slug>` for the harvest checklist
3. **Owner approves** by running `agentboard close <slug> --approve` themselves — the agent never records approval, never ticks a criterion the owner owns, and treats "close it" in chat as a request, not this approval
4. After the owner's approval, run `agentboard close <slug> --confirm` — the only archival path. It moves `work/<slug>.md` → `work/archive/<slug>.md`, removes the row from `ACTIVE.md`, and appends the closure line to `.platform/memory/log.md`
5. Update `memory/` if anything learned should persist cross-session

Hard blockers (Claude Code hooks; Codex and Gemini rely on the CLI check alone):
- The closure gate blocks closing or removing an `ACTIVE.md` row unless the CLI recorded the owner's approval and every item under `## Done criteria` is checked.
- It also blocks hand edits that grant approval in a stream file, ticking a criterion whose text names the owner, and any write under `work/archive/`.
- The bash guard asks before `rm`/`mv`/`cp`/`sed -i`/redirection touching `.platform/work/`.

## What NOT to put in a stream file

- Full implementation plans (those live in chat)
- Large code snippets (those live in the codebase)
- More than ~60 lines total — if it's growing, you're over-documenting
