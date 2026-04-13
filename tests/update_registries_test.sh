#!/usr/bin/env bash

set -euo pipefail

readonly UPDATE_BIN="${TEST_SRCDIR}/_main/tools/update_registries"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

main() {
  local tmp_root="${TEST_TMPDIR:-$(mktemp -d /tmp/rules_agents_update_test.XXXXXX)}"
  local catalog_path="${tmp_root}/registries.json"
  local fake_bin_dir="${tmp_root}/bin"
  local output_path="${tmp_root}/updated.json"

  mkdir -p "$fake_bin_dir"

  cat > "$catalog_path" <<'EOF'
{
  "version": 1,
  "registries": [
    {
      "id": "openai_skills",
      "homepage": "https://github.com/openai/skills",
      "repo_url": "https://github.com/openai/skills",
      "archive_url": "https://github.com/openai/skills/archive/refs/heads/main.tar.gz",
      "strip_prefix": "skills-main",
      "default_branch": "main"
    },
    {
      "id": "anthropic_skills",
      "homepage": "https://github.com/anthropics/skills",
      "repo_url": "https://github.com/anthropics/skills",
      "archive_url": "https://github.com/anthropics/skills/archive/refs/heads/main.tar.gz",
      "strip_prefix": "skills-main",
      "default_branch": "main"
    }
  ]
}
EOF

  cat > "${fake_bin_dir}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" != "ls-remote" ]]; then
  echo "unexpected git command: $*" >&2
  exit 1
fi

case "$2" in
  https://github.com/openai/skills)
    printf '0123456789abcdef0123456789abcdef01234567\t%s\n' "$3"
    ;;
  https://github.com/anthropics/skills)
    printf '89abcdef0123456789abcdef0123456789abcdef\t%s\n' "$3"
    ;;
  *)
    echo "unexpected repo url: $2" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${fake_bin_dir}/git"

  (
    export PATH="${fake_bin_dir}:/usr/bin:/bin"
    "$UPDATE_BIN" --catalog "$catalog_path" > "$output_path"
  )

  grep -q 'openai/skills/archive/0123456789abcdef0123456789abcdef01234567.tar.gz' "$output_path" || \
    fail "stdout output did not pin openai_skills archive_url"
  grep -q '"strip_prefix": "skills-0123456789abcdef0123456789abcdef01234567"' "$output_path" || \
    fail "stdout output did not update openai_skills strip_prefix"
  grep -q 'anthropics/skills/archive/89abcdef0123456789abcdef0123456789abcdef.tar.gz' "$output_path" || \
    fail "stdout output did not pin anthropic_skills archive_url"

  (
    export PATH="${fake_bin_dir}:/usr/bin:/bin"
    "$UPDATE_BIN" --catalog "$catalog_path" --registry openai_skills --apply
  ) > "${tmp_root}/apply.out"

  grep -q 'openai/skills/archive/0123456789abcdef0123456789abcdef01234567.tar.gz' "$catalog_path" || \
    fail "--apply did not write updated openai_skills archive_url"
  grep -q 'anthropics/skills/archive/refs/heads/main.tar.gz' "$catalog_path" || \
    fail "--registry filter unexpectedly rewrote anthropic_skills"
}

main "$@"
