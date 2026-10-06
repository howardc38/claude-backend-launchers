#!/usr/bin/env bash
# Explicit live smoke test; regression tests use local HTTP fixtures instead.
set -euo pipefail
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/credentials.sh"
source "$script_dir/lib/http.sh"

usage() {
  printf 'Usage: %s mimo|deepseek|glm|claudex [--model ID|--sol|--luna|--terra]\n' "$0"
}
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 2 ;;
esac
backend="$1"; shift
cb_settings "$backend"
while (($#)); do
  case "$1" in
    --model)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { printf '%s\n' '--model requires a value' >&2; exit 2; }
      CB_MODEL="$2"; shift 2 ;;
    --model=*) CB_MODEL="${1#*=}"; shift ;;
    --sol|--luna|--terra)
      [[ "$backend" == claudex ]] || { usage >&2; exit 2; }
      case "$1" in
        --sol) CB_MODEL="$CB_DEFAULT_MODEL" ;;
        --luna) CB_MODEL="$CB_LUNA_MODEL" ;;
        --terra) CB_MODEL="$CB_TERRA_MODEL" ;;
      esac
      shift ;;
    *) usage >&2; exit 2 ;;
  esac
done
cb_refresh_models
cb_require_jq
cb_load_auth "$backend"
if [[ "$backend" == claudex ]]; then
  inventory="$(cb_http GET /v1/models)"
  cb_check_model "$CB_WIRE_MODEL" "$inventory"
fi
payload="$(jq -cn --arg model "$CB_WIRE_MODEL" --arg backend "$backend" '
  {model:$model,max_tokens:256,stream:false,
    messages:[{role:"user",content:"Reply with exactly: ok"}]} +
  if $backend == "claudex" and
    (($model | startswith("gpt-6.1-sol")) or ($model | startswith("gpt-6-astra")) or
     ($model | startswith("claude-fable-5-dd-"))) then
    {thinking:{type:"adaptive"},output_config:{effort:"low"}}
  else {thinking:{type:"disabled"}} end')"
response="$(cb_http POST /v1/messages "$payload")"
if ! reply="$(printf '%s' "$response" | jq -er '[.content[]? | select(.type == "text") | .text] | join("\n") | select(length > 0)' 2>/dev/null)"; then
  printf 'Smoke test failed: response has no text content or invalid JSON.\n' >&2; exit 1
fi
case "$reply" in
  ok|OK|Ok|ok.|OK.|Ok.) ;;
  *) printf 'Smoke test failed: unexpected reply.\n' >&2; exit 1 ;;
esac
printf 'API smoke test OK (%s: %s)\n' "$backend" "$CB_WIRE_MODEL"
unset CB_TOKEN inventory payload response reply
