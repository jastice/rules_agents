#!/usr/bin/env bash

set -euo pipefail

readonly REPO_RUNFILES_ROOT="${TEST_SRCDIR}/_main"
readonly DOCTOR_BIN="${REPO_RUNFILES_ROOT}/examples/codex_dev_doctor"
readonly INSTALL_BIN="${REPO_RUNFILES_ROOT}/examples/codex_dev_setup"
readonly EXTRA_INSTALL_BIN="${REPO_RUNFILES_ROOT}/examples/codex_dev_extra_setup"
readonly START_BIN="${REPO_RUNFILES_ROOT}/examples/codex_dev"
readonly CLAUDE_INSTALL_BIN="${REPO_RUNFILES_ROOT}/examples/claude_dev_setup"
readonly CLAUDE_START_BIN="${REPO_RUNFILES_ROOT}/examples/claude_dev"
readonly CLAUDE_MANAGED_DIR="__bazel_agent_env__claude_dev_profile__main__examples__repo_helper"
readonly EXTRA_HELLO_WORLD_DIR="__bazel_agent_env__repo_dev_profile_extra__main__examples__hello_world"
readonly EXTRA_MANAGED_DIR="__bazel_agent_env__repo_dev_profile_extra__main__examples__repo_helper"
readonly FAKE_CODEX_SRC="${REPO_RUNFILES_ROOT}/examples/fake_codex.sh"
readonly FAKE_CLAUDE_SRC="${REPO_RUNFILES_ROOT}/examples/fake_claude.sh"
readonly MANAGED_DIR="__bazel_agent_env__repo_dev_profile__main__examples__repo_helper"

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
  local claude_workspace="${TEST_TMPDIR}/claude-workspace"
  local start_workspace="${TEST_TMPDIR}/start-workspace"
  local claude_start_workspace="${TEST_TMPDIR}/claude-start-workspace"
  local output_file="${TEST_TMPDIR}/start.out"
  local claude_output_file="${TEST_TMPDIR}/claude-start.out"
  local fake_codex_bin="${TEST_TMPDIR}/fake_codex.sh"
  local fake_claude_bin="${TEST_TMPDIR}/fake_claude.sh"
  local path_shadow_dir="${TEST_TMPDIR}/path-shadow"
  local path_shadow_out="${TEST_TMPDIR}/path-shadow.out"

  cp "$FAKE_CODEX_SRC" "$fake_codex_bin"
  chmod +x "$fake_codex_bin"
  cp "$FAKE_CLAUDE_SRC" "$fake_claude_bin"
  chmod +x "$fake_claude_bin"

  make_workspace "$install_workspace"
  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$INSTALL_BIN"
  )

  assert_file "${install_workspace}/.agents/skills/${MANAGED_DIR}/SKILL.md"
  assert_file "${install_workspace}/.agents/skills/${MANAGED_DIR}/.bazel_agent_env_owner.json"
  assert_file "${install_workspace}/.agents/skills/.bazel_agent_env_repo_dev_profile.json"

  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$EXTRA_INSTALL_BIN"
  ) >/dev/null

  assert_file "${install_workspace}/.agents/skills/${EXTRA_MANAGED_DIR}/SKILL.md"
  assert_file "${install_workspace}/.agents/skills/${EXTRA_HELLO_WORLD_DIR}/SKILL.md"
  [[ ! -e "${install_workspace}/.agents/skills/${MANAGED_DIR}" ]] || \
    fail "previous profile skill remained after switching profiles"

  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$INSTALL_BIN"
  ) >/dev/null

  assert_file "${install_workspace}/.agents/skills/${MANAGED_DIR}/SKILL.md"
  [[ ! -e "${install_workspace}/.agents/skills/${EXTRA_MANAGED_DIR}" ]] || \
    fail "extra profile repo_helper remained after switching back"
  [[ ! -e "${install_workspace}/.agents/skills/${EXTRA_HELLO_WORLD_DIR}" ]] || \
    fail "extra profile hello_world remained after switching back"

  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$INSTALL_BIN"
  ) >/dev/null

  local stale_dir="${install_workspace}/.agents/skills/__bazel_agent_env__repo_dev_profile__stale_case"
  mkdir -p "$stale_dir"
  cat > "${stale_dir}/SKILL.md" <<'EOF'
# stale
EOF
  cat > "${stale_dir}/.bazel_agent_env_owner.json" <<'EOF'
{
  "agent": "codex",
  "managed_dir_name": "__bazel_agent_env__repo_dev_profile__stale_case",
  "profile_name": "repo_dev_profile",
  "tool": "rules_agents",
  "tool_version": "0.1.0"
}
EOF
  cat > "${install_workspace}/.agents/skills/.bazel_agent_env_repo_dev_profile.json" <<EOF
{
  "agent": "codex",
  "installed_managed_dirs": [
    "${MANAGED_DIR}",
    "__bazel_agent_env__repo_dev_profile__stale_case"
  ],
  "install_timestamp": "2025-01-01T00:00:00+00:00",
  "profile_name": "repo_dev_profile",
  "tool_version": "0.1.0"
}
EOF
  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$INSTALL_BIN"
  ) >/dev/null
  [[ ! -e "$stale_dir" ]] || fail "stale managed directory was not removed"

  local prefix_only_dir="${install_workspace}/.agents/skills/__bazel_agent_env__repo_dev_profile__prefix_only"
  mkdir -p "$prefix_only_dir"
  cat > "${prefix_only_dir}/SKILL.md" <<'EOF'
# unmanaged prefix
EOF
  cat > "${prefix_only_dir}/.bazel_agent_env_owner.json" <<'EOF'
{
  "agent": "codex",
  "managed_dir_name": "__bazel_agent_env__repo_dev_profile__different_name",
  "profile_name": "repo_dev_profile",
  "tool": "rules_agents",
  "tool_version": "0.1.0"
}
EOF
  cat > "${install_workspace}/.agents/skills/.bazel_agent_env_repo_dev_profile.json" <<EOF
{
  "agent": "codex",
  "installed_managed_dirs": [
    "${MANAGED_DIR}",
    "__bazel_agent_env__repo_dev_profile__prefix_only"
  ],
  "install_timestamp": "2025-01-01T00:00:00+00:00",
  "profile_name": "repo_dev_profile",
  "tool_version": "0.1.0"
}
EOF
  (
    export OPENAI_API_KEY=test
    export CODEX_BIN=/usr/bin/true
    run_with_workspace "$install_workspace" "$INSTALL_BIN"
  ) >/dev/null
  [[ -e "$prefix_only_dir" ]] || fail "managed-prefix directory without a valid marker was deleted"

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

  make_workspace "$claude_workspace"
  (
    export ANTHROPIC_API_KEY=test
    export CLAUDE_CODE_BIN=/usr/bin/true
    run_with_workspace "$claude_workspace" "$CLAUDE_INSTALL_BIN"
  )

  assert_file "${claude_workspace}/.claude/skills/${CLAUDE_MANAGED_DIR}/SKILL.md"
  assert_file "${claude_workspace}/.claude/skills/${CLAUDE_MANAGED_DIR}/.bazel_agent_env_owner.json"
  assert_file "${claude_workspace}/.claude/skills/.bazel_agent_env_claude_dev_profile.json"

  make_workspace "$start_workspace"
  mkdir -p "$path_shadow_dir"
  cat > "${path_shadow_dir}/codex" <<EOF
#!/usr/bin/env bash
echo path-shadow > "${path_shadow_out}"
EOF
  chmod +x "${path_shadow_dir}/codex"
  (
    export OPENAI_API_KEY=test
    export FAKE_CODEX_OUT="$output_file"
    export CODEX_BIN="$fake_codex_bin"
    export PATH="${path_shadow_dir}:/usr/bin:/bin"
    run_with_workspace "$start_workspace" "$START_BIN" -- --alpha beta
  )

  assert_file "$output_file"
  grep -q "cwd=${start_workspace}" "$output_file" || fail "start used wrong cwd"
  grep -q "openai_api_key=test" "$output_file" || fail "start did not forward env"
  grep -q "argv=--alpha beta " "$output_file" || fail "start did not forward args"
  [[ ! -e "$path_shadow_out" ]] || fail "PATH candidate was used instead of CODEX_BIN override"
  assert_file "${start_workspace}/.agents/skills/${MANAGED_DIR}/SKILL.md"

  make_workspace "$claude_start_workspace"
  (
    export ANTHROPIC_API_KEY=test
    export FAKE_CLAUDE_OUT="$claude_output_file"
    export CLAUDE_CODE_BIN="$fake_claude_bin"
    run_with_workspace "$claude_start_workspace" "$CLAUDE_START_BIN" -- --omega
  )

  assert_file "$claude_output_file"
  grep -q "cwd=${claude_start_workspace}" "$claude_output_file" || fail "claude start used wrong cwd"
  grep -q "anthropic_api_key=test" "$claude_output_file" || fail "claude start did not forward env"
  grep -q "argv=--omega " "$claude_output_file" || fail "claude start did not forward args"
  assert_file "${claude_start_workspace}/.claude/skills/${CLAUDE_MANAGED_DIR}/SKILL.md"
}

main "$@"
