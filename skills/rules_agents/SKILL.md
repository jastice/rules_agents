---
name: rules_agents
description: Use when installing rules_agents into a Bazel repo, verifying the setup, discovering skills from registries or custom repos, adding local skills, and configuring agent profiles and runners.
---

# rules_agents

Use this skill for repo-scoped agent setup in Bazel. Keep the flow narrow:

- supported runners: `codex`, `claude_code`
- repo-local install roots: `.agents/skills`, `.claude/skills`
- public API: `agent_skill`, `agent_profile`, `agent_runner`, `skill_deps`

## Discoverable Parts

1. For the fastest install-and-verify path, read `references/quickstart.md`.
2. For ongoing usage, read `references/usage.md`.

## Working Rules

- Prefer the quickstart path first unless the user already has a profile and just needs a specific usage flow.
- Use registry discovery only to browse available skills. A discovered skill becomes usable only after adding the printed `skill_deps.remote(...)` snippet and `use_repo(...)`.
- Use `agent_skill(...)` for repo-local skills and `skill_deps.remote(...)` for remote archives.
- Use `agent_profile(...)` to collect skills and required credential env vars.
- Use `agent_runner(...)` to pick `codex` or `claude_code` and expose `:name`, `:name_doctor`, `:name_setup`, `:name_run`, and `:name_manifest`.

## Verification Defaults

- `bazel run //:dev_doctor` verifies binary resolution, required env vars, and packaged skills without launching.
- `bazel build //:dev_manifest` verifies manifest generation.
- `bazel run //:dev -- --help` is a safe launch-path check once `doctor` passes.
