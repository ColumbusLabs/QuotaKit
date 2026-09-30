#!/usr/bin/env python3
"""Exercise release verification with fake transport/signature tools; no credentials or builds."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class ReleaseVerificationTests(unittest.TestCase):
    def test_downloaded_asset_signature_gate(self):
        with tempfile.TemporaryDirectory(prefix="quotakit-asset-test-") as directory:
            fixture = Path(directory)
            tools = fixture / "bin"
            tools.mkdir()
            fake = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["FIXTURE_CALLS"], "a") as f:
    f.write(json.dumps([name, *args]) + "\n")
mode = os.environ["FIXTURE_MODE"]
if name == "gh":
    assert args[:2] in [["release", "view"], ["release", "download"]]
    assert args[args.index("--repo") + 1] == "ColumbusLabs/QuotaKit"
    if args[1] == "view":
        print("QuotaKit-macos-universal-1.2.3.zip")
        print("QuotaKit-macos-universal-1.2.3.dSYM.zip")
        if mode != "missing-dmg": print("QuotaKit-macos-universal-1.2.3.dmg")
    else:
        if mode == "download-failure": sys.exit(1)
        assert args[args.index("--pattern") + 1] == "QuotaKit-macos-universal-1.2.3.zip"
        target = pathlib.Path(args[args.index("--dir") + 1])
        (target / "QuotaKit-macos-universal-1.2.3.zip").write_bytes(b"fixture")
elif name == "ditto":
    assert args[:3] == ["-x", "-k", "--norsrc"]
    app = pathlib.Path(args[-1]) / "QuotaKit.app"
    if mode == "symlink-app": app.symlink_to(".", target_is_directory=True)
    elif mode != "missing-app": app.mkdir()
elif name == "codesign":
    for flag in ["--verify", "--deep", "--strict", "--all-architectures"]: assert flag in args
    requirement = args[args.index("--test-requirement") + 1]
    assert 'identifier "com.columbuslabs.quotakit.mac"' in requirement
    assert 'certificate leaf[subject.OU] = "FIXTURE123"' in requirement
    assert 'anchor apple generic' in requirement
    assert '100.6.2.6' in requirement and '100.6.1.13' in requirement
    assert pathlib.Path(args[-1]).name == "QuotaKit.app"
    if mode == "bad-signature": sys.exit(1)
else:
    raise AssertionError(name)
'''
            for name in ["gh", "ditto", "codesign"]:
                path = tools / name
                path.write_text(fake)
                path.chmod(0o700)
            calls = fixture / "calls.jsonl"
            (tools / "python3").symlink_to(sys.executable)
            secret_marker = fixture / "secrets-loaded"
            release_env = fixture / "release.env"
            release_env.write_text(f"touch '{secret_marker}'\nexport APP_STORE_CONNECT_API_KEY_P8=fixture-only-secret\n")
            for mode in ["valid", "missing-dmg", "download-failure", "missing-app", "symlink-app", "bad-signature"]:
                with self.subTest(mode=mode):
                    calls.write_text("")
                    env = {
                        "PATH": f"{tools}:/usr/bin:/bin:/usr/sbin:/sbin",
                        "QUOTAKIT_RELEASE_ENV": str(release_env),
                        "APP_TEAM_ID": "FIXTURE123",
                        "FIXTURE_MODE": mode,
                        "FIXTURE_CALLS": str(calls),
                        "TMPDIR": str(fixture),
                    }
                    result = subprocess.run(
                        ["/bin/bash", str(ROOT / "Scripts/check-release-assets.sh"), "v1.2.3"],
                        env=env, text=True, capture_output=True, timeout=15,
                    )
                    self.assertEqual(result.returncode == 0, mode == "valid", result.stderr)
                    recorded = [json.loads(line) for line in calls.read_text().splitlines()]
                    if mode in ["missing-dmg", "download-failure", "missing-app", "symlink-app"]:
                        self.assertFalse(any(call[0] == "codesign" for call in recorded))
                    self.assertFalse(list(fixture.glob("quotakit-release-assets.*")))
                    self.assertFalse(secret_marker.exists())

            for team in ["", "bad\"team"]:
                env["APP_TEAM_ID"] = team
                calls.write_text("")
                result = subprocess.run(
                    ["/bin/bash", str(ROOT / "Scripts/check-release-assets.sh"), "v1.2.3"],
                    env=env, text=True, capture_output=True, timeout=15,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls.read_text(), "")

    def test_notary_upload_options(self):
        source = (ROOT / "Scripts/sign-and-notarize.sh").read_text()
        block = "NOTARYTOOL_OPTIONS=(--wait)" + source.split("NOTARYTOOL_OPTIONS=(--wait)", 1)[1].split(
            "# Load local-only release secrets", 1,
        )[0]
        self.assertEqual(source.count('"${NOTARYTOOL_OPTIONS[@]}"'), 2)
        for value, expected in [(None, ["--wait"]), ("1", ["--wait"]), ("0", ["--wait", "--no-s3-acceleration"]), ("", None), ("yes", None)]:
            with self.subTest(value=value):
                env = {"PATH": "/usr/bin:/bin"}
                if value is not None:
                    env["QUOTAKIT_NOTARY_S3_ACCELERATION"] = value
                result = subprocess.run(
                    ["/bin/bash", "-c", block + '\nprintf "%s\\n" "${NOTARYTOOL_OPTIONS[@]}"'],
                    env=env, text=True, capture_output=True, timeout=5,
                )
                self.assertEqual(result.returncode == 0, expected is not None)
                if expected is not None:
                    self.assertEqual(result.stdout.splitlines(), expected)


if __name__ == "__main__":
    unittest.main()
