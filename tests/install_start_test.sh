#!/usr/bin/env bash

set -euo pipefail

readonly REPO_RUNFILES_ROOT="${TEST_SRCDIR}/_main"
readonly DOCTOR_BIN="${REPO_RUNFILES_ROOT}/examples/dev_profile_doctor"
readonly INSTALL_BIN="${REPO_RUNFILES_ROOT}/examples/dev_profile_install"
readonly START_BIN="${REPO_RUNFILES_ROOT}/examples/dev_profile"
readonly FAKE_CODEX_SRC="${REPO_RUNFILES_ROOT}/examples/fake_codex.sh"
readonly MANAGED_DIR="__bazel_agent_env__dev_profile__main__examples__repo_helper"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_workspace() {
  local workspace_dir="$1"
  mkdir -p "$workspace_dir"
  : > "${workspace_dir}/MODULE.bazel"
}

run_with_workspace() {
  local workspace_dir="$1"
  shift
  export RUNFILES_DIR="${TEST_SRCDIR}"
  export BUILD_WORKSPACE_DIRECTORY="${workspace_dir}"
  "$@"
}

assert_file() {
  local file_path="$1"
  [[ -f "$file_path" ]] || fail "expected file missing: $file_path"
}

main() {
  local install_workspace="${TEST_TMPDIR}/install-workspace"
  local conflict_workspace="${TEST_TMPDIR}/conflict-workspace"
  local start_workspace="${TEST_TMPDIR}/start-workspace"
  local output_file="${TEST_TMPDIR}/start.out"
  local fake_codex_bin="${TEST_TMPDIR}/fake_codex.sh"

  cp "$FAKE_CODEX_SRC" "$fake_codex_bin"
  chmod +x "$fake_codex_bin"

  make_workspace "$install_workspace"
  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$INSTALL_BIN"
  )

  assert_file "${install_workspace}/.agents/skills/${MANAGED_DIR}/SKILL.md"
  assert_file "${install_workspace}/.agents/skills/${MANAGED_DIR}/.bazel_agent_env_owner.json"
  assert_file "${install_workspace}/.agents/skills/.bazel_agent_env_dev_profile.json"

  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$INSTALL_BIN"
  ) >/dev/null

  local stale_dir="${install_workspace}/.agents/skills/__bazel_agent_env__dev_profile__stale_case"
  mkdir -p "$stale_dir"
  cat > "${stale_dir}/SKILL.md" <<'EOF'
# stale
EOF
  cat > "${stale_dir}/.bazel_agent_env_owner.json" <<'EOF'
{
  "agent": "codex",
  "managed_dir_name": "__bazel_agent_env__dev_profile__stale_case",
  "profile_name": "dev_profile",
  "tool": "rules_agents",
  "tool_version": "0.1.0"
}
EOF
  cat > "${install_workspace}/.agents/skills/.bazel_agent_env_dev_profile.json" <<EOF
{
  "agent": "codex",
  "installed_managed_dirs": [
    "${MANAGED_DIR}",
    "__bazel_agent_env__dev_profile__stale_case"
  ],
  "install_timestamp": "2025-01-01T00:00:00+00:00",
  "profile_name": "dev_profile",
  "tool_version": "0.1.0"
}
EOF
  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$INSTALL_BIN"
  ) >/dev/null
  [[ ! -e "$stale_dir" ]] || fail "stale managed directory was not removed"

  make_workspace "$conflict_workspace"
  mkdir -p "${conflict_workspace}/.agents/skills/${MANAGED_DIR}"
  if (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$conflict_workspace" "$INSTALL_BIN"
  ) >/dev/null 2>"${TEST_TMPDIR}/conflict.err"; then
    fail "install succeeded despite unmanaged conflict"
  fi
  grep -q "refusing to overwrite unmanaged directory" "${TEST_TMPDIR}/conflict.err" || \
    fail "install conflict error text incorrect"

  make_workspace "$start_workspace"
  (
    export OPENAI_API_KEY=test
    export FAKE_CODEX_OUT="$output_file"
    export CODEX_BIN="$fake_codex_bin"
    run_with_workspace "$start_workspace" "$START_BIN" -- --alpha beta
  )

  assert_file "$output_file"
  grep -q "cwd=${start_workspace}" "$output_file" || fail "start used wrong cwd"
  grep -q "openai_api_key=test" "$output_file" || fail "start did not forward env"
  grep -q "argv=--alpha beta " "$output_file" || fail "start did not forward args"
  assert_file "${start_workspace}/.agents/skills/${MANAGED_DIR}/SKILL.md"
}

main "$@"
