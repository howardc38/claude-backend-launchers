"""Offline credential/launcher regression tests; no real keys or network."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "scripts/lib/credentials.sh"
TEST_BASH = os.environ.get("CLAUDE_BACKEND_TEST_BASH", "bash")


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
        self.fake("claude", "exec python3 -c 'import os,json,sys; keys=[\"ANTHROPIC_MODEL\",\"ANTHROPIC_DEFAULT_HAIKU_MODEL\",\"CLAUDE_CODE_SUBAGENT_MODEL\",\"CLAUDE_CODE_EFFORT_LEVEL\",\"CLAUDE_CODE_MAX_CONTEXT_TOKENS\",\"CLAUDE_CODE_AUTO_COMPACT_WINDOW\",\"CLAUDE_CODE_DISABLE_1M_CONTEXT\",\"CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY\",\"CLAUDE_STREAM_IDLE_TIMEOUT_MS\",\"CLAUDE_CODE_USE_BEDROCK\",\"CLAUDE_CODE_USE_VERTEX\",\"CLAUDE_CODE_USE_FOUNDRY\",\"CLAUDE_CODE_USE_ANTHROPIC_AWS\",\"CLAUDE_CODE_USE_MANTLE\"]; print(json.dumps({\"token\":os.environ.get(\"ANTHROPIC_AUTH_TOKEN\"),\"model\":os.environ.get(\"ANTHROPIC_MODEL\"),\"env\":{k:os.environ.get(k) for k in keys},\"args\":sys.argv[1:]}))' \"$@\"")
        self.fake("curl", 'printf \'{"data":[{"id":"gpt-5.6-sol"},{"id":"gpt-5.6-luna"}],"content":[{"type":"text","text":"OK"}]}\\n200\'')

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def run_script(self, script, *args, input=None):
        return subprocess.run([TEST_BASH, str(ROOT / script), *args], env=self.env,
                              input=input, text=True, capture_output=True)

    def resolve(self, backend="mimo"):
        return subprocess.run([TEST_BASH, "-euc",
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
        result = self.run_script("scripts/debug-auth-source.sh", "mimo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("test-secret-do-not-show", result.stdout + result.stderr)
        self.assertIn("value=hidden", result.stdout)

    def test_glm_model_effort_and_nested_settings(self):
        self.env.update(GLM_ANTHROPIC_AUTH_TOKEN="test-glm", CLAUDE_CODE_SUBAGENT_MODEL="parent-model", CLAUDE_CODE_EFFORT_LEVEL="low", API_TIMEOUT_MS="1")
        self.fake("claude", "exec python3 -c 'import os,json,sys; print(json.dumps({\"model\":os.environ[\"ANTHROPIC_MODEL\"],\"fast\":os.environ[\"ANTHROPIC_SMALL_FAST_MODEL\"],\"haiku\":os.environ[\"ANTHROPIC_DEFAULT_HAIKU_MODEL\"],\"subagent\":os.environ[\"CLAUDE_CODE_SUBAGENT_MODEL\"],\"effort\":os.environ[\"CLAUDE_CODE_EFFORT_LEVEL\"],\"context\":os.environ[\"CLAUDE_CODE_MAX_CONTEXT_TOKENS\"],\"timeout\":os.environ[\"API_TIMEOUT_MS\"],\"args\":sys.argv[1:]}))' \"$@\"")
        result = self.run_script("glm-claude")
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["model"], "glm-5.3[1m]")
        self.assertEqual(value["fast"], "glm-5.3-flash[1m]")
        self.assertEqual(value["haiku"], value["fast"])
        self.assertEqual(value["subagent"], value["model"])
        self.assertEqual(value["effort"], "max")
        self.assertEqual(value["context"], "1000000")
        self.assertEqual(value["timeout"], "3000000")
        self.assertEqual(value["args"], ["--model", "glm-5.3[1m]", "--effort", "max"])
        result = self.run_script("glm-claude", "--effort", "high")
        value = json.loads(result.stdout)
        self.assertEqual(value["args"], ["--model", "glm-5.3[1m]", "--effort", "high"])
        self.assertEqual(value["effort"], "high")
        self.env["GLM_EFFORT_LEVEL"] = "invalid"
        self.assertEqual(self.run_script("glm-claude").returncode, 2)

    def test_smoke_tests_share_credentials(self):
        self.fake("pass", 'printf test-pass-key')
        self.env["CLAUDE_BACKEND_CREDENTIAL_STORE"] = "pass"
        for backend in ("mimo", "deepseek", "glm", "claudex"):
            result = self.run_script("scripts/test-api.sh", backend)
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

    def test_generic_setup_supports_each_backend(self):
        self.fake("pass", 'cat >/dev/null')
        for backend in ("mimo", "deepseek", "glm", "claudex"):
            with self.subTest(backend=backend):
                result = self.run_script("scripts/setup-credential.sh", backend, "pass", input="test-input-key\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"Stored {backend} credential in pass", result.stdout)

    def test_effort_flags_override_backend_and_parent_environment(self):
        self.env.update(MIMO_ANTHROPIC_AUTH_TOKEN="test-mimo", DEEPSEEK_ANTHROPIC_AUTH_TOKEN="test-deepseek",
                        GLM_ANTHROPIC_AUTH_TOKEN="test-glm", CLAUDEX_PROXY_KEY="test-proxy",
                        CLAUDE_CODE_EFFORT_LEVEL="low")
        for launcher in ("mimo-claude", "deepseek-claude", "glm-claude", "claudex"):
            for flags in (("--effort", "high"), ("--effort=high",)):
                with self.subTest(launcher=launcher, flags=flags):
                    result = self.run_script(launcher, *flags)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    value = json.loads(result.stdout)
                    self.assertEqual(value["env"]["CLAUDE_CODE_EFFORT_LEVEL"], "high")
                    self.assertEqual(value["args"].count("--effort"), 1)
                    self.assertEqual(value["args"][value["args"].index("--effort") + 1], "high")

    def test_cloud_selectors_are_cleared_directly_and_when_nested(self):
        selectors = ("CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
                     "CLAUDE_CODE_USE_ANTHROPIC_AWS", "CLAUDE_CODE_USE_MANTLE")
        self.env.update({name: "1" for name in selectors})
        self.env.update(MIMO_ANTHROPIC_AUTH_TOKEN="test-mimo", DEEPSEEK_ANTHROPIC_AUTH_TOKEN="test-deepseek",
                        GLM_ANTHROPIC_AUTH_TOKEN="test-glm", CLAUDEX_PROXY_KEY="test-proxy")
        for launcher in ("mimo-claude", "deepseek-claude", "glm-claude", "claudex"):
            with self.subTest(launcher=launcher):
                value = json.loads(self.run_script(launcher).stdout)
                self.assertTrue(all(value["env"][name] is None for name in selectors))
        for backend in ("mimo", "deepseek", "glm"):
            with self.subTest(nested=backend):
                result = self.run_script("ask-backend", backend, "test")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(all(json.loads(result.stdout)["env"][name] is None for name in selectors))

    def test_proxy_model_flag_drives_preflight_and_subagents(self):
        self.env["CLAUDEX_PROXY_KEY"] = "test-proxy"
        self.fake("curl", 'printf \'{"data":[{"id":"gpt-5.6-luna"}]}\\n200\'')
        for flags in (("--model", "gpt-5.6-luna"), ("--model=gpt-5.6-luna",), ("--luna",)):
            result = self.run_script("claudex", *flags)
            self.assertEqual(result.returncode, 0, result.stderr)
            value = json.loads(result.stdout)
            self.assertEqual(value["model"], "gpt-5.6-luna")
            self.assertEqual(value["env"]["CLAUDE_CODE_SUBAGENT_MODEL"], "gpt-5.6-luna")
            self.assertEqual(value["args"].count("--model"), 1)

    def test_delimiter_preserves_literal_prompt_and_permission_flags(self):
        self.env["CLAUDEX_PROXY_KEY"] = "test-proxy"
        result = self.run_script("claudex", "-p", "--", "--luna", "--permission-mode", "default")
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["model"], "gpt-5.6-sol")
        self.assertEqual(value["args"][-5:], ["-p", "--", "--luna", "--permission-mode", "default"])
        self.assertIn("--dangerously-skip-permissions", value["args"])
        self.env["MIMO_ANTHROPIC_AUTH_TOKEN"] = "test-mimo"
        result = self.run_script("ask-backend", "mimo", "--effort", "--effort", "high")
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["args"][-2:], ["--", "--effort"])
        self.assertEqual(value["env"]["CLAUDE_CODE_EFFORT_LEVEL"], "high")

    def test_none_effort_and_missing_cli_values_are_rejected(self):
        self.env["CLAUDEX_PROXY_KEY"] = "test-proxy"
        self.env["CLAUDEX_EFFORT"] = "none"
        self.assertEqual(self.run_script("claudex").returncode, 2)
        self.env.pop("CLAUDEX_EFFORT")
        for flags in (("--effort",), ("--effort=",), ("--model",), ("--model=",)):
            self.assertEqual(self.run_script("claudex", *flags).returncode, 2)

    def test_passthrough_values_are_not_launcher_options(self):
        self.env.update(GLM_ANTHROPIC_AUTH_TOKEN="test-glm", CLAUDEX_PROXY_KEY="test-proxy")
        for launcher in ("glm-claude", "claudex"):
            for option, text in (("--append-system-prompt", "--effort=low"),
                                 ("--append-subagent-system-prompt", "--effort=low"),
                                 ("--system-prompt", "--model=gpt-5.6-luna"),
                                 ("--settings", "--luna"), ("--tools", "")):
                with self.subTest(launcher=launcher, option=option):
                    result = self.run_script(launcher, option, text)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    value = json.loads(result.stdout)
                    self.assertEqual(value["env"]["CLAUDE_CODE_EFFORT_LEVEL"], "max")
                    self.assertEqual(value["model"], "glm-5.3[1m]" if launcher == "glm-claude" else "gpt-5.6-sol")
                    self.assertEqual(value["args"][-2:], [option, text])

    def test_nested_permission_defaults_ignore_opaque_values(self):
        self.env.update(MIMO_ANTHROPIC_AUTH_TOKEN="test-mimo", DEEPSEEK_ANTHROPIC_AUTH_TOKEN="test-deepseek",
                        GLM_ANTHROPIC_AUTH_TOKEN="test-glm")
        for backend in ("mimo", "deepseek", "glm"):
            for text in ("--dangerously-skip-permissions", "--permission-mode=acceptEdits"):
                with self.subTest(backend=backend, text=text):
                    result = self.run_script("ask-backend", backend, "test", "--append-system-prompt", text)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    args = json.loads(result.stdout)["args"]
                    self.assertEqual(args[4:], ["--permission-mode", "default", "-p",
                                               "--append-system-prompt", text, "--", "test"])

    def test_fast_model_and_context_override_are_effective(self):
        self.env.update(MIMO_ANTHROPIC_AUTH_TOKEN="test-mimo", MIMO_FAST_MODEL="mimo-v2.5",
                        MIMO_MAX_CONTEXT_TOKENS="512000")
        result = self.run_script("mimo-claude")
        self.assertEqual(result.returncode, 0, result.stderr)
        values = json.loads(result.stdout)["env"]
        self.assertEqual(values["ANTHROPIC_DEFAULT_HAIKU_MODEL"], "mimo-v2.5")
        self.assertEqual(values["CLAUDE_CODE_SUBAGENT_MODEL"], "mimo-v2.5")
        self.assertEqual(values["CLAUDE_CODE_MAX_CONTEXT_TOKENS"], "512000")
        self.assertEqual(values["CLAUDE_CODE_DISABLE_1M_CONTEXT"], "1")

    def test_zero_spellings_are_rejected(self):
        self.env.update(MIMO_ANTHROPIC_AUTH_TOKEN="test-mimo", CLAUDEX_PROXY_KEY="test-proxy")
        for name, launcher in (("MIMO_MAX_RETRIES", "mimo-claude"), ("MIMO_TOOL_CONCURRENCY", "mimo-claude"),
                               ("CLAUDEX_CONCURRENCY", "claudex"), ("CLAUDEX_MAX_CONTEXT_TOKENS", "claudex")):
            for zero in ("0", "00", "000"):
                with self.subTest(name=name, zero=zero):
                    self.env[name] = zero
                    self.assertEqual(self.run_script(launcher).returncode, 2)
            self.env.pop(name)

    def test_store_failures_are_reported_without_raw_stderr(self):
        self.env["CLAUDE_BACKEND_CREDENTIAL_STORE"] = "pass"
        self.fake("pass", 'printf "gpg: decryption failed; test-secret-do-not-show" >&2; exit 42')
        result = self.run_script("scripts/debug-auth-source.sh", "mimo")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pass (exit 42)", result.stderr)
        self.assertIn("GPG decryption", result.stderr)
        self.assertNotIn("test-secret-do-not-show", result.stdout + result.stderr)

    def test_ask_backend_uses_default_permissions(self):
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
