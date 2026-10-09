#!/usr/bin/env python3
"""Verify repeated synthetic Codex RPC refreshes do not retain serve output pipes."""

import json
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request


def main():
    binary = pathlib.Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="quotakit-rpc-pipe-proof-") as directory:
        root = pathlib.Path(directory)
        home = root / "home"
        home.mkdir()
        stub = root / "codex"
        stub.write_text('''#!/usr/bin/python3
import json, sys
if "--version" in sys.argv:
    print("codex-cli 1.0.0")
    sys.exit(0)
for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    if request.get("method") == "account/rateLimits/read":
        result = {"rateLimits": {"primary": {
            "usedPercent": 12, "windowDurationMins": 300, "resetsAt": 1791500000}}}
    elif request.get("method") == "account/read":
        result = {"account": {"type": "chatgpt", "email": "fixture@example.test", "planType": "pro"},
                  "requiresOpenaiAuth": False}
    else:
        result = {}
    print(json.dumps({"id": request["id"], "result": result}), flush=True)
''')
        stub.chmod(0o755)
        config = root / "config.json"
        config.write_text(json.dumps({"version": 1, "providers": [{"id": "codex", "enabled": True, "source": "cli"}]}))
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        environment = {
            "PATH": "/usr/bin:/bin",
            "HOME": str(home),
            "CFFIXED_USER_HOME": str(home),
            "XDG_DATA_HOME": str(home / ".local/share"),
            "CODEX_HOME": str(home / ".codex"),
            "QUOTAKIT_CONFIG": str(config),
            "CODEX_CLI_PATH": str(stub),
            "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
            "CODEXBAR_DISABLE_KEYCHAIN_ACCESS": "1",
            "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
            "CODEXBAR_TEST_CODEX_FILE_ISOLATION": "1",
            "CODEXBAR_TEST_CODEX_FILE_FIXTURES": json.dumps({"grants": [
                {"url": root.as_uri(), "resolvedURL": root.as_uri(), "isRoot": True},
            ]}),
        }
        with (root / "server.log").open("w") as log:
            child = subprocess.Popen(
                [str(binary), "serve", "--port", str(port), "--refresh-interval", "0"],
                env=environment,
                stdout=log,
                stderr=log,
            )

            def get(path):
                with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=45) as response:
                    assert response.status == 200
                    return json.load(response)

            def pipes():
                values = set()
                for descriptor in pathlib.Path(f"/proc/{child.pid}/fd").iterdir():
                    try:
                        value = os.readlink(descriptor)
                    except FileNotFoundError:
                        continue
                    if value.startswith("pipe:"):
                        values.add(value)
                return values

            try:
                deadline = time.monotonic() + 30
                while True:
                    try:
                        assert get("/health")["status"] == "ok"
                        break
                    except OSError:
                        assert child.poll() is None and time.monotonic() < deadline
                        time.sleep(0.1)
                initial = pipes()
                for _ in range(60):
                    payload = get("/usage?provider=codex")
                    assert len(payload) == 1 and payload[0]["provider"] == "codex"
                    assert payload[0].get("usage", {}).get("primary", {}).get("usedPercent") == 12, \
                        "synthetic RPC usage was not returned"
                deadline = time.monotonic() + 10
                remaining = pipes() - initial
                while remaining and time.monotonic() < deadline:
                    time.sleep(0.05)
                    remaining = pipes() - initial
                assert get("/health")["status"] == "ok"
                print(json.dumps({
                    "rpc_fetches": 60,
                    "initial_pipes": len(initial),
                    "retained_pipe_growth": len(remaining),
                    "health": 200,
                }), flush=True)
                assert not remaining, "RPC refreshes retained output pipes"
            finally:
                child.terminate()
                try:
                    child.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_linux_serve_rpc_pipes.py /path/to/CodexBarCLI")
    main()
