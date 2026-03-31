"""Helpers for deriving normalized Bazel runfiles paths."""


def bundle_runfiles_path(ctx, bundle):
    short_path = bundle.short_path
    if short_path.startswith("../"):
        return short_path[3:]
    workspace_name = ctx.workspace_name or "_main"
    return workspace_name + "/" + short_path
