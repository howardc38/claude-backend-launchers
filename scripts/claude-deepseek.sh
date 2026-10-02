#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# 主 model 預設 = deepseek-v4-flash；fast/sub-agent 同樣用 deepseek-v4-flash。
# 主 model 必須帶 [1m]，Claude Code 先會按 DeepSeek 真實能力使用 1M context；未知嘅第三方
# model id 否則會按 200K 處理。呢個係 Claude Code 官方支援嘅 client-side suffix，送 request
# 去 provider 前會 strip。DeepSeek 官方確認 Flash 原生支援 1M；本機亦已實測 Flash[1m]
# 經 Claude Code 成功回應並顯示 contextWindow=1000000。
readonly DEFAULT_DEEPSEEK_MODEL="deepseek-v4-flash[1m]"
readonly DEFAULT_DEEPSEEK_FAST_MODEL="deepseek-v4-flash"
readonly DEFAULT_DEEPSEEK_BASE_URL="https://api.deepseek.com/anthropic"
readonly DEFAULT_DEEPSEEK_EFFORT_LEVEL="max"

# 明確把 auto-compact window 設為 1M。現行 Claude Code 對 [1m] model 本身亦預設 1M，
# 所以呢個值屬 explicit pin；可用 DEEPSEEK_AUTO_COMPACT_WINDOW 調低，令 compaction 更早發生。
readonly DEFAULT_AUTO_COMPACT_WINDOW="1000000"

# Nesting 衛生：唔繼承 parent session 嘅 ANTHROPIC_BASE_URL / ANTHROPIC_MODEL /
# ANTHROPIC_SMALL_FAST_MODEL（否則由其他已 set 咗 env 嘅 proxied session 嵌套 call
# 時會連錯 endpoint）。想覆寫請用 DEEPSEEK_* 變數。
model="${DEEPSEEK_MODEL:-$DEFAULT_DEEPSEEK_MODEL}"
fast_model="${DEEPSEEK_FAST_MODEL:-$DEFAULT_DEEPSEEK_FAST_MODEL}"
base_url="${DEEPSEEK_BASE_URL:-$DEFAULT_DEEPSEEK_BASE_URL}"
auto_compact_window="${DEEPSEEK_AUTO_COMPACT_WINDOW:-$DEFAULT_AUTO_COMPACT_WINDOW}"
effort_level="${DEEPSEEK_EFFORT_LEVEL:-$DEFAULT_DEEPSEEK_EFFORT_LEVEL}"
skip_permissions="${DEEPSEEK_SKIP_PERMISSIONS:-1}"

case "$skip_permissions" in
  0|1) ;;
  *)
    printf 'deepseek-claude: DEEPSEEK_SKIP_PERMISSIONS must be 0 or 1\n' >&2
    exit 2
    ;;
esac

user_set_permissions=0
for arg in "$@"; do
  case "$arg" in
    --dangerously-skip-permissions|--allow-dangerously-skip-permissions|--permission-mode|--permission-mode=*)
      user_set_permissions=1
      ;;
  esac
done

if [[ "$skip_permissions" == "1" && "$user_set_permissions" == "0" ]]; then
  set -- --dangerously-skip-permissions "$@"
fi

source "$script_dir/lib/credentials.sh"
cb_load_auth deepseek
token="$CB_TOKEN"
unset CB_TOKEN

# DeepSeek 官方推薦：opus/sonnet -> pro，haiku/small-fast -> flash（慳 quota）。
# 認證：同時 set ANTHROPIC_AUTH_TOKEN（-> Authorization: Bearer）同 ANTHROPIC_API_KEY
# （-> x-api-key）；DeepSeek /anthropic endpoint 兩者皆收。
exec env \
  ANTHROPIC_BASE_URL="${base_url}" \
  ANTHROPIC_MODEL="${model}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$fast_model" \
  ANTHROPIC_SMALL_FAST_MODEL="${fast_model}" \
  CLAUDE_CODE_SUBAGENT_MODEL="${fast_model}" \
  CLAUDE_CODE_EFFORT_LEVEL="${effort_level}" \
  ANTHROPIC_AUTH_TOKEN="${token}" \
  ANTHROPIC_API_KEY="${token}" \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW="${auto_compact_window}" \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}" \
  CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK="${CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK:-1}" \
  claude "$@"
