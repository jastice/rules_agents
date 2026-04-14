#!/usr/bin/env bash

set -euo pipefail

out="${FAKE_CODEX_OUT:?FAKE_CODEX_OUT must be set}"

{
  printf 'cwd=%s\n' "$PWD"
  printf 'openai_api_key=%s\n' "${OPENAI_API_KEY-}"
  printf 'argv='
  for arg in "$@"; do
    printf '%s ' "$arg"
  done
  printf '\n'
} >"$out"
