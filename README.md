# rules_agents

`rules_agents` is a Bazel-based system for defining a repository-local coding agent
environment and launching it with one command.

Current status: repository scaffold initialized.

## Goal

The intended user experience is:

```bash
bazel run //ai:dev
```

In v1, the system will let a repository:

- choose an agent client: `codex` or `claude_code`
- declare local or remote skills in Bazel
- install generated skills into the agent's native project-local layout
- validate and pass through selected credentials
- launch the configured agent from the repository root

## Repo layout

- `MODULE.bazel`: Bazel module root
- `ai/`: developer entrypoints, including `//ai:dev`
- `rules_agents/`: public Starlark surface
- `rules_agents/private/`: internal implementation details
- `rules_agents spec.md`: product and architecture notes

## Current entrypoint

The repo includes a bootstrap launcher:

```bash
bazel run //ai:dev
```

Right now it confirms the workspace is wired correctly and points at the next
implementation steps.
