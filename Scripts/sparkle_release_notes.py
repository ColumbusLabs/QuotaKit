#!/usr/bin/env python3
"""Embed the finalized QuotaKit changelog section as Sparkle Markdown."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"

MARKDOWN_REFERENCE = re.compile(
    r"(?P<code>`+[^`\n]*`+)|(?P<link>\[[^\]\n]*\]\([^\n)]*\))"
    r"|(?P<issue>(?<![\w/])#(?P<number>\d+)\b)"
    r"|(?P<user>(?<![\w.+-])@(?P<username>[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?)(?![A-Za-z0-9-]))"
)


def changelog_section(changelog: str, version: str) -> str:
    heading = re.compile(rf"^##\s+{re.escape(version)}(?:\s|$)")
    lines = changelog.splitlines()
    start = next((index for index, line in enumerate(lines) if heading.match(line)), None)
    if start is None:
        raise ValueError(f"No CHANGELOG.md section found for version {version}")

    end = next((index for index in range(start + 1, len(lines)) if lines[index].startswith("## ")), len(lines))
    notes = "\n".join(lines[start + 1 : end]).strip()
    if not notes:
        raise ValueError(f"CHANGELOG.md section for version {version} is empty")
    return notes


def link_github_references(markdown: str, repository: str) -> str:
    """Link issue, pull request, and contributor references outside code and existing links."""
    linked_lines: list[str] = []
    code_fence: str | None = None
    for line in markdown.splitlines(keepends=True):
        fence = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if code_fence is not None:
            linked_lines.append(line)
            if fence and fence.group(1)[0] == code_fence[0] and len(fence.group(1)) >= len(code_fence):
                code_fence = None
            continue
        if fence:
            code_fence = fence.group(1)
            linked_lines.append(line)
            continue

        def link_reference(match: re.Match[str]) -> str:
            if match.group("code") or match.group("link"):
                return match.group()
            if match.group("number"):
                number = match.group("number")
                return f"[#{number}](https://github.com/{repository}/issues/{number})"
            username = match.group("username")
            return f"[@{username}](https://github.com/{username})"

        linked_lines.append(MARKDOWN_REFERENCE.sub(link_reference, line))
    return "".join(linked_lines)


def appcast_markdown(
    changelog: str,
    version: str,
    app_name: str,
    repository: str,
    mobile_version: str = "",
    branch: str = "main",
) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError(f"Invalid GitHub repository: {repository}")
    body = changelog_section(changelog, version)
    mobile = f" Mobile {mobile_version}" if mobile_version else ""
    changelog_url = f"https://github.com/{repository}/blob/{quote(branch, safe='/-._')}/CHANGELOG.md"
    notes = link_github_references(body, repository)
    return f"## {app_name} {version}{mobile}\n\n{notes}\n\n[View full changelog]({changelog_url})"


def update_appcast_description(appcast_path: Path, version: str, markdown: str) -> None:
    ET.register_namespace("sparkle", SPARKLE)
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
    tree = ET.parse(appcast_path, parser=parser)
    channel = tree.getroot().find("./channel")
    if channel is None:
        raise ValueError("Appcast has no channel")

    short_version_key = f"{{{SPARKLE}}}shortVersionString"
    items = [item for item in channel.findall("item") if item.findtext(short_version_key) == version]
    if len(items) != 1:
        raise ValueError(f"Expected one appcast item for version {version}; found {len(items)}")

    description = items[0].find("description")
    if description is None:
        raise ValueError(f"Appcast item for version {version} has no description")
    tail = description.tail
    description.clear()
    description.set(f"{{{SPARKLE}}}format", "markdown")
    description.text = markdown
    description.tail = tail

    tree.write(appcast_path, encoding="utf-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--changelog", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--app-name", default="QuotaKit")
    parser.add_argument("--repository", default="ColumbusLabs/QuotaKit")
    parser.add_argument("--mobile-version", default="")
    parser.add_argument("--branch", default="main")
    args = parser.parse_args()

    try:
        markdown = appcast_markdown(
            args.changelog.read_text(encoding="utf-8"),
            args.version,
            args.app_name,
            args.repository,
            args.mobile_version,
            args.branch)
        update_appcast_description(args.appcast, args.version, markdown)
    except (OSError, ET.ParseError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Embedded Sparkle Markdown release notes for {args.app_name} {args.version}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
