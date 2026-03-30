"""Public rules_agents API surface."""

load("//rules_agents/private:profile.bzl", _agent_profile = "agent_profile")
load("//rules_agents/private:skill_rule.bzl", _agent_skill = "agent_skill")


def agent_profile(name, agent, skills = [], credential_env = []):
    """Declares a runnable local agent environment.

    Generates:
      - :name for install + start
      - :name_doctor for validation without launch
      - :name_manifest for the machine-readable manifest artifact
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
