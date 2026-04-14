# Quickstart

Use this path when the goal is: install `rules_agents` into a Bazel repo, get one working
skill, and verify the setup with the fewest decisions.

## 1. Add `rules_agents` to `MODULE.bazel`

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
    skill_path_prefix = "skills",
)

use_repo(skill_deps, "rules_agents_registry_index", "rules_agents_skills")
```

Why both calls:

- `skill_deps.registries()` enables registry discovery commands.
- `skill_deps.remote(...)` makes this repo's published skill bundle usable in `agent_profile(...)`.
- `strip_prefix` is not needed for standard GitHub archives; `rules_agents` auto-detects the
  archive wrapper directory and keeps `skill_path_prefix = "skills"` stable across branch, tag,
  and commit tarballs.

## 2. Declare one profile and one runner in `BUILD.bazel`

```python
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner")

agent_profile(
    name = "dev_profile",
    skills = ["@rules_agents_skills//:rules_agents"],
)

agent_runner(
    name = "dev",
    profile = ":dev_profile",
    runner = "codex",  # or "claude_code"
)
```

Use `codex` for repo-local installs under `.agents/skills`.
Use `claude_code` for repo-local installs under `.claude/skills`.

## 3. Verify before launching

```bash
bazel run //:dev_doctor
```

What `doctor` checks:

1. the selected agent binary resolves
2. required `credential_env` variables are present
3. declared skills package correctly and can be installed into the managed repo-local root

## 4. Optional follow-up checks

```bash
bazel build //:dev_manifest
bazel run //:dev -- --help
```

- `:dev_manifest` verifies manifest generation without launching.
- `:dev -- --help` confirms the launch path after `doctor` is clean.

## 5. What to do next

- To browse and add more skills, read `usage.md`.
- To add repo-local skills, start with `agent_skill(...)` from `usage.md`.
- Add `credential_env` only when a skill or repo tool explicitly requires forwarded env vars.
