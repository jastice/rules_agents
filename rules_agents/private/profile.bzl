"""Internal implementation for agent profiles."""

load(":profile_manifest_rule.bzl", _agent_profile_manifest = "agent_profile_manifest")


def agent_profile(name, agent, skills = [], credential_env = []):
    """Declares the manifest target for one local agent profile."""
    _agent_profile_manifest(
        name = name,
        agent = agent,
        credential_env = credential_env,
        profile_name = name,
        skills = skills,
    )
