#!/usr/bin/env python3
"""Verify iOS raw provider colors mirror Mac provider descriptors."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOBILE_PALETTE = ROOT / "CodexBarMobile/CodexBarMobile/Models/ProviderColorPalette.swift"
MAC_PROVIDERS = ROOT / "Sources/CodexBarCore/Providers"

PROVIDER_RE = re.compile(r"id:\s*\.(?P<id>[A-Za-z0-9_]+)")
COLOR_RE = re.compile(
    r"ProviderColor\(\s*red:\s*(?P<red>[^,\)]+),\s*green:\s*(?P<green>[^,\)]+),\s*blue:\s*(?P<blue>[^,\)]+)\)"
)
MOBILE_ENTRY_RE = re.compile(
    r'\(\s*\[(?P<aliases>[^\]]+)\],\s*RawColor\(red:\s*(?P<red>[^,\)]+),\s*green:\s*(?P<green>[^,\)]+),\s*blue:\s*(?P<blue>[^,\)]+)\)\s*\)'
)
MOBILE_ALIAS_TARGETS = {
    "11labs": "elevenlabs",
    "abacusai": "abacus",
    "ampcode": "amp",
    "anthropic": "claude",
    "bailian": "alibaba",
    "bailiantokenplan": "alibabatokenplan",
    "alibabatoken": "alibabatokenplan",
    "chatgpt": "openai",
    "droid": "factory",
    "eleven": "elevenlabs",
    "groqapi": "groq",
    "groqcloud": "groq",
    "kimiapi": "moonshot",
    "kimik2unofficial": "kimik2",
    "moonshotkimiapi": "moonshot",
    "sakanaai": "sakana",
    "syntheticnew": "synthetic",
    "t3": "t3chat",
    "vertex": "vertexai",
    "xiaomimimo": "mimo",
}


def evaluate_channel(expression: str) -> float:
    parts = [part.strip() for part in expression.split("/")]
    if len(parts) == 1:
        return float(parts[0])
    if len(parts) == 2:
        return float(parts[0]) / float(parts[1])
    raise ValueError(f"Unsupported color expression: {expression}")


def parse_color(match: re.Match[str]) -> tuple[float, float, float]:
    return (
        evaluate_channel(match.group("red")),
        evaluate_channel(match.group("green")),
        evaluate_channel(match.group("blue")),
    )


def mac_colors() -> dict[str, tuple[float, float, float]]:
    colors: dict[str, tuple[float, float, float]] = {}
    for path in sorted(MAC_PROVIDERS.rglob("*ProviderDescriptor.swift")):
        text = path.read_text(encoding="utf-8")
        provider = PROVIDER_RE.search(text)
        color = COLOR_RE.search(text)
        if provider and color:
            colors[provider.group("id")] = parse_color(color)
    return colors


def mobile_palette() -> tuple[
    dict[str, tuple[float, float, float]],
    dict[str, str],
]:
    text = MOBILE_PALETTE.read_text(encoding="utf-8")
    colors: dict[str, tuple[float, float, float]] = {}
    aliases: dict[str, str] = {}
    for match in MOBILE_ENTRY_RE.finditer(text):
        parsed_aliases = re.findall(r'"([^"]+)"', match.group("aliases"))
        if not parsed_aliases:
            continue
        canonical = parsed_aliases[0]
        colors[canonical] = parse_color(match)
        for alias in parsed_aliases[1:]:
            aliases[alias] = canonical
    return colors, aliases


def main() -> int:
    mac = mac_colors()
    mobile, aliases = mobile_palette()
    failures: list[str] = []

    for provider, mac_color in sorted(mac.items()):
        mobile_color = mobile.get(provider)
        if mobile_color is None:
            failures.append(f"{provider}: missing from mobile raw palette")
            continue
        if any(abs(lhs - rhs) > 0.001 for lhs, rhs in zip(mac_color, mobile_color)):
            failures.append(
                f"{provider}: Mac {mac_color!r} != mobile {mobile_color!r}")

    extra = sorted(set(mobile) - set(mac))
    for provider in extra:
        failures.append(f"{provider}: mobile canonical alias has no Mac descriptor")

    for alias, canonical in sorted(aliases.items()):
        expected = MOBILE_ALIAS_TARGETS.get(alias)
        if expected != canonical:
            failures.append(
                f"{alias}: mobile alias points to {canonical!r}, expected {expected!r}")

    missing_aliases = sorted(set(MOBILE_ALIAS_TARGETS) - set(aliases))
    for alias in missing_aliases:
        failures.append(f"{alias}: expected mobile alias is missing")

    if failures:
        print("ERROR: provider palette parity audit failed:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(f"provider palette audit: {len(mac)} Mac descriptors match mobile raw palette")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
