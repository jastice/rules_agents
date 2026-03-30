#!/usr/bin/env bash

set -euo pipefail

out_file="${FAKE_CODEX_OUT:?}"
{
  echo "cwd=$(pwd)"
  echo "openai_api_key=${OPENAI_API_KEY:-}"
  printf 'argv='
  printf '%s ' "$@"
  printf '\n'
} >"$out_file"
