#!/usr/bin/env sh
set -eu

mode="${1:-profile}"
project_root="${2:-$(pwd)}"
package_root=$(CDPATH= cd "$(dirname "$0")" && pwd -P)

normalize_future_directory() {
  future_path=$1
  case "$future_path" in
    /*) ;;
    *) future_path="$(pwd -P)/$future_path" ;;
  esac
  case "/$future_path/" in
    */../*|*/./*)
      echo "Refusing a non-normalized path containing . or ..: $future_path" >&2
      return 1
      ;;
  esac
  suffix=""
  while [ ! -d "$future_path" ]; do
    if [ -e "$future_path" ] || [ -L "$future_path" ]; then
      echo "Expected a directory path but found another filesystem object: $future_path" >&2
      return 1
    fi
    suffix="/$(basename "$future_path")$suffix"
    parent=$(dirname "$future_path")
    [ "$parent" != "$future_path" ] || return 1
    future_path=$parent
  done
  physical_parent=$(CDPATH= cd -- "$future_path" && pwd -P)
  printf '%s%s\n' "$physical_parent" "$suffix"
}

codex_home=$(normalize_future_directory "${CODEX_HOME:-$HOME/.codex}")

refuse_linked_directory() {
  if [ -L "$1" ]; then
    echo "Refusing a linked or redirected target directory: $1" >&2
    exit 1
  fi
  if [ -e "$1" ] && [ ! -d "$1" ]; then
    echo "Expected a directory but found another filesystem object: $1" >&2
    exit 1
  fi
}

case "$mode" in
  profile)
    target_config="$codex_home/sol-ultra.config.toml"
    target_agent="$codex_home/sol-ultra-workaround/terra-high.toml"
    ;;
  project)
    project_root=$(CDPATH= cd -- "$project_root" && pwd -P)
    home_root=$(CDPATH= cd -- "$HOME" && pwd -P)
    if [ "$project_root" = "$home_root" ]; then
      echo "Refusing to treat the user's home directory as project mode." >&2
      exit 1
    fi
    if [ "$project_root" = "$package_root" ] &&
       [ -f "$package_root/profiles/sol-ultra.config.toml" ]; then
      echo "Refusing to treat the package checkout as project mode." >&2
      exit 1
    fi
    project_codex_dir="$project_root/.codex"
    refuse_linked_directory "$project_codex_dir"
    if [ "${codex_home%/}" = "$project_codex_dir" ]; then
      echo "Refusing to treat the user's base Codex config as project mode." >&2
      exit 1
    fi
    target_config="$project_codex_dir/config.toml"
    target_agent="$project_codex_dir/sol-ultra-workaround/terra-high.toml"
    ;;
  *)
    echo "Usage: ./uninstall.sh [profile|project] [project-root]" >&2
    exit 2
    ;;
esac

config_parent=$(dirname "$target_config")
agent_parent=$(dirname "$target_agent")
refuse_linked_directory "$config_parent"
refuse_linked_directory "$agent_parent"
target_state="$agent_parent/install-state.txt"

config_present=0
agent_present=0
state_present=0
[ ! -e "$target_config" ] || config_present=1
[ ! -e "$target_agent" ] || agent_present=1
[ ! -e "$target_state" ] || state_present=1
if [ "$config_present" -eq 0 ] && [ "$agent_present" -eq 0 ] &&
   [ "$state_present" -eq 0 ]; then
  echo "SOL Ultra Workaround is not installed in $mode mode."
  exit 0
fi
if [ "$config_present" -ne 1 ] || [ "$agent_present" -ne 1 ] ||
   [ "$state_present" -ne 1 ]; then
  echo "Partial installation detected. Refusing to remove anything." >&2
  exit 1
fi

schema=""
state_mode=""
config_hash=""
agent_hash=""
config_parent_created=""
agent_parent_created=""
seen_schema=0
seen_mode=0
seen_config_hash=0
seen_agent_hash=0
seen_config_parent=0
seen_agent_parent=0
while IFS='=' read -r key value; do
  case "$key" in
    schema) [ "$seen_schema" -eq 0 ] || exit 1; schema=$value; seen_schema=1 ;;
    mode) [ "$seen_mode" -eq 0 ] || exit 1; state_mode=$value; seen_mode=1 ;;
    config_sha256) [ "$seen_config_hash" -eq 0 ] || exit 1; config_hash=$value; seen_config_hash=1 ;;
    agent_sha256) [ "$seen_agent_hash" -eq 0 ] || exit 1; agent_hash=$value; seen_agent_hash=1 ;;
    config_parent_created) [ "$seen_config_parent" -eq 0 ] || exit 1; config_parent_created=$value; seen_config_parent=1 ;;
    agent_parent_created) [ "$seen_agent_parent" -eq 0 ] || exit 1; agent_parent_created=$value; seen_agent_parent=1 ;;
    *) echo "Invalid install state. Refusing to remove anything." >&2; exit 1 ;;
  esac
done < "$target_state"

case "$config_hash" in ''|*[!0-9a-f]*) echo "Invalid install state. Refusing to remove anything." >&2; exit 1 ;; esac
case "$agent_hash" in ''|*[!0-9a-f]*) echo "Invalid install state. Refusing to remove anything." >&2; exit 1 ;; esac
if [ "$schema" != 1 ] || [ "$state_mode" != "$mode" ] ||
   [ "${#config_hash}" -ne 64 ] || [ "${#agent_hash}" -ne 64 ] ||
   { [ "$config_parent_created" != 0 ] && [ "$config_parent_created" != 1 ]; } ||
   { [ "$agent_parent_created" != 0 ] && [ "$agent_parent_created" != 1 ]; }; then
  echo "Invalid install state. Refusing to remove anything." >&2
  exit 1
fi

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "No SHA-256 utility found." >&2
    return 1
  fi
}
if [ "$(sha256_file "$target_config")" != "$config_hash" ]; then
  echo "Installed config hash does not match. Refusing to delete it." >&2
  exit 1
fi
if [ "$(sha256_file "$target_agent")" != "$agent_hash" ]; then
  echo "Installed agent hash does not match. Refusing to delete it." >&2
  exit 1
fi

suffix=".sol-ultra-remove-$$"
config_tombstone="$target_config$suffix"
agent_tombstone="$target_agent$suffix"
state_tombstone="$target_state$suffix"
for tombstone in "$config_tombstone" "$agent_tombstone" "$state_tombstone"; do
  if [ -e "$tombstone" ] || [ -L "$tombstone" ]; then
    echo "Uninstall staging path already exists: $tombstone" >&2
    exit 1
  fi
done

moved_config=0
moved_agent=0
moved_state=0
rollback() {
  [ "$moved_state" -eq 0 ] || mv "$state_tombstone" "$target_state"
  [ "$moved_agent" -eq 0 ] || mv "$agent_tombstone" "$target_agent"
  [ "$moved_config" -eq 0 ] || mv "$config_tombstone" "$target_config"
}
on_signal() {
  trap - 1 2 15
  rollback
  exit 1
}
trap on_signal 1 2 15

if ! mv "$target_config" "$config_tombstone"; then exit 1; fi
moved_config=1
if ! mv "$target_agent" "$agent_tombstone"; then rollback; exit 1; fi
moved_agent=1
if ! mv "$target_state" "$state_tombstone"; then rollback; exit 1; fi
moved_state=1
trap - 1 2 15

if ! rm "$config_tombstone" "$agent_tombstone" "$state_tombstone"; then
  echo "The workaround is disabled, but one or more staged files need manual cleanup." >&2
  exit 1
fi
if [ "$agent_parent_created" -eq 1 ]; then
  rmdir "$agent_parent" 2>/dev/null || true
fi
if [ "$config_parent_created" -eq 1 ]; then
  rmdir "$config_parent" 2>/dev/null || true
fi
echo "Uninstalled SOL Ultra Workaround from $mode mode."
echo "No pre-existing Codex file was changed or removed."
