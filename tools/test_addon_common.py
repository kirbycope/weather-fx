#!/usr/bin/env python3
"""Tests for the addon tooling's handling of Windows replace fragments.

Run with:  python -m unittest tools/test_addon_common.py

When pull_addons.py overwrites a DLL that a running program has loaded, an open Godot editor holding
a GDExtension for instance, Windows cannot delete the old file. It swaps the new one in and parks the
old one beside it, hidden, as ~<name>~RF<hex>.TMP. That file used to be mirrored into the addon's
clone by push_addons.py, where git saw an untracked file and the pre-push hook refused the push,
every time, until someone deleted it by hand. These tests hold the fix: a fragment is recognised, the
mirror ignores it on both sides, and the sweep removes what it can and reports what is still held.
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from addon_common import (  # noqa: E402
    is_replace_fragment,
    local_edits,
    mirror,
    sweep_replace_fragments,
)

FRAGMENT = "~libpure_doom.windows.template_debug.x86_64.dll~RF1c6eaf04.TMP"


class ReplaceFragmentName(unittest.TestCase):
    def test_the_name_windows_leaves_behind_is_recognised(self) -> None:
        self.assertTrue(is_replace_fragment(FRAGMENT))
        self.assertTrue(is_replace_fragment("~thing.dll~rfABCD1234.tmp"), "case does not matter")

    def test_ordinary_files_are_not(self) -> None:
        for name in ["libpure_doom.windows.template_debug.x86_64.dll", "~backup.tmp", "notes.TMP",
                     "~$word.docx", "RF.TMP", "plugin.cfg"]:
            self.assertFalse(is_replace_fragment(name), name)


class MirrorIgnoresFragments(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.source = base / "source"
        self.dest = base / "dest"
        (self.source / "bin").mkdir(parents=True)
        (self.dest / "bin").mkdir(parents=True)
        (self.source / "plugin.cfg").write_text("[plugin]\n")
        (self.source / "bin" / "lib.dll").write_bytes(b"new")
        (self.dest / "plugin.cfg").write_text("[plugin]\n")
        (self.dest / "bin" / "lib.dll").write_bytes(b"old")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_a_fragment_in_dest_is_neither_a_local_change_nor_deleted_work(self) -> None:
        fragment = self.dest / "bin" / FRAGMENT
        fragment.write_bytes(b"old copy windows could not delete")
        copied, removed = mirror(self.source, self.dest, dry_run=True)
        self.assertEqual(copied, 1, "only lib.dll differs")
        self.assertEqual(removed, [], "the fragment is not reported as work that would be lost")
        mirror(self.source, self.dest, dry_run=False)
        self.assertTrue(fragment.exists(), "and the mirror leaves it alone; the sweep is what clears it")
        self.assertEqual((self.dest / "bin" / "lib.dll").read_bytes(), b"new")

    def test_a_fragment_in_source_is_never_copied_into_a_repository(self) -> None:
        # this is the push direction: the project's vendored copy is the source, the clone the dest
        (self.source / "bin" / FRAGMENT).write_bytes(b"parked")
        copied, _removed = mirror(self.source, self.dest, dry_run=False)
        self.assertEqual(copied, 1)
        self.assertFalse((self.dest / "bin" / FRAGMENT).exists(), "nothing for git status to flag")


class SweepFragments(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "addon"
        (self.root / "bin").mkdir(parents=True)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_a_free_fragment_is_removed_and_a_held_one_is_reported(self) -> None:
        free = self.root / "bin" / FRAGMENT
        free.write_bytes(b"free")
        held_path = self.root / "bin" / "~other.dll~RFbeef0000.TMP"
        held_path.write_bytes(b"held")
        # holding a handle without delete sharing is what a loaded DLL amounts to on Windows
        handle = open(held_path, "rb")
        try:
            removed, held = sweep_replace_fragments(self.root)
        finally:
            handle.close()
        if os.name == "nt":
            self.assertEqual(removed, [free])
            self.assertEqual(held, [held_path], "the one still open is named, not failed on")
            self.assertTrue(held_path.exists())
        else:
            # A POSIX unlink of an open file succeeds, so both go and nothing is held. The held
            # assertion already said this; the removed one did not, and failed here every run.
            self.assertEqual(removed, sorted([free, held_path]))
            self.assertEqual(held, [])

    def test_ordinary_files_are_untouched(self) -> None:
        keep = self.root / "bin" / "lib.dll"
        keep.write_bytes(b"keep")
        removed, held = sweep_replace_fragments(self.root)
        self.assertEqual((removed, held), ([], []))
        self.assertTrue(keep.exists())


if __name__ == "__main__":
    unittest.main()


class LocalEdits(unittest.TestCase):
    """The check that stops a pull writing over work that was never pushed.

    mirror() copies whenever a file differs, which is how hand-tuned animation .tres files were lost
    twice: the pull counted them as "file(s) in" and said nothing about what it wrote over. Telling
    an edit made here from a change made upstream needs the commit the lock recorded to compare
    against, and local_edits is that comparison.
    """

    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.root = Path(self._temp.name)
        self.source = self.root / "source"
        self.dest = self.root / "dest"

    def tearDown(self) -> None:
        self._temp.cleanup()

    def write(self, base: Path, relative: str, text: str) -> Path:
        path = base / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_an_untouched_copy_reports_nothing(self) -> None:
        self.write(self.source, "scripts/player.gd", "extends Node\n")
        self.write(self.dest, "scripts/player.gd", "extends Node\n")

        self.assertEqual(local_edits(self.source, self.dest), [])

    def test_a_file_changed_here_is_reported(self) -> None:
        self.write(self.source, "animations/Swimming.tres", "hips = 0.699\n")
        edited = self.write(self.dest, "animations/Swimming.tres", "hips = 1.099\n")

        self.assertEqual(local_edits(self.source, self.dest), [edited])

    def test_a_file_only_upstream_is_not_an_edit(self) -> None:
        # It is simply new, and mirror() brings it in; there is nothing here to lose.
        self.write(self.source, "scripts/new_feature.gd", "extends Node\n")

        self.assertEqual(local_edits(self.source, self.dest), [])

    def test_a_file_only_here_is_left_to_the_removal_guard(self) -> None:
        # mirror() already reports this one as a removal, so counting it twice would say it wrong.
        self.write(self.source, "scripts/player.gd", "extends Node\n")
        self.write(self.dest, "scripts/player.gd", "extends Node\n")
        self.write(self.dest, "scripts/mine.gd", "extends Node\n")

        self.assertEqual(local_edits(self.source, self.dest), [])

    def test_a_same_length_edit_is_still_caught(self) -> None:
        # A re-saved .tres often keeps its length exactly, which a size check alone would miss.
        self.write(self.source, "animations/Running.tres", "hips = 0.921\n")
        edited = self.write(self.dest, "animations/Running.tres", "hips = 0.821\n")

        self.assertEqual(local_edits(self.source, self.dest), [edited])

    def test_every_edit_under_a_directory_is_listed(self) -> None:
        for name in ["Swimming", "Running", "Sprint"]:
            self.write(self.source, f"animations/{name}.tres", "raw\n")
        first = self.write(self.dest, "animations/Swimming.tres", "tuned\n")
        self.write(self.dest, "animations/Running.tres", "raw\n")
        second = self.write(self.dest, "animations/Sprint.tres", "tuned\n")

        self.assertEqual(local_edits(self.source, self.dest), sorted([first, second]))
