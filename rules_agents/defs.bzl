"""Public rules_agents API surface."""

load("//rules_agents/private:profile.bzl", _agent_profile = "agent_profile")
load("//rules_agents/private:skill_rule.bzl", _agent_skill = "agent_skill")


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
    """Declares a portable skill bundle rooted at `SKILL.md`."""
    _agent_skill(
        name = name,
        root = root,
        srcs = srcs,
    )
