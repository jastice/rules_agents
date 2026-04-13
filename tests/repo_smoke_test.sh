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
readonly REGISTRY_FIXTURE="${REPO_ROOT}/tests/fixtures/registry_repo"
readonly REGISTRY_ALT_FIXTURE="${REPO_ROOT}/tests/fixtures/registry_repo_alt"
readonly FAKE_CODEX_SRC="${REPO_ROOT}/examples/fake_codex.sh"
readonly FAKE_CLAUDE_SRC="${REPO_ROOT}/examples/fake_claude.sh"

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

  fail "unable to locate bazel for smoke test"
}

pack_archive() {
  local source_dir="$1"
  local output_path="$2"
  tar -czf "$output_path" -C "$source_dir" .
}

main() {
  local bazel_bin=
  local tmp_root="${TEST_TMPDIR:-$(mktemp -d /tmp/rules_agents_smoke_test.XXXXXX)}"
  local workspace_dir="${tmp_root}/consumer"
  local codex_archive="${tmp_root}/codex-skills.tar.gz"
  local claude_archive="${tmp_root}/claude-skills.tar.gz"
  local codex_out="${tmp_root}/codex.out"
  local claude_out="${tmp_root}/claude.out"
  local fake_codex_bin="${tmp_root}/fake_codex.sh"
  local fake_claude_bin="${tmp_root}/fake_claude.sh"
  local list_output="${tmp_root}/list.out"

  bazel_bin="$(resolve_bazel)"
  mkdir -p "${workspace_dir}/tools/rules_agents" "${workspace_dir}/skills/repo_helper"
  pack_archive "$REGISTRY_FIXTURE" "$codex_archive"
  pack_archive "$REGISTRY_ALT_FIXTURE" "$claude_archive"

  cp "$FAKE_CODEX_SRC" "$fake_codex_bin"
  chmod +x "$fake_codex_bin"
  cp "$FAKE_CLAUDE_SRC" "$fake_claude_bin"
  chmod +x "$fake_claude_bin"

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "rules_agents_smoke")

bazel_dep(name = "rules_agents", version = "0.1.0")
local_path_override(
    module_name = "rules_agents",
    path = "${REPO_ROOT}",
)

skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")
skill_deps.registries(
    config = "//tools/rules_agents:registries.json",
    mode = "replace",
)
skill_deps.remote(
    name = "codex_registry",
    url = "file://${codex_archive}",
)
skill_deps.remote(
    name = "claude_registry",
    url = "file://${claude_archive}",
)
use_repo(skill_deps, "claude_registry", "codex_registry", "rules_agents_registry_index")
EOF

  cat > "${workspace_dir}/BUILD.bazel" <<'EOF'
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner", "agent_skill")

agent_skill(
    name = "repo_helper",
    root = "skills/repo_helper",
    srcs = glob(["skills/repo_helper/**"], exclude_directories = 1),
)

agent_profile(
    name = "codex_profile",
    skills = [
        ":repo_helper",
        "@codex_registry//:python",
    ],
)

agent_runner(
    name = "codex_dev",
    profile = ":codex_profile",
    runner = "codex",
)

agent_profile(
    name = "claude_profile",
    skills = [
        ":repo_helper",
        "@claude_registry//:go_helper",
    ],
    credential_env = ["ANTHROPIC_API_KEY"],
)

agent_runner(
    name = "claude_dev",
    profile = ":claude_profile",
    runner = "claude_code",
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

  cat > "${workspace_dir}/tools/rules_agents/registries.json" <<EOF
{
  "version": 1,
  "registries": [
    {
      "id": "codex_registry",
      "display_name": "Codex Registry",
      "homepage": "https://example.com/codex",
      "repo_url": "https://github.com/example/codex-registry",
      "archive_url": "file://${codex_archive}",
      "agents": ["codex"],
      "description": "Fixture Codex registry."
    },
    {
      "id": "claude_registry",
      "display_name": "Claude Registry",
      "homepage": "https://example.com/claude",
      "repo_url": "https://github.com/example/claude-registry",
      "archive_url": "file://${claude_archive}",
      "agents": ["claude_code"],
      "description": "Fixture Claude registry."
    }
  ]
}
EOF

  (
    cd "$workspace_dir"
    "$bazel_bin" run @rules_agents_registry_index//:list_skills
  ) > "$list_output"

  grep -q "Registry: codex_registry" "$list_output" || fail "list_skills omitted codex registry"
  grep -q "Registry: claude_registry" "$list_output" || fail "list_skills omitted claude registry"
  grep -q '@codex_registry//:python' "$list_output" || fail "list_skills omitted codex target label"
  grep -q '@claude_registry//:go_helper' "$list_output" || fail "list_skills omitted claude target label"

  (
    cd "$workspace_dir"
    export CODEX_BIN="$fake_codex_bin"
    export FAKE_CODEX_OUT="$codex_out"
    "$bazel_bin" run //:codex_dev_doctor >/dev/null
    "$bazel_bin" run //:codex_dev -- --smoke codex
  )

  grep -q "cwd=${workspace_dir}" "$codex_out" || fail "codex runner used wrong cwd"
  grep -q "openai_api_key=$" "$codex_out" || fail "codex runner unexpectedly required OPENAI_API_KEY"
  grep -q "argv=--smoke codex " "$codex_out" || fail "codex runner did not forward args"
  [[ -f "${workspace_dir}/.agents/skills/__bazel_agent_env__codex_profile__main__repo_helper/SKILL.md" ]] || \
    fail "codex install did not materialize local skill"
  [[ "$(find "${workspace_dir}/.agents/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')" == "2" ]] || \
    fail "codex install did not materialize both declared skills"

  (
    cd "$workspace_dir"
    export ANTHROPIC_API_KEY=test-anthropic
    export CLAUDE_CODE_BIN="$fake_claude_bin"
    export FAKE_CLAUDE_OUT="$claude_out"
    "$bazel_bin" run //:claude_dev_doctor >/dev/null
    "$bazel_bin" run //:claude_dev -- --smoke claude
  )

  grep -q "cwd=${workspace_dir}" "$claude_out" || fail "claude runner used wrong cwd"
  grep -q "anthropic_api_key=test-anthropic" "$claude_out" || fail "claude runner did not forward env"
  grep -q "argv=--smoke claude " "$claude_out" || fail "claude runner did not forward args"
  [[ -f "${workspace_dir}/.claude/skills/__bazel_agent_env__claude_profile__main__repo_helper/SKILL.md" ]] || \
    fail "claude install did not materialize local skill"
  [[ "$(find "${workspace_dir}/.claude/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')" == "2" ]] || \
    fail "claude install did not materialize both declared skills"
}

main "$@"
