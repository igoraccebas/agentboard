#!/usr/bin/env bash
# Seed a tiny script with a real bug and a passing bash harness that does not
# yet cover the bug. base: slugify keeps a trailing dash. heldout: truncate is
# one character too long when it adds the ellipsis.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
fixture="$1" variant="${2:-base}"
bh_fixture "$fixture"
mkdir -p "$fixture/src" "$fixture/tests"
case "$variant" in
  base)
    cat > "$fixture/src/slugify.sh" <<'SRC'
#!/usr/bin/env bash
# slugify <text>: lowercase; each run of non-alphanumerics becomes one dash.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//'
  printf '\n'
}
slugify "$@"
SRC
    cat > "$fixture/tests/run.sh" <<'HARNESS'
#!/usr/bin/env bash
# Assertion harness: one check per line, exits non-zero on any failure.
set -u
cd "$(dirname "$0")/.." || exit 1
fails=0
check() {
  local got; got="$(bash src/slugify.sh "$1")"
  if [[ "$got" == "$2" ]]; then printf 'PASS %s -> %s\n' "$1" "$got"
  else printf 'FAIL %s -> got %s, expected %s\n' "$1" "$got" "$2"; fails=$((fails + 1)); fi
}
check "Hello World" "hello-world"
check "Agent_Board v2" "agent-board-v2"
exit "$fails"
HARNESS
    ;;
  heldout)
    cat > "$fixture/src/truncate.sh" <<'SRC'
#!/usr/bin/env bash
# truncate <text> <max>: return text unchanged if it fits, otherwise cut it and
# append "..." so the result is exactly <max> characters long.
truncate() {
  local text="$1" max="$2"
  if (( ${#text} <= max )); then printf '%s\n' "$text"; return; fi
  printf '%s...\n' "${text:0:$((max - 2))}"
}
truncate "$@"
SRC
    cat > "$fixture/tests/run.sh" <<'HARNESS'
#!/usr/bin/env bash
# Assertion harness: one check per line, exits non-zero on any failure.
set -u
cd "$(dirname "$0")/.." || exit 1
fails=0
check() {
  local got; got="$(bash src/truncate.sh "$1" "$2")"
  if [[ "$got" == "$3" ]]; then printf 'PASS %s/%s -> %s\n' "$1" "$2" "$got"
  else printf 'FAIL %s/%s -> got %s, expected %s\n' "$1" "$2" "$got" "$3"; fails=$((fails + 1)); fi
}
check "hello" 10 "hello"
check "abc" 3 "abc"
exit "$fails"
HARNESS
    ;;
  *) printf 'unknown variant %s\n' "$variant" >&2; exit 2 ;;
esac
chmod +x "$fixture"/src/*.sh "$fixture/tests/run.sh"
( cd "$fixture" && bash tests/run.sh >/dev/null ) || { printf 'seeded harness must pass before the session\n' >&2; exit 1; }
bh_save_baseline "$fixture" tests/run.sh
commit_all "$fixture" "seed scenario"
