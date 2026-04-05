# rules_agents

`rules_agents` lets a repository declare a local coding-agent environment in Bazel and
launch it with one command.

The intended v1 experience is simple:

```bash
bazel run //agent:dev
```

From the repository's point of view, that command should:

1. choose a supported agent client: `codex` or `claude_code`
2. build the repo's declared profile artifact
3. set up the selected runner's repo-local state
4. validate required credential environment variables
5. launch the selected agent from the repository root

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
- `doctor`, `manifest`, `setup`, and `run` behavior for declared profiles and runners

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
- `agent_profile`: one buildable local profile artifact
- `agent_runner`: one runtime realization of a profile
- `skill_deps`: one module extension for bringing in remote skill archives

For the supported agents, managed skills are intended to be installed under:

- `codex`: `<repo>/.agents/skills`
- `claude_code`: `<repo>/.claude/skills`

The launcher manages only tool-owned subdirectories inside those native roots.
Multiple `agent_profile` targets can coexist in Bazel, but installs are active per agent root:
running one Codex profile replaces managed skills previously installed by another Codex profile,
and likewise for Claude Code profiles.

## Minimal Setup

For the smallest local-only setup, a repo only needs a local skill and one profile.

In a BUILD file:

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
    credential_env = ["OPENAI_API_KEY"],
)

agent_runner(
    name = "codex_dev",
    runner = "codex",
    profile = ":repo_dev_profile",
)
```

That gives the repo one buildable profile artifact plus one runnable Codex runner.

If the repo also wants to reuse skills published from another repository, add a module
extension entry in `MODULE.bazel`:

In `MODULE.bazel`, bring in `rules_agents` and any remote skill repos:

```python
bazel_dep(name = "rules_agents")

archive_override(
    module_name = "rules_agents",
    urls = ["https://github.com/you/rules_agents/archive/COMMIT.tar.gz"],
    strip_prefix = "rules_agents-COMMIT",
)

skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.remote(
    name = "community_skills",
    url = "https://github.com/org/bazel-skills/archive/abc123.tar.gz",
    strip_prefix = "bazel-skills-abc123",
)

use_repo(skill_deps, "community_skills")
```

In a BUILD file, declare one local skill and one profile:

```python
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner", "agent_skill")

agent_skill(
    name = "bazel_debug_skill",
    root = "skills/bazel_debug",
    srcs = glob(["skills/bazel_debug/**"], exclude_directories = 1),
)

agent_profile(
    name = "repo_dev_profile",
    skills = [
        ":bazel_debug_skill",
        "@community_skills//:test_runner",
    ],
    credential_env = ["OPENAI_API_KEY"],
)

agent_runner(
    name = "codex_dev",
    runner = "codex",
    profile = ":repo_dev_profile",
)
```

Then the intended user commands are:

```bash
bazel build //agent:repo_dev_profile
bazel run //agent:codex_dev_doctor
bazel run //agent:codex_dev_setup
bazel run //agent:codex_dev
bazel run //agent:codex_dev -- --help
```

## Skill Registry Workflow

Once skill registry discovery is implemented, the expected user workflow is:

1. enable registry discovery in `MODULE.bazel`
2. list available skills from the configured registries
3. copy the printed Bazel snippet for the skill you want
4. add the synthesized skill target to an `agent_profile`
5. optionally pin newer registry revisions with an explicit update command

### 1. Enable built-in registries

If you only want the registries that ship with `rules_agents`, add this to `MODULE.bazel`:

```python
skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.registries()
```

That enables the built-in curated registries and lets Bazel cache registry resolution through
its normal module-extension machinery.

### 2. List available skills

To list all skills from the active registries:

```bash
bazel run @rules_agents//tools:list_skills
```

To filter the output:

```bash
bazel run @rules_agents//tools:list_skills -- --agent=codex
bazel run @rules_agents//tools:list_skills -- --registry=openai_skills
bazel run @rules_agents//tools:list_skills -- --skill=python
bazel run @rules_agents//tools:list_skills -- --json
```

For each discovered skill, the command prints:

- the short description from `SKILL.md` frontmatter
- a link to the full online skill source
- the Bazel snippet needed to add that registry and the target label to reference

### 3. Add a discovered skill

Pick a skill from the listing output and copy the printed `MODULE.bazel` snippet.

For example, if the listing shows `@openai_skills//:python`, add the generated remote repo
declaration to `MODULE.bazel`:

```python
skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.remote(
    name = "openai_skills",
    url = "https://github.com/openai/skills/archive/0123456789abcdef.tar.gz",
    strip_prefix = "skills-0123456789abcdef",
)

use_repo(skill_deps, "openai_skills")
```

Then reference the discovered skill target from your profile:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        ":repo_helper",
        "@openai_skills//:python",
    ],
    credential_env = ["OPENAI_API_KEY"],
)
```

### 4. Add repo-specific registries or pin overrides

If your repository needs additional registries or different pinned revisions, create
`agent/registries.json` and tell `skill_deps` to use it.

In `MODULE.bazel`:

```python
skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.registries(
    config = "//agent:registries.json",
    mode = "extend",  # or "replace"
)
```

Use `mode = "extend"` to add repo-specific registries on top of the built-ins. Use
`mode = "replace"` if the repo wants to ignore the built-in curated set completely.

### 5. Explicitly update registry pins

Listing skills never changes registry pins. To check for newer upstream revisions, run the
separate maintainer command:

```bash
bazel run @rules_agents//tools:update_registries
```

To check one registry only:

```bash
bazel run @rules_agents//tools:update_registries -- --registry=openai_skills
```

To apply the proposed pin updates to the repo-owned registry config:

```bash
bazel run @rules_agents//tools:update_registries -- --apply
```

Or for one registry:

```bash
bazel run @rules_agents//tools:update_registries -- --registry=openai_skills --apply
```

After the pin changes, rerun `bazel run @rules_agents//tools:list_skills` or your normal
profile targets. Bazel handles cache invalidation and lockfile updates itself.

## Public API

The public API stays deliberately small:

- `agent_skill`
- `agent_profile`
- `agent_runner`
- `skill_deps`

The legacy runnable `agent_profile(agent = ...)` form is still supported as compatibility sugar.
The product and architecture source of truth for the implemented v1 slice is `spec/v1.md`.
The profile/runner split is described in `spec/profile_runner.md`.

## Target Model

The implemented profile/runner split is:

- `agent_profile`: a buildable profile artifact target
- `agent_runner`: a runtime target that sets up and runs a concrete client or wrapper

One example target flow is:

```bash
bazel build //agent:repo_dev_profile
bazel run //agent:codex_dev_setup
bazel run //agent:codex_dev_run
```

Meaning:

1. build the portable profile artifact
2. deploy or synchronize that artifact into repo-local runner state
3. launch the agent frontend using the realized state

Another example with a different runner would be:

```bash
bazel build //agent:repo_dev_profile
bazel run //agent:claude_dev_setup
bazel run //agent:claude_dev_run
```

In that proposed model, for example:

- `//...:repo_dev_profile` builds the profile artifact
- `//...:codex_dev_setup` realizes the profile for a concrete runner
- `//...:codex_dev_run` launches or attaches to the runner frontend
- `//...:codex_dev` aliases the default interactive entrypoint
- `//...:claude_dev_setup` and `//...:claude_dev_run` follow the same pattern for another runner

The older runnable `agent_profile(agent = ...)` form still exists for compatibility, but new
examples and targets use the split model above.

## Current Status

The current implementation provides:

- `agent_skill` packages local skill bundles and validates bundle shape
- `agent_profile` builds `:name` and `:name_manifest` profile artifacts
- `agent_runner` generates `:name`, `:name_setup`, `:name_run`, `:name_doctor`, and `:name_manifest`
- the runtime launcher supports `doctor`, `setup`, `run`, plus legacy `install` and `start`
- managed installs land under `.agents/skills` for Codex and `.claude/skills` for Claude Code
- `skill_deps.remote(...)` synthesizes remote `agent_skill` targets from archive contents
- examples exist for both supported agents

Repository verification today:

- `bazel test //tests:all`
- `tests/remote_skill_deps_test.sh`
- `tests/missing_skill_md_test.sh`

## Example Targets

- `//agent:dev`, `//agent:dev_doctor` alias the runnable Codex example runner targets
- `//agent:dev_manifest` aliases the Codex example profile artifact target (use `bazel build`, not `bazel run`)
- `//agent:claude_dev`, `//agent:claude_dev_doctor` alias the runnable Claude Code example runner targets
- `//agent:claude_dev_manifest` aliases the Claude Code example profile artifact target (use `bazel build`, not `bazel run`)
- `//examples:codex_dev_setup` and `//examples:claude_dev_setup` are example setup wrappers used by tests

## Repository Layout

- `MODULE.bazel`: Bazel module root
- `BUILD.bazel`: top-level Bazel package
- `agent/`: example-facing aliases for the runnable profiles
- `examples/`: working local skill and profile targets for both agents
- `tests/`: Bazel integration tests for the launcher flow
- `rules_agents/`: public Starlark surface
- `rules_agents/private/`: internal implementation
- `rules_agents/runtime/`: runtime launcher implementation
- `spec/`: product and design specs
- `spec/v1.md`: v1 product spec and implementation plan
- `spec/profile_runner.md`: draft proposal for splitting profile declaration from runner realization
