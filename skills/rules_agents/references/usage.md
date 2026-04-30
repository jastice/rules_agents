# Usage

Use this guide after the quickstart is working or when the user already has `rules_agents`
installed and needs a specific configuration flow.

Current platform scope: Linux and macOS are supported. Windows is not supported yet.

## Using the Bundled `rules_agents` Skill

If you only want the maintained skill bundle that ships with the resolved `@rules_agents`
module, no registry or remote archive is required. This works whether the module came from
BCR or from the quickstart source override. Reference the bundled target directly:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        "@rules_agents//skills:rules_agents",
    ],
)
```

Use `skill_deps.remote(...)` only when you want skills from another archive or want to
materialize skills discovered through a registry listing.

## Discovering Skills from Registries

Enable registry discovery in `MODULE.bazel`:

```python
skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.registries()

use_repo(skill_deps, "rules_agents_registry_index")
```

List available skills:

```bash
bazel run @rules_agents_registry_index//:list_skills
bazel run @rules_agents_registry_index//:list_skills -- --agent=codex
bazel run @rules_agents_registry_index//:list_skills -- --registry=openai_skills
bazel run @rules_agents_registry_index//:list_skills -- --skill=python
bazel run @rules_agents_registry_index//:list_skills -- --json
```

The listing output tells you:

- the skill description from frontmatter
- the online source link
- the `skill_deps.remote(...)` and `use_repo(...)` snippet needed to import that repo
- the Bazel target label to reference from `agent_profile(...)`

## Installing a Skill from a Registry

After picking a discovered skill, add the printed snippet to `MODULE.bazel`. Example:

```python
skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.remote(
    name = "openai_skills",
    url = "https://github.com/openai/skills/archive/0123456789abcdef.tar.gz",
)

use_repo(skill_deps, "openai_skills")
```

Then reference it from a profile:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        "@openai_skills//:python",
    ],
)
```

`skill_deps.registries(...)` is only for discovery. `skill_deps.remote(...)` is what actually
makes the external skill repo available to Bazel targets.

For standard GitHub-style tarballs, `rules_agents` auto-detects the archive wrapper directory,
so `strip_prefix` is usually unnecessary. Keep it only as an override for unusual archive
layouts.

## Installing a Skill from a Custom Repo

For a remote archive that is not part of a registry, add it directly:

```python
skill_deps = use_extension("@rules_agents//rules_agents:extensions.bzl", "skill_deps")

skill_deps.remote(
    name = "community_skills",
    url = "https://github.com/org/skills/archive/abc123.tar.gz",
)

use_repo(skill_deps, "community_skills")
```

Then add the synthesized target to a profile:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        "@community_skills//:test_runner",
    ],
)
```

Archive synthesis rules:

- any directory containing `SKILL.md` becomes a target
- if the archive root contains `SKILL.md`, the root becomes a skill target named after the repo
- nested skill roots under an already discovered skill root are skipped

## Adding a Local Skill

Declare the skill in a repo `BUILD.bazel` file:

```python
load("@rules_agents//rules_agents:defs.bzl", "agent_profile", "agent_runner", "agent_skill")

agent_skill(
    name = "repo_helper",
    root = "skills/repo_helper",
    srcs = glob(["skills/repo_helper/**"], exclude_directories = 1),
)
```

Then add it to a profile:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        ":repo_helper",
        "@rules_agents//skills:rules_agents",
    ],
)
```

Local skill rules:

- `root` must be a normalized relative path
- `srcs` must stay under `root`
- the bundle must contain `SKILL.md` at the bundle root
- packaged files preserve their paths relative to `root`

## Configuring Profiles

Use `agent_profile(...)` to define the reusable skill set and required env vars:

```python
agent_profile(
    name = "repo_dev_profile",
    skills = [
        ":repo_helper",
        "@community_skills//:test_runner",
    ],
    credential_env = [
        "OPENAI_API_KEY",
    ],
)
```

Guidance:

- keep one profile per skill set, not per agent
- omit `credential_env` unless a skill or repo workflow explicitly requires that variable
- the profile artifact is buildable as `:name` or `:name_manifest`

## Running Agents

Use `agent_runner(...)` to realize a profile for one supported client:

```python
agent_runner(
    name = "codex_dev",
    profile = ":repo_dev_profile",
    runner = "codex",
)

agent_runner(
    name = "claude_dev",
    profile = ":repo_dev_profile",
    runner = "claude_code",
)
```

Generated targets:

- `:name`: default interactive entrypoint
- `:name_doctor`: validate binary, credentials, and skill bundles without launching
- `:name_setup`: install or sync managed repo-local skill state
- `:name_run`: install then launch the runner
- `:name_manifest`: machine-readable runner manifest

Install destinations:

- `codex`: `<repo>/.agents/skills`
- `claude_code`: `<repo>/.claude/skills`

Typical flow:

```bash
bazel build //agent:repo_dev_profile
bazel run //agent:codex_dev_doctor
bazel run //agent:codex_dev
```

Or for Claude Code:

```bash
bazel build //agent:repo_dev_profile
bazel run //agent:claude_dev_doctor
bazel run //agent:claude_dev
```

## Registry Overrides and Pin Updates

To add repo-specific registries or replace the defaults, point `skill_deps.registries(...)`
at a workspace-owned config:

```python
skill_deps.registries(
    config = "//tools/rules_agents:registries.json",
    mode = "extend",  # or "replace"
)
```

To check for newer registry pins:

```bash
bazel run @rules_agents//tools:update_registries
bazel run @rules_agents//tools:update_registries -- --registry=openai_skills
bazel run @rules_agents//tools:update_registries -- --apply
```
