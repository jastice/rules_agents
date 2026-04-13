#!/usr/bin/env bash

set -euo pipefail

readonly REPO_RUNFILES_ROOT="${TEST_SRCDIR}/_main"
readonly DOCTOR_BIN="${REPO_RUNFILES_ROOT}/examples/codex_dev_doctor"
readonly CLAUDE_DOCTOR_BIN="${REPO_RUNFILES_ROOT}/examples/claude_dev_doctor"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_workspace() {
  local workspace_dir="$1"
  mkdir -p "${workspace_dir}"
  : > "${workspace_dir}/MODULE.bazel"
}

run_doctor() {
  local bin_path="$1"
  shift
  local workspace_dir="$1"
  shift
  export RUNFILES_DIR="${TEST_SRCDIR}"
  export BUILD_WORKSPACE_DIRECTORY="${workspace_dir}"
  "$bin_path" "$@"
}

main() {
  local workspace_dir="${TEST_TMPDIR}/doctor-workspace"
  local output_file="${TEST_TMPDIR}/doctor.out"
  make_workspace "$workspace_dir"

  (
    export CODEX_BIN=/usr/bin/true
    run_doctor "$DOCTOR_BIN" "$workspace_dir"
  ) >"$output_file"

  grep -q "profile: repo_dev_profile" "$output_file" || fail "doctor omitted profile"
  grep -q "agent_binary: found" "$output_file" || fail "doctor did not find binary"
  grep -q "status=ok" "$output_file" || fail "doctor did not validate skill bundle"
  if grep -q "OPENAI_API_KEY" "$output_file"; then
    fail "codex doctor unexpectedly required OPENAI_API_KEY"
  fi

  if (
    unset ANTHROPIC_API_KEY
    export CLAUDE_CODE_BIN=/usr/bin/true
    run_doctor "$CLAUDE_DOCTOR_BIN" "$workspace_dir"
  ) >"$output_file" 2>&1; then
    fail "claude doctor succeeded without required credential"
  fi
  grep -q "ANTHROPIC_API_KEY: missing" "$output_file" || fail "claude doctor missing-credential output incorrect"

  if (
    unset CODEX_BIN
    export PATH=/usr/bin:/bin
    run_doctor "$DOCTOR_BIN" "$workspace_dir"
  ) >"$output_file" 2>&1; then
    fail "doctor succeeded without agent binary"
  fi
  grep -q "agent_binary: missing" "$output_file" || fail "doctor missing-binary output incorrect"
}

main "$@"
