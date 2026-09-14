# Serialize cooperating CLI writers on macOS and Linux (no flock dependency).
# A killed process may leave the directory: time out with recovery guidance,
# never steal a possibly live lock or erase a pending recovery journal.
with_state_lock() (
  if [[ ! -d ./.platform ]]; then "$@"; exit $?; fi
  local lock="./.platform/.state.lock" attempts=0
  while ! mkdir "$lock" 2>/dev/null; do
    attempts=$((attempts + 1))
    if (( attempts >= 200 )); then
      warn "Project state is locked. Retry after the other command finishes. If it crashed, inspect .platform/.transaction.* backups, then remove the empty .platform/.state.lock directory."
      exit 1
    fi
    sleep 0.1
  done
  trap 'rmdir "$lock" 2>/dev/null || true' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
)

# Run a short mutation with a recoverable snapshot of its exact output paths.
# CLI writers must hold with_state_lock. Hard termination leaves the journal;
# ordinary errors/signals restore snapshots before releasing the lock.
state_transaction() (
  local callback="$1"; shift
  local -a targets=("$@")
  local txn index=0 file
  txn="$(mktemp -d ./.platform/.transaction.XXXXXX)" || exit 1
  printf '%s\n' "${targets[@]}" > "$txn/targets" || exit 1
  for file in "${targets[@]}"; do
    if [[ -L "$file" || ( -e "$file" && ! -f "$file" ) ]]; then
      warn "Refusing non-regular state file: $file (journal: $txn)"; exit 1
    fi
    if [[ -f "$file" ]]; then cp -p "$file" "$txn/$index" || exit 1; fi
    index=$((index + 1))
  done
  _state_finish() {
    local status="$1" restored=1 index=0 file restore
    trap - EXIT
    if (( status != 0 )); then
      for ((index=0; index<${#targets[@]}; index++)); do
        file="${targets[$index]}"
        if [[ -f "$txn/$index" ]]; then
          restore="$(mktemp "$(dirname "$file")/.restore.XXXXXX")" || { restored=0; continue; }
          cp -p "$txn/$index" "$restore" && mv "$restore" "$file" || { rm -f "$restore"; restored=0; }
        else
          rm -f "$file" || restored=0
        fi
      done
    fi
    if (( restored )); then
      for ((index=0; index<${#targets[@]}; index++)); do rm -f "$txn/$index"; done
      rm -f "$txn/targets"
      rmdir "$txn"
    else
      warn "State recovery needs attention. Original files retained in $txn (see targets)."
    fi
    return "$status"
  }
  trap '_state_finish "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$callback"
)
