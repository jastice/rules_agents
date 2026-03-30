"""Local shell test rule for repositories without native `sh_test`."""


def _shell_test_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = executable,
        target_file = ctx.file.src,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [ctx.file.src])
    for target in ctx.attr.data:
        runfiles = runfiles.merge(ctx.runfiles(files = target[DefaultInfo].files.to_list()))
        runfiles = runfiles.merge(target[DefaultInfo].default_runfiles)

    return DefaultInfo(
        executable = executable,
        runfiles = runfiles,
    )


_shell_test = rule(
    implementation = _shell_test_impl,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "src": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
    executable = True,
    test = True,
)


def sh_test(name, srcs, data = [], **kwargs):
    if len(srcs) != 1:
        fail("sh_test expects exactly one src, got %d" % len(srcs))
    _shell_test(
        name = name,
        src = srcs[0],
        data = data,
        **kwargs
    )
