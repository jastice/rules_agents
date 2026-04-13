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


def _discover_skill_roots(repo_ctx, skill_path_prefix = ""):
    search_root = _search_root_for_prefix(skill_path_prefix)
    result = repo_ctx.execute(["/usr/bin/find", search_root, "-type", "f", "-name", "SKILL.md"])
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

    skill_path_prefix = _normalize_relpath(repo_ctx.attr.skill_path_prefix, "skill_path_prefix")
    if skill_path_prefix and not repo_ctx.path(skill_path_prefix).exists:
        fail("skill_path_prefix %r does not exist in extracted archive" % skill_path_prefix)

    skill_roots = sorted(_discover_skill_roots(repo_ctx, skill_path_prefix))

    repo_ctx.file("BUILD.bazel", _build_file_for_skills(repo_ctx.attr.repo_name, skill_roots))


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
        if registry["strip_prefix"]:
            kwargs["stripPrefix"] = registry["strip_prefix"]
        repo_ctx.download_and_extract(**kwargs)

        search_prefix = _join_relpath(output_dir, registry["skill_path_prefix"])
        if registry["skill_path_prefix"] and not repo_ctx.path(search_prefix).exists:
            fail("registry %r declared skill_path_prefix %r that does not exist in extracted archive" % (
                registry_id,
                registry["skill_path_prefix"],
            ))

        skill_roots = _discover_skill_roots(repo_ctx, search_prefix)
        skills = []
        for skill_root in sorted(skill_roots):
            target_name = _target_name_for_skill(registry_id, skill_root)
            frontmatter = _parse_frontmatter(repo_ctx.read(skill_root + "/SKILL.md"))
            skills.append({
                "skill_name": target_name,
                "display_name": frontmatter.get("name", target_name),
                "description": frontmatter.get("description", ""),
                "skill_path": skill_root[len(output_dir) + 1:] if skill_root.startswith(output_dir + "/") else skill_root,
                "source_url": _source_url_for_skill(
                    registry,
                    skill_root[len(output_dir) + 1:] if skill_root.startswith(output_dir + "/") else skill_root,
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
