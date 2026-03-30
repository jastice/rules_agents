#!/usr/bin/env python3
"""Runtime launcher for rules_agents profiles."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path


WORKSPACE_MARKERS = (
    "MODULE.bazel",
    "MODULE.bazel.lock",
    "WORKSPACE",
    "WORKSPACE.bazel",
)

AGENT_ADAPTERS = {
    "codex": {
        "binary_candidates": ("codex",),
        "binary_override_env": "CODEX_BIN",
        "display_name": "Codex",
        "project_skill_root": ".agents/skills",
    },
    "claude_code": {
        "binary_candidates": ("claude",),
        "binary_override_env": "CLAUDE_CODE_BIN",
        "display_name": "Claude Code",
        "project_skill_root": ".claude/skills",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="rules_agents_launcher")
    parser.add_argument("command", choices=("doctor", "install", "start"))
    parser.add_argument("manifest_path", help="Absolute path or Bazel runfiles path to the profile manifest")
    parser.add_argument("extra_args", nargs=argparse.REMAINDER)
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def try_resolve_runfile(path: str) -> Path | None:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate

    runfiles_dir = os.environ.get("RUNFILES_DIR")
    if runfiles_dir:
        resolved = Path(runfiles_dir) / path
        if resolved.exists():
            return resolved

    manifest_file = os.environ.get("RUNFILES_MANIFEST_FILE")
    if manifest_file:
        with open(manifest_file, "r", encoding="utf-8") as handle:
            for line in handle:
                record = line.rstrip("\n").split(" ", 1)
                if len(record) == 2 and record[0] == path:
                    return Path(record[1])

    return None


def resolve_runfile(path: str) -> Path:
    resolved = try_resolve_runfile(path)
    if resolved is None:
        fail(f"unable to resolve runfile {path!r}")
    return resolved


def load_manifest(path: str) -> dict:
    manifest_path = resolve_runfile(path)
    with open(manifest_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_bundle_root(bundle_runfiles_path: str) -> Path | None:
    skill_md = try_resolve_runfile(bundle_runfiles_path + "/SKILL.md")
    if skill_md is None:
        return None
    return skill_md.parent


def resolve_workspace_root() -> Path:
    root = os.environ.get("BUILD_WORKSPACE_DIRECTORY") or os.getcwd()
    resolved = Path(root).resolve()
    if "BUILD_WORKSPACE_DIRECTORY" not in os.environ:
        if not any((resolved / marker).exists() for marker in WORKSPACE_MARKERS):
            fail(
                "computed workspace root %r does not contain any of %s"
                % (str(resolved), ", ".join(WORKSPACE_MARKERS))
            )
    return resolved


def resolve_agent_binary(agent: str) -> tuple[str | None, str]:
    adapter = AGENT_ADAPTERS[agent]
    override_env = adapter["binary_override_env"]
    override = os.environ.get(override_env)
    if override:
        return override, f"{override_env}={override}"

    for candidate in adapter["binary_candidates"]:
        resolved = shutil.which(candidate)
        if resolved:
            return resolved, f"PATH:{candidate}"

    return None, "tried %s and PATH candidates %s" % (
        override_env,
        ", ".join(adapter["binary_candidates"]),
    )


def validate_credentials(manifest: dict) -> list[str]:
    missing = []
    for env_name in manifest.get("credential_env", []):
        if env_name not in os.environ:
            missing.append(env_name)
    return missing


def validate_skill_bundles(manifest: dict) -> list[tuple[str, Path]]:
    failures = []
    for skill in manifest.get("skills", []):
        bundle_dir = resolve_bundle_root(skill["bundle_runfiles_path"])
        if bundle_dir is None or not (bundle_dir / "SKILL.md").is_file():
            failures.append((skill["skill_id"], Path(skill["bundle_runfiles_path"])))
    return failures


def print_doctor(manifest: dict) -> int:
    agent = manifest["agent"]
    adapter = AGENT_ADAPTERS.get(agent)
    if adapter is None:
        fail(f"unsupported agent {agent!r}")

    workspace_root = resolve_workspace_root()
    native_skill_root = workspace_root / adapter["project_skill_root"]
    binary, binary_detail = resolve_agent_binary(agent)
    missing_credentials = validate_credentials(manifest)
    bundle_failures = validate_skill_bundles(manifest)

    print("rules_agents doctor")
    print(f"profile: {manifest['profile_name']}")
    print(f"agent: {agent}")
    print(f"workspace_root: {workspace_root}")
    print(f"native_skill_root: {native_skill_root}")
    if binary:
        print(f"agent_binary: found ({binary_detail})")
        print(f"agent_binary_path: {binary}")
    else:
        print(f"agent_binary: missing ({binary_detail})")

    print("skills:")
    for skill in manifest.get("skills", []):
        bundle_dir = resolve_bundle_root(skill["bundle_runfiles_path"])
        skill_ok = bundle_dir is not None and (bundle_dir / "SKILL.md").is_file()
        print(
            "  - %s logical_name=%s managed_dir=%s bundle=%s status=%s"
            % (
                skill["skill_id"],
                skill["logical_name"],
                skill["managed_dir_name"],
                bundle_dir or skill["bundle_runfiles_path"],
                "ok" if skill_ok else "missing_SKILL.md",
            )
        )

    print("credentials:")
    for env_name in manifest.get("credential_env", []):
        print("  - %s: %s" % (env_name, "set" if env_name not in missing_credentials else "missing"))

    failed = False
    if not binary:
        failed = True
    if missing_credentials:
        failed = True
    if bundle_failures:
        failed = True

    return 1 if failed else 0


def main() -> int:
    args = parse_args()
    manifest = load_manifest(args.manifest_path)

    if args.command == "doctor":
        return print_doctor(manifest)

    fail(f"{args.command} is not implemented yet")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
