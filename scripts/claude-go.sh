#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  --list-models) exec python3 "$script_dir/opencode-go-proxy.py" list ;;
  -h|--help)
    printf 'Usage: go-claude [--model ID] [--effort LEVEL] [Claude flags...]\n'
    printf '       go-claude --list-models\n\n'
    printf 'Requires Python 3.9+, CLIProxyAPI 7.2.130+, and a Go credential.\n'
    printf 'Set up with scripts/setup-credential.sh go. Default effort: highest per model.\n'
    printf 'Permissions are bypassed by default; restore with --permission-mode default.\n'
    exit 0 ;;
esac
source "$script_dir/lib/launch.sh"
cb_launch_init go "$@"
cb_exec_claude
