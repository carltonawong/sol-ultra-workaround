#!/usr/bin/env sh
set -eu
umask 077

if [ "$#" -lt 1 ]; then
  echo "Usage: ./install.sh profile" >&2
  echo "   or: ./install.sh project /absolute/project/root" >&2
  exit 2
fi

mode=$1
project_root="${2:-}"
package_root=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
source_config="$package_root/profiles/sol-ultra.config.toml"
source_agent="$package_root/agents/terra-high.toml"

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

legacy_default="$codex_home/agents/default.toml"
if [ -e "$legacy_default" ] || [ -L "$legacy_default" ]; then
  echo "Existing global agents/default.toml detected. Review or remove the legacy/global override before installing this scoped version." >&2
  exit 1
fi

case "$mode" in
  profile)
    if [ "$#" -ne 1 ]; then
      echo "Profile mode does not accept a project root." >&2
      exit 2
    fi
    target_config="$codex_home/sol-ultra.config.toml"
    target_agent="$codex_home/sol-ultra-workaround/terra-high.toml"
    ;;
  project)
    if [ "$#" -ne 2 ]; then
      echo "Project mode requires one absolute project root." >&2
      exit 2
    fi
    case "$project_root" in
      /*) ;;
      *)
        echo "Project root must be an absolute path: $project_root" >&2
        exit 2
        ;;
    esac
    project_root=$(CDPATH= cd -- "$project_root" && pwd -P)
    home_root=$(CDPATH= cd -- "$HOME" && pwd -P)
    case "$project_root" in
      /)
        echo "Refusing to turn a filesystem root into project mode." >&2
        exit 1
        ;;
    esac
    if [ "$project_root" = "$codex_home" ]; then
      echo "Refusing to turn CODEX_HOME into project mode." >&2
      exit 1
    fi
    case "$project_root" in
      "$package_root"|"$package_root"/*)
        echo "Refusing to install project mode into the package checkout." >&2
        exit 1
        ;;
    esac
    if [ "$project_root" = "$home_root" ]; then
      echo "Refusing to turn the user's home directory into project mode." >&2
      exit 1
    fi
    project_codex_dir="$project_root/.codex"
    refuse_linked_directory "$project_codex_dir"
    if [ "${codex_home%/}" = "$project_codex_dir" ]; then
      echo "Refusing to turn the user's base Codex config into project mode." >&2
      exit 1
    fi
    existing_default="$project_codex_dir/agents/default.toml"
    if [ -e "$existing_default" ] || [ -L "$existing_default" ]; then
      echo "Refusing to shadow existing project agent: $existing_default" >&2
      exit 1
    fi
    target_config="$project_codex_dir/config.toml"
    target_agent="$project_codex_dir/sol-ultra-workaround/terra-high.toml"
    ;;
  *)
    echo "Usage: ./install.sh profile" >&2
    echo "   or: ./install.sh project /absolute/project/root" >&2
    exit 2
    ;;
esac

config_parent=$(dirname "$target_config")
agent_parent=$(dirname "$target_agent")
refuse_linked_directory "$config_parent"
refuse_linked_directory "$agent_parent"
target_state="$agent_parent/install-state.txt"

for target in "$target_config" "$target_agent" "$target_state"; do
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "Refusing to overwrite existing filesystem object: $target" >&2
    exit 1
  fi
done

config_parent_created=0
agent_parent_created=0
[ -d "$config_parent" ] || config_parent_created=1
[ -d "$agent_parent" ] || agent_parent_created=1
created_config=0
created_agent=0
created_state=0
pending_temp=""

cleanup() {
  [ -z "$pending_temp" ] || rm -f "$pending_temp"
  [ "$created_state" -eq 0 ] || rm -f "$target_state"
  [ "$created_agent" -eq 0 ] || rm -f "$target_agent"
  [ "$created_config" -eq 0 ] || rm -f "$target_config"
  if [ "$agent_parent_created" -eq 1 ]; then
    rmdir "$agent_parent" 2>/dev/null || true
  fi
  if [ "$config_parent_created" -eq 1 ]; then
    rmdir "$config_parent" 2>/dev/null || true
  fi
}
on_exit() {
  status=$?
  if [ "$status" -ne 0 ]; then cleanup; fi
}
on_signal() {
  trap - 0 1 2 15
  cleanup
  exit 1
}
trap on_exit 0
trap on_signal 1 2 15

mkdir -p "$config_parent" "$agent_parent"

install_source_file() {
  source_file=$1
  target_file=$2
  target_kind=$3
  pending_temp=$(mktemp "$(dirname "$target_file")/.sol-ultra-workaround.XXXXXX")
  cp "$source_file" "$pending_temp"
  if ! ln "$pending_temp" "$target_file" 2>/dev/null; then
    echo "Refusing to overwrite a target created during installation: $target_file" >&2
    return 1
  fi
  case "$target_kind" in
    config) created_config=1 ;;
    agent) created_agent=1 ;;
  esac
  rm -f "$pending_temp"
  pending_temp=""
}

install_source_file "$source_config" "$target_config" config
install_source_file "$source_agent" "$target_agent" agent

if ! cmp -s "$source_config" "$target_config" ||
   ! cmp -s "$source_agent" "$target_agent"; then
  echo "Installation verification failed." >&2
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
config_hash=$(sha256_file "$target_config")
agent_hash=$(sha256_file "$target_agent")

pending_temp=$(mktemp "$agent_parent/.sol-ultra-workaround.XXXXXX")
printf 'schema=1\nmode=%s\nconfig_sha256=%s\nagent_sha256=%s\nconfig_parent_created=%s\nagent_parent_created=%s\n' \
  "$mode" "$config_hash" "$agent_hash" \
  "$config_parent_created" "$agent_parent_created" > "$pending_temp"
if ! ln "$pending_temp" "$target_state" 2>/dev/null; then
  echo "Refusing to overwrite a state file created during installation: $target_state" >&2
  exit 1
fi
created_state=1
rm -f "$pending_temp"
pending_temp=""
trap - 0 1 2 15

echo "Installed SOL Ultra Workaround in $mode mode."
echo "No existing Codex file was overwritten."
if [ "$mode" = profile ]; then
  echo "Launch: codex --profile sol-ultra"
  echo "Resume: codex resume --profile sol-ultra <SESSION_ID_OR_NAME>"
else
  echo "Project mode: open and trust this folder or workspace, then create a new task inside it: $project_root"
fi
