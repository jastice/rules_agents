---
description: Concise setup and usage guide for this repository's rules_agents API and runner flow.
---

# rules_agents Repo Guide

Use this repository to declare a repo-local coding-agent environment in Bazel and launch it
from the workspace root. Keep the model narrow:

- supported runners: `codex`, `claude_code`
- repo-local install roots: `.agents/skills`, `.claude/skills`
- public API: `agent_skill`, `agent_profile`, `agent_runner`, `skill_deps`
- built-in registries: `openai_skills` and `anthropic_skills`

## 1. Short Overview

- `agent_skill` packages one local or remote skill bundle rooted at `SKILL.md`
- `agent_profile` builds a portable profile artifact with skills plus required env var names
- `agent_runner` realizes that profile for `codex` or `claude_code`
- `skill_deps` imports remote skill archives and optionally exposes registry discovery

The default user flow is:

```bash
bazel build //agent:repo_dev_profile
bazel run //agent:codex_dev_doctor
bazel run //agent:codex_dev
```

That build/install/run path validates declared credentials, installs managed skills into the
native repo-local agent directory, and launches the agent from the repository root.

## 2. Batteries-Included Quickstart

Add `rules_agents` in `MODULE.bazel` and enable the built-in official skill registries:

```python
bazel_dep(name = "rules_agents", version = "0.1.0")

git_override(
    module_name = "rules_agents",
    remote = "https://github.com/jastice/rules_agents/",
    branch = "main",
)

skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.registries()

use_repo(skill_deps, "rules_agents_registry_index")
```

List the built-in registries and discover a skill:

```bash
bazel run @rules_agents_registry_index//:list_skills
bazel run @rules_agents_registry_index//:list_skills -- --agent=codex
```

Declare one local skill, one profile, and one runner in a `BUILD.bazel` file:

```python
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner", "agent_skill")

agent_skill(
    name = "repo_helper",
    root = "skills/repo_helper",
    srcs = glob(["skills/repo_helper/**"], exclude_directories = 1),
)

agent_profile(
    name = "repo_dev_profile",
    skills = [
        ":repo_helper",
    ],
)

agent_runner(
    name = "codex_dev",
    profile = ":repo_dev_profile",
    runner = "codex",
)
```

Then run:

```bash
bazel run //:codex_dev_doctor
bazel run //:codex_dev
```

What happens:

1. `list_skills` lets the repo browse the bundled registries before pinning a remote archive.
2. `doctor` checks the agent binary, required env vars, and packaged skill bundles.
3. `run` installs the declared skills under `.agents/skills`.
4. the launcher starts `codex` from the repository root.

For Claude Code, switch only the runner:

```python
agent_profile(
    name = "claude_dev_profile",
    skills = [":repo_helper"],
)

agent_runner(
    name = "claude_dev",
    profile = ":claude_dev_profile",
    runner = "claude_code",
)
```

Install path:

- `codex`: `<repo>/.agents/skills`
- `claude_code`: `<repo>/.claude/skills`

## 3. Full API Reference

### `agent_skill`

Packages one portable skill bundle rooted at `SKILL.md`.

```python
agent_skill(
    name = "bazel_debug",
    root = "skills/bazel_debug",
    srcs = glob(["skills/bazel_debug/**"], exclude_directories = 1),
)
```

Rules:

- `root` must be a normalized relative path
- `srcs` must stay under `root`
- the bundle must contain `SKILL.md` at its root
- packaged files preserve their paths relative to `root`

### `agent_profile`

Builds a portable profile artifact. It does not pick a runner by itself.

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        ":repo_helper",
        "@community_skills//:test_runner",
    ],
)
```

Generated targets:

- `:name`: buildable profile manifest artifact
- `:name_manifest`: alias to the same artifact

Profile manifest contents:

- `profile_name`
- `credential_env`
- `skills`
- `version`

### `agent_runner`

Realizes one profile for a concrete client.

```python
agent_runner(
    name = "codex_dev",
    profile = ":repo_dev_profile",
    runner = "codex",
)
```

Supported runners:

- `codex`
- `claude_code`

Generated targets:

- `:name`: default interactive entrypoint, alias to `:name_run`
- `:name_setup`: install/sync managed repo-local skill state
- `:name_run`: install then launch the runner
- `:name_doctor`: validate binary, credentials, and skill bundles without launching
- `:name_manifest`: machine-readable runner manifest

### `skill_deps`

Module extension for remote skill archives and registry discovery.

Remote archive setup:

```python
skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.remote(
    name = "community_skills",
    url = "https://github.com/org/bazel-skills/archive/abc123.tar.gz",
    strip_prefix = "bazel-skills-abc123",
)

use_repo(skill_deps, "community_skills")
```

Reference discovered targets from `agent_profile`:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        ":repo_helper",
        "@community_skills//:test_runner",
    ],
)
```

Archive synthesis rules:

- any directory containing `SKILL.md` becomes a target
- if the archive root contains `SKILL.md`, the root becomes a skill target named after the repo
- nested skill roots under an already discovered skill root are skipped

Registry discovery:

```python
skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.registries()

use_repo(skill_deps, "rules_agents_registry_index")
```

Useful commands:

```bash
bazel run @rules_agents_registry_index//:list_skills
bazel run @rules_agents_registry_index//:list_skills -- --agent=codex
bazel run @rules_agents//tools:update_registries
bazel run @rules_agents//tools:update_registries -- --apply
```

`update_registries` refreshes GitHub archive pins. Use `--catalog=tools/rules_agents/registries.json`
when you want to rewrite a repository-owned override file instead of the catalog in this repo.

## 4. Examples

Current example targets in this repository:

- `//agent:dev` -> alias to the example Codex runner
- `//agent:dev_doctor`
- `//agent:dev_manifest`
- `//agent:claude_dev` -> default Claude Code example without declared credential env
- `//agent:claude_dev_doctor`
- `//agent:claude_dev_manifest`
- `//agent:claude_dev_auth` -> optional Claude Code example with `credential_env = ["ANTHROPIC_API_KEY"]`

Example source declarations live in `examples/BUILD.bazel`:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [":repo_helper"],
)

agent_runner(
    name = "codex_dev",
    profile = ":repo_dev_profile",
    runner = "codex",
)
```

Useful local verification:

```bash
bazel test //tests:all
tests/remote_skill_deps_test.sh
tests/missing_skill_md_test.sh
```

Behavior to rely on:

- runner setup installs only tool-managed directories under the native skill root
- switching profiles for the same runner replaces previously managed skills for that agent root
- declared credential env vars are required and forwarded unchanged to the launched process
- launch always runs from the repository root
