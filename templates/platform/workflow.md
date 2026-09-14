# Workflow — The 6-Stage Inline Workflow

> **Audience:** any AI agent (Claude Code, Codex CLI, Gemini CLI) or human working on this project.
> **Goal:** move fast on small tasks, think carefully on big ones, and never bureaucratize small work.

---

## The 6 stages

```
Triage → Interview → Research → Propose → Execute → Verify + Learn
```

Each stage has a clear entry condition and a clear exit condition. Skip stages that don't apply.

### 1. Triage

For every non-trivial task, state inline in chat:

- **Type:** bug / feature / refactor / chore / investigation / docs
- **Scope:** trivial / small / medium / large
- **Risk:** low / medium / high (blast radius + reversibility)

**Exit:** you know how big this is and how careful to be.

Trivial tasks (typo fix, rename, 1-line config change) skip directly to Stage 5.

### 1b. Register (mandatory for non-trivial tasks)

**Before doing anything else** — research, proposals, code — register the workstream:

1. **Check `work/ACTIVE.md`** — does this stream already exist? If yes, load the stream file and continue from where it left off. Do not create a duplicate.
2. **Check `.platform/domains/`** — does a domain file exist for **this specific concern**?
   - Ask: "Does an existing domain file fully describe the cross-repo touch-points for THIS concern (which files in which repos, what the API contract is, what breaks if this changes)?" A related-but-different domain file does NOT count.
   - If **yes and it's accurate**: read it, verify it's current, update if stale.
   - If **no, or the existing file only partially covers it**: create `.platform/domains/<name>.md` with the cross-layer touch-point inventory. Create it NOW, before the stream file.
   - **Common trap:** finding a domain file for a nearby feature (e.g. `menu-builder.md`) and treating it as sufficient for a different concern (e.g. subdomain routing). These are separate concerns and require separate domain files.
3. **Create `work/<stream-slug>.md`** from `work/TEMPLATE.md` — fill in the frontmatter metadata (`stream_id`, `slug`, `type`, `status`, `agent_owner`, `domain_slugs`, `repo_ids`, `created_at`, `updated_at`) before writing scope, done criteria, and next action. Keep `stream_id` canonical: `stream-<slug>`.
4. **Add a row to `work/ACTIVE.md`** — slug / type / in-progress / agent / date.
5. **Update `work/BRIEF.md`** — set primary stream to this task; add domain file under "Relevant context".

**Why this is non-negotiable:** if the context is cleared, the computer restarts, or a different agent picks up the work, the stream file is the only way to resume. Zero registration = zero traceability = zero resumability. A workstream without a domain file has no focused context for the next agent.

Full protocol: `agents/work-tracking.md` § "Starting a new workstream".

**Exit:** domain file exists, stream file exists, `ACTIVE.md` has the row, `BRIEF.md` is current.

### 2. Interview

**Only if requirements are ambiguous.** Ask 2–5 targeted questions. Do not ask "is my plan ready?" — use the plan-approval tool for that.

**Exit:** requirements are unambiguous.

### 3. Research

**Only for medium+ scope.** Default route: delegate to the configured researcher —
run `agentboard research <slug> "<question>"` (add `--web` for web research).
The command inherits the configured Codex model and does not automatically
select a cheaper one. It invokes the local Codex CLI
read-only, streams its activity live, and
anchors findings in the stream's `## Research notes`, where ab-planner and
the executor read them. The session invokes this — the human never has to
remember the command.

Escape hatch: targeted inline reads of a few already-known files don't need
it. If Codex is unavailable, fall back to parallel subagents:
- Subagent A: read existing code paths that touch the area
- Subagent B: web search / docs fetch (strict budget: 1 search + 2–3 fetches)
- Subagent C: check conventions/ and decisions.md for prior art

Synthesize in chat (≤300 words). **Do not** write a research `.md` file —
durable findings belong in the stream's `## Research notes`.

**Exit:** you understand the area well enough to propose.

### 4. Propose

State a 5–10 bullet plan **inline in chat**. Include:
- Files to touch
- New files / deleted files
- Test plan
- Risk factors
- Rollback path (for risky changes)

**Do not** write a plan `.md` file. If the user approves, proceed. If they push back, iterate.

**Exit:** the work is covered by the user's existing authorization, or the user has approved a needed scope or risk change. Silence is not approval.

### 5. Execute

Write the code. One complete idea per file: ~300 lines is the tripwire, not the limit — crossing it asks "is this still one idea, or did a second idea move in?" Split when the answer is two ideas; never split a cohesive idea just to satisfy a number. For specialist work, delegate to the appropriate skill from `repos.md`.

> **⛔ Do NOT commit during Stage 5.** Code is written but never committed until Stage 6 passes and the user explicitly approves.

**When dispatching implementation sub-agents:** never include `git add` or `git commit` in the agent's task prompt. Agents write code and report back. The commit is the main agent's responsibility after Stage 6 clears and the human approves.

**After execution completes:** present a change summary inline — files modified/created, expected behavior change, what Stage 6 needs to verify.

**Backlog rule:** When you encounter a real limitation, tech debt item, or missing feature that is out of scope — do NOT fix it, do NOT open a new work stream. Append one row to `.platform/memory/BACKLOG.md` (priority / area / description / found-during / date) and continue.

**Exit:** code is written, NOT yet committed, ready for Stage 6 verification.

### 6. Verify + Gate + Learn

#### The commit gate — required before ANY `git commit`

All three must be true before committing:

| Gate | Requirement |
|---|---|
| ✅ Tests pass | Unit tests for every new/modified function and component |
| ✅ Security clear | Quick pass on anything touching auth, payments, or data access |
| ✅ Human approves | User explicitly says "ship it" / "commit it" — the AI never self-approves |

Present Stage 6 results to the user **before committing**. Honor explicit commit authorization already given for the same scope; otherwise wait for the owner's approval.

#### Testing philosophy — when and how to write tests

Not dogmatic TDD. Optimize for: **clear contracts, regression safety, fast feedback, maintainable tests, testing behavior that matters.**

**By task type:**

| Task type | Approach |
|---|---|
| 🐛 **Bug fix** | Failing test first — always. Reproduce → write failing test → fix → run suite. Proves the fix and prevents regression. |
| 🧠 **Pure business logic** | Test-first is excellent. Contract is clear, no churn. |
| ✨ **New feature (clear contract)** | Write the behavior/API test first, then implement. |
| ✨ **New feature (design moving)** | Sketch implementation first. Add tests immediately once shape stabilizes. |
| 🖼️ **UI / components** | Finish implementation first (markup/props settle), then add tests right after. |
| ♻️ **Refactor** | Lock existing behavior with characterization tests before changing internals. |
| ⚠️ **High-risk code** | Test earlier and more thoroughly. |

**The strong workflow (for new features):**
1. Define the behavior/contract.
2. Add one test for the main case.
3. Implement.
4. Add boundary / error / empty-state tests.
5. Run the nearest relevant suite.

**What NOT to do:**
- Write tests after the fact just to satisfy a coverage metric
- Test implementation details instead of behavior
- Add huge brittle tests before you understand the design
- Skip the failing regression test for a bug fix

Then verify in parallel:
- Specialist A: run tests
- Specialist B: security / code review pass (for anything security-sensitive)
- Specialist C: real-browser QA (for UI changes)

Then record the outcome and any durable lessons:

- Append one concise outcome to `.platform/memory/log.md`.
- Record non-obvious root causes, gotchas, and reusable practices with
  `agentboard fact new`; use the relevant domain and stream. Keep one fact per
  lesson instead of creating parallel memory files.
- Record architectural or product decisions in `.platform/memory/decisions.md`.

Before investigating a non-obvious bug, search `.platform/memory/facts/` for
related lessons. On older projects, also check `.platform/memory/learnings.md` before migration
or `.platform/memory/legacy/learnings.md` after migration, when present. Do not load the full memory pack.

**Exit:** task is done, recorded, and learned from.

---

## Stream Closure Protocol

> **Hard rule: only the human/owner declares a stream complete.**
> The AI never self-declares completion. The AI may say "I believe this stream is done — here is the evidence" and propose closure, but the final decision belongs to the developer. No exceptions.
>
> **⛔ Do NOT run steps 7–9 (archive, ACTIVE.md removal, log) until the human explicitly approves closure.** Implementation being done ≠ stream being closed. The stream file stays in `work/` and the row stays in `ACTIVE.md` until the owner says so. Steps 1–6 (verify criteria, update docs) can run after implementation. Steps 7–9 require explicit human sign-off.

Run this checklist **every time a stream reaches done** — before archiving the stream file.

> **Why:** skipping this leaves stale docs for the next session/agent. Completed features must be fully reflected in all reference files before the stream is archived.

1. **Verify done criteria** — open the stream file (`work/<slug>.md`), confirm every checkbox is ticked.
2. **Update STATUS files** — for every repo the stream touched, mark features ✓ Done, update Last touched date, remove from Immediate priorities.
3. **Update domain file** — open `.platform/domains/<name>.md` if one exists. Update file paths, API shapes, cross-repo touch-points that changed.
4. **Deep-reference file check** — for every repo the stream touched, make an explicit YES/NO decision on whether the per-repo reference file (e.g. `backend.md`, `admin.md`) is now stale. Ask: *"Would a new developer or agent reading this file today take a wrong path?"* Update if YES. Skip if NO. This catches: new URL routes, removed fields, stack changes, patterns that no longer apply. State the decision in chat either way.
5. **Update architecture.md** — if the stream changed system topology (new endpoints, new data flows, auth changes), update the relevant section.
6. **Unblock downstream streams** — flip any `pending (blocked on this)` stream in `ACTIVE.md` to `ready-to-plan`.
7. **Archive the stream file** — first check: does the stream file have `closure_approved: true`? If not, **STOP**. Do not archive. Ask the owner to set it. Only when `closure_approved: true` is present: move `work/<slug>.md` → `work/archive/<slug>.md`, remove from `ACTIVE.md`, reset `BRIEF.md`. **Remove the closed stream from `BRIEF.md` entirely — do NOT add a "Previously completed" section.** Completed work belongs in `log.md` only. `BRIEF.md` must only ever list active streams.
8. **Log token usage** — run `agentboard usage log` to record the total token investment for this stream (aggregate from session reports).
9. **Append to log.md** — one line: `YYYY-MM-DD — <stream> — <outcome> — <takeaway>`.
10. **Learnings check** — any non-obvious bugs surfaced? Confirm each has a learning fact (`agentboard fact list --type learning`). Add if missing.

**Hard rule:** steps 2–5 are not optional. If a stream touched 3 repos, all 3 STATUS files get updated and all 3 deep-reference files get an explicit YES/NO decision. The next agent should be able to open any reference file and see a correct picture of the world.

---

## Stream / Feature Analysis Protocol

> **Trigger:** When asked for a feature audit, stream analysis, "what's the state of X", "audit end to end", "check the state of", or "full analysis of \<feature/stream\>".

> ⛔ **MANDATORY — NO EXCEPTIONS:** Before doing anything else when this protocol is triggered — including collecting already-running agent results — read this section in full. A compressed context summary from a resumed session is NOT a substitute for reading this spec. The protocol steps below must be followed in order every time. Skipping any step (especially Step 3 "wait for all agents", Step 4 "exact template", Step 5 "anchor in stream file") is a protocol violation regardless of how much context you already have.

### Step 1 — Identify scope

Determine which repos are touched. If a stream file exists at `work/<slug>.md`, read it first — it defines scope, done criteria, and key files.

- Use one independent review agent per repository when delegation is available.
- If delegation is unavailable, perform a separate review pass locally and disclose that limit.

### Step 2 — Announce and dispatch in parallel

```
Dispatching N agent(s): <name1> [configured model] — <purpose>; ...
```

Analysis is read-only. Use an available review role and respect the configured
model; choose review depth according to the task and risk.

Spawn one per repo (`run_in_background: true`), each covering:

| Dimension | What to check |
|---|---|
| **Implementation state** | What's built, stubbed, missing; TODO/FIXME comments |
| **Test coverage** | Which files have tests, which have zero, breadth vs. complexity |
| **Security** | Auth/permissions, hardcoded secrets, XSS, SQL injection, tenant isolation |
| **Code quality** | File cohesion (review at ~300 lines), business logic in views, N+1 queries, duplication |
| **Feature-specific** | *(if scoped)* Exact implementation per layer — done, missing, untested |

### Step 3 — Wait for all agents, then synthesize

Do not partially report. Wait for every agent before outputting anything.

### Step 4 — Output in standardized format

Always use this exact template:

---

```
# 📋 <Feature / Stream / Platform> — Audit Snapshot

> **Stream:** `<slug>` · **Date:** YYYY-MM-DD · **Status:** <emoji + status>
> **Repos touched:** <list>

---

## ⚡ At-a-Glance Scorecard

| | 🖥️ <Repo A> | 🎛️ <Repo B> | 📱 <Repo C> |
|---|:---:|:---:|:---:|
| **Implementation** | 🟢/🟡/🔴 | ... | ... |
| **Tests**          | 🟢/🟡/🔴 | ... | ... |
| **Security**       | 🟢/🟡/🔴 | ... | ... |
| **Code Quality**   | 🟢/🟡/🔴 | ... | ... |

> **Bottom line:** <one sentence — what is the overall state?>

---

## 🔄 How the Feature Works (End-to-End)

<ASCII flow diagram — only when it clarifies cross-layer architecture>

---

## 🛡️ Security

| Severity | Repo | Finding |
|:---:|---|---|
| 🔴 Critical / 🟡 Medium / 🟢 Clean | | |

---

## 🧪 Test Coverage

### <Repo Name>
| Area | Tested? | File |
|---|:---:|---|
| <area> | ✅ Strong / 🟡 Thin / 🔴 None | path/to/test |

---

## ✅ Implementation Status

### <Repo Name>
| Component | Status | Location |
|---|:---:|---|
| <name> | ✅ Done / ❌ Missing / ⚪ Deferred | file:line |

---

## 🔧 Open Issues

### 🔴 Must Fix (blocking)
| # | Repo | Issue |
|---|---|---|

### 🟡 Should Fix Soon
| # | Repo | Issue | Location |
|---|---|---|---|

### ⚪ Known Limitations (document, not block)
| # | Limitation |
|---|---|

---

## 🎯 Close Checklist / Priority Order

  □  1. 🧪  <test task>
  □  2. 🐛  <correctness fix>
  □  3. 🔍  <QA / verification step>
  □  4. ⚡  <performance fix>
  □  5. ✅  <closure step>
```

---

**Output rules:**
- Scorecard always first — tells the story before any detail
- Flow diagram only when it clarifies cross-layer connections
- Every security finding: 🔴 Critical / 🟡 Medium / 🟢 Clean
- Every test area: ✅ Strong / ✅ Good / 🟡 Thin / 🔴 None
- Healthy areas always listed — not just problems
- `file:line` for every actionable finding
- Tables and bullets only — no prose paragraphs

### Step 5 — Anchor the report in the stream file

> ⛔ **MANDATORY — do this before moving to Step 6 or responding about next steps.** The report is not complete until it is written into the stream file. Outputting it in chat only is a protocol violation.

Immediately after outputting the report, write it into the stream file (`work/<slug>.md`):

- **First audit on this stream:** append a new `## 🔍 Audit — YYYY-MM-DD` section at the bottom of the stream file.
- **Re-audit (audit section already exists):** replace the existing audit section entirely with the new report. Do not accumulate multiple audit sections — only the latest report stays. Add a `> Supersedes previous audit.` note at the top of the section.

```markdown
---

## 🔍 Audit — YYYY-MM-DD

> Supersedes previous audit. Run via Stream / Feature Analysis Protocol — N parallel agents.

<paste the full standardized report here>
```

This makes the report a living checklist inside the stream — every fix can be tracked against it, and any agent picking up the work in a new session has the findings immediately without re-running the analysis.

### Step 6 — Fix → Re-audit loop

Repeat until the scorecard is all 🟢:

```
┌─────────────────────────────────────────────┐
│  1. Work through 🔴 Must Fix items first     │
│  2. For each fix: implement → test → verify  │
│  3. Once all 🔴 resolved, re-run analysis    │
│     (Steps 1–4, same scope, fresh agents)    │
│  4. Compare new report to previous:          │
│     • All flagged items resolved?            │
│     • Any new issues introduced?             │
│                                              │
│  If clean → remove audit section from        │
│             stream file, proceed to closure  │
│  If not clean → return to Step 1             │
└─────────────────────────────────────────────┘
```

**Rules for the loop:**
- Never self-declare clean. Always re-run the analysis — don't assume fixes worked.
- Re-audit scope = same repos as the original audit. Don't narrow it.
- New issues found in re-audit get added to the stream file's audit section (append, don't replace).
- The audit section is removed from the stream file **only** when the re-audit returns all 🟢 with no 🔴 items remaining.

---

## Hard rules

1. **No `.md` artifacts for plans.** Plans live in chat. Only write `.md` files when they're genuinely reusable (specs, docs, conventions). **`work/` stream files are the exception — they are mandatory operational state, not plan documents. Always create them (Stage 1b) before starting non-trivial work.**
2. **One complete idea per file (code).** ~300 lines is the tripwire that forces the question "is this still one idea?" — answer it in the PR instead of ignoring it. For context files the rule is different: **optimize the load path, not the file** — always-loaded surfaces (brief, INDEX.md, entry files) stay ruthlessly lean because they cost tokens every session; depth lives in on-demand files.
3. **Trivial tasks skip to Stage 5.** Don't bureaucratize small work.
4. **Parallelize subagents.** Never run independent subagents sequentially.
5. **Every success logs one line.** `.platform/memory/log.md` is append-only, newest-on-top.
6. **Read before you edit.** Always read the file before modifying it, even if you "know" the content.
7. **Ask before destructive actions.** Deletes, force-pushes, rollbacks, schema drops — always confirm.
8. **Never commit before Stage 6 + human approval.** Execute produces code. Stage 6 + the human produces the commit. No exceptions — not even for "trivial" changes.
9. **Never include `git commit` in sub-agent prompts.** Agents write code and stop. If an agent is told to commit, it bypasses tests and human approval — exactly the failure mode this rule prevents.

---

## Model guidance (optional)

Use the user's selected model by default. No model-routing announcement is required.
For a new session or a useful delegated task, choose among the models actually
available to that provider:

| Task | Starting point |
|---|---|
| Mechanical, well-bounded work | Lightweight model, if switching overhead is worthwhile |
| Everyday features, fixes, and tests | Balanced coding model |
| Difficult debugging, architecture, or high-risk review | Strong reasoning model |
| Hardest sustained work across multiple systems | Most capable available model |

Discuss a switch only when it would materially help. Respect explicit model and
budget choices; this guidance does not switch sessions or authorize a different
provider. Reassess evidence and context before attributing failure to the model.
Log the actual model and usage only when known.

## The plan→approve→execute gate (optional, per stream)

For medium+ scope work, split planning from execution across models with a
human gate between them:

1. **Plan** — the `ab-planner` agent (pinned to the planning model) researches
   the codebase and writes an `## Execution brief` into the stream file:
   objective, Do / Do NOT lines, files in scope, acceptance criteria. It sets
   `brief_approved: false` and never writes code.
2. **Approve** — a human reviews the brief and runs
   `agentboard approve <slug>`. In Claude Code the bash-guard turns this into
   a native approval prompt for recognized commands. The metadata remains editable;
   this is a workflow guardrail, not independent authentication of the human.
3. **Execute** — the execution model implements strictly within the brief.
   `agentboard handoff` shows the gate status (⛔ awaiting / ✓ approved); an
   unapproved brief means: do not write code, ask the user.

Streams without an Execution brief are not gated — trivial work flows
untouched. Re-plan? `agentboard approve <slug> --revoke`, edit, re-approve.

---

## Integration with agent CLIs

- **Claude Code:** `CLAUDE.md` at project root auto-loads. Skills in `.claude/skills/` extend this workflow.
- **Codex CLI:** `AGENTS.md` at project root auto-loads. Its managed block is synchronized by `scripts/sync-context.sh`; provider-specific text is preserved.
- **Gemini CLI:** `GEMINI.md` follows the same managed-block contract.

All three read the same `.platform/` reference pack.
