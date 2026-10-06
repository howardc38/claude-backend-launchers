# claude-backend-launchers

Cross-platform Claude Code launchers for Xiaomi MiMo, DeepSeek, Z.AI GLM, and Codex via CLIProxyAPI. Supports **macOS, Linux, and WSL**, independently of other frameworks. Licensed under [MIT](LICENSE).

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
| `ask-backend` | MiMo / DeepSeek / GLM | Selected backend's default model |

Model availability and quotas depend on your account. `claudex` requires a separately configured CLIProxyAPI instance and Codex OAuth sign-in; see the [backend guide](docs/multi-backend-guide.md).

Defaults last verified **2026-10-06** against [MiMo releases](https://mimo.mi.com/docs/en-US/updates/model), [DeepSeek model details](https://api-docs.deepseek.com/quick_start/pricing/), [Z.AI's current configuration](https://docs.z.ai/devpack/latest-model), and [OpenAI's GPT-6 guide](https://developers.openai.com/api/docs/guides/latest-model). `claudex --luna` selects `gpt-6-luna`; GPT-6 Astra is available through `--model gpt-6-astra` when your account provides it. Terra remains the legacy `gpt-5.6-terra` option.

```bash
glm-claude --effort high
DEEPSEEK_MODEL='deepseek-v4-pro[1m]' deepseek-claude
claudex --luna
claudex --model gpt-6.1-sol --effort high
ask-backend glm "compare these two approaches"
```

Explicit `--model` and `--effort` flags override backend environment defaults. Use `--` before prompt text that resembles a launcher option. Detailed model mappings, transport safeguards, and overrides are in the [backend guide](docs/multi-backend-guide.md).

MiMo, DeepSeek, and `claudex` enable permission bypass by default. Restore prompts with `MIMO_SKIP_PERMISSIONS=0`, `DEEPSEEK_SKIP_PERMISSIONS=0`, or `CLAUDEX_SKIP_PERMISSIONS=0`. GLM keeps the default permission mode. `ask-backend` also defaults to normal permission checks; existing allow rules and hooks still apply, so it is not a read-only sandbox. Prompts and code go to the selected provider.

## Setup, diagnostics, and live API checks

```bash
./scripts/setup-credential.sh glm
./scripts/debug-auth-source.sh glm
./scripts/debug-cliproxy.sh

./scripts/test-api.sh mimo
./scripts/test-api.sh deepseek
./scripts/test-api.sh glm
./scripts/test-api.sh claudex --luna
```

API smoke tests make live requests to the configured endpoint. They share launcher model defaults, strip the client-side `[1m]` selector, and use provider-specific authentication. Requests have a 10-second connection timeout and a 60-second total timeout. Proxy diagnostics report the full model inventory and the selected model.

GPT-6.1 Sol and Astra smoke requests use low reasoning effort because these models do not support reasoning `none`. Luna, legacy Codex models, and direct-backend smoke requests retain thinking-disabled requests.

Credentials and active proxy configurations belong outside Git; see [`.gitignore`](.gitignore). HTTP credentials are supplied to curl through a file descriptor, not command-line headers. The proxy template still retains request-error logs; details are in the [backend guide](docs/multi-backend-guide.md#proxy-configuration).

## Migration: removed script paths

The five public commands above are retained. This cleanup removes ten legacy administrative script paths; update direct calls as follows:

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

Tests use fake credentials and local HTTP fixtures. If Claude Code is installed, an additional contract test checks its actual request effort and effective context window against a loopback server. GitHub Actions runs the offline suite on macOS/Linux and real Linux credential-store integration. See the [Linux testing guide](docs/linux.md#tests).

Backend defaults live in [scripts/lib/backends.sh](scripts/lib/backends.sh), launch policy in [scripts/lib/launch.sh](scripts/lib/launch.sh), credential resolution in [scripts/lib/credentials.sh](scripts/lib/credentials.sh), and HTTP handling in [scripts/lib/http.sh](scripts/lib/http.sh).

## License

[MIT](LICENSE) © 2026 howardc38.
