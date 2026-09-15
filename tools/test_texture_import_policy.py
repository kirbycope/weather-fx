#!/usr/bin/env python3
"""Tests for the tool that puts texture importing back on Godot's own defaults.

Run with:  python -m unittest tools/test_texture_import_policy.py

The tool rewrites every .import file in a project, so the things worth pinning down are the ones
that would be destructive to get wrong: that it leaves a texture Godot has already promoted to VRAM
Compressed alone, that it does not reach into an addon pulled from another repository, and that
--check reports without writing.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from texture_import_policy import (  # noqa: E402
    fix_import_files,
    fix_project_file,
    vendored_addons,
)

LOSSY_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=1
compress/lossy_quality=0.7
process/size_limit=512
detect_3d/compress_to=0
"""

VRAM_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
detect_3d/compress_to=0
"""

FORCED_PROJECT = """config_version=5

[importer_defaults]

texture={
&"compress/mode": 1,
&"detect_3d/compress_to": 0,
&"process/size_limit": 0
}
"""


class TextureImportPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.root = Path(self._temp.name)

    def tearDown(self) -> None:
        self._temp.cleanup()

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_a_lossy_texture_becomes_lossless_and_is_allowed_to_promote_in_3d(self) -> None:
        path = self.write("assets/rock.png.import", LOSSY_IMPORT)

        fixed, vram = fix_import_files(self.root)

        self.assertEqual(fixed, 1)
        self.assertEqual(vram, 0)
        self.assertIn("compress/mode=0", path.read_text())
        self.assertIn("detect_3d/compress_to=1", path.read_text())
        self.assertIn("process/size_limit=0", path.read_text(), "a committed 512 is the downscale rule again")

    def test_a_texture_godot_already_promoted_keeps_its_mode(self) -> None:
        path = self.write("assets/wall.png.import", VRAM_IMPORT)

        fixed, vram = fix_import_files(self.root)

        self.assertEqual((fixed, vram), (0, 1))
        self.assertEqual(path.read_text(), VRAM_IMPORT, "VRAM Compressed is Godot's own end state")

    def test_a_size_limit_is_cleared_even_on_a_texture_that_keeps_its_mode(self) -> None:
        path = self.write("assets/wall.png.import", VRAM_IMPORT.replace(
            "detect_3d/compress_to=0", "detect_3d/compress_to=0\nprocess/size_limit=512"))

        fixed, vram = fix_import_files(self.root)

        self.assertEqual((fixed, vram), (1, 1), "the limit is off policy even where the mode is not")
        self.assertIn("compress/mode=2", path.read_text(), "and the mode it already reached is kept")
        self.assertIn("process/size_limit=0", path.read_text())

    def test_a_file_that_is_not_a_texture_is_untouched(self) -> None:
        path = self.write("assets/hit.wav.import", '[remap]\n\nimporter="wav"\n')

        fixed, _ = fix_import_files(self.root)

        self.assertEqual(fixed, 0)
        self.assertNotIn("compress/mode", path.read_text())

    def test_an_addon_pulled_from_another_repository_is_not_rewritten(self) -> None:
        self.write(
            "tools/addons.json",
            json.dumps({"addons": [{"name": "controls", "repo": "x", "ref": "main"}]}),
        )
        vendored = self.write("addons/controls/icon.svg.import", LOSSY_IMPORT)
        ours = self.write("addons/gut/icon.png.import", LOSSY_IMPORT)

        fixed, _ = fix_import_files(self.root)

        self.assertEqual(fixed, 1, "only the addon that is not pulled from elsewhere")
        self.assertEqual(vendored.read_text(), LOSSY_IMPORT, "the pull would undo it anyway")
        self.assertIn("compress/mode=0", ours.read_text(), "a third-party addon committed here is ours to fix")

    def test_without_a_manifest_nothing_counts_as_vendored(self) -> None:
        self.assertEqual(vendored_addons(self.root), set())

    def test_the_project_defaults_are_put_back_on_policy(self) -> None:
        project = self.write("project.godot", FORCED_PROJECT)

        changed = fix_project_file(project)

        self.assertEqual(len(changed), 2, changed)
        self.assertIn('&"compress/mode": 0', project.read_text())
        self.assertIn('&"detect_3d/compress_to": 1', project.read_text())
        self.assertIn('&"process/size_limit": 0', project.read_text(), "the web build caps itself, not the source")

    def test_a_project_wide_size_limit_is_cleared(self) -> None:
        project = self.write("project.godot", FORCED_PROJECT.replace(
            '&"process/size_limit": 0', '&"process/size_limit": 512'))

        changed = fix_project_file(project)

        self.assertEqual(len(changed), 3, changed)
        self.assertIn('&"process/size_limit": 0', project.read_text(), "the source keeps its resolution")

    def test_a_project_already_on_policy_reports_no_change(self) -> None:
        project = self.write("project.godot", FORCED_PROJECT)
        fix_project_file(project)

        self.assertEqual(fix_project_file(project), [])

    def test_check_reports_without_writing(self) -> None:
        project = self.write("project.godot", FORCED_PROJECT)
        texture = self.write("assets/rock.png.import", LOSSY_IMPORT)

        changed = fix_project_file(project, dry_run=True)
        fixed, _ = fix_import_files(self.root, dry_run=True)

        self.assertEqual(len(changed), 2)
        self.assertEqual(fixed, 1)
        self.assertEqual(project.read_text(), FORCED_PROJECT, "--check must not write")
        self.assertEqual(texture.read_text(), LOSSY_IMPORT, "--check must not write")


if __name__ == "__main__":
    unittest.main()
