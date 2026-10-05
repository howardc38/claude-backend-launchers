#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/launch.sh"
cb_launch_init deepseek "$@"
cb_exec_claude
