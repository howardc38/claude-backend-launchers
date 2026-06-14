# Claude Code Multi-Backend Guide — 個人使用手冊

> 透過 `raine/claude-code-proxy` 用 ChatGPT 訂閱跑 Claude Code，作為 Anthropic Opus 嘅替代 backend。
>
> 設定日期：2026-05-13（升級覆核 2026-06-13）· macOS Apple Silicon (darwin-arm64) · proxy v0.0.18
>
> **內容已對齊**：[官方 README](https://github.com/raine/claude-code-proxy/blob/main/README.md)（對應 v0.0.18 `--help` / `models`）+ binary `strings` 直接 verify + 本機實際 endpoint 測試。所有 env var / mapping / file path 都有 source。

> **增補（2026-06-09）**：本 repo 另外加入咗 **MiMo 直連 launcher**，唔經 `claude-code-proxy`，直接用 Anthropic-compatible endpoint 跑 Claude Code。以下內容會同時保留：
> - OpenAI / Codex via `claude-code-proxy`
> - MiMo direct via `mimo-claude`
> - 原生 Anthropic via `claude`
>
> **增補（2026-06-13 覆核 + 升級）**：原生 `claude` 現行 flagship 已係 **Opus 4.8**（`claude-opus-4-8`，1M context 預設），取代 Opus 4.7。`claude-code-proxy` **已升級至 v0.0.18**（新增 Cursor provider、`models` 子命令、`CCP_CODEX_TRANSPORT` 等）。`claude-cc` 預設亦由 `gpt-5.4[1m]` 轉為 **`gpt-5.5[1m]`**（本機帳號實測 gpt-5.5 / gpt-5.4 經 Codex 均回 HTTP 200；small/fast 仍用 `gpt-5.4-mini[1m]`，因為冇 gpt-5.5-mini）。舊 binary 備份喺 `~/.local/bin/claude-code-proxy.v0.0.12.bak`。

---

## ⚡ 快速切換總表

| 你打嘅 command | backend | 現時預設 model | context / `[1m]` | effort 行為 |
|---|---|---|---|---|
| `claude` | 原生 Anthropic | 你本機 Claude Code 預設 | 由 Anthropic / Claude Code 原生處理 | Claude Code 原生 |
| `claude-cc` | OpenAI Codex via proxy | `gpt-5.5[1m]` | proxy 會 strip `[1m]` 再送上游；Claude Code 用它調高 auto-compact threshold | `low/medium/high/max` 經 proxy 映射；`max -> xhigh` |
| `mimo-claude` | MiMo direct（Anthropic-compatible） | `mimo-v2.5-pro[1m]`（本機 launcher 目前設定） | `[1m]` 交由 Claude Code / MiMo 配置慣例處理，用來打開長 context 模式 | **無本地 custom mapping**；Claude Code 的 effort 直接 pass-through |
| `deepseek-claude` | DeepSeek direct（Anthropic-compatible） | `deepseek-v4-pro`（fast tier 用 `deepseek-v4-flash`） | **唔好加 `[1m]`**（DeepSeek 官方明講當 formatting artifact）；DeepSeek-V4 原生長 context | effort 經 `output_config.effort` 送上游；DeepSeek 收窄成 **high / max**（low/medium→high，max→max）。複雜 agent（Claude Code）DeepSeek 側預設拉到 `max` |

**最實用理解：**

- 想用原生 Anthropic：`claude`
- 想用 OpenAI / Codex：`claude-cc`
- 想用 MiMo：`mimo-claude`
- 想用 DeepSeek：`deepseek-claude`
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
| `~/.local/bin/claude-code-proxy` | Proxy binary v0.0.18 (~66 MB, ad-hoc signed)；舊版備份 `claude-code-proxy.v0.0.12.bak` |
| `~/.local/bin/claude-cc-proxy` | Wrapper：pass-through 起 proxy（無 env override，效一律由 Claude Code 嗰邊決定） |
| `~/.local/bin/claude-cc` | Wrapper：set ANTHROPIC_* env vars + exec claude |
| `~/.local/bin/mimo-claude` | User-level symlink / launcher：直連 MiMo Anthropic-compatible endpoint |
| **macOS Keychain** service `claude-code-proxy.codex` | OAuth tokens（**唔係檔案** — 用 Keychain Access 或 `security find-generic-password` 睇）|
| **macOS Keychain** service `mimo-claude-code` | MiMo API key（`mimo-claude` 讀呢個 service） |
| `~/.local/bin/deepseek-claude` | User-level symlink / launcher：直連 DeepSeek Anthropic-compatible endpoint |
| **macOS Keychain** service `deepseek-claude-code` | DeepSeek API key（`deepseek-claude` 讀呢個 service） |
| `~/.config/claude-code-proxy/config.json` | 可選 config file（env vars 嘅替代品，[詳見配置 section](#-config-file-替代-env-vars)） |
| `~/.local/state/claude-code-proxy/proxy.log` | JSON-lines log，20 MiB 自動 rotate，secrets 已 redact |
| `~/.claude/settings.json` | Claude Code 設定（`effortLevel: max`） |
| `/Users/howard/Projects/claude-backend-launchers/mimo-claude` | repo 內 launcher entrypoint（user-level symlink 指向呢個檔案） |
| `/Users/howard/Projects/claude-backend-launchers/scripts/claude-mimo.sh` | MiMo 實際 wrapper（set `ANTHROPIC_*` env vars） |
| `/Users/howard/Projects/claude-backend-launchers/scripts/setup-mimo-keychain.sh` | 寫入 / 更新 MiMo key 到 Keychain |
| `/Users/howard/Projects/claude-backend-launchers/scripts/test-mimo-api.sh` | 從 Keychain / env 讀 key，直接 call MiMo Anthropic endpoint 做 smoke test |
| `/Users/howard/Projects/claude-backend-launchers/deepseek-claude` | repo 內 DeepSeek launcher entrypoint（user-level symlink 指向呢個檔案） |
| `/Users/howard/Projects/claude-backend-launchers/scripts/claude-deepseek.sh` | DeepSeek 實際 wrapper（set `ANTHROPIC_*` env vars） |
| `/Users/howard/Projects/claude-backend-launchers/scripts/setup-deepseek-keychain.sh` | 寫入 / 更新 DeepSeek key 到 Keychain |
| `/Users/howard/Projects/claude-backend-launchers/scripts/test-deepseek-api.sh` | 從 Keychain / env 讀 key，直接 call DeepSeek Anthropic endpoint 做 smoke test |

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

Title bar 應該顯示 `gpt-5.5[1m] with max effort`。

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

> 備註：Xiaomi 官方例子用嘅 model 名係淨 `mimo-v2.5-pro`；`[1m]` 係 Claude Code CLI 慣例（見下面「MiMo 版本點理解 `[1m]`」），本機 launcher 預設帶 `[1m]` 屬無害，可用 `MIMO_MODEL=mimo-v2.5-pro` 覆寫。

### Step 5: 想用 DeepSeek（直連，唔經 proxy）

先存 key 入 Keychain（一次）：

```sh
/Users/howard/Projects/claude-backend-launchers/scripts/setup-deepseek-keychain.sh
# 貼入 DeepSeek API key（sk-...）
```

之後：

```sh
deepseek-claude
deepseek-claude --effort max          # 拉到 DeepSeek "max" thinking
DEEPSEEK_MODEL=deepseek-v4-flash deepseek-claude   # 改用 flash（快 / 慳 quota / 唔 think 咁深）
```

**目前本機 `deepseek-claude` 會 set：**

| 變數 | 值 |
|------|----|
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` |
| `ANTHROPIC_MODEL` | `deepseek-v4-pro`（**唔帶 `[1m]`**） |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` / `_SONNET_MODEL` | `deepseek-v4-pro` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `deepseek-v4-flash` |
| `ANTHROPIC_SMALL_FAST_MODEL` | `deepseek-v4-flash` |

> 覆寫位：`DEEPSEEK_MODEL` / `DEEPSEEK_FAST_MODEL` / `DEEPSEEK_BASE_URL` / `DEEPSEEK_KEYCHAIN_SERVICE` / `DEEPSEEK_ANTHROPIC_AUTH_TOKEN`。長期改：改 `scripts/claude-deepseek.sh` 頂部嘅 `DEFAULT_*`。

#### DeepSeek-v4-pro 嘅 thinking mode / effort 點設定 ⭐

> 來源：[DeepSeek Thinking Mode 官方 doc](https://api-docs.deepseek.com/guides/thinking_mode) + [Claude Code 整合 doc](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code)（2026-06-14 覆核）。

- **Thinking 預設係 ON** — `deepseek-v4-pro` 係 reasoning model，thinking toggle 預設 `enabled`，唔使你做嘢去開。
- **Effort 用 Claude Code 原生機制控制**，唔使 set DeepSeek-specific 嘢：
  - `~/.claude/settings.json` 嘅 `effortLevel`、或 `deepseek-claude --effort <low|medium|high|max>`、或 `CLAUDE_CODE_EFFORT_LEVEL=max`。
  - Claude Code 會把佢經 `output_config.effort` 送上游，**DeepSeek 收窄成兩級**：`low`/`medium`/`high` → DeepSeek `high`；`max` → DeepSeek `max`。即係 v4-pro 冇真正嘅 low/medium，最低就係 "high"。
  - DeepSeek 官方仲講明：**對 Claude Code 呢類複雜 agent request，佢哋會自動把 effort 拉到 `max`**。你 `settings.json` 而家已經係 `effortLevel: max` → 即天然行 DeepSeek max。
- **想關 thinking / 要快**：v4-pro 經 Claude Code 嘅 Anthropic 路徑**冇乾淨方法**逐個 request 收 thinking（DeepSeek 只接受 `thinking:{type:disabled}`，而 Claude Code 唔會幫你送呢個、亦冇 "none" effort 級）。要「唔 think 咁深」就**改用 `deepseek-v4-flash`**（`DEEPSEEK_MODEL=deepseek-v4-flash deepseek-claude`，或者交畀 haiku/small-fast mapping 嘅 background 任務行）。
- ⚠️ **成本提醒**：DeepSeek `max` thinking 嘅 chain-of-thought 可以好長 → 食 token 多 + 慢。日常 task 用 `--effort high` 已足夠；淨係硬數學 / 多步 planning / agent 先值得 `max`。

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
| `CCP_CODEX_EFFORT` | `codex.effort` | unset | **強制覆寫** Codex reasoning effort：`none / low / medium / high / xhigh` |
| `CCP_CODEX_MODEL` | `codex.model` | unset | 強制所有 Codex request 用呢個 model（無視 Claude Code 寄咩） |
| `CCP_CODEX_SERVICE_TIER` | `codex.serviceTier` | unset | 強制 Codex service tier：`fast` / `priority`（=fast 上游）/ `flex` |
| `CCP_CODEX_BASE_URL` | `codex.baseUrl` | `https://chatgpt.com/backend-api/codex/responses` | Codex endpoint override（debug 用） |
| `CCP_CODEX_ORIGINATOR` | `codex.originator` | `claude-code-proxy` | `originator` header |
| `CCP_CODEX_USER_AGENT` | `codex.userAgent` | `claude-code-proxy/<ver>` | User-Agent header |
| `CCP_ORIGINATOR` | — | `claude-code-proxy` | `CCP_CODEX_ORIGINATOR` 嘅 fallback |
| `CCP_USER_AGENT` | — | unset | `CCP_CODEX_USER_AGENT` 嘅 fallback |
| `CCP_CODEX_TRANSPORT` | — | — | Codex 上游傳輸模式（`websocket` / `http` / `auto`）— **v0.0.18 新增** |
| `CCP_TRAFFIC_LOG` | — | unset | 額外寫低 request/response traffic log — **v0.0.18 新增** |
| `CCP_CURSOR_BASE_URL` / `_CLIENT_VERSION` / `_AGENT_BUNDLE` / `_AUTH_TOKEN` | — | — | Cursor provider 設定（endpoint / client version / agent bundle / token）— **v0.0.18 新增** |

> v0.0.18 新增嘅 env var **名**由 binary `strings` 確認；其 config key 同預設值未逐一核實，需要時用 `claude-code-proxy --help` / `models --full` 對。

我預設**冇 set** 任何 proxy override env vars — 全部行 default + Claude Code 嗰邊（settings.json / agent frontmatter）控制。

### Claude Code 嘅 env vars（我 wrapper 入面 set）

| 變數 | 我嘅值 | 作用 |
|------|--------|------|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:18765` | 指向本機 proxy |
| `ANTHROPIC_AUTH_TOKEN` | `unused` | proxy 唔 check，任何字串都 OK |
| `ANTHROPIC_MODEL` | `gpt-5.5[1m]` | 主 model |
| `ANTHROPIC_SMALL_FAST_MODEL` | `gpt-5.4-mini[1m]` | Claude Code background 任務（title gen、token count）用嘅 model — **必須 set**，否則 background request 會 400。冇 gpt-5.5-mini，故仍用 5.4-mini |
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

`claude-cc` wrapper 默認 `gpt-5.5[1m]`（small/fast 仍係 `gpt-5.4-mini[1m]`）。

### MiMo：切 model / 切 context

`mimo-claude` 預設用 `mimo-v2.5-pro[1m]`。想臨時改 model，可以喺啟動前覆寫 env：

```sh
MIMO_MODEL='mimo-v2.5-pro' mimo-claude
MIMO_MODEL='mimo-v2.5-pro[1m]' mimo-claude
```

> ⚠️ 覆寫一律用 `MIMO_MODEL` / `MIMO_BASE_URL` / `MIMO_FAST_MODEL`。launcher **唔再繼承** parent 嘅 `ANTHROPIC_MODEL` / `ANTHROPIC_BASE_URL`（nesting 衛生，見下面 §嵌套呼叫），所以 `ANTHROPIC_MODEL='...' mimo-claude` 已經唔生效。

如果你想改長期預設，改 repo 入面呢個檔案：

```sh
/Users/howard/Projects/claude-backend-launchers/scripts/claude-mimo.sh
```

### 不同 backend 點切 model

| backend | 慣常切法 |
|---|---|
| Anthropic 原生 | `claude` 入面 `/model`，或者本機 Claude Code 設定 |
| OpenAI / Codex via proxy | `ANTHROPIC_MODEL='gpt-5.4-mini[1m]' claude-cc`、`/model` |
| MiMo direct | `MIMO_MODEL='mimo-v2.5-pro[1m]' mimo-claude` 或修改 `scripts/claude-mimo.sh` |
| DeepSeek direct | `DEEPSEEK_MODEL='deepseek-v4-flash' deepseek-claude` 或修改 `scripts/claude-deepseek.sh`（預設 `deepseek-v4-pro`，唔帶 `[1m]`） |

### 本機帳號實測可用嘅 model（2026-06-13 經 proxy 直測）

- ✅ `gpt-5.5` — 本機帳號實測經 Codex 回 **HTTP 200**，已設為 `claude-cc` 預設
- ✅ `gpt-5.4` — 同樣實測 200（之前網上傳「ChatGPT-login 受限」喺本帳號**唔適用**）
- 🟡 `gpt-5.3-codex` / `gpt-5.4-mini` / `gpt-5.2` — README 標 working，本機未逐一直測

> 註：上游 model 若唔 entitle 你個 ChatGPT account 會收到 400：
> ```
> "The 'gpt-X.X' model is not supported when using Codex with a ChatGPT account."
> ```
> 想自己核：`claude-cc` 入面 `/model`，或啟動時 `ANTHROPIC_MODEL='<model>' claude-cc`。

### `-fast` suffix（priority service tier）

任何 Codex model 後面加 `-fast` = 用 priority service tier（更快、quota 食得多）：

```sh
ANTHROPIC_MODEL='gpt-5.4-fast[1m]' claude-cc
# proxy strip 走 -fast，上游送 "gpt-5.4" + service_tier: "priority"
```

`CCP_CODEX_SERVICE_TIER` env override 比 `-fast` suffix 優先。

### 完整 model list（`claude-code-proxy --help` 印出來）

- **Codex provider**：`gpt-5.2` / `gpt-5.3-codex` / `gpt-5.3-codex-spark` / `gpt-5.4` / `gpt-5.4-mini` / `gpt-5.5`（每個都有 `-fast` 變體）— 本機 `claude-cc` 預設 `gpt-5.5[1m]`
- **Anthropic aliases**：`haiku` / `sonnet` / `opus` / `claude-haiku-4-5` / `claude-haiku-4-5-20251001` / `claude-sonnet-4-6` / `claude-opus-4-7` — **預設 route 去 Codex**（v0.0.18 列表仍係 `claude-opus-4-7`，未加 4-8）
- **Cursor provider**（v0.0.18 新增）：`cursor` / `cursor-agent` / `cursor-composer`(`-fast`) / `cursor-plan` / `cursor-ask` / `composer-2.5`(`-fast`)，加上 `cursor:<id>` / `cursor-plan:<id>` / `cursor-ask:<id>` 形式可叫 **129 個 Cursor catalog model**（例：`cursor:gpt-5.5-high`、`cursor:gemini-3.1-pro`）。auth：`claude-cc-proxy cursor auth login`，token 存 macOS Keychain service `claude-code-proxy.cursor`
- 睇完整列表：`claude-code-proxy models`（精簡）/ `claude-code-proxy models --full`（全部 alias）

---

## 🪆 嵌套呼叫：由官方 Claude Code call 後端 agent

可以喺**官方 Anthropic-backed `claude`** session 入面，叫一個跑 MiMo / DeepSeek 嘅 Claude Code agent 做嘢。

**唔係用 native sub-agent** —— Claude Code 內建 sub-agent（Task tool / agent frontmatter）一律共用 main session 嘅 `ANTHROPIC_*` 連線，無法 route 去另一個 backend（`CLAUDE_CODE_SUBAGENT_MODEL` 只改 model 名，唔改 provider）。

**正解係 headless shell-out**：由 main session 嘅 Bash tool 跑後端 launcher 嘅 print 模式（`-p`）。本 repo 提供一個 wrapper：

```sh
# 唯讀問答（安全預設）— 攞意見 / review / 解釋，唔會郁你啲檔
ask-backend deepseek "review 呢個 function 有冇 bug"
ask-backend deepseek --effort max "解釋呢個 module 點 work"

# 畀佢改檔（auto-accept file edits）
ask-backend deepseek "幫我 fix 呢個 bug" --permission-mode acceptEdits

# 畀佢完全自主（讀寫 + 跑任意 Bash）— 慎用
ask-backend deepseek "重構呢個 module" --dangerously-skip-permissions
```

`ask-backend`（→ `scripts/ask-backend.sh`）做嘅事：

1. 先 `env -u` 清走繼承落嚟嘅 `ANTHROPIC_BASE_URL` / `ANTHROPIC_MODEL` 等（**nesting 衛生**），再 pin 後端 base URL；
2. 用 `claude -p`（headless）跑對應 launcher，回純文字 stdout；
3. auth token 由各 launcher 自己由 macOS Keychain 讀。

> 配合 launcher 本身嘅 nesting 衛生（launcher 已**唔再繼承** parent 嘅 `ANTHROPIC_BASE_URL`/`ANTHROPIC_MODEL`），即使由 `claude-cc`（指住 proxy）嵌套呼叫都唔會連錯 endpoint。

### 權限：佢可唔可以郁你啲檔？⚠️（實測）

nested agent 係**完整 Claude Code**（有齊 `Read` / `Write` / `Edit` / `Bash`），背後 LLM 只係換成 DeepSeek / MiMo。能唔能改檔，由**權限模式**決定：

| 點打 | 行為（已實測） |
|---|---|
| `ask-backend deepseek "..."`（預設） | ⛔ 想 `Write` 會卡喺等授權，headless 冇得批 → **唔會改檔**。實際 = 可讀、可答、唔可改。 |
| `... --permission-mode acceptEdits` | ✅ auto-accept file edits，**會真係寫 / 改檔**。 |
| `... --dangerously-skip-permissions` | ✅✅ 讀寫 + 跑任意 Bash，完全唔問。**慎用**。 |

**兩個關鍵 caveat：**

1. **作用範圍 = 你執行 `ask-backend` 嗰個 cwd**，唔係 launcher repo、亦**冇額外沙箱**。喺 `~/Projects/foo` 跑 `--permission-mode acceptEdits` 就會改 `~/Projects/foo`；`--dangerously-skip-permissions` 更可掂到你帳號掂得到嘅任何嘢。
2. **內容會送去第三方**：就算純讀，agent 睇到嘅 code / 檔案內容都會經 API 送上 DeepSeek / MiMo。敏感 repo / 客戶 code / secrets **唔好**咁畀佢睇。

**建議**：日常用預設（唯讀）；要佢落手改 code 先加 `--permission-mode acceptEdits`，而且喺**乾淨 git working tree** 跑，改完 `git diff` 睇過先收。唔好對住有 secret / 生產 repo 用 `--dangerously-skip-permissions`。

### 全域 slash command `/ask-backend`

`~/.claude/commands/ask-backend.md` 令呢個能力喺**所有**官方 Claude Code session 都有：

```
/ask-backend mimo "explain X"
/ask-backend deepseek --effort max "review this code: ..."
```

它會（已預先授權 Bash）跑 `ask-backend $ARGUMENTS`，再 relay 後端答案 + 註明邊個 backend。

**要知嘅 caveat：**

- nested agent 用**獨立 context + 獨立 quota**（MiMo / DeepSeek key），同當前 Anthropic session 無關。
- 檔案操作 / 權限見上面 [§權限](#權限佢可唔可以郁你啲檔實測)：預設唯讀，要改檔先加 `--permission-mode acceptEdits`。slash command 傳同樣 flag，例如 `/ask-backend deepseek "fix bug" --permission-mode acceptEdits`。
- 後端 launcher 要搵到（repo 喺 `/Users/howard/Projects/claude-backend-launchers`），key 要已存入對應 Keychain service。

---

## 📐 Context Window：`[1m]` 唔等於真係 1M ⚠️

呢個 section 引用 README 官方說明：

### `[1m]` 嘅實際作用

Claude Code 用 model 嘅 context window 決定幾時 auto-compact。對於不認識嘅 model（包括 proxy 用嘅所有 model），Claude Code 默認當佢 **200K context**，所以 auto-compact 會過早觸發。

`[1m]` suffix 係 **Claude Code 自己嘅 convention**，叫佢將 auto-compact 嘅 threshold 調高到 1M token。**呢個唔係解鎖更大 context、亦唔係轉去 API 嘅 experimental 1M mode** — 純粹延遲 auto-compaction 嘅時機。

Proxy 收到 `gpt-5.5[1m]` 之後嘅實作（從 binary 確認）：
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

> ⚠️ **Caveat**：[OpenAI Codex Discussion #1999](https://github.com/openai/codex/discussions/1999) 入面有 user 觀察到 192K-272K，但係 thread 入面亦有人指出個 number 反映 billing 唔係 actual allocation。Proxy README（作者親自寫）話 GPT-5.4 via Codex 至少 400K。

### MiMo 版本點理解 `[1m]`

- `mimo-v2.5-pro` **原生支援 1M context window**（Xiaomi 官方文檔）
- `[1m]` 本質上係 **Claude Code CLI 嘅 client-side 慣例**：append 落 model id 用嚟調高 auto-compact threshold（趨向 1M token），由 CLI 自己處理 —— **唔係 Xiaomi 文檔規定嘅後綴**
- ⚠️ **覆核（2026-06-13）**：可讀到嘅 Xiaomi 官方例子同第三方配置指南（DevTk 等）都用**淨** id `mimo-v2.5-pro`，冇 `[1m]`。所以唔好當 `[1m]` 係「Xiaomi 官方接受的慣例」。

本機 `mimo-claude` 預設帶 `[1m]` 係**無害**做法（CLI 客戶端處理，MiMo 原生 1M context）；如某個 Claude Code CLI build 唔收 bracketed id，用 `MIMO_MODEL=mimo-v2.5-pro mimo-claude` 即可 fallback。  
來源：

- [Claude Code Configuration](https://platform.xiaomimimo.com/docs/integration/claudecode)
- [Model and Rate Limit](https://platform.xiaomimimo.com/docs/en-US/quick-start/model)

### 各 backend 嘅 context / effort 一眼睇

| backend | `[1m]` 作用 | 真實 context / 文檔說法 | effort mapping |
|---|---|---|---|
| Anthropic 原生 | 跟 Anthropic / Claude Code 原生行為 | 以官方 Claude / Anthropic 文檔為準 | 原生 |
| OpenAI Codex via proxy | Claude Code auto-compact hint；proxy strip 後送上游 | `gpt-5.4` via Codex 實測 / README 約 400K+ | `max -> xhigh` |
| MiMo direct | `[1m]` 係 Claude Code CLI client-side 慣例（非 Xiaomi 規定） | Xiaomi 文檔：`mimo-v2.5-pro` 原生 1M context window | **無本地 custom mapping，pass-through** |
| DeepSeek direct | **唔加 `[1m]`**（DeepSeek 官方當 formatting artifact） | DeepSeek-V4 原生長 context（think-max 模式建議 ≥384K） | `output_config.effort`：low/medium/high→`high`，max→`max`；Claude Code agent 預設拉 `max` |

### 用法 implication

**日常 coding task（< 200K context）**：
- ✅ 完全無問題，照 `gpt-5.4[1m]` 用

**Long context task（150K+ tokens）**：
- ⚠️ 接近 GPT-5.4 Codex 嘅 400K 上限就要小心
- 撞 limit 嘅 error：upstream 會 return 400 / `context_length_exceeded`
- 🛡️ 保守做法：
  1. 喺 chat 入面打 `/compact` 命令手動壓縮
  2. 唔加 `[1m]` 直接用 `ANTHROPIC_MODEL='gpt-5.4' claude-cc`，等 Claude Code 用 200K 默認 threshold 提早 compact
  3. 大型 task 用返 native Anthropic（`claude` 行 Opus 4.8 — 1M context，Claude API 預設）

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
Expires: <ISO-8601 timestamp> (in <N>s)
Storage: macOS Keychain
```

Token auto-refresh：access token expire 前 5 分鐘 proxy 會自動 refresh，有 single-flight guard 防 stampede。

### Token 存放位置

| 平台 | Codex token |
|------|------------|
| **macOS** | Keychain service `claude-code-proxy.codex` |
| Linux/其他 | `~/.config/claude-code-proxy/codex/auth.json` (mode 0600) |

### MiMo / DeepSeek key 存放位置（本 repo launcher）

| 平台 | MiMo key | DeepSeek key |
|------|---------|-------------|
| **macOS** | Keychain service `mimo-claude-code` | Keychain service `deepseek-claude-code` |
| 其他 | 目前本 repo launcher 主要按 env vars / macOS Keychain 設計，未做 Linux file-based helper | 同左 |

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
  "codex": {
    "originator": "claude-code-proxy",
    "userAgent": "claude-code-proxy/dev",
    "model": "gpt-5.4",
    "effort": "xhigh",
    "serviceTier": "fast",
    "baseUrl": "https://chatgpt.com/backend-api/codex/responses"
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
VERSION=v0.0.18   # 改返做最新 tag（見上面「睇最新 release」）
cd /tmp
# ⚠️ 用 -O 保留原始檔名：.sha256 檔內寫住原檔名,改名做 ccp.* 會令 shasum -c 搵唔到檔
curl -fsSL -O \
  "https://github.com/raine/claude-code-proxy/releases/download/${VERSION}/claude-code-proxy-darwin-arm64.tar.gz"
curl -fsSL -O \
  "https://github.com/raine/claude-code-proxy/releases/download/${VERSION}/claude-code-proxy-darwin-arm64.sha256"
shasum -a 256 -c claude-code-proxy-darwin-arm64.sha256 || exit 1
tar -xzf claude-code-proxy-darwin-arm64.tar.gz
chmod +x claude-code-proxy
# 備份舊版以便 rollback
cp -p ~/.local/bin/claude-code-proxy ~/.local/bin/claude-code-proxy.bak 2>/dev/null || true
mv -f claude-code-proxy ~/.local/bin/claude-code-proxy
codesign --remove-signature ~/.local/bin/claude-code-proxy 2>/dev/null
codesign --sign - --force ~/.local/bin/claude-code-proxy
~/.local/bin/claude-code-proxy --version
rm claude-code-proxy-darwin-arm64.tar.gz claude-code-proxy-darwin-arm64.sha256
```

升級後重啟 proxy（`launchctl kickstart -k gui/$(id -u)/com.user.claude-code-proxy` 如果用 LaunchAgent）。

---

## 🗑️ Uninstall

### 移除 claude-code-proxy + MiMo launcher

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
README 明文：用非官方 client 連 Codex backend 係 **gray area**，"**use at your own risk**"。建議：
- 用次要 ChatGPT account 試
- 唔好放生產 code / 客戶資料 / secrets 落去
- 純試 / 個人項目用

### 2. Rate limit 共享
你個 ChatGPT account quota 同所有 client（網頁版、ChatGPT app、proxy）共享。Codex 嘅 `codex.rate_limits.limit_reached` 會 surface 做 HTTP 429 + `retry-after`。

### 3. Codex — reasoning blocks 唔轉發 ⚠️
官方限制：upstream model 即使有 reasoning，**Codex 路徑唔會 forward 返 Claude Code**，所以你**睇唔到 thinking block**。Response quality 唔受影響，但 debug 時冇 visibility 入 model 諗咩。

### 4. Codex — image inputs in `tool_result` 會 placeholder
Codex Responses API 嘅 `function_call_output` 只接受 string，所以 nested 喺 `tool_result` 入面嘅 image block 會變 `[image omitted: <media_type>]`。**Top-level user message 嘅 image 可以正常 pass through**。

### 5. Session title generation 會消耗 token
Claude Code 同時有個 "generate session title" 嘅 background request，proxy 唔會 stub 走，會照 forward 上游 → 每個 session 消耗少量 tokens。我 wrapper 已經 set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` 但呢個唔會完全停掉所有 background traffic。

### 6. `output_config.format` 部分支援
Codex 路徑下，`output_config.format` 會被 translate 做 Responses API 嘅 `text.format`（json_schema with `strict: true`）。其他 Anthropic-specific `output_config` field 會被丟棄。

### 7. Log 留 prompt 內容
`proxy.log` 嘅 secrets（`authorization`, `access`, `refresh`, `id_token`, `ChatGPT-Account-Id` 等）已 redact，但**普通 prompt / response / code 內容唔會 redact**。敏感 repo 慎用，或者用完 `rm proxy.log`。

### 8. 兩個 backend 並存
`claude`（Anthropic）同 `claude-cc`（GPT-5.5）可以同時跑唔同 tab，互不干擾。 Proxy 一次 listen 一個 port，所有 session 共用同一個 proxy process。

---

## 📊 Quick Reference

| 命令 | Backend | Effort |
|------|---------|--------|
| `claude` | Anthropic Opus 4.8 | max (per settings.json) |
| `claude-cc` | GPT-5.5 via proxy | max → xhigh (Codex mapping)，sub-agent 跟自己 frontmatter |
| `mimo-claude` | MiMo v2.5 Pro（直連） | pass-through（無本地 mapping） |
| `deepseek-claude` | DeepSeek V4 Pro（直連） | low/med/high→high，max→max；CC agent 預設 max |
| `claude-cc-proxy serve` | 起 proxy server（pass-through，無 override） | n/a |
| `claude-cc-proxy codex auth status` | 睇 ChatGPT 登入狀態 | n/a |

---

## 🔗 Links

- GitHub: https://github.com/raine/claude-code-proxy
- Release: https://github.com/raine/claude-code-proxy/releases
- 當前版本: v0.0.18（本機已裝；upstream latest 同步）

> 本指南由 Claude (Opus 4.7) 於 2026-05-13 為 howard@dress-as.com 製作。
