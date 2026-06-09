#!/usr/bin/env python3
"""Fail on customer-visible legacy CodexBar branding leaks.

Inherited target names, module imports, storage identifiers, localization keys,
debug log prefixes, and explicit upstream attribution are allowed. Displayed
localization values and raw customer copy must use QuotaKit.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_RE = re.compile(r"CodexBar|codexbar|~/\.codexbar")

LOCALIZABLE_RE = re.compile(
    r'"(?P<key>(?:\\.|[^"\\])*)"\s*=\s*"(?P<value>(?:\\.|[^"\\])*)";'
)
SWIFT_STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')

ATTRIBUTION_PATTERNS = [
    re.compile(r"CodexBar by Peter Steinberger"),
    re.compile(r"steipete/CodexBar"),
    re.compile(r"https://github\.com/steipete/CodexBar"),
    re.compile(r"built in part from CodexBar"),
]

TOKEN_ALLOWLIST_PATTERNS = [
    re.compile(pattern)
    for pattern in [
        r"\bimport CodexBar(Core|MacroSupport|Sync)?\b",
        r"\bCodexBar[A-Za-z0-9_]+\b",
        r"\b[A-Za-z0-9_]+CodexBar[A-Za-z0-9_]*\b",
        r"\bCodexbarApp\b",
        r"\bCodexBarLog\b",
        r"\bCodexBarLogger\b",
        r"\bCodexBarConfig\b",
        r"\bCodexBarLocalization\b",
        r"\bCodexBarMockProvidersEnabled\b",
        r"\bCODEXBAR_[A-Z0-9_]+\b",
        r"\bMAC_RELEASE_.*CODEXBAR\b",
        r"\blegacy[A-Za-z0-9_]*\b",
        r"\.codexbar\b",
        r"\.codexbar[A-Za-z0-9_]+\b",
        r"\bcase codexbar\b",
        r"com\.steipete\.codexbar",
        r"com\.steipete\.CodexBar",
        r"com\.codexbar",
        r"CodexBarTeamID",
        r"CodexBar_CodexBar",
        r"CodexBarClaudeWatchdog",
        r"CodexBarLifecycleKeepalive",
        r"messageHandlers\?\.codexbarLog",
        r"window\.__codexbar",
        r"clientName: \"codexbar\"",
        r"installationId\": \"codexbar\"",
        r"fingerprintId\": \"codexbar-usage\"",
        r"__codexbar_",
        r"experimental_thread_store=.*codexbar-status",
        r"codexbar-[A-Za-z0-9_{}().\\-]+",
        r"\"codexbar-\"",
        r"\"codexbarLog\"",
        r"appendingPathComponent\(\"CodexBar\"",
        r"appendingPathComponent\(\"CodexBar\.log\"",
        r"appendingPathComponent\(\"codexbar-buy-credits\.log\"",
        r"appendingPathComponent\(\"Library/Application Support/CodexBar/ClaudeProbe\"",
        r"UserDefaults\(suiteName: \"CodexBar\"\)",
        r"Notification\.Name\(\"codexbar[A-Za-z0-9_]+\"\)",
        r"\"codexbar\.[A-Za-z0-9_.-]+\"",
        r"\"com\.codexbar\.[A-Za-z0-9_.-]+\"",
        r"legacyStoreSubdirectoryNames = \[\"CodexBar\"",
        r"\[CodexBar [^\]]+\]",
        r"CodexBar found another managed account that already uses the current system account\.",
        r"CodexBar could not read managed account storage\.",
        r"Sources/CodexBar",
        r"CodexBarSwiftDataSchema",
    ]
]


def has_forbidden(text: str) -> bool:
    return FORBIDDEN_RE.search(text) is not None


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


def allowed_by_patterns(text: str, start: int, end: int) -> bool:
    for pattern in ATTRIBUTION_PATTERNS + TOKEN_ALLOWLIST_PATTERNS:
        for match in pattern.finditer(text):
            if match.start() <= start and end <= match.end():
                return True
    return False


def disallowed_token_count(text: str) -> int:
    count = 0
    for match in FORBIDDEN_RE.finditer(text):
        if not allowed_by_patterns(text, match.start(), match.end()):
            count += 1
    return count


def string_unit_values(node: object) -> list[str]:
    values: list[str] = []
    if isinstance(node, dict):
        string_unit = node.get("stringUnit")
        if isinstance(string_unit, dict):
            value = string_unit.get("value")
            if isinstance(value, str):
                values.append(value)
        for child in node.values():
            values.extend(string_unit_values(child))
    elif isinstance(node, list):
        for child in node:
            values.extend(string_unit_values(child))
    return values


def disallowed_swift_literal_on_line(line: str, literal_match: re.Match[str]) -> bool:
    """Check only tokens inside a Swift literal, using the full source line for allowlist context."""
    literal_start, literal_end = literal_match.span()
    for match in FORBIDDEN_RE.finditer(line, literal_start, literal_end):
        if not allowed_by_patterns(line, match.start(), match.end()):
            return True
    return False


def audit_localizable_values() -> list[str]:
    failures: list[str] = []
    resource_root = ROOT / "Sources" / "CodexBar" / "Resources"
    for path in sorted(resource_root.glob("*.lproj/Localizable.strings")):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            match = LOCALIZABLE_RE.search(line)
            if not match:
                continue
            value = match.group("value")
            if disallowed_token_count(value):
                failures.append(f"{relative(path)}:{line_number}: localized value contains legacy branding")
    return failures


def audit_xcstrings_values() -> list[str]:
    failures: list[str] = []
    for path in sorted(ROOT.rglob("*.xcstrings")):
        if ".build" in path.parts or "DerivedData" in path.parts:
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        strings = data.get("strings", {})
        for key, entry in strings.items():
            for locale, localization in entry.get("localizations", {}).items():
                for value in string_unit_values(localization):
                    if disallowed_token_count(value):
                        failures.append(
                            f"{relative(path)}:{locale}: localized value for {key[:80]!r} contains legacy branding")
                        break
    return failures


def source_roots() -> list[Path]:
    return [
        ROOT / "Sources" / "CodexBar",
        ROOT / "Sources" / "CodexBarCore",
        ROOT / "Shared",
        ROOT / "CodexBarMobile" / "CodexBarMobile",
        ROOT / "CodexBarMobile" / "CodexBarMobilePushExtension",
        ROOT / "CodexBarMobile" / "CodexBarMobileWidgets",
    ]


def allowed_source_line(path: Path, stripped: str) -> bool:
    if not stripped or stripped.startswith("//") or stripped.startswith("*"):
        return True
    if path.name == "KeychainPromptCoordinator.swift" and "L(" not in stripped:
        return True
    if "L(" in stripped and path.parts[-3:] != ("Resources", "en.lproj", "Localizable.strings"):
        return True
    return False


def audit_swift_literals() -> list[str]:
    failures: list[str] = []
    for source_root in source_roots():
        if not source_root.exists():
            continue
        for path in sorted(source_root.rglob("*.swift")):
            if ".build" in path.parts or "Generated" in path.parts:
                continue
            for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                if not has_forbidden(line):
                    continue
                stripped = line.strip()
                if allowed_source_line(path, stripped):
                    continue
                for string_match in SWIFT_STRING_RE.finditer(line):
                    if disallowed_swift_literal_on_line(line, string_match):
                        failures.append(
                            f"{relative(path)}:{line_number}: possible customer-facing legacy branding")
                        break
    return failures


def audit_app_bundle() -> list[str]:
    bundle = os.environ.get("QUOTAKIT_APP_BUNDLE")
    if not bundle:
        return []
    bundle_path = Path(bundle)
    if not bundle_path.exists():
        return [f"{bundle}: QUOTAKIT_APP_BUNDLE does not exist"]

    failures: list[str] = []
    for path in sorted(bundle_path.rglob("*")):
        if path.is_dir() or path.suffix in {".png", ".jpg", ".jpeg", ".icns", ".car", ".dylib", ".so"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if disallowed_token_count(text) and "CodexBar_CodexBar.bundle" not in str(path):
            failures.append(f"{path}: packaged file contains legacy branding")
    return failures


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        return self_test()

    failures = audit_localizable_values()
    failures.extend(audit_xcstrings_values())
    failures.extend(audit_swift_literals())
    failures.extend(audit_app_bundle())

    if failures:
        print("ERROR: customer branding audit found legacy CodexBar references:", file=sys.stderr)
        for failure in failures[:80]:
            print(f"  {failure}", file=sys.stderr)
        if len(failures) > 80:
            print(f"  ... {len(failures) - 80} more", file=sys.stderr)
        print("Keep internal compatibility names allowlisted, but customer copy must say QuotaKit.", file=sys.stderr)
        return 1

    print("customer branding audit: no visible CodexBar leaks")
    return 0


def self_test() -> int:
    fixture = {
        "variations": {
            "plural": {
                "one": {"stringUnit": {"value": "QuotaKit has one update"}},
                "other": {"stringUnit": {"value": "CodexBar has %lld updates"}},
            }
        }
    }
    values = string_unit_values(fixture)
    if values != ["QuotaKit has one update", "CodexBar has %lld updates"]:
        print("ERROR: self-test failed to traverse nested string units", file=sys.stderr)
        return 1
    if sum(disallowed_token_count(value) for value in values) != 1:
        print("ERROR: self-test failed to detect nested legacy branding", file=sys.stderr)
        return 1
    if disallowed_token_count("CodexBar") != 1:
        print("ERROR: self-test must audit values, not keys", file=sys.stderr)
        return 1
    print("customer branding audit self-test: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
