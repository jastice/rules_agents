#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REMOTE_ROOT_FIXTURE="${REPO_ROOT}/tests/fixtures/remote_repo_root"
readonly REMOTE_DIRS_FIXTURE="${REPO_ROOT}/tests/fixtures/remote_repo_dirs"

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

  fail "unable to locate bazel for nested integration test"
}

write_local_skill() {
  local workspace_dir="$1"
  mkdir -p "${workspace_dir}/local_skill"
  cat > "${workspace_dir}/local_skill/SKILL.md" <<'EOF'
# Local Skill
EOF
}

write_module_file() {
  local workspace_dir="$1"
  local root_archive="$2"
  local dirs_archive="$3"

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "remote_skill_test")

bazel_dep(name = "rules_agents", version = "0.1.0")
local_path_override(
    module_name = "rules_agents",
    path = "${REPO_ROOT}",
)

skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")
skill_deps.remote(
    name = "remote_root_skill",
    url = "file://${root_archive}",
)
skill_deps.remote(
    name = "remote_dir_skills",
    url = "file://${dirs_archive}",
)
use_repo(skill_deps, "remote_dir_skills", "remote_root_skill")
EOF
}

write_build_file() {
  local workspace_dir="$1"

  cat > "${workspace_dir}/BUILD.bazel" <<'EOF'
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_skill")

agent_skill(
    name = "local_skill",
    root = "local_skill",
    srcs = glob(["local_skill/**"], exclude_directories = 1),
)

agent_profile(
    name = "dev",
    agent = "codex",
    skills = [
        ":local_skill",
        "@remote_root_skill//:remote_root_skill",
        "@remote_dir_skills//:bazel_debug",
        "@remote_dir_skills//:test_runner",
    ],
    credential_env = ["OPENAI_API_KEY"],
)
EOF
}

pack_archive() {
  local source_dir="$1"
  local output_path="$2"
  tar -czf "$output_path" -C "$source_dir" .
}

main() {
  local bazel_bin=
  local tmp_root="${TEST_TMPDIR:-$(mktemp -d /tmp/rules_agents_remote_test.XXXXXX)}"
  local workspace_dir="${tmp_root}/remote-skill-workspace"
  local root_archive="${tmp_root}/remote-root-skill.tar.gz"
  local dirs_archive="${tmp_root}/remote-dir-skills.tar.gz"
  local manifest_path=

  bazel_bin="$(resolve_bazel)"
  mkdir -p "$workspace_dir"
  write_local_skill "$workspace_dir"
  pack_archive "$REMOTE_ROOT_FIXTURE" "$root_archive"
  pack_archive "$REMOTE_DIRS_FIXTURE" "$dirs_archive"
  write_module_file "$workspace_dir" "$root_archive" "$dirs_archive"
  write_build_file "$workspace_dir"

  (
    cd "$workspace_dir"
    "$bazel_bin" build //:dev
  )

  manifest_path="${workspace_dir}/bazel-bin/dev.json"
  [[ -f "$manifest_path" ]] || fail "expected manifest missing: $manifest_path"
  grep -q '"logical_name": "remote_root_skill"' "$manifest_path" || \
    fail "manifest omitted archive-root remote skill"
  grep -q '"logical_name": "bazel_debug"' "$manifest_path" || \
    fail "manifest omitted synthesized bazel_debug skill"
  grep -q '"logical_name": "test_runner"' "$manifest_path" || \
    fail "manifest omitted synthesized test_runner skill"
}

main "$@"
