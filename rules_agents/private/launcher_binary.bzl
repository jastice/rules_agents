"""Executable wrapper around the runtime launcher."""


def _launcher_binary_impl(ctx):
    launcher = ctx.file.launcher
    manifest = ctx.file.manifest
    executable = ctx.actions.declare_file(ctx.label.name)
    workspace_name = ctx.workspace_name or "_main"

    script = """#!/usr/bin/env bash
set -euo pipefail

runfiles_dir="${{RUNFILES_DIR:-$0.runfiles}}"
export RUNFILES_DIR="$runfiles_dir"
launcher="$runfiles_dir/{workspace}/{launcher_short_path}"
manifest="$runfiles_dir/{workspace}/{manifest_short_path}"

exec python3 "$launcher" "{subcommand}" "$manifest" "$@"
""".format(
        launcher_short_path = launcher.short_path,
        manifest_short_path = manifest.short_path,
        subcommand = ctx.attr.subcommand,
        workspace = workspace_name,
    )

    ctx.actions.write(
        output = executable,
        content = script,
        is_executable = True,
    )

    return DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = [launcher, manifest]).merge(
            ctx.attr.manifest[DefaultInfo].default_runfiles,
        ),
    )


launcher_binary = rule(
    implementation = _launcher_binary_impl,
    attrs = {
        "launcher": attr.label(
            allow_single_file = True,
            default = "//rules_agents/runtime:launcher.py",
        ),
        "manifest": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "subcommand": attr.string(mandatory = True),
    },
    executable = True,
)
