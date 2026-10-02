# claude-backend-launchers

當 Claude Code 用盡 token / 想用其他後端時嘅 launcher + 手冊。
由 auto-dev-docs 抽出（與 auto-dev 框架零耦合）。

**Codex / Tibo `claudex`（CLIProxyAPI + ChatGPT OAuth）**
> 預設 `gpt-5.6-sol`、主 session / sub-agent 都係 `max`、tool concurrency 3，而且預設 `--dangerously-skip-permissions`。想用 Luna：`claudex --luna`；想保留 permission prompts：`CLAUDEX_SKIP_PERMISSIONS=0 claudex`。
- `claudex` — Tibo 方法嘅完整 launcher，連去 loopback-only `http://127.0.0.1:8317`
- `scripts/claude-cliproxy.sh` — model / effort / permission / nesting 設定
- `scripts/test-cliproxy-api.sh` — Sol / Luna API smoke test
- `scripts/debug-cliproxy.sh` — masked diagnostics
- `config/cliproxyapi.conf.example` — 安全本機設定範本

**MiMo（小米 MiMo Anthropic-compat endpoint）**
> 預設 `mimo-v2.6-pro[1m]`；主 session、fast tier、sub-agent 全部用 Pro 1M，Claude Code effort 固定 `max`，context ceiling `1048576`，auto-compact `786432`，並預設加入 `--dangerously-skip-permissions`。穩定性保護：10 分鐘 request timeout、90 秒首 byte／stream idle watchdog、3 retries、tool concurrency 3、允許 streaming 失敗時轉 non-streaming。MiMo 目前將所有非 `none` effort 視為同一個 thinking-on 級別，所以 `max` 係 client 最高設定，但服務端實際推理強度不高於 `high`。要恢復 permission prompts：`MIMO_SKIP_PERMISSIONS=0 mimo-claude`。
- `mimo-claude` — launcher，exec `scripts/claude-mimo.sh`
- `scripts/setup-mimo-keychain.sh` — 寫 / 更新 token 入 macOS Keychain
- `scripts/test-mimo-api.sh` — endpoint smoke test
- `scripts/debug-mimo-auth-source.sh` — 印 auth 來源（值已 mask）

**DeepSeek（Anthropic-compatible endpoint；Flash-0731 / Pro-0813）**
> 主 model 預設 `deepseek-v4-flash[1m]` + `max` effort；sub-agent / fast tier 用 `deepseek-v4-flash`；預設加入 `--dangerously-skip-permissions`。`[1m]` 係 Claude Code 官方支援嘅 client-side context selector：Flash 原生支援 1M，主 model 應保留 suffix；CLI 送上游前會 strip。要臨時用 Pro：`DEEPSEEK_MODEL='deepseek-v4-pro[1m]' deepseek-claude`。要恢復 permission prompts：`DEEPSEEK_SKIP_PERMISSIONS=0 deepseek-claude`。
- `deepseek-claude` — launcher，exec `scripts/claude-deepseek.sh`
- `scripts/setup-deepseek-keychain.sh` — 寫 / 更新 token 入 macOS Keychain
- `scripts/test-deepseek-api.sh` — endpoint smoke test
- `scripts/debug-deepseek-auth-source.sh` — 印 auth 來源（值已 mask）

**GLM / Z.AI（官方 Claude Code endpoint，預設 `glm-5.2[1m]`）**
> 官方 Claude Code base URL：`https://api.z.ai/api/anthropic`。Opus/Sonnet → `glm-5.2[1m]`，Haiku / small-fast → `glm-4.5-air`；`CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000`。
- `glm-claude` — launcher，exec `scripts/claude-glm.sh`
- `scripts/setup-glm-keychain.sh` — 寫 / 更新 token 入 macOS Keychain
- `scripts/test-glm-api.sh` — endpoint smoke test（raw curl 會 strip `[1m]`）
- `scripts/debug-glm-auth-source.sh` — 印 auth 來源（值已 mask）

**嵌套呼叫（由官方 Claude Code call 後端 agent）**
- `ask-backend` — wrapper，exec `scripts/ask-backend.sh`；安全咁 headless（`claude -p`）call `mimo` / `deepseek` / `glm`，已做 nesting env 衛生。**預設唯讀**（唔會改檔）；要佢改檔加 `--permission-mode acceptEdits`，完全自主加 `--dangerously-skip-permissions`（慎用）。資料會送去第三方 backend
- `~/.claude/commands/ask-backend.md` — 全域 slash command `/ask-backend`（用法見手冊「嵌套呼叫」section）

**手冊**
- `docs/multi-backend-guide.md` — Tibo / CLIProxyAPI + 多後端完整手冊

## 硬規則（安全）
直連 backend API key 同 CLIProxyAPI 本地 client key 存 macOS Keychain（MiMo → `mimo-claude-code`；DeepSeek → `deepseek-claude-code`；GLM → `glm-claude-code`；CLIProxyAPI client → `cliproxyapi-claudex`）。CLIProxyAPI 上游 OAuth credential 由程式管理於 `~/.cli-proxy-api`，directory / file 必須分別維持 `0700` / `0600`，**永不**放入 repo / git。
唔好 commit 任何 `.env` / `*.local` / token 檔（見 .gitignore）。PRIVATE repo。
