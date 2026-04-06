#!/usr/bin/env bash
set -euo pipefail

json_mode=false
filter_registry=""
filter_skill=""
filter_agent=""

for arg in "$@"; do
  case "$arg" in
    --json)       json_mode=true ;;
    --registry=*) filter_registry="${arg#--registry=}" ;;
    --skill=*)    filter_skill="${arg#--skill=}" ;;
    --agent=*)    filter_agent="${arg#--agent=}" ;;
    *)            echo "error: unknown flag $arg" >&2; exit 1 ;;
  esac
done

if "$json_mode"; then
  cat <<'__JSON_EOF__'
__AGGREGATE_JSON__
__JSON_EOF__
  exit 0
fi

awk -F'\t' -v filter_reg="$filter_registry" -v filter_skill="$filter_skill" -v filter_agent="$filter_agent" '
{
  if (NF == 0) next
  reg_id = $1
  agents = $2
  archive_url = $3
  strip_prefix = $4
  skill_path_prefix = $5
  skill_name = $6
  description = $7
  source_url = $8
  target_label = $9

  if (filter_reg != "" && reg_id != filter_reg) next
  if (filter_agent != "") {
    n = split(agents, agent_list, ",")
    found = 0
    for (i = 1; i <= n; i++) {
      if (agent_list[i] == filter_agent) { found = 1; break }
    }
    if (!found) next
  }
  if (filter_skill != "" && skill_name != filter_skill) next

  if (reg_id != current_registry) {
    if (registry_count > 0) printf "\n"
    current_registry = reg_id
    registry_count++

    print "Registry: " reg_id
    printf "\n"
    print "Add:"
    print "  skill_deps = use_extension("
    print "      \"@rules_agents//rules_agents:extensions.bzl\","
    print "      \"skill_deps\","
    print "  )"
    print "  skill_deps.remote("
    printf "      name = \"%s\",\n", reg_id
    printf "      url = \"%s\",\n", archive_url
    if (strip_prefix != "") printf "      strip_prefix = \"%s\",\n", strip_prefix
    if (skill_path_prefix != "") printf "      skill_path_prefix = \"%s\",\n", skill_path_prefix
    print "  )"
    printf "  use_repo(skill_deps, \"%s\")\n", reg_id
  }

  printf "\n"
  print "- " skill_name
  if (description != "") print "  Description: " description
  if (source_url != "") print "  Source: " source_url
  print "  Target: " target_label
}
END {
  if (registry_count == 0) {
    print "No skills discovered from configured registries."
  }
}
' <<'__TSV_EOF__'
__SKILLS_TSV__
__TSV_EOF__
