# rules_agents

AI Agent Environment v1: Architecture, Scope, and Implementation Plan

## 1. Purpose

Build a small Bazel-based system that lets a repository define a local coding-agent setup and launch it with one command.

The v1 problem statement is narrow:

- choose an agent client: `codex` or `claude_code`
- declare a set of skills in Bazel — from local sources or remote git archives
- provision those skills into the agent's native filesystem layout
- pass through a declared set of credentials from the caller environment
- start the agent from the repository with that configuration active

This is not "Bazel for all AI tooling". It is a repo-owned launcher and installer for local and remote agent skills.

## 2. Product goal

After a user installs a supported agent client separately, they should be able to run one Bazel target and get a working agent session with the repo's declared skills active.

Desired user experience:

```bash
bazel run //ai:dev
```

Expected result:

1. the launcher resolves the requested agent binary
2. the launcher validates required environment variables
3. the launcher installs or refreshes generated skills in the agent's native project-local skills directory
4. the launcher starts the agent in the repository root

## 3. Why this is enough for v1

This MVP proves the core thesis:

- the repo can own the agent choice
- the repo can own reusable agent capabilities
- Bazel can turn that declaration into a reproducible local setup

That is enough to validate the product direction without pulling in MCP, client config synthesis, binary installation, or secret management.

Remote skill resolution is in scope for v1 because it is the mechanism that makes skills shareable across repos — the core ecosystem thesis. Registry infrastructure is not.

## 4. Explicit non-goals

Do not build any of the following in v1:

- Bazel Central Registry publication or a custom registry
- versioned skill resolution (semver, tags) — commit-pinned archives only
- MCP server provisioning or wiring
- auto-installing Codex or Claude Code
- secret storage, secret files, or credential minting
- general client configuration beyond what is strictly needed for skills
- support for more than two agents
- support for IDE plugins, desktop apps, cloud agents, or hosted environments
- global per-user skill installation
- Windows-specific behavior beyond code structure that could support it later

## 5. External constraints from current client behavior

These assumptions are the reason v1 should use project-local skill installation instead of trying to own global config.

### 5.1 Codex

Current Codex docs indicate:

- user config lives under `~/.codex/config.toml`
- project config can live under `.codex/config.toml`
- Codex supports `AGENTS.md` for persistent instructions
- Codex skills are filesystem-based directories with `SKILL.md`
- repo-local skills live in `.agents/skills`
- personal skills live in `$HOME/.agents/skills`
- Codex state can be redirected with `CODEX_HOME`, but that is about config and state, not the repo-local skill directory

Implication for v1:

- do not try to synthesize or own `~/.codex`
- do not depend on `CODEX_HOME` for skill installation
- install skills into `<repo>/.agents/skills/...`
- launch Codex from the repo root and let it discover repo-local skills normally

### 5.2 Claude Code

Current Claude docs indicate:

- Claude Code filesystem settings include `CLAUDE.md` and `.claude/CLAUDE.md`
- Claude Code skills are filesystem-based directories under `.claude/skills/*/SKILL.md`
- the Claude Agent SDK can load filesystem-based settings from project sources

Implication for v1:

- do not try to synthesize or own a user-global Claude home/config area
- install skills into `<repo>/.claude/skills/...`
- launch Claude Code from the repo root and let it discover project-local skills normally

## 6. Core design decision

**Use project-local native skill directories. Do not use user-global installation in v1.**

Reasons:

- repo scope is the product goal
- no dependence on fragile vendor home-directory state
- no global pollution across repositories
- no need to copy or re-home existing auth/config files
- matches how both supported agents already discover project-local skills

Trade-off:

- the launcher will write generated files into the working tree under agent-native hidden directories

This is acceptable in v1. The tool should manage only its own generated subdirectories and avoid touching unmanaged user files.

## 7. v1 public API

Use a small surface area.

### 7.0 Bootstrapping `agent_env` itself

`agent_env` is not on BCR in v1. Consumers pull it directly via a MODULE.bazel override:

```python
bazel_dep(name = "agent_env")
archive_override(
    module_name = "agent_env",
    urls = ["https://github.com/you/agent_env/archive/COMMIT.tar.gz"],

    strip_prefix = "agent_env-COMMIT",
)
```

Or via git:

```python
git_override(
    module_name = "agent_env",
    remote = "https://github.com/you/agent_env",
    commit = "...",
)
```

This is the same resolution model used for remote skills. The tool is self-similar.

### 7.1 `agent_skill`

Represents one portable skill bundle.

Suggested macro/rule shape:

```python
agent_skill(
    name = "bazel_debug_skill",
    root = "skills/bazel_debug",
    srcs = glob(["skills/bazel_debug/**"], exclude_directories = 1),
)
```

Semantics:

- `root` is the logical root of the skill bundle
- the bundle must contain `SKILL.md` at the bundle root
- all files under `root` are packaged and preserved relative to that root
- the bundle may contain support files, scripts, examples, and references

Validation requirements:

- fail if no `SKILL.md` exists at the bundle root
- fail if more than one file maps to the same relative output path
- fail if `srcs` escape the declared root

### 7.2 `agent_profile`

Represents one runnable local agent environment.

Suggested macro shape:

```python
agent_profile(
    name = "dev",
    agent = "codex",  # or "claude_code"
    skills = [
        ":bazel_debug_skill",
    ],
    credential_env = [
        "OPENAI_API_KEY",
    ],
)
```

Semantics:

- `agent` is an enum with exactly two values in v1: `codex`, `claude_code`
- `skills` is a list of `agent_skill` targets
- `credential_env` is a list of environment variable names to require and pass through unchanged to the launched process

Generated targets:

- `//ai:dev` — install + start
- `//ai:dev_doctor` — validate without launching
- `//ai:dev_manifest` — machine-readable manifest artifact

Implementation note:

Use a **macro** for the public API.

### 7.3 `skill_deps` module extension

Declared in the consumer's `MODULE.bazel`. Resolves remote skill archives by URL and
SRI hash. Synthesizes `agent_skill` targets by convention from the downloaded content.

```python
# MODULE.bazel
bazel_dep(name = "agent_env")
# ... override for agent_env itself (see 7.0) ...

skill_deps = use_extension("@agent_env//:extensions.bzl", "skill_deps")
skill_deps.remote(
    name = "community_skills",
    url = "https://github.com/org/bazel-skills/archive/abc123def456.tar.gz",
    strip_prefix = "bazel-skills-abc123def456",  # optional
)
use_repo(skill_deps, "community_skills")
```

The `remote` tag class fields:

- `name` — Bazel repo name; used as `@name//:skill_target`
- `url` — archive URL; GitHub, internal git server, or any HTTP(S) source
- `strip_prefix` — optional top-level directory to strip from the archive

Synthesized targets are named after the skill directory:

```python
# after the above, in any BUILD file:
agent_profile(
    skills = [
        ":local_skill",
        "@community_skills//:bazel_debug",
        "@community_skills//:test_runner",
    ],
    ...
)
```

The remote repo requires no BUILD files and no knowledge of these rules.
Any directory at the archive root containing a `SKILL.md` becomes a target. The macro can create a private manifest-producing rule and two runnable wrapper targets. Do not force a single Bazel rule to pretend it can conveniently expose multiple public executables.

## 8. Internal architecture

Split the implementation into four layers.

### 8.1 Layer A: skill packaging

Responsibility:

- turn source files into a normalized skill bundle artifact
- validate bundle shape
- expose metadata to downstream rules

Suggested provider:

`AgentSkillInfo`

Suggested fields:

- `bundle_dir`: tree artifact containing the packaged skill
- `logical_name`: stable name derived from label name
- `src_root`: original declared root for diagnostics

The bundle artifact should contain:

- `SKILL.md` at bundle root
- all additional files under the same relative paths as the source tree

### 8.2 Layer B: profile manifest generation

Responsibility:

- aggregate skills and static profile settings
- render a canonical JSON manifest consumed by the runtime launcher

Suggested private rule:

`_agent_profile_manifest`

Manifest schema v1:

```json
{
  "version": 1,
  "profile_name": "dev",
  "agent": "codex",
  "credential_env": ["OPENAI_API_KEY"],
  "skills": [
    {
      "logical_name": "bazel_debug_skill",
      "bundle_runfiles_path": "...",
      "managed_dir_name": "__bazel_agent_env__dev__bazel_debug_skill"
    }
  ]
}
```

Rules:

- `managed_dir_name` must be deterministic
- no secret values may appear in the manifest
- the manifest must contain runfiles-resolvable paths to packaged skill bundles

### 8.3 Layer C: runtime launcher

Responsibility:

- resolve the actual agent binary on the user's machine
- validate credentials
- install generated skills into the agent's native project-local skill root
- launch the agent

Implementation recommendation:

- implement as a small Python binary for portability and file-manipulation sanity
- use Bazel runfiles support to locate bundle artifacts and the manifest

Runtime subcommands:

- `doctor`
- `install`
- `start`

`start` should call `install` first, then exec the agent.

### 8.4 Layer D: module extension and remote skill synthesis

Responsibility:

- implement the `skill_deps` module extension in `extensions.bzl`
- define the `remote` tag class
- implement the underlying repository rule that downloads archives and generates a
  BUILD.bazel synthesizing `agent_skill` targets by convention

Convention for synthesis:

- walk the archive root (after optional `strip_prefix`)
- any directory containing a `SKILL.md` file at its root becomes one `agent_skill` target
- target name = directory name
- nested skill directories (skills within skills) are not supported in v1

The synthesized BUILD.bazel is an implementation detail. Consumers reference targets
only by label.

### 8.5 Layer E: agent adapters

Responsibility:

- encapsulate the agent-specific differences that still exist in v1

Use a simple internal table, not a public rule.

Suggested adapter contract:

- `agent_id`
- `binary_override_env`
- `binary_candidates`
- `project_skill_root(workspace_root)`
- `display_name`

Suggested v1 mapping:

- `codex`
  - project skill root: `<workspace>/.agents/skills`
  - binary override env: `CODEX_BIN`
- `claude_code`
  - project skill root: `<workspace>/.claude/skills`
  - binary override env: `CLAUDE_CODE_BIN`

`binary_candidates` may start with a short candidate list and can be refined later. The override env var must take precedence over any PATH lookup.

## 9. Skill installation model

### 9.1 Install location

The launcher must install only into a managed namespace under the native skill root.

Examples:

- Codex: `<repo>/.agents/skills/__bazel_agent_env__dev__bazel_debug_skill/`
- Claude Code: `<repo>/.claude/skills/__bazel_agent_env__dev__bazel_debug_skill/`

Reason:

- avoid collisions with user-authored native skills
- enable deterministic cleanup
- allow multiple Bazel-managed profiles to coexist in one repo

Important detail:

The model-visible skill name comes from `SKILL.md`, not from the directory name. The managed directory name may therefore be prefixed for isolation.

### 9.2 Install behavior

On every `install` or `start`:

1. resolve the native skill root for the selected agent
2. create the root if missing
3. for each declared skill:
   - delete any existing managed directory for that skill/profile
   - copy the packaged bundle into the managed directory
4. remove stale managed directories belonging to this profile that are no longer declared
5. write a small profile-local manifest file for diagnostics and cleanup

Suggested cleanup manifest location:

- Codex: `<repo>/.agents/skills/.bazel_agent_env_dev.json`
- Claude Code: `<repo>/.claude/skills/.bazel_agent_env_dev.json`

Suggested cleanup manifest contents:

- profile name
- agent id
- installed managed directory names
- install timestamp
- tool version

### 9.3 Conflict policy

The launcher must never delete or overwrite directories it does not own.

Rules:

- only delete directories listed in the last cleanup manifest for the same profile, or directories whose names match the managed prefix for the same profile
- if a destination directory exists but is not managed by this tool, fail with a clear error

## 10. Credential handling

Credential handling in v1 is deliberately narrow.

### 10.1 Contract

- credentials are declared as environment variable names in `credential_env`
- the launcher checks that each name is present in the parent environment
- the launcher passes those variables through unchanged to the child process
- the launcher never writes credential values to disk
- the launcher never writes credential values into the Bazel manifest

### 10.2 What v1 does not do

- no keychain integration
- no `.env` parsing
- no secret file generation
- no login automation
- no provider-specific auth flows

### 10.3 Codex-specific note

Codex may still rely on its own existing login/auth state for interactive use. v1 does not provision that state. The pass-through env mechanism is generic and useful for future client options and skill-side tooling, but it is not a substitute for full vendor login management.

## 11. Start behavior

`bazel run //ai:dev -- <extra args>` should work.

Runtime contract for `start`:

1. locate workspace root
2. load profile manifest from runfiles
3. resolve agent binary
4. validate required env vars
5. install or refresh managed skills
6. `execve` the agent binary with:
   - current working directory = workspace root
   - environment = current environment plus the allowlisted pass-through vars
   - argv = resolved binary + forwarded user args

Important:

- do not spawn a long-lived wrapper process if it can be avoided; replace the launcher process with the agent process after setup
- do not invent agent-specific flags unless required later

## 12. Doctor behavior

`doctor` is required in v1.

Runtime contract for `doctor`:

- print selected profile and agent
- print resolved workspace root
- print native install root
- print whether the agent binary was found and where
- validate every skill bundle contains `SKILL.md`
- optionally parse `SKILL.md` front matter enough to confirm the presence of `name` and `description`
- print which credentials are required and whether each is set
- print the managed install directories that would be written
- exit nonzero on any failure

`doctor` must not modify the workspace.

## 13. Workspace root resolution

Preferred runtime rule:

- use `BUILD_WORKSPACE_DIRECTORY` if present
- otherwise fall back to the current working directory

Then normalize to an absolute real path.

The launcher should fail fast if the computed workspace root does not look like a repository root.

## 14. Implementation plan

Implement in this order.

### Step 1: Define package layout

Create the skeleton:

```text
agent_env/
  defs.bzl
  private/
    skill_rule.bzl
    profile_manifest_rule.bzl
    providers.bzl
  runtime/
    launcher.py
    runfiles.py   # or Bazel runfiles helper usage
  examples/
    BUILD.bazel
    skills/
```

Deliverable:

- empty but wired package structure

### Step 2: Implement `AgentSkillInfo` and `agent_skill`

Tasks:

- define the provider
- package `srcs` under `root` into a tree artifact
- validate that `SKILL.md` exists at bundle root
- expose the tree artifact and logical name

Acceptance criteria:

- a sample skill builds successfully
- malformed skill input fails with a clear error

### Step 3: Implement manifest generation

Tasks:

- define manifest schema v1
- implement private manifest rule that aggregates skills and `credential_env`
- emit a JSON file

Acceptance criteria:

- the JSON manifest is deterministic
- manifest contains no secrets
- manifest paths can be resolved from the runtime launcher via runfiles

### Step 4: Implement runtime launcher with `doctor`

Tasks:

- parse args: `doctor`, `install`, `start`
- load manifest from runfiles
- resolve workspace root
- resolve agent binary via override env then PATH candidates
- validate `credential_env`
- implement `doctor` output

Acceptance criteria:

- `doctor` works with fake agent binaries in tests
- missing binary and missing credentials both produce clear failures

### Step 5: Implement installation logic

Tasks:

- compute native skill root from agent adapter
- compute managed directory names
- copy packaged skill trees into the workspace
- write cleanup manifest
- remove stale managed directories for the current profile
- enforce unmanaged conflict policy

Acceptance criteria:

- repeated runs are idempotent
- removed skills are cleaned up
- unmanaged directories are preserved

### Step 6: Implement `start`

Tasks:

- call install
- forward tail args after `--`
- exec the resolved agent binary from the repo root

Acceptance criteria:

- fake binary sees correct cwd
- fake binary sees forwarded env vars and forwarded args

### Step 6b: Implement `skill_deps` module extension

Tasks:

- define `skill_deps` module extension in `extensions.bzl`
- implement `remote` tag class with `name`, `url`, and optional `strip_prefix`
- implement repository rule that downloads the archive and synthesizes `agent_skill`
  targets by convention (any directory containing `SKILL.md`)
- generate a BUILD.bazel in the external repo exposing one `agent_skill` target per
  discovered skill directory, named after the directory
- validate `SKILL.md` presence and required frontmatter fields at synthesis time

Acceptance criteria:

- a remote archive downloads and skills are synthesized by convention; synthesized targets are usable as `@name//:skill_dir_name`
- a directory without `SKILL.md` is silently ignored (not an error)
- synthesized targets are usable identically to locally declared `agent_skill` targets

### Step 7: Implement public `agent_profile` macro

Tasks:

- create private manifest target
- create public runnable targets for start and doctor
- create public manifest file target

Acceptance criteria:

- example BUILD file exposes `:dev`, `:dev_doctor`, and `:dev_manifest`

### Step 8: Add integration tests with fake binaries

Use fake `codex` and fake `claude_code` executables in tests.

Test cases:

1. Codex profile installs to `.agents/skills/...`
2. Claude profile installs to `.claude/skills/...`
3. missing `SKILL.md` fails
4. missing credential env var fails
5. stale managed skill directory is removed
6. unmanaged directory is preserved
7. extra args after `--` reach the child process
8. binary override env var wins over PATH lookup

### Step 9: Add one example repo target

Provide one working example for each agent.

Acceptance criteria:

- a new contributor can read the example BUILD file and understand how to use the rules

## 15. Example

### MODULE.bazel

```python
bazel_dep(name = "agent_env")
archive_override(
    module_name = "agent_env",
    urls = ["https://github.com/you/agent_env/archive/COMMIT.tar.gz"],

    strip_prefix = "agent_env-COMMIT",
)

skill_deps = use_extension("@agent_env//:extensions.bzl", "skill_deps")
skill_deps.remote(
    name = "community_skills",
    url = "https://github.com/org/bazel-skills/archive/abc123.tar.gz",

    strip_prefix = "bazel-skills-abc123",
)
use_repo(skill_deps, "community_skills")
```

### BUILD file

```python
load("@agent_env//:defs.bzl", "agent_profile", "agent_skill")

agent_skill(
    name = "bazel_debug_skill",
    root = "skills/bazel_debug",
    srcs = glob(["skills/bazel_debug/**"], exclude_directories = 1),
)

agent_profile(
    name = "dev",
    agent = "codex",
    skills = [
        ":bazel_debug_skill",
        "@community_skills//:test_runner",
    ],
    credential_env = ["OPENAI_API_KEY"],
)
```

Expected user commands:

```bash
bazel run //ai:dev_doctor
bazel run //ai:dev
bazel run //ai:dev -- --help
```

## 16. Acceptance criteria for the whole MVP

The MVP is done when all of the following are true:

1. a repo can declare a profile for `codex` or `claude_code`
2. declared skills are packaged by Bazel and installed into the agent's native project-local skill root
3. remote skills are resolved from a URL, verified by SRI hash, and installable identically to local skills
4. required env vars are validated and forwarded
5. `bazel run //...:profile` launches the selected agent from the repo root
6. `doctor` explains failures clearly
7. rerunning the launcher is safe and deterministic
8. the launcher never writes secret values to disk
9. the launcher never overwrites unmanaged skill directories

## 17. Future extensions intentionally deferred

If v1 works, the most natural v2 additions are:

- first-class `AGENTS.md` / `CLAUDE.md` support
- project-scoped agent config generation
- MCP server provisioning
- SRI integrity hash verification for remote skill archives
- versioned skill resolution (semver, tags) via BCR or custom registry
- agent binary installation helpers
- richer profile selection and per-profile overrides

Do not let any of these distort v1.

## 18. Final guidance to the implementing agent

Stay disciplined.

The right v1 is boring on purpose:

- one small public API
- two agent adapters
- skills only
- env pass-through only
- install + doctor + start

Do not abstract ahead of the problem. Do not invent a universal agent framework. Build the thin layer that proves Bazel can own a portable, repo-scoped local agent environment.

## 19. Reference links used to ground client-specific assumptions

- Codex config basics: https://developers.openai.com/codex/config-basic
- Codex advanced config: https://developers.openai.com/codex/config-advanced
- Codex AGENTS.md guide: https://developers.openai.com/codex/guides/agents-md
- Codex customization: https://developers.openai.com/codex/concepts/customization
- Codex skills: https://developers.openai.com/codex/skills
- Codex best practices: https://developers.openai.com/codex/learn/best-practices
- Claude skills overview: https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview
- Claude Agent SDK overview: https://docs.claude.com/en/docs/agent-sdk/overview
- Claude Agent SDK migration guide: https://docs.claude.com/en/docs/agent-sdk/migration-guide
