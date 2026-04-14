#!/usr/bin/env python3
"""Consumer smoke test for the checked-in BCR test module."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


RUNFILES_ROOT = Path(os.environ["TEST_SRCDIR"]) / "_main"
CODEX_DOCTOR_BIN = RUNFILES_ROOT / "codex_dev_doctor"
CODEX_RUN_BIN = RUNFILES_ROOT / "codex_dev_run"
CLAUDE_DOCTOR_BIN = RUNFILES_ROOT / "claude_dev_doctor"
CLAUDE_RUN_BIN = RUNFILES_ROOT / "claude_dev_run"
FAKE_CODEX_SRC = RUNFILES_ROOT / "fake_codex.sh"
FAKE_CLAUDE_SRC = RUNFILES_ROOT / "fake_claude.sh"
CODEX_MANAGED_DIR = "__bazel_agent_env__codex_profile__main__repo_helper"
CLAUDE_MANAGED_DIR = "__bazel_agent_env__claude_profile__main__repo_helper"


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def make_workspace(workspace_dir: Path) -> None:
    workspace_dir.mkdir(parents=True, exist_ok=True)
    (workspace_dir / "MODULE.bazel").write_text("", encoding="utf-8")


def copy_executable(source: Path, destination: Path) -> None:
    shutil.copyfile(source, destination)
    destination.chmod(0o755)


def run_with_workspace(
    workspace_dir: Path,
    command: list[str],
    *,
    env_overrides: dict[str, str],
    output_path: Path | None = None,
    expect_success: bool = True,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["RUNFILES_DIR"] = os.environ["TEST_SRCDIR"]
    env["BUILD_WORKSPACE_DIRECTORY"] = str(workspace_dir)
    env.update(env_overrides)
    result = subprocess.run(
        command,
        cwd=workspace_dir,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if output_path is not None:
        output_path.write_text(result.stdout + result.stderr, encoding="utf-8")
    if expect_success and result.returncode != 0:
        fail(f"command failed: {' '.join(command)}\n{result.stdout}{result.stderr}")
    if not expect_success and result.returncode == 0:
        fail(f"command unexpectedly succeeded: {' '.join(command)}")
    return result


def assert_contains(path: Path, expected: str, message: str) -> None:
    contents = path.read_text(encoding="utf-8")
    if expected not in contents:
        fail(f"{message}: {expected!r} not found in {path}")


def main() -> None:
    test_tmpdir = Path(os.environ["TEST_TMPDIR"])
    codex_workspace = test_tmpdir / "codex-workspace"
    claude_workspace = test_tmpdir / "claude-workspace"
    codex_output = test_tmpdir / "codex.out"
    claude_output = test_tmpdir / "claude.out"
    doctor_output = test_tmpdir / "doctor.out"
    fake_codex_bin = test_tmpdir / "fake_codex.sh"
    fake_claude_bin = test_tmpdir / "fake_claude.sh"

    copy_executable(FAKE_CODEX_SRC, fake_codex_bin)
    copy_executable(FAKE_CLAUDE_SRC, fake_claude_bin)

    make_workspace(codex_workspace)
    run_with_workspace(
        codex_workspace,
        [str(CODEX_DOCTOR_BIN)],
        env_overrides={"CODEX_BIN": "/usr/bin/true"},
        output_path=doctor_output,
    )
    assert_contains(doctor_output, "profile: codex_profile", "codex doctor omitted profile")
    assert_contains(doctor_output, "agent_binary: found", "codex doctor did not find binary")
    assert_contains(doctor_output, "status=ok", "codex doctor did not validate skill bundle")
    if "OPENAI_API_KEY" in doctor_output.read_text(encoding="utf-8"):
        fail("codex doctor unexpectedly required OPENAI_API_KEY")

    run_with_workspace(
        codex_workspace,
        [str(CODEX_RUN_BIN), "--", "--alpha", "beta"],
        env_overrides={
            "CODEX_BIN": str(fake_codex_bin),
            "FAKE_CODEX_OUT": str(codex_output),
        },
    )
    assert_contains(codex_output, f"cwd={codex_workspace}", "codex run used wrong cwd")
    assert_contains(codex_output, "openai_api_key=", "codex run unexpectedly required OPENAI_API_KEY")
    assert_contains(codex_output, "argv=--alpha beta ", "codex run did not forward args")
    if not (codex_workspace / ".agents" / "skills" / CODEX_MANAGED_DIR / "SKILL.md").is_file():
        fail("codex install did not materialize the local skill")

    make_workspace(claude_workspace)
    run_with_workspace(
        claude_workspace,
        [str(CLAUDE_DOCTOR_BIN)],
        env_overrides={"CLAUDE_CODE_BIN": "/usr/bin/true"},
        output_path=doctor_output,
        expect_success=False,
    )
    assert_contains(
        doctor_output,
        "ANTHROPIC_API_KEY: missing",
        "claude doctor missing-credential output incorrect",
    )

    run_with_workspace(
        claude_workspace,
        [str(CLAUDE_RUN_BIN), "--", "--omega"],
        env_overrides={
            "ANTHROPIC_API_KEY": "test-anthropic",
            "CLAUDE_CODE_BIN": str(fake_claude_bin),
            "FAKE_CLAUDE_OUT": str(claude_output),
        },
    )
    assert_contains(claude_output, f"cwd={claude_workspace}", "claude run used wrong cwd")
    assert_contains(
        claude_output,
        "anthropic_api_key=test-anthropic",
        "claude run did not forward ANTHROPIC_API_KEY",
    )
    assert_contains(claude_output, "argv=--omega ", "claude run did not forward args")
    if not (claude_workspace / ".claude" / "skills" / CLAUDE_MANAGED_DIR / "SKILL.md").is_file():
        fail("claude install did not materialize the local skill")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # pragma: no cover
        raise SystemExit(f"FAIL: {exc}") from exc
