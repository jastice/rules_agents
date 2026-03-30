"""Minimal executable wrapper for checked-in scripts."""


def _script_binary_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = executable,
        target_file = ctx.file.src,
        is_executable = True,
    )
    return DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = [ctx.file.src]),
    )


script_binary = rule(
    implementation = _script_binary_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
    executable = True,
)
