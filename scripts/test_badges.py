import re
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import badges


class RenderTests(unittest.TestCase):
    def test_svg_is_well_formed_and_accessible(self) -> None:
        root = ET.fromstring(badges.render_badge("release", "v1.2.3", "#123456"))
        self.assertEqual(root.attrib["role"], "img")
        self.assertEqual(root.attrib["aria-label"], "release: v1.2.3")
        self.assertEqual(root.find("{http://www.w3.org/2000/svg}title").text, "release: v1.2.3")

    def test_svg_references_nothing_external(self) -> None:
        svg = badges.render_badge("a", "b", "#000")
        self.assertEqual(re.findall(r"https?://[^\"' ]+", svg), ["http://www.w3.org/2000/svg"])
        self.assertNotIn("href", svg)

    def test_values_are_escaped(self) -> None:
        root = ET.fromstring(badges.render_badge("a&b", 'c"<d>', "#000"))
        self.assertEqual(root.attrib["aria-label"], 'a&b: c"<d>')


class SourceTests(unittest.TestCase):
    def test_latest_tag_is_the_highest_version_not_the_last_listed(self) -> None:
        self.assertEqual(badges.latest_tag(["v0.9.0", "v0.10.0", "v0.2.1", "nightly"]), "v0.10.0")

    def test_no_tag_reads_as_none(self) -> None:
        self.assertEqual(badges.latest_tag(["nightly"]), "none")

    def test_platform_is_read_from_the_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Package.swift").write_text("platforms: [\n .macOS(.v14)\n]", encoding="utf-8")
            self.assertEqual(badges.read_platform(root), "macOS 14+")

    def test_real_repository_values_are_present(self) -> None:
        self.assertTrue(badges.read_license())
        self.assertRegex(badges.read_platform(), r"^macOS \d+\+$")


if __name__ == "__main__":
    unittest.main()
