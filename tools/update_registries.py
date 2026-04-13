#!/usr/bin/env python3
"""Refresh registry archive pins from upstream git refs."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="update_registries")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Rewrite the catalog file in place instead of printing updated JSON to stdout.",
    )
    parser.add_argument(
        "--catalog",
        help="Path to a registries.json file. Relative paths resolve from BUILD_WORKSPACE_DIRECTORY or the current directory.",
    )
    parser.add_argument(
        "--registry",
        action="append",
        default=[],
        help="Limit updates to one registry id. May be repeated.",
    )
    return parser.parse_args()


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def workspace_root() -> Path:
    root = os.environ.get("BUILD_WORKSPACE_DIRECTORY") or os.getcwd()
    return Path(root).resolve()


def resolve_catalog_path(arg_value: str | None) -> tuple[Path, bool]:
    if arg_value:
        candidate = Path(arg_value)
        if not candidate.is_absolute():
            candidate = workspace_root() / candidate
        return candidate.resolve(), True

    workspace_catalog = workspace_root() / "catalog" / "registries.json"
    if workspace_catalog.is_file():
        return workspace_catalog, True

    runfiles_catalog = Path(__file__).resolve().parents[1] / "catalog" / "registries.json"
    return runfiles_catalog, False


def load_catalog(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def render_catalog(payload: dict) -> str:
    return json.dumps(payload, indent=2) + "\n"


def resolve_latest_sha(repo_url: str, branch: str) -> str:
    result = subprocess.run(
        ["git", "ls-remote", repo_url, f"refs/heads/{branch}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"git ls-remote failed for {repo_url}")

    first_line = next((line for line in result.stdout.splitlines() if line.strip()), "")
    sha = first_line.split()[0] if first_line else ""
    if len(sha) != 40 or any(char not in "0123456789abcdef" for char in sha):
        raise RuntimeError(f"unexpected ls-remote output for {repo_url!r}: {first_line!r}")
    return sha


def github_archive_fields(repo_url: str, revision: str) -> tuple[str, str]:
    normalized = repo_url.rstrip("/")
    if not normalized.startswith("https://github.com/"):
        raise RuntimeError(
            f"registry repo_url must be a GitHub repository URL for automatic archive pinning: {repo_url}"
        )
    repo_name = normalized.rsplit("/", 1)[-1]
    return f"{normalized}/archive/{revision}.tar.gz", f"{repo_name}-{revision}"


def update_catalog(payload: dict, selected_ids: set[str]) -> tuple[dict, list[str]]:
    registries = payload.get("registries")
    if not isinstance(registries, list):
        raise RuntimeError("catalog must define a registries array")

    known_ids = {entry.get("id") for entry in registries if isinstance(entry, dict)}
    missing = sorted(selected_ids - known_ids)
    if missing:
        raise RuntimeError("unknown registry id(s): %s" % ", ".join(missing))

    updates = []
    for entry in registries:
        registry_id = entry["id"]
        if selected_ids and registry_id not in selected_ids:
            continue

        revision = resolve_latest_sha(entry["repo_url"], entry.get("default_branch", "main"))
        archive_url, strip_prefix = github_archive_fields(entry["repo_url"], revision)
        changed = (
            entry.get("archive_url") != archive_url or
            entry.get("strip_prefix", "") != strip_prefix
        )
        entry["archive_url"] = archive_url
        entry["strip_prefix"] = strip_prefix
        updates.append(
            "%s: %s%s" % (
                registry_id,
                revision,
                " (updated)" if changed else " (unchanged)",
            )
        )

    return payload, updates


def main() -> int:
    args = parse_args()
    catalog_path, catalog_is_workspace_file = resolve_catalog_path(args.catalog)
    if not catalog_path.is_file():
        return fail(f"catalog file not found: {catalog_path}")

    try:
        payload = load_catalog(catalog_path)
        payload, updates = update_catalog(payload, set(args.registry))
    except (OSError, ValueError, RuntimeError) as exc:
        return fail(str(exc))

    if not updates:
        print("No registries selected for update.", file=sys.stderr)
        return 0

    rendered = render_catalog(payload)
    if args.apply:
        if not args.catalog and not catalog_is_workspace_file:
            return fail(
                "default catalog resolved inside runfiles; pass --catalog with a writable path when using --apply"
            )
        try:
            with open(catalog_path, "w", encoding="utf-8") as handle:
                handle.write(rendered)
        except OSError as exc:
            return fail(f"unable to write catalog file {catalog_path}: {exc}")
        print(f"Updated {catalog_path}")
        for line in updates:
            print(line)
        return 0

    sys.stdout.write(rendered)
    for line in updates:
        print(line, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
