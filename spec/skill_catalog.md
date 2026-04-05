# rules_agents

Skill Registry Discovery Proposal

Status: draft for review

## 1. Summary

This document proposes a small discovery layer for `rules_agents`:

- ship a curated set of registry definitions with this repo
- allow consuming repositories to extend or replace those definitions at repo scope
- pin each active registry to an exact archive version through repo-owned registry config
  consumed by Bazel module extension evaluation
- discover skills from those pinned archives during the Bazel invocation
- expose one Bazel target that prints discovered skills with install guidance

This proposal does not add a new installation mechanism. Remote skills still become usable
only through `skill_deps.remote(...)`.

## 2. Problem

Users want one command that answers:

- what skills are available across known registries
- what each skill does at a basic level
- where to read the full skill online
- what Bazel snippet to add in order to use it

Browsing multiple registry repositories by hand is too much friction. A checked-in static
skill inventory would become stale. The system should therefore keep registry definitions
stable and checked in, but discover current skills from pinned registry contents.

## 3. Design constraints

Public API context for this proposal:

- `agent_skill`
- `agent_profile`
- `agent_runner`
- `skill_deps`

Design constraints:

- keep remote resolution based on explicit pinned archives
- avoid a live online registry service
- avoid hidden user-global configuration
- preserve machine-readable outputs

The discovery layer is an index and formatter. It is not a package manager or dependency
solver.

## 4. Goals

- provide one Bazel command to list skills across configured registries
- discover skills from pinned registry archives instead of checked-in skill snapshots
- print a short description from `SKILL.md` frontmatter
- print a link to the full online skill source
- print the correct Bazel snippet and target label needed to add a skill
- reuse Bazel caching so repeated invocations are cheap
- allow repo-level extension or replacement of default registries

## 5. Non-goals

- dynamic discovery from floating branches or tags
- arbitrary network access from normal `list_skills` or install flows
- scraping GitHub or vendor APIs directly at listing time
- symbolic installation without a pinned archive URL
- automatic mutation of the caller's `MODULE.bazel`
- hidden home-directory config for registry definitions
- implicit registry pin drift during normal `list_skills` or install flows

## 6. Proposed user experience

Provide a runnable target from the generated registry index repo:

```bash
bazel run @rules_agents_registry_index//:list_skills
```

For local development in this repository:

```bash
bazel run @rules_agents_registry_index//:list_skills
```

Default behavior:

1. load registry definitions from `rules_agents`
2. apply any repo-level extension or replacement definitions
3. resolve each registry through the merged pinned registry config consumed by module
   extension evaluation
4. discover skills by scanning extracted archive contents for `SKILL.md`
5. parse a basic description from frontmatter during repository evaluation
6. run the generated `@rules_agents_registry_index//:list_skills` target
7. print discovered skills in a stable order

Expected output per skill:

1. the basic skill description from `SKILL.md` frontmatter
2. a link to the full online skill
3. the correct Bazel invocation to add the skill

Example commands:

```bash
bazel run @rules_agents_registry_index//:list_skills
bazel run @rules_agents_registry_index//:list_skills -- --agent=codex
bazel run @rules_agents_registry_index//:list_skills -- --registry=openai_skills
bazel run @rules_agents_registry_index//:list_skills -- --skill=python
bazel run @rules_agents_registry_index//:list_skills -- --json
```

Supported flags:

- `--json`
  - print the discovered and filtered results as JSON
- `--registry=<id>`
  - filter to one registry
- `--skill=<name>`
  - filter by discovered skill name
- `--agent=codex|claude_code`
  - filter by supported agent at registry granularity; a registry is included if its
    `agents` field contains the requested agent

## 7. Registry model

### 7.1 Checked-in default registries

`rules_agents` checks in a curated list of registry definitions.

Suggested path:

- `catalog/registries.json`

These are definitions only, not checked-in skill inventories.

Each registry definition identifies:

- registry id
- homepage
- supported agents
- archive URL template or repository URL needed to form online source links
- optional path conventions needed to map discovered skills to online links

### 7.2 Repo-level extension or replacement

A consuming repository may customize the registry set at repo scope.

Two supported modes:

- extend the default registry definitions with additional registries
- replace the default registry definitions entirely

This should be done with checked-in repo files, not user-global config.

Suggested path in the consuming repository:

- `tools/rules_agents/registries.json`

If replacement is chosen, the repo-owned definitions become the complete registry set for
that repository.

The repo-level file should be the stable authored surface for:

- additional or replacement registry definitions
- explicit pinned archive URLs for those active registries
- any update-tool rewrites approved by the maintainer

### 7.3 Why definitions are checked in but skills are discovered

This is the intended split:

- registry definitions change infrequently and should be repo-owned
- skill contents change with registry revisions and should be discovered from the pinned
  archive contents

This avoids stale checked-in skill lists while keeping the registry surface predictable.

### 7.4 Explicit update workflow

Pinned registries still need a simple update path.

The update model should be:

- explicit
- maintainer-oriented
- separate from normal listing and install flows

The intended behavior is:

1. normal `list_skills` and install behavior always use the currently pinned archive URL
2. a separate update command checks whether newer upstream revisions exist
3. that command rewrites the repo-owned registry config file only when explicitly requested
4. subsequent Bazel invocations pick up the new pins through normal module extension
   reevaluation

Suggested target:

- `@rules_agents//tools:update_registries`

Suggested capabilities:

- check all active registries or a selected registry
- resolve a newer upstream commit for a configured branch or default branch
- print the proposed old pin and new pin
- require an explicit apply step before rewriting repo-owned config
- update the pinned `archive_url` and related fields such as `strip_prefix`

The update command is a maintainer tool, not part of the ordinary end-user skill lookup
flow.

It is the explicit exception to the normal no-network rule for listing and install flows.

For built-in registries shipped by `rules_agents`, that maintainer workflow runs in the
`rules_agents` repository itself. A consuming repository that relies only on built-in
registries receives those updates by bumping its `rules_agents` version, or by adding a
repo-level `tools/rules_agents/registries.json` override when it needs to move independently.

A consuming repository must not expect `@rules_agents//tools:update_registries -- --apply`
to rewrite the built-in `catalog/registries.json` inside the external `rules_agents`
repository. `--apply` rewrites only repo-owned config files in the current workspace.

### 7.5 `registries.json` schema

The built-in catalog file and the optional repo-level override file should use the same JSON
schema.

That schema should be written as a standard JSON Schema document, using JSON Schema Draft
2020-12.

Suggested schema file:

- `catalog/registries.schema.json`

Suggested schema:

```json
{
  "version": 1,
  "registries": [
    {
      "id": "openai_skills",
      "display_name": "OpenAI Skills",
      "homepage": "https://github.com/openai/skills",
      "repo_url": "https://github.com/openai/skills",
      "archive_url": "https://github.com/openai/skills/archive/0123456789abcdef.tar.gz",
      "strip_prefix": "skills-0123456789abcdef",
      "default_branch": "main",
      "agents": ["codex"],
      "skill_path_prefix": "",
      "description": "Curated Codex skills.",
      "link_format": "github_tree"
    }
  ]
}
```

Top-level fields:

- `version`
  - schema version; must be `1`
- `registries`
  - list of registry entries

Registry entry fields:

- `id`
  - stable registry identifier; unique within one file and within the merged config
- `display_name`
  - human-readable name used by listing output
- `homepage`
  - canonical documentation or repository page for the registry
- `repo_url`
  - canonical repository URL used for rendering source links and update checks
- `archive_url`
  - exact pinned archive URL used for fetch and discovery; must not float
- `strip_prefix`
  - optional extracted archive root to strip before skill discovery
- `default_branch`
  - optional branch name used only by the explicit update tool when looking for newer
    upstream commits
- `agents`
  - subset of `{codex, claude_code}` used for filtering
- `skill_path_prefix`
  - optional relative path under the extracted archive root where skill discovery begins;
    empty string means the archive root itself
- `description`
  - short summary of the registry
- `link_format`
  - source-link rendering convention; v1 supports only `github_tree`

Validation rules:

- `version` must be `1`
- `registries` must be present
- `id`, `homepage`, `repo_url`, and `archive_url` are required and must be non-empty
- `archive_url` must identify a pinned archive revision
- `skill_path_prefix` must be relative and must not escape the extracted archive root
- `agents` must contain only supported agent ids
- `link_format` must be `github_tree` in v1

Schema notes:

- using one schema for built-ins and repo-level overrides keeps merge behavior simple
- the schema should use `additionalProperties: false` for the top-level object and registry
  entries in v1
- the updater rewrites only data fields in this file; it does not modify `MODULE.bazel`
- repositories that need a non-GitHub source-link format are out of scope for v1
- structural validation should be performed with JSON Schema
- semantic validation that is awkward or non-portable in JSON Schema should be implemented in
  normal code after schema validation
- `agents` applies at registry granularity, not per-skill granularity
- registries that need precise mixed-agent filtering should be split by agent in this PoC

Suggested semantic checks beyond JSON Schema:

- `archive_url` is commit-pinned rather than floating
- merged registry ids are unique after applying `extend` or `replace`
- `skill_path_prefix` does not escape the extracted archive root
- the pinned archive URL is compatible with the selected `link_format`

### 7.6 Merge semantics

The merged active registry config is computed from:

1. built-in `catalog/registries.json`
2. optional repo-level `tools/rules_agents/registries.json`
3. the `mode` passed through `skill_deps.registries(...)`

Merge rules:

- if no repo-level file is provided, the built-in file is the full active config
- if `mode = "extend"`, repo-level entries are added to the built-ins and replace built-in
  entries with the same `id`
- if `mode = "replace"`, only repo-level entries are active
- final output ordering should be deterministic and sorted by `id`

This replacement-by-`id` behavior should be used both by extension evaluation and by the
update tool.

## 8. Pinning and lock model

### 8.1 Purpose

Registry definitions do not directly point at floating content. Each active registry must be
pinned through repo-owned registry configuration consumed by module extension evaluation.

The Bazel lockfile, `MODULE.bazel.lock`, is the cache and reproducibility boundary for that
resolution work.

Repeated invocations should only force refetch or rediscovery when the pinned registry
version changes, when registry config inputs change, or when the discovery code changes.

### 8.2 User-authored inputs

Suggested repo-owned inputs:

- built-in registry definitions and default pins in `catalog/registries.json`
- optional repo-level registry definitions and pin overrides in
  `tools/rules_agents/registries.json`
- a stable `MODULE.bazel` entry that enables registry discovery and points at the optional
  repo-level config file

The human-authored configuration surface should remain ordinary repo files plus
`MODULE.bazel`, not a second custom lock format.

### 8.3 Module extension contract

The intended model is:

1. registry definitions declare stable metadata such as homepage, supported agents, and URL
   rendering conventions
2. built-in registry definitions provide a default curated registry set
3. the consuming repository may optionally provide `tools/rules_agents/registries.json` to extend or
   replace that set and override pins
4. the existing `skill_deps` module extension consumes the merged registry config
5. active registries are resolved to exact archive URLs from that merged config
6. Bazel records module resolution and extension evaluation results in `MODULE.bazel.lock`
7. the extension generates a discovery repo containing machine-readable registry manifests
   consumed by `@rules_agents_registry_index//:list_skills`

Suggested extension shape:

```python
skill_deps = use_extension(
    "@rules_agents//rules_agents:extensions.bzl",
    "skill_deps",
)

skill_deps.registries(
    config = "//tools/rules_agents:registries.json",  # optional
    mode = "extend",  # or "replace"
)

use_repo(skill_deps, "rules_agents_registry_index")
```

Field semantics:

- `config`
  - label of the optional repo-level registry config file
- `mode`
  - whether repo-level config extends built-ins or replaces them

Tag class contract:

- `config`
  - type: label
  - required: no
  - default: unset
  - meaning: when unset, only built-in registries are active
- `mode`
  - type: string enum
  - required: no
  - default: `extend`
  - allowed values: `extend`, `replace`

Zero-argument form:

```python
skill_deps.registries()
use_repo(skill_deps, "rules_agents_registry_index")
```

This means:

- use built-in registries only
- no repo-level override file
- mode behaves as `extend`, though no override file is present

Generated repo contract:

- `skill_deps.registries(...)` must generate an external repo named
  `rules_agents_registry_index`
- that repo must expose:
  - `@rules_agents_registry_index//:registry_manifests`
    - filegroup or equivalent containing all per-registry manifests plus the aggregate
      manifest
  - `@rules_agents_registry_index//:aggregate_manifest.json`
    - aggregate manifest consumed by `@rules_agents_registry_index//:list_skills`
  - `@rules_agents_registry_index//:list_skills`
    - public runnable wrapper target for browsing discovered skills

Validation rules:

- every active registry id in the merged config must resolve to one registry definition
- every active registry entry in the merged config must provide one exact archive URL
- active registry ids must be unique within the final merged config
- merged `archive_url` values must be pinned, not floating
- repo-level registry config files read by the extension must be watched so changes
  invalidate extension evaluation cleanly
- the generated repo name `rules_agents_registry_index` must be stable

Registry pins may be rewritten by a separate explicit maintainer workflow, but normal listing
and install behavior must never rewrite them implicitly.

### 8.4 Relationship between `registries()` and `remote()`

`skill_deps.registries(...)` and `skill_deps.remote(...)` may coexist in the same
`MODULE.bazel`.

Their responsibilities are different:

- `skill_deps.registries(...)`
  - enables registry discovery from configured pinned registries
  - does not make discovered skills directly usable in `agent_profile`
  - does not synthesize implicit `remote()` entries
  - generates the `rules_agents_registry_index` repo used for skill browsing
- `skill_deps.remote(...)`
  - declares one concrete remote skill archive as a usable external repo
  - produces synthesized `agent_skill` targets that may be referenced from
    `agent_profile`

The intended user flow is:

1. enable registry discovery with `skill_deps.registries(...)`
2. inspect available skills with `@rules_agents_registry_index//:list_skills`
3. copy the printed `skill_deps.remote(...)` stanza for the registry you want
4. add the synthesized target label to `agent_profile`

To keep discovery and installation aligned, this proposal extends `skill_deps.remote(...)`
with:

- `skill_path_prefix`
  - type: string
  - required: no
  - default: `""`
  - meaning: relative path under the extracted archive root where skill synthesis begins

### 8.5 Relationship to `MODULE.bazel.lock`

`MODULE.bazel.lock` should be treated as Bazel-owned state, not as a custom user-facing API.

This feature should integrate with it by:

- performing registry discovery through the existing `skill_deps` module extension
- letting Bazel cache extension evaluation and generated repository specs
- letting Bazel invalidate that state when `MODULE.bazel`, watched repo config files, or
  extension implementation inputs change

`rules_agents` must not directly parse, mutate, or otherwise depend on the concrete file
format of `MODULE.bazel.lock`.

The spec should not require users to hand-edit `MODULE.bazel.lock`.

## 9. Discovery model

### 9.1 Where discovery happens

Discovery should happen as Bazel fetch/build work, not as ad hoc network logic in the final
runtime binary.

The intended pipeline is:

1. Bazel evaluates the registry module extension
2. Bazel resolves pinned registry archives
3. Bazel fetches or reuses those external repositories
4. repository-rule logic scans extracted contents for skill roots
5. repository-rule logic parses `SKILL.md` frontmatter and emits machine-readable manifests
6. the generated aggregate manifest is exposed from
   `@rules_agents_registry_index//:aggregate_manifest.json`
7. the generated `@rules_agents_registry_index//:list_skills` target receives that aggregate
   manifest as a runfiles data dependency and formats output from it

Any repo-level registry config files consumed by the extension must be read in a way that
causes Bazel to invalidate the extension when those files change.

This is the correct way to take advantage of Bazel caching.

### 9.1.1 Manifest dependency contract

`@rules_agents_registry_index//:list_skills` must locate discovery results through Bazel
runfiles, not by scanning the workspace or external repo cache directly.

Required contract:

- `@rules_agents_registry_index//:list_skills` has a data dependency on
  `@rules_agents_registry_index//:aggregate_manifest.json`
- the aggregate manifest is present in runfiles at runtime
- the formatter reads only that aggregate manifest
- per-registry manifests are intermediate artifacts and may be used to build the aggregate
  manifest, but `list_skills` does not need to discover them dynamically
- `@rules_agents_registry_index//:list_skills` must remain publicly runnable from consuming
  repositories that enable `skill_deps.registries(...)`

### 9.2 Skill discovery rules

For each pinned registry archive:

- walk the archive root after applying `strip_prefix` and `skill_path_prefix`
- any directory containing `SKILL.md` at its root is one discovered skill
- if the archive root itself contains `SKILL.md`, treat the archive root as one skill
- nested skill directories inside an already-discovered skill root are not supported in v1

This should stay aligned with the existing `skill_deps` discovery convention.

### 9.3 Frontmatter extraction

The discovery step should read the minimal frontmatter needed for listing.

Supported frontmatter format in this proposal:

- YAML frontmatter only
- frontmatter must appear at the start of `SKILL.md`
- opening delimiter: `---`
- closing delimiter: `---`

Example:

```md
---
name: Python
description: Python coding workflow skill.
---

# Python
```

Required extracted fields:

- `name`
  - optional display name shown in listings
- `description`
  - optional short description shown in listings

Fallback behavior:

- if `name` is missing, use the discovered skill directory name
- if `description` is missing, report an empty description or a short placeholder
- if frontmatter is malformed, treat it as absent for listing purposes
- frontmatter absence is not a validity failure for discovery if the skill otherwise has a
  valid `SKILL.md`

This frontmatter parsing requirement applies only to the registry discovery layer. It does
not change `agent_skill` validation, which still only requires that `SKILL.md` exist at the
bundle root.

## 10. Manifest formats

### 10.1 Per-registry manifest

Each discovered registry must emit one JSON manifest with this schema:

```json
{
  "version": 1,
  "registry": {
    "id": "openai_skills",
    "display_name": "OpenAI Skills",
    "homepage": "https://github.com/openai/skills",
    "repo_url": "https://github.com/openai/skills",
    "archive_url": "https://github.com/openai/skills/archive/0123456789abcdef.tar.gz",
    "strip_prefix": "skills-0123456789abcdef",
    "skill_path_prefix": "",
    "agents": ["codex"],
    "description": "Curated Codex skills.",
    "link_format": "github_tree"
  },
  "skills": [
    {
      "skill_name": "python",
      "display_name": "Python",
      "description": "Python coding workflow skill.",
      "skill_path": "python",
      "source_url": "https://github.com/openai/skills/tree/0123456789abcdef/python",
      "target_label": "@openai_skills//:python"
    }
  ]
}
```

`target_label` is a suggested label, not a live resolved label at discovery time. It assumes
the user adopts the printed `skill_deps.remote(...)` stanza with `name` equal to the
registry `id`.

### 10.2 Aggregate manifest

The aggregate manifest consumed by `list_skills` must have this schema:

```json
{
  "version": 1,
  "registries": [
    {
      "id": "openai_skills",
      "display_name": "OpenAI Skills",
      "homepage": "https://github.com/openai/skills",
      "repo_url": "https://github.com/openai/skills",
      "archive_url": "https://github.com/openai/skills/archive/0123456789abcdef.tar.gz",
      "strip_prefix": "skills-0123456789abcdef",
      "skill_path_prefix": "",
      "agents": ["codex"],
      "description": "Curated Codex skills.",
      "link_format": "github_tree",
      "skills": [
        {
          "skill_name": "python",
          "display_name": "Python",
          "description": "Python coding workflow skill.",
          "skill_path": "python",
          "source_url": "https://github.com/openai/skills/tree/0123456789abcdef/python",
          "target_label": "@openai_skills//:python"
        }
      ]
    }
  ]
}
```

`list_skills --json` must emit this aggregate schema, after applying any requested filters.

## 11. Output behavior

### 11.1 Human-readable output

Default output should be grouped by registry and list, for each skill:

- one registry-level Bazel snippet block
- then one entry per matching skill containing:
  - discovered name
  - short description from frontmatter
  - online link to the full skill
  - suggested target label

Example:

```text
Registry: openai_skills

Add:
  skill_deps = use_extension(
      "@rules_agents//rules_agents:extensions.bzl",
      "skill_deps",
  )
  skill_deps.remote(
      name = "openai_skills",
      url = "https://github.com/openai/skills/archive/0123456789abcdef.tar.gz",
      strip_prefix = "skills-0123456789abcdef",
  )
  use_repo(skill_deps, "openai_skills")

- python
  Description: Python coding workflow skill.
  Source: https://github.com/openai/skills/tree/0123456789abcdef/python
  Target: @openai_skills//:python
```

The exact formatting can vary, but those information elements must be present.

### 11.2 JSON output

`--json` prints the aggregate manifest schema from section 10.2, after filtering.

## 12. Link generation

Each discovered skill should include a link to the full online skill source.

For GitHub-backed registries, the preferred form is:

- repository tree URL pinned to the resolved revision
- full path to the discovered skill directory

Example:

- `https://github.com/openai/skills/tree/0123456789abcdef/python`

Registry definitions therefore need enough information to render that URL deterministically.

In v1, that means:

- derive the resolved revision from the pinned `archive_url`
- use `repo_url`
- append `tree/<resolved_revision>/<skill_path>` where `skill_path` is the discovered skill
  path relative to the extracted archive root after `strip_prefix`

### 12.1 `archive_url` to revision mapping

For `link_format = "github_tree"`, the revision used for source links must be derived from
`archive_url` using this supported shape:

- `https://github.com/<owner>/<repo>/archive/<rev>.tar.gz`

In this proposal, active registries must be commit-pinned. Therefore:

- extract `<rev>` from `.../archive/<rev>.tar.gz`
- require `<rev>` to match `[0-9a-f]{7,40}`

If `archive_url` does not match the supported commit-pinned GitHub archive shape, discovery
may still proceed, but `source_url` must be omitted unless the implementation has another
deterministic way to compute it from the configured `link_format`.

## 13. Bazel snippet generation

The listing target should print the correct Bazel usage for each skill.

That output must include:

- the `skill_deps = use_extension(...)` line
- the correct `skill_deps.remote(...)` stanza using the same pinned archive URL
- the `skill_path_prefix` argument only when its value differs from the default `""`
- the `use_repo(...)` line
- the suggested target label, for example `@openai_skills//:python`

The goal is that a user can copy from the listing output directly into:

- `MODULE.bazel`
- the relevant `BUILD.bazel` file using `agent_profile`

This is still guidance output. The tool does not edit user files.

`--skill=<name>` matching rules:

- with no `--registry` filter, match all registries containing a discovered skill with that
  exact `skill_name`
- with `--registry=<id>`, apply `--skill` after the registry filter, so the result is the
  intersection of both filters

## 14. Caching model

### 14.1 Module extension and repository cache

Pinned registry archives should be fetched through Bazel module extension and repository rule
machinery so Bazel can reuse both extension evaluation results and downloaded content until
the effective pin changes.

The expected cache boundary is `MODULE.bazel.lock`, not a custom lock file.

### 14.2 Repository evaluation cache

Skill discovery and frontmatter parsing occur during repository rule or module-extension
evaluation, not as normal Bazel build actions. The generated manifests should be reused until
one of the following changes:

- the pinned archive contents
- the discovery implementation
- registry definition inputs that affect link rendering or filtering
- repo-level registry config files consumed by the extension

### 14.3 Final run target

The final `bazel run ...:list_skills` target should be a formatter over already-generated
manifests. It should not perform the expensive network or parsing work itself.

This is the main reason repeated invocations can stay cheap.

## 15. Suggested repository layout

Suggested new files in `rules_agents`:

- `catalog/registries.json`
- `catalog/registries.schema.json`
- `tools/list_skills.py`
- `tools/update_registries.py`
- `tools/BUILD.bazel`

Suggested generated artifacts:

- one per-registry discovered manifest JSON
- one aggregate manifest consumed by `list_skills`

Suggested target names:

- `@rules_agents_registry_index//:list_skills`
- `@rules_agents//tools:update_registries`
- `@rules_agents_registry_index//:registry_manifests`
- `@rules_agents_registry_index//:aggregate_manifest.json`

## 16. Testing requirements

The feature should be covered with deterministic tests:

- built-in registry definitions conform to `catalog/registries.schema.json`
- repo-level override files conform to `catalog/registries.schema.json`
- built-in registry definitions load successfully
- zero-argument `skill_deps.registries()` enables built-in registries only
- repo-level extension merges correctly
- repo-level replacement fully replaces defaults
- module extension inputs are reflected in `MODULE.bazel.lock` or repository reevaluation
  invalidation behavior
- pinned archive changes invalidate discovery outputs
- unchanged pins reuse cached discovery outputs
- skill discovery matches the `skill_deps` convention
- frontmatter description extraction works
- malformed YAML frontmatter falls back to no extracted metadata
- source links are rendered correctly
- printed Bazel snippets use pinned archive URLs and omit default `skill_path_prefix`
- no ad hoc network logic exists in the final runtime formatter
- `update_registries` network behavior is limited to the explicit maintainer command
- registry update tooling does not modify pins without explicit apply behavior
- registry update tooling rewrites pins deterministically when apply is requested
- unreachable archive failures are surfaced clearly during discovery
- nonexistent `skill_path_prefix` fails clearly during discovery
- `--skill=<name>` matches across registries and intersects with `--registry`

## 17. Why this is the right scope

This proposal solves the discovery problem without turning `rules_agents` into a general
registry product.

It keeps the core discipline:

- registries are checked in
- consuming repos may extend or replace them at repo scope
- active registry pins come from merged repo-owned registry config consumed by the existing
  `skill_deps` extension
- `MODULE.bazel.lock` is the Bazel-owned cache boundary
- skills are discovered from those pinned contents
- Bazel caches the expensive work
- users still install skills through the existing `skill_deps.remote(...)` mechanism

This is a boring, Bazel-native solution.

## 18. Deferred ideas

Keep the following out of the first version:

- automatic lock refresh from upstream
- semver or tag resolution
- trust scoring or reputation systems
- non-pinned shorthand such as `skill_deps.remote(name = "openai_skills")`
- automatic editing of `MODULE.bazel`
- richer metadata extraction beyond the minimum needed for listing

Those can be revisited later if this narrower model proves insufficient.
