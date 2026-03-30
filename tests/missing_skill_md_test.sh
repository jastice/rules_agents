#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

resolve_bazel() {
  if command -v bazel >/dev/null 2>&1; then
    command -v bazel
    return
  fi

  for candidate in /opt/homebrew/bin/bazel /usr/local/bin/bazel /usr/bin/bazel; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

  fail "unable to locate bazel for missing-skill integration test"
}

main() {
  local bazel_bin=
  local tmp_root="${TEST_TMPDIR:-$(mktemp -d /tmp/rules_agents_missing_skill.XXXXXX)}"
  local output_file="${tmp_root}/missing-skill.out"

  bazel_bin="$(resolve_bazel)"
  if "$bazel_bin" build //tests/invalid:missing_skill >"$output_file" 2>&1; then
    fail "malformed skill unexpectedly built successfully"
  fi

  if ! grep -q "is missing .*SKILL.md" "$output_file"; then
    cat "$output_file" >&2
    fail "missing-skill failure text was not clear"
  fi
}

main "$@"
