# Claude Code Multi-Backend Guide — 個人使用手冊

> 透過 `raine/claude-code-proxy` 用 ChatGPT 訂閱跑 Claude Code，作為 Anthropic Opus 嘅替代 backend。
>
> 設定日期：2026-05-13 · macOS Apple Silicon (darwin-arm64) · proxy v0.0.12
>
> **內容已對齊**：[官方 README](https://github.com/raine/claude-code-proxy/blob/main/README.md) (commit 對應 v0.0.12) + binary `strings` 直接 verify + 本機實際 endpoint 測試。所有 env var / mapping / file path 都有 source。

> **增補（2026-06-09）**：本 repo 另外加入咗 **MiMo 直連 launcher**，唔經 `claude-code-proxy`，直接用 Anthropic-compatible endpoint 跑 Claude Code。以下內容會同時保留：
> - OpenAI / Codex via `claude-code-proxy`
> - Kimi via `claude-code-proxy`
> - MiMo direct via `mimo-claude`
> - 原生 Anthropic via `claude`

---

## ⚡ 快速切換總表

| 你打嘅 command | backend | 現時預設 model | context / `[1m]` | effort 行為 |
|---|---|---|---|---|
| `claude` | 原生 Anthropic | 你本機 Claude Code 預設 | 由 Anthropic / Claude Code 原生處理 | Claude Code 原生 |
| `claude-cc` | OpenAI Codex via proxy | `gpt-5.4[1m]` | proxy 會 strip `[1m]` 再送上游；Claude Code 用它調高 auto-compact threshold | `low/medium/high/max` 經 proxy 映射；`max -> xhigh` |
| `claude-cc` + `CCP_ALIAS_PROVIDER=kimi` | Kimi via proxy | `kimi-for-coding` / `kimi-k2.6` alias | 無 `[1m]` 慣例；Kimi 文檔路徑為主 | `max -> high`，其餘 pass-through |
| `mimo-claude` | MiMo direct（Anthropic-compatible） | `mimo-v2.5-pro[1m]`（本機 launcher 目前設定） | `[1m]` 交由 Claude Code / MiMo 配置慣例處理，用來打開長 context 模式 | **無本地 custom mapping**；Claude Code 的 effort 直接 pass-through |

**最實用理解：**

- 想用原生 Anthropic：`claude`
- 想用 OpenAI / Codex：`claude-cc`
- 想用 MiMo：`mimo-claude`
- 想臨時改 effort：任何一個 command 後面都可以加 `--effort high`

---

## 🗺️ 架構一覽

```
┌─────────────────┐       ┌───────────────────────┐       ┌──────────────┐
│  Claude Code    │──→    │  claude-code-proxy    │──→    │   OpenAI     │
│  effortLevel:   │       │  pass-through         │       │   ChatGPT    │
│  max            │       │  (max → xhigh map)    │       │   Plus/Pro   │
│  sub-agent:     │       │                       │       │              │
│  effort: low/.. │       │                       │       │              │
└─────────────────┘       └───────────────────────┘       └──────────────┘
       ↓ effort=<per-context>     ↓ reasoning_effort=<mapped>
```

每個 sub-agent 嘅 frontmatter `effort:` field 都會被尊重 — main session 用 max → xhigh，但 light sub-agent (`effort: low`) 仍然行 low。

預設 `claude` 命令 **完全唔變**，繼續行原生 Anthropic。打 `claude-cc` 會 route 去 GPT-5.4（經 proxy）；打 `mimo-claude` 會 route 去 MiMo（直連 Anthropic-compatible endpoint）。

---

## 📂 安裝檔案

| 路徑 | 用途 |
|------|------|
| `~/.local/bin/claude-code-proxy` | Proxy binary v0.0.12 (66 MB, ad-hoc signed) |
| `~/.local/bin/claude-cc-proxy` | Wrapper：pass-through 起 proxy（無 env override，效一律由 Claude Code 嗰邊決定） |
| `~/.local/bin/claude-cc` | Wrapper：set ANTHROPIC_* env vars + exec claude |
| `~/.local/bin/mimo-claude` | User-level symlink / launcher：直連 MiMo Anthropic-compatible endpoint |
| **macOS Keychain** service `claude-code-proxy.codex` | OAuth tokens（**唔係檔案** — 用 Keychain Access 或 `security find-generic-password` 睇）|
| **macOS Keychain** service `mimo-claude-code` | MiMo API key（`mimo-claude` 讀呢個 service） |
| `~/.config/claude-code-proxy/config.json` | 可選 config file（env vars 嘅替代品，[詳見配置 section](#-config-file-替代-env-vars)） |
| `~/.local/state/claude-code-proxy/proxy.log` | JSON-lines log，20 MiB 自動 rotate，secrets 已 redact |
| `~/.claude/settings.json` | Claude Code 設定（`effortLevel: max`） |
| `/Users/howard/Projects/claude-backend-launchers/mimo-claude` | repo 內 launcher entrypoint（user-level symlink 指向呢個檔案） |
| `/Users/howard/Projects/claude-backend-launchers/scripts/claude-mimo.sh` | MiMo 實際 wrapper（set `ANTHROPIC_*` env vars） |
| `/Users/howard/Projects/claude-backend-launchers/scripts/setup-mimo-keychain.sh` | 寫入 / 更新 MiMo key 到 Keychain |
| `/Users/howard/Projects/claude-backend-launchers/scripts/test-mimo-api.sh` | 從 Keychain / env 讀 key，直接 call MiMo Anthropic endpoint 做 smoke test |

> Linux / 非 macOS 嘅 OAuth token 喺 `~/.config/claude-code-proxy/<provider>/auth.json` (mode 0600)。macOS **只有** Keychain。

---

## 🚀 日常使用（3 步）

### Step 1: 啟動 proxy（每次 boot 要做一次）

打開 Terminal，**留一個 tab** 專門跑：

```sh
claude-cc-proxy serve
```

見到 `Proxy listening on http://localhost:18765` 就 OK。**唔好關呢個 tab**。

> Background 跑：用 `tmux`、`nohup`，或者裝下面嘅 LaunchAgent。

### Step 2: 用 `claude-cc` 跑 Claude Code

另一個 tab：

```sh
cd /path/to/your/project
claude-cc                              # 普通 mode
claude-cc --dangerously-skip-permissions   # bypass permission
claude-cc --effort high                # 臨時改 effort（唔改 settings.json）
```

Title bar 應該顯示 `gpt-5.4[1m] with max effort`。

### Step 3: 想用返 Anthropic Opus

直接打 `claude`，無 wrapper，env vars 唔受影響。兩個 backend 可以同時開唔同 tab 並存。

### Step 4: 想用 MiMo（直連，唔經 proxy）

如果你已經做咗 user-level install：

```sh
mimo-claude
mimo-claude --effort high
```

如果未加到 PATH，就喺 repo 入面直接：

```sh
cd /Users/howard/Projects/claude-backend-launchers
./mimo-claude
```

**目前本機 `mimo-claude` 會 set：**

| 變數 | 值 |
|------|----|
| `ANTHROPIC_BASE_URL` | `https://api.xiaomimimo.com/anthropic` |
| `ANTHROPIC_MODEL` | `mimo-v2.5-pro[1m]` |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `mimo-v2.5-pro[1m]` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `mimo-v2.5-pro[1m]` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `mimo-v2.5-pro[1m]` |
| `ANTHROPIC_SMALL_FAST_MODEL` | `mimo-v2.5-pro[1m]` |

> 備註：Xiaomi 官方 Claude Code 設定文檔用嘅示例 model 名係 `mimo-v2.5-pro` / `mimo-v2.5-pro[1m]`；本機 launcher 已改為跟官方 literal。

---

## ⚙️ 配置位

### `~/.claude/settings.json`

```json
{
  "effortLevel": "max",
  ...
}
```

可選值：`low / medium / high / max`（**唔好填 `xhigh`** — proxy 嘅 Anthropic-side schema 只接受呢 4 個）

**Codex provider 嘅 mapping**（從 binary `toCodexEffort` function 確認）：

| Claude Code 寄 | Proxy 轉換 → Codex |
|----------------|-------------------|
| low | low |
| medium | medium |
| high | high |
| **max** | **xhigh** ⭐ |

**Kimi provider 嘅 mapping**（從 binary 另一個 `mapReasoningEffort` function 確認）：

| Claude Code 寄 | Proxy 轉換 → Kimi |
|----------------|-------------------|
| low | low |
| medium | medium |
| high | high |
| max | **high**（Kimi 冇 xhigh，封頂 high）|
| 冇 effort | medium（默認） |

### Per-agent effort 控制

每個 sub-agent 嘅 markdown frontmatter 入面可以寫 `effort: max` (或 low/medium/high)。Main session 嘅 effort 由 `~/.claude/settings.json` 嘅 `effortLevel` 或者 `--effort` flag 決定。

**所有 effort 設定都會經 proxy mapping 翻譯落 Codex**。

> 如果你想強制所有 Codex request 一律 xhigh（無視 agent/session 設定），可以喺 `claude-cc-proxy` wrapper 加返 `export CCP_CODEX_EFFORT=xhigh`。預設我**冇加** — 讓 agent 自主控制。

### MiMo 嘅 effort 點理解？

`mimo-claude` 呢條路線**唔經 `claude-code-proxy`**，所以：

- **無 `max -> xhigh` 呢類本地映射**
- Claude Code CLI 收到嘅 `--effort low/medium/high/max` 會**直接**跟住 Anthropic-compatible request path 送去 MiMo
- 換句話講：`mimo-claude --effort high` 係真 `high`；`mimo-claude --effort max` 亦係直送 `max`

**目前可確定 / 不可確定嘅邊界：**

- ✅ 可確定：本地 launcher **冇做 custom remap**
- ✅ 可確定：`[1m]` 係長 context 慣例，**唔係 effort**
- ⚠️ 未見 Xiaomi 官方公開一張「Claude Code effort level → MiMo 內部 thinking budget」對照表；所以文件上應視之為 **pass-through**，唔好自行假設 `max = xhigh`

### Proxy env vars

完整官方 list（precedence：**env var > config.json > 內建 default**）：

| 變數 | Config key | 預設 | 作用 |
|------|-----------|------|------|
| `PORT` | `port` | `18765` | Proxy listen port |
| `XDG_STATE_HOME` | — | `~/.local/state` | `proxy.log` 嘅 base dir |
| `CCP_LOG_STDERR` | `log.stderr` | unset | =1 mirror log line 到 stderr |
| `CCP_LOG_VERBOSE` | `log.verbose` | unset | =1 log 完整 request/response + 每個 SSE event |
| `CCP_ALIAS_PROVIDER` | `aliasProvider` | `codex` | 將 Anthropic alias (haiku/sonnet/opus/claude-\*) route 去 `codex` 定 `kimi` |
| `CCP_CODEX_EFFORT` | `codex.effort` | unset | **強制覆寫** Codex reasoning effort：`none / low / medium / high / xhigh` |
| `CCP_CODEX_MODEL` | `codex.model` | unset | 強制所有 Codex request 用呢個 model（無視 Claude Code 寄咩） |
| `CCP_CODEX_SERVICE_TIER` | `codex.serviceTier` | unset | 強制 Codex service tier：`fast` / `priority`（=fast 上游）/ `flex` |
| `CCP_CODEX_BASE_URL` | `codex.baseUrl` | `https://chatgpt.com/backend-api/codex/responses` | Codex endpoint override（debug 用） |
| `CCP_CODEX_ORIGINATOR` | `codex.originator` | `claude-code-proxy` | `originator` header |
| `CCP_CODEX_USER_AGENT` | `codex.userAgent` | `claude-code-proxy/<ver>` | User-Agent header |
| `CCP_KIMI_OAUTH_HOST` | `kimi.oauthHost` | `https://auth.kimi.com` | Kimi OAuth host override |
| `CCP_KIMI_BASE_URL` | `kimi.baseUrl` | `https://api.kimi.com/coding/v1` | Kimi API base URL |
| `CCP_KIMI_USER_AGENT` | `kimi.userAgent` | `KimiCLI/1.37.0` | Kimi User-Agent |
| `CCP_ORIGINATOR` | — | `claude-code-proxy` | `CCP_CODEX_ORIGINATOR` 嘅 fallback |
| `CCP_USER_AGENT` | — | unset | `CCP_CODEX_USER_AGENT` 同 `CCP_KIMI_USER_AGENT` 嘅 fallback |

我預設**冇 set** 任何 proxy override env vars — 全部行 default + Claude Code 嗰邊（settings.json / agent frontmatter）控制。

### Claude Code 嘅 env vars（我 wrapper 入面 set）

| 變數 | 我嘅值 | 作用 |
|------|--------|------|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:18765` | 指向本機 proxy |
| `ANTHROPIC_AUTH_TOKEN` | `unused` | proxy 唔 check，任何字串都 OK |
| `ANTHROPIC_MODEL` | `gpt-5.4[1m]` | 主 model |
| `ANTHROPIC_SMALL_FAST_MODEL` | `gpt-5.4-mini[1m]` | Claude Code background 任務（title gen、token count）用嘅 model — **必須 set**，否則 background request 會 400 |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | 停掉 Anthropic telemetry，唔好洩漏到 proxy |
| `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` | `1` | **重要**：proxy 一律用 streaming 與上游溝通，呢個 flag 阻止 Claude Code 重試 partially-completed stream — 否則可能造成 duplicate tool calls |
| `DISABLE_AUTO_COMPACT` (可選) | unset | =1 完全停掉 auto-compaction（風險：可能撞 upstream 真實 limit） |

### Claude Code 一次性 flag

```sh
claude-cc --effort high                  # 臨時 high effort
claude-cc --max-budget-usd 5             # 預算上限（只 --print mode 有用）
claude-cc --dangerously-skip-permissions # bypass permission
```

---

## 🔄 切換 model

```sh
# 喺 Claude Code chat 入面：
/model

# 或者啟動時：
ANTHROPIC_MODEL='gpt-5.3-codex[1m]' claude-cc      # coding 專用，Plus 確認可用
ANTHROPIC_MODEL='gpt-5.4-mini[1m]' claude-cc       # 快/平，Plus 確認可用
ANTHROPIC_MODEL='gpt-5.4-fast[1m]' claude-cc       # 行 priority service tier
```

`claude-cc` wrapper 默認 `gpt-5.4[1m]`。

### MiMo：切 model / 切 context

`mimo-claude` 預設用 `mimo-v2.5-pro[1m]`。想臨時改 model，可以喺啟動前覆寫 env：

```sh
MIMO_MODEL='mimo-v2.5-pro' mimo-claude
MIMO_MODEL='mimo-v2.5-pro[1m]' mimo-claude
ANTHROPIC_MODEL='mimo-v2.5-pro[1m]' mimo-claude
```

如果你想改長期預設，改 repo 入面呢個檔案：

```sh
/Users/howard/Projects/claude-backend-launchers/scripts/claude-mimo.sh
```

### 不同 backend 點切 model

| backend | 慣常切法 |
|---|---|
| Anthropic 原生 | `claude` 入面 `/model`，或者本機 Claude Code 設定 |
| OpenAI / Codex via proxy | `ANTHROPIC_MODEL='gpt-5.4-mini[1m]' claude-cc`、`/model` |
| Kimi via proxy | 改 proxy route / provider config |
| MiMo direct | `MIMO_MODEL='mimo-v2.5-pro[1m]' mimo-claude` 或修改 `scripts/claude-mimo.sh` |

### Plus tier 確認可用嘅 model（官方）

README 列明喺 **ChatGPT Plus** 帳號確認 working：
- ✅ `gpt-5.4`
- ✅ `gpt-5.3-codex`

「Also verified」(冇講明 tier)：
- 🟡 `gpt-5.2`
- 🟡 `gpt-5.4-mini`

⚠️ **未確認**（包括 `gpt-5.5`、`gpt-5.3-codex-spark`）— 你個 ChatGPT account 唔 entitle 嘅話會收到 400 error：
```
"The 'gpt-X.X' model is not supported when using Codex with a ChatGPT account."
```

### `-fast` suffix（priority service tier）

任何 Codex model 後面加 `-fast` = 用 priority service tier（更快、quota 食得多）：

```sh
ANTHROPIC_MODEL='gpt-5.4-fast[1m]' claude-cc
# proxy strip 走 -fast，上游送 "gpt-5.4" + service_tier: "priority"
```

`CCP_CODEX_SERVICE_TIER` env override 比 `-fast` suffix 優先。

### 完整 model list（`claude-code-proxy --help` 印出來）

- **Codex provider**：`gpt-5.2` / `gpt-5.3-codex` / `gpt-5.3-codex-spark` / `gpt-5.4` / `gpt-5.4-mini` / `gpt-5.5`（每個都有 `-fast` 變體）
- **Anthropic aliases**：`haiku` / `sonnet` / `opus` / `claude-haiku-4-5` / `claude-haiku-4-5-20251001` / `claude-sonnet-4-6` / `claude-opus-4-7` — **預設 route 去 Codex**，可以用 `CCP_ALIAS_PROVIDER=kimi` 改為 route 去 Kimi
- **Kimi provider**：`kimi-for-coding` / `kimi-k2.6` / `k2.6`（後兩個係 alias）— Kimi 只有一個 wire model（`kimi-for-coding`，display name 係 Kimi-k2.6），256K context

---

## 📐 Context Window：`[1m]` 唔等於真係 1M ⚠️

呢個 section 引用 README 官方說明：

### `[1m]` 嘅實際作用

Claude Code 用 model 嘅 context window 決定幾時 auto-compact。對於不認識嘅 model（包括 proxy 用嘅所有 model），Claude Code 默認當佢 **200K context**，所以 auto-compact 會過早觸發。

`[1m]` suffix 係 **Claude Code 自己嘅 convention**，叫佢將 auto-compact 嘅 threshold 調高到 1M token。**呢個唔係解鎖更大 context、亦唔係轉去 API 嘅 experimental 1M mode** — 純粹延遲 auto-compaction 嘅時機。

Proxy 收到 `gpt-5.4[1m]` 之後嘅實作（從 binary 確認）：
```js
function normalizeIncomingModel(model) {
  return model.replace(/\[1m\]$/i, "");   // strip [1m] 之後送上游
}
```

### 各 backend 嘅真實 context

| 訪問途徑 | 真實 context | 來源 |
|---------|-------------|------|
| GPT-5.4 native API | 1.05M (922K in + 128K out) — 要 explicit opt-in `model_context_window`，否則 272K | [OpenAI API docs](https://developers.openai.com/api/docs/models/gpt-5.4) |
| **GPT-5.4 via Codex (ChatGPT Plus/Pro)** | **400K+** | [claude-code-proxy README](https://github.com/raine/claude-code-proxy#5-context-window-size) |
| GPT-5.5 via Codex | 400K cap（feature request to raise — [issue #19464](https://github.com/openai/codex/issues/19464)） | OpenAI Codex GitHub |
| Kimi-k2.6 | 256K | claude-code-proxy README |

> ⚠️ **Caveat**：[OpenAI Codex Discussion #1999](https://github.com/openai/codex/discussions/1999) 入面有 user 觀察到 192K-272K，但係 thread 入面亦有人指出個 number 反映 billing 唔係 actual allocation。Proxy README（作者親自寫）話 GPT-5.4 via Codex 至少 400K。

### MiMo 版本點理解 `[1m]`

根據 Xiaomi 官方文檔：

- `mimo-v2.5-pro` 支援 **1M context window**
- Claude Code 配置頁明確寫咗：對支援 1M context 嘅 MiMo model，可以喺 model ID 後面加 `[1m]`

所以對 MiMo 來講，`[1m]` 至少係一個**官方接受的 Claude Code 配置慣例**。本機 `mimo-claude` 因此預設已帶 `[1m]`。  
來源：

- [Claude Code Configuration](https://platform.xiaomimimo.com/docs/integration/claudecode)
- [Model and Rate Limit](https://platform.xiaomimimo.com/docs/en-US/quick-start/model)

### 各 backend 嘅 context / effort 一眼睇

| backend | `[1m]` 作用 | 真實 context / 文檔說法 | effort mapping |
|---|---|---|---|
| Anthropic 原生 | 跟 Anthropic / Claude Code 原生行為 | 以官方 Claude / Anthropic 文檔為準 | 原生 |
| OpenAI Codex via proxy | Claude Code auto-compact hint；proxy strip 後送上游 | `gpt-5.4` via Codex 實測 / README 約 400K+ | `max -> xhigh` |
| Kimi via proxy | 無主要依賴 `[1m]` | Kimi 文檔 / proxy README：256K | `max -> high` |
| MiMo direct | 官方接受 `[1m]` 作為 Claude Code 長 context 配置慣例 | Xiaomi 文檔：`mimo-v2.5-pro` context window 1M | **無本地 custom mapping，pass-through** |

### 用法 implication

**日常 coding task（< 200K context）**：
- ✅ 完全無問題，照 `gpt-5.4[1m]` 用

**Long context task（150K+ tokens）**：
- ⚠️ 接近 GPT-5.4 Codex 嘅 400K 上限就要小心
- 撞 limit 嘅 error：upstream 會 return 400 / `context_length_exceeded`
- 🛡️ 保守做法：
  1. 喺 chat 入面打 `/compact` 命令手動壓縮
  2. 唔加 `[1m]` 直接用 `ANTHROPIC_MODEL='gpt-5.4' claude-cc`，等 Claude Code 用 200K 默認 threshold 提早 compact
  3. 大型 task 用返 native Anthropic（`claude` 行 Opus 4.7 — 真係 1M context）

**完全停掉 auto-compact**：

設 `DISABLE_AUTO_COMPACT=1` 喺 env 或者 `~/.claude/settings.json`。風險：撞到 upstream 真實 limit 之前 Claude Code 唔會自動幫你壓縮。手動 `/compact` 仍然 work。

**唔好諗住嘅 workaround**：
- ❌ 改 `[1m]` 做 `[400k]`：proxy 嘅 `normalizeIncomingModel()` 只 strip `[1m]`，其他 suffix 會原樣送上游 → OpenAI 認唔到 model 而 error
- ❌ Set `CCP_*` env vars 解鎖更大 context：proxy 冇呢個 feature

### 點 verify 限制

```sh
# 撞 limit 嘅 error 喺 log 入面
tail -f ~/.local/state/claude-code-proxy/proxy.log | grep -iE 'context|too.long|exceed|400|429'
```

---

## 🔐 帳號管理

### Codex (ChatGPT) auth 命令

| 命令 | 作用 |
|------|------|
| `claude-cc-proxy codex auth login` | Browser PKCE OAuth via `auth.openai.com`（local callback :1455）|
| `claude-cc-proxy codex auth device` | Device-code flow，headless 機用 |
| `claude-cc-proxy codex auth status` | 睇 account ID + token expiry + storage |
| `claude-cc-proxy codex auth logout` | 清 stored credentials |

`status` 輸出例子（macOS）：
```
Account: 010e864f-c430-48e5-8744-9e076ecc4b75
Expires: 2026-05-23T05:47:30.970Z (in 863104s)
Storage: macOS Keychain
```

Token auto-refresh：access token expire 前 5 分鐘 proxy 會自動 refresh，有 single-flight guard 防 stampede。

### Kimi auth 命令（如果你想用 kimi.com）

| 命令 | 作用 |
|------|------|
| `claude-cc-proxy kimi auth login` | Device-code flow，印 URL + code |
| `claude-cc-proxy kimi auth status` | 睇 user ID + expiry + scope + storage |
| `claude-cc-proxy kimi auth logout` | 清 stored credentials |

Kimi access token 只 ~15 分鐘 expire，proxy 同樣自動 refresh。Kimi 嘅 device_id 喺 `~/.config/claude-code-proxy/kimi/device_id`，bound 入個 JWT，**唔好亂刪**。

### Token 存放位置

| 平台 | Codex token | Kimi token |
|------|------------|-----------|
| **macOS** | Keychain service `claude-code-proxy.codex` | Keychain service `claude-code-proxy.kimi` |
| Linux/其他 | `~/.config/claude-code-proxy/codex/auth.json` (mode 0600) | `~/.config/claude-code-proxy/kimi/auth.json` (mode 0600) |

### MiMo key 存放位置（本 repo launcher）

| 平台 | MiMo key |
|------|---------|
| **macOS** | Keychain service `mimo-claude-code` |
| 其他 | 目前本 repo launcher 主要按 env vars / macOS Keychain 設計，未做 Linux file-based helper |

### 點更新 MiMo API key（唔好直接寫落 shell history）

**推薦做法：直接重跑 setup script。**  
因為 [scripts/setup-mimo-keychain.sh](/Users/howard/Projects/claude-backend-launchers/scripts/setup-mimo-keychain.sh) 內部用 `security add-generic-password -U ...`，`-U` 代表 **同一個 service 存在就更新**。

```sh
/Users/howard/Projects/claude-backend-launchers/scripts/setup-mimo-keychain.sh
```

然後把**新 key**貼入 prompt。  
唔使先 delete，再 add；script 會直接覆蓋舊值。

**你而家如果要把舊 `tp-...` key 換成新 `sk-...` key：**

1. 跑：
   ```sh
   /Users/howard/Projects/claude-backend-launchers/scripts/setup-mimo-keychain.sh
   ```
2. 當 prompt 出現 `Mimo auth token:` 時，貼入新 key
3. 之後重新開：
   ```sh
   mimo-claude
   ```

### 點安全驗證 MiMo API key + endpoint 係咪通

```sh
/Users/howard/Projects/claude-backend-launchers/scripts/test-mimo-api.sh
```

呢個 script 會：

- 從 env 或 Keychain service `mimo-claude-code` 讀 key
- 用 `https://api.xiaomimimo.com/anthropic/v1/messages`
- 送一個極細 request
- 成功就回應一段 JSON；正常應見到 assistant reply `ok`

如果你想手動清除舊 key，先做：

```sh
security delete-generic-password -a "$USER" -s "mimo-claude-code" 2>/dev/null || true
```

再重跑 setup script。

macOS 想直接睇 keychain：
```sh
security find-generic-password -s "claude-code-proxy.codex" -w   # 印 raw JSON token blob
# 或者 GUI: Keychain Access app → 搜 "claude-code-proxy"
```

---

## 📝 Config file 替代 env vars

Proxy 支援 `~/.config/claude-code-proxy/config.json` 做設定，等於每個 env var 嘅靜態替代。precedence：**env > config.json > built-in default**。

Schema 例子（所有 key 都 optional）：

```json
{
  "port": 18765,
  "aliasProvider": "codex",
  "codex": {
    "originator": "claude-code-proxy",
    "userAgent": "claude-code-proxy/dev",
    "model": "gpt-5.4",
    "effort": "xhigh",
    "serviceTier": "fast",
    "baseUrl": "https://chatgpt.com/backend-api/codex/responses"
  },
  "kimi": {
    "userAgent": "KimiCLI/1.37.0",
    "oauthHost": "https://auth.kimi.com",
    "baseUrl": "https://api.kimi.com/coding/v1"
  },
  "log": {
    "stderr": false,
    "verbose": false
  }
}
```

如果你用 config file 寫 `"effort": "xhigh"`，就可以**刪走 `claude-cc-proxy` wrapper 入面個 env var**，直接跑 `claude-code-proxy serve`。

Malformed JSON 會喺 stderr report 然後 ignored — 唔會搞掛 proxy。

---

## 🔬 Verify / Debug

### 確認 proxy 收到啲咩、出咩

```sh
# 普通 log
tail -f ~/.local/state/claude-code-proxy/proxy.log

# 篩選 effort/reasoning
tail -f ~/.local/state/claude-code-proxy/proxy.log | grep -iE 'reasoning|effort'

# 開 verbose mode（要重啟 proxy）
CCP_LOG_VERBOSE=1 claude-cc-proxy serve
```

### Health check

Proxy 提供 `GET /healthz` endpoint：

```sh
curl -s http://127.0.0.1:18765/healthz
# 返 {"ok":true} 代表 alive
```

Quick one-liner：
```sh
curl -fs http://127.0.0.1:18765/healthz >/dev/null && echo "proxy alive" || echo "proxy dead"
```

### Proxy 支援嘅 endpoints

Proxy 只 implement Claude Code 用到嘅 subset：

| Endpoint | 用途 |
|----------|------|
| `POST /v1/messages` | 主 turn endpoint (streaming + non-streaming) |
| `POST /v1/messages?beta=true` | 同上（Claude Code 永遠寄 `?beta=true`） |
| `POST /v1/messages/count_tokens` | 用 `gpt-tokenizer` (o200k_base) 本地計 token；Claude Code compaction logic 用 |
| `GET /healthz` | Liveness check |

### `claude-cc` 唔識用？
- Proxy 未起 → `claude-cc-proxy serve`
- Port 18765 比人佔 → `PORT=18766 claude-cc-proxy serve`，同時改 `claude-cc` 入面個 port
- Token expire → `claude-cc-proxy codex auth login` 重新登入
- 上游 model 唔支援你個 ChatGPT account → 用 README 確認過嘅 `gpt-5.4` 或 `gpt-5.3-codex`

---

## 🤖 開機自動啟動 proxy（macOS LaunchAgent）

寫一次 `~/Library/LaunchAgents/com.user.claude-code-proxy.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.user.claude-code-proxy</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/howard/.local/bin/claude-cc-proxy</string>
    <string>serve</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/Users/howard/.local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Users/howard/.local/state/claude-code-proxy/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/howard/.local/state/claude-code-proxy/launchd.err.log</string>
</dict>
</plist>
```

載入：
```sh
launchctl load ~/Library/LaunchAgents/com.user.claude-code-proxy.plist
launchctl start com.user.claude-code-proxy
```

關閉：
```sh
launchctl unload ~/Library/LaunchAgents/com.user.claude-code-proxy.plist
```

裝咗 LaunchAgent 之後 boot 自動跑、crash 自動重啟，唔使開 tab。

---

## 🧹 升級

```sh
# 睇最新 release
curl -fsSL https://api.github.com/repos/raine/claude-code-proxy/releases/latest | grep tag_name

# 拎新版本（手動，安全）
VERSION=v0.0.13   # 改返做最新 tag
cd /tmp
curl -fsSL -o ccp.tar.gz \
  "https://github.com/raine/claude-code-proxy/releases/download/${VERSION}/claude-code-proxy-darwin-arm64.tar.gz"
curl -fsSL -o ccp.sha256 \
  "https://github.com/raine/claude-code-proxy/releases/download/${VERSION}/claude-code-proxy-darwin-arm64.sha256"
shasum -a 256 -c ccp.sha256 || exit 1
tar -xzf ccp.tar.gz
chmod +x claude-code-proxy
mv -f claude-code-proxy ~/.local/bin/claude-code-proxy
codesign --remove-signature ~/.local/bin/claude-code-proxy 2>/dev/null
codesign --sign - --force ~/.local/bin/claude-code-proxy
~/.local/bin/claude-code-proxy --version
rm ccp.tar.gz ccp.sha256
```

升級後重啟 proxy（`launchctl kickstart -k gui/$(id -u)/com.user.claude-code-proxy` 如果用 LaunchAgent）。

---

## 🗑️ Uninstall

### 移除 Gemini mux 試裝（`claude-code-mux` / `ccm-start` / `gemini-claude`）

如果你想**完整移除**今次試過的 Gemini proxy / mux 路線，按以下順序做：

```sh
# 1. 停掉本機 mux（如果仲跑緊）
ccm stop 2>/dev/null || true
pkill -f '/Users/howard/.local/bin/ccm start' 2>/dev/null || true

# 2. 刪 user-level commands
rm -f ~/.local/bin/ccm
rm -f ~/.local/bin/ccm-start
rm -f ~/.local/bin/gemini-claude

# 3. 刪本機 mux state / OAuth tokens / config
rm -rf ~/.claude-code-mux
```

驗證：

```sh
which ccm ccm-start gemini-claude 2>/dev/null
# 預期：（無 output）

ls ~/.claude-code-mux 2>/dev/null
# 預期：No such file or directory
```

```sh
# 1. 殺 proxy
pkill -f claude-code-proxy

# 2. 關 LaunchAgent（如果有裝）
launchctl unload ~/Library/LaunchAgents/com.user.claude-code-proxy.plist
rm ~/Library/LaunchAgents/com.user.claude-code-proxy.plist

# 3. 刪 binary + wrappers
rm ~/.local/bin/claude-code-proxy
rm ~/.local/bin/claude-cc
rm ~/.local/bin/claude-cc-proxy

# 4. 清 macOS Keychain credentials（重要！rm -rf ~/.config 唔會清呢個）
security delete-generic-password -s "claude-code-proxy.codex"  2>/dev/null || true
security delete-generic-password -s "claude-code-proxy.kimi"   2>/dev/null || true

# 5. 清 config / log / 殘留 file-based auth（Linux 嘅 path，macOS 通常空）
rm -rf ~/.config/claude-code-proxy
rm -rf ~/.local/state/claude-code-proxy

# 6. 改返 settings.json
# "effortLevel": "max" → "high" （如果你想返去原本）
```

Verify 清乾淨：
```sh
security find-generic-password -s "claude-code-proxy.codex" 2>&1 | head -3
# 預期：The specified item could not be found in the keychain.
which claude-code-proxy claude-cc claude-cc-proxy 2>/dev/null
# 預期：（無 output）
```

---

## ⚠️ 重要 caveat / limitations（官方）

### 1. Terms of Service gray area
README 明文：用非官方 client 連 Codex/Kimi backend 係 **gray area**，"**use at your own risk**"。建議：
- 用次要 ChatGPT account 試
- 唔好放生產 code / 客戶資料 / secrets 落去
- 純試 / 個人項目用

### 2. Rate limit 共享
你個 ChatGPT account quota 同所有 client（網頁版、ChatGPT app、proxy）共享。Codex 嘅 `codex.rate_limits.limit_reached` 同 Kimi 嘅 HTTP 429 都會 surface 做 HTTP 429 + `retry-after`。

### 3. Codex — reasoning blocks 唔轉發 ⚠️
官方限制：upstream model 即使有 reasoning，**Codex 路徑唔會 forward 返 Claude Code**，所以你**睇唔到 thinking block**。Response quality 唔受影響，但 debug 時冇 visibility 入 model 諗咩。

> Kimi 路徑就 forward thinking 做 Anthropic-style `thinking` content blocks（除非你 disable thinking）。

### 4. Codex — image inputs in `tool_result` 會 placeholder
Codex Responses API 嘅 `function_call_output` 只接受 string，所以 nested 喺 `tool_result` 入面嘅 image block 會變 `[image omitted: <media_type>]`。**Top-level user message 嘅 image 可以正常 pass through**。

Kimi 唔受呢個限制（image 可以 nested 喺 tool result）。

### 5. Session title generation 會消耗 token
Claude Code 同時有個 "generate session title" 嘅 background request，proxy 唔會 stub 走，會照 forward 上游 → 每個 session 消耗少量 tokens。我 wrapper 已經 set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` 但呢個唔會完全停掉所有 background traffic。

### 6. `output_config.format` 部分支援
Codex 路徑下，`output_config.format` 會被 translate 做 Responses API 嘅 `text.format`（json_schema with `strict: true`）。其他 Anthropic-specific `output_config` field 會被丟棄。

### 7. Log 留 prompt 內容
`proxy.log` 嘅 secrets（`authorization`, `access`, `refresh`, `id_token`, `ChatGPT-Account-Id` 等）已 redact，但**普通 prompt / response / code 內容唔會 redact**。敏感 repo 慎用，或者用完 `rm proxy.log`。

### 8. 兩個 backend 並存
`claude`（Anthropic）同 `claude-cc`（GPT-5.4）可以同時跑唔同 tab，互不干擾。 Proxy 一次 listen 一個 port，所有 session 共用同一個 proxy process。

---

## 📊 Quick Reference

| 命令 | Backend | Effort |
|------|---------|--------|
| `claude` | Anthropic Opus 4.7 | max (per settings.json) |
| `claude-cc` | GPT-5.4 via proxy | max → xhigh (Codex mapping)，sub-agent 跟自己 frontmatter |
| `claude-cc-proxy serve` | 起 proxy server（pass-through，無 override） | n/a |
| `claude-cc-proxy codex auth status` | 睇 ChatGPT 登入狀態 | n/a |

---

## 🔗 Links

- GitHub: https://github.com/raine/claude-code-proxy
- Release: https://github.com/raine/claude-code-proxy/releases
- 當前版本: v0.0.12

> 本指南由 Claude (Opus 4.7) 於 2026-05-13 為 howard@dress-as.com 製作。
