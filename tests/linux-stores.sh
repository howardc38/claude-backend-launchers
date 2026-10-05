#!/usr/bin/env bash
# Real Linux pass/GPG + Secret Service round trips using disposable test keys.
# Run in the disposable Debian container described in docs/linux.md.
set -euo pipefail
repo_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d)"
export GNUPGHOME="$fixture_dir/gpg"
export PASSWORD_STORE_DIR="$fixture_dir/password-store"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key 'Launcher integration <launcher@example.invalid>' default default never >/dev/null 2>&1
fingerprint="$(gpg --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')"
pass init "$fingerprint" >/dev/null
printf 'test-only-pass-credential\n' | "$repo_dir/scripts/setup-credential.sh" mimo pass
export CLAUDE_BACKEND_CREDENTIAL_STORE=pass
source "$repo_dir/scripts/lib/credentials.sh"
cb_load_auth mimo
[[ "$CB_TOKEN" == test-only-pass-credential && "$CB_SOURCE" == pass ]]
[[ -f "$PASSWORD_STORE_DIR/claude-backends/mimo.gpg" ]]
printf 'PASS real pass/GPG encrypted round trip\n'

export XDG_RUNTIME_DIR="$fixture_dir/runtime"
export XDG_DATA_HOME="$fixture_dir/data"
export XDG_CONFIG_HOME="$fixture_dir/config"
mkdir -m 700 "$XDG_RUNTIME_DIR"
dbus-run-session -- bash -eu -c '
  printf "test-keyring-password" | gnome-keyring-daemon --unlock --components=secrets >/dev/null
  printf "test-only-secret-service-credential\n" | "$1/scripts/setup-credential.sh" deepseek secret-service
  export CLAUDE_BACKEND_CREDENTIAL_STORE=secret-service
  source "$1/scripts/lib/credentials.sh"
  cb_load_auth deepseek
  [[ "$CB_TOKEN" == test-only-secret-service-credential && "$CB_SOURCE" == secret-service ]]
  "$1/scripts/debug-auth-source.sh" deepseek | grep -q "value=hidden"
  printf "PASS real Secret Service round trip\n"
' test "$repo_dir"
gpgconf --kill gpg-agent
