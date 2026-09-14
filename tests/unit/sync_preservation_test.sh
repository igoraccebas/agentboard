#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/helpers.sh"
node - "$TEST_ROOT" <<'NODE'
const fs = require('fs'), os = require('os'), path = require('path'), assert = require('assert');
const {spawnSync} = require('child_process');
const dir = fs.mkdtempSync(path.join(os.tmpdir(),'ab-sync-'));
const scripts = path.join(dir,'.platform/scripts'); fs.mkdirSync(scripts,{recursive:true});
const script = path.join(scripts,'sync-context.sh');
fs.copyFileSync(path.join(process.argv[2],'templates/platform/scripts/sync-context.sh'),script);
const begin='<!-- agentboard:root-entry:begin v=1 -->', end='<!-- agentboard:root-entry:end v=1 -->';
const shared = `${begin}\nShared rule\n${end}`;
fs.writeFileSync(path.join(dir,'CLAUDE.md'),`Claude private\n${shared}\nClaude footer\n`);
fs.writeFileSync(path.join(dir,'AGENTS.md'),'Codex private\n');
fs.writeFileSync(path.join(dir,'GEMINI.md'),`Gemini private\n${begin}\nOld rule\n${end}\nGemini footer\n`);
const run = (...args) => spawnSync('bash',[script,...args],{cwd:dir,encoding:'utf8'});
let result=run('--apply'); assert.equal(result.status,0,result.stderr);
assert.equal(fs.readFileSync(path.join(dir,'AGENTS.md'),'utf8'),`${shared}\n\nCodex private\n`);
assert.equal(fs.readFileSync(path.join(dir,'GEMINI.md'),'utf8'),`Gemini private\n${shared}\nGemini footer\n`);
assert.equal(run().status,0);
assert.equal(run('--apply').status,0);
fs.writeFileSync(path.join(dir,'CLAUDE.md'),'unmarked source\n');
const before=fs.readFileSync(path.join(dir,'AGENTS.md'),'utf8');
assert.equal(run('--apply').status,2);
assert.equal(fs.readFileSync(path.join(dir,'AGENTS.md'),'utf8'),before);
fs.writeFileSync(path.join(dir,'CLAUDE.md'),`${shared}\n`);
fs.writeFileSync(path.join(dir,'GEMINI.md'),`${begin}\nbroken block\n`);
assert.equal(run('--apply').status,2);
assert.equal(fs.readFileSync(path.join(dir,'AGENTS.md'),'utf8'),before);
NODE
