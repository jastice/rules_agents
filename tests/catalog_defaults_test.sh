#!/usr/bin/env bash

set -euo pipefail

readonly CATALOG_JSON="${TEST_SRCDIR}/_main/catalog/registries.json"

export CATALOG_JSON

python3 - <<'PY'
import json
import os
from pathlib import Path

catalog_path = Path(os.environ["CATALOG_JSON"])
data = json.loads(catalog_path.read_text())
assert data["version"] == 1
registries = {entry["id"]: entry for entry in data["registries"]}

assert "openai_skills" in registries, "missing openai_skills default registry"
assert "anthropic_skills" in registries, "missing anthropic_skills default registry"

openai = registries["openai_skills"]
anthropic = registries["anthropic_skills"]

assert openai["repo_url"] == "https://github.com/openai/skills"
assert openai["agents"] == ["codex"]
assert openai["skill_path_prefix"] == "skills/.curated"

assert anthropic["repo_url"] == "https://github.com/anthropics/skills"
assert anthropic["agents"] == ["claude_code"]
assert anthropic["skill_path_prefix"] == "skills"
PY
