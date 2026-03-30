"""Implementation of the `agent_skill` rule."""

load(":providers.bzl", "AgentSkillInfo")

_INVALID_ROOT_SEGMENTS = (
    "..",
    ".",
)


def _sanitize_fragment(value):
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    pieces = []
    for index in range(len(value)):
        char = value[index]
        if char in allowed:
            pieces.append(char.lower())
        else:
            pieces.append("_")

    sanitized = "".join(pieces).strip("_")
    return sanitized or "root"


def _skill_id(label):
    fragments = []
    if label.workspace_name:
        fragments.append(label.workspace_name)
    else:
        fragments.append("main")

    if label.package:
        fragments.append(label.package)

    fragments.append(label.name)
    return "__".join([_sanitize_fragment(fragment) for fragment in fragments])


def _validate_root(root):
    if not root:
        fail("root must be a non-empty relative path")
    if root.startswith("/") or root.endswith("/"):
        fail("root must be a normalized relative path, got %r" % root)
    if "//" in root:
        fail("root must not contain empty path segments, got %r" % root)
    for segment in root.split("/"):
        if segment in _INVALID_ROOT_SEGMENTS:
            fail("root must not contain %r segments, got %r" % (segment, root))


def _root_prefix(label, root):
    if label.package:
        return label.package + "/" + root
    return root


def _bundle_relpath(file, bundle_root):
    if file.short_path == bundle_root:
        fail("srcs must contain files under %r, got %r" % (bundle_root, file.short_path))
    prefix = bundle_root + "/"
    if not file.short_path.startswith(prefix):
        fail(
            "src %r is outside root %r; expected files under %r" % (
                file.short_path,
                bundle_root,
                bundle_root,
            ),
        )
    return file.short_path[len(prefix):]


def _agent_skill_impl(ctx):
    _validate_root(ctx.attr.root)

    bundle_root = _root_prefix(ctx.label, ctx.attr.root)
    bundle = ctx.actions.declare_directory(ctx.label.name)

    if not ctx.files.srcs:
        fail("agent_skill requires at least one source file")

    source_mappings = []
    has_skill_md = False

    srcs_by_short_path = {src.short_path: src for src in ctx.files.srcs}
    for short_path in sorted(srcs_by_short_path.keys()):
        src = srcs_by_short_path[short_path]
        relpath = _bundle_relpath(src, bundle_root)
        if relpath == "SKILL.md":
            has_skill_md = True
        source_mappings.append("%s=%s" % (src.path, relpath))

    if not has_skill_md:
        fail("agent_skill %r is missing %s/SKILL.md" % (ctx.label, ctx.attr.root))

    args = ctx.actions.args()
    args.add_all(source_mappings)

    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [bundle],
        arguments = [bundle.path, args],
        command = """
set -euo pipefail

out="$1"
shift
rm -rf "$out"
mkdir -p "$out"

for mapping in "$@"; do
  src="${mapping%%=*}"
  rel="${mapping#*=}"
  dest="$out/$rel"
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
done
""",
        mnemonic = "PackageAgentSkill",
        progress_message = "Packaging agent skill %s" % ctx.label,
    )

    return [
        DefaultInfo(files = depset([bundle])),
        AgentSkillInfo(
            bundle = bundle,
            logical_name = ctx.label.name,
            root = ctx.attr.root,
            skill_id = _skill_id(ctx.label),
        ),
    ]


agent_skill = rule(
    implementation = _agent_skill_impl,
    attrs = {
        "root": attr.string(mandatory = True),
        "srcs": attr.label_list(
            allow_files = True,
        ),
    },
)
