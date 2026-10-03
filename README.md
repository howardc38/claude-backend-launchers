# claude-backend-launchers

Cross-platform launchers for Claude Code with MiMo, DeepSeek, Z.AI GLM, and Codex via CLIProxyAPI.

Use another backend when you reach Claude Code's usage limits or want a different model. This project works independently of any other framework and is open source under the [MIT License](LICENSE).

Supports **macOS, Linux, and WSL**. Credentials are loaded from macOS Keychain or Linux Secret Service / `pass`. All four backends also accept dedicated environment variables. For Linux installation details, see the [Linux / WSL guide](docs/linux.md).

## Quick start

Requires Git, Bash 3.2+, curl, and `claude` installed on your PATH ([Claude Code installation instructions](https://code.claude.com/docs/en/setup)). Direct backends require your own API key. For `claudex`, install and configure CLIProxyAPI separately and sign in with Codex OAuth; see the [full guide](docs/multi-backend-guide.md).

```bash
git clone https://github.com/howardc38/claude-backend-launchers.git
cd claude-backend-launchers
./scripts/install-launchers.sh
export PATH="$HOME/.local/bin:$PATH"
./scripts/setup-credential.sh mimo      # Hidden input; saves to your OS credential store
mimo-claude
```

The installer creates symlinks, so keep the repository checkout. Each user must configure their own credentials; cloning the repository does not transfer API keys or OAuth credentials.

## Supported backends and default models

| Command | Backend | Default model | Alternatives |
|---|---|---|---|
| `mimo-claude` | Xiaomi MiMo | `mimo-v2.6-pro[1m]` | Override with `MIMO_MODEL` |
| `deepseek-claude` | DeepSeek | `deepseek-v4-flash[1m]` | `DEEPSEEK_MODEL='deepseek-v4-pro[1m]'` |
| `glm-claude` | Z.AI | `glm-5.3[1m]`; fast: `glm-5.3-flash[1m]`; effort: `max` | Override with `GLM_MODEL` / `GLM_FAST_MODEL` |
| `claudex` | Codex via CLIProxyAPI | `gpt-5.6-sol` | `--luna`, `--terra`, or `CLAUDEX_MODEL` |

These are launcher settings. Actual model availability and quotas depend on the provider and your account. MiMo, DeepSeek, and `claudex` skip Claude Code permission prompts by default; the sections below explain how to restore them.

## Usage

### Codex / Tibo `claudex` (CLIProxyAPI + ChatGPT OAuth)

Defaults to `gpt-5.6-sol`, with `max` effort for the main session and subagents, tool concurrency of 3, and `--dangerously-skip-permissions`. Use `claudex --luna` for Luna. Restore permission prompts with `CLAUDEX_SKIP_PERMISSIONS=0 claudex`.

- [`claudex`](claudex) — launcher implementing Tibo's approach, connecting to the loopback-only endpoint `http://127.0.0.1:8317`.
- [`scripts/claude-cliproxy.sh`](scripts/claude-cliproxy.sh) — model, effort, permission, and nesting settings.
- [`scripts/test-cliproxy-api.sh`](scripts/test-cliproxy-api.sh) — Sol / Luna API smoke test.
- [`scripts/debug-cliproxy.sh`](scripts/debug-cliproxy.sh) — diagnostics with credentials hidden.
- [`config/cliproxyapi.conf.example`](config/cliproxyapi.conf.example) — secure local configuration template.

### MiMo (Xiaomi MiMo Anthropic-compatible endpoint)

Defaults to `mimo-v2.6-pro[1m]` for the main session, fast tier, and subagents. Claude Code effort defaults to `max`. The launcher exports `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576`, sets an auto-compact window of `786432`, and enables `--dangerously-skip-permissions`. Recent Claude Code versions assume a 1M window for unknown `[1m]` model IDs and ignore the context override on its own; see the [context configuration notes](docs/multi-backend-guide.md#context-window-settings).

Reliability defaults include a 10-minute request timeout, 90-second first-byte and stream-idle watchdogs, 3 retries, tool concurrency of 3, and non-streaming fallback when streaming fails. MiMo currently treats all non-`none` effort levels as the same thinking-enabled mode: `max` is the highest client setting, but does not provide more server-side reasoning effort than `high`.

Restore permission prompts with `MIMO_SKIP_PERMISSIONS=0 mimo-claude`.

- [`mimo-claude`](mimo-claude) — executes [`scripts/claude-mimo.sh`](scripts/claude-mimo.sh).
- `scripts/setup-credential.sh mimo` — reads hidden input and saves the key to macOS Keychain, Linux Secret Service, or `pass`.
- [`scripts/test-mimo-api.sh`](scripts/test-mimo-api.sh) — endpoint smoke test.
- [`scripts/debug-mimo-auth-source.sh`](scripts/debug-mimo-auth-source.sh) — reports the credential source without exposing its value.

### DeepSeek (Anthropic-compatible endpoint; Flash-0731 / Pro-0813)

The main model defaults to `deepseek-v4-flash[1m]` with `max` effort. Subagents and the fast tier use `deepseek-v4-flash`. The launcher adds `--dangerously-skip-permissions` by default.

`[1m]` is Claude Code's supported client-side context selector. Flash natively supports a 1M context window, so retain the suffix on the main model; the CLI strips it before sending requests to the provider.

Use Pro for a session with `DEEPSEEK_MODEL='deepseek-v4-pro[1m]' deepseek-claude`. Restore permission prompts with `DEEPSEEK_SKIP_PERMISSIONS=0 deepseek-claude`.

- [`deepseek-claude`](deepseek-claude) — executes [`scripts/claude-deepseek.sh`](scripts/claude-deepseek.sh).
- `scripts/setup-credential.sh deepseek` — reads hidden input and saves the key to the OS credential store.
- [`scripts/test-deepseek-api.sh`](scripts/test-deepseek-api.sh) — endpoint smoke test.
- [`scripts/debug-deepseek-auth-source.sh`](scripts/debug-deepseek-auth-source.sh) — reports the credential source without exposing its value.

### GLM / Z.AI (official Claude Code endpoint)

Uses the official Claude Code base URL `https://api.z.ai/api/anthropic`. The main session, subagents, Opus, and Sonnet use `glm-5.3[1m]`; Haiku / small-fast use `glm-5.3-flash[1m]`. Effort is explicitly set to `max`, with context and auto-compact windows of `1000000`. See the [official model and effort settings](https://docs.z.ai/devpack/latest-model).

- [`glm-claude`](glm-claude) — executes [`scripts/claude-glm.sh`](scripts/claude-glm.sh).
- `scripts/setup-credential.sh glm` — reads hidden input and saves the key to the OS credential store.
- [`scripts/test-glm-api.sh`](scripts/test-glm-api.sh) — endpoint smoke test; strips `[1m]` for direct curl requests.
- [`scripts/debug-glm-auth-source.sh`](scripts/debug-glm-auth-source.sh) — reports the credential source without exposing its value.

### Nested backend calls

[`ask-backend`](ask-backend) executes [`scripts/ask-backend.sh`](scripts/ask-backend.sh) to call `mimo`, `deepseek`, or `glm` in headless mode (`claude -p`). It clears inherited endpoint and model settings before launching the child session.

It uses **Claude Code's default permission mode**, without automatically bypassing checks. Existing permission rules still apply, so it does not guarantee read-only execution. Add `--permission-mode acceptEdits` to allow file edits automatically, or `--dangerously-skip-permissions` for autonomous execution; use the latter with care. Prompts and code are sent to the selected third-party backend.

See the nested-call section of the [full guide](docs/multi-backend-guide.md) for examples.

## Documentation

- [Multi-backend guide](docs/multi-backend-guide.md) — Tibo / CLIProxyAPI setup and detailed backend usage.
- [Linux / WSL guide](docs/linux.md) — installation, credential stores, and Linux integration tests.

## Credential security

Store direct-backend API keys and the CLIProxyAPI local client key in macOS Keychain, Linux Secret Service, or GPG-encrypted `pass`. CI can inject credentials through dedicated environment variables.

| Backend | Credential service name |
|---|---|
| MiMo | `mimo-claude-code` |
| DeepSeek | `deepseek-claude-code` |
| GLM | `glm-claude-code` |
| CLIProxyAPI client | `cliproxyapi-claudex` |

CLIProxyAPI manages upstream OAuth credentials in `~/.cli-proxy-api`. Keep directory permissions at `0700` and credential file permissions at `0600`. **Never commit these credentials to Git.**

Do not commit `.env`, `*.local`, or token files; see [`.gitignore`](.gitignore).

## Development and testing

Offline tests require no real API keys and do not contact any backend:

```bash
python3 -B -m unittest discover -s tests -v
```

GitHub Actions runs regression tests on macOS and Linux, plus Secret Service / `pass` integration tests on Linux.

## License

[MIT](LICENSE) © 2026 howardc38.
