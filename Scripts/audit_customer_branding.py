#!/usr/bin/env python3
"""Fail on customer-visible legacy CodexBar branding leaks.

Inherited Swift target names, storage identifiers, localization keys, and migration
paths are still allowed. Displayed localization values and raw customer copy are not.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = ("CodexBar", "codexbar", "~/.codexbar")

LOCALIZABLE_RE = re.compile(
    r'"(?P<key>(?:\\.|[^"\\])*)"\s*=\s*"(?P<value>(?:\\.|[^"\\])*)";'
)


def has_forbidden(text: str) -> bool:
    return any(term in text for term in FORBIDDEN)


def audit_localizable_values() -> list[str]:
    failures: list[str] = []
    resource_root = ROOT / "Sources" / "CodexBar" / "Resources"
    for path in sorted(resource_root.glob("*.lproj/Localizable.strings")):
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            match = LOCALIZABLE_RE.search(line)
            if not match:
                continue
            value = match.group("value")
            if has_forbidden(value):
                failures.append(f"{path.relative_to(ROOT)}:{line_number}: localized value contains legacy branding")
    return failures


SOURCE_ALLOWLIST_PATTERNS = [
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
    r"appendingPathComponent\(",
    r"UserDefaults\(suiteName:",
    r"MigrationItem\(service:",
    r"Notification\.Name\(",
    r"DispatchQueue\(label:",
    r"Logger\(label:",
    r"identifier:",
    r"logHandlerName",
    r"messageHandlers\?\.codexbarLog",
    r"window\.__codexbar",
    r"clientName: \"codexbar\"",
    r"installationId\": \"codexbar\"",
    r"fingerprintId\": \"codexbar-usage\"",
    r"__codexbar_",
    r"experimental_thread_store=.*codexbar-status",
    r"codexbar-[A-Za-z0-9_{}().\\-]+",
    r"\[CodexBar Sync\]",
    r"CodexBar found another managed account that already uses the current system account\.",
    r"CodexBar could not read managed account storage\.",
]

SOURCE_ALLOWLIST = [re.compile(pattern) for pattern in SOURCE_ALLOWLIST_PATTERNS]


def allowed_source_line(path: Path, stripped: str) -> bool:
    if not stripped or stripped.startswith("//") or stripped.startswith("*"):
        return True
    if path.name == "KeychainPromptCoordinator.swift" and "L(" not in stripped:
        # These are legacy localization keys; displayed Localizable.strings values are audited above.
        return True
    if "L(" in stripped and path.parts[-3:] != ("Resources", "en.lproj", "Localizable.strings"):
        # Legacy localization lookup keys intentionally retain old English keys.
        return True
    return any(pattern.search(stripped) for pattern in SOURCE_ALLOWLIST)


def audit_swift_literals() -> list[str]:
    failures: list[str] = []
    source_roots = [ROOT / "Sources" / "CodexBar", ROOT / "Sources" / "CodexBarCore", ROOT / "Shared"]
    for source_root in source_roots:
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
                failures.append(f"{path.relative_to(ROOT)}:{line_number}: possible customer-facing legacy branding")
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
        if has_forbidden(text) and "CodexBar_CodexBar.bundle" not in str(path):
            failures.append(f"{path}: packaged file contains legacy branding")
    return failures


def main() -> int:
    failures = audit_localizable_values()
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


if __name__ == "__main__":
    raise SystemExit(main())
