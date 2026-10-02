#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -P -- "$script_dir/.." && pwd)"
install_dir="${CLAUDE_BACKEND_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$install_dir"
for name in mimo-claude deepseek-claude glm-claude claudex ask-backend; do
  target="$install_dir/$name"
  if [[ -e "$target" && ! -L "$target" ]]; then
    printf 'Refusing to replace non-symlink: %s\n' "$target" >&2
    exit 1
  fi
done
for name in mimo-claude deepseek-claude glm-claude claudex ask-backend; do
  ln -sfn "$repo_dir/$name" "$install_dir/$name"
done
printf 'Installed launcher symlinks in %s. Keep this checkout; add this directory to PATH if needed.\n' "$install_dir"
