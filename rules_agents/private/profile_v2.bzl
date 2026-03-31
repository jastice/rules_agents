"""Internal implementation for buildable agent profiles."""

load(":profile_artifact_rule.bzl", _agent_profile_artifact = "agent_profile_artifact")


def agent_profile(name, skills = [], credential_env = []):
    """Declares one buildable local agent profile artifact."""
    _agent_profile_artifact(
        name = name,
        credential_env = credential_env,
        profile_name = name,
        skills = skills,
    )

    native.alias(
        name = name + "_manifest",
        actual = ":" + name,
    )
