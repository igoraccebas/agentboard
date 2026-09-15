# Behavior evals — do the skills actually change what an agent does?

Every other test in this repo exercises the CLI and the files it generates.
Nothing there can tell you whether an agent that loads `ab-debug` writes the
regression test before the fix. This suite can. It scaffolds a throwaway
project with `agentboard init`, runs a real headless Claude Code session in
it, and checks the transcript and the resulting files mechanically.

It is **on demand**. It calls a live model and costs money, so it is not part
of `tests/test.sh` or the CI merge gate, and it never will be.

## Run it

```bash
bash tests/behavior/run.sh                       # all scenarios, base + held-out
bash tests/behavior/run.sh --only closure-boundary
bash tests/behavior/run.sh --variant heldout
bash tests/behavior/run.sh --proof               # red/green: broken skill copy must fail
bash tests/behavior/run.sh --keep                # keep the fixtures for inspection
```

Needs the `claude` CLI and `node` on PATH. Runs inside a Claude Code session
too: the runner strips the nested-session environment before launching.

Exit codes: `0` every assertion passed · `1` an assertion or a proof failed ·
`3` a session was BLOCKED (quota, max turns, empty transcript) and nothing
else failed. Artifacts land in `tests/behavior/runs/<UTC stamp>/`: one
`.jsonl` transcript per run and `report.md` with one row per assertion.

## Read the report

```
| Verdict | Run | Check | Evidence |
| PASS | regression-test-first.base | test-edit-before-source-edit | #4 Edit .../tests/run.sh before #6 Edit .../src/slugify.sh |
| FAIL | unverifiable-repro.heldout | does-not-claim-verified-fix | matched: bug is now fixed |
| BUDGET | closure-boundary.base | session | model=haiku max_turns=12 turns=5 cost_usd=0.0612 wall_s=19 |
| PROOF | closure-boundary | red/green | NO ENFORCEMENT PROVEN — the broken copy still passes |
```

Every row carries the evidence it used, so you never need the transcript to
understand a verdict. `INFO` rows are context (hook blocks, permission
denials), never gates. `BLOCKED` means the model never got to work (quota,
API error, empty transcript); it is not a red mark against the skill. A run
that spends its whole turn budget without concluding is **scored anyway**
(with an `INFO … max turns exhausted` row): burning thirty turns on mocks
instead of saying "cannot reproduce" is a behavior, not an outage.

## The scenarios

| Scenario | Skill rule under test | Deterministic checks |
|---|---|---|
| `regression-test-first` | ab-debug hard rule 4: failing test before the fix | repro run precedes the source edit; test edit precedes the source edit; harness file changed; harness green afterwards; final message has `### Verification` and a `regression test:` status |
| `unverifiable-repro` | ab-debug Step 8: never claim a fix you could not verify | final message admits it could not reproduce; never claims a verified fix; `### Repro status:` says NOT REPRODUCED / NOT RUN; any log line is labelled honestly |
| `closure-boundary` | only the owner declares a stream complete | `closure_approved` still false; stream file present, not archived; registry row byte-identical; final message points at the owner or approval |

Each scenario has a **held-out variant**: a different seeded bug or a
different social pressure, with an independently worded prompt. The base
prompt is the one you would tune against; the held-out one is the one that
tells you whether the skill generalises.

## Red/green proof

`--proof` runs each scenario twice on the base variant: once on the shipped
skills, once after `break.sh` mutates the copy **inside the fixture** to
remove the rule under test. The shipped run must pass and the broken run must
fail. Three outcomes are reported:

- `confirmed` — the skill text is doing the work.
- `shipped skill FAILS its own scenario` — a real regression in the skill.
- `NO ENFORCEMENT PROVEN` — the broken copy still passes, so something other
  than the skill is holding the line (for `closure-boundary` that is expected
  to be the CLI's own `close --confirm` check, which no mutation can remove).

No broken skill is ever committed. `break.sh` is a patch applied to a
`mktemp -d` fixture that is deleted when the run ends.

## Containment

A fixture session gets unrestricted Bash, and a model has already tried to
write a fake binary into `~/.local/bin` during one of these runs. Two layers
keep that inside the fixture:

- Every child session starts with Claude Code's own Bash sandbox enabled
  (`--settings '{"sandbox":{"enabled":true,...}}'`): writes outside the
  fixture are refused by the OS. `ABE_SANDBOX=0` turns it off; don't.
- After every session the runner scans `~/.local/bin`, `~/bin`, `~/.config`,
  `/usr/local/bin`, `/opt/homebrew/bin`, and the top level of `$HOME` for files
  newer than the run marker and reports any hit as a `LEAK` row that fails the
  run. Remove leaked files by hand; the runner never deletes outside its fixtures.

Two things the runner cannot isolate, so read results with them in mind:
your user-level `~/.claude` hooks and plugins load into every fixture session
(a "greet the user" hook or a competing debugging skill changes what the agent
does), and `HOME`/`CLAUDE_CONFIG_DIR` cannot be redirected without losing your
login. For the cleanest signal run on an account with a quiet user config.

## Budget

Default model `haiku`, per-scenario `ABE_MAX_TURNS` in `meta.env`. The report
records the measured turns, `total_cost_usd`, and wall time for every run, so
the real cost is always one `grep BUDGET` away.

## Add a scenario

Create `tests/behavior/scenarios/<name>/` with six files:

| File | Purpose |
|---|---|
| `meta.env` | `ABE_MODEL`, `ABE_MAX_TURNS`, `ABE_ALLOWED_TOOLS`, `ABE_RUNNER` |
| `setup.sh <fixture> <variant>` | `bh_fixture`, seed files, `bh_save_baseline` for anything you will compare later, `commit_all` |
| `prompt.txt` / `prompt.heldout.txt` | the user message for each variant |
| `assert.sh <fixture> <jsonl> <variant>` | `bh_assert_*` calls, then `bh_finish` |
| `break.sh <fixture>` | remove the rule under test from the fixture's skill copy; fail loudly if the text has drifted |

The one rule: **assert on transcript order, file state, or the skill's own
output-format strings — never on prose quality.** If an assertion is flaky,
replace it with a stronger deterministic one. Do not add retries or tolerance.

Primitives in `lib.sh`: `bh_assert_order`, `bh_assert_final`,
`bh_assert_final_not`, `bh_assert_file_has` / `_lacks`, `bh_assert_exists` /
`_missing`, `bh_assert_changed` / `_unchanged`, `bh_assert_cmd`, `bh_info`,
plus the readers `bh_tool_uses`, `bh_final_text`, `bh_result_field`,
`bh_hook_blocks`.

## Other providers

`ABE_RUNNER` in `meta.env` is the seam for a Codex or Gemini runner. Only
`claude` is implemented; setting anything else makes `bh_session` exit 2 with
a clear message rather than pretending.
