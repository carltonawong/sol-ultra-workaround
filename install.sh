#!/usr/bin/env sh
set -eu
umask 077

usage() { echo "Usage: ./install.sh profile" >&2; echo "   or: ./install.sh project /absolute/project/root" >&2; exit 2; }
[ "$#" -ge 1 ] || usage
mode=$1
project_root=${2:-}
package_root=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
source_config="$package_root/profiles/sol-ultra.config.toml"
source_agent="$package_root/agents/terra-high.toml"
source_guidance="$package_root/profiles/sol-ultra.AGENTS.md"
begin_marker='<!-- SOL-ULTRA-WORKAROUND:BEGIN -->'
end_marker='<!-- SOL-ULTRA-WORKAROUND:END -->'

normalize_future_directory() {
  future_path=$1
  case "$future_path" in /*) ;; *) future_path="$(pwd -P)/$future_path";; esac
  case "/$future_path/" in */../*|*/./*) echo "Refusing a non-normalized path: $future_path" >&2; return 1;; esac
  suffix=
  while [ ! -d "$future_path" ]; do
    if [ -e "$future_path" ] || [ -L "$future_path" ]; then echo "Expected a directory: $future_path" >&2; return 1; fi
    suffix="/$(basename "$future_path")$suffix"; parent=$(dirname "$future_path")
    [ "$parent" != "$future_path" ] || return 1; future_path=$parent
  done
  physical_parent=$(CDPATH= cd -- "$future_path" && pwd -P); printf '%s%s\n' "$physical_parent" "$suffix"
}
refuse_linked_directory() {
  if [ -L "$1" ]; then echo "Refusing a linked or redirected target directory: $1" >&2; exit 1; fi
  if [ -e "$1" ] && [ ! -d "$1" ]; then echo "Expected a directory: $1" >&2; exit 1; fi
}
is_plain_file() { [ -f "$1" ] && [ ! -L "$1" ]; }
safe_text_file() {
  is_plain_file "$1" || return 1
  # NUL bytes identify UTF-16 and the common binary forms we must never rewrite.
  bytes=$(od -An -v -tx1 "$1") || return 1
  if printf '%s\n' "$bytes" | grep -Eq '(^|[[:space:]])00([[:space:]]|$)'; then return 1; fi
  return 0
}
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else echo "No SHA-256 utility found." >&2; return 1; fi
}
count_exact_line() { grep -F -x "$1" "$2" | wc -l | tr -d ' '; }
has_guidance_marker() { grep -F "$begin_marker" "$1" >/dev/null 2>&1 || grep -F "$end_marker" "$1" >/dev/null 2>&1; }
validate_block() {
  safe_text_file "$1" || return 1
  [ "$(count_exact_line "$begin_marker" "$1")" = 1 ] && [ "$(count_exact_line "$end_marker" "$1")" = 1 ]
}

codex_home=$(normalize_future_directory "${CODEX_HOME:-$HOME/.codex}")
legacy_default="$codex_home/agents/default.toml"
if [ -e "$legacy_default" ] || [ -L "$legacy_default" ]; then echo "Existing global agents/default.toml detected." >&2; exit 1; fi
for source in "$source_config" "$source_agent"; do is_plain_file "$source" || { echo "Invalid package payload: $source" >&2; exit 1; }; done

guidance_action=none; guidance_file=none; guidance_target=; guidance_parent=; guidance_backup=; guidance_block=; guidance_pre_hash=none; guidance_existed=0
case "$mode" in
  profile)
    [ "$#" -eq 1 ] || usage
    target_config="$codex_home/sol-ultra.config.toml"; target_agent="$codex_home/sol-ultra-workaround/terra-high.toml";;
  project)
    [ "$#" -eq 2 ] || usage
    case "$project_root" in /*) ;; *) echo "Project root must be absolute: $project_root" >&2; exit 2;; esac
    project_root=$(CDPATH= cd -- "$project_root" && pwd -P); home_root=$(CDPATH= cd -- "$HOME" && pwd -P)
    [ "$project_root" != / ] && [ "$project_root" != "$home_root" ] || { echo "Refusing unsafe project root." >&2; exit 1; }
    case "$project_root" in "$package_root"|"$package_root"/*) echo "Refusing package checkout as project root." >&2; exit 1;; esac
    project_codex_dir="$project_root/.codex"; refuse_linked_directory "$project_codex_dir"
    [ "${codex_home%/}" != "$project_codex_dir" ] || { echo "Refusing CODEX_HOME as project root." >&2; exit 1; }
    existing_default="$project_codex_dir/agents/default.toml"
    if [ -e "$existing_default" ] || [ -L "$existing_default" ]; then echo "Refusing to shadow existing project agent: $existing_default" >&2; exit 1; fi
    target_config="$project_codex_dir/config.toml"; target_agent="$project_codex_dir/sol-ultra-workaround/terra-high.toml"
    if [ -e "$project_root/AGENTS.override.md" ] || [ -L "$project_root/AGENTS.override.md" ]; then guidance_file=AGENTS.override.md
    else guidance_file=AGENTS.md; fi
    guidance_target="$project_root/$guidance_file"; guidance_parent=$(dirname "$guidance_target")
    guidance_backup="$project_codex_dir/sol-ultra-workaround/$guidance_file.preinstall.bak"
    guidance_block="$project_codex_dir/sol-ultra-workaround/guidance-block.md"
    validate_block "$source_guidance" || { echo "Invalid canonical guidance block: $source_guidance" >&2; exit 1; }
    if [ -e "$guidance_target" ] || [ -L "$guidance_target" ]; then
      safe_text_file "$guidance_target" || { echo "Refusing non-regular, linked, or binary guidance: $guidance_target" >&2; exit 1; }
      ! has_guidance_marker "$guidance_target" || { echo "Existing SOL Ultra guidance markers found; refusing to modify $guidance_target" >&2; exit 1; }
      guidance_existed=1
    fi;;
  *) usage;;
esac

config_parent=$(dirname "$target_config"); agent_parent=$(dirname "$target_agent"); target_state="$agent_parent/install-state.txt"
refuse_linked_directory "$config_parent"; refuse_linked_directory "$agent_parent"
for target in "$target_config" "$target_agent" "$target_state"; do if [ -e "$target" ] || [ -L "$target" ]; then echo "Refusing to overwrite existing filesystem object: $target" >&2; exit 1; fi; done
if [ "$mode" = project ]; then for target in "$guidance_block" "$guidance_backup"; do if [ -e "$target" ] || [ -L "$target" ]; then echo "Refusing owned target: $target" >&2; exit 1; fi; done; fi

config_parent_created=0; agent_parent_created=0; [ -d "$config_parent" ] || config_parent_created=1; [ -d "$agent_parent" ] || agent_parent_created=1
created_config=0; created_agent=0; created_state=0; created_block=0; created_backup=0; guidance_frozen=0; guidance_linked=0; guidance_stage=; guidance_original=; guidance_expected=; pending_temp=; recovery_needed=0
recover_guidance() {
  [ -n "$guidance_stage" ] || return 0
  if [ "$guidance_linked" -eq 1 ] && { [ -e "$guidance_target" ] || [ -L "$guidance_target" ]; }; then
    rollback_current="$guidance_stage/current-at-failure"
    if mv "$guidance_target" "$rollback_current" 2>/dev/null; then
      if is_plain_file "$rollback_current" && [ -f "$guidance_expected" ] && cmp -s "$rollback_current" "$guidance_expected"; then
        rm -f "$rollback_current"
      else
        if [ ! -e "$guidance_target" ] && [ ! -L "$guidance_target" ]; then ln "$rollback_current" "$guidance_target" 2>/dev/null || true; fi
        echo "Recovery required: a different file was preserved at $guidance_target or $rollback_current." >&2
        recovery_needed=1
      fi
    fi
  fi
  if [ "$guidance_frozen" -eq 1 ]; then
    if [ ! -e "$guidance_target" ] && [ ! -L "$guidance_target" ]; then
      if ln "$guidance_original" "$guidance_target" 2>/dev/null; then rm -f "$guidance_original"; guidance_frozen=0
      else echo "Recovery required: restore the original guidance from $guidance_original" >&2; recovery_needed=1; fi
    else
      echo "Recovery required: original guidance remains at $guidance_original" >&2
      recovery_needed=1
    fi
  fi
  if [ "$recovery_needed" -eq 0 ]; then rm -rf "$guidance_stage"; guidance_stage=
  else echo "Installer staging retained for recovery: $guidance_stage" >&2; fi
}
cleanup() {
  [ -z "$pending_temp" ] || rm -f "$pending_temp"
  recover_guidance
  [ "$created_state" -eq 0 ] || rm -f "$target_state"; [ "$created_agent" -eq 0 ] || rm -f "$target_agent"; [ "$created_config" -eq 0 ] || rm -f "$target_config"
  [ "$created_block" -eq 0 ] || rm -f "$guidance_block"; [ "$created_backup" -eq 0 ] || rm -f "$guidance_backup"
  [ "$agent_parent_created" -eq 0 ] || rmdir "$agent_parent" 2>/dev/null || true; [ "$config_parent_created" -eq 0 ] || rmdir "$config_parent" 2>/dev/null || true
}
on_exit() { status=$?; [ "$status" -eq 0 ] || cleanup; }
trap on_exit 0; trap 'trap - 0 1 2 15; cleanup; exit 1' 1 2 15
mkdir -p "$config_parent" "$agent_parent"
install_source_file() { pending_temp=$(mktemp "$(dirname "$2")/.sol-ultra-workaround.XXXXXX"); cp "$1" "$pending_temp"; ln "$pending_temp" "$2" || { echo "Refusing a target created during installation: $2" >&2; return 1; }; rm -f "$pending_temp"; pending_temp=; case "$3" in config) created_config=1;; agent) created_agent=1;; block) created_block=1;; backup) created_backup=1;; esac; }
install_source_file "$source_config" "$target_config" config; install_source_file "$source_agent" "$target_agent" agent
if [ "$mode" = project ]; then
  install_source_file "$source_guidance" "$guidance_block" block
  guidance_stage=$(mktemp -d "$guidance_parent/.sol-ultra-install.XXXXXX")
  guidance_original="$guidance_stage/original"; guidance_candidate="$guidance_stage/replacement"; guidance_expected="$guidance_stage/expected"
  if [ "$guidance_existed" -eq 1 ]; then
    mv "$guidance_target" "$guidance_original" || { echo "Existing guidance changed before it could be frozen." >&2; exit 1; }
    guidance_frozen=1; guidance_action=appended
    safe_text_file "$guidance_original" || { echo "Refusing non-regular, linked, or binary frozen guidance: $guidance_original" >&2; exit 1; }
    ! has_guidance_marker "$guidance_original" || { echo "Frozen guidance contains SOL Ultra markers." >&2; exit 1; }
    guidance_pre_hash=$(sha256_file "$guidance_original")
    install_source_file "$guidance_original" "$guidance_backup" backup
    cat "$guidance_original" > "$guidance_candidate"
    last_byte=$(od -An -tx1 "$guidance_original" | awk '{last=$NF} END {print last}')
    [ "$last_byte" = 0a ] || printf '\n' >> "$guidance_candidate"
    cat "$source_guidance" >> "$guidance_candidate"
  else
    guidance_action=created
    cp "$source_guidance" "$guidance_candidate"
  fi
  cp "$guidance_candidate" "$guidance_expected"
  if [ "$guidance_file" = AGENTS.md ] && { [ -e "$project_root/AGENTS.override.md" ] || [ -L "$project_root/AGENTS.override.md" ]; }; then
    echo "AGENTS.override.md appeared during installation; refusing a stale guidance target." >&2; exit 1
  fi
  if ! ln "$guidance_candidate" "$guidance_target" 2>/dev/null; then
    echo "Guidance target appeared during installation and was preserved: $guidance_target" >&2
    exit 1
  fi
  guidance_linked=1; rm -f "$guidance_candidate"
fi
if ! cmp -s "$source_config" "$target_config" || ! cmp -s "$source_agent" "$target_agent"; then echo "Installation verification failed." >&2; exit 1; fi
config_hash=$(sha256_file "$target_config"); agent_hash=$(sha256_file "$target_agent")
guidance_post_hash=none; guidance_backup_hash=none; guidance_block_hash=none
if [ "$mode" = project ]; then guidance_post_hash=$(sha256_file "$guidance_expected"); guidance_block_hash=$(sha256_file "$guidance_block"); [ "$guidance_action" != appended ] || guidance_backup_hash=$(sha256_file "$guidance_backup"); fi
pending_temp=$(mktemp "$agent_parent/.sol-ultra-workaround.XXXXXX")
printf 'schema=2\nmode=%s\nconfig_sha256=%s\nagent_sha256=%s\nconfig_parent_created=%s\nagent_parent_created=%s\nguidance_action=%s\nguidance_file=%s\nguidance_pre_sha256=%s\nguidance_post_sha256=%s\nguidance_backup_sha256=%s\nguidance_block_sha256=%s\n' "$mode" "$config_hash" "$agent_hash" "$config_parent_created" "$agent_parent_created" "$guidance_action" "$guidance_file" "$guidance_pre_hash" "$guidance_post_hash" "$guidance_backup_hash" "$guidance_block_hash" > "$pending_temp"
ln "$pending_temp" "$target_state" || { echo "Refusing a state file created during installation." >&2; exit 1; }; created_state=1; rm -f "$pending_temp"; pending_temp=
if [ -n "$guidance_stage" ]; then rm -rf "$guidance_stage"; guidance_stage=; guidance_frozen=0; guidance_linked=0; fi
trap - 0 1 2 15
echo "Installed SOL Ultra Workaround in $mode mode."
if [ "$mode" = profile ]; then echo "Launch: codex --profile sol-ultra"; echo "Resume: codex resume --profile sol-ultra <SESSION_ID_OR_NAME>"
else
  echo "Project mode: open and trust this folder or workspace, then create a new task inside it: $project_root"
  echo "Managed guidance: $guidance_target ($guidance_action)."
  [ "$guidance_action" != appended ] || echo "Guidance backup: $guidance_backup"
fi
