# Quickstart

Use this path when the goal is: install `rules_agents` into a Bazel repo, get one working
skill, and verify the setup with the fewest decisions.

Current platform scope: Linux and macOS are supported. Windows is not supported yet.

## 1. Add `rules_agents` to `MODULE.bazel`

```python
bazel_dep(name = "rules_agents", version = "0.1.0")
```

That is enough for released usage from the published module.

## 2. Declare one profile and one runner in `BUILD.bazel`

```python
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner")

agent_profile(
    name = "dev_profile",
    skills = ["@rules_agents//skills:rules_agents"],
)

agent_runner(
    name = "dev",
    profile = ":dev_profile",
    runner = "codex",  # or "claude_code"
)
```

Use `codex` for repo-local installs under `.agents/skills`.
Use `claude_code` for repo-local installs under `.claude/skills`.

If you need unreleased repository changes instead of the published module, add this
development-only override to `MODULE.bazel`:

```python
git_override(
    module_name = "rules_agents",
    remote = "https://github.com/jastice/rules_agents/",
    branch = "main",
)
```

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
