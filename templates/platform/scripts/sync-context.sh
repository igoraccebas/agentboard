#!/usr/bin/env bash
# Sync only the managed root-entry block. Preserve all provider-owned text.
# Legacy source: wrap shared rules in begin/end v=1 markers before syncing.
set -euo pipefail
REPOS=(
  "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
)
MODE="${1:---check}"
case "$MODE" in
  --check|--apply) ;;
  --list) printf '%s\n' "${REPOS[@]}"; exit 0 ;;
  --help|-h) printf '%s\n' 'Usage: sync-context.sh [--check|--apply|--list]' 'Only managed root-entry blocks are synchronized; custom instructions are preserved.'; exit 0 ;;
  *) printf 'Unknown flag: %s\n' "$MODE" >&2; exit 2 ;;
esac
command -v node >/dev/null 2>&1 || { printf 'sync-context requires node\n' >&2; exit 2; }
status=0
for repo in "${REPOS[@]}"; do
  [[ -f "$repo/CLAUDE.md" ]] || { printf 'SKIP %s (no CLAUDE.md)\n' "$repo"; continue; }
  result=0
  node - "$repo" "$MODE" <<'NODE' || result=$?
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const [repo, mode] = process.argv.slice(2);
const begin = '<!-- agentboard:root-entry:begin v=1 -->';
const end = '<!-- agentboard:root-entry:end v=1 -->';
function span(text, required) {
  const first=text.indexOf(begin), last=text.indexOf(end);
  if (first<0 && last<0 && !required) return null;
  if (first<0 || last<first || text.indexOf(begin, first+begin.length)>=0 ||
      text.indexOf(end, last+end.length)>=0) {
    throw new Error('Expected one complete managed block: ' + begin + ' ... ' + end +
      '. Wrap only shared rules in CLAUDE.md; keep provider-specific rules outside.');
  }
  return [first,last+end.length];
}
try {
  const source=fs.readFileSync(path.join(repo,'CLAUDE.md'),'utf8');
  const sourceSpan=span(source,true);
  const shared=source.slice(...sourceSpan);
  // Validate every target before any write.
  const changes=['AGENTS','GEMINI'].map(variant => {
    const target=path.join(repo,variant+'.md');
    if (fs.existsSync(target) && fs.lstatSync(target).isSymbolicLink())
      throw new Error('Refusing symlink target: '+target);
    const original=fs.existsSync(target) ? fs.readFileSync(target,'utf8') : '';
    const range=span(original,false);
    const block=shared.replaceAll('Claude Code Entry', variant==='AGENTS' ? 'Codex CLI Entry' : 'Gemini CLI Entry');
    const next=range ? original.slice(0,range[0])+block+original.slice(range[1])
      : block+'\n'+(original ? '\n'+original : '');
    return {target,original,next};
  });
  let drift=false;
  for (const {target,original,next} of changes) {
    if (original===next) { console.log('OK '+target); continue; }
    drift=true;
    if (mode==='--apply') {
      const tmp=target+'.agentboard-'+crypto.randomUUID();
      try {
        fs.writeFileSync(tmp,next,{flag:'wx',mode:fs.existsSync(target) ? fs.statSync(target).mode : 0o644});
        fs.renameSync(tmp,target);
      } finally { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); }
      console.log('Synced managed block: '+target);
    } else console.log('DRIFT '+target+' (run --apply)');
  }
  if (drift && mode!=='--apply') process.exitCode=1;
} catch (error) {
  console.error(error.message);
  process.exitCode=2;
}
NODE
  (( result <= status )) || status="$result"
done
exit "$status"
