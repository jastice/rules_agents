"""Private manifest rule for agent profiles."""

load(":providers.bzl", "AgentSkillInfo")
load(":runfiles_path.bzl", "bundle_runfiles_path")

_VALID_AGENTS = (
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


def _skill_entry(ctx, skill):
    info = skill[AgentSkillInfo]
    return {
        "bundle_runfiles_path": bundle_runfiles_path(ctx, info.bundle_dir),
        "logical_name": info.logical_name,
        "managed_dir_name": _managed_dir_name(ctx.attr.profile_name, info.skill_id),
        "skill_id": info.skill_id,
    }


def _agent_profile_manifest_impl(ctx):
    if ctx.attr.agent not in _VALID_AGENTS:
        fail("agent must be one of %s, got %r" % (_VALID_AGENTS, ctx.attr.agent))

    skills = sorted(
        [_skill_entry(ctx, skill) for skill in ctx.attr.skills],
        key = lambda entry: entry["skill_id"],
    )
    manifest = ctx.actions.declare_file(ctx.label.name + ".json")
    bundle_files = [skill[AgentSkillInfo].bundle_dir for skill in ctx.attr.skills]
    ctx.actions.write(
        output = manifest,
        content = json.encode_indent({
            "agent": ctx.attr.agent,
            "credential_env": sorted(depset(ctx.attr.credential_env).to_list()),
            "profile_name": ctx.attr.profile_name,
            "skills": skills,
            "version": 1,
        }, indent = "  ") + "\n",
    )

    return DefaultInfo(
        files = depset([manifest]),
        runfiles = ctx.runfiles(files = [manifest] + bundle_files),
    )


agent_profile_manifest = rule(
    implementation = _agent_profile_manifest_impl,
    attrs = {
        "agent": attr.string(mandatory = True),
        "credential_env": attr.string_list(),
        "profile_name": attr.string(mandatory = True),
        "skills": attr.label_list(
            allow_files = False,
            providers = [[AgentSkillInfo]],
        ),
    },
)
