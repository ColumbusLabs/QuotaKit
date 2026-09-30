#!/usr/bin/env python3
"""Exercise test entrypoints with fake processes, recording names only, never values."""

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
SECRET_NAMES = [
    "QK_FIXTURE_TOKEN", "QK_FIXTURE_API_KEY", "QK_FIXTURE_SECRET",
    "QK_FIXTURE_PASSWORD", "QK_FIXTURE_PASSWD", "QK_FIXTURE_WEBHOOK",
    "QK_FIXTURE_CREDENTIAL", "QK_FIXTURE_COOKIE", "QK_FIXTURE_PRIVATE",
    "QK_FIXTURE_PAT", "CODEXBAR_FIXTURE_TOKEN", "qk_fixture_token",
]
DARWIN_LOADER_NAMES = {"DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH"}
ALLOW_NAMES = [
    "CI", "CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT", "LD_LIBRARY_PATH",
    "DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH", "LIBRARY_PATH", "PKG_CONFIG_PATH",
]


def main():
    with tempfile.TemporaryDirectory(prefix="quotakit-test-environment-") as directory:
        temp = Path(directory)
        log = temp / "observations.jsonl"
        # The fake executable reports only name presence and invocation arguments.
        # Absolute interpreter avoids recursion through the fake python3 entrypoint.
        import sys
        fake = f"#!{sys.executable}\n" + '''import json, os, sys
names = json.loads(os.environ["QK_ENV_FIXTURE_NAMES"])
record = {"process": os.path.basename(sys.argv[0]), "args": sys.argv[1:],
          "present": {name: name in os.environ for name in names}}
with open(os.environ["QK_ENV_FIXTURE_LOG"], "a") as stream:
    stream.write(json.dumps(record) + "\\n")
sys.exit(int(os.environ.get("QK_ENV_FIXTURE_EXIT", "0")))
'''
        for name in ["swift", "python3"]:
            executable = temp / name
            executable.write_text(fake)
            executable.chmod(0o755)
        observed = SECRET_NAMES + ALLOW_NAMES + [
            "CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS", "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS",
            "CODEXBAR_TEST_CODEX_FILE_ISOLATION", "CODEXBAR_TEST_SESSION_FILE_ISOLATION",
            "CODEXBAR_TEST_CODEX_FILE_FIXTURES", "LIVE_TEST",
        ]
        env = {"PATH": str(temp) + os.pathsep + os.environ.get("PATH", ""),
               "HOME": str(temp), "QK_ENV_FIXTURE_LOG": str(log),
               "QK_ENV_FIXTURE_NAMES": json.dumps(observed)}
        env.update({name: "synthetic" for name in SECRET_NAMES + ALLOW_NAMES})
        env["CODEXBAR_TEST_CODEX_FILE_FIXTURES"] = "synthetic"

        def check(command, live=False, exit_code=0, expected_process="swift"):
            log.write_text("")
            current = env | {"QK_ENV_FIXTURE_EXIT": str(exit_code)}
            result = subprocess.run(command, cwd=ROOT, env=current, capture_output=True, text=True)
            # Make maps a child failure to its own nonzero status.
            assert (result.returncode == 0) == (exit_code == 0), "Entrypoint lost process status"
            rows = [json.loads(line) for line in log.read_text().splitlines()]
            assert rows, "Entrypoint did not execute fake process"
            for row in rows:
                assert row["process"] == expected_process
                presence = row["present"]
                assert not any(presence[name] for name in SECRET_NAMES), "Secret-shaped name survived"
                # macOS strips DYLD variables when launching system Bash; verify those in-shell below.
                expected_allow = [name for name in ALLOW_NAMES
                                  if not (sys.platform == "darwin" and name in DARWIN_LOADER_NAMES)]
                assert all(presence[name] for name in expected_allow), "Documented non-secret control lost"
                assert presence["CODEXBAR_TEST_CODEX_FILE_ISOLATION"]
                assert presence["CODEXBAR_TEST_SESSION_FILE_ISOLATION"]
                assert not presence["CODEXBAR_TEST_CODEX_FILE_FIXTURES"]
                assert presence["CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] == live
                assert presence["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] != live
            return rows

        loader_check = (
            "export DYLD_LIBRARY_PATH=synthetic DYLD_FRAMEWORK_PATH=synthetic; "
            "source Scripts/test_environment.sh; "
            '[[ "${DYLD_LIBRARY_PATH+x}" == x && "${DYLD_FRAMEWORK_PATH+x}" == x ]]')
        subprocess.run(["bash", "-c", loader_check], cwd=ROOT, env=env, check=True)
        rows = check(["bash", "Scripts/test.sh", "--skip-build", "--filter", "FixtureSuite"],
                     expected_process="python3")
        assert rows[0]["args"][-3:] == ["--skip-build", "--filter", "FixtureSuite"]
        check(["bash", "Scripts/test.sh", "--skip-build"], exit_code=17, expected_process="python3")
        assert len(check(["bash", "Scripts/test-plugin-engines.sh"])) == 2
        check(["bash", "Scripts/test-plugin-engines.sh"], exit_code=17)
        for target, live in [("test-tty", False), ("test-live", True)]:
            rows = check(["make", "--no-print-directory", target], live=live)
            assert rows[0]["args"] == ["test", "--filter",
                                       "LiveAccountTests" if live else "TTYIntegrationTests"]
            assert rows[0]["present"]["LIVE_TEST"] == live
            check(["make", "--no-print-directory", target], live=live, exit_code=17)
        check(["bash", "-c", "source Scripts/test_environment.sh; swift test --filter CodexBarLinuxTests"])
    print("Test environment entrypoint fixtures passed (fake processes; no credentials or SwiftPM).")


if __name__ == "__main__":
    main()
