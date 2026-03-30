"""Providers used by internal rules_agents implementation."""

AgentSkillInfo = provider(
    doc = "Metadata for one packaged skill bundle.",
    fields = {
        "bundle": "Tree artifact containing the packaged skill bundle.",
        "logical_name": "Public skill name for the bundle.",
        "root": "Logical source root declared by the user.",
        "skill_id": "Stable identifier derived from the target label.",
    },
)
