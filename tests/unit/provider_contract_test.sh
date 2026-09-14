#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

test_installed_codex_roles_resolve_and_use_supported_sandboxes() {
  local dir
  dir="$(mktemp -d)"
  init_project_fixture "$dir"
  node - "$dir" <<'NODE'
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const root = path.join(process.argv[2], '.codex');
const config = fs.readFileSync(path.join(root, 'config.toml'), 'utf8');
const roles = [...config.matchAll(/^config_file\s*=\s*"([^"]+)"/gm)];
assert.strictEqual(roles.length, 4);
for (const [, relative] of roles) {
  const rolePath = path.resolve(root, relative);
  assert(fs.existsSync(rolePath), `Role path does not resolve: ${rolePath}`);
  const role = fs.readFileSync(rolePath, 'utf8');
  const sandbox = role.match(/^sandbox_mode\s*=\s*"([^"]+)"/m)?.[1];
  assert(['read-only', 'workspace-write', 'danger-full-access'].includes(sandbox));
  assert(!/^model\s*=/m.test(role), 'Default roles should inherit the selected model');
  assert(!role.includes('codex-4-5'), 'Do not log a hardcoded model');
}
NODE
}

test_installed_codex_roles_resolve_and_use_supported_sandboxes
