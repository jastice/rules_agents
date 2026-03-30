"""Module extensions for remote skill dependencies."""


def _skill_deps_impl(_ctx):
    return None


skill_deps = module_extension(
    implementation = _skill_deps_impl,
)
