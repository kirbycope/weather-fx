#!/usr/bin/env python3
"""Put texture importing back on Godot's own defaults: lossless on disk, VRAM compressed in 3D.

These projects used to force `compress/mode=1` (Lossy) on every texture, project wide, with
`detect_3d/compress_to=0` so nothing was ever promoted. That was a way of fitting built `.pck`
files under GitHub's 100 MB limit, and it cost twice over:

  Lossy re-encodes the image through WebP at quality 0.7 before Godot ever sees it, so the loss is
  permanent and lands on normal maps and ORM masks, whose pixels are surface directions and
  material coefficients rather than colours. It also uploads to VRAM *uncompressed*, so it buys
  nothing at run time; the saving is only in the file on disk. A vector icon imported this way is
  blurred for no gain at all.

Nothing is built and committed any more, so the limit does not apply. The policy is now whatever
Godot itself would do with a freshly dropped in texture:

  compress/mode          0   Lossless
  detect_3d/compress_to  1   VRAM Compressed, once the editor sees the texture used in 3D
  process/size_limit     0   full resolution; tools/web_texture_cap.py caps the web build alone

A texture already at `compress/mode=2` is left alone: that is Godot's own end state after it has
detected 3D use, and re-running the detection would only arrive back at the same place.

    python3 tools/texture_import_policy.py                  # this repository
    python3 tools/texture_import_policy.py --root ../gta    # another one
    python3 tools/texture_import_policy.py --check          # report only, non-zero if off policy
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

LOSSLESS = 0
VRAM_COMPRESSED = 2

# Godot writes the project-wide defaults with quoted StringName keys and the per-file ones bare.
PROJECT_COMPRESS = re.compile(r'(&"compress/mode":\s*)(\d+)')
PROJECT_DETECT_3D = re.compile(r'(&"detect_3d/compress_to":\s*)(\d+)')
PROJECT_SIZE_LIMIT = re.compile(r'(&"process/size_limit":\s*)(\d+)')
IMPORT_COMPRESS = re.compile(r"^(compress/mode=)(\d+)$", re.MULTILINE)
IMPORT_DETECT_3D = re.compile(r"^(detect_3d/compress_to=)(\d+)$", re.MULTILINE)
IMPORT_SIZE_LIMIT = re.compile(r"^(process/size_limit=)(\d+)$", re.MULTILINE)

SKIP_DIRS = {".git", ".godot", ".addon_cache", "build", "__pycache__"}


def vendored_addons(root: Path) -> set[Path]:
    """The addon folders this project pulls from elsewhere, which are not ours to change here.

    A vendored addon is fixed in the repository it comes from; editing the copy would only be
    undone by the next `pull_addons.py`. Everything else under addons/ is either the repository's
    own addon, when this is an addon repository, or a third-party one committed here, and both do
    need fixing. tools/addons.json is what tells the two apart, so a repository without one has
    nothing vendored.
    """
    manifest = root / "tools" / "addons.json"
    if not manifest.exists():
        return set()
    entries = json.loads(manifest.read_text(encoding="utf-8"))["addons"]
    return {(root / "addons" / entry["name"]).resolve() for entry in entries}


def read_mode(text: str) -> int | None:
    """The compress/mode an .import file declares, or None if it declares none."""
    match = IMPORT_COMPRESS.search(text)
    return int(match.group(2)) if match else None


def fix_project_file(project_file: Path, dry_run: bool = False) -> list[str]:
    """Put the importer defaults back on policy. Returns what changed, by name."""
    if not project_file.exists():
        return []
    text: str = project_file.read_text()
    changed: list[str] = []

    fixed: str = text
    if (match := PROJECT_COMPRESS.search(fixed)) and int(match.group(2)) != LOSSLESS:
        changed.append(f"compress/mode {match.group(2)} -> {LOSSLESS}")
        fixed = PROJECT_COMPRESS.sub(lambda m: f"{m.group(1)}{LOSSLESS}", fixed)
    if (match := PROJECT_DETECT_3D.search(fixed)) and int(match.group(2)) != 1:
        changed.append(f"detect_3d/compress_to {match.group(2)} -> 1")
        fixed = PROJECT_DETECT_3D.sub(lambda m: f"{m.group(1)}1", fixed)
    if (match := PROJECT_SIZE_LIMIT.search(fixed)) and int(match.group(2)) != 0:
        changed.append(f"process/size_limit {match.group(2)} -> 0")
        fixed = PROJECT_SIZE_LIMIT.sub(lambda m: f"{m.group(1)}0", fixed)

    if changed and not dry_run:
        project_file.write_text(fixed)
    return changed


def fix_import_files(root: Path, dry_run: bool = False) -> tuple[int, int]:
    """Put every off-policy .import back on it. Returns (fixed, left as VRAM compressed).

    Two separate things can be off policy, and a file can be off on either. `compress/mode` decides
    how much of the image survives the import; `process/size_limit` decides how much of it is even
    read, and a committed 512 there is the downscale rule wearing a different hat. The web build
    puts its own limit back on a CI checkout, which is thrown away.
    """
    fixed: int = 0
    vram: int = 0
    vendored: set[Path] = vendored_addons(root)

    for path in sorted(root.rglob("*.import")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if any(path.resolve().is_relative_to(folder) for folder in vendored):
            continue
        text: str = path.read_text()
        mode: int | None = read_mode(text)
        if mode is None:
            continue

        updated: str = text
        if mode == VRAM_COMPRESSED:
            vram += 1
        elif mode != LOSSLESS:
            # Lossy, or one of the Basis Universal modes: back to lossless, and let the editor
            # promote it to VRAM compressed the first time it sees the texture on a 3D material.
            updated = IMPORT_COMPRESS.sub(lambda m: f"{m.group(1)}{LOSSLESS}", updated)
            updated = IMPORT_DETECT_3D.sub(lambda m: f"{m.group(1)}1", updated)

        updated = IMPORT_SIZE_LIMIT.sub(lambda m: f"{m.group(1)}0", updated)

        if updated == text:
            continue
        fixed += 1
        if not dry_run:
            path.write_text(updated)

    return fixed, vram


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--root", type=str, default=str(ROOT), help="Project root (default: this repository)")
    parser.add_argument("--check", action="store_true", help="Report without writing; exit 1 if anything is off policy")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"[Error] No such directory: {root}")
        return 1

    project_changes: list[str] = fix_project_file(root / "project.godot", dry_run=args.check)
    fixed, vram = fix_import_files(root, dry_run=args.check)

    print(f"{root.name}")
    for change in project_changes:
        print(f"  project.godot: {change}")
    if not project_changes:
        print("  project.godot: already on policy")
    print(f"  .import files {'off policy' if args.check else 'set to lossless'}: {fixed}")
    print(f"  .import files left VRAM compressed:          {vram}")

    if args.check and (project_changes or fixed):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
