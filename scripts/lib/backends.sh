#!/usr/bin/env bash
# Canonical backend defaults and credential metadata (Bash 3.2+).

cb_profile() {
  CB_BACKEND="$1"
  CB_DEFAULT_EFFORT=max
  CB_DEFAULT_CONTEXT=1000000
  CB_DEFAULT_COMPACT=1000000
  CB_DEFAULT_TIMEOUT=600000
  CB_DEFAULT_SKIP_PERMISSIONS=1
  CB_DEFAULT_CONCURRENCY=""
  CB_DEFAULT_FAST=""
  CB_LUNA_MODEL=gpt-6-luna
  CB_TERRA_MODEL=gpt-5.6-terra
  CB_SUBAGENT_TIER=fast
  CB_AUTH_PREFIX=""
  case "$1" in
    mimo)
      CB_PREFIX=MIMO; CB_ENV=MIMO_ANTHROPIC_AUTH_TOKEN; CB_SERVICE=mimo-claude-code
      CB_DEFAULT_MODEL='mimo-v2.6-pro[1m]'
      CB_DEFAULT_URL=https://api.xiaomimimo.com/anthropic
      CB_DEFAULT_CONTEXT=1048576; CB_DEFAULT_COMPACT=786432
      CB_DEFAULT_CONCURRENCY=3; CB_AUTH_HEADER=api-key
      ;;
    deepseek)
      CB_PREFIX=DEEPSEEK; CB_ENV=DEEPSEEK_ANTHROPIC_AUTH_TOKEN; CB_SERVICE=deepseek-claude-code
      CB_DEFAULT_MODEL='deepseek-flash[1m]'; CB_DEFAULT_FAST=deepseek-flash
      CB_DEFAULT_URL=https://api.deepseek.com/anthropic
      CB_AUTH_HEADER=Authorization; CB_AUTH_PREFIX='Bearer '
      ;;
    glm)
      CB_PREFIX=GLM; CB_ENV=GLM_ANTHROPIC_AUTH_TOKEN; CB_SERVICE=glm-claude-code
      CB_DEFAULT_MODEL='glm-5.3[1m]'; CB_DEFAULT_FAST='glm-5.3-flash[1m]'
      CB_DEFAULT_URL=https://api.z.ai/api/anthropic
      CB_DEFAULT_SKIP_PERMISSIONS=0; CB_DEFAULT_TIMEOUT=3000000
      CB_SUBAGENT_TIER=main; CB_AUTH_HEADER=x-api-key
      ;;
    claudex)
      CB_PREFIX=CLAUDEX; CB_ENV=CLAUDEX_PROXY_KEY; CB_SERVICE=cliproxyapi-claudex
      CB_DEFAULT_MODEL=gpt-6.1-sol; CB_DEFAULT_URL=http://127.0.0.1:8317
      CB_DEFAULT_CONTEXT=1050000; CB_DEFAULT_COMPACT=1050000
      CB_DEFAULT_CONCURRENCY=3; CB_SUBAGENT_TIER=main
      CB_AUTH_HEADER=Authorization; CB_AUTH_PREFIX='Bearer '
      ;;
    *) printf 'Unknown backend: %s\n' "$1" >&2; return 2 ;;
  esac
}

cb_setting() {
  local output_name="$1" suffix="$2" fallback="$3"
  local setting_name="${CB_PREFIX}_${suffix}"
  printf -v "$output_name" '%s' "${!setting_name:-$fallback}"
}

cb_api_model() {
  # Claude Code owns the terminal [1m] selector; raw HTTP uses the native ID.
  printf '%s' "${1%[[]1[mM][]]}"
}

cb_validate_model() {
  local native_model
  native_model="$(cb_api_model "$1")"
  case "$native_model" in
    ''|*[!a-zA-Z0-9._:/@+-]*)
      printf 'Invalid model ID: use a provider ID, optionally ending in [1m].\n' >&2
      return 2 ;;
  esac
}

cb_validate_positive() {
  local value="$2"
  case "$value" in
    ''|*[!0-9]*) printf '%s must be a positive integer\n' "$1" >&2; return 2 ;;
  esac
  while [[ "$value" == 0* ]]; do value="${value#0}"; done
  if [[ -z "$value" ]]; then
    printf '%s must be a positive integer\n' "$1" >&2
    return 2
  fi
  printf -v "$1" '%s' "$value"
}

cb_validate_boolean() {
  case "$2" in
    0|1) ;;
    *) printf '%s must be 0 or 1\n' "$1" >&2; return 2 ;;
  esac
}

cb_settings() {
  cb_profile "$1" || return $?
  cb_setting CB_MODEL MODEL "$CB_DEFAULT_MODEL"
  cb_setting CB_BASE_URL BASE_URL "$CB_DEFAULT_URL"
  CB_BASE_URL="${CB_BASE_URL%/}"
  case "$CB_BASE_URL" in
    http://*|https://*) ;;
    *) printf '%s_BASE_URL must be an HTTP(S) URL\n' "$CB_PREFIX" >&2; return 2 ;;
  esac
  cb_setting CB_MAX_CONTEXT_TOKENS MAX_CONTEXT_TOKENS "$CB_DEFAULT_CONTEXT"
  cb_setting CB_COMPACT_WINDOW AUTO_COMPACT_WINDOW "$CB_DEFAULT_COMPACT"
  cb_setting CB_API_TIMEOUT_MS API_TIMEOUT_MS "$CB_DEFAULT_TIMEOUT"
  cb_setting CB_SKIP_PERMISSIONS SKIP_PERMISSIONS "$CB_DEFAULT_SKIP_PERMISSIONS"
  cb_setting CB_CONCURRENCY TOOL_CONCURRENCY "$CB_DEFAULT_CONCURRENCY"
  if [[ "$CB_BACKEND" == claudex ]]; then
    CB_EFFORT="${CLAUDEX_EFFORT:-$CB_DEFAULT_EFFORT}"
    CB_CONCURRENCY="${CLAUDEX_CONCURRENCY:-$CB_DEFAULT_CONCURRENCY}"
  else
    cb_setting CB_EFFORT EFFORT_LEVEL "$CB_DEFAULT_EFFORT"
  fi
}

cb_refresh_models() {
  cb_setting CB_FAST_MODEL FAST_MODEL "${CB_DEFAULT_FAST:-$CB_MODEL}"
  local subagent_default="$CB_FAST_MODEL"
  [[ "$CB_SUBAGENT_TIER" != main ]] || subagent_default="$CB_MODEL"
  cb_setting CB_SUBAGENT_MODEL SUBAGENT_MODEL "$subagent_default"
  if [[ "$CB_BACKEND" == claudex ]]; then
    CB_FAST_MODEL="$CB_MODEL"; CB_SUBAGENT_MODEL="$CB_MODEL"
  fi
  cb_validate_model "$CB_MODEL" || return $?
  cb_validate_model "$CB_FAST_MODEL" || return $?
  cb_validate_model "$CB_SUBAGENT_MODEL" || return $?
  CB_WIRE_MODEL="$(cb_api_model "$CB_MODEL")"
}
