# Linux / WSL setup

Supports Linux desktops, headless servers, and WSL. Requires Bash 3.2+, curl, and an installed Claude Code CLI; jq is useful for inspecting smoke-test JSON. macOS continues to use existing Keychain entries.

## Install the commands

Ubuntu / Debian:

```bash
sudo apt-get update
sudo apt-get install git bash curl jq
git clone https://github.com/howardc38/claude-backend-launchers.git
cd claude-backend-launchers
./scripts/install-launchers.sh
export PATH="$HOME/.local/bin:$PATH"
```

Install Claude Code using the [official instructions](https://code.claude.com/docs/en/setup). `install-launchers.sh` creates symlinks, so keep this checkout; commands use the updated scripts after `git pull`. The installer refuses to overwrite existing regular files.

## Linux desktop: Secret Service

GNOME Keyring / KDE Wallet provides Secret Service. It requires a desktop D-Bus session and an unlocked keyring. Install the client on Ubuntu / Debian:

```bash
sudo apt-get install libsecret-tools
./scripts/setup-credential.sh mimo secret-service
./scripts/setup-credential.sh deepseek secret-service
./scripts/setup-credential.sh glm secret-service
```

Each command reads the key with terminal echo disabled and saves it directly to the keyring. Then run:

```bash
mimo-claude
deepseek-claude
glm-claude
```

## Headless Linux / WSL: pass + GPG

```bash
sudo apt-get install pass gnupg
gpg --full-generate-key
gpg --list-secret-keys --keyid-format LONG
pass init 'YOUR_GPG_KEY_ID_OR_FINGERPRINT'
./scripts/setup-credential.sh mimo pass
./scripts/setup-credential.sh deepseek pass
./scripts/setup-credential.sh glm pass
```

`pass` encrypts credentials with GPG. Default entries are `claude-backends/mimo`, `claude-backends/deepseek`, `claude-backends/glm`, and `claude-backends/claudex`. GPG may require unlocking; in an interactive SSH session, set `export GPG_TTY="$(tty)"`. For CI or unattended jobs, inject dedicated environment variables through a secret manager to avoid waiting for an unlock prompt.

If both credential stores are installed, select one explicitly. This setting contains no secret and can go in your shell configuration:

```bash
export CLAUDE_BACKEND_CREDENTIAL_STORE=pass
mimo-claude
```

## Temporary environment variables / CI

```bash
read -r -s -p 'MiMo key: ' MIMO_ANTHROPIC_AUTH_TOKEN
printf '\n'
export MIMO_ANTHROPIC_AUTH_TOKEN
mimo-claude
unset MIMO_ANTHROPIC_AUTH_TOKEN
```

The other dedicated variables are `DEEPSEEK_ANTHROPIC_AUTH_TOKEN`, `GLM_ANTHROPIC_AUTH_TOKEN`, and `CLAUDEX_PROXY_KEY`. CI secret managers can inject these directly.

Lookup order: backend-specific environment variable → OS store (macOS Keychain or Linux desktop Secret Service) → `pass` → legacy standalone Anthropic environment variables. `CLAUDE_BACKEND_CREDENTIAL_STORE=env` skips stores; `keychain`, `secret-service`, and `pass` select a single store. Backend-specific environment variables always take priority. `claudex` only accepts its own client key and never reads generic Anthropic credentials.

Customize `MIMO_PASS_ENTRY` (or the corresponding `DEEPSEEK_`, `GLM_`, or `CLAUDEX_` variable) and `CLAUDE_BACKEND_CREDENTIAL_ACCOUNT` as needed. Existing `*_KEYCHAIN_SERVICE` variables also set the Secret Service `service` attribute. Legacy `setup-*-keychain.sh` scripts still work and delegate to the cross-platform setup script.

## CLIProxyAPI / claudex

`claudex` requires CLIProxyAPI running on Linux. Sign in with Codex OAuth again on the Linux host, even when using the same account. Install the `cli-proxy-api` binary using the [CLIProxyAPI Linux quick start](https://help.router-for.me/introduction/quick-start); Arch users can use the AUR package `cli-proxy-api-bin`.

```bash
umask 077
mkdir -p "$HOME/.cli-proxy-api"
cp config/cliproxyapi.conf.example "$HOME/.cli-proxy-api/config.yaml"
chmod 700 "$HOME/.cli-proxy-api"
chmod 600 "$HOME/.cli-proxy-api/config.yaml"
```

Use an editor to replace `REPLACE_WITH_LOCAL_KEY` in the config with a local client key you generate yourself. Keep this config outside the repository. Save the same key to your credential store:

```bash
./scripts/setup-credential.sh claudex pass
cli-proxy-api --config "$HOME/.cli-proxy-api/config.yaml" --codex-login --no-browser
cli-proxy-api --config "$HOME/.cli-proxy-api/config.yaml"
```

In another terminal, run:

```bash
claudex
claudex --luna
./scripts/debug-cliproxy.sh
```

Running the proxy in the foreground helps with initial verification. For a persistent service, use the package's systemd configuration. OAuth uses a localhost callback (port 1455 by default); remote SSH requires callback forwarding or device login if supported by your binary. Check `cli-proxy-api --help` for the flags available in your installed version.

## Diagnostics and security

```bash
./scripts/debug-mimo-auth-source.sh
./scripts/debug-deepseek-auth-source.sh
./scripts/debug-glm-auth-source.sh
./scripts/test-mimo-api.sh
```

Diagnostics only show the credential source, service, and `value=hidden`; they never print key characters. Configure your own key on Linux; macOS Keychain credentials do not transfer with a Git clone. Each host can use a separate key for easier revocation.

MiMo, DeepSeek, and `claudex` retain their default permission bypass unless you disable it. `ask-backend` explicitly selects Claude Code's default permission mode and only enables bypass when requested. Existing permission rules and project hooks still apply; default permission mode does not guarantee read-only execution.

## Tests

```bash
python3 -m unittest discover -s tests -v
```

The offline suite covers credential precedence, missing keys, setup through stdin, diagnostics without secrets, all launchers, and symlinks. Test real Linux credential stores in a disposable container using fake keys only; do not mount the host's Keychain:

```bash
docker run --rm -v "$PWD:/work:ro" -w /work python:3.12-slim bash -c \
  'apt-get update -qq && apt-get install -y -qq --no-install-recommends pass gnupg dbus gnome-keyring libsecret-tools && python3 -B -m unittest discover -s tests -v && bash tests/linux-stores.sh'
```

Sources: [Secret Service client manpage](https://dyn.manpages.debian.org/trixie/libsecret-tools/secret-tool.1.en.html), [pass documentation](https://www.passwordstore.org/).
