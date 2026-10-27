"""Go contract tests: real CLIProxyAPI, loopback upstream, no provider keys/calls."""
import contextlib
import http.client
import http.server
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("go_proxy", ROOT / "scripts/opencode-go-proxy.py")
go = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(go)
PROXY = shutil.which("cliproxyapi") or shutil.which("cli-proxy-api")
CLAUDE = shutil.which("claude")


class GoPolicy(unittest.TestCase):
    def test_catalog_covers_requested_families_and_selected_new_models(self):
        models = go.load_models()
        counts = {prefix: sum(model.startswith(prefix) for model in models)
                  for prefix in ("glm-", "kimi-", "deepseek-", "mimo-", "minimax-", "qwen", "claude-")}
        self.assertEqual(counts, {"glm-": 3, "kimi-": 3, "deepseek-": 5, "mimo-": 4,
                                  "minimax-": 3, "qwen": 3, "claude-": 1})
        for model in ("gpt-6-luna", "grok-4.7", "gemini-4-argon-contributor"):
            self.assertIn(model, models)
        for model in ("gpt-5.6-luna", "grok-4.6", "muse-spark-1.3-contributor"):
            with self.assertRaises(ValueError):
                go.model_settings(model, models)

    def test_invalid_efforts_are_rejected_instead_of_silently_clamped(self):
        models = go.load_models()
        for model, spec in models.items():
            for level in go.CLIENT_LEVELS:
                with self.subTest(model=model, level=level):
                    if level == "max" or level in spec["efforts"]:
                        go.resolve_effort(spec, level)
                    else:
                        with self.assertRaises(ValueError):
                            go.resolve_effort(spec, level)

    def test_prefix_and_context_tag_resolve_to_native_id(self):
        model, _ = go.model_settings("opencode-go/kimi-k3[1m]", go.load_models())
        self.assertEqual(model, "kimi-k3")
        model, spec = go.model_settings("gemini-4-argon", go.load_models())
        self.assertEqual(model, "gemini-4-argon-contributor")
        self.assertTrue(spec["training"])

    def test_generic_anthropic_key_cannot_authenticate_go(self):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("OPENCODE_GO_", "ANTHROPIC_", "CLAUDE_BACKEND_"))}
        env.update(ANTHROPIC_AUTH_TOKEN="wrong-provider", CLAUDE_BACKEND_CREDENTIAL_STORE="env")
        result = subprocess.run(["bash", str(ROOT / "scripts/debug-auth-source.sh"), "go"],
                                env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("wrong-provider", result.stdout + result.stderr)

    def test_launcher_rejects_overstated_context_and_output_before_auth(self):
        for setting, value in (("MAX_CONTEXT_TOKENS", "1000000"),
                               ("MAX_OUTPUT_TOKENS", "262144"), ("AUTO_COMPACT_WINDOW", "999999")):
            env = dict(os.environ, **{"OPENCODE_GO_" + setting: value})
            result = subprocess.run(["bash", str(ROOT / "go-claude"), "--model", "minimax-m2.7"],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("limits", result.stderr)

    def test_batch_efforts_are_validated_before_loading_credentials(self):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("OPENCODE_GO_", "ANTHROPIC_", "CLAUDE_BACKEND_"))}
        env["CLAUDE_BACKEND_CREDENTIAL_STORE"] = "env"
        result = subprocess.run(["bash", str(ROOT / "scripts/test-api.sh"), "go", "--all", "--effort", "low"],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("supports", result.stderr)
        self.assertNotIn("No credential", result.stderr)


@unittest.skipUnless(PROXY, "CLIProxyAPI required for offline wire contracts")
class GoWire(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.requests = []
        cls.status = 200
        cls.tool_response = False

        class Upstream(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                cls.requests.append({"path": self.path, "body": body, "headers": dict(self.headers)})
                if cls.status != 200:
                    return self.reply({"error": {"message": "fixture rate limit", "type": "rate_limit_error"}}, cls.status)
                if self.path.endswith("/responses"):
                    return self.responses_reply(body)
                if "/models/" in self.path:
                    return self.google_reply(body)
                if self.path.endswith("/chat/completions"):
                    if body.get("stream"):
                        self.send_response(200)
                        self.send_header("Content-Type", "text/event-stream")
                        self.end_headers()
                        deltas = [{"role": "assistant"}, {"reasoning_content": "fixture reasoning"}]
                        if cls.tool_response:
                            deltas += [{"tool_calls": [{"index": 0, "id": "call_fixture", "type": "function",
                                                       "function": {"name": "get_value", "arguments": '{"key":"x"}'}}]}]
                        else:
                            deltas += [{"content": "ok"}]
                        for delta in deltas:
                            self.wfile.write(("data: " + json.dumps({"id": "chat_fixture", "model": body["model"],
                                "choices": [{"index": 0, "delta": delta, "finish_reason": None}]}) + "\n\n").encode())
                            self.wfile.flush()
                        finish = "tool_calls" if cls.tool_response else "stop"
                        self.wfile.write(("data: " + json.dumps({"id": "chat_fixture", "model": body["model"],
                            "choices": [{"index": 0, "delta": {}, "finish_reason": finish}],
                            "usage": {"prompt_tokens": 10, "completion_tokens": 3}}) + "\n\ndata: [DONE]\n\n").encode())
                        return
                    content = {"id": "chat_fixture", "object": "chat.completion", "created": 0,
                        "model": body["model"], "choices": [{"index": 0, "message": {"role": "assistant",
                            "reasoning_content": "fixture reasoning", "content": "ok"}, "finish_reason": "stop"}],
                        "usage": {"prompt_tokens": 10, "completion_tokens": 3}}
                else:
                    content = {"id": "msg_fixture", "type": "message", "role": "assistant", "model": body["model"],
                        "content": [{"type": "thinking", "thinking": "fixture reasoning", "signature": "opaque-signature"},
                                    {"type": "text", "text": "ok"}],
                        "stop_reason": "end_turn", "stop_sequence": None, "usage": {"input_tokens": 10, "output_tokens": 3}}
                    if body.get("stream"):
                        self.send_response(200)
                        self.send_header("Content-Type", "text/event-stream")
                        self.end_headers()
                        message = {**content, "content": [], "stop_reason": None}
                        events = [("message_start", {"type": "message_start", "message": message}),
                            ("content_block_start", {"type": "content_block_start", "index": 0,
                                "content_block": {"type": "text", "text": ""}}),
                            ("content_block_delta", {"type": "content_block_delta", "index": 0,
                                "delta": {"type": "text_delta", "text": "ok"}}),
                            ("content_block_stop", {"type": "content_block_stop", "index": 0}),
                            ("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn"},
                                               "usage": {"output_tokens": 3}}),
                            ("message_stop", {"type": "message_stop"})]
                        for name, event in events:
                            self.wfile.write(f"event: {name}\ndata: {json.dumps(event)}\n\n".encode())
                            self.wfile.flush()
                        return
                self.reply(content)

            def responses_reply(self, body):
                if cls.tool_response:
                    item = {"id": "fc_fixture", "type": "function_call", "call_id": "call_fixture",
                            "name": "get_value", "arguments": '{"key":"x"}', "status": "completed"}
                else:
                    item = {"id": "msg_fixture", "type": "message", "role": "assistant", "status": "completed",
                            "content": [{"type": "output_text", "text": "ok", "annotations": []}]}
                response = {"id": "resp_fixture", "object": "response", "status": "completed", "model": body["model"],
                            "output": [item], "usage": {"input_tokens": 10, "output_tokens": 3, "total_tokens": 13}}
                if not body.get("stream"):
                    return self.reply(response)
                events = [("response.created", {"response": {**response, "status": "in_progress", "output": []}}),
                          ("response.output_item.added", {"output_index": 0, "item": {**item, "status": "in_progress"}})]
                if cls.tool_response:
                    events += [("response.function_call_arguments.delta", {"output_index": 0, "item_id": item["id"],
                                "delta": item["arguments"]}),
                               ("response.function_call_arguments.done", {"output_index": 0, "item_id": item["id"],
                                "arguments": item["arguments"]})]
                else:
                    events += [("response.content_part.added", {"output_index": 0, "content_index": 0, "item_id": item["id"],
                                "part": {"type": "output_text", "text": "", "annotations": []}}),
                               ("response.output_text.delta", {"output_index": 0, "content_index": 0,
                                "item_id": item["id"], "delta": "ok"}),
                               ("response.output_text.done", {"output_index": 0, "content_index": 0,
                                "item_id": item["id"], "text": "ok"})]
                events += [("response.output_item.done", {"output_index": 0, "item": item}),
                           ("response.completed", {"response": response})]
                self.send_events(events)

            def google_reply(self, body):
                if cls.tool_response:
                    parts = [{"functionCall": {"name": "get_value", "args": {"key": "x"}}}]
                else:
                    parts = [{"text": "ok"}]
                response = {"candidates": [{"index": 0, "content": {"role": "model", "parts": parts}, "finishReason": "STOP"}],
                            "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 3, "totalTokenCount": 13}}
                if "streamGenerateContent" not in self.path:
                    return self.reply(response)
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                self.wfile.write(("data: " + json.dumps(response) + "\n\n").encode())
                self.wfile.flush()

            def send_events(self, events):
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                for sequence, (name, event) in enumerate(events):
                    event = {"type": name, "sequence_number": sequence, **event}
                    self.wfile.write(f"event: {name}\ndata: {json.dumps(event)}\n\n".encode())
                    self.wfile.flush()

            def reply(self, content, status=200):
                body = json.dumps(content).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        cls.upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        threading.Thread(target=cls.upstream.serve_forever, daemon=True).start()
        cls.models = go.load_models()
        cls.url = f"http://127.0.0.1:{cls.upstream.server_port}"
        cls.stack = contextlib.ExitStack()
        cls.stack.callback(cls.upstream.server_close)
        cls.stack.callback(cls.upstream.shutdown)
        try:
            cls.gateway = cls.stack.enter_context(go.running_gateway(cls.models, cls.url, "test-go-upstream-key", PROXY))
        except BaseException:
            cls.stack.close()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.stack.close()

    def setUp(self):
        type(self).status = 200
        type(self).tool_response = False

    def call(self, payload=None, path="/v1/messages", key=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.gateway.server_port, timeout=20)
        try:
            connection.request("GET" if payload is None else "POST", path,
                body=None if payload is None else json.dumps(payload),
                headers={"Authorization": "Bearer " + (self.gateway.client_key if key is None else key),
                         "Content-Type": "application/json"})
            response = connection.getresponse()
            return response.status, response.read().decode()
        finally:
            connection.close()

    def test_every_model_and_supported_effort_reaches_the_correct_wire(self):
        for model, spec in self.models.items():
            for level in set(spec["efforts"] + ["max"]):
                with self.subTest(model=model, effort=level):
                    status, response = self.call({"model": model, "max_tokens": 8192,
                        "output_config": {"effort": level}, "messages": [{"role": "user", "content": "say ok"}]})
                    self.assertEqual(status, 200, response)
                    self.assertEqual("".join(item["text"] for item in json.loads(response)["content"]
                                             if item["type"] == "text"), "ok")
                    request = self.requests[-1]
                    body = request["body"]
                    if spec["protocol"] != "google":
                        self.assertEqual(body["model"], model)
                    headers = {key.lower(): value for key, value in request["headers"].items()}
                    self.assertEqual(headers["authorization"], "Bearer test-go-upstream-key")
                    self.assertEqual(headers["x-opencode-session"], self.gateway.session)
                    self.assertEqual(headers["user-agent"], go.USER_AGENT)
                    if spec["protocol"] == "chat":
                        self.assertEqual(request["path"], spec.get("api_path", "/v1") + "/chat/completions")
                        if spec["efforts"]:
                            self.assertEqual(body.get("reasoning_effort"), go.resolve_effort(spec, level))
                        else:
                            self.assertNotIn("reasoning_effort", body)
                        if model == "glm-5.3-flash":
                            self.assertNotIn("thinking", body)
                        elif model == "minimax-m3.1-flash-free":
                            self.assertNotIn("thinking", body)
                            self.assertNotIn("temperature", body)
                            self.assertNotIn("top_p", body)
                        elif model.startswith(("mimo-", "deepseek-", "glm-")):
                            self.assertEqual(body.get("thinking"), {"type": "enabled"})
                    elif spec["protocol"] == "responses":
                        self.assertEqual(request["path"], "/v1/responses")
                        self.assertEqual(body["reasoning"]["effort"], go.resolve_effort(spec, level))
                    elif spec["protocol"] == "google":
                        self.assertTrue(request["path"].startswith("/v1/models/" + model + ":"))
                        self.assertEqual(body["generationConfig"]["thinkingConfig"]["thinkingLevel"].lower(),
                                         go.resolve_effort(spec, level))
                    else:
                        self.assertEqual(request["path"], spec.get("api_path", "/v1") + "/messages")
                        if spec["efforts"]:
                            self.assertEqual(body["output_config"]["effort"], go.resolve_effort(spec, level))
                        else:
                            self.assertNotIn("effort", body.get("output_config", {}))
                        if model == "minimax-m3":
                            self.assertEqual(body["thinking"], {"type": "adaptive"})
                        if model == "minimax-m2.7":
                            self.assertNotIn("thinking", body)
                        if model == "qwen3.7-plus":
                            self.assertEqual(body["thinking"], {"type": "enabled", "budget_tokens": 8191})

    def test_sse_tool_call_and_reasoning_survive_chat_translation(self):
        for model in ("mimo-v2.6-pro", "minimax-m3.1-flash-free"):
            with self.subTest(model=model):
                self.assert_chat_tool_round_trip(model)

    def assert_chat_tool_round_trip(self, model):
        type(self).tool_response = True
        status, stream = self.call({"model": model, "max_tokens": 8192, "stream": True,
            "output_config": {"effort": "max"}, "messages": [{"role": "user", "content": "get x"}],
            "tools": [{"name": "get_value", "description": "lookup", "input_schema": {"type": "object",
                       "properties": {"key": {"type": "string"}}, "required": ["key"]}}]})
        self.assertEqual(status, 200, stream)
        events = [json.loads(line[6:]) for line in stream.splitlines() if line.startswith("data: ")]
        self.assertTrue(any(event.get("delta", {}).get("thinking") == "fixture reasoning" for event in events))
        block = next(event["content_block"] for event in events
                     if event.get("content_block", {}).get("type") == "tool_use")
        self.assertEqual(block["name"], "get_value")
        self.assertEqual(self.requests[-1]["body"]["tools"][0]["function"]["name"], "get_value")
        type(self).tool_response = False
        status, response = self.call({"model": model, "max_tokens": 8192,
            "messages": [{"role": "user", "content": "get x"},
                {"role": "assistant", "content": [{"type": "thinking", "thinking": "fixture reasoning"},
                    {"type": "tool_use", "id": "call_fixture", "name": "get_value", "input": {"key": "x"}}]},
                {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "call_fixture", "content": "42"}]}]})
        self.assertEqual(status, 200, response)
        history = self.requests[-1]["body"]["messages"]
        assistant = next(item for item in history if item["role"] == "assistant")
        self.assertEqual(assistant.get("reasoning_content"), "fixture reasoning")
        self.assertEqual(next(item for item in history if item["role"] == "tool")["content"], "42")

    def test_messages_preserve_native_signatures_and_tool_history(self):
        messages = [{"role": "user", "content": "hello"}, {"role": "assistant", "content": [
            {"type": "thinking", "thinking": "earlier", "signature": "original-signature"},
            {"type": "tool_use", "id": "tool_native", "name": "get_value", "input": {}}]},
            {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "tool_native", "content": "42"}]}]
        status, response = self.call({"model": "claude-haiku-5-5", "max_tokens": 8192, "messages": messages})
        self.assertEqual(status, 200, response)
        self.assertEqual(self.requests[-1]["body"]["messages"], messages)
        self.assertEqual(json.loads(response)["content"][0]["signature"], "opaque-signature")

    def test_unsupported_effort_and_responses_are_rejected_before_upstream(self):
        count = len(self.requests)
        for payload in ({"model": "glm-5.3", "output_config": {"effort": "medium"}},
                        {"model": "gpt-5.6-luna"}, {"model": "qwen3.8-max", "max_tokens": False}):
            self.assertEqual(self.call(payload)[0], 400)
        self.assertEqual(self.call({}, path="/v1/responses")[0], 404)
        self.assertEqual(self.call({}, key="wrong-key")[0], 401)
        self.assertEqual(len(self.requests), count)

    def test_responses_and_google_streaming_tool_calls(self):
        type(self).tool_response = True
        for model in ("grok-4.7", "gpt-6-luna", "gemini-4-argon"):
            with self.subTest(model=model):
                status, stream = self.call({"model": model, "max_tokens": 8192, "stream": True,
                    "messages": [{"role": "user", "content": "get x"}],
                    "tools": [{"name": "get_value", "description": "lookup", "input_schema": {"type": "object",
                               "properties": {"key": {"type": "string"}}, "required": ["key"]}}]})
                self.assertEqual(status, 200, stream)
                events = [json.loads(line[6:]) for line in stream.splitlines() if line.startswith("data: ")]
                block = next(event["content_block"] for event in events
                             if event.get("content_block", {}).get("type") == "tool_use")
                self.assertEqual(block["name"], "get_value")

    def test_inventory_and_upstream_rate_limits(self):
        status, response = self.call(path="/v1/models")
        self.assertEqual(status, 200)
        self.assertEqual({item["id"] for item in json.loads(response)["data"]}, set(self.models))
        type(self).status = 429
        status, _ = self.call({"model": "qwen3.8-max", "messages": []})
        self.assertEqual(status, 429)

    def test_launcher_uses_local_key_and_cleans_up_private_proxy_files(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "claude"
            fake.write_text("#!/usr/bin/env python3\nimport os,json,sys\n"
                "print(json.dumps({'upstream_key':os.environ.get('OPENCODE_GO_API_KEY'),"
                "'api_key':os.environ.get('ANTHROPIC_API_KEY'),'key_replaced':"
                "os.environ.get('ANTHROPIC_AUTH_TOKEN') != 'test-go-upstream-key',"
                "'url':os.environ['ANTHROPIC_BASE_URL'],'context':os.environ['CLAUDE_CODE_MAX_CONTEXT_TOKENS'],"
                "'compact':os.environ['CLAUDE_CODE_AUTO_COMPACT_WINDOW'],"
                "'model':os.environ['ANTHROPIC_MODEL'],'subagent':os.environ['CLAUDE_CODE_SUBAGENT_MODEL'],"
                "'args':sys.argv[1:]}))\n")
            fake.chmod(0o755)
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith(("OPENCODE_GO_", "ANTHROPIC_", "CLAUDE_BACKEND_"))}
            env.update(PATH=directory + ":" + os.environ["PATH"], TMPDIR=directory,
                OPENCODE_GO_API_KEY="test-go-upstream-key", OPENCODE_GO_BASE_URL=self.url,
                CLAUDE_BACKEND_CREDENTIAL_STORE="env", OPENCODE_GO_PROXY_BIN=PROXY)
            result = subprocess.run(["bash", str(ROOT / "go-claude"), "--model", "kimi-k2.6"],
                                    env=env, capture_output=True, text=True, timeout=25)
            self.assertEqual(result.returncode, 0, result.stderr)
            value = json.loads(result.stdout)
            self.assertIsNone(value["upstream_key"])
            self.assertIsNone(value["api_key"])
            self.assertTrue(value["key_replaced"])
            self.assertEqual(value["context"], "262144")
            self.assertEqual(value["compact"], "196608")
            self.assertEqual(value["model"], value["subagent"])
            self.assertEqual(value["args"].count("--dangerously-skip-permissions"), 1)
            self.assertFalse(list(Path(directory).glob("opencode-go-*")))
            for setting, flags in (({"OPENCODE_GO_SKIP_PERMISSIONS": "0"}, []),
                                   ({}, ["--permission-mode", "default"])):
                with self.subTest(setting=setting, flags=flags):
                    result = subprocess.run(["bash", str(ROOT / "go-claude"), "--model", "kimi-k2.6", *flags],
                                            env={**env, **setting}, capture_output=True, text=True, timeout=25)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    value = json.loads(result.stdout)
                    self.assertNotIn("--dangerously-skip-permissions", value["args"])
                    if flags:
                        self.assertEqual(value["args"][-2:], flags)
                    self.assertFalse(list(Path(directory).glob("opencode-go-*")))

    @unittest.skipUnless(CLAUDE, "Installed Claude optional; only loopback requests")
    def test_installed_claude_uses_streaming_and_native_highest_effort(self):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("OPENCODE_GO_", "ANTHROPIC_", "CLAUDE_BACKEND_", "CLAUDE_CODE_"))}
        with tempfile.TemporaryDirectory() as directory:
            env.update(OPENCODE_GO_API_KEY="test-go-upstream-key", OPENCODE_GO_BASE_URL=self.url,
                       CLAUDE_BACKEND_CREDENTIAL_STORE="env", OPENCODE_GO_PROXY_BIN=PROXY,
                       CLAUDE_CONFIG_DIR=directory)
            for model, effort in (("glm-5.3", "max"), ("qwen3.8-max", "xhigh")):
                with self.subTest(model=model):
                    result = subprocess.run(["bash", str(ROOT / "go-claude"), "--model", model,
                        "--bare", "-p", "--tools", "", "--output-format", "json", "--", "say ok"],
                        env=env, capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout)["result"], "ok")
                    body = self.requests[-1]["body"]
                    self.assertTrue(body["stream"])
                    self.assertEqual(body.get("reasoning_effort", body.get("output_config", {}).get("effort")), effort)

    @unittest.skipUnless(CLAUDE, "Installed Claude optional; only loopback requests")
    def test_smoke_helper_uses_actual_claude_and_checks_response(self):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("OPENCODE_GO_", "ANTHROPIC_", "CLAUDE_BACKEND_", "CLAUDE_CODE_"))}
        with tempfile.TemporaryDirectory() as directory:
            env.update(OPENCODE_GO_API_KEY="test-go-upstream-key", OPENCODE_GO_BASE_URL=self.url,
                       CLAUDE_BACKEND_CREDENTIAL_STORE="env", OPENCODE_GO_PROXY_BIN=PROXY,
                       CLAUDE_CONFIG_DIR=directory)
            result = subprocess.run(["bash", str(ROOT / "scripts/test-api.sh"), "go", "--model", "glm-5.3"],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("API smoke test OK", result.stdout)
            self.assertNotIn("test-go-upstream-key", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
