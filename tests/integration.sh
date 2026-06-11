#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTBOARD="$ROOT/bin/agentboard"


# git < 2.28 has no `init -b`; fall back to pointing HEAD by hand so the
# suite still runs on older stock-macOS git installs.
git_init_branch() {
  local dir="$1" branch="${2:-main}"
  if ! git -C "$dir" init -b "$branch" >/dev/null 2>&1; then
    git -C "$dir" init >/dev/null 2>&1
    git -C "$dir" symbolic-ref HEAD "refs/heads/$branch" >/dev/null 2>&1
  fi
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_file_contains() {
  local file="$1" needle="$2"
  grep -Fq "$needle" "$file" || fail "expected $file to contain: $needle"
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

make_single_repo_fixture() {
  local dir="$1"
  mkdir -p "$dir/src/features/auth" "$dir/src/features/billing"
  printf 'export const auth = true;\n' > "$dir/src/features/auth/index.ts"
  printf 'export const billing = true;\n' > "$dir/src/features/billing/index.ts"
  printf '{\n  "name": "single",\n  "scripts": {\n    "dev": "vite",\n    "test": "vitest",\n    "build": "vite build"\n  }\n}\n' > "$dir/package.json"
  git_init_branch "$dir" feat-auth-session
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Agentboard Test"
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" >/dev/null 2>&1
}

make_dirty_default_branch_fixture() {
  local dir="$1"
  mkdir -p "$dir/src/features/auth"
  printf 'export const auth = true;\n' > "$dir/src/features/auth/index.ts"
  printf '{\n  "name": "dirty",\n  "scripts": {\n    "dev": "vite",\n    "test": "vitest",\n    "build": "vite build"\n  }\n}\n' > "$dir/package.json"
  git_init_branch "$dir" main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Agentboard Test"
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" >/dev/null 2>&1
}

make_doc_artifact_fixture() {
  local dir="$1"
  mkdir -p "$dir/src/features/auth" "$dir/docs"
  printf 'export const auth = true;\n' > "$dir/src/features/auth/index.ts"
  printf '# Sample\n' > "$dir/README.md"
  printf '# Architecture\n' > "$dir/architecture.md"
  printf '# Decisions\n' > "$dir/decisions.md"
  printf 'openapi: 3.0.0\n' > "$dir/openapi.yaml"
  printf '{\n  "name": "doc-artifacts",\n  "scripts": {\n    "dev": "vite",\n    "test": "vitest",\n    "build": "vite build"\n  }\n}\n' > "$dir/package.json"
  git_init_branch "$dir" main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Agentboard Test"
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" >/dev/null 2>&1
}

make_hub_fixture() {
  local dir="$1"
  mkdir -p "$dir/backend/accounts" "$dir/frontend/src/features/auth" "$dir/frontend/src/features/billing"
  printf 'from django.apps import AppConfig\n' > "$dir/backend/accounts/apps.py"
  printf 'print(\"ok\")\n' > "$dir/backend/manage.py"
  printf 'export const auth = true;\n' > "$dir/frontend/src/features/auth/index.ts"
  printf 'export const billing = true;\n' > "$dir/frontend/src/features/billing/index.ts"
  printf '{\n  "name": "frontend",\n  "dependencies": {\n    "react": "^19.0.0"\n  },\n  "scripts": {\n    "dev": "vite",\n    "test": "vitest",\n    "build": "vite build"\n  }\n}\n' > "$dir/frontend/package.json"
  git_init_branch "$dir/backend" feat-auth-hardening
  git -C "$dir/backend" config user.email test@example.com
  git -C "$dir/backend" config user.name "Agentboard Test"
  git -C "$dir/backend" add .
  git -C "$dir/backend" commit -m "initial" >/dev/null 2>&1
  git_init_branch "$dir/frontend" fix-billing-bug
  git -C "$dir/frontend" config user.email test@example.com
  git -C "$dir/frontend" config user.name "Agentboard Test"
  git -C "$dir/frontend" add .
  git -C "$dir/frontend" commit -m "initial" >/dev/null 2>&1
}

make_unknown_repo_fixture() {
  local dir="$1"
  mkdir -p "$dir/scripts"
  printf '#!/usr/bin/env bash\necho helper\n' > "$dir/scripts/helper.sh"
  chmod +x "$dir/scripts/helper.sh"
  git_init_branch "$dir" main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Agentboard Test"
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" >/dev/null 2>&1
}

make_node_backend_fixture() {
  local dir="$1"
  mkdir -p "$dir/src"
  printf '{\n  "name": "api-service",\n  "dependencies": {\n    "express": "^5.0.0"\n  },\n  "scripts": {\n    "start": "node src/server.js",\n    "test": "node --test",\n    "build": "tsup src/server.ts"\n  }\n}\n' > "$dir/package.json"
  printf 'console.log(\"ok\")\n' > "$dir/src/server.js"
  git_init_branch "$dir" main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Agentboard Test"
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" >/dev/null 2>&1
}

make_ios_fixture() {
  local dir="$1"
  mkdir -p "$dir/App.xcodeproj" "$dir/ios"
  printf '// project placeholder\n' > "$dir/App.xcodeproj/project.pbxproj"
  git_init_branch "$dir" main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Agentboard Test"
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" >/dev/null 2>&1
}

init_project() {
  local dir="$1"
  (
    cd "$dir"
    printf '\n\n' | "$AGENTBOARD" init >/dev/null 2>&1
    git config user.email test@example.com
    git config user.name "Agentboard Test"
    git add .
    git commit -m "agentboard init" >/dev/null 2>&1
  )
}

init_hub() {
  local dir="$1"
  (
    cd "$dir"
    printf '\n\nY\n' | "$AGENTBOARD" init >/dev/null 2>&1
    git init >/dev/null 2>&1 || true
    git config user.email test@example.com
    git config user.name "Agentboard Test"
    git add .platform .claude CLAUDE.md
    git commit -m "agentboard init" >/dev/null 2>&1
  )
}

test_single_repo_branch_inference() {
  local dir
  dir="$(mktemp -d)"
  make_single_repo_fixture "$dir"
  init_project "$dir"

  local output
  output="$(
    cd "$dir"
    "$AGENTBOARD" bootstrap
  )"

  assert_contains "$output" "Inferred domains"
  assert_contains "$output" "auth -> repos [repo-primary]"
  assert_contains "$output" "billing -> repos [repo-primary]"
  assert_contains "$output" "auth-session"
  assert_contains "$output" "confidence: medium"
  assert_contains "$output" "agentboard new-stream auth-session --domain auth --type feature --repo repo-primary"
}

test_apply_domains_creates_stubs() {
  local dir
  dir="$(mktemp -d)"
  make_single_repo_fixture "$dir"
  init_project "$dir"

  (
    cd "$dir"
    "$AGENTBOARD" bootstrap --apply-domains >/dev/null
  )

  [[ -f "$dir/.platform/domains/auth.md" ]] || fail "expected inferred auth domain stub"
  [[ -f "$dir/.platform/domains/billing.md" ]] || fail "expected inferred billing domain stub"
  assert_file_contains "$dir/.platform/domains/auth.md" "domain_id: dom-auth"
  assert_file_contains "$dir/.platform/domains/auth.md" "repo_ids: [repo-primary]"
}

test_default_branch_dirty_worktree_inference() {
  local dir
  dir="$(mktemp -d)"
  make_dirty_default_branch_fixture "$dir"
  init_project "$dir"
  printf 'export function normalizeAuthError(err) { return err?.message ?? \"auth fix\"; }\n' > "$dir/src/features/auth/errors.ts"

  local output
  output="$(
    cd "$dir"
    "$AGENTBOARD" bootstrap
  )"

  assert_contains "$output" "auth-errors-fix"
  assert_contains "$output" "branch: main"
  assert_contains "$output" "confidence: high"
  assert_contains "$output" "agentboard new-stream auth-errors-fix --domain auth --type bug --repo repo-primary"
}

test_hub_bootstrap_references_and_high_confidence_streams() {
  local dir
  dir="$(mktemp -d)"
  make_hub_fixture "$dir"
  init_hub "$dir"
  printf 'changed\n' > "$dir/frontend/src/features/billing/view.tsx"

  local output
  output="$(
    cd "$dir"
    "$AGENTBOARD" bootstrap --apply-domains
  )"

  assert_contains "$output" "auth-hardening"
  assert_contains "$output" "confidence: high"
  assert_contains "$output" "billing-bug"
  assert_contains "$output" "agentboard new-stream billing-bug --domain billing --type bug --repo frontend"

  assert_file_contains "$dir/.platform/backend.md" 'Repo role: backend'
  assert_file_contains "$dir/.platform/backend.md" 'Stack hint: django'
  assert_file_contains "$dir/.platform/backend.md" 'Dev: `python manage.py runserver`'
  assert_file_contains "$dir/.platform/backend.md" 'Test: `python manage.py test`'
  assert_file_contains "$dir/.platform/backend.md" 'Likely serves APIs, auth, or shared contracts to `frontend`'
  assert_file_contains "$dir/.platform/frontend.md" 'Repo role: frontend'
  assert_file_contains "$dir/.platform/frontend.md" 'Stack hint: react'
  assert_file_contains "$dir/.platform/frontend.md" 'Dev: `npm run dev`'
  assert_file_contains "$dir/.platform/frontend.md" 'Build: `npm run build`'
  assert_file_contains "$dir/.platform/frontend.md" 'Likely consumes APIs or contracts from `backend`'
}

test_unknown_repo_safe_fallback() {
  local dir ref_file
  dir="$(mktemp -d)"
  make_unknown_repo_fixture "$dir"
  init_project "$dir"
  ref_file="$dir/.platform/$(slugify "$(basename "$dir")").md"

  (
    cd "$dir"
    "$AGENTBOARD" bootstrap >/dev/null
  )

  assert_file_contains "$ref_file" 'Repo role: unknown'
  assert_file_contains "$ref_file" 'Stack hint: unknown'
  assert_file_contains "$ref_file" 'Dev: `_fill during activation_`'
}

test_node_backend_role_hint() {
  local dir ref_file
  dir="$(mktemp -d)"
  make_node_backend_fixture "$dir"
  init_project "$dir"
  ref_file="$dir/.platform/$(slugify "$(basename "$dir")").md"

  (
    cd "$dir"
    "$AGENTBOARD" bootstrap >/dev/null
  )

  assert_file_contains "$ref_file" 'Repo role: backend'
  assert_file_contains "$ref_file" 'Stack hint: node-service'
  assert_file_contains "$ref_file" 'Dev: `npm start`'
  assert_file_contains "$ref_file" 'Test: `npm test`'
  assert_file_contains "$ref_file" 'Build: `npm run build`'
}

test_ios_role_hint_safe_defaults() {
  local dir ref_file
  dir="$(mktemp -d)"
  make_ios_fixture "$dir"
  init_project "$dir"
  ref_file="$dir/.platform/$(slugify "$(basename "$dir")").md"

  (
    cd "$dir"
    "$AGENTBOARD" bootstrap >/dev/null
  )

  assert_file_contains "$ref_file" 'Repo role: mobile'
  assert_file_contains "$ref_file" 'Stack hint: ios'
  assert_file_contains "$ref_file" 'Test: `xcodebuild test -scheme <fill>`'
  assert_file_contains "$ref_file" 'Build: `xcodebuild build -scheme <fill>`'
}

test_local_context_artifacts_are_listed() {
  local dir ref_file
  dir="$(mktemp -d)"
  make_doc_artifact_fixture "$dir"
  init_project "$dir"
  ref_file="$dir/.platform/$(slugify "$(basename "$dir")").md"

  (
    cd "$dir"
    "$AGENTBOARD" bootstrap >/dev/null
  )

  assert_file_contains "$ref_file" '## Local context artifacts'
  assert_file_contains "$ref_file" '`README.md`'
  assert_file_contains "$ref_file" '`docs/`'
  assert_file_contains "$ref_file" '`architecture.md`'
  assert_file_contains "$ref_file" '`decisions.md`'
  assert_file_contains "$ref_file" '`openapi.yaml`'
}

test_single_repo_branch_inference
test_apply_domains_creates_stubs
test_default_branch_dirty_worktree_inference
test_hub_bootstrap_references_and_high_confidence_streams
test_unknown_repo_safe_fallback
test_node_backend_role_hint
test_ios_role_hint_safe_defaults
test_local_context_artifacts_are_listed

printf 'PASS: integration\n'
