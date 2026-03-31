"""Internal implementation for agent runners."""

load(":launcher_binary.bzl", _launcher_binary = "launcher_binary")
load(":runner_manifest_rule.bzl", _agent_runner_manifest = "agent_runner_manifest")


def agent_runner(name, runner, profile):
    """Declares one runtime realization of an agent profile."""
    manifest_rule_target = "_" + name + "_manifest"
    manifest_target = name + "_manifest"

    _agent_runner_manifest(
        name = manifest_rule_target,
        profile = profile,
        runner = runner,
    )

    native.alias(
        name = manifest_target,
        actual = ":" + manifest_rule_target,
    )

    _launcher_binary(
        name = name + "_setup",
        manifest = ":" + manifest_target,
        subcommand = "setup",
    )

    _launcher_binary(
        name = name + "_run",
        manifest = ":" + manifest_target,
        subcommand = "run",
    )

    _launcher_binary(
        name = name + "_doctor",
        manifest = ":" + manifest_target,
        subcommand = "doctor",
    )

    native.alias(
        name = name,
        actual = ":" + name + "_run",
    )
