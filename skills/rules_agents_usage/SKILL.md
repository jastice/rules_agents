---
description: Use when setting up rules_agents in a repository and you need the fastest working path plus examples for local skills, registry-discovered skills, and direct remote archives.
---

# rules_agents Usage

Use this flow when adding `rules_agents` to a repo.

## Fast Path

In `MODULE.bazel`:

```python
bazel_dep(name = "rules_agents", version = "0.1.0")

git_override(
    module_name = "rules_agents",
    remote = "https://github.com/jastice/rules_agents/",
    branch = "main",
)

skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.registries()
skill_deps.remote(
    name = "rules_agents_skills",
    url = "https://github.com/jastice/rules_agents/archive/refs/heads/main.tar.gz",
    strip_prefix = "rules_agents-main",
    skill_path_prefix = "skills",
)

use_repo(skill_deps, "rules_agents_registry_index", "rules_agents_skills")
```

In `BUILD.bazel`:

```python
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner")

agent_profile(
    name = "dev_profile",
    skills = ["@rules_agents_skills//:rules_agents_usage"],
)

agent_runner(
    name = "dev",
    profile = ":dev_profile",
    runner = "codex",  # or "claude_code"
)
```

Verify with one command:

```bash
bazel run //:dev_doctor
```

Default examples omit `credential_env`. Add it only if a skill or repo-local tool actually
needs an environment variable.

## Skill Sources

### Local repo skill

```python
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner", "agent_skill")

agent_skill(
    name = "repo_helper",
    root = "skills/repo_helper",
    srcs = glob(["skills/repo_helper/**"], exclude_directories = 1),
)

agent_profile(
    name = "dev_profile",
    skills = [
        ":repo_helper",
        "@rules_agents_skills//:rules_agents_usage",
    ],
)
```

### Registry-discovered skill

Browse first:

```bash
bazel run @rules_agents_registry_index//:list_skills -- --agent=codex
```

Then add the printed `skill_deps.remote(...)` snippet and reference the target from
`agent_profile`.

### Direct remote archive

```python
skill_deps.remote(
    name = "community_skills",
    url = "https://github.com/org/skills/archive/abc123.tar.gz",
    strip_prefix = "skills-abc123",
)

use_repo(skill_deps, "community_skills")
```

```python
agent_profile(
    name = "dev_profile",
    skills = [
        "@community_skills//:test_runner",
    ],
)
```

## Verification

- `bazel run //:dev_doctor` verifies the install path, binary resolution, skill bundles, and required env vars.
- `bazel build //:dev_manifest` checks manifest generation without launching the agent.
- `bazel run //:dev -- --help` verifies the launch path after `doctor` is clean.
