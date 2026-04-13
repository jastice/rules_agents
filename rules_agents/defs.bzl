"""Public rules_agents API surface."""

load("//rules_agents/private:profile_v2.bzl", _agent_profile_v2 = "agent_profile")
load("//rules_agents/private:runner.bzl", _agent_runner = "agent_runner")
load("//rules_agents/private:skill_rule.bzl", _agent_skill = "agent_skill")


def agent_profile(name, skills = [], credential_env = []):
    """Declares an agent profile.

    Generates:
      - :name for the buildable profile artifact
      - :name_manifest as an explicit alias to the profile artifact
    """
    _agent_profile_v2(
        name = name,
        skills = skills,
        credential_env = credential_env,
    )


def agent_runner(name, runner, profile):
    """Declares a concrete runner for an agent profile.

    Generates:
      - :name as the default interactive entrypoint
      - :name_setup for repo-local setup
      - :name_run for setup + launch
      - :name_doctor for validation without launch
      - :name_manifest for the machine-readable runner manifest artifact
    """
    _agent_runner(
        name = name,
        runner = runner,
        profile = profile,
    )


def agent_skill(name, root, srcs):
    """Declares a portable skill bundle rooted at `SKILL.md`."""
    _agent_skill(
        name = name,
        root = root,
        srcs = srcs,
    )
