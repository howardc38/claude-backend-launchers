# Backend and proxy operations

For installation and the command overview, see [README](../README.md). Linux/WSL credential-store and service setup is covered in the [Linux guide](linux.md).

## Model and launch settings

The canonical defaults are in [backends.sh](../scripts/lib/backends.sh). Launchers and API smoke tests use the same backend profile.

| Backend | Main model | Fast / Haiku | Subagents | Default effort | Permission bypass |
|---|---|---|---|---|---|
| MiMo | `mimo-v2.6-pro[1m]` | Selected main model | Selected fast model | `max` | Enabled |
| DeepSeek | `deepseek-flash[1m]` (V4.1 Flash) | `deepseek-flash` | Selected fast model | `max` | Enabled |
| GLM | `glm-5.3[1m]` | `glm-5.3-flash[1m]` | Selected main model | `max` | Disabled |
| Codex proxy | `gpt-6.1-sol` | Selected main model | Selected main model | `max` | Enabled |

Verified on 2026-10-06: DeepSeek now recommends the stable `deepseek-flash` API name, currently served by V4.1 Flash. Legacy `deepseek-v4-flash` requests are also served by V4.1 Flash. Sol defaults to GPT-6.1, Luna selects `gpt-6-luna`, and Terra remains the legacy `gpt-5.6-terra` option. Version-specific GPT-5.6 selector flags keep selecting their named versions. See [DeepSeek's model details](https://api-docs.deepseek.com/quick_start/pricing/) and [OpenAI's current model guide](https://developers.openai.com/api/docs/guides/latest-model).

Direct backends use the `MIMO_`, `DEEPSEEK_`, and `GLM_` prefixes. The proxy uses `CLAUDEX_`.

| Setting | Direct backends | Codex proxy |
|---|---|---|
| Main model | `<PREFIX>_MODEL` | `CLAUDEX_MODEL`, `--sol`, `--luna`, `--terra` |
| Fast model | `<PREFIX>_FAST_MODEL` | Follows the main model |
| Subagent model | `<PREFIX>_SUBAGENT_MODEL` | Follows the main model |
| Effort | `<PREFIX>_EFFORT_LEVEL` | `CLAUDEX_EFFORT` |
| Endpoint | `<PREFIX>_BASE_URL` | `CLAUDEX_BASE_URL` |
| Context window | `<PREFIX>_MAX_CONTEXT_TOKENS` | `CLAUDEX_MAX_CONTEXT_TOKENS` |
| Auto-compact window | `<PREFIX>_AUTO_COMPACT_WINDOW` | `CLAUDEX_AUTO_COMPACT_WINDOW` |
| Client request timeout | `<PREFIX>_API_TIMEOUT_MS` | `CLAUDEX_API_TIMEOUT_MS` |
| Tool concurrency | `<PREFIX>_TOOL_CONCURRENCY` | `CLAUDEX_CONCURRENCY` |
| Permission bypass | `<PREFIX>_SKIP_PERMISSIONS` | `CLAUDEX_SKIP_PERMISSIONS` |

Explicit `--model` and `--effort` flags win over backend defaults/environment settings. The resolved values are used both in Claude's command-line arguments and its environment, avoiding the upstream environment-over-flag precedence conflict. Supported client effort values are `low`, `medium`, `high`, `xhigh`, and `max`; provider support can vary. `none` is rejected. Put literal option-like prompt text after `--`:

```bash
glm-claude --effort high
claudex --model gpt-6.1-sol --effort high
claudex -p -- --luna
```

All launchers clear inherited Bedrock, Vertex, Foundry, Anthropic-on-AWS, and Mantle selectors. They set their own endpoint, credentials, models, effort, context, and timeout. User or managed Claude settings can still impose policy; the launchers do not bypass those settings.

Numeric overrides require positive decimal integers; `0`, `00`, and other all-zero spellings are rejected. Boolean overrides require `0` or `1`.

## Context window settings

MiMo declares `1048576` tokens and compacts at `786432`; DeepSeek and GLM declare/compact at `1000000`; the Codex proxy declares/compacts at `1050000`.

For unknown custom model IDs containing `[1m]`, Claude Code otherwise assumes a 1M window and ignores the context variable on its own. When the resolved window differs from 1M, the launcher also sets `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`, allowing the declared window to apply. The actual installed-Claude regression test checks a lowered MiMo window. IDs that resolve to recognized Claude models retain Claude Code's native context rules. See the [official context guide](https://code.claude.com/docs/en/model-config#correct-the-window-for-a-gateway-or-custom-model-id).

```bash
MIMO_MAX_CONTEXT_TOKENS=512000 MIMO_AUTO_COMPACT_WINDOW=400000 mimo-claude
GLM_MAX_CONTEXT_TOKENS=512000 GLM_AUTO_COMPACT_WINDOW=400000 glm-claude
```

The auto-compact window is separate from context capacity and is capped by Claude Code. Model availability, provider limits, and account quotas remain authoritative.

## MiMo transport safeguards

MiMo retains provider-specific defaults in [claude-mimo.sh](../scripts/claude-mimo.sh):

- Request timeout: 10 minutes.
- First-byte / stream-idle watchdogs: 90 seconds each.
- Maximum retries: 3.
- Tool concurrency: 3.
- Non-streaming fallback allowed after a streaming failure.

Override with `MIMO_API_TIMEOUT_MS`, `MIMO_STREAM_FIRST_BYTE_TIMEOUT_MS`, `MIMO_STREAM_IDLE_TIMEOUT_MS`, `MIMO_MAX_RETRIES`, `MIMO_TOOL_CONCURRENCY`, and `MIMO_DISABLE_NONSTREAMING_FALLBACK`.

MiMo currently maps non-`none` effort levels to the same thinking-enabled server mode. A client setting of `max` does not establish a separate server-side maximum compute tier.

GLM retains a 50-minute client request timeout. DeepSeek and the proxy use a 10-minute client timeout. The explicit API smoke command has a separate 60-second HTTP deadline for every backend.

## Headless backend calls

```bash
ask-backend --list
ask-backend mimo "explain this error in one sentence"
ask-backend deepseek "review this function"
ask-backend glm "compare these two approaches"
ask-backend glm "update this file" --permission-mode acceptEdits
```

`ask-backend` clears generic parent Anthropic credentials and uses the selected direct backend's canonical endpoint. It defaults to `--permission-mode default`; existing permission rules and hooks still apply. File edits are not categorically prohibited. Add an explicit editing or bypass flag only when intended. The prompt is passed after `--` and stdin is `/dev/null` so option-like text stays literal and the child does not wait for piped input.

## Proxy configuration

The proxy path follows Tibo's published approach: Claude Code → Anthropic `/v1/messages` → CLIProxyAPI → Codex OAuth. This is an unofficial integration, and upstream policy/entitlement behavior can change.

[cliproxyapi.conf.example](../config/cliproxyapi.conf.example) uses the CLIProxyAPI 7.2.130 configuration layout. Verify your installed version before copying it; newer upstream versions may organize settings differently.

| macOS location | Purpose |
|---|---|
| `/opt/homebrew/bin/cliproxyapi` | Homebrew binary |
| `/opt/homebrew/etc/cliproxyapi.conf` | Private active config, mode `0600` |
| `~/.cli-proxy-api/` | Proxy-managed OAuth; directory `0700`, credential files `0600` |
| Credential service `cliproxyapi-claudex` | Local client key |
| `~/.local/bin/claudex` | Symlink to the public launcher |

Keep the listener on `127.0.0.1:8317`, remote management disabled, and the client key in the OS store. The checked-in template only contains a placeholder key.

`logging-to-file: false` disables application file logging. The template retains up to 10 request-error logs, which may include prompt/request bodies. Treat these as sensitive; see the [upstream logging configuration](https://github.com/router-for-me/CLIProxyAPI/blob/main/config.example.yaml).

```bash
brew services info cliproxyapi
brew services restart cliproxyapi
cliproxyapi -codex-login
cliproxyapi -codex-device-login

CLAUDEX_MODEL=gpt-6.1-sol ./scripts/debug-cliproxy.sh
./scripts/test-api.sh claudex --luna
```

Diagnostics show the full model inventory and check the configured model. Launch preflight checks the exact native model ID selected through flags or the environment. The same selected model is used for the main session and subagents.

Some local compatibility builds advertise OpenAI models as `claude-fable-5-dd-<reversed-native-id>` while accepting native IDs on `/v1/messages`. Preflight also recognizes that exact OpenAI-owned inventory envelope; requests still use the selected native model ID. For arbitrary custom aliases, select the advertised ID explicitly with `CLAUDEX_MODEL` or `--model`.

## Credentials and HTTP checks

| Backend | Dedicated environment variable | Default service |
|---|---|---|
| MiMo | `MIMO_ANTHROPIC_AUTH_TOKEN` | `mimo-claude-code` |
| DeepSeek | `DEEPSEEK_ANTHROPIC_AUTH_TOKEN` | `deepseek-claude-code` |
| GLM | `GLM_ANTHROPIC_AUTH_TOKEN` | `glm-claude-code` |
| Proxy | `CLAUDEX_PROXY_KEY` | `cliproxyapi-claudex` |

Use `scripts/setup-credential.sh <backend>` and `scripts/debug-auth-source.sh <backend>`. Diagnostics never print credential values or raw store stderr. A failed lookup reports the store and exit code; check entry existence, keyring unlock, or GPG decryption rather than assuming the key is absent. Store selection and precedence are documented in the [Linux guide](linux.md).

The shared HTTP helper passes authentication via `/dev/fd/3`, disables user curl configuration, and never puts the credential header in curl's argv. POST JSON uses stdin. MiMo uses `api-key`, DeepSeek/proxy use `Authorization: Bearer`, and GLM uses `x-api-key`. Smoke requests strip `[1m]`. GPT-6.1 Sol/Astra and the compatibility inventory aliases use adaptive thinking with low effort; native Luna/legacy Codex IDs and direct backends retain thinking-disabled requests. Non-2xx responses, malformed model inventories, and missing/unexpected text fail the check.

## Security boundaries

- Keep active configs, OAuth files, API keys, Keychain exports, and token files outside Git.
- The local client key protects access to the proxy; upstream authority comes from the OAuth account.
- Permission bypass remains a documented launcher choice; disable it for untrusted work.
- Prompts and code are sent to the configured provider. The proxy may retain failed request bodies locally.
- Use official clients/APIs when policy or entitlement errors arise.

## References

- [Tibo's original steps and alias](https://x.com/thsottiaux/status/2076119366647894371)
- [Theo's CLIProxyAPI / Claude Code explanation](https://x.com/theo/status/2076114415368482854)
- [CLIProxyAPI repository](https://github.com/router-for-me/CLIProxyAPI)
- [CLIProxyAPI guides](https://help.router-for.me/)
- [Claude environment precedence](https://code.claude.com/docs/en/env-vars#precedence)
- [Z.AI model and effort settings](https://docs.z.ai/devpack/latest-model)
