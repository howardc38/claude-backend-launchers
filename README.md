# claude-backend-launchers

當 Claude Code 用盡 token / 想用其他後端時嘅 launcher + 手冊。
由 auto-dev-docs 抽出（與 auto-dev 框架零耦合）。

**MiMo（小米 MiMo Anthropic-compat endpoint）**
- `mimo-claude` — launcher，exec `scripts/claude-mimo.sh`
- `scripts/setup-mimo-keychain.sh` — 寫 / 更新 token 入 macOS Keychain
- `scripts/test-mimo-api.sh` — endpoint smoke test
- `scripts/debug-mimo-auth-source.sh` — 印 auth 來源（值已 mask）

**DeepSeek（DeepSeek Anthropic-compat endpoint，預設 `deepseek-v4-pro`）**
- `deepseek-claude` — launcher，exec `scripts/claude-deepseek.sh`
- `scripts/setup-deepseek-keychain.sh` — 寫 / 更新 token 入 macOS Keychain
- `scripts/test-deepseek-api.sh` — endpoint smoke test
- `scripts/debug-deepseek-auth-source.sh` — 印 auth 來源（值已 mask）

**嵌套呼叫（由官方 Claude Code call 後端 agent）**
- `ask-backend` — wrapper，exec `scripts/ask-backend.sh`；安全咁 headless（`claude -p`）call `mimo` / `deepseek`，已做 nesting env 衛生
- `~/.claude/commands/ask-backend.md` — 全域 slash command `/ask-backend`（用法見手冊「嵌套呼叫」section）

**手冊**
- `docs/claude-cc-guide.md` — 多後端手冊

## 硬規則（安全）
Token **只**存 macOS Keychain（MiMo → service `mimo-claude-code`；DeepSeek → service `deepseek-claude-code`），runtime 先讀，**永不**寫入 disk / git。
唔好 commit 任何 `.env` / `*.local` / token 檔（見 .gitignore）。PRIVATE repo。
