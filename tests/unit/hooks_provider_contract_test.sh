#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"

node - "$TEST_ROOT" <<'NODE'
const assert = require('assert');
const path = require('path');
const fs = require('fs');
const os = require('os');
const {spawnSync} = require('child_process');
const root = process.argv[2];
const hooks = path.join(root, 'templates/platform/scripts/hooks');
let failed = false;
function test(name, run) {
  try { run(); } catch (error) { failed = true; console.error(`${name}: ${error.message}`); }
}
for (const command of ['git commit -m x', 'git -C /tmp/repo commit -m x', 'git --git-dir=/tmp/repo/.git push', 'git reset HEAD --hard', 'git branch feature -D', 'agentboard approve abc', 'agentboard close abc --confirm', 'agentboard close --confirm abc', 'git\tcommit -m x']) {
  test(`guard requests approval: ${command}`, () => {
    const result = spawnSync('bash', [path.join(hooks, 'bash-guard.sh')], {input: JSON.stringify({tool_name:'Bash',tool_input:{command}}), encoding:'utf8'});
    assert.strictEqual(result.status, 0);
    const response = JSON.parse(result.stdout).hookSpecificOutput;
    assert.strictEqual(response?.hookEventName, 'PreToolUse');
    assert.strictEqual(response.permissionDecision, 'ask');
    assert(response.permissionDecisionReason);
  });
}
test('guard ignores other JSON fields', () => {
  const result = spawnSync('bash', [path.join(hooks, 'bash-guard.sh')], {input: JSON.stringify({tool_name:'Bash',tool_input:{command:'git status'},note:'git commit'}), encoding:'utf8'});
  assert.strictEqual(result.stdout, '');
});

const row = '| auth-fix | bug | active | codex | today |\n';
function closure(tool_name, oldContent, newContent, streamContent, expected) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-hook-'));
  const work = path.join(dir, '.platform/work');
  fs.mkdirSync(work, {recursive:true});
  const active = path.join(work, 'ACTIVE.md');
  fs.writeFileSync(active, oldContent);
  if (streamContent !== null) fs.writeFileSync(path.join(work, 'auth-fix.md'), streamContent);
  const tool_input = tool_name === 'Write' ? {file_path:active,content:newContent} : {file_path:active,old_string:oldContent,new_string:newContent};
  const result = spawnSync('node', [path.join(hooks,'platform-closure-gate.js')], {input:JSON.stringify({tool_name,cwd:dir,tool_input}),encoding:'utf8'});
  assert.strictEqual(result.status, expected, result.stdout + result.stderr);
  if (expected === 2) assert(result.stderr.includes('STREAM CLOSURE BLOCKED'));
}
const approved = 'closure_approved: true\n\n## Done criteria\n- [x] verified\n';
test('Write cannot remove unapproved stream', () => closure('Write',row,'', 'closure_approved: false',2));
test('Edit cannot close row by changing its status', () => closure('Edit',row,row.replace('active','closed'), 'closure_approved: false',2));
test('missing stream cannot establish approval', () => closure('Edit',row,'',null,2));
test('truthy prefix is not explicit approval', () => closure('Edit',row,'','closure_approved: trueish',2));
test('approved Write can remove complete stream', () => closure('Write',row,'',approved,0));
test('Write retains streams with flexible table whitespace', () => closure('Write',row,row.replaceAll(' | ', '\t|\t'),'closure_approved: false',0));
test('new stream registration remains allowed', () => closure('Write','',row,null,0));

test('relative ACTIVE.md path is still guarded', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-hook-'));
  const work = path.join(dir, '.platform/work');
  fs.mkdirSync(work, {recursive:true});
  fs.writeFileSync(path.join(work, 'ACTIVE.md'), row);
  fs.writeFileSync(path.join(work, 'auth-fix.md'), 'closure_approved: false');
  const result = spawnSync('node', [path.join(hooks,'platform-closure-gate.js')], {input:JSON.stringify({tool_name:'Edit',cwd:path.join(dir,'.platform'),tool_input:{file_path:'work/ACTIVE.md',old_string:row,new_string:''}}),encoding:'utf8'});
  assert.strictEqual(result.status, 2, result.stdout + result.stderr);
});
test('Write can create a missing ACTIVE.md', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-hook-'));
  const work = path.join(dir, '.platform/work');
  fs.mkdirSync(work, {recursive:true});
  const result = spawnSync('node', [path.join(hooks,'platform-closure-gate.js')], {input:JSON.stringify({tool_name:'Write',cwd:dir,tool_input:{file_path:path.join(work,'ACTIVE.md'),content:row}}),encoding:'utf8'});
  assert.strictEqual(result.status, 0, result.stdout + result.stderr);
});

test('guard reports unreadable input without blocking', () => {
  for (const input of ['not json', '', JSON.stringify({tool_name:'Bash',tool_input:{}})]) {
    const result = spawnSync('bash', [path.join(hooks, 'bash-guard.sh')], {input, encoding:'utf8'});
    assert.strictEqual(result.status, 1, result.stdout + result.stderr);
    assert.strictEqual(result.stdout, '');
    assert(result.stderr.includes('could not read hook input'));
  }
});
test('closure gate reports unreadable input without blocking', () => {
  for (const input of ['not json', '', 'null']) {
    const result = spawnSync('node', [path.join(hooks,'platform-closure-gate.js')], {input, encoding:'utf8'});
    assert.strictEqual(result.status, 1, result.stdout + result.stderr);
    assert(!result.stderr.includes('STREAM CLOSURE BLOCKED'));
  }
});

test('install-hooks installs every referenced hook', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-install-hooks-'));
  fs.mkdirSync(path.join(dir,'.platform'));
  const result = spawnSync(path.join(root,'bin/agentboard'), ['install-hooks'], {cwd:dir,encoding:'utf8'});
  assert.strictEqual(result.status, 0, result.stderr);
  const settings = JSON.parse(fs.readFileSync(path.join(dir,'.claude/settings.json'),'utf8'));
  let closureMatcher;
  for (const entries of Object.values(settings.hooks)) for (const entry of entries) for (const hook of entry.hooks) {
    const relative = hook.command.match(/\.\/\.platform\/scripts\/hooks\/[^"\s]+/)?.[0];
    if (relative) assert(fs.existsSync(path.resolve(dir,relative)), `Missing installed hook: ${relative}`);
    if (hook.command.includes('platform-closure-gate.js')) closureMatcher = entry.matcher;
  }
  assert(new RegExp(`^(?:${closureMatcher})$`).test('Edit'));
  assert(new RegExp(`^(?:${closureMatcher})$`).test('Write'));
});
if (failed) process.exit(1);
NODE
