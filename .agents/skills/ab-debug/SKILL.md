---
name: ab-debug
description: "Root-cause bug investigation using the scientific method. Forms a hypothesis, tests it, narrows the search, and fixes the underlying cause — not the symptom. Logs each hypothesis + result so you can't loop on the same wrong theory."
argument-hint: "<bug description — what's broken, what's expected, how to repro>"
allowed-tools:
  - Read
  - Edit
  - Bash
  - Grep
  - Glob
  - WebSearch
  - WebFetch
---

# ab-debug — Root-cause debugger

## Purpose

Stop guessing. Stop tweaking random things hoping the bug goes away. This skill uses a structured hypothesis-test-narrow loop with a hard cap on attempts before re-assessing.

The failure mode this prevents: "I tried 10 things, one of them worked, I don't know which, and the bug is back in a week."

## When to use

- You have a bug that's not immediately obvious
- A first-guess fix didn't work
- The bug is intermittent / flaky / race-condition-shaped
- The bug crosses component boundaries
- `ab-qa` produced a finding and the cause isn't clear

## When NOT to use

- Obvious bugs with obvious fixes (just fix them)
- Tasks that aren't bugs (new features, refactors)
- "It works but slowly" performance issues (different skill — profile, don't debug)

## Protocol

### Step 1 — Lock in the facts

Before any code reading, write in chat:

```
## Bug: <short title>

Observed: <what is happening, concretely>
Expected: <what should be happening>
Repro steps:
  1. <step>
  2. <step>
  3. <step>
Frequency: <every time / intermittent / once>
Environment: <where was this observed>
First seen: <when did this start, if known>
Recent changes: <what changed in the area lately, from git log>
```

Mark unknown fields explicitly. Ask for missing information when it blocks investigation; otherwise gather evidence to establish a repro before fixing.

### Step 2 — Reproduce locally

Run the repro steps in the dev environment. **Do not skip this step.**

If you can't reproduce locally, record the attempted steps and mark the cause unconfirmed. Investigate incomplete repro steps, intermittent behavior, and differences between environments (config, data, versions, feature flags) as hypotheses. Failure to reproduce alone does not establish an environmental cause.

If you CAN reproduce, note the exact command / URL / input that triggers it. This is your test oracle for the rest of the debug session.

A mock, stub, fake binary, or fixture you write yourself is **not** a reproduction. CONFIRMED means the reported failure happened through the given repro path against the real dependency. If a dependency (a binary, a host, credentials, data) is unavailable here, the repro status is NOT RUN — say so and continue with the cause marked unconfirmed. Never install or shadow a binary outside the project to make a repro pass.

### Step 3 — Form the first hypothesis

Based on the facts, write one hypothesis in chat:

```
Hypothesis 1: <specific, testable theory about what's causing the bug>
Why I believe it: <the signal that made you think this>
How to test it: <a specific experiment that will confirm or deny it>
```

**Specific** matters. "Something in the auth code" is not a hypothesis. "The JWT expiry check compares seconds vs milliseconds" is a hypothesis.

The user's certainty about the cause ("I'm sure it's the timezone") is a hypothesis to test like any other, not evidence. Test it against the real failure, not against a simulation of it.

### Step 4 — Run the experiment

Run exactly the experiment from Step 3. Do not run five experiments at once — you won't know which one mattered.

Record the result:
```
Result 1: CONFIRMED / DENIED / INCONCLUSIVE
Evidence: <what you observed that proves or disproves>
```

### Step 5 — Narrow or pivot

- **If CONFIRMED:** proceed to Step 6 and demonstrate a failing regression test before the Step 7 fix.
- **If DENIED:** form a new hypothesis based on what you learned. The new hypothesis should narrow the search, not restart it.
- **If INCONCLUSIVE:** record what the experiment could not establish. Check for missing observations, intermittent behavior, or experiment limitations, then refine the experiment or gather more evidence. Keep the hypothesis unconfirmed.

Repeat Steps 3–5. **Maximum 3 hypotheses before re-assessing.** If you've burned 3 hypotheses and still don't know:
- Stop
- Re-read the facts
- Ask: am I debugging the wrong thing?
- Ask: is there a different interpretation of the symptom?
- Consider: is the repro actually what the user reported, or something similar-looking?

If re-assessment doesn't help, escalate to the user or pair with a different angle (fresh read of the relevant files, grep for recent similar bugs in `.platform/memory/log.md`).

### Step 6 — Write the regression test

Before fixing, write a test that reproduces the bug and fails. This is non-negotiable. If the test passes before the fix, it's not testing the bug.

Use `ab-test-writer` if the test framework / style isn't obvious.

### Step 7 — Fix the root cause

Fix the cause you confirmed, not the symptom. Examples:
- **Symptom fix (bad):** wrap the null access in a try/except
- **Root fix (good):** find out why the value is null and fix that

If the root cause is too deep to fix now, the symptom fix is acceptable **only** if:
1. You document the root cause in `.platform/memory/decisions.md` as deferred
2. You add a TODO at the site with a reference to the decision
3. You add a test for the symptom

### Step 8 — Verify

Run the regression test — it should now pass.
Run the surrounding test suite — nothing else should break.
Re-run the original repro steps — the bug should be gone.

Report each check as passed, failed, or not run, with evidence or the reason it could not run. If the original repro cannot be exercised, mark that verification unavailable; do not claim the bug is verified fixed.

When the original repro could not run: the Verification block says `original repro: not run`, the Fix section says `unverified`, and the log line says `fix unverified`. Do not write PASS, ✅, "verified", or "confirmed" about anything you could not execute against the real path. Passing your own mock proves the mock, not the fix.

### Step 9 — Log the debug session

Append to `.platform/memory/log.md`:
```
YYYY-MM-DD — debug: <bug title> — <verified fix / mitigated / unresolved / fix unverified>: <evidence or limitation> — <takeaway / next step>
```

If the takeaway is important enough that future sessions should know, add a row to `.platform/memory/decisions.md` or `.platform/conventions/*.md` with the prevention rule.

## Output format

End your final message with this block. A summary may come before it, never instead of it. If any Verification line says `not run`, the last sentence of your message is `Fix unverified: <what could not run>.` Never write verified, ✅, or PASS about a check that only ran against a mock you wrote.

```
## Debug: <bug title>

### Facts
Observed: ...
Expected: ...
Repro: ...
Environment: ...

### Repro status: <CONFIRMED locally — the given repro command failed as reported and nothing you created is in its path / NOT REPRODUCED — it ran here and did not fail / NOT RUN — name the real dependency that is missing here>

### Hypotheses tried
1. <hypothesis 1> — DENIED (evidence)
2. <hypothesis 2> — CONFIRMED (evidence)

### Root cause
<evidence-backed cause, or UNCONFIRMED with remaining hypotheses>

### Fix
- <file:line change>
- regression test: <file>
- status: <verified against the real repro / UNVERIFIED — real repro not run>
<or: no fix — unresolved>

### Verification
- regression test: <passed / failed / not run — evidence or reason>
- surrounding tests: <passed / failed / not run — evidence or reason>
- original repro: <fixed / still reproduces / not run — evidence or reason>

### Logged to .platform/memory/log.md: ✓
```

## Red flags — stop and ask

- **You can't reproduce locally.** Keep the cause unconfirmed and investigate the repro and available evidence; ask for missing access or details if they block progress.
- **You've burned 3 hypotheses and are about to guess a 4th.** Stop. Re-read. Reconsider the problem.
- **The fix works but you can't explain why.** Do not ship. The bug will come back.
- **The fix involves `try/except Exception: pass`.** Almost always wrong.
- **You're fixing a symptom because the root cause is "too deep".** Document the deferral explicitly or keep digging.
- **The repro depends on a race condition and passes locally sometimes.** Use a deterministic trigger (fake time, fake randomness, explicit ordering).

## Hard rules

1. **Repro before fix.** No real repro → no verified fix: label the fix unverified or stop and ask. A mock you wrote is not a repro.
2. **One hypothesis, one experiment, one result.** No shotgun debugging.
3. **Max 3 hypotheses before re-assessing.** Then ask a fresh question.
4. **Regression test before fix.** Non-negotiable.
5. **Root cause over symptom.** Symptom fixes are logged as deferred root causes.
6. **Log the session.** Future sessions should not re-debug the same thing.
7. **A mock proves the mock.** Checks that ran only against fixtures, stubs, or binaries you created are reported as such — never as verification of the fix, never as CONFIRMED.

## Integration

- **Upstream:** called by `ab-qa` when a finding needs root-cause work, by `ab-workflow` when Stage 5 hits a bug, or directly
- **Calls:** `ab-test-writer` for the regression test
- **Downstream:** writes to `.platform/memory/log.md`, optionally `.platform/memory/decisions.md` / `conventions/*.md`

## Anti-patterns

1. **Shotgun debugging.** Changing five things at once. Find the causal chain, don't scatter buckshot.
2. **Blaming the framework first.** It's almost always your code. Eliminate your code as a suspect first.
3. **Skipping the repro.** "I know what it is" — maybe, but prove it.
4. **Silencing the error.** `try/except: pass`, logger level changes, `// @ts-ignore` — these are not fixes.
5. **Not logging the debug session.** The next session will hit the same bug and re-derive the same fix.
6. **Confirmation bias.** Designing experiments that can only confirm, never deny. Every hypothesis needs a way to be wrong.
