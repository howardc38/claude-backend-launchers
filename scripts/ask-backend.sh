#!/usr/bin/env bash
set -euo pipefail

# ask-backend — 由官方 Claude Code（或任何 shell）安全咁 call 一個後端 LLM agent。
#
# 用 headless print 模式（claude -p）跑後端 launcher，並先用 `env -u` 清走會洩漏嘅
# ANTHROPIC_* endpoint/model env（nesting 衛生），再 pin 後端專屬 base URL，確保 child
# 一定連去正確 endpoint —— 即使呢個 helper 由其他已指住 proxy 嘅 session 嵌套
# 呼叫都唔會連錯。
#
# 用法:
#   ask-backend <backend> <prompt> [extra claude flags...]
#   ask-backend --list | -h | --help
#
# backend: mimo | deepseek | glm
#
# 例:
#   ask-backend mimo "用一句講解 TCP three-way handshake"
#   ask-backend deepseek "review 呢個 function: ..."
#   ask-backend deepseek "幫我改 README" --permission-mode acceptEdits   # 要改檔先加
#
# 回傳: 後端 agent 嘅最終答案（純文字）去 stdout。auth token 由各 launcher 自己
#       由環境變數或 OS credential store 讀。

prog="ask-backend"

usage() {
  cat <<EOF
Usage: ${prog} <backend> <prompt> [extra claude flags...]
       ${prog} --list

backends:
  mimo       MiMo v2.6 Pro    (https://api.xiaomimimo.com/anthropic)
  deepseek   DeepSeek V4 Flash (https://api.deepseek.com/anthropic)
  glm        GLM 5.3          (https://api.z.ai/api/anthropic)

examples:
  ${prog} mimo "explain the TCP handshake in one line"
  ${prog} deepseek "review this code: ..."
EOF
}

# engine 永遠住喺 <repo>/scripts/，root entrypoint 會用絕對路徑 exec 佢，所以
# 直接由自己位置推算 repo root 即可。
script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -P -- "${script_dir}/.." && pwd)"

case "${1:-}" in
  ""|-h|--help)
    usage
    exit 0
    ;;
  --list)
    echo "mimo"
    echo "deepseek"
    echo "glm"
    exit 0
    ;;
esac

backend="$1"
shift

if [[ $# -lt 1 ]]; then
  echo "Error: missing <prompt>." >&2
  usage >&2
  exit 2
fi

prompt="$1"
shift
# 餘下 "$@" = 額外 flags（可空）。"$@" 喺 bash 3.2 + set -u 下零參數都安全。

user_set_permissions=0
for arg in "$@"; do
  case "$arg" in
    --dangerously-skip-permissions|--allow-dangerously-skip-permissions|--permission-mode|--permission-mode=*)
      user_set_permissions=1
      ;;
  esac
done
if [[ "$user_set_permissions" == 0 ]]; then
  set -- --permission-mode default "$@"
fi

# 共用：要 strip 走嘅繼承 endpoint/model env（防止 nested 連錯後端）。
# Generic parent credentials belong to that session, not the selected backend.
strip_env=(
  -u ANTHROPIC_AUTH_TOKEN
  -u ANTHROPIC_API_KEY
  -u ANTHROPIC_BASE_URL
  -u ANTHROPIC_MODEL
  -u ANTHROPIC_SMALL_FAST_MODEL
  -u ANTHROPIC_DEFAULT_OPUS_MODEL
  -u ANTHROPIC_DEFAULT_SONNET_MODEL
  -u ANTHROPIC_DEFAULT_HAIKU_MODEL
)

# prompt 由 arg 傳，唔靠 stdin —— `< /dev/null` 避免 claude -p 等 3s piped stdin
# 再吐 warning（agent-to-backend 呼叫嘅常見路徑）。要 pipe 內容入後端，直接用
# 對應 launcher：`deepseek-claude -p "..." < file`。
case "${backend}" in
  mimo)
    exec env "${strip_env[@]}" \
      MIMO_BASE_URL="https://api.xiaomimimo.com/anthropic" \
      "${repo_dir}/mimo-claude" -p "${prompt}" "$@" < /dev/null
    ;;
  deepseek)
    exec env "${strip_env[@]}" \
      DEEPSEEK_BASE_URL="https://api.deepseek.com/anthropic" \
      "${repo_dir}/deepseek-claude" -p "${prompt}" "$@" < /dev/null
    ;;
  glm)
    exec env "${strip_env[@]}" \
      GLM_BASE_URL="https://api.z.ai/api/anthropic" \
      "${repo_dir}/glm-claude" -p "${prompt}" "$@" < /dev/null
    ;;
  *)
    echo "Error: unknown backend '${backend}'. Use: mimo | deepseek | glm (see --list)." >&2
    usage >&2
    exit 2
    ;;
esac
