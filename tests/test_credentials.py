"""Offline credential/launcher regression tests; no real keys or network."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "scripts/lib/credentials.sh"


class Credentials(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith(("ANTHROPIC_", "MIMO_", "DEEPSEEK_", "GLM_", "CLAUDEX_", "CLAUDE_BACKEND_")):
                self.env.pop(key)
        self.env.update(PATH=str(self.bin) + ":" + os.environ["PATH"],
                        DBUS_SESSION_BUS_ADDRESS="test-bus")
        self.fake("uname", 'printf "Linux\\n"')
        self.fake("security", "exit 1")
        self.fake("secret-tool", "exit 1")
        self.fake("pass", "exit 1")
        self.fake("claude", "exec python3 -c 'import os,json,sys; print(json.dumps({\"token\":os.environ.get(\"ANTHROPIC_AUTH_TOKEN\"),\"model\":os.environ.get(\"ANTHROPIC_MODEL\"),\"args\":sys.argv[1:]}))' \"$@\"")
        self.fake("curl", 'printf \'{"data":[{"id":"gpt-5.6-sol"},{"id":"gpt-5.6-luna"}],"content":[{"type":"text","text":"OK"}]}\'')

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def run_script(self, script, *args, input=None):
        return subprocess.run(["bash", str(ROOT / script), *args], env=self.env,
                              input=input, text=True, capture_output=True)

    def resolve(self, backend="mimo"):
        return subprocess.run(["bash", "-euc",
                               'source "$1"; cb_load_auth "$2"; printf "%s:%s" "$CB_SOURCE" "$CB_TOKEN"',
                               "test", str(LIB), backend], env=self.env,
                              text=True, capture_output=True)

    def test_env_wins_over_stores(self):
        self.env["MIMO_ANTHROPIC_AUTH_TOKEN"] = "test-explicit"
        self.fake("secret-tool", 'printf "test-store"')
        self.assertEqual(self.resolve().stdout, "MIMO_ANTHROPIC_AUTH_TOKEN:test-explicit")

    def test_linux_secret_service_attributes(self):
        self.fake("secret-tool", '[[ "$*" == "lookup service mimo-claude-code account test-account" ]]; printf test-secret')
        self.env["CLAUDE_BACKEND_CREDENTIAL_ACCOUNT"] = "test-account"
        self.assertEqual(self.resolve().stdout, "secret-service:test-secret")

    def test_pass_fallback_first_line(self):
        self.fake("pass", '[[ "$*" == "show claude-backends/mimo" ]]; printf "test-pass\\nnotes\\n"')
        self.assertEqual(self.resolve().stdout, "pass:test-pass")

    def test_headless_skips_desktop_keyring(self):
        self.env.pop("DBUS_SESSION_BUS_ADDRESS", None)
        self.fake("secret-tool", 'printf wrong-desktop-key')
        self.fake("pass", 'printf test-headless-key')
        self.assertEqual(self.resolve().stdout, "pass:test-headless-key")

    def test_mac_keychain_uses_existing_service(self):
        self.fake("uname", 'printf "Darwin\\n"')
        self.fake("security", '[[ "$*" == "find-generic-password -a test-account -s mimo-claude-code -w" ]]; printf test-mac')
        self.env["CLAUDE_BACKEND_CREDENTIAL_ACCOUNT"] = "test-account"
        self.assertEqual(self.resolve().stdout, "keychain:test-mac")

    def test_explicit_store_does_not_read_other_stores(self):
        self.env["CLAUDE_BACKEND_CREDENTIAL_STORE"] = "pass"
        self.fake("secret-tool", 'printf wrong-secret')
        self.assertNotEqual(self.resolve().returncode, 0)

    def test_custom_service_and_pass_entry(self):
        self.env.update(CLAUDE_BACKEND_CREDENTIAL_STORE="pass", MIMO_PASS_ENTRY="custom/mimo")
        self.fake("pass", '[[ "$*" == "show custom/mimo" ]]; printf custom-token')
        self.assertEqual(self.resolve().stdout, "pass:custom-token")
        self.env.update(CLAUDE_BACKEND_CREDENTIAL_STORE="secret-service", MIMO_KEYCHAIN_SERVICE="custom-service", CLAUDE_BACKEND_CREDENTIAL_ACCOUNT="test-account")
        self.fake("secret-tool", '[[ "$*" == "lookup service custom-service account test-account" ]]; printf custom-token')
        self.assertEqual(self.resolve().stdout, "secret-service:custom-token")

    def test_no_key_fails_without_secret_output(self):
        result = self.resolve()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("setup-credential.sh mimo", result.stderr)

    def test_invalid_store_rejected(self):
        self.env["CLAUDE_BACKEND_CREDENTIAL_STORE"] = "plaintext"
        self.assertEqual(self.resolve().returncode, 2)

    def test_claudex_does_not_reuse_anthropic_key(self):
        self.env["ANTHROPIC_AUTH_TOKEN"] = "wrong-provider"
        self.assertNotEqual(self.resolve("claudex").returncode, 0)

    def test_generic_env_still_works_for_standalone(self):
        self.env["ANTHROPIC_AUTH_TOKEN"] = "test-generic"
        self.assertEqual(self.resolve().stdout, "ANTHROPIC_AUTH_TOKEN:test-generic")

    def test_all_launchers_use_linux_store(self):
        self.fake("pass", 'printf test-pass-key')
        self.env["CLAUDE_BACKEND_CREDENTIAL_STORE"] = "pass"
        for command in ("mimo-claude", "deepseek-claude", "glm-claude", "claudex"):
            with self.subTest(command=command):
                result = self.run_script(command)
                self.assertEqual(result.returncode, 0, result.stderr)
                value = json.loads(result.stdout)
                self.assertEqual(value["token"], "test-pass-key")
                self.assertTrue(value["model"])
                if command != "glm-claude":
                    self.assertIn("--dangerously-skip-permissions", value["args"])

    def test_diagnostics_never_show_key(self):
        self.env["MIMO_ANTHROPIC_AUTH_TOKEN"] = "test-secret-do-not-show"
        result = self.run_script("scripts/debug-mimo-auth-source.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("test-secret-do-not-show", result.stdout + result.stderr)
        self.assertIn("value=hidden", result.stdout)

    def test_smoke_tests_share_credentials(self):
        self.fake("pass", 'printf test-pass-key')
        self.env["CLAUDE_BACKEND_CREDENTIAL_STORE"] = "pass"
        for backend in ("mimo", "deepseek", "glm", "cliproxy"):
            result = self.run_script(f"scripts/test-{backend}-api.sh")
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_setup_pass_receives_key_via_stdin_only(self):
        saved = Path(self.temp.name) / "saved"
        self.fake("pass", f'[[ "$*" == "insert --multiline --force claude-backends/mimo" ]]; cat > "{saved}"')
        result = self.run_script("scripts/setup-credential.sh", "mimo", "pass", input="test-input-key\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(saved.read_text(), "test-input-key\n")
        self.assertNotIn("test-input-key", result.stdout + result.stderr)

    def test_setup_secret_service_does_not_store_newline(self):
        saved = Path(self.temp.name) / "saved"
        self.env["CLAUDE_BACKEND_CREDENTIAL_ACCOUNT"] = "test-account"
        self.fake("secret-tool", f'[[ "$*" == "store --label=Claude backend: mimo service mimo-claude-code account test-account" ]]; cat > "{saved}"')
        result = self.run_script("scripts/setup-credential.sh", "mimo", "secret-service", input="test-input-key\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(saved.read_text(), "test-input-key")

    def test_failed_setup_reports_failure(self):
        self.fake("secret-tool", "exit 1")
        result = self.run_script("scripts/setup-credential.sh", "mimo", "secret-service", input="test-input-key\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Stored", result.stdout)

    def test_legacy_setup_alias_works_on_linux(self):
        self.fake("pass", 'cat >/dev/null')
        result = self.run_script("scripts/setup-mimo-keychain.sh", "pass", input="test-input-key\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Stored mimo credential in pass", result.stdout)

    def test_ask_backend_keeps_readonly_default(self):
        self.env.update(MIMO_ANTHROPIC_AUTH_TOKEN="correct-provider", ANTHROPIC_AUTH_TOKEN="parent-provider")
        result = self.run_script("ask-backend", "mimo", "test")
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["token"], "correct-provider")
        self.assertIn("default", value["args"])
        self.assertNotIn("--dangerously-skip-permissions", value["args"])
        result = self.run_script("ask-backend", "mimo", "test", "--dangerously-skip-permissions")
        value = json.loads(result.stdout)
        self.assertIn("--dangerously-skip-permissions", value["args"])
        self.assertNotIn("--permission-mode", value["args"])
        self.env.pop("MIMO_ANTHROPIC_AUTH_TOKEN")
        self.assertNotEqual(self.run_script("ask-backend", "mimo", "test").returncode, 0)

    def test_install_and_symlink_launch(self):
        self.env["CLAUDE_BACKEND_BIN_DIR"] = str(Path(self.temp.name) / "installed")
        self.assertEqual(self.run_script("scripts/install-launchers.sh").returncode, 0)
        installed = Path(self.env["CLAUDE_BACKEND_BIN_DIR"])
        self.env["MIMO_ANTHROPIC_AUTH_TOKEN"] = "test-env"
        result = subprocess.run([str(installed / "mimo-claude")], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["token"], "test-env")
        (installed / "claudex").unlink()
        (installed / "claudex").write_text("user file")
        self.assertNotEqual(self.run_script("scripts/install-launchers.sh").returncode, 0)
        self.assertEqual((installed / "claudex").read_text(), "user file")


if __name__ == "__main__":
    unittest.main()
