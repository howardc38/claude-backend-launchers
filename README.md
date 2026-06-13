# claude-backend-launchers

當 Claude Code 用盡 token / 想用其他後端時嘅 launcher + 手冊。
由 auto-dev-docs 抽出（與 auto-dev 框架零耦合）。

- `mimo-claude` — launcher，exec `scripts/claude-mimo.sh`（小米 MiMo Anthropic-compat endpoint）
- `scripts/setup-mimo-keychain.sh` — 寫 / 更新 token 入 macOS Keychain
- `scripts/test-mimo-api.sh` — endpoint smoke test
- `scripts/debug-mimo-auth-source.sh` — 印 auth 來源（值已 mask）
- `docs/claude-cc-guide.md` — 多後端手冊

## 硬規則（安全）
Token **只**存 macOS Keychain service `mimo-claude-code`，runtime 先讀，**永不**寫入 disk / git。
唔好 commit 任何 `.env` / `*.local` / token 檔（見 .gitignore）。PRIVATE repo。
