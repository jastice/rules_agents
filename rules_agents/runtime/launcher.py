#!/usr/bin/env python3
"""Runtime launcher for rules_agents profiles."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

from python.runfiles import Runfiles

TOOL_VERSION = "0.1.0"
OWNER_MARKER_NAME = ".bazel_agent_env_owner.json"
CLEANUP_MANIFEST_PREFIX = ".bazel_agent_env_"

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
    parser.add_argument("command", choices=("doctor", "install", "run", "setup", "start"))
    parser.add_argument("manifest_path", help="Absolute path or Bazel runfiles path to the profile manifest")
    parser.add_argument("extra_args", nargs=argparse.REMAINDER)
    return parser.parse_args()


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def create_runfiles() -> Runfiles:
    runfiles = Runfiles.Create()
    if runfiles is None:
        fail("unable to initialize Bazel runfiles support")
    return runfiles


def try_resolve_runfile(path: str, runfiles: Runfiles) -> Path | None:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate

    resolved = runfiles.Rlocation(path)
    return Path(resolved) if resolved else None


def resolve_runfile(path: str, runfiles: Runfiles) -> Path:
    resolved = try_resolve_runfile(path, runfiles)
    if resolved is None:
        fail(f"unable to resolve runfile {path!r}")
    return resolved


def load_manifest(path: str, runfiles: Runfiles) -> dict:
    manifest_path = resolve_runfile(path, runfiles)
    with open(manifest_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_bundle_root(bundle_runfiles_path: str, runfiles: Runfiles) -> Path | None:
    skill_md = try_resolve_runfile(bundle_runfiles_path + "/SKILL.md", runfiles)
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


def validate_skill_bundles(manifest: dict, runfiles: Runfiles) -> list[tuple[str, Path]]:
    failures = []
    for skill in manifest.get("skills", []):
        bundle_dir = resolve_bundle_root(skill["bundle_runfiles_path"], runfiles)
        if bundle_dir is None or not (bundle_dir / "SKILL.md").is_file():
            failures.append((skill["skill_id"], Path(skill["bundle_runfiles_path"])))
    return failures


def native_skill_root(workspace_root: Path, manifest: dict) -> Path:
    agent = manifest["agent"]
    adapter = AGENT_ADAPTERS.get(agent)
    if adapter is None:
        fail(f"unsupported agent {agent!r}")
    return workspace_root / adapter["project_skill_root"]


def cleanup_manifest_path(skill_root: Path, profile_name: str) -> Path:
    return skill_root / f"{CLEANUP_MANIFEST_PREFIX}{profile_name}.json"


def owner_marker_contents(manifest: dict, managed_dir_name: str) -> dict:
    return {
        "agent": manifest["agent"],
        "managed_dir_name": managed_dir_name,
        "profile_name": manifest["profile_name"],
        "tool": "rules_agents",
        "tool_version": TOOL_VERSION,
    }


def read_json_file(path: Path) -> dict | None:
    if not path.is_file():
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json_file(path: Path, payload: dict) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def read_cleanup_manifest(path: Path) -> dict | None:
    try:
        return read_json_file(path)
    except json.JSONDecodeError as exc:
        fail(f"invalid cleanup manifest at {path}: {exc}")


def read_owner_marker(path: Path) -> dict | None:
    try:
        return read_json_file(path / OWNER_MARKER_NAME)
    except json.JSONDecodeError as exc:
        fail(f"invalid ownership marker at {path / OWNER_MARKER_NAME}: {exc}")


def marker_matches(manifest: dict, managed_dir_name: str, marker: dict | None) -> bool:
    return marker_matches_values(
        agent=manifest["agent"],
        profile_name=manifest["profile_name"],
        managed_dir_name=managed_dir_name,
        marker=marker,
    )


def marker_matches_values(
    *,
    agent: str,
    profile_name: str,
    managed_dir_name: str,
    marker: dict | None,
) -> bool:
    if marker is None:
        return False
    return (
        marker.get("tool") == "rules_agents"
        and marker.get("agent") == agent
        and marker.get("profile_name") == profile_name
        and marker.get("managed_dir_name") == managed_dir_name
    )


def is_owned_destination(manifest: dict, previous_cleanup: dict | None, path: Path) -> bool:
    return is_owned_destination_for_profile(
        agent=manifest["agent"],
        profile_name=manifest["profile_name"],
        previous_cleanup=previous_cleanup,
        path=path,
    )


def is_owned_destination_for_profile(
    *,
    agent: str,
    profile_name: str,
    previous_cleanup: dict | None,
    path: Path,
) -> bool:
    managed_dir_name = path.name
    if previous_cleanup is None:
        return False
    if previous_cleanup.get("agent") != agent:
        return False
    if previous_cleanup.get("profile_name") != profile_name:
        return False
    installed = previous_cleanup.get("installed_managed_dirs", [])
    if managed_dir_name not in installed:
        return False
    return marker_matches_values(
        agent=agent,
        profile_name=profile_name,
        managed_dir_name=managed_dir_name,
        marker=read_owner_marker(path),
    )


def write_owner_marker(path: Path, manifest: dict, managed_dir_name: str) -> None:
    write_json_file(path / OWNER_MARKER_NAME, owner_marker_contents(manifest, managed_dir_name))


def remove_inactive_profile_dirs(
    skill_root: Path,
    manifest: dict,
    installed_managed_dirs: list[str],
) -> list[str]:
    removed_dirs = []
    current_cleanup_path = cleanup_manifest_path(skill_root, manifest["profile_name"])
    for cleanup_path in skill_root.glob(f"{CLEANUP_MANIFEST_PREFIX}*.json"):
        if cleanup_path == current_cleanup_path:
            continue
        previous_cleanup = read_cleanup_manifest(cleanup_path)
        if previous_cleanup is None:
            continue
        if previous_cleanup.get("agent") != manifest["agent"]:
            continue
        profile_name = previous_cleanup.get("profile_name")
        if not isinstance(profile_name, str) or not profile_name:
            continue
        for managed_dir_name in previous_cleanup.get("installed_managed_dirs", []):
            if managed_dir_name in installed_managed_dirs:
                continue
            candidate = skill_root / managed_dir_name
            if candidate.exists() and is_owned_destination_for_profile(
                agent=manifest["agent"],
                profile_name=profile_name,
                previous_cleanup=previous_cleanup,
                path=candidate,
            ):
                shutil.rmtree(candidate)
                removed_dirs.append(managed_dir_name)
    return removed_dirs


def stage_skill_bundle(skill_root: Path, manifest: dict, skill: dict, runfiles: Runfiles) -> Path:
    bundle_dir = resolve_bundle_root(skill["bundle_runfiles_path"], runfiles)
    if bundle_dir is None:
        fail(f"unable to resolve bundle for skill {skill['skill_id']}")
    temp_dir = Path(
        tempfile.mkdtemp(prefix=f".{skill['managed_dir_name']}.", dir=str(skill_root))
    )
    shutil.copytree(bundle_dir, temp_dir / "bundle", dirs_exist_ok=True)
    staged_dir = temp_dir / "bundle"
    for root, dirs, files in os.walk(staged_dir):
        os.chmod(root, 0o755)
        for name in dirs:
            os.chmod(Path(root) / name, 0o755)
        for name in files:
            os.chmod(Path(root) / name, 0o644)
    write_owner_marker(staged_dir, manifest, skill["managed_dir_name"])
    return staged_dir


def replace_owned_destination(temp_dir: Path, destination: Path) -> None:
    backup = destination.parent / f".{destination.name}.old"
    if backup.exists():
        shutil.rmtree(backup)
    os.replace(destination, backup)
    try:
        os.replace(temp_dir, destination)
    except Exception:
        os.replace(backup, destination)
        raise
    shutil.rmtree(backup)


def install_declared_skills(workspace_root: Path, manifest: dict, runfiles: Runfiles) -> list[str]:
    skill_root = native_skill_root(workspace_root, manifest)
    skill_root.mkdir(parents=True, exist_ok=True)
    cleanup_path = cleanup_manifest_path(skill_root, manifest["profile_name"])
    previous_cleanup = read_cleanup_manifest(cleanup_path)
    installed_managed_dirs: list[str] = []

    for skill in manifest.get("skills", []):
        managed_dir_name = skill["managed_dir_name"]
        destination = skill_root / managed_dir_name
        staged_dir = stage_skill_bundle(skill_root, manifest, skill, runfiles)
        installed_managed_dirs.append(managed_dir_name)
        staged_parent = staged_dir.parent
        try:
            if destination.exists():
                if not is_owned_destination(manifest, previous_cleanup, destination):
                    fail(f"refusing to overwrite unmanaged directory {destination}")
                replace_owned_destination(staged_dir, destination)
            else:
                os.replace(staged_dir, destination)
        finally:
            if staged_parent.exists():
                shutil.rmtree(staged_parent)

    stale_dirs = []
    if previous_cleanup is not None:
        for managed_dir_name in previous_cleanup.get("installed_managed_dirs", []):
            if managed_dir_name not in installed_managed_dirs:
                candidate = skill_root / managed_dir_name
                if candidate.exists() and is_owned_destination(manifest, previous_cleanup, candidate):
                    shutil.rmtree(candidate)
                    stale_dirs.append(managed_dir_name)

    stale_dirs.extend(
        remove_inactive_profile_dirs(
            skill_root=skill_root,
            manifest=manifest,
            installed_managed_dirs=installed_managed_dirs,
        )
    )

    cleanup_payload = {
        "agent": manifest["agent"],
        "installed_managed_dirs": installed_managed_dirs,
        "install_timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "profile_name": manifest["profile_name"],
        "tool_version": TOOL_VERSION,
    }
    write_json_file(cleanup_path, cleanup_payload)
    return stale_dirs


def run_install(manifest: dict, runfiles: Runfiles) -> int:
    workspace_root = resolve_workspace_root()
    return perform_install(manifest, workspace_root, runfiles, verbose=True)


def perform_install(manifest: dict, workspace_root: Path, runfiles: Runfiles, verbose: bool) -> int:
    missing_credentials = validate_credentials(manifest)
    if missing_credentials:
        print("rules_agents install", file=sys.stderr)
        for env_name in missing_credentials:
            print(f"missing credential: {env_name}", file=sys.stderr)
        return 1

    bundle_failures = validate_skill_bundles(manifest, runfiles)
    if bundle_failures:
        print("rules_agents install", file=sys.stderr)
        for skill_id, bundle_path in bundle_failures:
            print(f"invalid skill bundle: {skill_id} at {bundle_path}", file=sys.stderr)
        return 1

    skill_root = native_skill_root(workspace_root, manifest)
    removed = install_declared_skills(workspace_root, manifest, runfiles)

    if verbose:
        print("rules_agents install")
        print(f"profile: {manifest['profile_name']}")
        print(f"agent: {manifest['agent']}")
        print(f"native_skill_root: {skill_root}")
        print("installed:")
        for skill in manifest.get("skills", []):
            print(f"  - {skill['managed_dir_name']}")
        if removed:
            print("removed_stale:")
            for managed_dir_name in removed:
                print(f"  - {managed_dir_name}")

    return 0


def normalized_extra_args(values: list[str]) -> list[str]:
    if values and values[0] == "--":
        return values[1:]
    return values


def run_start(manifest: dict, runfiles: Runfiles, extra_args: list[str]) -> int:
    workspace_root = resolve_workspace_root()
    binary, binary_detail = resolve_agent_binary(manifest["agent"])
    if binary is None:
        print("rules_agents start", file=sys.stderr)
        print(f"missing agent binary: {binary_detail}", file=sys.stderr)
        return 1

    install_status = perform_install(manifest, workspace_root, runfiles, verbose=False)
    if install_status != 0:
        return install_status

    os.chdir(workspace_root)
    child_argv = [binary] + normalized_extra_args(extra_args)
    child_env = os.environ.copy()
    os.execvpe(binary, child_argv, child_env)
    return 1


def print_doctor(manifest: dict, runfiles: Runfiles) -> int:
    agent = manifest["agent"]
    adapter = AGENT_ADAPTERS.get(agent)
    if adapter is None:
        fail(f"unsupported agent {agent!r}")

    workspace_root = resolve_workspace_root()
    native_skill_root = workspace_root / adapter["project_skill_root"]
    binary, binary_detail = resolve_agent_binary(agent)
    missing_credentials = validate_credentials(manifest)
    bundle_failures = validate_skill_bundles(manifest, runfiles)

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
        bundle_dir = resolve_bundle_root(skill["bundle_runfiles_path"], runfiles)
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
    runfiles = create_runfiles()
    manifest = load_manifest(args.manifest_path, runfiles)

    if args.command == "doctor":
        return print_doctor(manifest, runfiles)
    if args.command in ("install", "setup"):
        return run_install(manifest, runfiles)
    if args.command in ("run", "start"):
        return run_start(manifest, runfiles, args.extra_args)

    fail(f"{args.command} is not implemented yet")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
