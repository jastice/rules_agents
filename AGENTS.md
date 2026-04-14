This file applies to the entire repository.

## What This Repo Is

`rules_agents` is a Bazel-based repo-scoped agent environment tool.

Current implemented scope:

- supported agent clients: `codex`, `claude_code`
- local skills declared in Bazel with `agent_skill(...)`
- remote skills synthesized from git archive downloads with `skill_deps.remote(...)`
- profile artifacts declared with `agent_profile(...)`
- concrete runners declared with `agent_runner(...)`
- repo-local installation into native agent directories
- validation and launch flows through `doctor`, `manifest`, `setup`, and `run`

Non-goals:

- general agent orchestration
- global user config management
- agent binary installation
- secret storage or secret minting

## Source Of Truth

- Treat current code, tests, and repository docs as the source of truth.
- Treat everything under `spec/` as historical reference unless the user explicitly says to adopt or follow a spec document.
- If a task explicitly references a spec doc, use only the relevant sections and say that the spec is being treated as design input for that task.

## Current Public Surface

The public Bazel API today is:

- `agent_skill`
- `agent_profile`
- `agent_runner`
- `skill_deps`

Current behavior:

- `agent_skill(...)` packages one portable skill bundle rooted at `SKILL.md`
- `agent_profile(...)` builds a reusable profile artifact and `:name_manifest`
- `agent_runner(...)` realizes a profile for one client and generates `:name`, `:name_setup`, `:name_run`, `:name_doctor`, and `:name_manifest`
- `skill_deps.remote(...)` synthesizes remote `agent_skill` targets from archive contents
- `skill_deps.registries(...)` enables registry discovery, not installation by itself

Do not describe this repo as only exposing `agent_skill`, `agent_profile`, and `skill_deps`. `agent_runner` is part of the implemented public surface.

## Core Constraints

Keep the implementation narrow and boring:

- install Codex skills under `.agents/skills`
- install Claude Code skills under `.claude/skills`
- support Linux and macOS; do not claim Windows support unless the code, docs, and tests are updated together
- rely on normal repository-root discovery for both clients
- do not depend on `CODEX_HOME` for Codex skill installation
- do not synthesize a global Claude home
- keep generated file ownership limited to tool-managed subdirectories
- preserve machine-readable manifest and doctor outputs

Avoid:

- speculative extension points
- broad abstractions over the current two-client model
- writing outside repo-managed install roots unless the task explicitly requires it

## BCR Readiness

Treat Bazel Central Registry compatibility as a maintained repo constraint, not a release-time cleanup.

Keep these repo facts true:

- the root `LICENSE` file exists and stays current; use Apache 2.0 unless the user explicitly changes licensing
- `MODULE.bazel` keeps an explicit `version` and `compatibility_level`
- public docs describe released-module consumption accurately
- platform claims stay explicit: Linux and macOS are supported, Windows is not supported yet
- examples and tests do not imply unsupported platforms work

When changing released-module behavior:

- prefer `bazel_dep(...)` as the default documented install path for released usage
- keep `git_override(...)`, branch tarballs, and other unreleased-source flows clearly marked as development-only paths
- do not make the README or quickstart depend on `main` branch artifacts as the primary path once a released path exists
- keep versioned snippets aligned with the current module version

When preparing or maintaining BCR publication:

- use immutable source archives for published versions; do not point BCR metadata at branches
- cut and use git tags for published versions
- keep any checked-in BCR test module representative of a real consumer flow
- keep BCR presubmit scope aligned with actual support; for now that means no Windows task

If the repo gains BCR metadata files or presubmit config, treat them like first-class source:

- update them whenever module version, source layout, supported Bazel versions, or platform scope changes
- keep them consistent with `README.md`, examples, and test coverage
- do not broaden the presubmit matrix beyond what the repo is actually validating

## Where To Look First

Key files and directories:

- `README.md`: current user-facing behavior and setup flow
- `rules_agents/defs.bzl`: public macro surface
- `rules_agents/private/`: packaging, manifest, runner, and registry implementation
- `rules_agents/runtime/`: runtime launcher code
- `examples/BUILD.bazel`: smallest working local examples for both supported agents
- `agent/BUILD.bazel`: top-level example aliases like `//agent:dev`
- `catalog/registries.json`: built-in registry catalog
- `bcr/presubmit.yml`: checked-in BCR presubmit template for this repo
- `bcr/test_module/`: checked-in consumer module for BCR-style validation
- `skills/rules_agents/`: the maintained repo skill bundle
- `skills/rules_agents/references/quickstart.md`: shortest onboarding path
- `skills/rules_agents/references/usage.md`: registry, local skill, profile, and runner usage
- `tests/`: integration and behavior tests

The old `skills/rules_agents_repo_guide` and `skills/rules_agents_usage` directories are no longer maintained skill bundles. Do not restore them as public skills without an explicit request.

## Working In This Repo

When making changes:

- prefer minimal, testable layers over abstraction
- fix root causes instead of papering over failing behavior
- keep naming aligned with the current code and README
- update docs and examples when public behavior changes
- keep the skill docs, README, examples, and tests consistent with each other
- keep BCR-facing metadata, docs, and test-module expectations consistent with the current release story

If you change onboarding or skill discovery behavior, check all of:

- `README.md`
- `skills/rules_agents/SKILL.md`
- `skills/rules_agents/references/quickstart.md`
- `skills/rules_agents/references/usage.md`
- registry-related tests and examples

If you change release metadata, platform support, or published-module setup guidance, also check all of:

- `LICENSE`
- `MODULE.bazel`
- `AGENTS.md`
- `bcr/presubmit.yml`
- `bcr/test_module/`
- any future `metadata.json` or `source.json` files once they exist

## Validation Expectations

Prefer targeted validation for the area you changed.

Common checks:

- skill packaging changes: `bazel build //skills:rules_agents`
- public docs or self-hosted skill onboarding changes: `bazel test //tests:bzlmod_git_override_test`
- remote archive synthesis changes: `bazel test //tests:remote_skill_deps_test`
- registry discovery or catalog changes: `bazel test //tests:registry_discovery_test` and `bazel test //tests:catalog_defaults_test`
- runtime doctor behavior: `bazel test //tests:doctor_test`
- install and launch behavior: `bazel test //tests:install_start_test`
- broader consumer flow: `bazel test //tests:repo_smoke_test`

For BCR-facing changes, prefer validating:

- `bazel build //:codex_dev_manifest //:claude_dev_manifest` from `bcr/test_module`
- `bazel test //:bcr_smoke_test` from `bcr/test_module`
- `bazel test //tests:repo_smoke_test`
- `bazel test //tests:bzlmod_git_override_test`
- `bazel test //tests:catalog_defaults_test`

If runnable code exists, prioritize validating:

- skill bundle packaging rules
- manifest generation
- install destinations and conflict handling
- required environment variable validation
- launcher behavior for both supported agents

## Documentation Notes

- Keep README examples consistent with what actually passes in tests.
- Do not present historical spec language as current behavior.
- If a documented quickstart is known to require a workaround, fix the guide or note the limitation explicitly instead of leaving it implied.
- Keep released usage docs centered on stable versioned module consumption.
- Do not imply Windows support in docs until the implementation and validation actually support it.

## Final Handoff

- mention the user-visible behavior you changed
- mention the validation you ran
- if you followed a spec or design doc by explicit request, mention any intentional deviation from that adopted document
