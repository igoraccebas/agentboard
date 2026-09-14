<!-- agentboard:root-entry:begin v=1 -->
## Shared workflow

This repository is activated and uses `.platform/` for its own work state.
Start with `agentboard brief`, then `.platform/work/BRIEF.md` and `.platform/work/ACTIVE.md`.
Use the user's stated task to choose the stream; ask only when the task is ambiguous.
Run `agentboard handoff <slug>` before resuming an existing stream.
Follow `.platform/workflow.md` for registration, verification, analysis, and closure.
For a stream/feature audit, read its analysis protocol before dispatching reviewers or synthesizing results, and anchor the report in the stream.
Preserve unrelated edits and provider-specific instructions. Existing task authorization remains valid. Commit and merge require passing checks and explicit owner authorization; honor prior authorization for the same scope. Closure follows the evidence and owner sign-off sequence in `.platform/workflow.md`.
Checkpoint before ending work. Record only known usage and actual model identity.
Store lessons through `agentboard fact new`; decisions and session outcomes belong in `.platform/memory/decisions.md` and `.platform/memory/log.md`.
<!-- agentboard:root-entry:end v=1 -->

# Agentboard — Codex CLI Entry

> Bash CLI for shared work-state across Claude Code, Codex CLI, and Gemini CLI

**Status:** Activated. This repository uses `.platform/` to track work on Agentboard itself.

---

## You are an AI agent reading this file (Codex CLI / OpenAI Agents)

This file is auto-loaded when you open this project in Codex CLI. All mandatory protocols below apply to you exactly as they apply to Claude Code and Gemini CLI.

---

## Active Work (`.platform/work/`)

### Session start (every session — mandatory)

1. **Run `agentboard brief`** first — compact "state of the project" view: active streams, recent gotchas (landmines the 20-year-employee would warn you about), open questions, latest usage pattern. This is your institutional memory; read it before touching code.
2. Then read the narrative docs in order:
   - **`work/BRIEF.md`** — what we're building, why, current state, relevant context
   - **`work/ACTIVE.md`** — stream registry

If there is an active stream you're resuming, **run `agentboard handoff <slug>`** before anything else — it prints the exact load order and the Resume state (what just happened, current focus, next action) left by the previous agent. This is how context is shared between Claude, Codex, and Gemini without re-explaining.

Use the user's stated task to select or create the stream. Announce the next action; ask which stream only if the task is ambiguous.

### Context handoff — before ending or switching providers (mandatory)

When context is running low, you're ending the session, or you're about to hand off to another CLI (Claude → Codex, Codex → Gemini, etc.), **run**:

```bash
agentboard checkpoint <stream-slug> --what "<1-2 lines of what just happened>" --next "<one sentence: what to do next>" \
  --cumulative-in <N> --cumulative-out <N> --provider codex --model <model-id> [--complexity trivial|normal|heavy]
```

For `--cumulative-in` / `--cumulative-out` pass your **current session totals** (running counters, not per-segment deltas). Pass a stable `--session-id` (or `AGENTBOARD_SESSION_ID`) for this provider session so Agentboard can subtract its previously recorded totals. Omit the token fields if you don't know the counts; the checkpoint itself still works.

This overwrites the stream file's `## Resume state` block with compact "where we are" state and trims the progress log to the last 10 entries. The next agent runs `agentboard handoff <slug>` and picks up from there — **no re-explaining the feature**. Without this, the next agent has only stale state.

### Stream closure — before archiving (mandatory harvest ritual)

When a stream is done, **do not just archive the file**. Run the two-step close to feed project memory:

```bash
# Step 1 — print the harvest checklist
agentboard close <stream-slug>
```

Follow the printed harvest checklist. Record gotchas, practices, questions, and
root causes with `agentboard fact new` in `.platform/memory/facts/`, tagged with
the relevant domain and stream. Record locked decisions in
`.platform/memory/decisions.md`; skip categories with nothing to add.

```bash
# Step 2 — after harvest, archive the stream
agentboard close <stream-slug> --confirm
```

This is the compounding ritual. Each close adds durable knowledge so the next agent running `agentboard brief` inherits what you learned, without you being there to explain it.

### Long session fallback — `agentboard watch` (optional)

For heavy sessions where checkpoints may be forgotten, the user can start a
background watcher:

```bash
agentboard watch &
```

It polls `git status` every 10 min and auto-checkpoints the active stream
whenever ≥1 tracked file has changed since the last poll. The auto-content is
mechanical (file list + carried-over Next action) — always prefer your own
explicit checkpoints with specific `--what` / `--next`. The watcher skips
ticks when it sees a manual checkpoint happened in the last 5 minutes, so it
never clobbers fresh state. Stop with `agentboard watch --stop`.

### New task bootstrap (before any non-trivial task — mandatory)

When the user gives a task not already tracked in `ACTIVE.md`, **stop and complete these steps before any research, planning, or code**:

1. **Check `ACTIVE.md`** — does this stream already exist? If yes, load it and continue.
2. **Check `.platform/domains/`** — does a domain file exist for this feature area?
   - No → **create `.platform/domains/<name>.md`** with cross-layer touch-point inventory first.
3. **Create `work/<stream-slug>.md`** — what we're building, why, done criteria, key files, current state.
4. **Add a row to `work/ACTIVE.md`** — slug / type / in-progress / agent / date.
5. **Update `work/BRIEF.md`** — point to new primary stream + list domain file under "Relevant context".
6. Only then proceed to triage → research → propose → execute.

> **Non-negotiable.** Skipping this means context is lost when the session ends. Trivial single-file fixes are the only exception.

## Reference pack

**Loading rule: only load files listed in `work/BRIEF.md` § "Relevant context".** Do not auto-load the full pack. Never read `work/archive/*` unless explicitly asked. **Never load `BACKLOG.md` or `learnings.md` at session start** — read them only when the user asks, or when appending.

- `.platform/workflow.md` — the 6-stage inline workflow **← read this before running any multi-step protocol**
- `.platform/ONBOARDING.md` — 7-step onboarding path for future sessions
- `.platform/memory/facts/` — search relevant learning facts before diagnosing non-obvious bugs; check `.platform/memory/learnings.md` before migration or `.platform/memory/legacy/learnings.md` after migration when present

## Mandatory Protocol — Stream Audit / Analysis

Whenever the user asks to audit, analyze, or check the state of a stream or its implementation (e.g. "audit the stream", "analyze what we've done on X", "check the state of \<feature\>", or references a `work/*.md` file explicitly), you MUST:

1. **Read `.platform/workflow.md` first** — before touching any agent results or synthesizing anything.
2. **Follow the Stream / Feature Analysis Protocol exactly** as written there — no shortcuts, no partial synthesis before all agents finish, no skipping the standardized template or the stream-file anchor step.

This applies even when resuming after context compaction. A compressed context summary is NOT a substitute for reading the protocol spec.

## Stream Closure — Human Approval Required

**Only the human/owner declares a stream complete.** You never self-declare completion. You may say "I believe this is done — here is the evidence" and propose closure, but the final decision belongs to the developer. No exceptions.

**Before running Steps 7–9 of the Stream Closure Protocol** (archiving the stream file, removing from ACTIVE.md, appending to log.md), you MUST:
1. Present evidence of completion to the user.
2. Wait for explicit human sign-off.
3. Verify the stream file has `closure_approved: true` before archiving.

**Enforcement:** Agentboard's Claude hooks cover selected operations; other
provider enforcement must be verified in its native host. The shared CLI checks
recorded approval and done criteria on `close --confirm`. Editable flags and hooks
are workflow guardrails, not independent proof of human identity.

Full protocol: `.platform/workflow.md` → "Stream Closure Protocol".

## Skills available to you

Installed into `.agents/skills/` by `agentboard init`.

`ab-triage`, `ab-workflow`, `ab-research`, `ab-pm`, `ab-architect`, `ab-test-writer`, `ab-security`, `ab-qa`, `ab-review`, `ab-debug`

Read each skill's `SKILL.md` on first use to understand its protocol.

---

_The managed shared block is synchronized by `.platform/scripts/sync-context.sh`; provider-specific instructions outside it are preserved._
