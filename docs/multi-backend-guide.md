# Claude Code 多後端手冊

macOS / Linux / WSL 都支援；Linux credential、命令安裝同 CLIProxyAPI 設定見 [Linux guide](linux.md)。各 `setup-*-keychain.sh` 保留為 alias；建議用 `scripts/setup-credential.sh <backend>`。API smoke tests 同診斷共用同一 credential resolver。

> 更新：2026-08-14。Codex 路線已由舊 proxy 完整換成 Tibo 公開方法：`CLIProxyAPI` + Codex OAuth + `claudex`。

## 快速選擇

| 命令 | 後端 | 預設 model / 設定 |
|---|---|---|
| `claude` | Anthropic | 原生 Claude Code，完全不受本 repo 影響 |
| `claudex` | ChatGPT / Codex OAuth | `gpt-5.6-sol`，主 / sub-agent `max`，預設 bypass permission |
| `claudex --luna` | ChatGPT / Codex OAuth | `gpt-5.6-luna`，其餘同上 |
| `mimo-claude` | Xiaomi MiMo | `mimo-v2.6-pro[1m]`；主 / fast / sub-agent 全部 Pro；client effort `max`；預設 bypass permission |
| `deepseek-claude` | DeepSeek | `deepseek-v4-flash[1m]`，sub-agent / fast 用 Flash，`max`，預設 bypass permission |
| `glm-claude` | Z.AI | `glm-5.2[1m]`，fast 用 `glm-4.5-air` |
| `ask-backend` | MiMo / DeepSeek / GLM | headless child agent，預設唯讀 |

## Tibo 方法係乜

Tibo 2026-07-12 推文寫嘅核心步驟係：安裝 CLIProxyAPI、Connect，然後用一個 `claudex` alias 將 Claude Code 主 model / sub-agent 指去 `gpt-5.6-sol`，開啟 effort，tool concurrency 設 3，並關閉 tool search。Tibo 引用嘅 Theo 貼文亦係同一條路：CLIProxyAPI 同時理解 Claude / OpenAI 格式，先做 Codex OAuth，再將 Claude Code 指去本機 proxy。

本 repo 實作保留呢個架構，但補齊咗 Tibo 短 alias 冇明寫嘅要求：

- effort 明確固定為 `max`，主 session 同 sub-agent 都用同一 model；
- 預設加入 `--dangerously-skip-permissions`；
- `gpt-5.6-sol` 做預設，`--luna` / `--terra` 一鍵切換；
- 按 OpenAI model spec 將 Claude Code context ceiling 設為 `1050000`；
- local client key 從 Keychain 讀，啟動前驗證 proxy 同 model；
- 清走繼承自其他 backend 嘅 endpoint / cloud-provider env，避免 nested session 連錯；
- proxy 只 listen `127.0.0.1:8317`，remote management / file log / usage stats 關閉。

```text
Claude Code (claudex)
        |
        | Anthropic /v1/messages
        v
CLIProxyAPI 127.0.0.1:8317
        |
        | protocol translation + Codex OAuth
        v
OpenAI Codex: gpt-5.6-sol / gpt-5.6-luna
```

呢個係非官方 workaround，唔係 Anthropic 或 OpenAI 官方支援嘅 Claude Code integration。上游 policy、OAuth 行為或 model entitlement 可以隨時改變；重要工作應保留原生 `claude` / `codex` 作 fallback。

## 已安裝架構

| 位置 | 用途 |
|---|---|
| `/opt/homebrew/bin/cliproxyapi` | Homebrew CLIProxyAPI binary |
| `/opt/homebrew/etc/cliproxyapi.conf` | active config，mode `0600` |
| `~/.cli-proxy-api/` | proxy-managed Codex OAuth，directory `0700`、credential file `0600` |
| Keychain service `cliproxyapi-claudex` | 只供本機 client 連 proxy 嘅隨機 key |
| `~/.local/bin/claudex` | 指向本 repo launcher 嘅 symlink |

active config 由 `config/cliproxyapi.conf.example` 衍生；repo template 永遠只有 placeholder，唔含真 key。

## 日常用法

```bash
claudex                         # Sol；max；預設 bypass
claudex --luna                  # Luna；max；預設 bypass
claudex --terra                 # Terra；如帳戶提供
claudex --luna -p "Reply OK"    # headless

CLAUDEX_SKIP_PERMISSIONS=0 claudex    # 恢復 permission prompts
CLAUDEX_EFFORT=high claudex            # 單次降低 effort
CLAUDEX_CONCURRENCY=2 claudex          # 單次改 tool concurrency
CLAUDEX_MODEL=gpt-5.6-luna claudex     # env 形式揀 model
CLAUDEX_MAX_CONTEXT_TOKENS=500000 claudex  # 單次調低 context ceiling
```

`claudex` 會將其他 flags 原樣傳畀 Claude Code。bypass permission 代表 Claude Code 可以不經逐次確認執行工具或改檔，只應在你信任嘅 repo / prompt 使用。要安全 default，建議永久設定 `CLAUDEX_SKIP_PERMISSIONS=0`。

Sol 同 Luna 官方 API model page 都列出 `none` 至 `max` reasoning effort，以及 1.05M context window。Claude Code 2.1.232 未內建識別呢兩個新 model ID，所以 launcher 直接設 `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1050000`，避免未知 model 自動縮到 200K；model ID 本身仍跟 Tibo 原方法，不加 `[1m]` 假 suffix。不過「Claude Code → 第三方 proxy → subscription OAuth」係非官方路徑，實際可用 context / quota 最終仍由 CLIProxyAPI、Claude Code 同帳戶 entitlement 決定。

## 服務、重新登入與測試

```bash
brew services info cliproxyapi
brew services restart cliproxyapi

cliproxyapi -codex-login          # browser OAuth
cliproxyapi -codex-device-login   # headless / device flow

./scripts/debug-cliproxy.sh
./scripts/test-cliproxy-api.sh --sol
./scripts/test-cliproxy-api.sh --luna
```

如 `claudex` 報 proxy unreachable：先睇 service status，再 restart。如報 model unavailable：重新登入或用 debug script 睇當前 OAuth account 暴露嘅 model list。診斷 script 只報 credential 有冇存在，唔會印 secret。

升級：

```bash
brew update
brew upgrade cliproxyapi
brew services restart cliproxyapi
./scripts/test-cliproxy-api.sh --luna
```

## 其他直接後端

### MiMo

```bash
./scripts/setup-mimo-keychain.sh
./scripts/test-mimo-api.sh
mimo-claude
```

預設 `mimo-v2.6-pro[1m]`，主 session、fast tier、sub-agent 全部用同一個 Pro 1M model；Claude Code client effort 固定 `max`，context ceiling `1048576`，auto-compact `786432`，並預設加入 `--dangerously-skip-permissions`。MiMo 目前未真正區分非 `none` effort 強度：`max` 會映射成服務端 `high`／thinking enabled，所以呢個係 client 可選最高值，但唔代表服務端有獨立 max compute tier。

針對 MiMo 間歇性 silent SSE / 5xx / tool-call flooding，launcher 預設有以下穩定性保護：

- request timeout 10 分鐘；
- 90 秒收唔到首 byte 或 stream 冇新資料就中止該 attempt；
- 最多 3 次 retry，避免一個壞 request 等足十次；
- streaming 失敗時容許 Claude Code fallback 去 non-streaming；
- tool concurrency 限 3，降低 bypass mode 下大量 parallel calls 嘅破壞面。

臨時覆寫：

```bash
MIMO_MODEL='<model>' mimo-claude
MIMO_EFFORT_LEVEL=high mimo-claude
MIMO_AUTO_COMPACT_WINDOW=524288 mimo-claude
MIMO_MAX_RETRIES=1 mimo-claude
MIMO_TOOL_CONCURRENCY=1 mimo-claude
```

單次恢復 permission prompts：

```bash
MIMO_SKIP_PERMISSIONS=0 mimo-claude
```

### DeepSeek

```bash
./scripts/setup-deepseek-keychain.sh
./scripts/test-deepseek-api.sh
deepseek-claude
```

預設係 `deepseek-v4-flash[1m]` + `max`；sub-agent / fast tier 用 `deepseek-v4-flash`。要 Pro：

```bash
DEEPSEEK_MODEL='deepseek-v4-pro[1m]' deepseek-claude
```

launcher 預設加入 `--dangerously-skip-permissions`。單次恢復 permission prompts：

```bash
DEEPSEEK_SKIP_PERMISSIONS=0 deepseek-claude
```

### GLM / Z.AI

```bash
./scripts/setup-glm-keychain.sh
./scripts/test-glm-api.sh
glm-claude
```

預設主 model `glm-5.2[1m]`，fast `glm-4.5-air`，auto-compact window 明確設 1M。

## 由一個 session 呼叫另一個 backend

```bash
ask-backend --list
ask-backend deepseek "review 呢個 function"
ask-backend mimo "用一句解釋呢段錯誤"
ask-backend glm "比較兩個方案"
```

`ask-backend` 預設 headless / 唯讀。需要 child 修改檔案才加 `--permission-mode acceptEdits`；要完全 bypass 可加 `--dangerously-skip-permissions`，風險同 `claudex` 一樣。送出嘅 prompt / code 會離開本機去所選第三方 backend。

## 安全邊界

- CLIProxyAPI 只 listen loopback；唔好將 host 改成 `0.0.0.0`，亦唔好開 remote management。
- 唔好將 `/opt/homebrew/etc/cliproxyapi.conf`、`~/.cli-proxy-api/`、Keychain export、`.env` 或 token commit 入 git。
- local client key 只係保護本機 proxy；真正上游權限來自 Codex OAuth file。
- bypass permission 係方便性選擇，唔係 proxy 必需條件；不可信 repo 請關閉。
- OAuth / subscription 經第三方工具使用可能有帳戶或條款風險；見到 policy / entitlement 錯誤時唔好嘗試繞過，改用官方 client 或 API。

## 參考來源

- [Tibo 原始三步 + alias](https://x.com/thsottiaux/status/2076119366647894371)
- [Theo 被 Tibo 引用嘅 CLIProxyAPI / Claude Code 說明](https://x.com/theo/status/2076114415368482854)
- [CLIProxyAPI 官方 repository](https://github.com/router-for-me/CLIProxyAPI)
- [CLIProxyAPI 官方 guides](https://help.router-for.me/)
- [OpenAI GPT-5.6 Sol model page](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [OpenAI GPT-5.6 Luna model page](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
