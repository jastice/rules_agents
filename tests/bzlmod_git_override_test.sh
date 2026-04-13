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
  local output_file="${tmp_root}/doctor.out"

  bazel_bin="$(resolve_bazel)"
  mkdir -p "${workspace_dir}/skills/repo_helper" "${workspace_dir}/tools/rules_agents"

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "git_override_test")

bazel_dep(name = "rules_agents", version = "0.1.0")
git_override(
    module_name = "rules_agents",
    remote = "file://${REPO_ROOT}",
    branch = "main",
)

skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")
skill_deps.registries(
    config = "//tools/rules_agents:registries.json",
    mode = "replace",
)
use_repo(skill_deps, "rules_agents_registry_index")
EOF

  cat > "${workspace_dir}/BUILD.bazel" <<'EOF'
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner", "agent_skill")

agent_skill(
    name = "repo_helper",
    root = "skills/repo_helper",
    srcs = glob(["skills/repo_helper/**"], exclude_directories = 1),
)

agent_profile(
    name = "repo_dev_profile",
    skills = [":repo_helper"],
)

agent_runner(
    name = "codex_dev",
    profile = ":repo_dev_profile",
    runner = "codex",
)
EOF

  cat > "${workspace_dir}/skills/repo_helper/SKILL.md" <<'EOF'
# Repo Helper
EOF

  cat > "${workspace_dir}/tools/BUILD.bazel" <<'EOF'
package(default_visibility = ["//visibility:public"])
EOF

  cat > "${workspace_dir}/tools/rules_agents/BUILD.bazel" <<'EOF'
package(default_visibility = ["//visibility:public"])
exports_files(["registries.json"])
EOF

  cat > "${workspace_dir}/tools/rules_agents/registries.json" <<'EOF'
{
  "version": 1,
  "registries": []
}
EOF

  (
    cd "$workspace_dir"
    "$bazel_bin" build //:codex_dev_manifest
    export CODEX_BIN=/usr/bin/true
    "$bazel_bin" run //:codex_dev_doctor
  ) > "$output_file"

  grep -q "profile: repo_dev_profile" "$output_file" || fail "doctor omitted profile"
  grep -q "agent_binary: found" "$output_file" || fail "doctor did not resolve codex binary"
}

main "$@"
