#!/usr/bin/env python3
"""Supervise an isolated CLIProxyAPI and apply Go's per-model request policy.

CLIProxyAPI owns Chat, Responses, Google, tool, and SSE translation. Messages go
directly to Go, preserving native thinking blocks and signatures. Only the Python stdlib
is required. Keys stay out of argv and the temporary config is removed on exit.
"""
import contextlib
import hmac
import http.client
import http.server
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from urllib.parse import urlsplit

CATALOG_PATH = Path(__file__).resolve().parents[1] / "config/opencode-go-models.json"
MODEL_ALIASES = json.loads(CATALOG_PATH.read_text()).get("aliases", {})
USER_AGENT = "claude-backend-launchers/opencode-go/1.0"
CLIENT_LEVELS = ("low", "medium", "high", "xhigh", "max")


def load_models():
    return json.loads(CATALOG_PATH.read_text())["models"]


def model_settings(model, models):
    model = model.removeprefix("opencode-go/")
    model = re.sub(r"\[1m\]$", "", model, flags=re.IGNORECASE)
    model = MODEL_ALIASES.get(model, model)
    if model not in models:
        raise ValueError("Unsupported Go model. Run go-claude --list-models.")
    return model, models[model]


def resolve_effort(spec, effort):
    # max means the highest supported setting, including xhigh/budget/on models.
    if effort == "max":
        return spec["default_effort"]
    if effort in spec["efforts"]:
        return effort
    supported = ", ".join(spec["efforts"]) or "thinking only (no graded effort)"
    raise ValueError(f"{spec['name']} supports {supported}; use max for its highest setting.")


def normalize_request(payload, models):
    if not isinstance(payload, dict) or not isinstance(payload.get("model"), str):
        raise ValueError("A model ID is required.")
    model, spec = model_settings(payload["model"], models)
    payload = dict(payload)
    output_config = payload.get("output_config") or {}
    if not isinstance(output_config, dict):
        raise ValueError("output_config must be an object.")
    effort = resolve_effort(spec, output_config.get("effort", "max"))
    max_tokens = payload.get("max_tokens", spec["output"])
    if isinstance(max_tokens, bool) or not isinstance(max_tokens, int) or max_tokens < 1:
        raise ValueError("max_tokens must be a positive integer.")
    payload["model"] = model
    payload["max_tokens"] = min(max_tokens, spec["output"])
    output_config = dict(output_config)
    if spec["protocol"] != "messages":
        # Use adaptive thinking only on the local translator's input. Its output
        # policy below supplies the provider's actual thinking and effort fields.
        output_config["effort"] = effort
        payload["thinking"] = {"type": "adaptive"}
    elif spec["mode"] == "effort":
        output_config["effort"] = effort
        payload["thinking"] = {"type": "enabled"} if model.startswith("qwen") else {"type": "adaptive"}
    else:
        output_config.pop("effort", None)
        if spec["mode"] == "always":
            payload.pop("thinking", None)
        elif spec["mode"] == "budget":
            # Alibaba's Messages adapter fits thinking inside the response cap.
            payload["thinking"] = {"type": "enabled", "budget_tokens": min(
                spec["thinking_budget"], payload["max_tokens"] - 1)}
        else:
            payload["thinking"] = {"type": "adaptive"}
    if output_config:
        payload["output_config"] = output_config
    else:
        payload.pop("output_config", None)
    return payload, spec


def build_config(models, upstream, upstream_key, client_key, session, port, auth_dir, gateway_port):
    chat_groups, overrides, filters = {}, [], []
    providers = {"xai": [], "codex": [], "gemini": []}
    headers = {"User-Agent": USER_AGENT, "x-opencode-session": session}
    for model, spec in models.items():
        if spec["protocol"] == "messages":
            continue
        entry = {"name": model, "alias": model, "is-compat": True,
                 "max-context-length": spec["context"],
                 "thinking": {"levels": spec["efforts"] or ["max"]}}
        if spec["protocol"] != "chat":
            provider = spec["proxy_provider"]
            base = upstream + "/v1"
            key = upstream_key
            if provider == "gemini":
                # Native CLIProxyAPI uses v1beta; Go serves Google's API at v1.
                # Route through the authenticated gateway to rewrite the path.
                base = f"http://127.0.0.1:{gateway_port}/_go/google"
                key = client_key
            elif spec["protocol"] == "responses":
                # Codex replaces custom user-agent headers. The relay supplies
                # our actual coding-agent identity and Go session on every call.
                base = f"http://127.0.0.1:{gateway_port}/_go/openai/v1"
                key = client_key
            providers[provider].append({"api-key": key, "base-url": base,
                                         "headers": headers, "models": [entry]})
            continue
        api_path = spec.get("api_path", "/v1")
        chat_groups.setdefault(api_path, []).append(entry)
        selector = [{"name": model, "protocol": "openai"}]
        if spec.get("chat_params"):
            overrides.append({"models": selector, "params": spec["chat_params"]})
        params = []
        if not spec["efforts"]:
            params.append("reasoning_effort")
        if spec.get("filter_sampling"):
            params += ["temperature", "top_p"]
        if spec.get("filter_thinking"):
            params.append("thinking")
        if params:
            filters.append({"models": selector, "params": params})
    return {"host": "127.0.0.1", "port": port, "auth-dir": str(auth_dir),
            "api-keys": [client_key], "remote-management": {"allow-remote": False, "secret-key": "",
                                                           "disable-control-panel": True},
            "debug": False, "logging-to-file": False, "request-log": False,
            "error-logs-max-files": 1, "usage-statistics-enabled": False,
            "request-retry": 0, "max-retry-credentials": 1,
            "openai-compatibility": [{"name": "opencode-go" if api_path == "/v1" else
                "opencode-go-" + api_path.strip("/").replace("/", "-"),
                "base-url": upstream + api_path,
                "headers": headers,
                "api-key-entries": [{"api-key": upstream_key}], "models": entries}
                for api_path, entries in chat_groups.items()],
            "xai-api-key": providers["xai"], "codex-api-key": providers["codex"],
            "gemini-api-key": providers["gemini"],
            "payload": {"override": overrides, "filter": filters}}


def clean_environment(env):
    return {key: value for key, value in env.items()
            if key not in ("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "OPENCODE_GO_API_KEY")}


def unused_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def proxy_binary():
    configured = os.environ.get("OPENCODE_GO_PROXY_BIN")
    binary = shutil.which(configured) if configured else (shutil.which("cliproxyapi") or shutil.which("cli-proxy-api"))
    if not binary:
        raise ValueError("CLIProxyAPI is required. Install it and put cliproxyapi on PATH.")
    result = subprocess.run([binary, "-h"], capture_output=True, text=True,
                            timeout=10, env=clean_environment(os.environ))
    match = re.search(r"Version:\s*v?(\d+)\.(\d+)\.(\d+)", result.stdout + result.stderr)
    if not match or tuple(map(int, match.groups())) < (7, 2, 130):
        raise ValueError("OpenCode Go requires CLIProxyAPI 7.2.130 or later.")
    return binary


class Gateway(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, models, upstream, upstream_key, client_key, session, proxy_port):
        super().__init__(("127.0.0.1", 0), Handler)
        self.models, self.upstream, self.upstream_key = models, upstream, upstream_key
        self.client_key, self.session, self.proxy_port = client_key, session, proxy_port


class Handler(http.server.BaseHTTPRequestHandler):
    # Closing each response avoids buffering SSE or relaying hop-by-hop headers.
    protocol_version = "HTTP/1.0"

    def log_message(self, *_args):
        pass

    def authenticated(self):
        received = self.headers.get("Authorization", "")
        if self.path.startswith("/_go/google/"):
            received = "Bearer " + self.headers.get("x-goog-api-key", "")
        return hmac.compare_digest(received.encode(), ("Bearer " + self.server.client_key).encode())

    def send_json(self, status, content):
        body = json.dumps(content).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def error(self, status, message):
        self.send_json(status, {"type": "error", "error": {"type": "invalid_request_error", "message": message}})

    def do_GET(self):
        if not self.authenticated():
            return self.error(401, "Invalid local gateway credential.")
        if self.path.split("?", 1)[0] != "/v1/models":
            return self.error(404, "Unsupported endpoint.")
        entries = [{"id": model, "object": "model", "type": "model", "owned_by": "opencode-go",
                    "display_name": spec["name"], "created_at": "2026-10-14T00:00:00Z",
                    "max_input_tokens": spec.get("input", spec["context"]), "max_output_tokens": spec["output"],
                    "context_window": spec["context"], "supported_effort_levels": spec["efforts"]}
                   for model, spec in self.server.models.items()]
        self.send_json(200, {"data": entries, "has_more": False,
                             "first_id": entries[0]["id"], "last_id": entries[-1]["id"]})

    def do_POST(self):
        if not self.authenticated():
            return self.error(401, "Invalid local gateway credential.")
        if self.path.startswith("/_go/google/"):
            return self.forward_google()
        if self.path.split("?", 1)[0] == "/_go/openai/v1/responses":
            return self.forward_responses()
        if self.path.split("?", 1)[0] != "/v1/messages":
            return self.error(404, "Unsupported endpoint.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 64 * 1024 * 1024:
                raise ValueError("Invalid request size.")
            payload, spec = normalize_request(json.loads(self.rfile.read(length)), self.server.models)
        except (ValueError, TypeError):
            return self.error(400, "Invalid model, effort, or Messages request. Run go-claude --list-models.")
        if spec["protocol"] != "messages":
            target = f"http://127.0.0.1:{self.server.proxy_port}"
            key = self.server.client_key
        else:
            target, key = self.server.upstream, self.server.upstream_key
        path = spec.get("api_path", "/v1") + "/messages" if spec["protocol"] == "messages" else "/v1/messages"
        self.relay(target, path, json.dumps(payload).encode(), key)

    def forward_google(self):
        path = urlsplit(self.path)
        prefix = "/_go/google/v1beta/models/"
        if not path.path.startswith(prefix):
            return self.error(404, "Unsupported Google bridge endpoint.")
        model, separator, action = path.path[len(prefix):].partition(":")
        spec = self.server.models.get(model, {})
        if not separator or spec.get("protocol") != "google" or action not in ("generateContent", "streamGenerateContent", "countTokens"):
            return self.error(404, "Unsupported Google model or action.")
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 64 * 1024 * 1024:
                raise ValueError
            body = self.rfile.read(length)
            if not isinstance(json.loads(body), dict):
                raise ValueError
        except (ValueError, TypeError):
            return self.error(400, "Invalid Google request.")
        destination = "/v1/models/" + model + ":" + action
        if path.query == "alt=sse":
            destination += "?alt=sse"
        self.relay(self.server.upstream, destination, body, self.server.upstream_key)

    def forward_responses(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 64 * 1024 * 1024:
                raise ValueError
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError
            spec = self.server.models.get(body.get("model"), {})
            if spec.get("protocol") != "responses":
                raise ValueError
            maximum = min(spec["output"], int(os.environ.get("CLAUDE_CODE_MAX_OUTPUT_TOKENS", spec["context"] // 4)))
            requested = body.get("max_output_tokens", maximum)
            if isinstance(requested, bool) or not isinstance(requested, int) or requested < 1:
                raise ValueError
            body["max_output_tokens"] = min(requested, maximum)
        except (ValueError, TypeError):
            return self.error(400, "Invalid Responses request.")
        self.relay(self.server.upstream, "/v1/responses", json.dumps(body).encode(), self.server.upstream_key)

    def relay(self, target, path, body, key):
        url = urlsplit(target)
        connection_class = http.client.HTTPSConnection if url.scheme == "https" else http.client.HTTPConnection
        connection = connection_class(url.hostname, url.port, timeout=600)
        headers = {"Content-Type": "application/json", "Authorization": "Bearer " + key,
                   "User-Agent": USER_AGENT, "anthropic-version": "2023-06-01",
                   "x-opencode-session": self.server.session}
        for name in ("anthropic-beta", "x-claude-code-session-id"):
            if name in self.headers:
                headers[name] = self.headers[name]
        started = False
        try:
            connection.request("POST", url.path.rstrip("/") + path, body=body, headers=headers)
            response = connection.getresponse()
            self.send_response(response.status)
            self.send_header("Content-Type", response.getheader("Content-Type", "application/json"))
            for name in ("request-id", "retry-after", "x-request-id"):
                if response.getheader(name):
                    self.send_header(name, response.getheader(name))
            self.end_headers()
            started = True
            while True:
                chunk = response.read1(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (OSError, http.client.HTTPException):
            if not started:
                self.error(502, "OpenCode Go upstream request failed.")
        finally:
            connection.close()


def wait_for_proxy(process, port, key):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if process.poll() is not None:
            break
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=0.3)
        try:
            connection.request("GET", "/v1/models", headers={"Authorization": "Bearer " + key})
            response = connection.getresponse()
            if response.status == 200 and json.loads(response.read()).get("data"):
                return
        except (OSError, ValueError, http.client.HTTPException):
            pass
        finally:
            connection.close()
        time.sleep(0.05)
    raise ValueError("The isolated CLIProxyAPI could not start. Check the installed version and local ports.")


@contextlib.contextmanager
def running_gateway(models, upstream, upstream_key, binary):
    upstream = upstream.rstrip("/")
    parsed = urlsplit(upstream)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.query or parsed.fragment:
        raise ValueError("OPENCODE_GO_BASE_URL must be an HTTP(S) base URL without credentials/query/fragment.")
    if not upstream_key or any(char.isspace() for char in upstream_key):
        raise ValueError("Invalid Go credential.")
    client_key, session = secrets.token_urlsafe(32), str(uuid.uuid4())
    with tempfile.TemporaryDirectory(prefix="opencode-go-") as directory:
        root = Path(directory)
        auth_dir = root / "auth"
        auth_dir.mkdir(mode=0o700)
        port = unused_port()
        gateway = Gateway(models, upstream, upstream_key, client_key, session, port)
        thread = threading.Thread(target=gateway.serve_forever, daemon=True)
        thread.start()
        process = None
        try:
            config = build_config(models, upstream, upstream_key, client_key, session, port, auth_dir, gateway.server_port)
            config_path = root / "config.json"
            with open(config_path, "x", opener=lambda path, flags: os.open(path, flags, 0o600)) as stream:
                json.dump(config, stream)
            process = subprocess.Popen([binary, "-config", str(config_path), "-local-model"], cwd=root,
                                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       env=clean_environment(os.environ), start_new_session=True)
            wait_for_proxy(process, port, client_key)
            yield gateway
        finally:
            if gateway:
                gateway.shutdown()
                gateway.server_close()
            if process:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def main(argv):
    if sys.version_info < (3, 9):
        raise ValueError("Python 3.9+ is required.")
    models = load_models()
    if argv[:1] == ["describe"] and len(argv) == 3:
        model, spec = model_settings(argv[1], models)
        resolve_effort(spec, argv[2])
        print(model, spec["context"], spec["output"])
        return 0
    if argv == ["list"]:
        print(f"{'Model':30} {'API':10} {'Effort levels':26} {'Highest':14} Context")
        for model, spec in models.items():
            levels = ",".join(spec["efforts"]) or spec["mode"]
            highest = spec["default_effort"] if spec["efforts"] else "thinking on"
            if spec["mode"] == "budget":
                highest = "budget:" + str(min(spec["thinking_budget"], min(spec["output"], spec["context"] // 4) - 1))
            note = " [trains on requests]" if spec.get("training") else ""
            print(f"{model:30} {spec['protocol']:10} {levels:26} {highest:14} {spec['context']}{note}")
        return 0
    if argv[:1] != ["--"] or len(argv) < 2:
        raise ValueError("Use go-claude or go-claude --list-models.")
    upstream = os.environ.get("OPENCODE_GO_BASE_URL", "https://opencode.ai/inference/go")
    key = os.environ.get("ANTHROPIC_AUTH_TOKEN", "")
    binary = proxy_binary()
    children = []

    def terminate(_signum, _frame):
        for child in children:
            if child.poll() is None:
                child.terminate()
        raise KeyboardInterrupt

    previous = signal.signal(signal.SIGTERM, terminate)
    try:
        with running_gateway(models, upstream, key, binary) as gateway:
            env = clean_environment(os.environ)
            env["ANTHROPIC_BASE_URL"] = f"http://127.0.0.1:{gateway.server_port}"
            env["ANTHROPIC_AUTH_TOKEN"] = gateway.client_key
            child = subprocess.Popen(argv[1:], env=env)
            children.append(child)
            # Ctrl-C belongs to Claude's interactive UI. A Python signal handler
            # resets to default in exec children, unlike inheriting SIG_IGN.
            previous_int = signal.signal(signal.SIGINT, lambda *_args: None)
            try:
                return child.wait()
            finally:
                signal.signal(signal.SIGINT, previous_int)
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        # Never include subprocess output, HTTP bodies, or credentials here.
        print("go-claude: " + (str(error) if isinstance(error, ValueError) else "local proxy/Claude process failed."), file=sys.stderr)
        sys.exit(2)
