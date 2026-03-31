"""Module extensions for remote skill dependencies."""

_REMOTE_TAG = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "url": attr.string(mandatory = True),
    },
)


def _target_name_for_skill(repo_name, skill_root):
    if skill_root == ".":
        return repo_name
    segments = skill_root.split("/")
    return segments[len(segments) - 1]


def _glob_patterns(skill_root):
    if skill_root == ".":
        return ["*", "**", ".*", "**/.*"]
    return [
        skill_root + "/**",
        skill_root + "/.*",
        skill_root + "/**/.*",
    ]


def _skill_root_from_path(path):
    if path == "./SKILL.md":
        return "."
    suffix = "/SKILL.md"
    if not path.startswith("./") or not path.endswith(suffix):
        fail("unexpected SKILL.md path from archive scan: %r" % path)
    return path[2:-len(suffix)]


def _is_nested_under(root, parent):
    if parent == ".":
        return False
    return root.startswith(parent + "/")


def _discover_skill_roots(repo_ctx):
    result = repo_ctx.execute(["/usr/bin/find", ".", "-type", "f", "-name", "SKILL.md"])
    if result.return_code != 0:
        fail("failed to scan remote skill archive: %s" % result.stderr)

    discovered = []
    for path in sorted([line for line in result.stdout.splitlines() if line]):
        root = _skill_root_from_path(path)
        nested = False
        for existing in discovered:
            if root == existing or _is_nested_under(root, existing):
                nested = True
                break
        if not nested:
            discovered.append(root)
    return discovered


def _build_file_for_skills(repo_name, skill_roots):
    lines = [
        "package(default_visibility = [\"//visibility:public\"])",
        "",
        "load(\"@rules_agents//rules_agents:defs.bzl\", \"agent_skill\")",
        "",
    ]

    seen_names = {}
    for skill_root in skill_roots:
        target_name = _target_name_for_skill(repo_name, skill_root)
        if target_name in seen_names:
            fail("duplicate synthesized skill target %r from %r and %r" % (
                target_name,
                seen_names[target_name],
                skill_root,
            ))
        seen_names[target_name] = skill_root

        lines.extend([
            "agent_skill(",
            "    name = %r," % target_name,
            "    root = %r," % skill_root,
            "    srcs = glob(%r, allow_empty = True, exclude_directories = 1%s)," % (
                _glob_patterns(skill_root),
                ", exclude = [\"BUILD.bazel\"]" if skill_root == "." else "",
            ),
            ")",
            "",
        ])

    return "\n".join(lines)


def _remote_skill_repo_impl(repo_ctx):
    kwargs = {"url": repo_ctx.attr.url}
    if repo_ctx.attr.strip_prefix:
        kwargs["stripPrefix"] = repo_ctx.attr.strip_prefix
    repo_ctx.download_and_extract(**kwargs)

    skill_roots = sorted(_discover_skill_roots(repo_ctx))

    repo_ctx.file("BUILD.bazel", _build_file_for_skills(repo_ctx.attr.repo_name, skill_roots))


_remote_skill_repo = repository_rule(
    implementation = _remote_skill_repo_impl,
    attrs = {
        "repo_name": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "url": attr.string(mandatory = True),
    },
)


def _skill_deps_impl(ctx):
    for module in ctx.modules:
        for remote in module.tags.remote:
            _remote_skill_repo(
                name = remote.name,
                repo_name = remote.name,
                strip_prefix = remote.strip_prefix,
                url = remote.url,
            )


skill_deps = module_extension(
    implementation = _skill_deps_impl,
    tag_classes = {"remote": _REMOTE_TAG},
)
