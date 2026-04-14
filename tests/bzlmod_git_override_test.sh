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

main() {
  local bazel_bin=
  local tmp_root="${TEST_TMPDIR:-$(mktemp -d /tmp/rules_agents_git_override_test.XXXXXX)}"
  local workspace_dir="${tmp_root}/git-override-workspace"
  local repo_skills_archive="${tmp_root}/rules-agents-skills.tar.gz"
  local archive_root="${tmp_root}/archive-root"
  local output_file="${tmp_root}/doctor.out"

  bazel_bin="$(resolve_bazel)"
  mkdir -p "${workspace_dir}"
  mkdir -p "${archive_root}/rules_agents-main"
  cp -R "${REPO_ROOT}/skills" "${archive_root}/rules_agents-main/skills"
  tar -czf "$repo_skills_archive" -C "${archive_root}" rules_agents-main

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "git_override_test")

bazel_dep(name = "rules_agents", version = "0.1.0")
git_override(
    module_name = "rules_agents",
    remote = "file://${REPO_ROOT}",
    branch = "main",
)

skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")
skill_deps.registries()
skill_deps.remote(
    name = "rules_agents_skills",
    url = "file://${repo_skills_archive}",
    skill_path_prefix = "skills",
)
use_repo(skill_deps, "rules_agents_registry_index", "rules_agents_skills")
EOF

  cat > "${workspace_dir}/BUILD.bazel" <<'EOF'
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner")

agent_profile(
    name = "dev_profile",
    skills = ["@rules_agents_skills//:rules_agents"],
)

agent_runner(
    name = "dev",
    profile = ":dev_profile",
    runner = "codex",
)
EOF

  (
    cd "$workspace_dir"
    "$bazel_bin" build //:dev_manifest
    "$bazel_bin" run @rules_agents_registry_index//:list_skills -- --registry=rules_agents_skills
    export CODEX_BIN=/usr/bin/true
    "$bazel_bin" run //:dev_doctor
  ) > "$output_file"

  grep -q "@rules_agents_skills//:rules_agents" "$output_file" || fail "registry listing omitted rules_agents"
  grep -q "profile: dev_profile" "$output_file" || fail "doctor omitted profile"
  grep -q "agent_binary: found" "$output_file" || fail "doctor did not resolve codex binary"
}

main "$@"
