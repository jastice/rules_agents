This file applies to the entire repository.
- The repository currently centers on the v1 product spec in `spec/v1.md`.
- Treat `spec/v1.md` as the source of truth for implemented behavior unless the user explicitly overrides it.
- Design proposals under `spec/` may extend or challenge the v1 model, but they are not implemented truth unless the user asks to adopt them.
- If implementation work begins, read the relevant spec sections before making structural decisions.
Build a small Bazel-based system that lets a repository declare a local coding-agent environment and launch it with one command.
The v1 contract is intentionally narrow:
- support exactly two agent clients: `codex` and `claude_code`
- declare skills in Bazel from local sources or remote git archives
- install skills into the agent's native project-local skill directories
- pass through a declared set of credential environment variables unchanged
- launch the selected agent from the repository root
Keep the implementation boring and narrow on purpose.
Do:
- use project-local native skill directories
- keep the public API small: `agent_skill`, `agent_profile`, and `skill_deps`
- preserve the distinction between packaging, manifest generation, installation, launch, and agent-specific adapters
- follow the implementation order in section 14 of `spec/v1.md` when possible
- keep generated file ownership limited to tool-managed subdirectories
Do not:
- build a general agent framework
- synthesize or own user-global client config
- broaden scope beyond install, doctor, manifest, and start behavior
For `codex`:
- install repo-local skills under `.agents/skills`
- rely on normal repository-root discovery
- do not depend on `CODEX_HOME` for skill installation
For `claude_code`:
- install repo-local skills under `.claude/skills`
- rely on normal repository-root discovery
- do not synthesize a global Claude home
When coding in this repo:
- prefer minimal, testable layers over abstraction
- fix root causes rather than papering over behavior
- keep naming aligned with the spec terminology
- avoid speculative extension points unless the spec already requires them
- preserve machine-readable outputs where the spec calls for manifests or doctor checks
If runnable code exists, prioritize validating:
- skill bundle packaging rules
- manifest generation
- install destinations and conflict handling
- required environment variable validation
- launcher behavior for both supported agents
- start from the spec, especially sections 7 through 14
- implement the smallest slice that satisfies the current step of the plan
- keep changes repository-scoped and reproducible
- document any intentional deviation from the spec in the final handoff
