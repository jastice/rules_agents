#!/usr/bin/env bash

set -euo pipefail

readonly REPO_RUNFILES_ROOT="${TEST_SRCDIR}/_main"
readonly DOCTOR_BIN="${REPO_RUNFILES_ROOT}/examples/codex_dev_doctor"

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
  local workspace_dir="$1"
  shift
  export RUNFILES_DIR="${TEST_SRCDIR}"
  export BUILD_WORKSPACE_DIRECTORY="${workspace_dir}"
  "$DOCTOR_BIN" "$@"
}

main() {
  local workspace_dir="${TEST_TMPDIR}/doctor-workspace"
  local output_file="${TEST_TMPDIR}/doctor.out"
  make_workspace "$workspace_dir"

  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_doctor "$workspace_dir"
  ) >"$output_file"

  grep -q "profile: repo_dev_profile" "$output_file" || fail "doctor omitted profile"
  grep -q "agent_binary: found" "$output_file" || fail "doctor did not find binary"
  grep -q "OPENAI_API_KEY: set" "$output_file" || fail "doctor did not report credential"
  grep -q "status=ok" "$output_file" || fail "doctor did not validate skill bundle"

  if (
    unset OPENAI_API_KEY
    export CODEX_BIN=/usr/bin/true
    run_doctor "$workspace_dir"
  ) >"$output_file" 2>&1; then
    fail "doctor succeeded without required credential"
  fi
  grep -q "OPENAI_API_KEY: missing" "$output_file" || fail "doctor missing-credential output incorrect"

  if (
    unset CODEX_BIN
    export OPENAI_API_KEY=test
    export PATH=/usr/bin:/bin
    run_doctor "$workspace_dir"
  ) >"$output_file" 2>&1; then
    fail "doctor succeeded without agent binary"
  fi
  grep -q "agent_binary: missing" "$output_file" || fail "doctor missing-binary output incorrect"
}

main "$@"
