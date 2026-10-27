#!/usr/bin/env bash
# Explicit live checks use the actual Claude harness and Go gateway.
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/backends.sh"
source "$script_dir/lib/http.sh"
cb_settings go
all=0
while (($#)); do
  case "$1" in
    --all) all=1; shift ;;
    --model)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { printf '%s\n' '--model requires a value' >&2; exit 2; }
      CB_MODEL="$2"; shift 2 ;;
    --model=*) CB_MODEL="${1#*=}"; shift ;;
    --effort)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { printf '%s\n' '--effort requires a value' >&2; exit 2; }
      CB_EFFORT="$2"; shift 2 ;;
    --effort=*) CB_EFFORT="${1#*=}"; shift ;;
    *) printf 'Usage: test-api.sh go [--all | --model ID] [--effort LEVEL]\n' >&2; exit 2 ;;
  esac
done
cb_refresh_models
cb_require_jq
models=("$CB_MODEL")
if [[ "$all" == 1 ]]; then
  models=()
  while IFS= read -r model; do models+=("$model"); done < <(
    jq -r '.models | to_entries | sort_by(.key) | .[] |
      select(.key != "deepseek-flash" and .value.training != true) | .key' "$script_dir/../config/opencode-go-models.json")
fi
# Validate the entire batch before any paid API request.
for model in "${models[@]}"; do
  python3 "$script_dir/opencode-go-proxy.py" describe "$model" "$CB_EFFORT" >/dev/null
done
for model in "${models[@]}"; do
  command=("$script_dir/../go-claude" --model "$model" --effort "$CB_EFFORT" --bare -p
    --permission-mode default --tools '' --max-turns 1 --output-format json
    -- 'Reply with exactly: ok')
  result="$("${command[@]}" < /dev/null)"
  if ! printf '%s' "$result" | jq -e '
    .is_error != true and (.result | ascii_downcase | gsub("^[[:space:]]+|[[:space:]]+$"; "") | . == "ok" or . == "ok.")
    ' >/dev/null 2>&1; then
    printf 'Go smoke test failed (%s): missing or unexpected response.\n' "$model" >&2; exit 1
  fi
  printf 'API smoke test OK (go: %s, effort: %s)\n' "$model" "$CB_EFFORT"
done
