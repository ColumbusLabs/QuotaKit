#!/usr/bin/env python3
"""Exercise the Swift test runner's owned process-group timeout cleanup."""

from __future__ import annotations

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch

import ci_swift_test_by_suite as runner

FIXTURE_SCRIPT_PATH = str(Path(__file__).resolve())


def wait_until(predicate, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() >= deadline:
            raise AssertionError("condition did not become true within its bound")
        time.sleep(0.01)


def process_is_absent(pid: int) -> bool:
    result = subprocess.run(
        ["ps", "-o", "stat=", "-p", str(pid)],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode != 0 or not result.stdout.strip()


def fixture(mode: str, directory: str) -> None:
    root = Path(directory)
    if mode == "child":
        def on_term(_signum, _frame):
            (root / "child-term").touch()
            raise SystemExit(0)

        signal.signal(signal.SIGTERM, on_term)
        (root / "child.pid").write_text(str(os.getpid()))
        (root / "child.ready").touch()
        while True:
            time.sleep(0.05)

    def on_parent_term(_signum, _frame):
        (root / "parent-term").touch()

    signal.signal(signal.SIGTERM, on_parent_term)
    (root / "parent.pid").write_text(str(os.getpid()))
    child = subprocess.Popen([sys.executable, FIXTURE_SCRIPT_PATH, "--fixture", "child", directory])
    wait_until(lambda: (root / "child.ready").exists(), timeout=5)
    (root / "parent.ready").touch()
    wait_until(lambda: (root / "parent-term").exists(), timeout=10)
    child.wait(timeout=5)
    (root / "child-reaped").touch()
    while True:
        time.sleep(0.05)


@unittest.skipUnless(os.name == "posix", "requires POSIX process groups")
class ProcessGroupCleanupTests(unittest.TestCase):
    def test_timeout_escalates_from_term_to_kill_and_reaps_the_process_tree(self):
        with tempfile.TemporaryDirectory(prefix="quotakit-test-process-cleanup-") as directory:
            root = Path(directory)
            actual_popen = subprocess.Popen
            actual_killpg = os.killpg
            created_processes = []
            sent_signals = []

            class FastGraceProcess:
                def __init__(self, command, **kwargs):
                    self.process = actual_popen(command, **kwargs)
                    self.wait_count = 0
                    created_processes.append(self)
                    wait_until(lambda: (root / "parent.ready").exists(), timeout=5)

                def wait(self, timeout=None):
                    self.wait_count += 1
                    if self.wait_count == 2:
                        if timeout != 10:
                            raise AssertionError(f"runner TERM grace changed unexpectedly: {timeout}")
                        # The runner's ten-second grace remains unchanged; fast-forward its expiry
                        # only after TERM reached the parent and the child exited and was reaped.
                        wait_until(lambda: (root / "child-reaped").exists(), timeout=5)
                        if self.process.poll() is not None:
                            raise AssertionError("the fixture parent exited before KILL escalation")
                        raise subprocess.TimeoutExpired(self.process.args, timeout)
                    return self.process.wait(timeout=timeout)

                def __getattr__(self, name):
                    return getattr(self.process, name)

            def send_group_signal(pgid, sig):
                sent_signals.append(sig)
                actual_killpg(pgid, sig)

            try:
                runner_subprocess = types.SimpleNamespace(
                    Popen=FastGraceProcess,
                    TimeoutExpired=subprocess.TimeoutExpired,
                )
                with (
                    patch.object(runner, "subprocess", runner_subprocess),
                    patch.object(runner.os, "killpg", side_effect=send_group_signal),
                ):
                    result = runner.run_command(
                        [sys.executable, FIXTURE_SCRIPT_PATH, "--fixture", "parent", directory],
                        timeout=1,
                    )

                self.assertEqual(result, 124)
                self.assertEqual(sent_signals, [signal.SIGTERM, signal.SIGKILL])
                self.assertTrue((root / "parent-term").exists())
                self.assertTrue((root / "child-term").exists())
                self.assertTrue((root / "child-reaped").exists())
                self.assertEqual(created_processes[0].returncode, -signal.SIGKILL)

                pids = [int((root / name).read_text()) for name in ("parent.pid", "child.pid")]
                wait_until(lambda: all(process_is_absent(pid) for pid in pids), timeout=5)
            finally:
                if created_processes:
                    process = created_processes[0].process
                    if process.poll() is None:
                        try:
                            actual_killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait(timeout=5)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--fixture":
        fixture(sys.argv[2], sys.argv[3])
    else:
        unittest.main()
