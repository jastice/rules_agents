"""Internal implementation for agent profiles."""

load(":providers.bzl", "AgentSkillInfo")

_VALID_AGENTS = (
    "claude_code",
    "codex",
)


def _agent_profile_impl(ctx):
    if ctx.attr.agent not in _VALID_AGENTS:
        fail("agent must be one of %s, got %r" % (_VALID_AGENTS, ctx.attr.agent))

    manifest = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(
        output = manifest,
        content = """{
  "name": "%s",
  "agent": "%s",
  "skills": [%s],
  "credential_env": [%s]
}
""" % (
            ctx.label.name,
            ctx.attr.agent,
            ", ".join(['"%s"' % skill[AgentSkillInfo].skill_id for skill in ctx.attr.skills]),
            ", ".join(['"%s"' % env for env in ctx.attr.credential_env]),
        ),
    )

    return DefaultInfo(
        files = depset([manifest]),
    )


agent_profile = rule(
    implementation = _agent_profile_impl,
    attrs = {
        "agent": attr.string(mandatory = True),
        "skills": attr.label_list(
            allow_files = False,
            providers = [[AgentSkillInfo]],
        ),
        "credential_env": attr.string_list(),
    },
)
