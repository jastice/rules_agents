"""Module extensions for remote skill dependencies and registry discovery."""

_REMOTE_TAG = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "skill_path_prefix": attr.string(default = ""),
        "strip_prefix": attr.string(),
        "url": attr.string(mandatory = True),
    },
)

_REGISTRIES_TAG = tag_class(
    attrs = {
        "config": attr.label(),
        "mode": attr.string(default = "extend"),
    },
)

_GITHUB_TREE_LINK_FORMAT = "github_tree"
_REGISTRY_INDEX_REPO = "rules_agents_registry_index"
_REGISTRY_MANIFEST_VERSION = 1
_REMOTE_ARCHIVE_STAGE_DIR = "__archive__"


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


def _normalize_relpath(path, field_name):
    if not path:
        return ""
    if path.startswith("/"):
        fail("%s must be relative, got %r" % (field_name, path))
    parts = [part for part in path.split("/") if part and part != "."]
    for part in parts:
        if part == "..":
            fail("%s must not escape the extracted archive root, got %r" % (field_name, path))
    return "/".join(parts)


def _join_relpath(prefix, suffix):
    if not prefix:
        return suffix
    if not suffix:
        return prefix
    return prefix + "/" + suffix


def _search_root_for_prefix(prefix):
    if not prefix:
        return "."
    return "./" + prefix


def _build_file_path(package_dir, build_file_name):
    if not package_dir:
        return build_file_name
    return package_dir + "/" + build_file_name


def _path_relative_to_root(path, root):
    if not root:
        return path or "."
    if path == root:
        return "."
    prefix = root + "/"
    if not path.startswith(prefix):
        fail("path %r is not under root %r" % (path, root))
    return path[len(prefix):]


def _join_logical_roots(prefix, suffix):
    normalized_prefix = "" if prefix in ("", ".") else prefix
    normalized_suffix = "" if suffix in ("", ".") else suffix
    joined = _join_relpath(normalized_prefix, normalized_suffix)
    return joined or "."


def _strip_search_root_prefix(path, search_root):
    if search_root == ".":
        if path.startswith("./"):
            return path[2:]
        return path

    prefix = search_root + "/"
    if not path.startswith(prefix):
        fail("path %r is not under search root %r" % (path, search_root))
    return path[len(prefix):]


def _find_paths(repo_ctx, root, args, failure_message):
    search_root = _search_root_for_prefix(root)
    result = repo_ctx.execute(["/usr/bin/find", search_root] + args)
    if result.return_code != 0:
        fail("%s: %s" % (failure_message, result.stderr))

    return [
        _strip_search_root_prefix(path, search_root)
        for path in sorted([line for line in result.stdout.splitlines() if line])
    ]


def _archive_url_uses_host_wrapper(url):
    return url.startswith("https://github.com/") and "/archive/" in url and url.endswith(".tar.gz")


def _list_direct_children(repo_ctx, root, directories_only = False):
    args = ["-mindepth", "1", "-maxdepth", "1"]
    if directories_only:
        args.extend(["-type", "d"])
    return _find_paths(
        repo_ctx,
        root,
        args,
        "failed to inspect extracted archive layout",
    )


def _build_file_name_for_package(repo_ctx, package_dir):
    if repo_ctx.path(_build_file_path(package_dir, "BUILD")).exists:
        return "BUILD"
    return "BUILD.bazel"


def _package_dir_for_skill_root(skill_root, skill_path_prefix = ""):
    if skill_root == ".":
        return ""

    if skill_path_prefix and (skill_root == skill_path_prefix or skill_root.startswith(skill_path_prefix + "/")):
        return skill_path_prefix

    if "/" not in skill_root:
        return ""
    return skill_root.rsplit("/", 1)[0]


def _skill_root_relative_to_package(skill_root, package_dir):
    return _path_relative_to_root(skill_root, package_dir)


def _discover_skill_roots(repo_ctx, skill_path_prefix = ""):
    discovered = []
    for path in _find_paths(
        repo_ctx,
        skill_path_prefix,
        ["-type", "f", "-name", "SKILL.md"],
        "failed to scan remote skill archive",
    ):
        path = "./" + path
        root = _skill_root_from_path(path)
        nested = False
        for existing in discovered:
            if root == existing or _is_nested_under(root, existing):
                nested = True
                break
        if not nested:
            discovered.append(root)
    return discovered


def _resolve_archive_root(repo_ctx, archive_url, extracted_root, strip_prefix, skill_path_prefix, context_name):
    # Archive hosts such as GitHub wrap tarballs in a synthetic top-level directory whose
    # name changes with the selected branch, tag, or commit. We normalize that wrapper
    # inside a hidden staging tree so callers can keep stable logical paths like
    # `skill_path_prefix = "skills"` instead of hard-coding host-specific wrapper names.
    if strip_prefix:
        resolved_root = _join_relpath(extracted_root, _normalize_relpath(strip_prefix, "strip_prefix"))
        if not repo_ctx.path(resolved_root).exists:
            fail("%s strip_prefix %r does not exist in extracted archive" % (context_name, strip_prefix))
        return resolved_root

    current_root = extracted_root
    for _ in range(64):
        if skill_path_prefix and repo_ctx.path(_join_relpath(current_root, skill_path_prefix)).exists:
            return current_root

        child_dirs = _list_direct_children(repo_ctx, current_root, directories_only = True)
        if skill_path_prefix:
            matching_children = []
            for child_dir in child_dirs:
                candidate = _join_relpath(_join_relpath(current_root, child_dir), skill_path_prefix)
                if repo_ctx.path(candidate).exists:
                    matching_children.append(child_dir)
            if len(matching_children) > 1:
                fail(
                    "%s archive layout is ambiguous without strip_prefix; skill_path_prefix %r exists under multiple top-level directories: %s" % (
                        context_name,
                        skill_path_prefix,
                        ", ".join(sorted(matching_children)),
                    ),
                )
            if len(matching_children) == 1:
                current_root = _join_relpath(current_root, matching_children[0])
                continue

        children = _list_direct_children(repo_ctx, current_root)
        if len(children) == 1 and len(child_dirs) == 1:
            if not skill_path_prefix:
                child_root = _join_relpath(current_root, child_dirs[0])
                if (repo_ctx.path(_join_relpath(child_root, "SKILL.md")).exists and
                    not _archive_url_uses_host_wrapper(archive_url)):
                    return current_root
            current_root = _join_relpath(current_root, child_dirs[0])
            continue

        return current_root

    fail("%s archive layout exceeded normalization depth while inferring strip_prefix" % context_name)


def _agent_skill_target_lines(target_name, skill_root):
    exclude_patterns = ""
    if skill_root == ".":
        exclude_patterns = ", exclude = [\"BUILD\", \"BUILD.bazel\"]"

    return [
        "agent_skill(",
        "    name = %r," % target_name,
        "    root = %r," % skill_root,
        "    srcs = glob(%r, allow_empty = True, exclude_directories = 1%s)," % (
            _glob_patterns(skill_root),
            exclude_patterns,
        ),
        ")",
        "",
    ]


def _build_file_for_package(skill_targets = [], alias_targets = {}):
    lines = [
        "package(default_visibility = [\"//visibility:public\"])",
        "",
    ]

    if skill_targets:
        lines.extend([
            "load(\"@rules_agents//rules_agents:defs.bzl\", \"agent_skill\")",
            "",
        ])
        for skill_target in skill_targets:
            lines.extend(_agent_skill_target_lines(
                target_name = skill_target["target_name"],
                skill_root = skill_target["skill_root"],
            ))

    for target_name in sorted(alias_targets.keys()):
        lines.extend([
            "alias(",
            "    name = %r," % target_name,
            "    actual = %r," % alias_targets[target_name],
            ")",
            "",
        ])

    return "\n".join(lines)


def _remote_skill_repo_impl(repo_ctx):
    kwargs = {
        "output": _REMOTE_ARCHIVE_STAGE_DIR,
        "url": repo_ctx.attr.url,
    }
    repo_ctx.download_and_extract(**kwargs)

    skill_path_prefix = _normalize_relpath(repo_ctx.attr.skill_path_prefix, "skill_path_prefix")
    archive_root = _resolve_archive_root(
        repo_ctx,
        archive_url = repo_ctx.attr.url,
        extracted_root = _REMOTE_ARCHIVE_STAGE_DIR,
        strip_prefix = repo_ctx.attr.strip_prefix,
        skill_path_prefix = skill_path_prefix,
        context_name = "remote skill archive",
    )
    search_root = _join_relpath(archive_root, skill_path_prefix)
    if skill_path_prefix and not repo_ctx.path(search_root).exists:
        fail("skill_path_prefix %r does not exist in extracted archive" % skill_path_prefix)

    # We synthesize BUILD files only inside the hidden staging tree. That keeps public
    # labels stable while preventing archive-native BUILD files from leaking their own
    # providers or package boundaries into the generated remote skill repository.
    skill_roots = sorted(_discover_skill_roots(repo_ctx, search_root))
    logical_search_root = _path_relative_to_root(search_root, archive_root)
    skill_targets_by_package = {}
    root_aliases = {}
    seen_names = {}

    for skill_root in skill_roots:
        logical_skill_root = _join_logical_roots(logical_search_root, skill_root)
        actual_skill_root = _join_relpath(search_root, "" if skill_root == "." else skill_root)
        target_name = _target_name_for_skill(repo_ctx.attr.repo_name, logical_skill_root)
        if target_name in seen_names:
            fail("duplicate synthesized skill target %r from %r and %r" % (
                target_name,
                seen_names[target_name],
                logical_skill_root,
            ))
        seen_names[target_name] = logical_skill_root

        package_dir = _package_dir_for_skill_root(actual_skill_root, search_root)
        package_skill_root = _skill_root_relative_to_package(actual_skill_root, package_dir)
        skill_targets = skill_targets_by_package.setdefault(package_dir, [])
        skill_targets.append({
            "skill_root": package_skill_root,
            "target_name": target_name,
        })

        if package_dir:
            root_aliases[target_name] = "//%s:%s" % (package_dir, target_name)

    packages_to_write = dict(skill_targets_by_package)
    packages_to_write.setdefault("", [])

    for package_dir in packages_to_write:
        build_file_name = _build_file_name_for_package(repo_ctx, package_dir)
        repo_ctx.file(
            _build_file_path(package_dir, build_file_name),
            _build_file_for_package(
                skill_targets = sorted(
                    packages_to_write[package_dir],
                    key = lambda item: item["target_name"],
                ),
                alias_targets = root_aliases if not package_dir else {},
            ),
        )


_remote_skill_repo = repository_rule(
    implementation = _remote_skill_repo_impl,
    attrs = {
        "repo_name": attr.string(mandatory = True),
        "skill_path_prefix": attr.string(default = ""),
        "strip_prefix": attr.string(),
        "url": attr.string(mandatory = True),
    },
)


def _validate_agents(agents, registry_id):
    allowed = ["claude_code", "codex"]
    for agent in agents:
        if agent not in allowed:
            fail("registry %r declared unsupported agent %r" % (registry_id, agent))


def _require_field(entry, field_name):
    value = entry.get(field_name)
    if value == None or value == "":
        fail("registry entry missing required field %r" % field_name)
    return value


def _validate_registry_entry(entry):
    registry_id = _require_field(entry, "id")
    _require_field(entry, "homepage")
    _require_field(entry, "repo_url")
    _require_field(entry, "archive_url")
    entry["display_name"] = entry.get("display_name", registry_id)
    entry["description"] = entry.get("description", "")
    entry["strip_prefix"] = entry.get("strip_prefix", "")
    entry["default_branch"] = entry.get("default_branch", "main")
    entry["skill_path_prefix"] = _normalize_relpath(entry.get("skill_path_prefix", ""), "skill_path_prefix")
    entry["agents"] = entry.get("agents", [])
    entry["link_format"] = entry.get("link_format", _GITHUB_TREE_LINK_FORMAT)

    _validate_agents(entry["agents"], registry_id)
    if entry["link_format"] != _GITHUB_TREE_LINK_FORMAT:
        fail("registry %r declared unsupported link_format %r" % (
            registry_id,
            entry["link_format"],
        ))
    return entry


def _load_registry_config(repo_ctx, label, label_name):
    data = json.decode(repo_ctx.read(label))
    if data.get("version") != 1:
        fail("%s must declare version = 1" % label_name)
    registries = data.get("registries")
    if type(registries) != type([]):
        fail("%s must declare a registries list" % label_name)

    by_id = {}
    for raw_entry in registries:
        entry = _validate_registry_entry(dict(raw_entry))
        registry_id = entry["id"]
        if registry_id in by_id:
            fail("%s declared duplicate registry id %r" % (label_name, registry_id))
        by_id[registry_id] = entry
    return by_id


def _merge_registry_configs(builtins, override, mode):
    if mode == "replace":
        return dict(override)
    if mode != "extend":
        fail("registries() mode must be \"extend\" or \"replace\", got %r" % mode)

    merged = dict(builtins)
    for registry_id, entry in override.items():
        merged[registry_id] = entry
    return merged


def _parse_frontmatter(skill_md_contents):
    if not skill_md_contents.startswith("---\n"):
        return {}
    lines = skill_md_contents.splitlines()
    end_index = -1
    for index in range(1, len(lines)):
        if lines[index] == "---":
            end_index = index
            break
    if end_index == -1:
        return {}

    parsed = {}
    for line in lines[1:end_index]:
        if not line or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            return {}
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            return {}
        if ((value.startswith('"') and value.endswith('"')) or
            (value.startswith("'") and value.endswith("'"))):
            value = value[1:-1]
        parsed[key] = value
    return parsed


def _extract_revision_from_archive_url(url):
    prefix = "https://github.com/"
    suffix = ".tar.gz"
    marker = "/archive/"
    if not url.startswith(prefix) or not url.endswith(suffix) or marker not in url:
        return None
    return url[url.index(marker) + len(marker):-len(suffix)]


def _is_hex_sha_prefix(text):
    if len(text) < 7 or len(text) > 40:
        return False
    for char in text.elems():
        if char not in "0123456789abcdef":
            return False
    return True


def _source_url_for_skill(registry, skill_path):
    if registry["link_format"] != _GITHUB_TREE_LINK_FORMAT:
        return None

    revision = _extract_revision_from_archive_url(registry["archive_url"])
    if revision == None or not _is_hex_sha_prefix(revision):
        return None

    if not registry["repo_url"].startswith("https://github.com/"):
        return None

    return registry["repo_url"] + "/tree/" + revision + "/" + skill_path


def _per_registry_manifest(registry, skills):
    return {
        "version": _REGISTRY_MANIFEST_VERSION,
        "registry": {
            "id": registry["id"],
            "display_name": registry["display_name"],
            "homepage": registry["homepage"],
            "repo_url": registry["repo_url"],
            "archive_url": registry["archive_url"],
            "strip_prefix": registry["strip_prefix"],
            "skill_path_prefix": registry["skill_path_prefix"],
            "agents": registry["agents"],
            "description": registry["description"],
            "link_format": registry["link_format"],
        },
        "skills": skills,
    }


def _aggregate_registry_entry(registry, skills):
    return {
        "id": registry["id"],
        "display_name": registry["display_name"],
        "homepage": registry["homepage"],
        "repo_url": registry["repo_url"],
        "archive_url": registry["archive_url"],
        "strip_prefix": registry["strip_prefix"],
        "skill_path_prefix": registry["skill_path_prefix"],
        "agents": registry["agents"],
        "description": registry["description"],
        "link_format": registry["link_format"],
        "skills": skills,
    }


def _skills_tsv_content(aggregate):
    """Generate tab-separated skill data for shell filtering."""
    lines = []
    for registry in aggregate.get("registries", []):
        agents_str = ",".join(sorted(registry.get("agents", [])))
        for skill in registry.get("skills", []):
            source_url = skill.get("source_url")
            if source_url == None:
                source_url = ""
            lines.append("\t".join([
                registry["id"],
                agents_str,
                registry["archive_url"],
                registry.get("strip_prefix", ""),
                registry.get("skill_path_prefix", ""),
                skill["skill_name"],
                skill.get("description", ""),
                source_url,
                skill["target_label"],
            ]))
    return "\n".join(lines)


def _registry_index_build_file():
    return """package(default_visibility = ["//visibility:public"])

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

filegroup(
    name = "registry_manifests",
    srcs = glob(["*.manifest.json"], allow_empty = True) + ["aggregate_manifest.json"],
)

sh_binary(
    name = "list_skills",
    srcs = ["list_skills.sh"],
    data = [
        "aggregate_manifest.json",
        "skills.tsv",
    ],
)

exports_files(["aggregate_manifest.json"])
"""


def _registry_index_repo_impl(repo_ctx):
    builtins = _load_registry_config(repo_ctx, repo_ctx.attr.builtins, "built-in registry catalog")
    override = {}
    if repo_ctx.attr.config:
        override = _load_registry_config(repo_ctx, repo_ctx.attr.config, "repo-level registry catalog")
    merged = _merge_registry_configs(builtins, override, repo_ctx.attr.mode)

    aggregate = {"version": _REGISTRY_MANIFEST_VERSION, "registries": []}
    manifest_paths = []
    downloads_root = "__registry_downloads__"

    for registry_id in sorted(merged.keys()):
        registry = merged[registry_id]
        output_dir = _join_relpath(downloads_root, registry_id)
        kwargs = {
            "output": output_dir,
            "url": registry["archive_url"],
        }
        repo_ctx.download_and_extract(**kwargs)

        archive_root = _resolve_archive_root(
            repo_ctx,
            archive_url = registry["archive_url"],
            extracted_root = output_dir,
            strip_prefix = registry["strip_prefix"],
            skill_path_prefix = registry["skill_path_prefix"],
            context_name = "registry %r" % registry_id,
        )
        search_prefix = _join_relpath(archive_root, registry["skill_path_prefix"])
        if registry["skill_path_prefix"] and not repo_ctx.path(search_prefix).exists:
            fail("registry %r declared skill_path_prefix %r that does not exist in extracted archive" % (
                registry_id,
                registry["skill_path_prefix"],
            ))

        skill_roots = _discover_skill_roots(repo_ctx, search_prefix)
        logical_search_root = _path_relative_to_root(search_prefix, archive_root)
        skills = []
        for skill_root in sorted(skill_roots):
            logical_skill_root = _join_logical_roots(logical_search_root, skill_root)
            actual_skill_root = _join_relpath(search_prefix, "" if skill_root == "." else skill_root)
            target_name = _target_name_for_skill(registry_id, logical_skill_root)
            frontmatter = _parse_frontmatter(repo_ctx.read(actual_skill_root + "/SKILL.md"))
            skills.append({
                "skill_name": target_name,
                "display_name": frontmatter.get("name", target_name),
                "description": frontmatter.get("description", ""),
                "skill_path": logical_skill_root,
                "source_url": _source_url_for_skill(
                    registry,
                    logical_skill_root,
                ),
                "target_label": "@%s//:%s" % (registry_id, target_name),
            })

        per_registry = _per_registry_manifest(registry, skills)
        manifest_name = "%s.manifest.json" % registry_id
        repo_ctx.file(manifest_name, json.encode(per_registry))
        manifest_paths.append(manifest_name)
        aggregate["registries"].append(_aggregate_registry_entry(registry, skills))

    aggregate_json = json.encode(aggregate)
    skills_tsv = _skills_tsv_content(aggregate)
    repo_ctx.file("aggregate_manifest.json", aggregate_json)
    repo_ctx.file("skills.tsv", skills_tsv)
    repo_ctx.file("list_skills.sh", repo_ctx.read(repo_ctx.attr.list_skills_script), executable = True)
    repo_ctx.file("BUILD.bazel", _registry_index_build_file())


_registry_index_repo = repository_rule(
    implementation = _registry_index_repo_impl,
    attrs = {
        "builtins": attr.label(mandatory = True),
        "config": attr.label(),
        "list_skills_script": attr.label(default = Label("//rules_agents:list_skills.sh")),
        "mode": attr.string(default = "extend"),
    },
)


def _root_module_registries_tag(ctx):
    registries_tags = []
    for module in ctx.modules:
        if not module.is_root:
            continue
        registries_tags.extend(module.tags.registries)
    if len(registries_tags) > 1:
        fail("skill_deps.registries() may be declared at most once in the root module")
    return registries_tags[0] if registries_tags else None


def _skill_deps_impl(ctx):
    for module in ctx.modules:
        for remote in module.tags.remote:
            _remote_skill_repo(
                name = remote.name,
                repo_name = remote.name,
                skill_path_prefix = remote.skill_path_prefix,
                strip_prefix = remote.strip_prefix,
                url = remote.url,
            )

    registries = _root_module_registries_tag(ctx)
    if registries == None:
        return

    _registry_index_repo(
        name = _REGISTRY_INDEX_REPO,
        builtins = Label("//catalog:registries.json"),
        config = registries.config,
        mode = registries.mode,
    )


skill_deps = module_extension(
    implementation = _skill_deps_impl,
    tag_classes = {
        "registries": _REGISTRIES_TAG,
        "remote": _REMOTE_TAG,
    },
)
