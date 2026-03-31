"""Private rule for agent-runner manifests."""

load(":providers.bzl", "AgentProfileInfo")

_VALID_RUNNERS = (
    "claude_code",
    "codex",
)


def _sanitize_fragment(value):
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    pieces = []
    for index in range(len(value)):
        char = value[index]
        if char in allowed:
            pieces.append(char.lower())
        else:
            pieces.append("_")

    sanitized = "".join(pieces).strip("_")
    return sanitized or "value"


def _managed_dir_name(profile_name, skill_id):
    return "__bazel_agent_env__%s__%s" % (
        _sanitize_fragment(profile_name),
        skill_id,
    )


def _bundle_runfiles_path(ctx, bundle):
    workspace_name = ctx.workspace_name or "_main"
    return workspace_name + "/" + bundle.short_path


def _agent_runner_manifest_impl(ctx):
    if ctx.attr.runner not in _VALID_RUNNERS:
        fail("runner must be one of %s, got %r" % (_VALID_RUNNERS, ctx.attr.runner))

    profile = ctx.attr.profile[AgentProfileInfo]
    skills = [
        {
            "bundle_runfiles_path": _bundle_runfiles_path(ctx, info.bundle_dir),
            "logical_name": info.logical_name,
            "managed_dir_name": _managed_dir_name(profile.profile_name, info.skill_id),
            "skill_id": info.skill_id,
        }
        for info in profile.skills
    ]

    manifest = ctx.actions.declare_file(ctx.label.name + ".json")
    bundle_files = [info.bundle_dir for info in profile.skills]

    ctx.actions.write(
        output = manifest,
        content = json.encode_indent({
            "agent": ctx.attr.runner,
            "credential_env": profile.credential_env,
            "profile_name": profile.profile_name,
            "skills": skills,
            "version": 1,
        }, indent = "  ") + "\n",
    )

    runfiles = ctx.runfiles(files = [manifest, profile.manifest] + bundle_files)
    runfiles = runfiles.merge(ctx.attr.profile[DefaultInfo].default_runfiles)

    return DefaultInfo(
        files = depset([manifest]),
        runfiles = runfiles,
    )


agent_runner_manifest = rule(
    implementation = _agent_runner_manifest_impl,
    attrs = {
        "profile": attr.label(
            allow_files = False,
            mandatory = True,
            providers = [[AgentProfileInfo]],
        ),
        "runner": attr.string(mandatory = True),
    },
)
