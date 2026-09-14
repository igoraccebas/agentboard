#!/usr/bin/env node
// Workflow guard for Edit/Write on ACTIVE.md. Shell commands remain governed
// by CLI validation and native permissions; editable files cannot prove identity.
// Exit 2 blocks the edit; exit 1 reports a hook error and lets the edit proceed.
const fs = require('fs');
const path = require('path');

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
    if (!['Edit', 'Write'].includes(data.tool_name)) return;
    const filePath = data.tool_input?.file_path || '';
    if (!/(^|[/\\])work[/\\]ACTIVE\.md$/.test(filePath)) return;
    const resolved = path.resolve(data.cwd || process.cwd(), filePath);
    const oldContent = data.tool_name === 'Write'
      ? (fs.existsSync(resolved) ? fs.readFileSync(resolved, 'utf8') : '')
      : data.tool_input.old_string || '';
    const newContent = data.tool_name === 'Write'
      ? data.tool_input.content : data.tool_input.new_string;
    if (typeof newContent !== 'string') throw new Error('Missing replacement content');
    const before = rows(oldContent);
    const after = rows(newContent);
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
      if (!/^closure_approved:\s*true\s*$/m.test(metadata || '')) {
        block('closure_approved is not set to true for "' + slug + '". Obtain owner sign-off first.');
        return;
      }
      const section = content.match(/^## Done criteria\s*\r?\n([\s\S]*?)(?=^## |$(?![\s\S]))/m)?.[1] || '';
      if (/^\s*[-*]\s+\[\s\]/m.test(section)) {
        block('Unchecked done criteria remain for "' + slug + '".');
        return;
      }
    }
  } catch (error) {
    block('Cannot validate this edit: ' + error.message);
  }
});
