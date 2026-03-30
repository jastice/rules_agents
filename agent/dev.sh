#!/usr/bin/env bash

set -euo pipefail

workspace_root="${BUILD_WORKSPACE_DIRECTORY:-$(pwd)}"

cat <<EOF
rules_agents bootstrap launcher

workspace: ${workspace_root}
status: Bazel repo initialized

Next implementation targets:
- add public Starlark rules in rules_agents/defs.bzl
- implement skill packaging and validation
- implement profile launchers for codex and claude_code
- generate install manifests and doctor targets
EOF
