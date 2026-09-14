#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for test_file in "$ROOT"/unit/*_test.sh; do
  printf 'RUN SUITE: %s\n' "$(basename "$test_file")"
  if ! bash "$test_file"; then
    printf 'FAIL: %s\n' "$(basename "$test_file")" >&2
    exit 1
  fi
done

printf 'PASS: unit\n'
