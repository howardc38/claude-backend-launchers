"""Real curl + local HTTP fixtures; no provider calls or real credentials."""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
REAL_CURL = shutil.which("curl")
REAL_CLAUDE = shutil.which("claude")
TEST_BASH = os.environ.get("CLAUDE_BACKEND_TEST_BASH", "bash")


class LocalAPI(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.capture = self.work / "curl-argv.jsonl"
        self.requests = []
        self.models = ["gpt-5.6-sol", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-6-luna", "gpt-6-astra", "gpt-6.1-sol"]
        self.inventory = None
        self.status = 200
        self.reply = {"content": [{"type": "text", "text": "ok"}]}
        self.fixture = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(handler):
                fixture = self.fixture
                fixture.requests.append({"method": "GET", "path": handler.path,
                                         "headers": dict(handler.headers)})
                inventory = fixture.inventory
                if inventory is None:
                    inventory = {"data": [{"id": model} for model in fixture.models]}
                handler.send_json(inventory)

            def do_POST(handler):
                fixture = self.fixture
                body = handler.rfile.read(int(handler.headers.get("Content-Length", "0")))
                payload = json.loads(body)
                fixture.requests.append({"method": "POST", "path": handler.path,
                                         "headers": dict(handler.headers), "body": payload})
                if payload.get("stream"):
                    model = payload["model"]
                    events = [
                        ("message_start", {"type": "message_start", "message": {
                            "id": "msg_local_test", "type": "message", "role": "assistant",
                            "model": model, "content": [], "stop_reason": None,
                            "stop_sequence": None, "usage": {"input_tokens": 1, "output_tokens": 0}}}),
                        ("content_block_start", {"type": "content_block_start", "index": 0,
                                                 "content_block": {"type": "text", "text": ""}}),
                        ("content_block_delta", {"type": "content_block_delta", "index": 0,
                                                 "delta": {"type": "text_delta", "text": "ok"}}),
                        ("content_block_stop", {"type": "content_block_stop", "index": 0}),
                        ("message_delta", {"type": "message_delta", "delta": {
                            "stop_reason": "end_turn", "stop_sequence": None}, "usage": {"output_tokens": 1}}),
                        ("message_stop", {"type": "message_stop"}),
                    ]
                    content = "".join(f"event: {name}\ndata: {json.dumps(data)}\n\n"
                                      for name, data in events).encode()
                    handler.send_response(200)
                    handler.send_header("Content-Type", "text/event-stream")
                    handler.send_header("Content-Length", str(len(content)))
                    handler.end_headers()
                    handler.wfile.write(content)
                else:
                    handler.send_json(fixture.reply)

            def send_json(handler, data):
                content = json.dumps(data).encode()
                handler.send_response(self.fixture.status)
                handler.send_header("Content-Type", "application/json")
                handler.send_header("Content-Length", str(len(content)))
                handler.end_headers()
                handler.wfile.write(content)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        self.env = dict(os.environ)
        for name in list(self.env):
            if name.startswith(("ANTHROPIC_", "MIMO_", "DEEPSEEK_", "GLM_", "CLAUDEX_", "CLAUDE_BACKEND_", "CLAUDE_CODE_")):
                self.env.pop(name)
        self.env.update(PATH=str(self.bin) + ":" + os.environ["PATH"],
                        CLAUDE_BACKEND_CREDENTIAL_STORE="env",
                        MIMO_ANTHROPIC_AUTH_TOKEN="test-http-key",
                        DEEPSEEK_ANTHROPIC_AUTH_TOKEN="test-http-key",
                        GLM_ANTHROPIC_AUTH_TOKEN="test-http-key",
                        CLAUDEX_PROXY_KEY="test-http-key",
                        MIMO_BASE_URL=self.url, DEEPSEEK_BASE_URL=self.url,
                        GLM_BASE_URL=self.url, CLAUDEX_BASE_URL=self.url,
                        CURL_ARGV_CAPTURE=str(self.capture), REAL_CURL_PATH=str(REAL_CURL),
                        CLAUDE_CONFIG_DIR=str(self.work / "claude-config"))
        self.fake("curl", "exec python3 -c 'import os,json,sys; "
                  "f=open(os.environ[\"CURL_ARGV_CAPTURE\"],\"a\"); "
                  "f.write(json.dumps(sys.argv[1:])+\"\\n\"); f.close(); "
                  "os.execv(os.environ[\"REAL_CURL_PATH\"],[\"curl\"]+sys.argv[1:])' \"$@\"")
        self.fake("claude", 'printf "Unexpected fake Claude execution\\n" >&2; exit 99')

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def run_script(self, script, *args, timeout=20):
        return subprocess.run([TEST_BASH, str(ROOT / script), *args], env=self.env,
                              text=True, capture_output=True, timeout=timeout)

    def post(self):
        return next(request for request in reversed(self.requests) if request["method"] == "POST")

    def test_default_models_headers_and_payloads_for_all_backends(self):
        expected = {
            "mimo": ("mimo-v2.6-pro", "Api-Key", "test-http-key"),
            "deepseek": ("deepseek-flash", "Authorization", "Bearer test-http-key"),
            "glm": ("glm-5.3", "X-Api-Key", "test-http-key"),
            "claudex": ("gpt-6.1-sol", "Authorization", "Bearer test-http-key"),
        }
        for backend, (model, header, credential) in expected.items():
            with self.subTest(backend=backend):
                result = self.run_script("scripts/test-api.sh", backend)
                self.assertEqual(result.returncode, 0, result.stderr)
                request = self.post()
                headers = {key.lower(): value for key, value in request["headers"].items()}
                self.assertEqual(headers[header.lower()], credential)
                self.assertEqual(request["body"]["model"], model)
                if backend == "claudex":
                    self.assertEqual(request["body"]["thinking"], {"type": "adaptive"})
                    self.assertEqual(request["body"]["output_config"]["effort"], "low")
                else:
                    self.assertEqual(request["body"]["thinking"], {"type": "disabled"})
                self.assertEqual(request["body"]["messages"], [{"role": "user", "content": "Reply with exactly: ok"}])
                self.assertNotIn("test-http-key", result.stdout + result.stderr)
        for line in self.capture.read_text().splitlines():
            argv = json.loads(line)
            self.assertNotIn("test-http-key", " ".join(argv))
            self.assertEqual(argv[0], "--disable")
            self.assertEqual(argv[argv.index("--config") + 1], "/dev/fd/3")
            self.assertEqual(argv[argv.index("--max-time") + 1], "60")
            self.assertEqual(argv[argv.index("--connect-timeout") + 1], "10")

    def test_context_suffix_is_stripped_for_every_backend(self):
        cases = (("mimo", "MIMO_MODEL", "mimo-v2.6-pro[1M]", "mimo-v2.6-pro"),
                 ("deepseek", "DEEPSEEK_MODEL", "deepseek-v4-pro[1m]", "deepseek-v4-pro"),
                 ("glm", "GLM_MODEL", "glm-5.3-flash[1m]", "glm-5.3-flash"),
                 ("claudex", "CLAUDEX_MODEL", "gpt-6.1-sol[1m]", "gpt-6.1-sol"))
        for backend, variable, configured, native in cases:
            with self.subTest(backend=backend):
                self.env[variable] = configured
                result = self.run_script("scripts/test-api.sh", backend)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.post()["body"]["model"], native)

    def test_proxy_environment_and_explicit_selectors(self):
        self.env["CLAUDEX_MODEL"] = "gpt-6-astra"
        for flags, model in (((), "gpt-6-astra"), (("--luna",), "gpt-6-luna"),
                             (("--terra",), "gpt-5.6-terra"), (("--model", "gpt-5.6-sol"), "gpt-5.6-sol")):
            with self.subTest(flags=flags):
                result = self.run_script("scripts/test-api.sh", "claudex", *flags)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.post()["body"]["model"], model)
                if model == "gpt-6-luna":
                    self.assertEqual(self.post()["body"]["thinking"], {"type": "disabled"})

    def test_proxy_preflight_rejects_missing_and_malformed_models(self):
        for inventory in ({"data": [{"id": "gpt-6-luna", "owner": "gpt-6.1-sol"}]},
                          {"data": "gpt-6.1-sol"}, {"data": [{"id": "other\ngpt-6.1-sol"}]}):
            with self.subTest(inventory=inventory):
                self.inventory = inventory
                self.requests.clear()
                result = self.run_script("scripts/test-api.sh", "claudex")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([request["method"] for request in self.requests], ["GET"])
                self.assertTrue("not listed" in result.stderr or "invalid model inventory" in result.stderr)
                self.assertFalse(any(request["method"] == "POST" for request in self.requests))

    def test_openai_inventory_envelope_keeps_native_request_model(self):
        self.inventory = {"data": [{"id": "claude-fable-5-dd-los-1.6-tpg", "owned_by": "openai"}]}
        result = self.run_script("scripts/test-api.sh", "claudex")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.post()["body"]["model"], "gpt-6.1-sol")
        self.assertEqual(self.post()["body"]["output_config"]["effort"], "low")

    def test_inventory_envelope_requires_exact_codec_and_provider(self):
        for item in ({"id": "claude-fable-5-dd-los-1.6-tpg", "owned_by": "anthropic"},
                     {"id": "claude-fable-5-dd-los-6.5-tpg", "owned_by": "openai"},
                     {"id": "custom-gpt-6.1-sol", "owned_by": "openai"}):
            with self.subTest(item=item):
                self.inventory = {"data": [item]}
                self.requests.clear()
                result = self.run_script("scripts/test-api.sh", "claudex")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("not listed", result.stderr)
                self.assertEqual([r["method"] for r in self.requests], ["GET"])

    def test_http_failures_do_not_report_success_or_print_credentials(self):
        self.status = 401
        result = self.run_script("scripts/test-api.sh", "glm")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("401", result.stderr)
        self.assertEqual(len(self.requests), 1)
        self.assertNotIn("smoke test OK", result.stdout)
        self.assertNotIn("test-http-key", result.stdout + result.stderr)

    def test_empty_or_invalid_responses_do_not_report_success(self):
        for reply in ({"content": []}, {"content": [{"type": "text", "text": "unexpected"}]}, {"other": "ok"}):
            with self.subTest(reply=reply):
                self.reply = reply
                self.requests.clear()
                result = self.run_script("scripts/test-api.sh", "mimo")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.requests), 1)
                self.assertIn("Smoke test failed:", result.stderr)
                self.assertNotIn("smoke test OK", result.stdout)

    def test_redirects_cannot_succeed_with_plausible_json(self):
        self.status = 302
        for script, args in (("scripts/test-api.sh", ("glm",)),
                             ("scripts/test-api.sh", ("claudex",)), ("claudex", ()),
                             ("scripts/debug-cliproxy.sh", ())):
            with self.subTest(script=script, args=args):
                self.requests.clear()
                result = self.run_script(script, *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("expected 2xx, received 302", result.stderr)
                self.assertEqual(len(self.requests), 1)
                self.assertNotIn("smoke test OK", result.stdout)

    def test_header_injection_is_rejected_before_curl(self):
        self.env["GLM_ANTHROPIC_AUTH_TOKEN"] = "test-key\r\nInjected: yes"
        result = self.run_script("scripts/test-api.sh", "glm")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.requests, [])
        self.assertNotIn("test-key", result.stdout + result.stderr)

    def test_config_escaping_preserves_opaque_header_value(self):
        credential = 'test-header"\\opaque'
        self.env["GLM_ANTHROPIC_AUTH_TOKEN"] = credential
        result = self.run_script("scripts/test-api.sh", "glm")
        self.assertEqual(result.returncode, 0, result.stderr)
        headers = {key.lower(): value for key, value in self.post()["headers"].items()}
        self.assertEqual(headers["x-api-key"], credential)
        self.assertNotIn(credential, self.capture.read_text())
        self.assertNotIn(credential, result.stdout + result.stderr)

    def test_proxy_debug_reports_custom_and_full_model_inventory(self):
        self.env["CLAUDEX_MODEL"] = "gpt-6.1-sol"
        result = self.run_script("scripts/debug-cliproxy.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        for model in self.models:
            self.assertIn(model, result.stdout)
        self.assertIn("Selected model: gpt-6.1-sol (available)", result.stdout)
        self.assertNotIn("test-http-key", result.stdout + result.stderr)

    @unittest.skipUnless(REAL_CLAUDE, "Optional installed-Claude contract check; local HTTP only")
    def test_installed_claude_resolves_effort_and_custom_context(self):
        # Use a fresh config, no tools/persistence, fake credentials, and loopback.
        self.env["REAL_CLAUDE_PATH"] = str(REAL_CLAUDE)
        self.fake("claude", 'exec "$REAL_CLAUDE_PATH" "$@"')
        result = self.run_script("glm-claude", "--append-system-prompt", "--effort=low", "-p", "--effort", "high", "--bare",
                                 "--permission-mode", "default",
                                 "--no-session-persistence", "--tools", "", "--output-format", "json",
                                 "--", "Reply with exactly: ok", timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr)
        request = self.post()["body"]
        self.assertEqual(request["model"], "glm-5.3")
        self.assertEqual(request["output_config"]["effort"], "high")
        self.assertIn("--effort=low", json.dumps(request["system"]))
        self.env["MIMO_MAX_CONTEXT_TOKENS"] = "512000"
        result = self.run_script("mimo-claude", "-p", "--bare", "--no-session-persistence",
                                 "--tools", "", "--output-format", "json", "--", "Reply with exactly: ok", timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr)
        usage = json.loads(result.stdout)["modelUsage"]
        self.assertTrue(usage, "Installed Claude must report model usage")
        self.assertTrue(all(model["contextWindow"] == 512000 for model in usage.values()))

    @unittest.skipUnless(REAL_CLAUDE, "Optional installed-Claude nested permission check; loopback only")
    def test_installed_claude_nested_text_cannot_enable_bypass(self):
        # The helper pins the canonical provider URL. This transport shim only
        # redirects the client to the fixture; permission arguments are intact.
        self.env.update(LOCAL_TEST_API_URL=self.url, REAL_CLAUDE_PATH=str(REAL_CLAUDE))
        self.fake("claude", 'export ANTHROPIC_BASE_URL="$LOCAL_TEST_API_URL"; exec "$REAL_CLAUDE_PATH" "$@"')
        result = self.run_script("ask-backend", "mimo", "Reply with exactly: ok",
                                 "--append-system-prompt", "--dangerously-skip-permissions",
                                 "--bare", "--no-session-persistence", "--tools", "",
                                 "--output-format", "stream-json", "--verbose", timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr)
        messages = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        init = next(message for message in messages if message.get("type") == "system" and message.get("subtype") == "init")
        self.assertIn(init["permissionMode"], ("default", "manual"))
        self.assertIn("--dangerously-skip-permissions", json.dumps(self.post()["body"]["system"]))


if __name__ == "__main__":
    unittest.main()
