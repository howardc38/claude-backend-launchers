#!/usr/bin/env bash
# Bounded HTTP requests with credential headers outside process argv.

cb_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'jq is required for API smoke tests and proxy model checks.\n' >&2
    return 1
  fi
}

cb_http() {
  local method="$1" path="$2" payload="${3:-}" header escaped_header output status
  if [[ -z "${CB_TOKEN:-}" || "$CB_TOKEN" == *[$'\r\n']* ]]; then
    printf 'Credential is empty or contains an invalid header character.\n' >&2; return 2
  fi
  header="${CB_AUTH_HEADER}: ${CB_AUTH_PREFIX}${CB_TOKEN}"
  escaped_header="${header//\\/\\\\}"
  escaped_header="${escaped_header//\"/\\\"}"
  local command=(curl --disable --silent --show-error --fail --config /dev/fd/3
    --connect-timeout 10 --max-time 60 --request "$method" --write-out $'\n%{http_code}'
    --header 'Content-Type: application/json' --header 'anthropic-version: 2023-06-01'
    --url "${CB_BASE_URL}${path}")
  if [[ $# -ge 3 ]]; then
    command+=(--data-binary @-)
    if output="$("${command[@]}" 3<<<"header = \"${escaped_header}\"" <<<"$payload")"; then :; else return $?; fi
  else
    if output="$("${command[@]}" 3<<<"header = \"${escaped_header}\"" < /dev/null)"; then :; else return $?; fi
  fi
  status="${output##*$'\n'}"
  case "$status" in
    2[0-9][0-9]) printf '%s' "${output%$'\n'*}" ;;
    *) printf 'HTTP request failed: expected 2xx, received %s.\n' "$status" >&2; return 1 ;;
  esac
}

cb_model_ids() {
  cb_require_jq || return $?
  jq -r 'if type == "object" and (.data | type == "array") then
    .data[] | if type == "object" and (.id | type == "string") and
      (.id | test("^[A-Za-z0-9._:/@+\\-]+$")) then .id
    else error("invalid model entry") end
    else error("invalid model inventory") end' 2>/dev/null
}

cb_check_model() {
  local model="$1" inventory="$2" ids
  if ! ids="$(printf '%s' "$inventory" | cb_model_ids)"; then
    printf 'Proxy returned an invalid model inventory.\n' >&2; return 1
  fi
  if ! printf '%s' "$inventory" | jq -e --arg model "$model" '.data | any(.[]; .id == $model)' >/dev/null 2>&1; then
    printf 'Model %s is not listed by the current CLIProxyAPI account.\n' "$model" >&2
    return 1
  fi
}
