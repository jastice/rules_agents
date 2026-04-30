# Quickstart

Use this path when the goal is: install `rules_agents` into a Bazel repo, get one working
skill, and verify the setup with the fewest decisions.

Current platform scope: Linux and macOS are supported. Windows is not supported yet.

## 1. Add `rules_agents` to `MODULE.bazel`

Until `rules_agents` is available from the Bazel Central Registry, use a normal Bzlmod
dependency plus a source override:

```python
bazel_dep(name = "rules_agents", version = "0.1.0")

git_override(
    module_name = "rules_agents",
    remote = "https://github.com/jastice/rules_agents.git",
    branch = "main",
)
```

This gives the repo the usual `@rules_agents` module name without requiring BCR publication.
For a shared repository, replace `branch = "main"` with `commit = "<sha>"` when you choose
a revision. Once `rules_agents` is published to BCR, remove the `git_override(...)` block
and keep the versioned `bazel_dep(...)`.

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
