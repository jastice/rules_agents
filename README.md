# rules_agents

`rules_agents` lets a repository declare a local coding-agent environment in Bazel and
launch it with one command.

The intended v1 experience is simple:

```bash
bazel run //agent:dev
```

From the repository's point of view, that command should:

1. choose a supported agent client: `codex` or `claude_code`
2. install the repo's declared skills into the agent's native project-local skill directory
3. validate required credential environment variables
4. launch the selected agent from the repository root

This is deliberately narrow. It is not a general AI framework, global config manager, or
agent installer. It is a repo-owned launcher and skill installer.

## Why it exists

Repositories already own their build, test, and developer tooling. This project aims to let
them own local coding-agent setup the same way:

- the repo chooses the agent
- the repo declares reusable skills
- Bazel turns that declaration into a reproducible local setup

That keeps agent setup repo-scoped, shareable, and boring in the right way.

## What v1 includes

- exactly two supported agent clients: `codex` and `claude_code`
- local skills declared from files already in the repo
- remote skills synthesized from git archive downloads
- installation into the agent's native project-local skill directories
- `doctor`, `manifest`, and `start` behavior for a declared profile

## What you need

Before using `rules_agents`, a developer should already have:

- Bazel with Bzlmod enabled
- one supported agent client installed separately
- any required agent login or auth state handled by that client
- required credential environment variables exported in the shell

`rules_agents` does not install agent binaries, synthesize user-global config, or manage
secrets beyond validating and forwarding declared env vars.

## Mental Model

- `agent_skill`: one portable skill bundle rooted at a `SKILL.md`
- `agent_profile`: one runnable local agent environment
- `skill_deps`: one module extension for bringing in remote skill archives

For the supported agents, managed skills are intended to be installed under:

- `codex`: `<repo>/.agents/skills`
- `claude_code`: `<repo>/.claude/skills`

The launcher manages only tool-owned subdirectories inside those native roots.

## Minimal Setup

For the smallest local-only setup, a repo only needs a local skill and one profile.

In a BUILD file:

```python
load("@agent_env//:defs.bzl", "agent_profile", "agent_skill")

agent_skill(
    name = "repo_helper",
    root = "skills/repo_helper",
    srcs = glob(["skills/repo_helper/**"], exclude_directories = 1),
)

agent_profile(
    name = "dev",
    agent = "codex",
    skills = [
        ":repo_helper",
    ],
    credential_env = ["OPENAI_API_KEY"],
)
```

That gives the repo a single local profile with no remote skill dependencies.

If the repo also wants to reuse skills published from another repository, add a module
extension entry in `MODULE.bazel`:

In `MODULE.bazel`, bring in `agent_env` and any remote skill repos:

```python
bazel_dep(name = "agent_env")

archive_override(
    module_name = "agent_env",
    urls = ["https://github.com/you/agent_env/archive/COMMIT.tar.gz"],
    strip_prefix = "agent_env-COMMIT",
)

skill_deps = use_extension("@agent_env//:extensions.bzl", "skill_deps")

skill_deps.remote(
    name = "community_skills",
    url = "https://github.com/org/bazel-skills/archive/abc123.tar.gz",
    strip_prefix = "bazel-skills-abc123",
)

use_repo(skill_deps, "community_skills")
```

In a BUILD file, declare one local skill and one profile:

```python
load("@agent_env//:defs.bzl", "agent_profile", "agent_skill")

agent_skill(
    name = "bazel_debug_skill",
    root = "skills/bazel_debug",
    srcs = glob(["skills/bazel_debug/**"], exclude_directories = 1),
)

agent_profile(
    name = "dev",
    agent = "codex",
    skills = [
        ":bazel_debug_skill",
        "@community_skills//:test_runner",
    ],
    credential_env = ["OPENAI_API_KEY"],
)
```

Then the intended user commands are:

```bash
bazel run //agent:dev_doctor
bazel run //agent:dev
bazel run //agent:dev -- --help
```

## Public API

The intended v1 public API stays deliberately small:

- `agent_skill`
- `agent_profile`
- `skill_deps`

The product and architecture source of truth is `rules_agents spec.md`.

## Current Status

The v1 slice described in `rules_agents spec.md` is implemented:

- `agent_skill` packages local skill bundles and validates bundle shape
- `agent_profile` generates `:name`, `:name_doctor`, and `:name_manifest`
- the runtime launcher supports `doctor`, `install`, and `start`
- managed installs land under `.agents/skills` for Codex and `.claude/skills` for Claude Code
- `skill_deps.remote(...)` synthesizes remote `agent_skill` targets from archive contents
- examples exist for both supported agents

Repository verification today:

- `bazel test //tests:all`
- `tests/remote_skill_deps_test.sh`
- `tests/missing_skill_md_test.sh`

## Example Targets

- `//agent:dev`, `//agent:dev_doctor`, `//agent:dev_manifest` alias the Codex example profile
- `//agent:claude_dev`, `//agent:claude_dev_doctor`, `//agent:claude_dev_manifest` alias the Claude Code example profile
- `//examples:dev_profile_install` and `//examples:claude_profile_install` are example install-only wrappers used by tests

## Repository Layout

- `MODULE.bazel`: Bazel module root
- `BUILD.bazel`: top-level Bazel package
- `agent/`: example-facing aliases for the runnable profiles
- `examples/`: working local skill and profile targets for both agents
- `tests/`: Bazel integration tests for the launcher flow
- `rules_agents/`: public Starlark surface
- `rules_agents/private/`: internal implementation
- `rules_agents/runtime/`: runtime launcher implementation
- `rules_agents spec.md`: product spec and implementation plan
