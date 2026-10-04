#!/usr/bin/env python3
"""Failure-only, bounded Mac test crash metadata; never builds or dumps memory."""

import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / ".build"
FILTER = (
    r"^CodexBarTests\.CostUsageDiscoveryRecoveryTests/"
    r"removed fork files do not strand discovery in an existing store(?:\(|$)"
)
OUTPUT_LIMIT = 256 * 1024
remaining_output = OUTPUT_LIMIT


def emit(value):
    global remaining_output
    text = str(value).replace("\x1b", "")
    # Prefix every line so report text cannot issue GitHub workflow commands.
    text = "\n".join("diagnostic: " + line for line in text.splitlines())
    encoded = text.encode("utf-8")[:remaining_output]
    if encoded:
        print(encoded.decode("utf-8", errors="ignore"), flush=True)
        remaining_output -= len(encoded)


def owned_image(path):
    if not isinstance(path, str):
        return False
    candidate = Path(path)
    return candidate.name == "CodexBarPackageTests" and candidate.is_relative_to(BUILD)


def print_ips(text):
    decoder = json.JSONDecoder()
    objects = []
    while text.strip():
        item, end = decoder.raw_decode(text.lstrip())
        objects.append(item)
        text = text.lstrip()[end:]
    report = objects[-1]
    images = report.get("usedImages", report.get("binaryImages", []))
    if not any(owned_image(image.get("path")) for image in images):
        return False
    fault = report.get("faultingThread")
    threads = report.get("threads", [])
    if not isinstance(fault, int) or not 0 <= fault < len(threads):
        return False
    frames = threads[fault].get("frames", [])[:192]
    if not frames:
        return False
    for key in ("procName", "procPath", "exception", "termination"):
        if key in report:
            emit(f"{key}: {json.dumps(report[key], ensure_ascii=True)}")
    emit(f"faultingThread: {fault}")
    image_indexes = set()
    for frame in frames:
        # Excludes registers, threadState, arguments and arbitrary crash payloads.
        allowed = {key: frame[key] for key in (
            "imageIndex", "imageOffset", "symbol", "symbolLocation", "sourceFile", "sourceLine"
        ) if key in frame}
        emit(json.dumps(allowed, ensure_ascii=True))
        if isinstance(frame.get("imageIndex"), int):
            image_indexes.add(frame["imageIndex"])
    for index in sorted(image_indexes):
        if 0 <= index < len(images):
            image = images[index]
            emit("image: " + json.dumps({key: image[key] for key in (
                "name", "path", "uuid", "arch", "base", "size"
            ) if key in image}, ensure_ascii=True))
    for key in ("vmRegionInfo", "vmSummary"):
        for line in str(report.get(key, "")).splitlines():
            if re.search(r"stack|guard", line, re.IGNORECASE):
                emit(f"{key}: {line}")
    return True


def print_crash(text):
    lines = text.splitlines()
    if not any("CodexBarPackageTests" in line and str(BUILD) in line for line in lines):
        return False
    in_fault = False
    frames = []
    metadata = []
    for line in lines:
        if re.match(r"Thread \d+ Crashed:", line):
            in_fault = True
            metadata.append(line)
        elif in_fault and re.match(r"\d+\s+", line):
            frames.append(line)
        elif in_fault:
            in_fault = False
        if line.startswith(("Process:", "Path:", "Exception Type:", "Exception Codes:",
                            "Exception Note:", "Termination Reason:")):
            metadata.append(line)
        elif re.match(r"\s*0x[0-9a-f]+\s+-\s+0x[0-9a-f]+", line, re.IGNORECASE):
            metadata.append(line)  # Binary image ranges, never register state.
        elif re.search(r"(?:STACK GUARD|Stack)\s+", line):
            metadata.append(line)
    if not frames:
        return False
    for line in metadata[:256] + frames[:192]:
        emit(line)
    return True


def existing_trace():
    directories = [Path.home() / "Library/Logs/DiagnosticReports", Path("/Library/Logs/DiagnosticReports")]
    candidates = []
    for directory in directories:
        if directory.is_dir():
            candidates.extend(path for path in directory.iterdir() if path.suffix in (".ips", ".crash"))
    candidates.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    found = False
    for path in candidates[:24]:
        if path.stat().st_mtime < time.time() - 2 * 3600 or path.stat().st_size > 8 * 1024 * 1024:
            continue
        try:
            text = path.read_text(errors="replace")
            usable = print_ips(text) if path.suffix == ".ips" else print_crash(text)
            if usable:
                emit(f"owned crash report: {path.name}")
                found = True
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            continue
        if remaining_output <= 0:
            break
    return found


def tool_output(arguments):
    return subprocess.check_output(arguments, text=True, timeout=10).strip()


def debugger_trace():
    # The shell sources test_environment.sh first; refuse an unsafe entry point.
    required = {
        "CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS": "0",
        "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
        "CODEXBAR_TEST_CODEX_FILE_ISOLATION": "1",
        "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
    }
    if any(os.environ.get(key) != value for key, value in required.items()):
        emit("LLDB skipped: hermetic test controls missing")
        return
    binary = BUILD / "debug/CodexBarPackageTests.xctest/Contents/MacOS/CodexBarPackageTests"
    if not binary.is_file():
        emit("LLDB skipped: failed job did not produce the compiled test bundle")
        return
    source_paths = [ROOT / "Package.swift"]
    for directory in (ROOT / "Sources", ROOT / "Shared", ROOT / "Tests"):
        source_paths.extend(directory.rglob("*.swift"))
    if binary.stat().st_mtime < max(path.stat().st_mtime for path in source_paths):
        emit("LLDB skipped: cached test bundle predates current package source")
        return
    if tool_output(["swift", "--version"]) != tool_output(["xcrun", "swift", "--version"]):
        emit("LLDB skipped: PATH Swift differs from the selected Xcode toolchain")
        return
    swift = Path(tool_output(["xcrun", "--find", "swift"]))
    helper = swift.parent.parent / "libexec/swift/pm/swiftpm-testing-helper"
    if not helper.is_file():
        emit("LLDB skipped: selected SwiftPM testing helper unavailable")
        return
    developer = Path(tool_output(["xcode-select", "-p"]))
    environment = os.environ.copy()
    # Match SwiftPM's macOS runtime search paths without exposing the environment.
    platform = developer / "Platforms/MacOSX.platform/Developer"
    environment["DYLD_FRAMEWORK_PATH"] = str(platform / "Library/Frameworks")
    environment["DYLD_LIBRARY_PATH"] = str(platform / "usr/lib")
    environment["NO_COLOR"] = "1"
    commands = [
        "settings set stop-line-count-before 0",
        "settings set stop-line-count-after 0",
        "settings set stop-disassembly-count 0",
        "settings set frame-format 'frame #${frame.index}: ${frame.pc} ${module.file.basename}`${function.name} at ${line.file.basename}:${line.number}\\n'",
    ]
    crash_commands = ["thread backtrace --count 192", "register read sp fp pc",
                      "memory region $sp", "memory region $fp", "image list -o -f", "process kill"]
    arguments = ["xcrun", "lldb", "--no-lldbinit", "--no-use-colors", "--batch", "--source-quietly"]
    for command in commands:
        arguments.extend(["--one-line", command])
    for command in crash_commands:
        arguments.extend(["--one-line-on-crash", command])
    # SwiftPM 6.2.4's TestRunner uses this same helper/bundle entry point.
    # Swift Testing's entry point accepts --filter and --no-parallel directly.
    arguments.extend(["--", str(helper), "--test-bundle-path", str(binary),
                      "--testing-library", "swift-testing", "--no-parallel", "--filter", FILTER])
    emit("No usable owned crash report; LLDB attempting the unchanged removed-fork fixture (90-second cap)")
    # Capture reporter text privately only to verify selection; never print its
    # parameter values or diagnostics. The temporary log is not uploaded/cached.
    descriptor, reporter_path = tempfile.mkstemp(prefix="codex-test-selection-", dir=os.environ.get("RUNNER_TEMP"))
    os.close(descriptor)
    launch_index = arguments.index("--")
    arguments[launch_index:launch_index] = [
        "--one-line", f"process launch --stdout /dev/null --stderr '{reporter_path}'"
    ]
    try:
        process = subprocess.Popen(arguments, cwd=ROOT, env=environment, start_new_session=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except OSError:
        os.unlink(reporter_path)
        raise
    output = b""
    try:
        output, _ = process.communicate(timeout=90)
    except subprocess.TimeoutExpired as error:
        output = error.output or b""
        emit("LLDB diagnostic timed out; terminating only its launched inferior and process group")
    finally:
        if process.poll() is None:
            # LLDB may launch its inferior in a separate group. Only its reported
            # launch PID, still running the exact selected helper, is eligible.
            match = re.search(rb"Process (\d+) launched:", output)
            if match:
                pid = int(match[1])
                try:
                    name = tool_output(["/bin/ps", "-p", str(pid), "-o", "comm="])
                    if Path(name).name == helper.name:
                        os.kill(pid, signal.SIGKILL)
                except (OSError, subprocess.SubprocessError):
                    pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
        try:
            with open(reporter_path, "rb") as reporter:
                reporter_text = reporter.read(512 * 1024).decode("utf-8", errors="replace")
            started = [line for line in reporter_text.splitlines() if re.search(r'Test "[^"]+" started', line)]
            selected = [line for line in started if
                        'Test "removed fork files do not strand discovery in an existing store"' in line]
            if selected and len(selected) == len(started):
                emit(f"Selected unchanged removed-fork fixture verified: {len(selected)} start record(s); other test starts: 0")
            else:
                emit("Fixture selection unverified; this diagnostic does not establish fixture execution")
        finally:
            os.unlink(reporter_path)
    # Inferior output is discarded; only debugger stack/region/image metadata is
    # emitted. No locals, environment, source lines or memory reads are requested.
    emit(output[:128 * 1024].decode("utf-8", errors="replace"))
    emit(f"LLDB exit status: {process.returncode}; original failed test gate remains failed")


def main():
    try:
        if not existing_trace():
            debugger_trace()
    except (OSError, subprocess.SubprocessError) as error:
        emit(f"Crash diagnostic unavailable: {type(error).__name__}")


if __name__ == "__main__":
    main()
