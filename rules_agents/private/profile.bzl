"""Internal implementation for agent profiles."""

load(":launcher_binary.bzl", _launcher_binary = "launcher_binary")
load(":profile_manifest_rule.bzl", _agent_profile_manifest = "agent_profile_manifest")


def agent_profile(name, agent, skills = [], credential_env = []):
    """Declares one runnable local agent profile and its public targets."""
    manifest_target = name + "_manifest"
    manifest_rule_target = "_" + manifest_target

    _agent_profile_manifest(
        name = manifest_rule_target,
        agent = agent,
        credential_env = credential_env,
        profile_name = name,
        skills = skills,
    )

    native.alias(
        name = manifest_target,
        actual = ":" + manifest_rule_target,
    )

    _launcher_binary(
        name = name,
        manifest = ":" + manifest_target,
        subcommand = "start",
    )

    _launcher_binary(
        name = name + "_doctor",
        manifest = ":" + manifest_target,
        subcommand = "doctor",
    )
