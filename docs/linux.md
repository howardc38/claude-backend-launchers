# Linux / WSL setup

Linux desktop、headless server 同 WSL 都支援。需要 Bash 3.2+、curl，同已安裝嘅 Claude Code；smoke-test JSON 查看建議安裝 jq。macOS 繼續使用原有 Keychain entries。

## 安裝命令

Ubuntu / Debian：

```bash
sudo apt-get update
sudo apt-get install git bash curl jq
git clone https://github.com/howardc38/claude-backend-launchers.git
cd claude-backend-launchers
./scripts/install-launchers.sh
export PATH="$HOME/.local/bin:$PATH"
```

Claude Code 按 [官方安裝說明](https://code.claude.com/docs/en/setup) 安裝。`install-launchers.sh` 建立 symlink，所以保留呢個 checkout；`git pull` 後命令會直接使用新版本。它會拒絕覆蓋已有普通檔案。

## Linux desktop：Secret Service

GNOME Keyring / KDE Wallet 提供 Secret Service，需要 desktop D-Bus session 同已解鎖 keyring。Ubuntu / Debian 安裝 client：

```bash
sudo apt-get install libsecret-tools
./scripts/setup-credential.sh mimo secret-service
./scripts/setup-credential.sh deepseek secret-service
./scripts/setup-credential.sh glm secret-service
```

每次會隱藏輸入 key，並直接存入 keyring。日常照用：

```bash
mimo-claude
deepseek-claude
glm-claude
```

## Headless Linux / WSL：pass + GPG

```bash
sudo apt-get install pass gnupg
gpg --full-generate-key
gpg --list-secret-keys --keyid-format LONG
pass init '你的 GPG key ID 或 fingerprint'
./scripts/setup-credential.sh mimo pass
./scripts/setup-credential.sh deepseek pass
./scripts/setup-credential.sh glm pass
```

`pass` 以 GPG 加密存檔，預設 entries 係 `claude-backends/mimo`、`claude-backends/deepseek`、`claude-backends/glm` 同 `claude-backends/claudex`。GPG 可能需要解鎖；在互動 SSH session 可設定 `export GPG_TTY="$(tty)"`。CI / unattended job 建議直接由 secret manager 注入專屬環境變數，避免等候 unlock prompt。

如果一部機有兩套 stores，可明確選擇；呢個選項本身唔含 secret，可放 shell 設定：

```bash
export CLAUDE_BACKEND_CREDENTIAL_STORE=pass
mimo-claude
```

## 臨時環境變數 / CI

```bash
read -r -s -p 'MiMo key: ' MIMO_ANTHROPIC_AUTH_TOKEN
printf '\n'
export MIMO_ANTHROPIC_AUTH_TOKEN
mimo-claude
unset MIMO_ANTHROPIC_AUTH_TOKEN
```

其他專屬變數係 `DEEPSEEK_ANTHROPIC_AUTH_TOKEN`、`GLM_ANTHROPIC_AUTH_TOKEN` 同 `CLAUDEX_PROXY_KEY`。CI secret manager 可直接注入呢啲變數。

讀取次序：backend 專屬 env → OS store（macOS Keychain；Linux desktop Secret Service）→ pass → standalone legacy Anthropic env。`CLAUDE_BACKEND_CREDENTIAL_STORE=env` 跳過 stores；`keychain`、`secret-service`、`pass` 明確選一個 store。backend 專屬 env 始終優先。`claudex` 只接受自己嘅 client key，不讀 generic Anthropic key。

可自訂 `MIMO_PASS_ENTRY`（或 `DEEPSEEK_` / `GLM_` / `CLAUDEX_`）、`CLAUDE_BACKEND_CREDENTIAL_ACCOUNT`。原有 `*_KEYCHAIN_SERVICE` 變數現在同時決定 Secret Service 嘅 service attribute。舊 `setup-*-keychain.sh` 仍可用，會 delegate 去跨平台 setup。

## CLIProxyAPI / claudex

`claudex` 仍需要 Linux 上運行 CLIProxyAPI，同一個 Codex account 要在 Linux 主機重新做 OAuth。依 [CLIProxyAPI Linux quick start](https://help.router-for.me/introduction/quick-start) 安裝 `cli-proxy-api` binary（Arch 可用 AUR `cli-proxy-api-bin`）。

```bash
umask 077
mkdir -p "$HOME/.cli-proxy-api"
cp config/cliproxyapi.conf.example "$HOME/.cli-proxy-api/config.yaml"
chmod 700 "$HOME/.cli-proxy-api"
chmod 600 "$HOME/.cli-proxy-api/config.yaml"
```

以 editor 將 config 嘅 `REPLACE_WITH_LOCAL_KEY` 換成自己產生嘅本地 client key；此 config 留在 repo 外。將同一個 key 存入 store：

```bash
./scripts/setup-credential.sh claudex pass
cli-proxy-api --config "$HOME/.cli-proxy-api/config.yaml" --codex-login --no-browser
cli-proxy-api --config "$HOME/.cli-proxy-api/config.yaml"
```

在另一個 terminal 執行：

```bash
claudex
claudex --luna
./scripts/debug-cliproxy.sh
```

以上前景啟動方便初次驗證；需要常駐時依套件 systemd 設定啟動。OAuth 使用 localhost callback（預設 1455）；遠端 SSH 需要 callback forwarding 或 binary 提供嘅 device login。Binary flags 以 `cli-proxy-api --help` 為準。

## 診斷與安全

```bash
./scripts/debug-mimo-auth-source.sh
./scripts/debug-deepseek-auth-source.sh
./scripts/debug-glm-auth-source.sh
./scripts/test-mimo-api.sh
```

診斷只顯示來源、service 同 `value=hidden`，唔印任何 key 字元。Linux 初次要輸入自己嘅 key，Mac Keychain 唔會跟 Git clone 自動搬過去。每台主機可使用獨立 key，方便撤銷。

MiMo / DeepSeek / claudex 依你選擇保留預設 bypass；`ask-backend` 會明確選擇 default permission mode，只有手動傳 bypass 才啟用。Project hooks 照樣載入。

## 測試

```bash
python3 -m unittest discover -s tests -v
```

Offline suite 測試 precedence、missing key、setup stdin、secret-free diagnostics、所有 launcher 同 symlink。真實 Linux store integration 可用 disposable container（只用 fake test keys，唔掛載主機 Keychain）：

```bash
docker run --rm -v "$PWD:/work:ro" -w /work python:3.12-slim bash -c \
  'apt-get update -qq && apt-get install -y -qq --no-install-recommends pass gnupg dbus gnome-keyring libsecret-tools && python3 -B -m unittest discover -s tests -v && bash tests/linux-stores.sh'
```

來源：[Secret Service client manpage](https://dyn.manpages.debian.org/trixie/libsecret-tools/secret-tool.1.en.html)、[pass 官方文件](https://www.passwordstore.org/)。
