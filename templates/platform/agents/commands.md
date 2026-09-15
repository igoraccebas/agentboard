# Agentboard Command Guide (LLM Protocols)

This guide defines the **Exact Phrases** you can use to trigger high-reliability workflows. When these phrases are used, the AI MUST follow the linked protocol without hallucination or deviation.

## 1. Stream Management

| Phrase | Action | Protocol Source |
|---|---|---|
| `audit stream` | Run a full QA/Security/Style audit of the current task. | `workflow.md#stage-6-verify` |
| `archive stream` | Finalize, log, and move the stream to archive. | `workflow.md#closure-checklist` |
| `start stream "<name>"`| Triage a new request and create a work stream file. | `workflow.md#stage-1-triage` |
| `plan stream` | Create a design doc with invariants and data flow. | `workflow.md#stage-4-propose` |
| `research stream` | Perform bounded research (1 search + 3 reads max). | `ab-research` |
| `debug stream` | Use the scientific method to find a root cause. | `ab-debug` |
| `sync context` | Ensure AGENTS.md and GEMINI.md are updated. | `.platform/scripts/sync-context.sh` |

---

## 2. Command Protocols (LLM Hard-Rules)

### `plan stream`
When I say **"plan stream"**, you MUST:
1. **Activate** the `ab-architect` skill.
2. **Read** the current stream brief in `work/BRIEF.md`.
3. **Produce** a design in the stream file (`work/<slug>.md`) that includes:
   - **Invariants:** What must never change?
   - **Data Flow:** How does information move?
   - **Failure Modes:** What happens when things break?
4. **Style:** No code implementation yet. Only design and architectural logic.

### `research stream`
When I say **"research stream"**, you MUST:
1. **Activate** the `ab-research` skill.
2. **Limit** output to a ≤300-word synthesis in the chat.
3. **Draft** any findings directly into the "Research" section of the current stream file.

### `debug stream`
When I say **"debug stream"**, you MUST:
1. **Activate** the `ab-debug` skill.
2. **State** a clear hypothesis before running any tests.
3. **Narrow** the cause through empirical testing (max 3 hypotheses).
4. **Log** the results of each test in the current stream file.

### `audit stream`
When I say **"audit stream"**, you MUST:
1. **Read** the current active stream file in `.platform/work/`.
2. **Execute** the checklist in `workflow.md` (Stage 6: Verify).
3. **Output** a structured report with these sections:
   - **Verification Results:** (Pass/Fail per criteria)
   - **Architectural Integrity:** (Check against `architecture.md`)
   - **Security/Style Check:** (Check against `conventions/`)
4. **Style:** Do NOT provide inline chat analysis. Provide a rendered markdown report. **Do NOT** make any code changes during an audit.

### `archive stream`
When I say **"archive stream"**, you MUST:
1. **Verify** that the owner has run `agentboard close <slug> --approve` (the CLI records it in the stream file). If not, stop and ask the owner — never record it yourself.
2. **Update** `.platform/STATUS.md` and any relevant deep-reference files.
3. **Run** `agentboard close <slug> --confirm` — the only archival path. It moves the file, removes the `ACTIVE.md` row, and logs the outcome in `.platform/memory/log.md`. Never move the file by hand.

### `status check`
When I say **"status check"**, you MUST:
1. **Render** a summary of `.platform/STATUS.md`.
2. **List** all active streams from `ACTIVE.md`.
3. **Identify** any blocking tasks or stale sessions.

---

## 3. Reliability Clause
As an AI Agent, when you encounter one of the phrases above, you are **forbidden** from:
- Inventing your own sequence of steps.
- Summarizing without checking the source protocol files.
- Modifying files unless the protocol explicitly requires it.
- Apologizing or explaining your process — just **execute** the protocol.
