# Contributing to agentboard

agentboard is small on purpose: a single bash CLI and a handful of
markdown templates. Contributions are very welcome — the guide below
is what you need to get your change merged without friction.

## Quick start

```bash
# 1. Fork da0101/agentboard on GitHub, then clone your fork
git clone git@github.com:<you>/agentboard.git
cd agentboard

# 2. Make sure your fork has the upstream default branch (develop)
git remote add upstream git@github.com:da0101/agentboard.git
git fetch upstream
git checkout -b feature/my-change upstream/develop

# 3. Hack away, then test locally
./bin/agentboard init        # run it in a scratch directory
./bin/agentboard version

# 4. Commit, push, open a PR against upstream:develop
git commit -m "Add concise imperative summary"
git push -u origin feature/my-change
```

Open the PR in the GitHub UI — the PR template will prompt you for the
checklist below.

## Branch model (gitflow)

agentboard uses a strict gitflow layout:

- `main` — **release branch**. Protected. Only the maintainer can merge
  into `main`, and only from `develop` (or a hotfix branch). Every
  commit on `main` corresponds to a tagged release.
- `develop` — **integration branch**. This is the repository default
  branch and the base for every contributor PR. CI runs on every PR
  into `develop`.
- `feature/<short-name>` — **your work branch**. Always branch off
  `develop`, never off `main`. Keep it focused: one feature or fix per
  branch.
- `hotfix/<short-name>` — for urgent production fixes only. The
  maintainer handles these; contributors should not open hotfix PRs
  against `main` directly.

**PRs from contributors always target `develop`.** The maintainer
periodically merges `develop` into `main` and tags a release.

## Template content policy

agentboard templates are read (and partially executed) by AI coding
agents inside other people's projects. A malicious line in a template
`.md` file is effectively a supply-chain attack on every downstream
user. These rules are **hard rules** — the CI scanner in
`.github/workflows/security-scan.yml` enforces them and will fail your
PR if any are violated.

1. **No external URLs in template `.md` files.** If you need to
   reference external documentation, describe it in words and let the
   downstream LLM search for the current URL. Baking URLs into
   templates turns the template into a fetch-and-execute loader.
2. **No network calls in any script.** `curl`, `wget`, `nc`, `netcat`,
   and `/dev/tcp` are all forbidden in `bin/agentboard` and
   `templates/**/*.sh`. agentboard runs entirely from local files.
3. **No base64 or otherwise-obfuscated strings.** If a reviewer cannot
   immediately read what the line does, it does not belong in the
   repo.
4. **No instructions that reference sensitive files.** Template files
   must not tell an LLM to read `.env`, `.ssh/`, `id_rsa`,
   `id_ed25519`, credentials files, or API key files. Negative
   references ("never read `.env`", "`.env.example` is OK") are
   allowed; positive instructions are not.
5. **No prompt-injection patterns.** Phrases like "ignore previous
   instructions", "disregard the system prompt", "you are now", "act
   as if", and "pretend you are" are banned anywhere under
   `templates/`, regardless of context.
6. **Every template change needs a plain-English explanation.** The PR
   template has a section for this. Write what you changed, and why,
   in short English sentences a non-engineer could follow. "Improve
   wording" is not an explanation.

If you think you have a legitimate reason to violate one of these
rules, open an issue first and let's discuss — do not try to smuggle
the change through CI.

## Code style

- **Bash scripts** match the style of the existing `bin/agentboard`:
  `#!/usr/bin/env bash` with `set -euo pipefail`, 2-space indent,
  snake_case function names, and short focused helpers. Keep functions
  small; prefer extracting a new helper over deep nesting.
- **Markdown templates** use ATX headings (`#`, `##`, ...), fenced code
  blocks with a language tag, and soft wrap around 100 columns. Keep
  the imperative, second-person voice that the existing templates use
  — they are written for an AI agent to follow.
- **No emojis** in templates or scripts. The existing files use plain
  ASCII and we want to keep terminal output predictable.
- **File size**: one complete idea per file. Crossing ~300 lines is
  the tripwire to ask "is this still one idea?" — answer it in the PR.
  Split files holding two ideas; don't split a cohesive idea to satisfy
  the number.

## PR process

1. **Fill the PR template checklist in full.** An unchecked security
   box is treated the same as a CI failure.
2. **Wait for CI.** The required status checks are
   `prompt-injection-scan` and `script-security-scan`. Both must be
   green. `large-diff-warning` is advisory only but may prompt a
   reviewer comment.
3. **CODEOWNERS review.** Every PR needs at least one approving review
   from `@da0101` (configured in `.github/CODEOWNERS`). For
   template-heavy PRs expect the reviewer to read every changed line
   aloud to themselves — that is the policy, not personal.
4. **Stale reviews are dismissed.** If you push new commits after an
   approval, the approval is dismissed and you need a fresh one. This
   is intentional — last-minute diffs have shipped exploits before.
5. **Squash-merge** is the default merge strategy on `develop`. Keep
   your commit message focused; the maintainer will adjust the final
   squash title if needed.

## Release process (maintainer only)

Contributors never touch `main` directly — that is the maintainer's job.

```
develop  ──── feature PRs land here ────────────────────────────►
                                    │
                                    │  maintainer opens PR: develop → main
                                    ▼
main     ──── release commits only ─── tag v1.2.3 ── GitHub Release created
```

1. Maintainer opens a PR from `develop` → `main` (the "release PR")
2. PR is reviewed, CI passes, maintainer merges
3. Maintainer creates and pushes a SemVer tag on `main`: `git tag -s v1.2.3 && git push origin v1.2.3`
4. The release workflow (`.github/workflows/release.yml`) fires automatically:
   - Verifies the tag points to a commit on `main` (not develop or a feature branch)
   - Generates `SHA256SUMS` for `bin/agentboard` + all template files
   - Creates the GitHub release with checksums attached

Tags on non-`main` commits are rejected by the release workflow. **Never tag from `develop`.**

## Reporting security issues

**Do not file security bugs as normal GitHub issues.** See
[SECURITY.md](SECURITY.md) for the private disclosure process.

## License

By contributing, you agree that your contribution will be released
under the same license as the project (see `LICENSE`).
