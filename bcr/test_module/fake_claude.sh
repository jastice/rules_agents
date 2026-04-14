#!/usr/bin/env bash

set -euo pipefail

out="${FAKE_CLAUDE_OUT:?FAKE_CLAUDE_OUT must be set}"

{
  printf 'cwd=%s\n' "$PWD"
  printf 'anthropic_api_key=%s\n' "${ANTHROPIC_API_KEY-}"
  printf 'argv='
  for arg in "$@"; do
    printf '%s ' "$arg"
  done
  printf '\n'
} >"$out"
