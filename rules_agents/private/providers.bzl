"""Providers used by internal rules_agents implementation."""

AgentSkillInfo = provider(
    doc = "Metadata for one packaged skill bundle.",
    fields = {
        "bundle_dir": "Tree artifact containing the packaged skill bundle.",
        "logical_name": "Public skill name for the bundle.",
        "src_root": "Logical source root declared by the user.",
        "skill_id": "Stable identifier derived from the target label.",
    },
)

AgentProfileInfo = provider(
    doc = "Metadata for one built agent profile artifact.",
    fields = {
        "credential_env": "Sorted credential environment variable names for the profile.",
        "manifest": "File containing the portable profile manifest.",
        "profile_name": "Declared profile name.",
        "skills": "Ordered list of AgentSkillInfo values for the profile.",
    },
)
