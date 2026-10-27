# claude-backend-launchers

Cross-platform Claude Code launchers for Xiaomi MiMo, DeepSeek, Z.AI GLM, OpenCode Go, and Codex via CLIProxyAPI. Supports **macOS, Linux, and WSL**, independently of other frameworks. Licensed under [MIT](LICENSE).

## Quick start

Requires Git, Bash 3.2+, curl, and [Claude Code](https://code.claude.com/docs/en/setup) on your PATH. `claudex`, proxy diagnostics, and API smoke tests also require **jq** (`brew install jq` on macOS; `sudo apt-get install jq` on Debian/Ubuntu).

```bash
git clone https://github.com/howardc38/claude-backend-launchers.git
cd claude-backend-launchers
./scripts/install-launchers.sh
export PATH="$HOME/.local/bin:$PATH"
./scripts/setup-credential.sh mimo
mimo-claude
```

The installer creates symlinks; keep the checkout. Set up your own credentials in macOS Keychain, Linux Secret Service, or GPG-encrypted `pass`. Dedicated environment variables are also supported. See the [Linux / WSL guide](docs/linux.md).

## Commands

| Command | Backend | Default main model |
|---|---|---|
| `mimo-claude` | Xiaomi MiMo | `mimo-v2.6-pro[1m]` |
| `deepseek-claude` | DeepSeek | `deepseek-flash[1m]` (V4.1 Flash) |
| `glm-claude` | Z.AI | `glm-5.3[1m]` |
| `claudex` | Codex via CLIProxyAPI | `gpt-6.1-sol` |
| `go-claude` | OpenCode Go | `glm-5.3`, highest supported effort |
| `ask-backend` | MiMo / DeepSeek / GLM / Go | Selected backend's default model |

Model availability and quotas depend on your account. `claudex` requires a separately configured CLIProxyAPI instance and Codex OAuth sign-in; see the [backend guide](docs/multi-backend-guide.md).

`go-claude` requires **Python 3.9+ and CLIProxyAPI 7.2.130+** on PATH. It starts and stops its own private proxy automatically. It supports 24 Go models: the original 20 from GLM, Kimi, DeepSeek, MiMo, MiniMax, Qwen, and Claude Haiku, plus MiniMax M3.1 Flash Free, Grok 4.7, GPT 6 Luna, and Gemini 4 Argon Contributor. `deepseek-flash` is also accepted as an alias. Set up and switch models as follows; see the [Go guide](docs/opencode-go.md) for every model's effort levels and context limits.

```bash
./scripts/install-launchers.sh
./scripts/setup-credential.sh go
go-claude --list-models
go-claude --model kimi-k3
go-claude --model qwen3.8-max
go-claude --model glm-5.3 --effort high
go-claude --model grok-4.7
go-claude --model gpt-6-luna
go-claude --model minimax-m3.1-flash-free --effort max
go-claude --model claude-haiku-5-5 --effort max
# Requires explicit paid-training consent in OpenCode Privacy settings:
go-claude --model gemini-4-argon-contributor
```

Go defaults to each model's highest supported reasoning setting. `--effort max` means maximum for the selected model: Qwen 3.8 and Grok 4.7 receive `xhigh`, Gemini receives `high`, and models without graded effort receive thinking-enabled requests. Unsupported lower effort levels fail before launch. `go-claude` bypasses permission prompts by default; restore checks with `OPENCODE_GO_SKIP_PERMISSIONS=0` or `--permission-mode default`.

Go's Gemini offer is the **Contributor** model, which uses request data for training and is not zero-retention. `gemini-4-argon` is an explicit alias for `gemini-4-argon-contributor`; the non-Contributor Console model is not used as a fallback. OpenCode blocks Contributor requests until paid-training consent is enabled in workspace Privacy settings.

Defaults last verified **2026-10-06** against [MiMo releases](https://mimo.mi.com/docs/en-US/updates/model), [DeepSeek model details](https://api-docs.deepseek.com/quick_start/pricing/), [Z.AI's current configuration](https://docs.z.ai/devpack/latest-model), and [OpenAI's GPT-6 guide](https://developers.openai.com/api/docs/guides/latest-model). `claudex --luna` selects `gpt-6-luna`; GPT-6 Astra is available through `--model gpt-6-astra` when your account provides it. Terra remains the legacy `gpt-5.6-terra` option.

```bash
glm-claude --effort high
DEEPSEEK_MODEL='deepseek-v4-pro[1m]' deepseek-claude
claudex --luna
claudex --model gpt-6.1-sol --effort high
ask-backend glm "compare these two approaches"
```

Explicit `--model` and `--effort` flags override backend environment defaults. Use `--` before prompt text that resembles a launcher option. Detailed model mappings, transport safeguards, and overrides are in the [backend guide](docs/multi-backend-guide.md).

DeepSeek keeps its 1M context window and defaults to an auto-compact window of `786432`, matching the [official Claude Code guide](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/). Override with `DEEPSEEK_AUTO_COMPACT_WINDOW` when needed.

MiMo, DeepSeek, `claudex`, and `go-claude` enable permission bypass by default. Restore prompts with `MIMO_SKIP_PERMISSIONS=0`, `DEEPSEEK_SKIP_PERMISSIONS=0`, `CLAUDEX_SKIP_PERMISSIONS=0`, or `OPENCODE_GO_SKIP_PERMISSIONS=0`. GLM keeps the default permission mode. `ask-backend` also defaults to normal permission checks; existing allow rules and hooks still apply, so it is not a read-only sandbox. Prompts and code go to the selected provider.

## Setup, diagnostics, and live API checks

```bash
./scripts/setup-credential.sh glm
./scripts/debug-auth-source.sh glm
./scripts/debug-cliproxy.sh

./scripts/test-api.sh mimo
./scripts/test-api.sh deepseek
./scripts/test-api.sh glm
./scripts/test-api.sh claudex --luna
./scripts/test-api.sh go --model glm-5.3
# Explicitly check all 23 models that do not train on requests:
./scripts/test-api.sh go --all
```

API smoke tests make live requests to the configured endpoint. They share launcher model defaults, strip the client-side `[1m]` selector, and use provider-specific authentication. The original backend curl checks have a 10-second connection timeout and a 60-second total timeout. Go checks use the actual Claude harness and its configured request timeout, preserving coding-agent identity, sessions, and highest effort. Proxy diagnostics report the full model inventory and the selected model.

GPT-6.1 Sol and Astra smoke requests use low reasoning effort because these models do not support reasoning `none`. Luna, legacy Codex models, and direct-backend smoke requests retain thinking-disabled requests.

Credentials and active proxy configurations belong outside Git; see [`.gitignore`](.gitignore). HTTP credentials are supplied to curl through a file descriptor, not command-line headers. The proxy template still retains request-error logs; details are in the [backend guide](docs/multi-backend-guide.md#proxy-configuration).

## Migration: removed script paths

The original five public commands are retained, with `go-claude` added. This cleanup removes ten legacy administrative script paths; update direct calls as follows:

| Previous path | Replacement |
|---|---|
| `scripts/setup-<backend>-keychain.sh` | `scripts/setup-credential.sh <backend>` |
| `scripts/debug-<backend>-auth-source.sh` | `scripts/debug-auth-source.sh <backend>` |
| `scripts/test-<backend>-api.sh` | `scripts/test-api.sh <backend>` |
| `scripts/test-cliproxy-api.sh [--sol|--luna]` | `scripts/test-api.sh claudex [--sol|--luna]` |

Here `<backend>` is `mimo`, `deepseek`, or `glm`. The proxy smoke default now follows `CLAUDEX_MODEL` / the Sol launcher default; use `--luna` for the previous smoke default. jq is required for proxy checks. `CLAUDEX_EFFORT=none` is rejected because Claude Code does not support it as an effort level.

## Development

```bash
python3 -B -m unittest discover -s tests -v
```

Tests use fake credentials and local HTTP fixtures. If Claude Code is installed, contract tests check its actual requests against loopback servers. Go wire tests run every supported effort through a real CLIProxyAPI, including streaming tools and reasoning history. GitHub Actions installs a checksummed, pinned CLIProxyAPI on macOS/Linux and runs real Linux credential-store integration. Local Go wire tests skip when CLIProxyAPI is unavailable. See the [Linux testing guide](docs/linux.md#tests).

Backend defaults live in [scripts/lib/backends.sh](scripts/lib/backends.sh), launch policy in [scripts/lib/launch.sh](scripts/lib/launch.sh), credential resolution in [scripts/lib/credentials.sh](scripts/lib/credentials.sh), and HTTP handling in [scripts/lib/http.sh](scripts/lib/http.sh).

## License

[MIT](LICENSE) © 2026 howardc38.
