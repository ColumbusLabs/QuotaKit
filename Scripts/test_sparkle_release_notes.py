#!/usr/bin/env python3
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from sparkle_release_notes import SPARKLE, appcast_markdown, update_appcast_description


class SparkleReleaseNotesTests(unittest.TestCase):
    def test_notes_use_the_exact_version_section_and_link_github_references(self):
        changelog = """# Changelog

## 1.2.3 - 2026-01-01

### Fixed

- Fix wrapping (#4751). Thanks @octo-user.
- Keep `#12 @not-a-link` and [existing link](https://example.com/#99).

```text
#13 @code
```

## 1.2.2 - 2025-12-01

- Older change.
"""

        markdown = appcast_markdown(
            changelog,
            "1.2.3",
            "QuotaKit",
            "ColumbusLabs/QuotaKit",
            mobile_version="2.0.1",
            branch="release/1.2",
        )

        self.assertIn("## QuotaKit 1.2.3 Mobile 2.0.1\n\n### Fixed", markdown)
        self.assertIn("[#4751](https://github.com/ColumbusLabs/QuotaKit/issues/4751)", markdown)
        self.assertIn("[@octo-user](https://github.com/octo-user)", markdown)
        self.assertIn("`#12 @not-a-link` and [existing link](https://example.com/#99)", markdown)
        self.assertIn("```text\n#13 @code\n```", markdown)
        self.assertNotIn("Older change", markdown)
        self.assertTrue(
            markdown.endswith(
                "[View full changelog](https://github.com/ColumbusLabs/QuotaKit/blob/release/1.2/CHANGELOG.md)"))

    def test_appcast_update_marks_only_the_selected_description_as_markdown(self):
        appcast = """<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item sparkle:channel="beta">
      <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
      <description><![CDATA[<h2>Old notes</h2>]]></description>
      <enclosure url="https://example.com/update.zip" length="42" sparkle:edSignature="sig" />
    </item>
    <item>
      <sparkle:shortVersionString>1.2.2</sparkle:shortVersionString>
      <description>Older notes</description>
    </item>
  </channel>
</rss>
"""
        markdown = "## QuotaKit 1.2.3\n\n### Fixed\n\n- Fix wrapping (#4751)."
        sparkle_namespace = {"sparkle": SPARKLE}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(appcast, encoding="utf-8")

            update_appcast_description(path, "1.2.3", markdown)

            tree = ET.parse(path)
            items = tree.getroot().findall("./channel/item")
            description = items[0].find("description")
            self.assertIsNotNone(description)
            self.assertEqual(description.get(f"{{{SPARKLE}}}format"), "markdown")
            self.assertEqual(description.text, markdown)
            enclosure = items[0].find("enclosure")
            self.assertEqual(enclosure.get("url"), "https://example.com/update.zip")
            self.assertEqual(enclosure.get("length"), "42")
            self.assertEqual(enclosure.get(f"{{{SPARKLE}}}edSignature"), "sig")
            self.assertEqual(items[0].get(f"{{{SPARKLE}}}channel"), "beta")
            self.assertEqual(items[1].findtext("description"), "Older notes")
            self.assertEqual(
                items[0].findtext("sparkle:shortVersionString", namespaces=sparkle_namespace),
                "1.2.3")

    def test_missing_version_section_fails_before_appcast_rewrite(self):
        with self.assertRaisesRegex(ValueError, "No CHANGELOG.md section"):
            appcast_markdown("## 1.2.2 - 2025-12-01\n\n- Old\n", "1.2.3", "QuotaKit", "ColumbusLabs/QuotaKit")


if __name__ == "__main__":
    unittest.main()
