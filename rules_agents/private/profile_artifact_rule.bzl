"""Private rule for buildable agent profile artifacts."""

load(":providers.bzl", "AgentProfileInfo", "AgentSkillInfo")


def _bundle_runfiles_path(ctx, bundle):
    workspace_name = ctx.workspace_name or "_main"
    return workspace_name + "/" + bundle.short_path


def _skill_entry(ctx, skill):
    info = skill[AgentSkillInfo]
    return {
        "bundle_runfiles_path": _bundle_runfiles_path(ctx, info.bundle_dir),
        "logical_name": info.logical_name,
        "skill_id": info.skill_id,
    }


def _agent_profile_artifact_impl(ctx):
    skill_infos = sorted(
        [skill[AgentSkillInfo] for skill in ctx.attr.skills],
        key = lambda info: info.skill_id,
    )
    skills = sorted(
        [_skill_entry(ctx, skill) for skill in ctx.attr.skills],
        key = lambda entry: entry["skill_id"],
    )

    manifest = ctx.actions.declare_file(ctx.label.name + ".json")
    bundle_files = [info.bundle_dir for info in skill_infos]
    credential_env = sorted(depset(ctx.attr.credential_env).to_list())

    ctx.actions.write(
        output = manifest,
        content = json.encode_indent({
            "credential_env": credential_env,
            "profile_name": ctx.attr.profile_name,
            "skills": skills,
            "version": 1,
        }, indent = "  ") + "\n",
    )

    return [
        DefaultInfo(
            files = depset([manifest]),
            runfiles = ctx.runfiles(files = [manifest] + bundle_files),
        ),
        AgentProfileInfo(
            credential_env = credential_env,
            manifest = manifest,
            profile_name = ctx.attr.profile_name,
            skills = skill_infos,
        ),
    ]


agent_profile_artifact = rule(
    implementation = _agent_profile_artifact_impl,
    attrs = {
        "credential_env": attr.string_list(),
        "profile_name": attr.string(mandatory = True),
        "skills": attr.label_list(
            allow_files = False,
            providers = [[AgentSkillInfo]],
        ),
    },
)
