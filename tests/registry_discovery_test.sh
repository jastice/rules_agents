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

pack_archive() {
  local source_dir="$1"
  local output_path="$2"
  tar -czf "$output_path" -C "$source_dir" .
}

# --- Test: explicit empty replace config disables built-in registries ---

test_empty_builtins() {
  local bazel_bin="$1"
  local tmp_root="$2"
  local workspace_dir="${tmp_root}/empty-builtins"
  local output_file="${tmp_root}/empty-builtins-output.txt"

  mkdir -p "${workspace_dir}/tools/rules_agents"

  cat > "${workspace_dir}/tools/rules_agents/registries.json" <<'EOF'
{
  "version": 1,
  "registries": []
}
EOF

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "registry_test_empty")

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
use_repo(skill_deps, "rules_agents_registry_index")
EOF

  : > "${workspace_dir}/BUILD.bazel"
  : > "${workspace_dir}/tools/BUILD.bazel"
  : > "${workspace_dir}/tools/rules_agents/BUILD.bazel"

  (
    cd "$workspace_dir"
    "$bazel_bin" run @rules_agents_registry_index//:list_skills
  ) > "$output_file" 2>"${output_file}.err"

  grep -q "No skills discovered" "$output_file" || \
    fail "empty builtins: expected no-skills message, got: $(cat "$output_file")"

  echo "PASS: test_empty_builtins"
}

# --- Test: repo-level registries with extend mode ---

test_extend_mode() {
  local bazel_bin="$1"
  local tmp_root="$2"
  local archive="${tmp_root}/registry-repo.tar.gz"
  local workspace_dir="${tmp_root}/extend-mode"
  local output_file="${tmp_root}/extend-output.txt"
  local json_file="${tmp_root}/extend-json.txt"

  pack_archive "$REGISTRY_FIXTURE" "$archive"
  mkdir -p "${workspace_dir}/tools/rules_agents"

  cat > "${workspace_dir}/tools/rules_agents/registries.json" <<EOF
{
  "version": 1,
  "registries": [
    {
      "id": "test_skills",
      "display_name": "Test Skills",
      "homepage": "https://github.com/test/skills",
      "repo_url": "https://github.com/test/skills",
      "archive_url": "file://${archive}",
      "agents": ["codex"],
      "description": "Test skill registry."
    }
  ]
}
EOF

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "registry_test_extend")

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
use_repo(skill_deps, "rules_agents_registry_index")
EOF

  cat > "${workspace_dir}/BUILD.bazel" <<'EOF'
EOF

  mkdir -p "${workspace_dir}/tools/rules_agents"
  : > "${workspace_dir}/tools/BUILD.bazel"
  : > "${workspace_dir}/tools/rules_agents/BUILD.bazel"

  # --- Human-readable output ---
  (
    cd "$workspace_dir"
    "$bazel_bin" run @rules_agents_registry_index//:list_skills
  ) > "$output_file" 2>"${output_file}.err"

  grep -q "Registry: test_skills" "$output_file" || \
    fail "extend: missing registry header"
  grep -q "python" "$output_file" || \
    fail "extend: missing python skill"
  grep -q "typescript" "$output_file" || \
    fail "extend: missing typescript skill"
  grep -q "Python coding workflow skill" "$output_file" || \
    fail "extend: missing python description from frontmatter"
  grep -q "TypeScript development skill" "$output_file" || \
    fail "extend: missing typescript description from frontmatter"
  grep -q '@test_skills//:python' "$output_file" || \
    fail "extend: missing python target label"
  grep -q 'skill_deps.remote(' "$output_file" || \
    fail "extend: missing Bazel snippet"

  # --- JSON output ---
  (
    cd "$workspace_dir"
    "$bazel_bin" run @rules_agents_registry_index//:list_skills -- --json
  ) > "$json_file" 2>"${json_file}.err"

  python3 -c "
import json, sys
data = json.load(open('$json_file'))
assert data['version'] == 1, 'wrong version'
assert len(data['registries']) == 1, 'expected 1 registry, got %d' % len(data['registries'])
reg = data['registries'][0]
assert reg['id'] == 'test_skills', 'wrong registry id'
names = sorted(s['skill_name'] for s in reg['skills'])
assert names == ['python', 'typescript'], 'unexpected skills: %s' % names
assert reg['skills'][0]['description'] or reg['skills'][1]['description'], 'missing descriptions'
" || fail "extend: JSON output validation failed"

  echo "PASS: test_extend_mode"
}

# --- Test: --agent filter ---

test_agent_filter() {
  local bazel_bin="$1"
  local tmp_root="$2"
  local archive="${tmp_root}/registry-repo.tar.gz"
  local alt_archive="${tmp_root}/registry-alt.tar.gz"
  local workspace_dir="${tmp_root}/agent-filter"
  local output_file="${tmp_root}/agent-filter-output.txt"

  pack_archive "$REGISTRY_FIXTURE" "$archive"
  pack_archive "$REGISTRY_ALT_FIXTURE" "$alt_archive"
  mkdir -p "${workspace_dir}/tools/rules_agents"

  cat > "${workspace_dir}/tools/rules_agents/registries.json" <<EOF
{
  "version": 1,
  "registries": [
    {
      "id": "codex_skills",
      "display_name": "Codex Skills",
      "homepage": "https://github.com/test/codex-skills",
      "repo_url": "https://github.com/test/codex-skills",
      "archive_url": "file://${archive}",
      "agents": ["codex"],
      "description": "Codex-only skills."
    },
    {
      "id": "claude_skills",
      "display_name": "Claude Skills",
      "homepage": "https://github.com/test/claude-skills",
      "repo_url": "https://github.com/test/claude-skills",
      "archive_url": "file://${alt_archive}",
      "agents": ["claude_code"],
      "description": "Claude-only skills."
    }
  ]
}
EOF

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "registry_test_agent_filter")

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
use_repo(skill_deps, "rules_agents_registry_index")
EOF

  : > "${workspace_dir}/BUILD.bazel"
  mkdir -p "${workspace_dir}/tools/rules_agents"
  : > "${workspace_dir}/tools/BUILD.bazel"
  : > "${workspace_dir}/tools/rules_agents/BUILD.bazel"

  # Filter for codex only
  (
    cd "$workspace_dir"
    "$bazel_bin" run @rules_agents_registry_index//:list_skills -- --agent=codex
  ) > "$output_file" 2>"${output_file}.err"

  grep -q "codex_skills" "$output_file" || \
    fail "agent filter: expected codex_skills registry"
  if grep -q "claude_skills" "$output_file"; then
    fail "agent filter: claude_skills should be excluded with --agent=codex"
  fi

  echo "PASS: test_agent_filter"
}

# --- Test: --skill filter ---

test_skill_filter() {
  local bazel_bin="$1"
  local tmp_root="$2"
  local archive="${tmp_root}/registry-repo.tar.gz"
  local workspace_dir="${tmp_root}/skill-filter"
  local output_file="${tmp_root}/skill-filter-output.txt"

  pack_archive "$REGISTRY_FIXTURE" "$archive"
  mkdir -p "${workspace_dir}/tools/rules_agents"

  cat > "${workspace_dir}/tools/rules_agents/registries.json" <<EOF
{
  "version": 1,
  "registries": [
    {
      "id": "test_skills",
      "display_name": "Test Skills",
      "homepage": "https://github.com/test/skills",
      "repo_url": "https://github.com/test/skills",
      "archive_url": "file://${archive}",
      "agents": ["codex"],
      "description": "Test skill registry."
    }
  ]
}
EOF

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "registry_test_skill_filter")

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
use_repo(skill_deps, "rules_agents_registry_index")
EOF

  : > "${workspace_dir}/BUILD.bazel"
  mkdir -p "${workspace_dir}/tools/rules_agents"
  : > "${workspace_dir}/tools/BUILD.bazel"
  : > "${workspace_dir}/tools/rules_agents/BUILD.bazel"

  (
    cd "$workspace_dir"
    "$bazel_bin" run @rules_agents_registry_index//:list_skills -- --skill=python
  ) > "$output_file" 2>"${output_file}.err"

  grep -q "python" "$output_file" || \
    fail "skill filter: expected python skill"
  if grep -q "typescript" "$output_file"; then
    fail "skill filter: typescript should be excluded with --skill=python"
  fi

  echo "PASS: test_skill_filter"
}

# --- Test: replace mode ---

test_replace_mode() {
  local bazel_bin="$1"
  local tmp_root="$2"
  local alt_archive="${tmp_root}/registry-alt.tar.gz"
  local workspace_dir="${tmp_root}/replace-mode"
  local output_file="${tmp_root}/replace-output.txt"

  pack_archive "$REGISTRY_ALT_FIXTURE" "$alt_archive"
  mkdir -p "${workspace_dir}/tools/rules_agents"

  cat > "${workspace_dir}/tools/rules_agents/registries.json" <<EOF
{
  "version": 1,
  "registries": [
    {
      "id": "alt_skills",
      "display_name": "Alt Skills",
      "homepage": "https://github.com/test/alt",
      "repo_url": "https://github.com/test/alt",
      "archive_url": "file://${alt_archive}",
      "agents": ["claude_code"],
      "description": "Replacement registry."
    }
  ]
}
EOF

  cat > "${workspace_dir}/MODULE.bazel" <<EOF
module(name = "registry_test_replace")

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
use_repo(skill_deps, "rules_agents_registry_index")
EOF

  : > "${workspace_dir}/BUILD.bazel"
  mkdir -p "${workspace_dir}/tools/rules_agents"
  : > "${workspace_dir}/tools/BUILD.bazel"
  : > "${workspace_dir}/tools/rules_agents/BUILD.bazel"

  (
    cd "$workspace_dir"
    "$bazel_bin" run @rules_agents_registry_index//:list_skills
  ) > "$output_file" 2>"${output_file}.err"

  grep -q "alt_skills" "$output_file" || \
    fail "replace: expected alt_skills registry"
  grep -q "go_helper" "$output_file" || \
    fail "replace: expected go_helper skill"
  grep -q "Go development assistant" "$output_file" || \
    fail "replace: expected go_helper description"

  echo "PASS: test_replace_mode"
}

# --- Main ---

main() {
  local bazel_bin
  local tmp_root="${TEST_TMPDIR:-$(mktemp -d /tmp/rules_agents_registry_test.XXXXXX)}"

  bazel_bin="$(resolve_bazel)"

  test_empty_builtins "$bazel_bin" "$tmp_root"
  test_extend_mode "$bazel_bin" "$tmp_root"
  test_agent_filter "$bazel_bin" "$tmp_root"
  test_skill_filter "$bazel_bin" "$tmp_root"
  test_replace_mode "$bazel_bin" "$tmp_root"

  echo ""
  echo "All registry discovery tests passed."
}

main "$@"
