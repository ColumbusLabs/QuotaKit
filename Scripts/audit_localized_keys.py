#!/usr/bin/env python3
"""Cross-check String(localized:) source keys against the xcstrings catalog.

Background: Xcode only auto-extracts new String(localized:) keys into
Localizable.xcstrings during a full Xcode/xcodebuild build. swift test,
SwiftFormat, and SwiftLint never trigger that extraction, so a developer
who adds new String(localized:) calls and ships via TestFlight without an
intermediate Xcode build will silently ship English-only text to non-English
users (the source string becomes the localization fallback).

Real incident (2026-05-18, iOS 1.7.0 build 130): 21 String(localized:) keys
(entire 1.7.0 release-notes catalog + 12 CloudKit sync status strings) were
absent from xcstrings — zh-Hans / ja / zh-Hant users saw English on every
new screen. The state="new" audit in lint.sh passed because the catalog
itself had no untranslated entries; it just had no entries for these keys
at all.

This script fails lint when a source key has no catalog entry. Use case-1:
add proper translations to xcstrings. Use case-2 (rare): if you intentionally
want a hard-coded English literal that's never localized, use `String(
verbatim: "...")` or a plain Swift String, not `String(localized:)`.
"""
from __future__ import annotations

import json
import os
import re
import sys

PATTERN = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')


def scan_source(root: str) -> set[str]:
    keys: set[str] = set()
    for dp, _, fns in os.walk(root):
        # Skip Xcode build products + preview assets
        if any(seg in dp for seg in (".build", "DerivedData", "Preview Content")):
            continue
        for fn in fns:
            if not fn.endswith(".swift"):
                continue
            path = os.path.join(dp, fn)
            with open(path, encoding="utf-8") as fh:
                content = fh.read()
            for m in PATTERN.finditer(content):
                # Swift literal -> raw string: only \" and \n are common here
                raw = m.group(1).replace('\\"', '"').replace("\\n", "\n")
                keys.add(raw)
    return keys


def load_catalog(xcstrings: str) -> set[str]:
    with open(xcstrings, encoding="utf-8") as fh:
        data = json.load(fh)
    return set(data.get("strings", {}).keys())


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <xcstrings_path> <source_root>", file=sys.stderr)
        return 2
    xcstrings, source_root = sys.argv[1], sys.argv[2]
    source_keys = scan_source(source_root)
    catalog_keys = load_catalog(xcstrings)
    missing = sorted(source_keys - catalog_keys)
    if not missing:
        print(f"i18n source-vs-catalog: {xcstrings} — all {len(source_keys)} source keys present")
        return 0
    print(
        f"ERROR: {xcstrings} is missing {len(missing)} source String(localized:) keys.",
        file=sys.stderr,
    )
    print(
        "  Xcode auto-extraction did not run; non-English locales will show English fallback.",
        file=sys.stderr,
    )
    print("  Missing keys (first 30):", file=sys.stderr)
    for k in missing[:30]:
        snippet = k if len(k) <= 100 else k[:97] + "…"
        # Escape newlines so error output stays single-line per key
        snippet = snippet.replace("\n", "\\n")
        print(f"    {snippet}", file=sys.stderr)
    if len(missing) > 30:
        print(f"    … ({len(missing) - 30} more)", file=sys.stderr)
    print(
        "  Fix: open the project in Xcode and Build once, OR add catalog entries by hand "
        "(4 locales: en / zh-Hans / zh-Hant / ja, state=translated).",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
