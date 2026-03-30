"""Public rules_agents API surface."""

load("//rules_agents/private:profile.bzl", _agent_profile = "agent_profile")


def agent_profile(name, agent, skills = [], credential_env = []):
    """Declares a runnable local agent environment.

    This is a v1 placeholder macro. It validates the public API shape while the
    implementation is being built out.
    """
    _agent_profile(
        name = name,
        agent = agent,
        skills = skills,
        credential_env = credential_env,
    )


def agent_skill(name, root, srcs):
    """Placeholder for a portable skill bundle declaration."""
    native.filegroup(
        name = name,
        srcs = srcs,
    )
