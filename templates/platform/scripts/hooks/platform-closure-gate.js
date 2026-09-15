#!/usr/bin/env node
// Workflow guard for Edit/Write on stream state. Three dispatches:
//   1. anything under work/archive/          → block (archiving is CLI-only)
//   2. work/<slug>.md                        → block edits that grant approval
//      by hand or tick a criterion the owner owns
//   3. work/ACTIVE.md                        → block closing/removing a row
//      without the CLI's approval record and complete criteria
// Shell commands stay governed by the CLI and native permissions; an editable
// file cannot prove identity. Exit 2 blocks the edit; exit 1 reports a hook
// error and lets the edit proceed.
const fs = require('fs');
const path = require('path');

const APPROVAL = /^\s*closure_approved\s*:\s*['"]?true['"]?\s*$/i;
const RECORD = /^\s*approved_(by|at)\s*:/i;
const TICKED = /^(\s*[-*]\s+)\[[xX]\]\s+(.*\S)\s*$/;
const UNTICKED = /^(\s*[-*]\s+)\[\s\]\s+(.*\S)\s*$/;

function rows(content) {
  const result = new Map();
  for (const line of content.split(/\r?\n/)) {
    if (!/^\s*\|/.test(line)) continue;
    const cells = line.split('|').slice(1, -1).map(cell => cell.trim());
    if (cells.length !== 5 || !/^[a-z0-9][a-z0-9-]*$/.test(cells[0])) continue;
    result.set(cells[0], cells[2]);
  }
  return result;
}

function lines(text) { return text.split(/\r?\n/); }

function block(reason) {
  // With exit 2 Claude reads stderr; stdout JSON is ignored.
  process.stderr.write('STREAM CLOSURE BLOCKED — ' + reason + '\n');
  process.exitCode = 2;
}

function hookError(reason) {
  // Unreadable hook input says nothing about the edit: report, do not block.
  process.stderr.write('Agentboard closure gate could not read hook input: ' + reason + '\n');
  process.exitCode = 1;
}

// Approval the CLI recorded: flag plus who/when. A bare flag is a hand edit.
function cliApproved(metadata) {
  return APPROVAL.test(metadata.match(/^\s*closure_approved.*$/m)?.[0] || '')
    && /^\s*approved_by\s*:\s*\S/m.test(metadata);
}

function guardStreamFile(slug, resolved, incoming) {
  const onDisk = fs.existsSync(resolved) ? fs.readFileSync(resolved, 'utf8') : '';
  const existing = new Set(lines(onDisk));
  for (const line of lines(incoming)) {
    if ((APPROVAL.test(line) || RECORD.test(line)) && !existing.has(line)) {
      block('only the owner can approve closure for "' + slug + '" — ask them to run: agentboard close ' + slug + ' --approve');
      return true;
    }
  }
  for (const line of lines(incoming)) {
    const ticked = line.match(TICKED);
    if (!ticked || !/\bowner\b/i.test(ticked[2])) continue;
    const wasOpen = lines(onDisk).some(disk => {
      const open = disk.match(UNTICKED);
      return open && open[2] === ticked[2];
    });
    if (wasOpen) {
      block('"' + line.trim() + '" is the owner\'s to verify — only the owner can tick it');
      return true;
    }
  }
  return false;
}

function guardRegistry(resolved, tool, input, incoming) {
  const oldContent = tool === 'Write'
    ? (fs.existsSync(resolved) ? fs.readFileSync(resolved, 'utf8') : '')
    : input.old_string || '';
  const before = rows(oldContent);
  const after = rows(incoming);
  const closing = /^(done|closed|archived)$/i;
  for (const [slug, previous] of before) {
    if (after.has(slug) && (!closing.test(after.get(slug)) || closing.test(previous))) continue;
    const streamFile = path.join(path.dirname(resolved), slug + '.md');
    if (!fs.existsSync(streamFile)) {
      block('Cannot establish approval: stream file is missing for "' + slug + '".');
      return;
    }
    const content = fs.readFileSync(streamFile, 'utf8');
    // Parse only the leading metadata block, with legacy metadata support.
    const metadata = content.startsWith('---\n')
      ? content.split(/^---\s*$/m)[1] : content.split(/^## /m)[0];
    if (!cliApproved(metadata || '')) {
      block('closure for "' + slug + '" was not approved by the owner — ask them to run: agentboard close ' + slug + ' --approve');
      return;
    }
    const section = content.match(/^## Done criteria\s*\r?\n([\s\S]*?)(?=^## |$(?![\s\S]))/m)?.[1] || '';
    if (/^\s*[-*]\s+\[\s\]/m.test(section)) {
      block('Unchecked done criteria remain for "' + slug + '".');
      return;
    }
  }
}

let input = '';
const timeout = setTimeout(() => {
  hookError('timed out waiting for stdin.');
  process.exit(1);
}, 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  clearTimeout(timeout);
  let data;
  try {
    data = JSON.parse(input);
    if (!data || typeof data !== 'object') throw new Error('hook input is not a JSON object');
  } catch (error) {
    hookError(error.message);
    return;
  }
  try {
    const tool = data.tool_name;
    if (!['Edit', 'Write'].includes(tool)) return;
    const toolInput = data.tool_input || {};
    const filePath = toolInput.file_path || '';
    const archive = filePath.match(/(^|[/\\])work[/\\]archive[/\\]([a-z0-9][a-z0-9-]*)?/);
    if (archive) {
      const slug = archive[2] || '<slug>';
      block('nothing may be written under work/archive/ — archiving happens only through: agentboard close ' + slug + ' --confirm');
      return;
    }
    const stream = filePath.match(/(^|[/\\])work[/\\]([a-z0-9][a-z0-9-]*)\.md$/);
    const registry = /(^|[/\\])work[/\\]ACTIVE\.md$/.test(filePath);
    if (!stream && !registry) return;
    const resolved = path.resolve(data.cwd || process.cwd(), filePath);
    const incoming = tool === 'Write' ? toolInput.content : toolInput.new_string;
    if (typeof incoming !== 'string') throw new Error('Missing replacement content');
    if (stream) { guardStreamFile(stream[2], resolved, incoming); return; }
    guardRegistry(resolved, tool, toolInput, incoming);
  } catch (error) {
    block('Cannot validate this edit: ' + error.message);
  }
});
