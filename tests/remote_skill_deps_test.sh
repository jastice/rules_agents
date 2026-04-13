#!/usr/bin/env bash

set -euo pipefail

self="${BASH_SOURCE[0]}"
while [[ -L "$self" ]]; do
  link="$(readlink "$self")"
  if [[ "$link" = /* ]]; then
    self="$link"
  else
    self="$(dirname "$self")/$link"
  fi
done

readonly SCRIPT_DIR="$(cd "$(dirname "$self")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REMOTE_ROOT_FIXTURE="${REPO_ROOT}/tests/fixtures/remote_repo_root"
readonly REMOTE_DIRS_FIXTURE="${REPO_ROOT}/tests/fixtures/remote_repo_dirs"
readonly REMOTE_ROOT_AND_CHILD_FIXTURE="${REPO_ROOT}/tests/fixtures/remote_repo_root_and_child"

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
  local root_and_child_archive="$4"

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
skill_deps.remote(
    name = "remote_root_and_child_skills",
    url = "file://${root_and_child_archive}",
)
use_repo(skill_deps, "remote_dir_skills", "remote_root_and_child_skills", "remote_root_skill")
EOF
}

write_build_file() {
  local workspace_dir="$1"

  cat > "${workspace_dir}/BUILD.bazel" <<'EOF'
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner", "agent_skill")

agent_skill(
    name = "local_skill",
    root = "local_skill",
    srcs = glob(["local_skill/**"], exclude_directories = 1),
)

agent_profile(
    name = "dev_profile",
    skills = [
        ":local_skill",
        "@remote_root_skill//:remote_root_skill",
        "@remote_dir_skills//:bazel_debug",
        "@remote_root_and_child_skills//:remote_root_and_child_skills",
        "@remote_root_and_child_skills//:child_skill",
        "@remote_dir_skills//:test_runner",
    ],
    credential_env = ["OPENAI_API_KEY"],
)

agent_runner(
    name = "dev",
    profile = ":dev_profile",
    runner = "codex",
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
  local root_and_child_archive="${tmp_root}/remote-root-and-child-skills.tar.gz"
  local manifest_path=
  local manifest_relpath=

  bazel_bin="$(resolve_bazel)"
  mkdir -p "$workspace_dir"
  write_local_skill "$workspace_dir"
  pack_archive "$REMOTE_ROOT_FIXTURE" "$root_archive"
  pack_archive "$REMOTE_DIRS_FIXTURE" "$dirs_archive"
  pack_archive "$REMOTE_ROOT_AND_CHILD_FIXTURE" "$root_and_child_archive"
  write_module_file "$workspace_dir" "$root_archive" "$dirs_archive" "$root_and_child_archive"
  write_build_file "$workspace_dir"

  (
    cd "$workspace_dir"
    "$bazel_bin" build //:dev_manifest
  )

  manifest_relpath="$(
    cd "$workspace_dir" &&
      "$bazel_bin" cquery --output=files //:dev_manifest
  )"
  manifest_path="${workspace_dir}/${manifest_relpath}"
  [[ -f "$manifest_path" ]] || fail "expected manifest missing: $manifest_path"
  grep -q '"logical_name": "remote_root_skill"' "$manifest_path" || \
    fail "manifest omitted archive-root remote skill"
  grep -q '"logical_name": "bazel_debug"' "$manifest_path" || \
    fail "manifest omitted synthesized bazel_debug skill"
  grep -q '"logical_name": "remote_root_and_child_skills"' "$manifest_path" || \
    fail "manifest omitted root-and-child archive root skill"
  grep -q '"logical_name": "child_skill"' "$manifest_path" || \
    fail "manifest omitted root-and-child archive child skill"
  grep -q '"logical_name": "test_runner"' "$manifest_path" || \
    fail "manifest omitted synthesized test_runner skill"
  if grep -q '"logical_name": "nested_child_skill"' "$manifest_path"; then
    fail "manifest included nested child skill under an existing skill root"
  fi
}

main "$@"
