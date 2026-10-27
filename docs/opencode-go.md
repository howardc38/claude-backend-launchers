# OpenCode Go with Claude Code

`go-claude` keeps Claude Code's interface and tools, routes Chat, Responses, and Google formats through an isolated CLIProxyAPI, and forwards Messages directly to Go. It supports the 20 requested models from GLM, Kimi, DeepSeek, MiMo, MiniMax, Qwen, and Claude Haiku, plus MiniMax M3.1 Flash Free, Grok 4.7, GPT 6 Luna, and Gemini 4 Argon Contributor. The stable DeepSeek alias is also accepted. Other Responses models and Muse Spark are not configured.

## Setup

Requires Claude Code, Bash 3.2+, Python 3.9+, and CLIProxyAPI 7.2.130 or later. The binary can be named `cliproxyapi` or `cli-proxy-api`; override its location with `OPENCODE_GO_PROXY_BIN`. On macOS, `brew install cliproxyapi` installs the proxy. Linux packages and binaries are documented in the [CLIProxyAPI quick start](https://help.router-for.me/introduction/quick-start).

Subscribe to Go in the [OpenCode Console](https://opencode.ai/console), obtain its API key, and store it locally:

```bash
./scripts/install-launchers.sh
./scripts/setup-credential.sh go
go-claude --list-models
go-claude
```

The default model is `glm-5.3`. Credentials use the existing cross-platform stores: service `opencode-go-claude`, pass entry `claude-backends/go`, or dedicated environment variable `OPENCODE_GO_API_KEY`. Generic Anthropic credentials are never used for Go. The [Linux guide](linux.md) covers Secret Service and pass setup.

## Switch models and effort

```bash
go-claude --model kimi-k3
go-claude --model deepseek-v4-pro
go-claude --model mimo-v2.6-pro
go-claude --model minimax-m3
go-claude --model minimax-m3.1-flash-free --effort max
go-claude --model qwen3.8-max
go-claude --model claude-haiku-5-5
go-claude --model grok-4.7
go-claude --model gpt-6-luna
# Requires the workspace's explicit paid-training consent:
go-claude --model gemini-4-argon-contributor
go-claude --model glm-5.3 --effort high

# Default for future launches; put this non-secret setting in your shell config.
export OPENCODE_GO_MODEL=qwen3.8-max
go-claude

ask-backend go 'Compare these implementations' --model kimi-k3
```

Each new launch updates main, Haiku/fast, and subagent models together, and uses the selected model's context and output limits. Native model IDs are recommended; `opencode-go/` prefixes and `[1m]` selectors are normalized to native IDs.

The default client effort is `max`, meaning the highest setting that the selected Go model actually supports. The gateway normalizes each request: Qwen 3.8 and Grok 4.7 get `xhigh`, Gemini gets `high`, and models without graded effort get thinking enabled without an unsupported effort field. Other explicit effort values must appear in the table below; unsupported values fail before loading credentials or starting the proxy. `none` remains unsupported by the shared Claude launcher.

Go exposes Gemini as `gemini-4-argon-contributor`. The shorter `gemini-4-argon` launcher alias resolves to that exact Contributor ID and displays it as the active model. Contributor requests may be used for training and do not have zero data retention. OpenCode rejects them unless **Allow paid endpoints that train on request data** is enabled under workspace Privacy settings. This is independent of permission bypass in Claude Code. The launcher does not change that consent or fall back to the separately billed non-Contributor Console endpoint.

Claude's `/model` picker uses the gateway's model discovery endpoint. Effort is revalidated on every request, including `/effort` changes. `max` keeps meaning the highest setting across model switches. A session-level model switch does not rerun the launcher or reset its pinned subagent, context, or output environment; relaunch with `--model` when moving between models with different limits.

## Verified model controls

Catalog checked on **2026-10-14** against [Go endpoints](https://opencode.ai/v2/docs/console/go/#endpoints) and the OpenCode [models.dev catalog](https://models.dev/api.json). The runtime catalog is [opencode-go-models.json](../config/opencode-go-models.json).

| Model | API | Graded effort | Default highest | Context |
|---|---|---|---|---:|
| `glm-5.3-flash` | Chat | low, high, max | max | 1,000,000 |
| `glm-5.3` | Chat | low, high, max | max | 1,000,000 |
| `glm-5.2` | Chat | high, max | max | 1,000,000 |
| `kimi-k3` | Chat | max on Go | max | 1,048,576 |
| `kimi-k2.7-code` | Chat | Always thinks | Thinking on | 262,144 |
| `kimi-k2.6` | Chat | Thinking switch | Thinking on, keep history | 262,144 |
| `deepseek-v4.1-flash` | Chat | low, high, max | max | 1,000,000 |
| `deepseek-v4-pro` | Chat | high, max | max | 1,000,000 |
| `deepseek-v4-flash` | Chat | low, high, max | max | 1,000,000 |
| `deepseek-v4-flash-vision-exp` | Chat | low, high, max | max | 1,000,000 |
| `mimo-v2.6-flash` | Chat | Thinking switch | Thinking on | 1,048,576 |
| `mimo-v2.6-pro` | Chat | Thinking switch | Thinking on | 1,048,576 |
| `mimo-v2.5` | Chat | Thinking switch | Thinking on | 1,000,000 |
| `mimo-v2.5-pro` | Chat | Thinking switch | Thinking on | 1,048,576 |
| `minimax-m3` | Messages | Thinking switch | adaptive thinking | 1,000,000 |
| `minimax-m3.1-flash-free` | Chat | low, medium, high, xhigh, max | max | 1,000,000 |
| `minimax-m2.7` | Messages | Always thinks | Native thinking | 204,800 |
| `qwen3.8-max` | Messages | low, medium, xhigh | xhigh | 1,000,000 |
| `qwen3.8-flash` | Messages | low, medium, xhigh | xhigh | 1,000,000 |
| `qwen3.7-plus` | Messages | Thinking budget | Maximum allowed budget | 1,000,000 |
| `claude-haiku-5-5` | Messages | low, medium, high, xhigh, max | max | 1,000,000 |
| `grok-4.7` | Responses | low, medium, high, xhigh | xhigh | 500,000 |
| `gpt-6-luna` | Responses | low, medium, high, xhigh, max | max | 1,050,000 |
| `gemini-4-argon-contributor` | Google | low, medium, high | high | 1,048,576 |

`deepseek-flash` is an additional stable V4.1 Flash alias. Availability, capacity, and accepted settings can change; account responses remain authoritative. Kimi K3's Go catalog advertises only `max`, even though some direct Moonshot deployments support more levels.

Live verification found that Go's GLM-5.3-Flash route rejects the `thinking` field. Its requests send `reasoning_effort` alone, with default `max`. Some DeepSeek routes require Global regions in the workspace's Privacy settings; a restricted region setting can block them before inference.

Qwen 3.7 Plus has a maximum thinking budget of 262,144, rather than discrete effort levels. Following OpenCode's [Alibaba Messages adapter](https://github.com/anomalyco/opencode/blob/dev/packages/ai/src/protocols/alibaba-messages.ts), each request fits this budget below its `max_tokens`. The Go output limit is 65,536, so the default effective budget is 65,535; a smaller request cap reduces it further. This is not a separate server-side `max` tier.

MiniMax M3 needs `thinking.type=adaptive` on Messages. M2.7 always thinks and receives no thinking or effort override. See OpenCode's [MiniMax adapter](https://github.com/anomalyco/opencode/blob/dev/packages/ai/src/providers/minimax.ts). Kimi K2.6 keeps reasoning history; K2.7 Code always reasons. See the [Moonshot adapter](https://github.com/anomalyco/opencode/blob/dev/packages/ai/src/providers/moonshot.ts).

MiniMax M3.1 Flash Free uses Go's `/openai/v1/chat/completions` namespace, with `reasoning_effort=max` by default. Its catalog output limit is 512,000 tokens; the launcher reserves 250,000 output tokens and uses a 750,000-token auto-compact window with its 1M context. Requests use the OpenAI effort field; the proxy removes sampling controls (`temperature`, `top_p`) and the separate `thinking` field. OpenCode currently offers it free for a limited time with no model training and zero data retention. See [OpenCode free models](https://opencode.ai/v2/docs/console/models#free-models). Claude Haiku 5.5 uses Go's canonical `/anthropic/v1/messages` endpoint and defaults to `max` effort.

## Overrides and process lifetime

Go settings use `OPENCODE_GO_`: `MODEL`, `EFFORT_LEVEL`, `MAX_CONTEXT_TOKENS`, `AUTO_COMPACT_WINDOW`, `MAX_OUTPUT_TOKENS`, `API_TIMEOUT_MS`, and `SKIP_PERMISSIONS`. Context/output overrides must not exceed the selected model's catalog limits. Output defaults to the smaller of the provider's output limit and 25% of context. Compaction defaults to 75% of context, or lower to reserve the chosen output budget. A custom compaction threshold plus the output budget must fit inside context. Permission bypass defaults to on: `go-claude` adds `--dangerously-skip-permissions`. Set `OPENCODE_GO_SKIP_PERMISSIONS=0` or pass `--permission-mode default` to restore checks for a launch. Explicit permission flags take priority. `ask-backend go` and live smoke checks explicitly use normal permission mode.

Each invocation binds two automatic loopback ports, generates a private local client key and a stable `x-opencode-session`, and supplies its own coding-agent user agent. The installed proxy converts Chat, Responses, and Google formats; direct Messages forwarding preserves native signatures, tools, and caching headers. Responses go through an authenticated local relay to retain the actual coding-agent identity after native Codex header handling. Google goes through the same gateway to rewrite CLIProxyAPI's `v1beta` path to Go's documented `v1` path. This works with 7.2.130, which cannot dynamically copy request headers through custom provider headers.

The proxy uses an isolated auth directory and a mode-0600 config inside a mode-0700 temporary directory. Upstream credentials stay out of argv and are removed from the Claude child's environment. The local gateway key replaces them. The supervisor stops its proxy and removes temporary config/log files when Claude exits, including ordinary interruption. CLIProxyAPI can write one failed-request log inside that private temporary directory; it is removed with the directory. Forced termination such as SIGKILL cannot run cleanup.

The existing `claudex` proxy/service is independent. `OPENCODE_GO_BASE_URL` changes Go's upstream root, normally `https://opencode.ai/inference/go`, without the final `/v1`. `ask-backend go` pins the canonical upstream just as it does for other backends.

## Tests and live checks

```bash
python3 -B -m unittest discover -s tests -v
./scripts/debug-auth-source.sh go
./scripts/test-api.sh go --model glm-5.3
./scripts/test-api.sh go --model qwen3.8-max --effort medium
./scripts/test-api.sh go --all
```

Offline tests use real CLIProxyAPI with a fake loopback Go server to check every catalog effort combination, highest-setting normalization, headers, streaming tools, reasoning replay, Messages signatures, limits, and process cleanup. Installed-Claude contracts also check its actual streamed requests. These tests do not establish account entitlement or live Go compatibility.

Live smoke checks use Claude Code's actual coding-agent request format, at highest effort by default. `--all` checks the 23 models that do not train on requests and stops at the first failure; it skips Contributor models and does not repeat the DeepSeek alias. Gemini can be checked explicitly with `--model gemini-4-argon-contributor` after training consent is enabled. Validate lower effort in an individual model check. A Go key and an active subscription are required for live verification.

On 2026-10-14, all 20 documented models passed live Claude Code checks across 40 distinct supported model/effort combinations. Global regions was required for DeepSeek V4.1 Flash, V4 Pro, and V4 Flash. This establishes current request compatibility for the tested account, rather than guaranteeing future availability or reasoning depth. The GLM-5.3-Flash thinking-field correction also passed the 14 Go regression tests against loopback fixtures.

The subsequent Grok 4.7 and GPT 6 Luna additions passed live Go checks across all nine supported model/effort combinations. The complete suite passed 61 tests, including native Responses and Google streaming tool calls. Gemini Contributor's live check is pending explicit workspace training consent; its Google `v1` route was confirmed to return the expected consent error while that setting is off.

On 2026-10-19, MiniMax M3.1 Flash Free passed live checks at all five effort levels, including the default `max`. Claude Haiku 5.5 was reverified at `max` through its canonical Anthropic namespace. Both also passed a real Claude Read-tool round trip with an unpredictable fixture value. The complete regression suite passed 62 tests, including the new MiniMax route's streaming tools and preserved reasoning history.

## Selected model release dates

These are the official public model/API announcement dates, rather than Go integration dates.

| Model | Release date | Source |
|---|---|---|
| Qwen3.8 Max | 2026-08-03 | [Alibaba Cloud announcement](https://www.alibabacloud.com/en/press-room/alibaba-unveils-qwen3-8-max) |
| Kimi K3 | 2026-07-16 | [Kimi release notes](https://www.kimi.com/code/docs/en/kimi-code/whats-new.html) |
| GLM-5.3 | 2026-08-14 | [Z.ai announcement](https://z.ai/blog/glm-5.3) |
| MiniMax M3 | 2026-06-01 | [MiniMax announcement](https://www.minimax.io/blog/minimax-m3) |
| MiMo-V2.6-Pro | 2026-09-22 | [MiMo announcement](https://mimo.mi.com/docs/zh-CN/news/latest/v2-6) |
| Claude Haiku 5.5 | 2026-10-07 | [Anthropic announcement](https://www.anthropic.com/claude-haiku-5-5) |
