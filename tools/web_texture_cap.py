#!/usr/bin/env python3
"""Cap imported texture size for a web build, without touching the source images.

Source textures are committed at full resolution and imported at full resolution, so a desktop
build gets the fidelity the artist shipped. The web build is the one place where load time is the
binding constraint, so it caps the largest edge instead.

A texture's size limit is an import-time setting, baked into `.godot/imported/*.ctex`, so it cannot
be chosen at export time. What can be done is to set the limit before the export's import pass. Run
this in CI ahead of `--import` and the web build alone is capped; nothing it changes is committed,
because CI works on a fresh checkout it throws away.

    python3 tools/web_texture_cap.py            # cap at 512
    python3 tools/web_texture_cap.py --size 256

It rewrites `process/size_limit` in `project.godot`'s importer defaults, which decides what any
newly imported texture gets, and in every `.import` file beside a texture, which is what the
already-imported ones actually read.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Godot writes the project-wide default with a quoted StringName key and the per-file one bare.
PROJECT_SETTING = re.compile(r'(&"process/size_limit":\s*)(\d+)')
IMPORT_SETTING = re.compile(r'^(process/size_limit=)(\d+)$', re.MULTILINE)

SKIP_DIRS = {".git", ".godot", ".addon_cache", "build", "__pycache__"}


def cap_project_file(project_file: Path, size: int) -> bool:
    """Set the importer default every future import inherits. Returns whether anything changed."""
    if not project_file.exists():
        return False
    text: str = project_file.read_text()
    capped: str = PROJECT_SETTING.sub(lambda m: f"{m.group(1)}{size}", text)
    if capped == text:
        return False
    project_file.write_text(capped)
    return True


def cap_import_files(root: Path, size: int) -> int:
    """Set the limit on every already-imported texture. Returns how many files changed."""
    changed: int = 0
    for path in root.rglob("*.import"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        text: str = path.read_text()
        capped: str = IMPORT_SETTING.sub(lambda m: f"{m.group(1)}{size}", text)
        if capped != text:
            path.write_text(capped)
            changed += 1
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--size", type=int, default=512, help="Largest edge in pixels (default: 512); 0 removes the cap")
    parser.add_argument("--root", type=str, default=str(ROOT), help="Project root (default: this repository)")
    args = parser.parse_args()

    if args.size < 0:
        print("[Error] --size cannot be negative; use 0 to remove the cap.")
        return 1

    root = Path(args.root)
    project_changed: bool = cap_project_file(root / "project.godot", args.size)
    imports_changed: int = cap_import_files(root, args.size)

    limit: str = "no limit" if args.size == 0 else f"{args.size} px"
    print(f"Texture size limit set to {limit}")
    print(f"  project.godot importer default: {'updated' if project_changed else 'already set'}")
    print(f"  .import files updated:          {imports_changed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
