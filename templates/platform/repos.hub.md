# {{PROJECT_NAME}} — Platform Brains Hub (Multi-Repo)

Last updated: {{TODAY}}

> {{DESCRIPTION}}

This folder is a **platform brains hub** — it coordinates context across multiple sibling repos. It does not contain application code of its own. The `.platform/` pack here is the single source of truth for cross-repo conventions, architecture, decisions, and workflow.

---

## Repos

Fill one row per sibling repo. Paths are relative to this hub folder (e.g. `../my-backend`) or absolute. The **Deep reference** column points at a per-repo reference file under `.platform/` (you'll create these during activation or as each repo is onboarded via `agentboard add-repo`).

| Repo ID | Path | Role / stack hint | Deep reference |
|---|---|---|---|
| _repo-1_ | `../repo-1` | _e.g. backend / django_ | `repo-1.md` |
| _repo-2_ | `../repo-2` | _e.g. frontend / react-vite_ | `repo-2.md` |
| _repo-3_ | `../repo-3` | _e.g. backend / serverless-functions_ | `repo-3.md` |

Replace placeholder rows with the real repos. Delete unused rows. Add more as needed.

## Conventions — which file governs which area

| Area you're touching | Read first |
|---|---|
| HTTP / API endpoints | `conventions/api.md` |
| Auth / tenant isolation / secrets | `conventions/security.md` + `conventions/permissions.md` |
| Tests | `conventions/testing.md` |
| Deploy / release / rollback | `conventions/deployment.md` |
| QA / manual verification | `conventions/qa.md` |
| Product scope / user value | `conventions/pm.md` |
| Stack-specific rules (per repo) | `conventions/{stack}.md` |

## Specialist routing (if you use Claude Code skills)

| When you touch... | Use skill |
|---|---|
| _Backend API endpoints_ | _e.g. `django-api` or `fastapi-routes`_ |
| _Frontend components_ | _e.g. `react-ui`_ |
| _Mobile code_ | _e.g. `ios-swift` / `android-kotlin` / `flutter`_ |
| _Tests_ | _e.g. `test-backend` / `test-frontend`_ |
| _Bug investigation_ | `investigate` or `detective` |
| _Code review before PR_ | `review` |
| _Real-browser QA_ | `browse` or `qa` |

Fill this table once with the skills you actually use. Delete rows for tech you don't touch.

## Hub rules (apply to every sibling repo)

1. One complete idea per file (~300 lines = the "split?" tripwire, not a gate)
2. No secrets in code, logs, or committed files
3. Every tenant-scoped query filters by trusted context, not query params (if applicable)
4. API response shape matches `conventions/api.md`
5. Every new feature has at least one happy-path + one edge-case test
6. Cross-repo API contracts stay backward-compatible unless every affected repo is updated in the same change
7. Architectural decisions that span >1 repo land in `decisions.md` here, not in individual repo READMEs

## Onboarding a new sibling repo

Run `agentboard add-repo <path-to-sibling>` from this hub folder. That copies per-repo entry file templates (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) into the sibling so its AI CLI sessions point back at this hub's `.platform/` pack.

Then:
1. Add a row to the **Repos** table above.
2. Create `.platform/<repo-slug>.md` with the repo's stack, conventions, file layout, and domain notes.
3. Update `.platform/scripts/sync-context.sh` `REPOS=()` array with the new path.
