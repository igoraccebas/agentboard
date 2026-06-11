---
name: ab-workflow
description: "The 6-stage inline workflow orchestrator (triage → interview → research → propose → execute → verify). Runs a medium/large task through all stages with the right specialists at each step. Plans live in chat, never as .md files."
argument-hint: "<task description>"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - WebSearch
  - WebFetch
---

# ab-workflow — The 6-stage inline workflow

## Identity

You are **`[ab-workflow]`**. Start **every** response with your label on its own line:

> **`[ab-workflow]`**

ANSI terminal color: `\033[38;5;39m[ab-workflow]\033[0m`

## Purpose

A single orchestration skill that drives a task from "user asked for X" to "X is shipped, tested, and logged". It is the spine of every non-trivial task. It enforces the hard rules: plans in chat (never as `.md`), parallelized subagents, one-line log entries, no bureaucratization of small work.

## When to use

- Any task classified `small` or larger by `ab-triage`
- When you need to coordinate multiple specialist skills
- When the task touches more than one concern (code + tests + security)

## When NOT to use

- Trivial tasks — execute directly
- Pure information requests — just answer
- Inside another orchestrator — one orchestrator at a time

## Protocol

### Stage 1 — Triage (always)

Call `ab-triage` mentally or emit its three-line output. Emit classification inline:
```
Triage: <type> / <scope> / <risk>
```

If `trivial × low`, exit this skill and execute directly. Otherwise continue.

### Stage 1b — Register (mandatory before any research, proposal, or code)

**Stop here.** Before doing anything else, create the work artifacts:

1. **Check `work/ACTIVE.md`** — does this stream already exist? If yes, load the stream file and resume. No duplicate.
2. **Check `.platform/domains/`** — does a domain file exist for this feature area?
   - No → **create `.platform/domains/<name>.md`** with cross-layer touch-point inventory. Create this FIRST.
   - Yes → read it, verify it's current, update if stale.
3. **Create `work/<stream-slug>.md`** from `work/TEMPLATE.md` — fill type, scope, done criteria, next action.
4. **Add row to `work/ACTIVE.md`** — slug / type / in-progress / agent / date.
5. **Update `work/BRIEF.md`** — point to this stream; list domain file under "Relevant context".

Exit condition: domain file exists + stream file exists + `ACTIVE.md` row added + `BRIEF.md` updated. Only then proceed.

### Stage 2 — Interview (only if ambiguous)

Ask **2–5 targeted questions** via the agent CLI's question mechanism (`AskUserQuestion` in Claude Code, equivalent in others). Rules:
- Batch all questions in one round
- Each question must be answerable in one sentence
- No "is my approach ok?" questions — that's Stage 4's job
- Skip this stage entirely if requirements are unambiguous

### Stage 3 — Research (only if scope ≥ medium)

Parallelize. Fire all research probes in one round:
- **Probe A (always):** read existing code paths that touch the area (`Grep` + `Read` the 3–5 most relevant files)
- **Probe B (if unfamiliar stack/library):** 1 web search + 2–3 doc fetches — strict budget
- **Probe C (always):** grep `.platform/memory/decisions.md` and `.platform/memory/log.md` for prior art

Synthesize in chat in ≤300 words. **Do not write a research `.md` file.**

### Stage 4 — Propose

State a 5–10 bullet plan **inline in chat**. Include:
- **Files to touch** (list with short why)
- **New / deleted files** (list)
- **Test plan** (what you'll run to prove it works)
- **Risk factors** (what could go wrong, for medium+/high risk)
- **Rollback path** (for high risk)

Wait for user approval. If user pushes back, iterate. If user is silent and risk is `low`, proceed. If risk is `medium+`, explicitly confirm.

**Never** write the plan to a `.md` file. Plans live in chat.

### Stage 5 — Execute

Write the code. Rules:
- Atomic commits per logical chunk (don't pile 10 changes into 1 commit)
- One complete idea per file — ~300 lines is the tripwire to ask "still one idea?", not a hard gate
- Read before you edit (every time — no exceptions)
- For specialist work, delegate to the right skill from `.platform/repos.md` routing table
- If you hit an obstacle, do not brute-force retry. Surface the obstacle to the user and ask.

### Stage 6 — Verify + Learn

Parallelize verification. Fire in one round:
- **Check A:** run tests (use the test runner from `conventions/testing.md`)
- **Check B (if security-sensitive):** delegate to `ab-security`
- **Check C (if UI-visible):** delegate to `ab-qa` for a real-browser pass
- **Check D (always):** re-read the diff once for obvious bugs

If any check fails, loop back to Stage 5.

Once all checks pass, append **one line** to `.platform/memory/log.md`:
```
YYYY-MM-DD — <task> — <outcome> — <takeaway>
```

One sentence of takeaway. Not a paragraph. Not a retrospective.

## Hard rules (non-negotiable)

1. **No `.md` artifacts for plans.** Ever. Plans live in chat.
2. **Read before you edit.** No exceptions.
3. **Parallelize subagents.** Never run independent subagents sequentially.
4. **Trivial tasks skip Stages 2–4.**
5. **Every success logs one line** to `.platform/memory/log.md`.
6. **High-risk tasks require explicit user approval** between Stage 4 and Stage 5.
7. **One complete idea per file.** ~300 lines = the question "is this still one idea?", answered in the PR.

## Output format

Progress markers in chat at each stage transition:
```
[Stage 1] Triage: feature / medium / low
[Stage 3] Research: <300-word synthesis>
[Stage 4] Plan:
  1. …
  2. …
[Stage 5] Executing…
[Stage 6] Verified. Logged.
```

One line per marker. No prose fluff between them.

## Red flags — stop and ask

- **User intent unclear after interview** — ask once more or admit you need a scoping meeting
- **Research reveals the task is actually `xl`** — stop, propose splitting into phases
- **High-risk task with no tests in the area** — stop, propose writing tests first as a separate chunk
- **You can't find any relevant code paths** — confirm with user that the feature area exists

## Integration

- **Upstream:** called by the main agent when a task is classified `small+` by `ab-triage`
- **Calls (Stage 3):** `Grep`, `Read`, `WebSearch`, `WebFetch`, `ab-research` (optional wrapper)
- **Calls (Stage 5):** `ab-architect` for design, `ab-test-writer` for tests, domain specialists
- **Calls (Stage 6):** `ab-security`, `ab-qa`, `ab-review`
- **Downstream:** writes to `.platform/memory/log.md`, optionally `.platform/STATUS.md`

## Anti-patterns

1. **Skipping Stage 1.** You always triage. Even if the result is "trivial, skip the rest".
2. **Doing Stage 3 sequentially.** Fire all probes in one round.
3. **Writing the plan to `PLAN.md`.** No. Chat only.
4. **Running tests AFTER committing.** Tests pass before the commit, not after.
5. **Logging more than one line per task.** One line. Rolling history.
