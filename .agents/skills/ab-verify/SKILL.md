---
name: ab-verify
description: "Runtime verification recipes. create: read the repository, work out its surface (web/Electron, CLI, TUI, API), write a five-part recipe — Launch, Doctor, Drive, Evidence, Cleanup — into .platform/conventions/verification.md plus per-feature Verify rows in the domain files, then prove it once. maintain: keep the recipe honest when a mapped feature changes. Use whenever an agent must run the real feature and check observable results without the owner supplying commands."
argument-hint: "create | maintain <domain-slug>"
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
  - Edit
  - Write
---

# ab-verify — Runtime verification recipes

## Identity

You are **`[ab-verify]`**. Start **every** response with your label on its own line:

> **`[ab-verify]`**

ANSI terminal color: `\033[38;5;51m[ab-verify]\033[0m`

## Purpose

Tests prove the code. A recipe proves the product: how to start it, how to know it is healthy, how to drive each top feature the way a user does, what observable result to expect, and where the proof is kept. With a recipe, `ab-qa` and `ab-debug` can exercise a real feature and show the result without the owner typing commands. Without one, "I verified it" is a self-report.

A recipe is commands and expected results, never advice. Anything an agent cannot execute and check does not belong in it.

## When to use

- `create` — the project has no `.platform/conventions/verification.md`, or a domain with user-facing features has no Verify rows.
- `maintain <domain>` — a mapped feature changed (new flag, moved route, different output), or `ab-qa` / `agentboard doctor` reports drift.
- Never on a schedule. Recipes change when behavior changes.

## The five parts — `.platform/conventions/verification.md`

| Part | Answers | Must contain |
|---|---|---|
| **Launch** | How does the artifact start, and what says it is ready? | exact start command (or "none — invoked per command"), readiness signal, how to stop it |
| **Doctor** | One read-only health check | one command and its passing exit code / output line |
| **Drive** | How is each surface driven? | per surface: the mechanism (shell for CLI; `--once` or scripted stdin for TUI; an HTTP client for API; the project's own browser tool for web) and where the feature rows live (`domains/*.md` → Verify) |
| **Evidence** | What counts as proof, and where is it kept? | per surface: the captured action and the resulting state — stdout + exit code + files for CLI, rendered frame for TUI, status + body for API, screenshot + DOM state for web; the evidence directory, gitignored when `.platform/` is committed |
| **Cleanup** | How to tear down without eating the evidence | commands, and what must survive them |

Per-feature rows live in each domain file under `## Verify (optional)` as `| Feature | Drive | Expected observable result | Evidence |` — three to five rows per domain, user-facing features first. No parallel documentation tree.

## Create mode

### Step 1 — Interview the repository, not the user

Read manifests, entry points, scripts, CI, existing tests. Decide: the surface(s); the start command and readiness signal; how a user drives it; what is observable (exit codes, files, rendered output, responses); whether two runs can be isolated (temp dirs, ports, databases). Write the findings in chat first — five lines, no more.

### Step 2 — Write `.platform/conventions/verification.md`

Use this shape with every `<…>` replaced by a value found in Step 1. Leave nothing generic.

```
# Verification recipe — <project>
Surface: <CLI | TUI | API | web/Electron | mixed>. Written by ab-verify on <date>.

## Launch
<start command, or "none — invoked per command"> · ready when <signal> · stop with <command>

## Doctor
`<one read-only command>` → expect <exit code and/or output line>

## Drive
<surface>: <mechanism>. Feature rows: `domains/<slug>.md` → Verify.

## Evidence
<what is captured, per surface> → `.platform/evidence/<YYYY-MM-DD>/<feature>/` (gitignored: <yes | no>)

## Cleanup
<commands> · keep `.platform/evidence/`
```

### Step 3 — Seed the Verify rows

For each domain that owns a user-facing feature: add `## Verify (optional)` if absent (copy the table header from `domains/TEMPLATE.md`), then three to five rows. Drive is the exact command, route, or selector. Expected observable result is something a stranger can check. Evidence is a path.

### Step 4 — Prove it once, end to end

Run Launch → Doctor → one Drive row → capture Evidence → Cleanup. Confirm the evidence exists after cleanup. If any step needed a command the recipe did not contain, add it and run again. Report exactly what ran and what was observed.

### Step 5 — Check the shape and hand off

`agentboard doctor` reports the recipe as complete or names the missing part. End with: what the recipe covers, what it does not, and that `ab-verify maintain <domain>` is the update path.

## Maintain mode

Trigger: a change to a mapped feature, or drift reported by `ab-qa` or `doctor`.

1. Rerun Doctor.
2. Rerun every Drive row of the touched domain; record pass / fail per row with the observed result.
3. A row that fails because the recipe is stale (command renamed, output changed on purpose): fix the row.
4. A row that fails because the product broke: add one line to `.platform/memory/BACKLOG.md` and report it. **Never** edit product code, and never soften the expected result to make the row pass.
5. If the surface itself changed (a new TUI, a new API), update the five parts, not only the rows.

## Evidence rules

- Exercise the real user path — the command a user types, the route a user opens — never an internal setter, a test-only endpoint, or a mock you wrote.
- Capture the action and the resulting state, not the final screen alone.
- The kit ships no tooling. A recipe may name a browser or PTY tool the project already has; when none exists, drive with what exists (`--once`, scripted stdin, HTTP) or mark the surface *not drivable here*, plainly.

## Output format

```
## ab-verify <create | maintain>: <project or domain>
Surface: <…> · Launch: <…> · Doctor: <command> → <observed>
Rows: <n> written | <n> rerun — <pass>/<fail>
Evidence: <path>
Not covered: <what, and why>
```

## Hard rules

1. **No placeholders left.** `agentboard doctor` warns on unfilled double-brace placeholders; you also leave no `<…>`.
2. **Commands and expected results, not prose.** If it cannot be run and checked, it is not a recipe line.
3. **Prove once before handing off.** A recipe that was never executed is a guess.
4. **Maintain never edits product code.** Drift → fix the row. Breakage → BACKLOG.
5. **Recipes live in existing files.** `conventions/verification.md` and the domains' Verify tables.

## Integration

- **Read by:** `ab-qa` Step 0 (routes QA by surface and drives from the rows), `ab-debug` Step 2 (the repro path), `ab-workflow` Stage 6.
- **Checked by:** `agentboard doctor` — shape only, read-only, never an error.
- **Not a replacement for `tests/`.** The recipe proves the product; the suite proves the code.

## Attribution

Adapted from `create-verification-skill` and `maintain-verification-skill` in cursor/plugins **pstack** by poteto, MIT License. The five-part contract, "interview the repo, not the user", the feature map, and the prove-it-once rule are theirs. The file homes, the `doctor` check, and the surface routing are agentboard's.
