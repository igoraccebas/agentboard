---
domain_id: dom-<domain-slug>
slug: <domain-slug>
status: active
repo_ids: [repo-primary]
related_domain_slugs: []
created_at: YYYY-MM-DD
updated_at: YYYY-MM-DD
---

# <domain-slug>

_Metadata rules: `domain_id` must be `dom-<slug>`, `slug` must match the filename, `repo_ids` should name the repos this domain touches, and `updated_at` should change whenever contracts or touch-points change._

## What this domain does

_2 sentences. Explain the user-facing outcome of this domain._

## Backend / source of truth

- _Models, services, endpoints, and invariants_

## Frontend / clients

- _Routes, state, UI surfaces, widgets, or mobile touch-points_

## API contract locked

- _Response shapes, request constraints, or cross-repo assumptions that must not break_

## Key files

- _Absolute or repo-relative file paths_

## Verify (optional)

_Runtime recipe rows for this domain's top user-facing features — written by `ab-verify`, read by `ab-qa`. Project-level Launch / Doctor / Cleanup live in `conventions/verification.md`._

| Feature | Drive (exact command / route / selector) | Expected observable result | Evidence (path) |
|---|---|---|---|
| _feature_ | _how a user reaches it_ | _what a stranger can check_ | _`.platform/evidence/...`_ |

## Decisions locked

- _3–5 constraints or choices that are not up for re-litigation during normal feature work_
