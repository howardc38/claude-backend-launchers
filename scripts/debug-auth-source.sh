#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/credentials.sh"
cb_load_auth "${1:-}"
printf 'backend=%s source=%s service=%s value=hidden\n' "$CB_BACKEND" "$CB_SOURCE" "$CB_SERVICE"
unset CB_TOKEN
