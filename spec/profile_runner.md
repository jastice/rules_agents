# rules_agents

Profile / Runner Split Proposal

Status: draft for review

## 1. Summary

This document proposes splitting the current `agent_profile` concept into two layers:

- `agent_profile`: declares the repo-owned agent environment
- `agent_runner`: realizes that profile for a concrete client or wrapper

The goal is to let the repository own more of the user tooling without assuming that every
tool is a single CLI launched directly by `rules_agents`.

This is intended as a successor design direction, not an immediate change to the current
implemented v1 behavior in `spec/v1.md`.

## 2. Problem

The current v1 API combines two distinct concerns inside `agent_profile`:

1. declaring what should be active for an agent session
2. deciding how that environment is installed, synchronized, and launched

That works for direct CLI integrations such as `codex` and `claude_code`, where the tool:

- has a known repo-local skill directory
- can be launched from the repository root
- discovers repo-local state in a predictable way

It becomes limiting for tools such as editor wrappers or orchestrators, for example:

- tools that are not primarily launched by `rules_agents`
- tools that orchestrate multiple underlying agents
- tools that consume generated workspace state rather than native skill directories
- tools where `start` is optional or not meaningful

The repository should still be able to own those tools. The abstraction needs to separate
environment declaration from runtime realization.

## 3. Goals

- let the repository declare one portable agent environment independent of a specific client
- preserve repo ownership over agent tooling, including wrappers and orchestrators
- keep the public API small and boring
- support direct CLI clients and non-launch-first adapters with the same core model
- preserve machine-readable manifests as the contract between declaration and runtime
- keep packaging, manifest generation, installation or sync, launch, and adapter logic distinct

## 3.1 End-to-end flow

The intended flow for this model is:

1. build an `agent_profile` target
2. produce a profile artifact
3. run an `agent_runner` setup target
4. deploy or synchronize runner-specific state into repo-local config
5. run an `agent_runner` run target
6. start the agent frontend when that runner supports launching

This is the key mental model:

- `agent_profile` is a buildable declaration target
- `agent_runner` setup realizes that declaration in a concrete runtime
- `agent_runner` run enters the interactive frontend

## 4. Non-goals

- designing a full plugin or provider ecosystem
- supporting every future client in this document
- specifying MCP, secrets, or binary installation in detail here
- inventing a generic multi-agent framework in one step

## 5. Proposed public API

The proposed public API is:

- `agent_skill`
- `agent_profile`
- `agent_runner`
- `skill_deps`

### 5.1 `agent_skill`

Unchanged in spirit from v1.

Responsibility:

- package one portable skill bundle rooted at `SKILL.md`

### 5.2 `agent_profile`

`agent_profile` becomes a pure declaration of the repo-owned agent environment.

Responsibility:

- aggregate declared skills
- declare required credential environment variables
- later aggregate other portable environment inputs such as MCP declarations
- emit a canonical machine-readable profile manifest

Important property:

- `agent_profile` does not imply a specific client, binary, or launcher
- `agent_profile` is a buildable target that produces a reusable artifact

Suggested shape:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        ":repo_helper",
        ":hello_world",
    ],
    credential_env = [
        "OPENAI_API_KEY",
    ],
)
```

### 5.3 `agent_runner`

`agent_runner` binds one `agent_profile` to a concrete runtime adapter.

Responsibility:

- consume the profile manifest
- project it into client-specific native state
- validate runtime requirements
- support `doctor`, `setup`, and `run` when applicable

Suggested shape:

```python
agent_runner(
    name = "codex_dev",
    runner = "codex",
    profile = ":repo_dev_profile",
)

agent_runner(
    name = "claude_dev",
    runner = "claude_code",
    profile = ":repo_dev_profile",
)
```

The name `agent_runner` is intentional. Some integrations launch a binary, while others only
sync workspace state or configure an orchestrator. The abstraction should not imply that every
adapter is nothing more than an executable path.

## 5.4 Build / setup / run split

The proposal deliberately separates three moments:

- build time: produce the profile artifact
- setup time: deploy runner-specific state into the repository workspace
- run time: launch or attach to the runner frontend

In practical terms:

- `agent_profile` owns build-time declaration
- `agent_runner` owns setup-time realization
- `agent_runner` owns run-time entry when supported

## 6. Core model

The central distinction is:

- `agent_profile` answers: what should be active?
- `agent_runner` answers: how is that profile realized here?

Rule of thumb:

- if a field should survive swapping one client for another, it belongs on `agent_profile`
- if a field changes with the concrete client or wrapper, it belongs on `agent_runner`

### 6.1 What belongs on `agent_profile`

Portable environment intent:

- `skills`
- `credential_env`
- later: MCP declarations
- later: repo-scoped instructions, roles, or subagent definitions if they are meant to be
  projected into multiple runners

### 6.2 What belongs on `agent_runner`

Runner-specific realization behavior:

- runner type, for example `codex`, `claude_code`, `cursor`, or `air`
- binary resolution and invocation
- native install root or sync destination
- adapter-specific projection logic
- launch behavior
- runner-specific options

## 7. Manifest boundaries

This proposal keeps manifests as the stable seam.

### 7.1 Profile manifest

Produced by `agent_profile`.

Responsibility:

- encode the portable, runner-agnostic environment contract

This artifact is intended to be buildable with `bazel build`.

Suggested schema v1 of this split:

```json
{
  "version": 1,
  "profile_name": "repo_dev_profile",
  "credential_env": ["OPENAI_API_KEY"],
  "skills": [
    {
      "skill_id": "main__examples__repo_helper",
      "logical_name": "repo_helper",
      "bundle_runfiles_path": "..."
    }
  ]
}
```

Properties:

- no runner-specific fields
- no install destination fields
- no secret values

### 7.2 Runner manifest

Produced by `agent_runner`, either as a real file or as an internal rendered view.

Responsibility:

- combine the profile manifest with runner-specific realization details

Suggested contents:

- profile manifest reference or inline data
- runner id
- derived managed directory names or sync destinations
- runner-specific capabilities
- adapter-specific settings required by runtime logic

This keeps the profile manifest portable while still allowing concrete runtime planning.

## 8. Generated targets

### 8.1 `agent_profile`

Suggested generated targets:

- `:name` — buildable profile artifact target
- `:name_manifest` — optional explicit alias for the profile manifest file

Behavior:

- `bazel build //...:name` produces the canonical profile artifact
- `agent_profile` does not directly generate launch targets

The important point is that the profile itself is a Bazel build product, not a runnable agent
session.

### 8.2 `agent_runner`

Suggested generated targets:

- `:name` — default interactive entrypoint, usually `run`
- `:name_doctor`
- `:name_setup`
- `:name_run`
- `:name_manifest`

Suggested behavior:

- `:name_setup` consumes the built profile artifact and deploys or synchronizes repo-local
  runner state
- `:name_run` performs setup first when required, then launches the client frontend if supported
- `:name` aliases `:name_run` for runners with launch semantics
- `:name` may alias `:name_setup` only for runners where no interactive run concept exists

This gives the public surface a concrete pipeline:

- profile builds
- runner sets up
- runner runs

## 9. Runner capabilities

Not every runner needs the same operational surface.

Suggested capability set:

- `doctor`
- `manifest`
- `setup`
- `run`

Examples:

- `codex`: `doctor`, `setup`, `run`
- `claude_code`: `doctor`, `setup`, `run`
- `cursor`: likely `doctor`, `setup`, maybe `run`
- `air`: likely `doctor`, `setup`, maybe `run`

Important design rule:

- `run` is a runner capability, not a required property of the overall model
- `setup` is the portable runtime action that every runner should support

That preserves repo ownership for tools that are configured or synchronized rather than
directly launched by `rules_agents`.

## 10. Direct CLI runners

For direct CLI runners, the current v1 shape maps cleanly:

### 10.1 Codex

- consume profile skill bundles
- install managed directories under `<repo>/.agents/skills`
- validate required credential env vars
- launch from repository root

### 10.2 Claude Code

- consume profile skill bundles
- install managed directories under `<repo>/.claude/skills`
- validate required credential env vars
- launch from repository root

In both cases:

- multiple runners may exist in Bazel
- only one runner is active at a time per native skill root if the adapter chooses exclusive
  managed installs

## 11. Wrapper or orchestrator runners

This split is mainly motivated by wrappers and orchestrators.

### 11.1 Cursor-like runners

A Cursor-like adapter may:

- consume the profile manifest
- project skills or instructions into workspace-local wrapper config
- validate required env vars
- expose `doctor` and `setup`
- optionally expose `run` if launching is meaningful

### 11.2 Air-like runners

An Air-like adapter may:

- consume one profile manifest
- map that profile into one or more underlying agent roles
- synchronize repo-local adapter state
- expose `doctor` and `setup`
- optionally expose `run`

The important point is that these still fit the same repo-owned model without pretending that
they are identical to a single native CLI.

## 12. Example usage

### 12.1 One profile, multiple runners

```python
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
    credential_env = [
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
    ],
)

agent_runner(
    name = "codex_dev",
    runner = "codex",
    profile = ":repo_dev_profile",
)

agent_runner(
    name = "claude_dev",
    runner = "claude_code",
    profile = ":repo_dev_profile",
)
```

### 12.2 Same profile, wrapper runner

```python
agent_runner(
    name = "air_dev",
    runner = "air",
    profile = ":repo_dev_profile",
)
```

The profile remains stable while the runtime binding changes.

### 12.3 Target flow example

```bash
bazel build //agent:repo_dev_profile
bazel run //agent:codex_dev_setup
bazel run //agent:codex_dev_run
```

Meaning:

1. build the profile artifact
2. deploy that profile into repo-local Codex state
3. launch the Codex frontend using that realized state

## 13. Migration from current v1

Current v1:

```python
agent_profile(
    name = "dev",
    agent = "codex",
    skills = [":repo_helper"],
    credential_env = ["OPENAI_API_KEY"],
)
```

Proposed direction:

```python
agent_profile(
    name = "dev_profile",
    skills = [":repo_helper"],
    credential_env = ["OPENAI_API_KEY"],
)

agent_runner(
    name = "dev",
    runner = "codex",
    profile = ":dev_profile",
)
```

Meaning:

- `//...:dev_profile` is the buildable profile artifact
- `//...:dev_setup` realizes that artifact for Codex
- `//...:dev_run` launches Codex using the realized repo-local state
- `//...:dev` may alias `//...:dev_run`

Possible compatibility strategies:

1. keep current `agent_profile(agent = ...)` as sugar for one profile plus one runner
2. add `agent_runner` and migrate examples first
3. eventually make `agent_profile` runner-agnostic only

Preferred direction:

- introduce `agent_runner`
- keep the old form only as a temporary compatibility shim if needed
- move examples and docs to the split model early

## 14. Why this is better

- keeps the core declaration portable
- preserves repo ownership over direct clients and wrappers
- avoids making launch semantics the center of the model
- keeps manifests as the contract between build-time and runtime layers
- allows future adapters without collapsing into an unstructured framework

## 15. Open questions for review

1. Should `agent_profile` remain strictly runner-agnostic, or should it still allow optional
   runner hints?
2. Should `agent_runner` support explicit `capabilities` declaration, or should capabilities be
   entirely adapter-defined?
3. Should `:name` on an `agent_runner` always mean `run`, even when `run` is only an attach or
   wrapper entrypoint rather than a direct process launch?
4. Should compatibility sugar from the current `agent_profile(agent = ...)` form exist at all?
5. Should wrapper runners be allowed to consume multiple profiles, or is one profile per runner
   the right starting point?

## 16. Recommendation

Adopt this split as the next architectural direction:

- `agent_profile` becomes the repo-owned environment contract
- `agent_runner` becomes the runner-specific realization layer

Do not implement every future adapter immediately. First use the split to clarify the model for:

- `codex`
- `claude_code`
- one representative wrapper or orchestrator

That is enough to validate the architecture without broadening into a general agent platform.
