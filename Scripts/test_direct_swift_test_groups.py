#!/usr/bin/env python3
import json
import io
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import ci_swift_test_by_suite as runner
from direct_swift_test_groups import InventoryMismatch, checked, pool_timeout, prepare_runtime, run_pool, run_worker, runtime_environment, selected_tests, xctest_inventory


class DirectSwiftTestGroupsTests(unittest.TestCase):
    def test_xctest_inventory_keeps_exact_method_identifiers(self):
        value = {"tests": [{"name": "All tests", "tests": [
            {"name": "CodexBarTests.ExampleTests", "tests": [{"name": "testFirst"}, {"name": "testSecond"}]}
        ]}]}
        self.assertEqual(xctest_inventory(value), ["CodexBarTests.ExampleTests/testFirst",
                                                  "CodexBarTests.ExampleTests/testSecond"])

    def test_group_filters_preserve_suite_and_top_level_selections(self):
        inventory = ["CodexBarTests.ExampleTests/testFirst", "CodexBarTests.OtherTests/testFirst",
                     "CodexBarTests.`top level test`()"]
        selections = [{"name": "CodexBarTests.ExampleTests", "suite_name": "CodexBarTests.ExampleTests",
                       "filter_pattern": r"^CodexBarTests\.ExampleTests/"}]
        self.assertEqual(selected_tests(inventory, selections), inventory[:1])
        selections.append({"name": "top level test", "suite_name": None,
                           "filter_pattern": r"CodexBarTests\..*top\ level\ test"})
        self.assertEqual(selected_tests(inventory, selections), [inventory[0], inventory[2]])

    def test_worker_environment_isolates_home_and_suppresses_keychain(self):
        developer = Path("/synthetic/Xcode/Contents/Developer")
        sdk = developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        with patch.dict(os.environ, {"HOME": "/synthetic/real-home", "CODEX_HOME": "/synthetic/real-home/.codex",
                                     "CODEX_SQLITE_HOME": "/synthetic/external-codex-sqlite",
                                     "CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS": "1",
                                     "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "0",
                                     "CODEXBAR_TEST_CODEX_FILE_FIXTURES": "inherited"}):
            environment = runtime_environment(developer, Path("/synthetic/group"), sdk)
        self.assertEqual(environment["CFFIXED_USER_HOME"], "/synthetic/group")
        self.assertEqual(environment["HOME"], "/synthetic/group")
        self.assertEqual(environment["CODEX_HOME"], "/synthetic/group/.codex")
        self.assertNotIn("CODEX_SQLITE_HOME", environment)
        self.assertIn(str(sdk / "System/Library/PrivateFrameworks"), environment["DYLD_FRAMEWORK_PATH"])
        self.assertIn(
            str(developer / "Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks"),
            environment["DYLD_FRAMEWORK_PATH"],
        )
        self.assertEqual(environment["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"], "1")
        self.assertNotIn("CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS", environment)
        self.assertNotIn("CODEXBAR_TEST_CODEX_FILE_FIXTURES", environment)

    def test_runtime_prefers_selected_sdk_frameworks_and_keeps_inherited_paths(self):
        with patch.dict(os.environ, {"DYLD_FRAMEWORK_PATH": "/synthetic/override"}, clear=True):
            environment = runtime_environment(
                Path("/synthetic/Developer"), Path("/synthetic/home"), Path("/synthetic/SDK")
            )
        self.assertEqual(environment["DYLD_FRAMEWORK_PATH"].split(":"), [
            "/synthetic/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks",
            "/synthetic/SDK/System/Library/PrivateFrameworks",
            "/synthetic/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks",
            "/synthetic/override",
        ])

    def test_failed_probe_names_helper_signal_and_redacts_stderr(self):
        output = io.StringIO()
        result = SimpleNamespace(returncode=-5, stdout="", stderr="dyld: missing framework; synthetic-secret")
        with patch("direct_swift_test_groups.subprocess.run", return_value=result), \
                patch("sys.stderr", output), patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, r"swiftpm-xctest-helper.*SIGTRAP"):
                checked(["/synthetic/swiftpm-xctest-helper"], {"API_TOKEN": "synthetic-secret"})
        self.assertIn("dyld: missing framework", output.getvalue())
        self.assertNotIn("synthetic-secret", output.getvalue())

    def test_crash_reports_are_fresh_process_scoped_and_redacted(self):
        from swift_test_diagnostics import print_crash_reports
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fresh = root / "swiftpm-xctest-helper-fresh.ips"
            fresh.write_text('Termination Reason: DYLD; synthetic-secret')
            old = root / "swiftpm-xctest-helper-old.crash"
            old.write_text("stale report must be excluded")
            os.utime(old, (1, 1))
            (root / "Unrelated-fresh.ips").write_text("unrelated report must be excluded")
            output = io.StringIO()
            with patch("sys.stderr", output), patch.dict(os.environ, {"API_TOKEN": "synthetic-secret"}, clear=True):
                self.assertEqual(print_crash_reports([root], 2), 1)
            self.assertIn("Termination Reason: DYLD", output.getvalue())
            for private in ["synthetic-secret", "stale report", "unrelated report"]:
                self.assertNotIn(private, output.getvalue())

    def test_diagnostics_redact_escaped_credentials_but_keep_nonsecret_controls(self):
        from swift_test_diagnostics import redact
        environment = {"API_TOKEN": 'synthetic-"secret"', "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1"}
        output = redact(json.dumps(environment) + " /Users/synthetic/Library test 1", environment)
        self.assertNotIn("secret", output)
        self.assertNotIn("/Users/synthetic/", output)
        self.assertIn("test 1", output)

    def test_worker_shares_deadline_across_frameworks_and_uses_exact_xctest_ids(self):
        group = [{"name": "ExampleTests", "suite_name": "ExampleTests", "filter_pattern": r"^ExampleTests/"}]
        runtime = {"developer": "/synthetic/Developer", "sdk": "/synthetic/SDK", "xctest": "synthetic-xctest",
                   "testing_helper": "synthetic-testing", "products": [{"bundle": "synthetic-bundle",
                   "binary": "synthetic-binary", "xctest": ["ExampleTests/testOne", "OtherTests/testTwo"],
                   "swift": ["ExampleTests/swiftTest()"]}]}
        calls = []
        def execute(command, timeout, **_kwargs):
            calls.append((command, timeout, os.environ["CFFIXED_USER_HOME"], os.environ["CODEX_HOME"],
                          os.environ["SWIFT_TESTING_ENABLED"]))
            return 0
        with patch.dict(os.environ), patch("direct_swift_test_groups.run_command", side_effect=execute), \
                patch("direct_swift_test_groups.time.monotonic", side_effect=[10, 12, 17]):
            result = run_worker({"runtime": runtime, "groups": [group], "timeout": 10}, 0)
        self.assertEqual(result, 0)
        self.assertEqual(calls[0][0], ["synthetic-xctest", "-XCTest", "ExampleTests/testOne", "synthetic-bundle"])
        self.assertEqual([call[1] for call in calls], [8, 3])
        self.assertEqual([call[4] for call in calls], ["0", "1"])
        self.assertEqual(calls[0][2], calls[1][2])
        self.assertEqual(calls[0][3], str(Path(calls[0][2]) / ".codex"))
        self.assertEqual(calls[0][3], calls[1][3])
        self.assertFalse(Path(calls[0][2]).exists())
        self.assertFalse(Path(calls[0][3]).exists())

    def test_worker_preserves_failure_after_running_other_frameworks(self):
        group = [{"name": "ExampleTests", "suite_name": "ExampleTests", "filter_pattern": r"^ExampleTests/"}]
        runtime = {"developer": "/synthetic/Developer", "xctest": "synthetic-xctest",
                   "testing_helper": "synthetic-testing", "products": [{"bundle": "synthetic-bundle",
                   "binary": "synthetic-binary", "xctest": ["ExampleTests/testOne"],
                   "swift": ["ExampleTests/swiftTest()"]}]}
        for codes in [[42, 0], [42, 23], [0, 23], [0, 124], [42, 124]]:
            with self.subTest(codes=codes), patch.dict(os.environ), \
                    patch("direct_swift_test_groups.run_command", side_effect=codes) as execute:
                self.assertEqual(run_worker({"runtime": runtime, "groups": [group], "timeout": 10}, 0),
                                 124 if 124 in codes else codes[0] or codes[1])
                self.assertEqual(execute.call_count, 2)

    def test_worker_sigterm_cleans_active_test_process_group(self):
        group = [{"name": "ExampleTests", "suite_name": "ExampleTests", "filter_pattern": r"^ExampleTests/"}]
        runtime = {"developer": "/synthetic/Developer", "sdk": "/synthetic/SDK", "xctest": "synthetic-xctest",
                   "testing_helper": "synthetic-testing", "products": [{"bundle": "synthetic-bundle",
                   "binary": "synthetic-binary", "xctest": ["ExampleTests/testOne"], "swift": []}]}
        terminated_groups = []
        test_case = self

        class InterruptedWaitProcess:
            pid = 4321

            def __init__(self):
                self.wait_active = False
                self.wait_count = 0
                self.poll_count = 0

            def wait(self, timeout=None):
                self.wait_count += 1
                if self.wait_count == 1:
                    self.wait_active = True
                    try:
                        signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
                    finally:
                        self.wait_active = False
                return -signal.SIGTERM

            def poll(self):
                test_case.assertFalse(self.wait_active, "process polling must wait until Popen.wait unwinds")
                self.poll_count += 1
                return -signal.SIGTERM

        process = InterruptedWaitProcess()

        def killpg(process_group_id, sig):
            if sig == 0:
                raise ProcessLookupError
            terminated_groups.append((process_group_id, sig))

        with patch.dict(os.environ), \
                patch("ci_swift_test_by_suite.subprocess.Popen", return_value=process), \
                patch("direct_swift_test_groups.os.killpg", side_effect=killpg), \
                patch("ci_swift_test_by_suite.terminate_process_group", wraps=runner.terminate_process_group) as cleanup:
            result = run_worker({"runtime": runtime, "groups": [group], "timeout": 10}, 0)

        self.assertEqual(cleanup.call_args.kwargs["grace_seconds"], 5)
        self.assertEqual(result, 128 + signal.SIGTERM)
        self.assertEqual(terminated_groups, [(4321, signal.SIGTERM)])
        self.assertEqual(process.wait_count, 2)
        self.assertGreater(process.poll_count, 0)

    def test_worker_records_sigterm_during_spawn_then_cleans_registered_process(self):
        group = [{"name": "ExampleTests", "suite_name": "ExampleTests", "filter_pattern": r"^ExampleTests/"}]
        runtime = {"developer": "/synthetic/Developer", "sdk": "/synthetic/SDK", "xctest": "synthetic-xctest",
                   "testing_helper": "synthetic-testing", "products": [{"bundle": "synthetic-bundle",
                   "binary": "synthetic-binary", "xctest": ["ExampleTests/testOne"], "swift": []}]}
        process = SimpleNamespace(pid=4321, poll=Mock(return_value=-signal.SIGTERM), wait=Mock(return_value=0))
        sent_signals = []

        def spawn(*_args, **_kwargs):
            signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
            return process

        def killpg(process_group_id, sig):
            if sig == 0:
                raise ProcessLookupError
            sent_signals.append((process_group_id, sig))

        with patch.dict(os.environ), \
                patch("ci_swift_test_by_suite.subprocess.Popen", side_effect=spawn), \
                patch("ci_swift_test_by_suite.os.killpg", side_effect=killpg):
            result = run_worker({"runtime": runtime, "groups": [group], "timeout": 10}, 0)

        self.assertEqual(result, 128 + signal.SIGTERM)
        self.assertEqual(sent_signals, [(4321, signal.SIGTERM)])
        self.assertEqual(process.wait.call_count, 1)
        process.poll.assert_called()

    def test_cancellation_during_callback_deactivation_cleans_detached_descendants(self):
        process = SimpleNamespace(pid=1234, poll=Mock(return_value=0), wait=Mock(return_value=0))
        callbacks = []
        sent_signals = []

        def deactivate(active_process):
            callbacks.append(active_process)
            if active_process is None:
                raise KeyboardInterrupt

        def killpg(process_group_id, sig):
            if sig == 0:
                raise ProcessLookupError
            sent_signals.append((process_group_id, sig))

        with patch("ci_swift_test_by_suite.subprocess.Popen", return_value=process), \
                patch("ci_swift_test_by_suite.os.killpg", side_effect=killpg):
            with self.assertRaises(KeyboardInterrupt):
                runner.run_command(["synthetic-pool"], cleanup_process_group=True,
                                   process_started_callback=deactivate)

        self.assertEqual(callbacks, [process, None])
        self.assertEqual(sent_signals, [(1234, signal.SIGTERM)])
        self.assertEqual(process.wait.call_count, 2)

    def test_outer_keyboard_interrupt_cleans_the_direct_pool_process_group(self):
        process = SimpleNamespace(
            pid=1234,
            poll=Mock(return_value=-signal.SIGTERM),
            wait=Mock(side_effect=[KeyboardInterrupt, 0]),
        )
        sent_signals = []

        def killpg(process_group_id, sig):
            if sig == 0:
                raise ProcessLookupError
            sent_signals.append((process_group_id, sig))

        with patch("ci_swift_test_by_suite.subprocess.Popen", return_value=process), \
                patch("ci_swift_test_by_suite.os.killpg", side_effect=killpg):
            with self.assertRaises(KeyboardInterrupt):
                runner.run_command(["synthetic-pool"], cleanup_process_group=True)

        self.assertEqual(sent_signals, [(1234, signal.SIGTERM)])
        self.assertEqual(process.wait.call_count, 2)

    def test_default_serial_timeout_signal_sequence_is_unchanged(self):
        timeout = subprocess.TimeoutExpired(["synthetic-swift"], 2)
        process = SimpleNamespace(pid=5678, wait=Mock(side_effect=[timeout, timeout, 0]))
        sent_signals = []

        with patch("ci_swift_test_by_suite.subprocess.Popen", return_value=process), \
                patch("ci_swift_test_by_suite.os.killpg", side_effect=lambda pid, sig: sent_signals.append((pid, sig))):
            result = runner.run_command(["synthetic-swift"], timeout=2)

        self.assertEqual(result, 124)
        self.assertEqual(sent_signals, [(5678, signal.SIGTERM), (5678, signal.SIGKILL)])
        self.assertEqual(process.wait.call_args_list[0].kwargs, {"timeout": 2})
        self.assertEqual(process.wait.call_args_list[1].kwargs, {"timeout": 10})
        self.assertEqual(process.wait.call_args_list[2].kwargs, {})

    def test_denied_cleanup_probe_preserves_timeout_and_isolated_recovery(self):
        group = [{"name": "ExampleTests", "suite_name": "ExampleTests", "filter_pattern": r"^ExampleTests/"}]
        runtime = {"developer": "/synthetic/Developer", "xctest": "synthetic-xctest",
                   "products": [{"bundle": "synthetic-bundle", "xctest": ["ExampleTests/testOne"], "swift": []}]}
        process = SimpleNamespace(
            pid=4321,
            poll=Mock(return_value=-signal.SIGTERM),
            wait=Mock(side_effect=[subprocess.TimeoutExpired(["synthetic-xctest"], 8), 0]),
        )
        sent_signals = []
        output = io.StringIO()

        def killpg(process_group_id, sig):
            sent_signals.append((process_group_id, sig))
            if sig == 0:
                raise PermissionError("synthetic denied group probe")

        with patch.dict(os.environ), patch("sys.stdout", output), \
                patch("ci_swift_test_by_suite.subprocess.Popen", return_value=process), \
                patch("ci_swift_test_by_suite.os.killpg", side_effect=killpg), \
                patch("ci_swift_test_by_suite.time.monotonic", side_effect=[10, 12, 20, 20, 25]), \
                patch("ci_swift_test_by_suite.time.sleep"):
            code = run_worker({"runtime": runtime, "groups": [group], "timeout": 10}, 0)

        self.assertEqual(code, 124)
        self.assertEqual(sent_signals, [(4321, signal.SIGTERM), (4321, 0), (4321, signal.SIGKILL)])
        self.assertEqual(process.wait.call_count, 2)
        self.assertEqual(process.wait.call_args_list[0].kwargs, {"timeout": 8})
        self.assertIn("continuing bounded cleanup", output.getvalue())
        # The recovered timeout must remain visible while an ordinary assertion failure
        # receives no retry and keep-going still executes the last queued group.
        result, records, calls = self.run_mock_pool(
            [code, 0, 0, 42, 0], group_size=2, retry=False, group_count=3, keep_going=True)
        self.assertEqual(result, 42)
        self.assertEqual(calls, 5)
        self.assertEqual(len(records), 3)
        self.assertEqual(sorted(record["first_code"] for record in records), [0, 42, 124])
        self.assertEqual(sum(record["timed_out"] for record in records), 1)
        self.assertEqual(sum(record["isolated_retries"] for record in records), 2)
        self.assertTrue(all(record["full_retries"] == 0 for record in records))

    def test_actual_cleanup_signal_permission_error_remains_failure(self):
        for denied_signal in [signal.SIGTERM, signal.SIGKILL]:
            with self.subTest(denied_signal=denied_signal):
                process = SimpleNamespace(pid=4321, poll=Mock(return_value=0))

                def killpg(_process_group_id, sig):
                    if sig == denied_signal:
                        raise PermissionError("synthetic denied cleanup signal")

                with patch("ci_swift_test_by_suite.os.killpg", side_effect=killpg), \
                        patch("ci_swift_test_by_suite.time.monotonic", side_effect=[0, 5]):
                    with self.assertRaises(PermissionError):
                        runner.terminate_process_group(4321, grace_seconds=5, process=process)

    def probe_runtime(
        self, swift_command, expected, *, different_toolchain=False, duplicate_actual=False, environment=None
    ):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            developer = root / "Developer"
            platform_developer = developer / "Platforms/MacOSX.platform/Developer"
            frameworks = platform_developer / "Library/Frameworks"
            frameworks.mkdir(parents=True)
            (platform_developer / "Library/PrivateFrameworks").mkdir(parents=True)
            sdk = platform_developer / "SDKs/MacOSX.sdk"
            (sdk / "System/Library/PrivateFrameworks").mkdir(parents=True)
            swift = root / "toolchain/usr/bin/swift"
            helper_root = swift.parent.parent / "libexec/swift/pm"
            helper_root.mkdir(parents=True)
            for name in ["swiftpm-testing-helper", "swiftpm-xctest-helper"]:
                (helper_root / name).touch()
            xctest = root / "xctest"
            xctest.touch()
            binary = root / "bin/Example.xctest/Contents/MacOS/Example"
            binary.parent.mkdir(parents=True)
            binary.touch()
            def probe(command, environment):
                if command == ["xcode-select", "-p"]:
                    return str(developer)
                if command == ["xcrun", "--find", "swift"]:
                    return str(swift)
                if command == ["xcrun", "--sdk", "macosx", "--show-sdk-path"]:
                    return str(sdk)
                if command == ["xcrun", "--find", "xctest"]:
                    return str(xctest)
                if command[-1] == "-print-target-info":
                    resource = "/other/toolchain" if different_toolchain and command[0] == swift_command[0] else str(swift.parent.parent / "lib/swift")
                    return json.dumps({"paths": {"runtimeResourcePath": resource},
                                       "target": {"triple": "arm64-apple-macosx"}})
                if command[-2:] == ["build", "--show-bin-path"]:
                    self.assertEqual(command[:-2], swift_command)
                    return str(root / "bin")
                if command[0].endswith("swiftpm-xctest-helper"):
                    self.assertEqual(environment["SWIFT_TESTING_ENABLED"], "0")
                    Path(command[2]).write_text('{"tests": []}')
                    return ""
                if command[0].endswith("swiftpm-testing-helper"):
                    self.assertEqual(environment["SWIFT_TESTING_ENABLED"], "1")
                    inventory = "ExampleTests/changed()"
                    return "\n".join([inventory, inventory] if duplicate_actual else [inventory])
                return "ExampleTests/changed()"
            with patch("direct_swift_test_groups.sys.platform", "darwin"), \
                    patch.dict(os.environ, environment or {}, clear=True), \
                    patch("direct_swift_test_groups.checked", side_effect=probe):
                return prepare_runtime(swift_command, [], expected, root)

    def test_inventory_mismatch_rejects_runtime_before_execution(self):
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.probe_runtime(["swift"], ["ExampleTests/original()"])

    def test_selected_toolchain_wrapper_uses_its_build_directory(self):
        runtime = self.probe_runtime(["/synthetic/swift-native"], ["ExampleTests/changed()"])
        self.assertEqual(runtime["products"][0]["swift"], ["ExampleTests/changed()"])
        self.assertTrue(runtime["sdk"].endswith("MacOSX.sdk"))

    def test_hosted_ci_accepts_verified_inventory(self):
        for environment in [{"CI": "true"}, {"GITHUB_ACTIONS": "true"}]:
            with self.subTest(environment=environment):
                runtime = self.probe_runtime(["swift"], ["ExampleTests/changed()"], environment=environment)
                self.assertEqual(runtime["products"][0]["swift"], ["ExampleTests/changed()"])

    def test_hosted_ci_rejects_inventory_mismatch(self):
        with self.assertRaises(InventoryMismatch):
            self.probe_runtime(["swift"], ["ExampleTests/original()"], environment={"CI": "true"})

    def test_hosted_ci_unavailable_runtime_fails_without_serial_fallback(self):
        selection = runner.TestSelection("ExampleTests", "^ExampleTests/", "ExampleTests")
        output = io.StringIO()
        with patch.dict(os.environ, {"CI": "true"}), \
                patch.object(runner.sys, "argv", ["test.sh", "--direct-workers", "2"]), \
                patch.object(runner, "swift_test_list", return_value=[selection]), \
                patch("direct_swift_test_groups.prepare_runtime", side_effect=ValueError("missing helper")), \
                patch.object(runner, "run_group", return_value=0) as serial, \
                patch.object(runner, "run_command") as direct, \
                patch.object(runner, "append_github_summary"), patch("sys.stdout", output), patch("sys.stderr", output):
            self.assertEqual(runner.main(), 2)
        self.assertIn("Direct mode refused", output.getvalue())
        serial.assert_not_called()
        direct.assert_not_called()

    def test_duplicate_swiftpm_inventory_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.probe_runtime(["swift"], ["ExampleTests/changed()"] * 2)

    def test_duplicate_direct_helper_inventory_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.probe_runtime(["swift"], ["ExampleTests/changed()"], duplicate_actual=True)

    def test_wrapper_for_another_toolchain_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "selected Swift toolchain"):
            self.probe_runtime(["/synthetic/swift-native"], ["ExampleTests/changed()"], different_toolchain=True)

    def test_inventory_mismatch_fails_runner_without_serial_fallback(self):
        selection = runner.TestSelection("ExampleTests", "^ExampleTests/", "ExampleTests")
        output = io.StringIO()
        with patch.object(runner.sys, "argv", ["test.sh", "--direct-workers", "4"]), \
                patch.object(runner, "swift_test_list", return_value=[selection]), \
                patch("direct_swift_test_groups.prepare_runtime", side_effect=InventoryMismatch("inventory differs")), \
                patch.object(runner, "run_group") as serial, patch.object(runner, "run_command") as direct, \
                patch.object(runner, "append_github_summary"), patch("sys.stdout", output), patch("sys.stderr", output):
            self.assertEqual(runner.main(), 2)
        self.assertIn("inventory differs", output.getvalue())
        serial.assert_not_called()
        direct.assert_not_called()

    def test_direct_and_serial_shards_keep_identical_ordered_groups(self):
        selections = [runner.TestSelection(name, f"^{name}/", name) for name in [
            "CodexBarTests.Alpha", "CodexBarTests.CLIEntryTests", "CodexBarTests.CostUsagePerformanceGateTests",
            "CodexBarTests.Delta", "CodexBarTests.Epsilon", "CodexBarTests.Zeta", "CodexBarTests.Eta",
            "CodexBarTests.Theta"]]
        for shard_count in [2, 3, 4]:
            for shard_index in range(shard_count):
                serial_groups = []
                def run_serial(group, timeout, command):
                    serial_groups.append([runner.asdict(selection) for selection in group])
                    return 0
                args = ["test.sh", "--group-size", "2", "--shard-index", str(shard_index),
                        "--shard-count", str(shard_count), "--no-retry-non-timeout-failures", "--keep-going"]
                with patch.object(runner, "swift_test_list", return_value=selections), \
                        patch.object(runner, "append_github_summary"), patch("sys.stdout", io.StringIO()), \
                        patch.object(runner.sys, "argv", args), \
                        patch.object(runner, "run_group", side_effect=run_serial):
                    self.assertEqual(runner.main(), 0)
                for workers in [2, 3]:
                    with self.subTest(shard_count=shard_count, shard_index=shard_index, workers=workers):
                        def execute(command, timeout, **_kwargs):
                            manifest = json.loads(Path(command[-1]).read_text())
                            self.assertEqual(manifest["groups"], serial_groups)
                            self.assertEqual(manifest["workers"], workers)
                            self.assertFalse(manifest["retry_non_timeout_failures"])
                            self.assertTrue(manifest["keep_going"])
                            return 0
                        with patch.dict(os.environ, {"CI": "true"}), \
                                patch.object(runner, "swift_test_list", return_value=selections), \
                                patch.object(runner, "append_github_summary"), patch("sys.stdout", io.StringIO()), \
                                patch.object(runner.sys, "argv", [*args, "--direct-workers", str(workers)]), \
                                patch("direct_swift_test_groups.prepare_runtime", return_value={"products": [{}]}) as prepare, \
                                patch.object(runner, "run_command", side_effect=execute), \
                                patch.object(runner, "run_group") as serial:
                            self.assertEqual(runner.main(), 0)
                        self.assertEqual(prepare.call_args.args[1], serial_groups)
                        serial.assert_not_called()

    def run_mock_pool(self, codes, group_size=1, retry=True, group_count=1, output=b"", keep_going=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"groups": [[{"name": str(index)} for index in range(group_size)]
                                                      for _ in range(group_count)],
                "timeout": 180, "workers": 1, "retry_non_timeout_failures": retry,
                "keep_going": keep_going, "runtime": {"products": [{}]}}))
            codes = iter(codes)
            def run(command, **kwargs):
                kwargs["stdout"].buffer.write(output)
                return SimpleNamespace(returncode=next(codes))
            with patch("direct_swift_test_groups.subprocess.run", side_effect=run) as execute, \
                    patch("builtins.print"):
                result = run_pool(manifest)
            return result, json.loads((root / "results.json").read_text()), execute.call_count

    def test_non_utf8_test_output_does_not_replace_success(self):
        result, records, calls = self.run_mock_pool([0], output=b"synthetic diagnostic: \xff\n")
        self.assertEqual((result, records[0]["code"], calls), (0, 0, 1))

    def test_pool_stops_queued_groups_after_unrecovered_failure(self):
        for retry, codes, attempts in [(False, [42, 0, 0], 1), (True, [42, 42, 0, 0], 2)]:
            with self.subTest(retry=retry):
                result, records, calls = self.run_mock_pool(codes, group_size=2, retry=retry, group_count=3)
                self.assertEqual(result, 42)
                self.assertEqual(calls, attempts)
                self.assertEqual(len(records), 1)

    def test_pool_keep_going_runs_every_queued_group_without_hiding_failure(self):
        for code in [42, 124]:
            with self.subTest(code=code):
                result, records, calls = self.run_mock_pool(
                    [code, 0, 0], retry=False, group_count=3, keep_going=True)
                self.assertEqual(result, code)
                self.assertEqual(calls, 3)
                self.assertEqual(len(records), 3)
                self.assertEqual(sum(record["code"] != 0 for record in records), 1)
                self.assertTrue(all(record["full_retries"] == 0 for record in records))

    def test_pool_preserves_singleton_timeout_and_arbitrary_failure_codes(self):
        for code in [124, 42]:
            with self.subTest(code=code):
                result, records, calls = self.run_mock_pool([code])
                self.assertEqual(result, code)
                self.assertEqual(records[0]["code"], code)
                self.assertEqual(calls, 1)

    def test_pool_retains_first_failure_while_draining_other_workers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"groups": [[{"name": "first"}], [{"name": "second"}]],
                "workers": 2, "retry_non_timeout_failures": False}))
            release = threading.Event()
            drained = threading.Event()
            started = threading.Event()
            def execute(command, **kwargs):
                if command[-1] == "0":
                    self.assertTrue(started.wait(5))
                    return SimpleNamespace(returncode=42)
                started.set()
                self.assertTrue(release.wait(5))
                drained.set()
                return SimpleNamespace(returncode=124)
            def output(message, **kwargs):
                if message == "::endgroup::":
                    release.set()
            with patch("direct_swift_test_groups.subprocess.run", side_effect=execute), \
                    patch("builtins.print", side_effect=output):
                result = run_pool(manifest)
            self.assertEqual(result, 42)
            self.assertTrue(drained.is_set())
            self.assertEqual(len(json.loads((root / "results.json").read_text())), 2)

    def test_pool_budget_covers_all_isolated_recovery_attempts_and_cleanup(self):
        group = [{"name": str(index)} for index in range(12)]
        result, records, calls = self.run_mock_pool([124] + [0] * 12, group_size=12)
        self.assertEqual(result, 0)
        self.assertEqual(records[0]["isolated_retries"], 12)
        self.assertEqual(calls, 13)
        # Reporter's initial 180s timeout + twelve 150s successes exceeds the old 1620s budget.
        self.assertGreater(pool_timeout([group], 180, True, 5), 180 + 12 * 150)
        self.assertGreater(pool_timeout([group], 180, True, 5), 14 * 180)
        self.assertGreater(pool_timeout([group], 180, True, 5), pool_timeout([group], 180, False, 5))
        self.assertGreater(pool_timeout([group], 180, True, 5), pool_timeout([group], 180, True, 1))

    def test_pool_records_timeout_during_full_retry_even_when_recovery_succeeds(self):
        result, records, calls = self.run_mock_pool([1, 124, 0, 0], group_size=2)
        self.assertEqual(result, 0)
        self.assertEqual(records[0]["first_code"], 1)
        self.assertTrue(records[0]["timed_out"])
        self.assertEqual(records[0]["full_retries"], 1)
        self.assertEqual(records[0]["isolated_retries"], 2)
        self.assertEqual(calls, 4)

    def test_unsupported_platform_and_command_prefix_fall_back_before_probes(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch("direct_swift_test_groups.sys.platform", "linux"), patch("direct_swift_test_groups.checked") as probe:
                with self.assertRaises(ValueError):
                    prepare_runtime(["swift"], [], [], Path(directory))
                probe.assert_not_called()
            with patch("direct_swift_test_groups.sys.platform", "darwin"), patch.dict(os.environ, {}, clear=True):
                with patch("direct_swift_test_groups.checked") as probe:
                    with self.assertRaises(ValueError):
                        prepare_runtime(["swift", "--sdk", "/synthetic"], [], [], Path(directory))
                    probe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
