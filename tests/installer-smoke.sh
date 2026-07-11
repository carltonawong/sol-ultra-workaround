#!/usr/bin/env sh
set -eu

fail() {
  echo "ASSERTION FAILED: $*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/sol-ultra-smoke.XXXXXX")
trap 'rm -rf "$test_root"' 0 1 2 15

grep -Fq 'fork_turns="none"' "$repo_root/profiles/sol-ultra.config.toml" || fail "isolated V2 fork policy missing"
! grep -Fq 'fork_turns="all"' "$repo_root/profiles/sol-ultra.config.toml" || fail "full-history V2 fork permitted"
grep -Fq 'Only the active root may spawn' "$repo_root/profiles/sol-ultra.AGENTS.md" || fail "root-only spawn policy missing"
grep -Fq "A child's self-report is not evidence" "$repo_root/profiles/sol-ultra.AGENTS.md" || fail "root runtime check missing"
grep -Fq 'Never call followup_task' "$repo_root/profiles/sol-ultra.config.toml" || fail "config permits completed-child reuse"
grep -Fq 'Never call `followup_task`' "$repo_root/profiles/sol-ultra.AGENTS.md" || fail "guidance permits completed-child reuse"
grep -Fq 'exactly one triggered child turn' "$repo_root/profiles/sol-ultra.AGENTS.md" || fail "root single-turn verification missing"
grep -Fq 'CODEX_THREAD_ID' "$repo_root/agents/terra-high.toml" || fail "child rollout discovery recipe missing"
grep -Fq 'RUNTIME_OK model=gpt-5.6-terra effort=high isolated=true' "$repo_root/agents/terra-high.toml" || fail "success contract missing"
grep -Fq 'ROUTING_FAILURE' "$repo_root/agents/terra-high.toml" || fail "failure contract missing"
grep -Fq 'reason=completed_child_reuse' "$repo_root/agents/terra-high.toml" || fail "child reuse failure contract missing"
grep -Fq 'exactly one inter_agent_communication_metadata event' "$repo_root/agents/terra-high.toml" || fail "child single-turn verification missing"
! grep -Fq 'RUNTIME_UNVERIFIED' "$repo_root/agents/terra-high.toml" || fail "runtime contract has a third state"

# Profile mode must not create or modify global guidance.
profile_home="$test_root/profile-home"
mkdir -p "$profile_home"
CODEX_HOME="$profile_home"; export CODEX_HOME
"$repo_root/install.sh" profile >/dev/null
grep -q '^schema=2$' "$profile_home/sol-ultra-workaround/install-state.txt" || fail "profile schema"
grep -q '^guidance_action=none$' "$profile_home/sol-ultra-workaround/install-state.txt" || fail "profile guidance action"
[ ! -e "$profile_home/AGENTS.md" ] || fail "profile created AGENTS.md"
"$repo_root/uninstall.sh" profile >/dev/null
[ ! -e "$profile_home/sol-ultra.config.toml" ] || fail "profile config remained"

# Existing guidance is backed up exactly and later edits survive block removal.
project="$test_root/existing-project"
mkdir -p "$project"
printf '# Existing guidance\n\nKeep this.\n' > "$project/AGENTS.md"
cp "$project/AGENTS.md" "$test_root/original-agents"
"$repo_root/install.sh" project "$project" >/dev/null
backup="$project/.codex/sol-ultra-workaround/AGENTS.md.preinstall.bak"
installed_block="$project/.codex/sol-ultra-workaround/guidance-block.md"
cmp -s "$backup" "$test_root/original-agents" || fail "guidance backup differs"
cmp -s "$installed_block" "$repo_root/profiles/sol-ultra.AGENTS.md" || fail "installed guidance block differs"
printf '\nUSER_EDIT_AFTER_INSTALL\n' >> "$project/AGENTS.md"
"$repo_root/uninstall.sh" project "$project" >/dev/null
grep -q '# Existing guidance' "$project/AGENTS.md" || fail "original guidance lost"
grep -q 'USER_EDIT_AFTER_INSTALL' "$project/AGENTS.md" || fail "later edit lost"
! grep -q 'SOL-ULTRA-WORKAROUND:BEGIN' "$project/AGENTS.md" || fail "managed block remained"

# Installer-created unchanged guidance is removed.
created_project="$test_root/created-project"
mkdir -p "$created_project"
"$repo_root/install.sh" project "$created_project" >/dev/null
[ -f "$created_project/AGENTS.md" ] || fail "guidance was not created"
"$repo_root/uninstall.sh" project "$created_project" >/dev/null
[ ! -e "$created_project/AGENTS.md" ] || fail "unchanged created guidance remained"

# An active override is managed; the shadowed AGENTS.md stays byte-identical.
override_project="$test_root/override-project"
mkdir -p "$override_project"
printf 'NORMAL_ONLY\n' > "$override_project/AGENTS.md"
printf 'OVERRIDE_ONLY\n' > "$override_project/AGENTS.override.md"
normal_hash=$(sha256_file "$override_project/AGENTS.md")
"$repo_root/install.sh" project "$override_project" >/dev/null
[ "$(sha256_file "$override_project/AGENTS.md")" = "$normal_hash" ] || fail "shadowed AGENTS.md changed"
grep -q 'SOL-ULTRA-WORKAROUND:BEGIN' "$override_project/AGENTS.override.md" || fail "override not managed"
"$repo_root/uninstall.sh" project "$override_project" >/dev/null
[ "$(cat "$override_project/AGENTS.override.md")" = 'OVERRIDE_ONLY' ] || fail "override not restored"
[ "$(sha256_file "$override_project/AGENTS.md")" = "$normal_hash" ] || fail "normal guidance changed during uninstall"

# A malformed/pre-existing marker is a conflict and leaves no package payload.
marker_project="$test_root/marker-project"
mkdir -p "$marker_project"
printf 'user text <!-- SOL-ULTRA-WORKAROUND:BEGIN --> malformed\n' > "$marker_project/AGENTS.md"
if "$repo_root/install.sh" project "$marker_project" >/dev/null 2>&1; then
  fail "pre-existing marker did not stop install"
fi
[ ! -e "$marker_project/.codex/config.toml" ] || fail "marker conflict left config"

# NUL-containing guidance is binary and must never be rewritten.
binary_project="$test_root/binary-project"
mkdir -p "$binary_project"
printf 'user\000data' > "$binary_project/AGENTS.md"
if "$repo_root/install.sh" project "$binary_project" >/dev/null 2>&1; then
  fail "binary guidance did not stop install"
fi
[ ! -e "$binary_project/.codex/config.toml" ] || fail "binary conflict left config"

# A modified managed block fails closed before removing owned files.
tamper_project="$test_root/tamper-project"
mkdir -p "$tamper_project"
printf 'ORIGINAL\n' > "$tamper_project/AGENTS.md"
"$repo_root/install.sh" project "$tamper_project" >/dev/null
sed 's/Only the active root may spawn/Only a changed root may spawn/' \
  "$tamper_project/AGENTS.md" > "$tamper_project/AGENTS.md.changed"
mv "$tamper_project/AGENTS.md.changed" "$tamper_project/AGENTS.md"
tamper_config="$tamper_project/.codex/config.toml"
tamper_hash=$(sha256_file "$tamper_config")
if "$repo_root/uninstall.sh" project "$tamper_project" >/dev/null 2>&1; then
  fail "tampered managed block did not stop uninstall"
fi
[ "$(sha256_file "$tamper_config")" = "$tamper_hash" ] || fail "failed uninstall changed config"
[ -f "$tamper_project/.codex/sol-ultra-workaround/install-state.txt" ] || fail "failed uninstall removed state"

# A modified exact backup must stop uninstall before package removal.
backup_tamper_project="$test_root/backup-tamper-project"
mkdir -p "$backup_tamper_project"
printf 'KEEP_ME\n' > "$backup_tamper_project/AGENTS.md"
"$repo_root/install.sh" project "$backup_tamper_project" >/dev/null
printf 'tamper' >> "$backup_tamper_project/.codex/sol-ultra-workaround/AGENTS.md.preinstall.bak"
if "$repo_root/uninstall.sh" project "$backup_tamper_project" >/dev/null 2>&1; then
  fail "tampered backup did not stop uninstall"
fi
[ -f "$backup_tamper_project/.codex/config.toml" ] || fail "backup failure removed config"

# Schema-1 profile installs remain removable by the new uninstaller.
legacy_home="$test_root/legacy-home"
legacy_dir="$legacy_home/sol-ultra-workaround"
mkdir -p "$legacy_dir"
cp "$repo_root/profiles/sol-ultra.config.toml" "$legacy_home/sol-ultra.config.toml"
cp "$repo_root/agents/terra-high.toml" "$legacy_dir/terra-high.toml"
legacy_config_hash=$(sha256_file "$legacy_home/sol-ultra.config.toml")
legacy_agent_hash=$(sha256_file "$legacy_dir/terra-high.toml")
printf 'schema=1\nmode=profile\nconfig_sha256=%s\nagent_sha256=%s\nconfig_parent_created=0\nagent_parent_created=1\n' \
  "$legacy_config_hash" "$legacy_agent_hash" > "$legacy_dir/install-state.txt"
CODEX_HOME="$legacy_home"; export CODEX_HOME
"$repo_root/uninstall.sh" profile >/dev/null
[ ! -e "$legacy_home/sol-ultra.config.toml" ] || fail "schema-1 config remained"
[ ! -e "$legacy_dir/terra-high.toml" ] || fail "schema-1 agent remained"

# Schema-1 project uninstall must leave root guidance untouched.
legacy_project="$test_root/legacy-project"
legacy_project_dir="$legacy_project/.codex/sol-ultra-workaround"
mkdir -p "$legacy_project_dir"
printf 'LEGACY_GUIDANCE\n' > "$legacy_project/AGENTS.md"
cp "$repo_root/profiles/sol-ultra.config.toml" "$legacy_project/.codex/config.toml"
cp "$repo_root/agents/terra-high.toml" "$legacy_project_dir/terra-high.toml"
legacy_project_config_hash=$(sha256_file "$legacy_project/.codex/config.toml")
legacy_project_agent_hash=$(sha256_file "$legacy_project_dir/terra-high.toml")
printf 'schema=1\nmode=project\nconfig_sha256=%s\nagent_sha256=%s\nconfig_parent_created=1\nagent_parent_created=1\n' \
  "$legacy_project_config_hash" "$legacy_project_agent_hash" > "$legacy_project_dir/install-state.txt"
"$repo_root/uninstall.sh" project "$legacy_project" >/dev/null
[ ! -e "$legacy_project/.codex/config.toml" ] || fail "schema-1 project config remained"
[ "$(cat "$legacy_project/AGENTS.md")" = 'LEGACY_GUIDANCE' ] || fail "schema-1 uninstall changed guidance"

echo "POSIX installer smoke tests passed."
