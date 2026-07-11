#!/usr/bin/env sh
set -eu
umask 077

mode=${1:-profile}
project_root=${2:-$(pwd)}
package_root=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
begin_marker='<!-- SOL-ULTRA-WORKAROUND:BEGIN -->'
end_marker='<!-- SOL-ULTRA-WORKAROUND:END -->'

normalize_future_directory() {
  future_path=$1; case "$future_path" in /*) ;; *) future_path="$(pwd -P)/$future_path";; esac
  case "/$future_path/" in */../*|*/./*) echo "Refusing a non-normalized path: $future_path" >&2; return 1;; esac
  suffix=; while [ ! -d "$future_path" ]; do
    if [ -e "$future_path" ] || [ -L "$future_path" ]; then echo "Expected a directory: $future_path" >&2; return 1; fi
    suffix="/$(basename "$future_path")$suffix"; parent=$(dirname "$future_path"); [ "$parent" != "$future_path" ] || return 1; future_path=$parent
  done
  physical_parent=$(CDPATH= cd -- "$future_path" && pwd -P); printf '%s%s\n' "$physical_parent" "$suffix"
}
refuse_linked_directory() { if [ -L "$1" ]; then echo "Refusing linked directory: $1" >&2; exit 1; fi; if [ -e "$1" ] && [ ! -d "$1" ]; then echo "Expected directory: $1" >&2; exit 1; fi; }
is_plain_file() { [ -f "$1" ] && [ ! -L "$1" ]; }
safe_text_file() { is_plain_file "$1" || return 1; bytes=$(od -An -v -tx1 "$1") || return 1; if printf '%s\n' "$bytes" | grep -Eq '(^|[[:space:]])00([[:space:]]|$)'; then return 1; fi; return 0; }
sha256_file() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else echo "No SHA-256 utility found." >&2; return 1; fi; }
valid_hash() { case "$1" in *[!0-9a-f]*|'') return 1;; esac; [ "${#1}" -eq 64 ]; }
count_exact_line() { grep -F -x "$1" "$2" | wc -l | tr -d ' '; }
invalid() { echo "Invalid install state. Refusing to remove anything." >&2; exit 1; }

codex_home=$(normalize_future_directory "${CODEX_HOME:-$HOME/.codex}")
guidance_target=; guidance_backup=; guidance_block=
case "$mode" in
  profile) target_config="$codex_home/sol-ultra.config.toml"; target_agent="$codex_home/sol-ultra-workaround/terra-high.toml";;
  project)
    case "$project_root" in /*) ;; *) echo "Project root must be absolute." >&2; exit 2;; esac
    project_root=$(CDPATH= cd -- "$project_root" && pwd -P); home_root=$(CDPATH= cd -- "$HOME" && pwd -P)
    [ "$project_root" != / ] && [ "$project_root" != "$home_root" ] || { echo "Refusing unsafe project root." >&2; exit 1; }
    if [ "$project_root" = "$package_root" ] && [ -f "$package_root/profiles/sol-ultra.config.toml" ]; then echo "Refusing package checkout as project root." >&2; exit 1; fi
    project_codex_dir="$project_root/.codex"; refuse_linked_directory "$project_codex_dir"; [ "${codex_home%/}" != "$project_codex_dir" ] || { echo "Refusing CODEX_HOME as project root." >&2; exit 1; }
    target_config="$project_codex_dir/config.toml"; target_agent="$project_codex_dir/sol-ultra-workaround/terra-high.toml";;
  *) echo "Usage: ./uninstall.sh [profile|project] [project-root]" >&2; exit 2;;
esac
config_parent=$(dirname "$target_config"); agent_parent=$(dirname "$target_agent"); target_state="$agent_parent/install-state.txt"
refuse_linked_directory "$config_parent"; refuse_linked_directory "$agent_parent"

config_present=0; agent_present=0; state_present=0
([ -e "$target_config" ] || [ -L "$target_config" ]) && config_present=1
([ -e "$target_agent" ] || [ -L "$target_agent" ]) && agent_present=1
([ -e "$target_state" ] || [ -L "$target_state" ]) && state_present=1
if [ "$config_present" -eq 0 ] && [ "$agent_present" -eq 0 ] && [ "$state_present" -eq 0 ]; then echo "SOL Ultra Workaround is not installed in $mode mode."; exit 0; fi
[ "$config_present" -eq 1 ] && [ "$agent_present" -eq 1 ] && [ "$state_present" -eq 1 ] || { echo "Partial installation detected. Refusing to remove anything." >&2; exit 1; }
is_plain_file "$target_config" && is_plain_file "$target_agent" && is_plain_file "$target_state" || { echo "Refusing linked or non-regular managed file." >&2; exit 1; }

schema=; state_mode=; config_hash=; agent_hash=; config_parent_created=; agent_parent_created=; guidance_action=; guidance_file=; guidance_pre_hash=; guidance_post_hash=; guidance_backup_hash=; guidance_block_hash=
seen_schema=0; seen_mode=0; seen_config_sha256=0; seen_agent_sha256=0; seen_config_parent_created=0; seen_agent_parent_created=0
seen_guidance_action=0; seen_guidance_file=0; seen_guidance_pre_sha256=0; seen_guidance_post_sha256=0; seen_guidance_backup_sha256=0; seen_guidance_block_sha256=0
while IFS='=' read -r key value; do
  case "$key" in
    schema) [ "$seen_schema" -eq 0 ] || invalid; schema=$value; seen_schema=1;;
    mode) [ "$seen_mode" -eq 0 ] || invalid; state_mode=$value; seen_mode=1;;
    config_sha256) [ "$seen_config_sha256" -eq 0 ] || invalid; config_hash=$value; seen_config_sha256=1;;
    agent_sha256) [ "$seen_agent_sha256" -eq 0 ] || invalid; agent_hash=$value; seen_agent_sha256=1;;
    config_parent_created) [ "$seen_config_parent_created" -eq 0 ] || invalid; config_parent_created=$value; seen_config_parent_created=1;;
    agent_parent_created) [ "$seen_agent_parent_created" -eq 0 ] || invalid; agent_parent_created=$value; seen_agent_parent_created=1;;
    guidance_action) [ "$seen_guidance_action" -eq 0 ] || invalid; guidance_action=$value; seen_guidance_action=1;;
    guidance_file) [ "$seen_guidance_file" -eq 0 ] || invalid; guidance_file=$value; seen_guidance_file=1;;
    guidance_pre_sha256) [ "$seen_guidance_pre_sha256" -eq 0 ] || invalid; guidance_pre_hash=$value; seen_guidance_pre_sha256=1;;
    guidance_post_sha256) [ "$seen_guidance_post_sha256" -eq 0 ] || invalid; guidance_post_hash=$value; seen_guidance_post_sha256=1;;
    guidance_backup_sha256) [ "$seen_guidance_backup_sha256" -eq 0 ] || invalid; guidance_backup_hash=$value; seen_guidance_backup_sha256=1;;
    guidance_block_sha256) [ "$seen_guidance_block_sha256" -eq 0 ] || invalid; guidance_block_hash=$value; seen_guidance_block_sha256=1;;
    *) invalid;; esac
done < "$target_state"
[ "$seen_schema" -eq 1 ] && [ "$seen_mode" -eq 1 ] && [ "$seen_config_sha256" -eq 1 ] && [ "$seen_agent_sha256" -eq 1 ] && [ "$seen_config_parent_created" -eq 1 ] && [ "$seen_agent_parent_created" -eq 1 ] || invalid
valid_hash "$config_hash" && valid_hash "$agent_hash" || invalid
[ "$state_mode" = "$mode" ] && { [ "$config_parent_created" = 0 ] || [ "$config_parent_created" = 1 ]; } && { [ "$agent_parent_created" = 0 ] || [ "$agent_parent_created" = 1 ]; } || invalid
[ "$(sha256_file "$target_config")" = "$config_hash" ] || { echo "Installed config hash does not match. Refusing to delete it." >&2; exit 1; }
[ "$(sha256_file "$target_agent")" = "$agent_hash" ] || { echo "Installed agent hash does not match. Refusing to delete it." >&2; exit 1; }

managed_guidance=0
case "$schema" in
  1)
    # Schema 1 did not manage project guidance and must retain its three-file behavior.
    [ "$seen_guidance_action" -eq 0 ] && [ "$seen_guidance_file" -eq 0 ] && [ "$seen_guidance_pre_sha256" -eq 0 ] && [ "$seen_guidance_post_sha256" -eq 0 ] && [ "$seen_guidance_backup_sha256" -eq 0 ] && [ "$seen_guidance_block_sha256" -eq 0 ] || invalid;;
  2)
    [ "$seen_guidance_action" -eq 1 ] && [ "$seen_guidance_file" -eq 1 ] && [ "$seen_guidance_pre_sha256" -eq 1 ] && [ "$seen_guidance_post_sha256" -eq 1 ] && [ "$seen_guidance_backup_sha256" -eq 1 ] && [ "$seen_guidance_block_sha256" -eq 1 ] || invalid
    if [ "$mode" = profile ]; then
      [ "$guidance_action" = none ] && [ "$guidance_file" = none ] && [ "$guidance_pre_hash" = none ] && [ "$guidance_post_hash" = none ] && [ "$guidance_backup_hash" = none ] && [ "$guidance_block_hash" = none ] || invalid
    else
      case "$guidance_action:$guidance_file" in created:AGENTS.md|created:AGENTS.override.md|appended:AGENTS.md|appended:AGENTS.override.md) ;; *) invalid;; esac
      valid_hash "$guidance_post_hash" && valid_hash "$guidance_block_hash" || invalid
      guidance_target="$project_root/$guidance_file"; guidance_backup="$agent_parent/$guidance_file.preinstall.bak"; guidance_block="$agent_parent/guidance-block.md"
      is_plain_file "$guidance_target" && is_plain_file "$guidance_block" || { echo "Managed guidance is missing, linked, or non-regular. Refusing to remove anything." >&2; exit 1; }
      if [ "$guidance_action" = appended ]; then valid_hash "$guidance_pre_hash" && valid_hash "$guidance_backup_hash" && is_plain_file "$guidance_backup" || invalid; else [ "$guidance_pre_hash" = none ] && [ "$guidance_backup_hash" = none ] || invalid; fi
      managed_guidance=1
    fi;;
  *) invalid;;
esac

transaction_dir=$(mktemp -d "$agent_parent/.sol-ultra-uninstall.XXXXXX")
staged_config="$transaction_dir/config"; staged_agent="$transaction_dir/agent"; staged_state="$transaction_dir/state"
staged_guidance="$transaction_dir/current-guidance"; staged_backup="$transaction_dir/backup"; staged_block="$transaction_dir/block"
guidance_result="$transaction_dir/result"; guidance_expected="$transaction_dir/expected"
moved_config=0; moved_agent=0; moved_state=0; moved_guidance=0; moved_backup=0; moved_block=0; guidance_linked=0; recovery_needed=0; committed=0; rolled_back=0
restore_staged_file() {
  staged=$1; destination=$2
  [ -e "$staged" ] || [ -L "$staged" ] || return 0
  if [ ! -e "$destination" ] && [ ! -L "$destination" ] && ln "$staged" "$destination" 2>/dev/null; then rm -f "$staged"
  else echo "Recovery required: preserved staged file $staged because $destination is occupied." >&2; recovery_needed=1; fi
}
rollback() {
  [ "$rolled_back" -eq 0 ] || return 0; rolled_back=1
  if [ "$guidance_linked" -eq 1 ] && { [ -e "$guidance_target" ] || [ -L "$guidance_target" ]; }; then
    rollback_current="$transaction_dir/current-at-failure"
    if mv "$guidance_target" "$rollback_current" 2>/dev/null; then
      if is_plain_file "$rollback_current" && [ -f "$guidance_expected" ] && cmp -s "$rollback_current" "$guidance_expected"; then rm -f "$rollback_current"
      else
        if [ ! -e "$guidance_target" ] && [ ! -L "$guidance_target" ]; then ln "$rollback_current" "$guidance_target" 2>/dev/null || true; fi
        echo "Recovery required: a different guidance file was preserved at $guidance_target or $rollback_current." >&2; recovery_needed=1
      fi
    fi
  fi
  [ "$moved_guidance" -eq 0 ] || restore_staged_file "$staged_guidance" "$guidance_target"
  [ "$moved_block" -eq 0 ] || restore_staged_file "$staged_block" "$guidance_block"
  [ "$moved_backup" -eq 0 ] || restore_staged_file "$staged_backup" "$guidance_backup"
  [ "$moved_state" -eq 0 ] || restore_staged_file "$staged_state" "$target_state"
  [ "$moved_agent" -eq 0 ] || restore_staged_file "$staged_agent" "$target_agent"
  [ "$moved_config" -eq 0 ] || restore_staged_file "$staged_config" "$target_config"
  if [ "$recovery_needed" -eq 0 ]; then rm -rf "$transaction_dir"
  else echo "Uninstall staging retained for recovery: $transaction_dir" >&2; fi
}
on_exit() { status=$?; if [ "$status" -ne 0 ] && [ "$committed" -eq 0 ]; then rollback; fi; }
trap on_exit 0; trap 'trap - 0 1 2 15; rollback; exit 1' 1 2 15

if [ "$managed_guidance" -eq 1 ]; then
  mv "$guidance_target" "$staged_guidance" || { echo "Managed guidance changed before it could be frozen." >&2; exit 1; }; moved_guidance=1
  mv "$guidance_block" "$staged_block" || exit 1; moved_block=1
  if [ "$guidance_action" = appended ]; then mv "$guidance_backup" "$staged_backup" || exit 1; moved_backup=1; fi
  safe_text_file "$staged_guidance" && safe_text_file "$staged_block" || { echo "Frozen managed guidance is non-regular or binary." >&2; exit 1; }
  [ "$(sha256_file "$staged_block")" = "$guidance_block_hash" ] || { echo "Managed guidance block changed. Refusing to remove anything." >&2; exit 1; }
  [ "$(count_exact_line "$begin_marker" "$staged_block")" = 1 ] && [ "$(count_exact_line "$end_marker" "$staged_block")" = 1 ] || invalid
  if [ "$guidance_action" = appended ]; then [ "$(sha256_file "$staged_backup")" = "$guidance_backup_hash" ] || { echo "Guidance backup changed. Refusing to remove anything." >&2; exit 1; }; fi
  [ "$(count_exact_line "$begin_marker" "$staged_guidance")" = 1 ] && [ "$(count_exact_line "$end_marker" "$staged_guidance")" = 1 ] || { echo "Managed guidance block is missing or duplicated. Refusing to remove anything." >&2; exit 1; }
  guidance_extract="$transaction_dir/extracted"
  awk -v begin="$begin_marker" -v end="$end_marker" '$0 == begin {p=1} p {print} $0 == end {exit}' "$staged_guidance" > "$guidance_extract"
  cmp -s "$guidance_extract" "$staged_block" || { echo "Managed guidance block changed. Refusing to remove anything." >&2; exit 1; }
  if [ "$(sha256_file "$staged_guidance")" = "$guidance_post_hash" ]; then
    if [ "$guidance_action" = appended ]; then cp "$staged_backup" "$guidance_result"; fi
  else
    awk -v begin="$begin_marker" -v end="$end_marker" '$0 == begin {p=1; next} $0 == end {p=0; next} !p {print}' "$staged_guidance" > "$guidance_result"
  fi
  if [ -f "$guidance_result" ]; then
    cp "$guidance_result" "$guidance_expected"
    if ! ln "$guidance_result" "$guidance_target" 2>/dev/null; then echo "A guidance file appeared during uninstall and was preserved: $guidance_target" >&2; exit 1; fi
    guidance_linked=1; rm -f "$guidance_result"
  fi
fi

mv "$target_config" "$staged_config"; moved_config=1
mv "$target_agent" "$staged_agent" || exit 1; moved_agent=1
mv "$target_state" "$staged_state" || exit 1; moved_state=1
committed=1; trap - 0 1 2 15
rm -rf "$transaction_dir"
[ "$agent_parent_created" -eq 0 ] || rmdir "$agent_parent" 2>/dev/null || true; [ "$config_parent_created" -eq 0 ] || rmdir "$config_parent" 2>/dev/null || true
echo "Uninstalled SOL Ultra Workaround from $mode mode."
