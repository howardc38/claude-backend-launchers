# Claude Code multi-backend guide

Supports macOS, Linux, and WSL. See the [Linux guide](linux.md) for Linux credentials, command installation, and CLIProxyAPI setup. The `setup-*-keychain.sh` scripts remain available as aliases; prefer `scripts/setup-credential.sh <backend>`. API smoke tests and diagnostics share the same credential resolver.

> Updated: 2026-10-03. The Codex integration uses Tibo's published approach: CLIProxyAPI + Codex OAuth + `claudex`.

## Choose a launcher

| Command | Backend | Default model / settings |
|---|---|---|
| `claude` | Anthropic | Native Claude Code; unaffected by this repository |
| `claudex` | ChatGPT / Codex OAuth | `gpt-5.6-sol`; main session / subagents use `max`; permission bypass enabled by default |
| `claudex --luna` | ChatGPT / Codex OAuth | `gpt-5.6-luna`; otherwise the same settings |
| `mimo-claude` | Xiaomi MiMo | `mimo-v2.6-pro[1m]`; main / fast / subagents all use Pro; client effort `max`; permission bypass enabled by default |
| `deepseek-claude` | DeepSeek | `deepseek-v4-flash[1m]`; subagents / fast tier use Flash; effort `max`; permission bypass enabled by default |
| `glm-claude` | Z.AI | `glm-5.3[1m]`; fast tier uses `glm-5.3-flash[1m]`; effort `max` |
| `ask-backend` | MiMo / DeepSeek / GLM | Headless child agent; default permission mode, without automatic bypass |

## Tibo's approach

Tibo's July 12, 2026 post describes installing CLIProxyAPI, connecting an account, and using a `claudex` alias to point Claude Code's main model and subagents at `gpt-5.6-sol`, enable effort, set tool concurrency to 3, and disable tool search. Theo's post, cited by Tibo, uses the same approach: CLIProxyAPI understands both Claude and OpenAI formats; sign in with Codex OAuth, then point Claude Code at the local proxy.

This repository keeps that architecture and makes additional settings explicit:

- Default effort is `max`, with the same model for the main session and subagents.
- `--dangerously-skip-permissions` is enabled by default.
- `gpt-5.6-sol` is the default; `--luna` / `--terra` switch models.
- The Claude Code context ceiling is set to `1050000`, matching the OpenAI model specification.
- The local client key is loaded through the credential resolver; the proxy and model are checked before launch.
- Inherited endpoint and cloud-provider settings are cleared to prevent nested sessions from connecting to the wrong backend.
- The proxy listens only on `127.0.0.1:8317`; the configuration template disables remote management, application file logging, and usage statistics. Request-error logs are still retained.

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

This is an unofficial workaround, without official Anthropic or OpenAI support as a Claude Code integration. Upstream policies, OAuth behavior, and model entitlements can change. Keep native `claude` / `codex` available as fallbacks for important work.

## macOS installation layout

| Location | Purpose |
|---|---|
| `/opt/homebrew/bin/cliproxyapi` | Homebrew CLIProxyAPI binary |
| `/opt/homebrew/etc/cliproxyapi.conf` | Active config; permissions `0600` |
| `~/.cli-proxy-api/` | Proxy-managed Codex OAuth; directory `0700`, credential files `0600` |
| Keychain service `cliproxyapi-claudex` | Random key for the local client to connect to the proxy |
| `~/.local/bin/claudex` | Symlink to this repository's launcher |

Derive the active config from `config/cliproxyapi.conf.example`. The repository template contains only placeholders, never real keys.

`logging-to-file: false` disables application file logging. The template still retains up to 10 request-error logs, which may include prompt and request bodies. Treat those logs as sensitive; see the [upstream logging configuration](https://github.com/router-for-me/CLIProxyAPI/blob/main/config.example.yaml).

## Daily usage

```bash
claudex                                  # Sol; max; bypass enabled by default
claudex --luna                           # Luna; max; bypass enabled by default
claudex --terra                          # Terra, if available to your account
claudex --luna -p "Reply OK"              # Headless

CLAUDEX_SKIP_PERMISSIONS=0 claudex         # Restore permission prompts
CLAUDEX_EFFORT=high claudex                # Lower effort for this session
CLAUDEX_CONCURRENCY=2 claudex              # Change tool concurrency for this session
CLAUDEX_MODEL=gpt-5.6-luna claudex         # Select a model through the environment
CLAUDEX_MAX_CONTEXT_TOKENS=500000 claudex  # Lower the context ceiling for this session
```

`claudex` passes other flags through to Claude Code. Permission bypass lets Claude Code run tools or edit files without individual confirmations; use it only with repositories and prompts you trust. To keep permission prompts enabled by default, set `CLAUDEX_SKIP_PERMISSIONS=0` permanently.

The official Sol and Luna API model pages list reasoning effort from `none` through `max` and a 1.05M context window. Claude Code 2.1.232 did not recognize these model IDs, so the launcher explicitly sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1050000` to avoid the 200K fallback for unknown models. Model IDs follow Tibo's original approach without adding a `[1m]` suffix. The Claude Code → third-party proxy → subscription OAuth path is unofficial; actual context availability and quotas depend on CLIProxyAPI, Claude Code, and account entitlements.

## Service management, sign-in, and tests

```bash
brew services info cliproxyapi
brew services restart cliproxyapi

cliproxyapi -codex-login          # Browser OAuth
cliproxyapi -codex-device-login   # Headless / device flow

./scripts/debug-cliproxy.sh
./scripts/test-cliproxy-api.sh --sol
./scripts/test-cliproxy-api.sh --luna
```

If `claudex` reports that the proxy is unreachable, check the service status and restart it. If it reports an unavailable model, sign in again. The debug script checks proxy connectivity and Sol / Luna availability; it does not print the full model inventory. Diagnostics report credential presence without printing secrets.

Upgrade with:

```bash
brew update
brew upgrade cliproxyapi
brew services restart cliproxyapi
./scripts/test-cliproxy-api.sh --luna
```

## Direct backends

### MiMo

```bash
./scripts/setup-mimo-keychain.sh
./scripts/test-mimo-api.sh
mimo-claude
```

Defaults to `mimo-v2.6-pro[1m]` for the main session, fast tier, and subagents. Claude Code client effort defaults to `max`. The launcher exports `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576`, sets an auto-compact window of `786432`, and enables `--dangerously-skip-permissions`; see [context window settings](#context-window-settings) for how Claude Code resolves the effective window. MiMo currently treats non-`none` effort levels alike: `max` maps to server-side `high` / thinking enabled. It is the highest client setting, without a separate server-side max compute tier.

For intermittent silent SSE streams, 5xx errors, or bursts of tool calls, the launcher defaults to:

- A 10-minute request timeout.
- A 90-second timeout for the first byte or an idle stream, after which the attempt is aborted.
- A maximum of 3 retries, avoiding ten attempts on a failing request.
- Non-streaming fallback when streaming fails.
- Tool concurrency of 3 to limit simultaneous calls while permission bypass is enabled.

Override settings for a session:

```bash
MIMO_MODEL='<model>' mimo-claude
MIMO_EFFORT_LEVEL=high mimo-claude
MIMO_AUTO_COMPACT_WINDOW=524288 mimo-claude
MIMO_MAX_RETRIES=1 mimo-claude
MIMO_TOOL_CONCURRENCY=1 mimo-claude
```

Restore permission prompts for a session:

```bash
MIMO_SKIP_PERMISSIONS=0 mimo-claude
```

### DeepSeek

```bash
./scripts/setup-deepseek-keychain.sh
./scripts/test-deepseek-api.sh
deepseek-claude
```

Defaults to `deepseek-v4-flash[1m]` with `max` effort; subagents / fast tier use `deepseek-v4-flash`. To use Pro:

```bash
DEEPSEEK_MODEL='deepseek-v4-pro[1m]' deepseek-claude
```

The launcher enables `--dangerously-skip-permissions` by default. Restore permission prompts for a session:

```bash
DEEPSEEK_SKIP_PERMISSIONS=0 deepseek-claude
```

### GLM / Z.AI

```bash
./scripts/setup-glm-keychain.sh
./scripts/test-glm-api.sh
glm-claude
```

The main model and subagents default to `glm-5.3[1m]`; the fast model is `glm-5.3-flash[1m]`. Effort is explicitly set to `max`, with context and auto-compact windows of 1M. Override with `GLM_MODEL`, `GLM_FAST_MODEL`, `GLM_SUBAGENT_MODEL`, or `GLM_EFFORT_LEVEL`; for example, `GLM_MODEL='glm-5.3-flash[1m]' glm-claude`.

Set effort through the backend-specific environment variable, for example `GLM_EFFORT_LEVEL=high glm-claude`. The launchers also export `CLAUDE_CODE_EFFORT_LEVEL`, which takes precedence over `--effort`; a CLI flag alone does not override it. See [Claude Code's configuration precedence](https://code.claude.com/docs/en/env-vars#precedence).

According to the [official Z.AI settings](https://docs.z.ai/devpack/latest-model), both 5.3 and 5.3 Flash support 1M context, and `xhigh` / `max` / `ultra` map to the highest `max` level. For HTTP 429 responses, also inspect the error code: `1113` means insufficient balance or no resource package. Avoid treating it as a transient rate limit and retrying repeatedly; check your Coding Plan, quota, and payment status in the Console.

### Context window settings

For an unknown model ID containing `[1m]`, recent Claude Code versions assume a 1M window and ignore `CLAUDE_CODE_MAX_CONTEXT_TOKENS` on its own. Changing `MIMO_MAX_CONTEXT_TOKENS` or `GLM_MAX_CONTEXT_TOKENS` alone therefore does not change the effective window for their default models. The [official context configuration guide](https://code.claude.com/docs/en/model-config#correct-the-window-for-a-gateway-or-custom-model-id) explains how `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` makes an explicit window override apply. The auto-compact window is a separate setting.

## Call another backend from a session

```bash
ask-backend --list
ask-backend deepseek "review this function"
ask-backend mimo "explain this error in one sentence"
ask-backend glm "compare these two approaches"
```

`ask-backend` runs headless and defaults to `--permission-mode default`, without adding permission bypass. Existing permission rules still apply, so this is not a read-only sandbox. Add `--permission-mode acceptEdits` to allow file edits automatically, or `--dangerously-skip-permissions` to bypass checks, with the same risks as `claudex`. Prompts and code are sent from your machine to the selected third-party backend.

The direct launchers replace Anthropic endpoint and model settings but currently retain inherited cloud-provider selectors. If you have `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, or `CLAUDE_CODE_USE_FOUNDRY` set, unset them before using MiMo, DeepSeek, or GLM to avoid selecting the parent's cloud provider.

## Security boundaries

- Keep CLIProxyAPI on loopback. Do not change its host to `0.0.0.0` or enable remote management.
- Never commit `/opt/homebrew/etc/cliproxyapi.conf`, `~/.cli-proxy-api/`, Keychain exports, `.env`, or token files.
- The local client key protects access to the local proxy; upstream access comes from the Codex OAuth file.
- Permission bypass is an optional convenience, not a proxy requirement. Disable it for untrusted repositories.
- Using OAuth / subscriptions through third-party tools may carry account or terms-of-service risks. If you encounter policy or entitlement errors, use an official client or API instead of attempting to bypass them.

## References

- [Tibo's original three steps and alias](https://x.com/thsottiaux/status/2076119366647894371)
- [Theo's CLIProxyAPI / Claude Code explanation cited by Tibo](https://x.com/theo/status/2076114415368482854)
- [CLIProxyAPI repository](https://github.com/router-for-me/CLIProxyAPI)
- [CLIProxyAPI guides](https://help.router-for.me/)
- [OpenAI GPT-5.6 Sol model page](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [OpenAI GPT-5.6 Luna model page](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
