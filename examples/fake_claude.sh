#!/usr/bin/env bash

set -euo pipefail

out_file="${FAKE_CLAUDE_OUT:?}"
{
  echo "cwd=$(pwd)"
  echo "anthropic_api_key=${ANTHROPIC_API_KEY:-}"
  printf 'argv='
  printf '%s ' "$@"
  printf '\n'
} >"$out_file"
