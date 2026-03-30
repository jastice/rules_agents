#!/usr/bin/env bash

set -euo pipefail

workspace_root="${BUILD_WORKSPACE_DIRECTORY:-$(pwd)}"

echo "rules_agents doctor"
echo "workspace: ${workspace_root}"
echo "check: workspace initialized"
