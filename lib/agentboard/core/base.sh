# -----------------------------------------------------------------------------
# Colors (honors NO_COLOR, disables if stdout isn't a TTY)
# -----------------------------------------------------------------------------

if [[ -n "${NO_COLOR:-}" ]] || ! [[ -t 1 ]]; then
  C_RESET=''; C_BOLD=''; C_DIM=''
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
else
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

say()  { printf '%s\n' "$*"; }
bold() { printf '%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
head() { printf '\n%s%s▸ %s%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }
ok()   { printf '  %s●%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '  %s⚠%s  %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '  %s✖%s  %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# ask <prompt> [default] [hint]
# Prints hint (if given) on its own dim line, then the prompt with the default
# shown in [brackets]. Returns the user input (or default) on stdout.
ask() {
  local prompt="$1" default="${2:-}" hint="${3:-}" reply
  if [[ -n "$hint" ]]; then
    printf '\n  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET" >&2
  fi
  if [[ -n "$default" ]]; then
    printf '  %s?%s %s%s%s %s[%s]%s: ' \
      "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$default" "$C_RESET" >&2
    read -r reply
    echo "${reply:-$default}"
  else
    printf '  %s?%s %s%s%s: ' \
      "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" >&2
    read -r reply
    echo "$reply"
  fi
}

ask_yes_no() {
  local prompt="$1" reply
  printf '  %s?%s %s%s%s %s[y/N]%s: ' \
    "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$C_RESET" >&2
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ask_yes_no_default <prompt> <default: Y|N> [hint]
# Same styling as ask_yes_no but with a configurable default. An empty reply
# returns the default. Supports a dim-line hint printed above the prompt.
ask_yes_no_default() {
  local prompt="$1" default="${2:-N}" hint="${3:-}" reply bracket
  if [[ "$default" =~ ^[Yy]$ ]]; then
    bracket="[Y/n]"
  else
    bracket="[y/N]"
  fi
  if [[ -n "$hint" ]]; then
    printf '\n  %s%s%s\n' "$C_DIM" "$hint" "$C_RESET" >&2
  fi
  printf '  %s?%s %s%s%s %s%s%s: ' \
    "$C_CYAN" "$C_RESET" "$C_BOLD" "$prompt" "$C_RESET" "$C_DIM" "$bracket" "$C_RESET" >&2
  read -r reply
  if [[ -z "$reply" ]]; then
    [[ "$default" =~ ^[Yy]$ ]]
  else
    [[ "$reply" =~ ^[Yy]$ ]]
  fi
}

today() { date +%F; }

# parse_token_budget <value>
# Accepts "4000", "4k", or "4K" and echoes the integer token count.
# Returns non-zero on malformed input.
parse_token_budget() {
  local raw="$1" lower
  lower="$(printf '%s' "$raw" | tr 'A-Z' 'a-z')"
  if [[ "$lower" =~ ^([0-9]+)k$ ]]; then
    printf '%s\n' "$(( ${BASH_REMATCH[1]} * 1000 ))"
    return 0
  fi
  if [[ "$lower" =~ ^([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# estimate_tokens_for_file <file>
# Rough heuristic: 1 token ≈ 4 bytes of English markdown. Echoes 0 if the
# file does not exist. Zero runtime deps.
estimate_tokens_for_file() {
  local file="$1" bytes
  if [[ ! -f "$file" ]]; then
    printf '0\n'
    return 0
  fi
  bytes="$(wc -c < "$file" 2>/dev/null | tr -d ' ')"
  [[ -z "$bytes" ]] && bytes=0
  printf '%s\n' "$(( bytes / 4 ))"
}

require_templates() {
  [[ -d "$TEMPLATES_PLATFORM" ]] || die "templates/platform/ not found at $TEMPLATES_PLATFORM"
}

substitute() {
  # substitute <file> KEY1 value1 KEY2 value2 ...
  local file="$1"; shift
  local key value value_esc
  while [[ $# -gt 0 ]]; do
    key="$1"; value="$2"; shift 2
    value_esc="${value//|/\\|}"
    sed -i.bak "s|{{${key}}}|${value_esc}|g" "$file"
    rm -f "${file}.bak"
  done
}

trim() {
  local s="$*"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    BEGIN { in_fm = 0; seen = 0 }
    /^---[[:space:]]*$/ {
      if (!seen) { seen = 1; in_fm = 1; next }
      if (in_fm) exit
    }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") {
      sub("^[^:]+:[[:space:]]*", "", $0)
      print
      exit
    }
  ' "$file"
}

has_frontmatter() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local first_line
  IFS= read -r first_line < "$file" || true
  [[ "$first_line" == "---" ]]
}

legacy_stream_value() {
  local file="$1" label="$2"
  sed -n "s/^\\*\\*${label}:\\*\\* //p; /^\\*\\*${label}:\\*\\* /q" "$file"
}

is_legacy_stream_file() {
  local file="$1"
  has_frontmatter "$file" && return 1
  grep -q '^# ' "$file" 2>/dev/null || return 1
  grep -q '^\*\*Type:\*\* ' "$file" 2>/dev/null || return 1
  grep -q '^\*\*Status:\*\* ' "$file" 2>/dev/null || return 1
  return 0
}

is_legacy_domain_file() {
  local file="$1"
  has_frontmatter "$file" && return 1
  grep -Eq '^# (Domain: |[[:alnum:]])' "$file" 2>/dev/null || return 1
  grep -Eq '^## Backend|^## Frontend|^## Mobile|^## API endpoints|^## Key files' "$file" 2>/dev/null || return 1
  return 0
}

is_legacy_brief_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  grep -q '^## Active streams' "$file" 2>/dev/null
}

normalize_kebab_value() {
  local value
  value="$(trim "$1")"
  [[ -z "$value" ]] && return 0
  printf '%s' "$value" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

legacy_closure_approved() {
  local file="$1" value
  value="$(sed -n 's/^\*\*closure_approved:\*\* \([^ ]*\).*$/\1/p; /^\*\*closure_approved:\*\* /q' "$file")"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == "true" ]] && printf 'true\n' || printf 'false\n'
}

score_slug_similarity() {
  local a="$1" b="$2"
  if [[ "$a" == "$b" ]]; then
    printf '100\n'
    return 0
  fi
  awk -v a="$a" -v b="$b" '
    function stopword(tok) {
      return tok == "admin" || tok == "api" || tok == "flow" || tok == "analysis" || \
             tok == "error" || tok == "errors" || tok == "bug" || tok == "bugs" || \
             tok == "stability" || tok == "fix" || tok == "report" || tok == "reports"
    }
    function norm(tok) {
      tok=tolower(tok)
      if (length(tok) > 3 && tok ~ /s$/) sub(/s$/, "", tok)
      if (stopword(tok)) return ""
      return tok
    }
    BEGIN {
      n = split(a, A, /-/)
      for (i = 1; i <= n; i++) {
        tok = norm(A[i])
        if (tok != "") seen[tok] = 1
      }
      m = split(b, B, /-/)
      score = 0
      for (i = 1; i <= m; i++) {
        tok = norm(B[i])
        if (tok in seen) score++
      }
      print score
    }
  '
}

infer_stream_domain_slugs() {
  local stream_slug="$1"
  local best_score=0 score domain_file domain_slug matches=""
  while IFS= read -r domain_file; do
    [[ -n "$domain_file" ]] || continue
    domain_slug="$(basename "$domain_file" .md)"
    score="$(score_slug_similarity "$stream_slug" "$domain_slug")"
    if (( score > best_score )); then
      best_score="$score"
      matches="$domain_slug"
    elif (( score > 0 && score == best_score )); then
      matches="${matches}"$'\n'"$domain_slug"
    fi
  done < <(domain_files)
  if (( best_score > 0 )); then
    printf '%s\n' "$matches" | unique_nonempty_lines
  fi
  return 0
}

infer_repo_ids_from_text() {
  local file="$1" repos_file="$2"
  local repo_rows=""
  [[ -f "$repos_file" ]] && repo_rows="$(repo_rows_from_registry "$repos_file")"
  if [[ -z "$repo_rows" ]]; then
    printf 'repo-primary\n'
    return 0
  fi

  local repo_name repo_path repo_stack repo_ref matched alias path_base ref_base
  while IFS='|' read -r repo_name repo_path repo_stack repo_ref; do
    [[ -n "$repo_name" ]] || continue
    matched=0
    path_base="$(basename "${repo_path#./}")"
    ref_base="${repo_ref%.md}"
    for alias in "$repo_name" "$path_base" "$ref_base"; do
      [[ -z "$alias" || "$alias" == "." ]] && continue
      if grep -qiF "$alias" "$file"; then
        matched=1
        break
      fi
    done
    if (( !matched )); then
      case "$repo_name" in
        *backend*|*greybox*)
          grep -Eq '^## Backend|^### Backend|^## Backend / source of truth|Backend \(' "$file" && matched=1
          ;;
        *frontend*)
          grep -Eq '^## Frontend|^### Frontend|Frontend \(' "$file" && matched=1
          ;;
        *mobile*|*ios*|*android*)
          grep -Eq '^## Mobile|^### Mobile|Mobile \(' "$file" && matched=1
          ;;
      esac
    fi
    (( matched )) && printf '%s\n' "$repo_name"
  done <<< "$repo_rows"
  return 0
}

infer_domain_repo_ids() {
  local domain_file="$1" repos_file="$2"
  infer_repo_ids_from_text "$domain_file" "$repos_file" | unique_nonempty_lines
  return 0
}

infer_stream_repo_ids() {
  local stream_file="$1" repos_file="$2" domain_slugs="$3"
  local repo_id domain_slug domain_file
  while IFS= read -r domain_slug; do
    [[ -z "$domain_slug" ]] && continue
    domain_file="./.platform/domains/${domain_slug}.md"
    [[ -f "$domain_file" ]] || continue
    if has_frontmatter "$domain_file"; then
      inline_array_items "$(frontmatter_value "$domain_file" "repo_ids")"
    else
      infer_domain_repo_ids "$domain_file" "$repos_file"
    fi
  done <<< "$domain_slugs"
  infer_repo_ids_from_text "$stream_file" "$repos_file"
  return 0
}

inline_array_items() {
  local value
  value="$(trim "$1")"
  [[ -z "$value" || "$value" == "[]" ]] && return 0
  value="${value#\[}"
  value="${value%\]}"

  local item
  local -a items
  IFS=',' read -r -a items <<< "$value"
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && printf '%s\n' "$item"
  done
}

is_placeholder_value() {
  local value
  value="$(trim "$1")"
  [[ -z "$value" ]] && return 0
  [[ "$value" == "—" ]] && return 0
  [[ "$value" == "YYYY-MM-DD" ]] && return 0
  [[ "$value" =~ \<.*\> ]] && return 0
  [[ "$value" =~ _TODO_ ]] && return 0
  [[ "$value" =~ ^TBD ]] && return 0
  return 1
}

replace_template_literals() {
  local file="$1"; shift
  local old new new_esc
  while [[ $# -gt 0 ]]; do
    old="$1"; new="$2"; shift 2
    new_esc="${new//|/\\|}"
    sed -i.bak "s|$old|$new_esc|g" "$file"
  done
  rm -f "${file}.bak"
}

replace_frontmatter_line() {
  local file="$1" key="$2" value="$3"
  sed -i.bak -E "s|^${key}: .*|${key}: ${value}|" "$file"
  rm -f "${file}.bak"
}

# set_frontmatter_value <file> <key> <value>
# Replace the key when present; insert it before the closing --- when absent.
set_frontmatter_value() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^${key}:" "$file"; then
    replace_frontmatter_line "$file" "$key" "$value"
    return 0
  fi
  local tmp; tmp="$(mktemp)"
  awk -v kv="${key}: ${value}" '
    BEGIN { seen = 0; in_fm = 0 }
    /^---[[:space:]]*$/ {
      if (!seen) { seen = 1; in_fm = 1; print; next }
      if (in_fm) { print kv; in_fm = 0; print; next }
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

unique_nonempty_lines() {
  awk 'NF && !seen[$0]++'
}

frontmatter_inline_array() {
  local item out=""
  while IFS= read -r item; do
    item="$(trim "$item")"
    [[ -z "$item" ]] && continue
    if [[ -z "$out" ]]; then
      out="$item"
    else
      out="$out, $item"
    fi
  done
  printf '[%s]\n' "$out"
}

join_lines_comma() {
  awk 'NF { out = out ? out ", " $0 : $0 } END { print out }'
}

brief_is_placeholder() {
  local brief="$1"
  [[ ! -f "$brief" ]] && return 0
  grep -q "_not yet set — fill this in when you start your first workstream_" "$brief"
}

stream_rows_from_active() {
  local active="$1"
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^## / { exit }
    {
      slug = trim($2)
      type = trim($3)
      status = trim($4)
      agent = trim($5)
      updated = trim($6)
      if (slug == "" || slug == "Stream" || slug == "_(none)_" || slug ~ /^-+$/) next
      printf "%s|%s|%s|%s|%s\n", slug, type, status, agent, updated
    }
  ' "$active"
}

repo_rows_from_registry() {
  local repos_file="$1"
  awk -F'|' '
    function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
    /^## Repos/ { in_repos = 1; next }
    in_repos && /^## / { exit }
    {
      if (!in_repos) next
      repo = trim($2)
      path = trim($3)
      stack = trim($4)
      ref = trim($5)
      if (repo == "" || repo == "Slug" || repo == "Repo" || repo == "Repo ID" || repo ~ /^-+$/) next
      printf "%s|%s|%s|%s\n", repo, path, stack, ref
    }
  ' "$repos_file"
}

repo_row_for_id() {
  local repo_rows="$1" repo_id="$2"
  printf '%s\n' "$repo_rows" | awk -F'|' -v repo_id="$repo_id" '$1 == repo_id { print; exit }'
}

resolve_repo_path() {
  local repos_file="$1" repo_path="$2"
  if [[ "$repo_path" = /* ]]; then
    printf '%s\n' "$repo_path"
  else
    (
      cd "$(dirname "$repos_file")/.." 2>/dev/null || exit 1
      cd "$repo_path" 2>/dev/null || exit 1
      pwd
    )
  fi
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

detect_shell_name() {
  local shell_path="${SHELL:-}"
  shell_path="${shell_path##*/}"
  case "$shell_path" in
    zsh|bash|fish) printf '%s\n' "$shell_path" ;;
    *) printf '%s\n' "zsh" ;;
  esac
}

default_user_bin_dir() {
  if [[ -n "${XDG_BIN_HOME:-}" ]]; then
    printf '%s\n' "$XDG_BIN_HOME"
  elif [[ -d "$HOME/.local/bin" ]]; then
    printf '%s\n' "$HOME/.local/bin"
  elif [[ -d "$HOME/bin" ]]; then
    printf '%s\n' "$HOME/bin"
  else
    printf '%s\n' "$HOME/.local/bin"
  fi
}

shell_rc_file() {
  local shell_name="$1"
  case "$shell_name" in
    zsh) printf '%s\n' "$HOME/.zshrc" ;;
    bash)
      if [[ -f "$HOME/.bash_profile" ]]; then
        printf '%s\n' "$HOME/.bash_profile"
      else
        printf '%s\n' "$HOME/.bashrc"
      fi
      ;;
    fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    *) printf '%s\n' "$HOME/.profile" ;;
  esac
}

shell_path_snippet() {
  local shell_name="$1" bin_dir="$2"
  case "$shell_name" in
    fish) printf 'fish_add_path "%s"\n' "$bin_dir" ;;
    *) printf 'export PATH="%s:$PATH"\n' "$bin_dir" ;;
  esac
}

path_contains_dir() {
  local dir="$1" entry
  IFS=':' read -r -a entries <<< "${PATH:-}"
  for entry in "${entries[@]}"; do
    [[ "$entry" == "$dir" ]] && return 0
  done
  return 1
}

