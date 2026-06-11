# {{PROJECT_NAME}} — Repos & Specialist Routing

Last updated: {{TODAY}}

---

## Repos

| Repo ID | Path | Role / stack hint | Deep reference |
|---|---|---|---|
| _example-backend_ | `../example-backend` | backend / django | `example-backend.md` |
| _example-frontend_ | `../example-frontend` | frontend / react-vite | `example-frontend.md` |

For single-repo projects, this file just has one row.

## Conventions — which file governs which area

| Area you're touching | Read first |
|---|---|
| HTTP / API endpoints | `conventions/api.md` |
| Auth / tenant isolation / secrets | `conventions/security.md` + `conventions/permissions.md` |
| Tests | `conventions/testing.md` |
| Deploy / release / rollback | `conventions/deployment.md` |
| QA / manual verification | `conventions/qa.md` |
| Product scope / user value | `conventions/pm.md` |
| Stack-specific rules | `conventions/{stack}.md` |

## Specialist routing (if you use Claude Code skills)

| When you touch... | Use skill |
|---|---|
| _Backend API endpoints_ | _e.g. `django-api` or `fastapi-routes`_ |
| _Frontend components_ | _e.g. `react-ui`_ |
| _Mobile code_ | _e.g. `ios-swift` / `android-kotlin` / `flutter`_ |
| _Native / engine code_ | _e.g. `cpp-core` / `unity-csharp`_ |
| _Tests_ | _e.g. `test-backend` / `test-frontend`_ |
| _Bug investigation_ | `investigate` or `detective` |
| _Code review before PR_ | `review` |
| _Real-browser QA_ | `browse` or `qa` |

Fill this table once with the skills you actually use. Delete rows for tech you don't touch.

## Hard repo rules carried over from the platform

These apply to every repo in this project:

1. One complete idea per file (~300 lines = the "split?" tripwire, not a gate)
2. No secrets in code, logs, or committed files
3. Every tenant-scoped query filters by trusted context, not query params (if applicable)
4. API response shape matches `conventions/api.md`
5. Every new feature has at least one happy-path + one edge-case test
