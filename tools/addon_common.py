#!/usr/bin/env python3
"""Shared pieces for pull_addons.py and push_addons.py.

An addon lives in one repository with the addon at its root. This project vendors a copy of that
root into addons/<name>/, committed like any other file, so the project always opens without a
fetch step. What is copied is the addon payload only: the repository's own demo project, CI
workflows and git metadata stay upstream.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

# Top-level entries in an addon repository that are the repository's scaffolding rather than the
# addon. "demo" is the standalone Godot project at the repository root; the demo *scene* inside the
# addon (scenes/demo/) is part of the addon and is copied.
EXCLUDED_TOP_LEVEL = {
    ".git",
    ".github",
    ".gitignore",
    ".gitattributes",
    ".gitmodules",
    ".godot",
    ".mcp",
    "demo",
    "build",
    "test-results",
    "__pycache__",
}

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "tools" / "addons.json"
LOCKFILE = ROOT / "tools" / "addons.lock.json"
CACHE = ROOT / ".addon_cache"


def run(args: list[str], cwd: Path | None = None, check: bool = True) -> str:
    """Run a command and return its stdout, raising on failure unless check is False."""
    result = subprocess.run(
        args, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"{' '.join(args)}\n  exit {result.returncode}\n  {result.stderr.strip()}"
        )
    return result.stdout.strip()


def load_manifest() -> list[dict]:
    if not MANIFEST.exists():
        sys.exit(f"No manifest at {MANIFEST}")
    return json.loads(MANIFEST.read_text(encoding="utf-8"))["addons"]


def load_lock() -> dict:
    if not LOCKFILE.exists():
        return {}
    return json.loads(LOCKFILE.read_text(encoding="utf-8"))


def save_lock(data: dict) -> None:
    LOCKFILE.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def is_third_party(addon: dict) -> bool:
    """Whether the addon is somebody else's work: pulled and pinned like the rest, never pushed to."""
    return bool(addon.get("third_party", False))


def resolve_ref(cache: Path, ref: str) -> str:
    """What to check out for a manifest ref: a branch on origin, else a tag, else a commit."""
    for candidate in (f"origin/{ref}", f"refs/tags/{ref}", ref):
        try:
            run(["git", "rev-parse", "--verify", "--quiet", f"{candidate}^{{commit}}"], cwd=cache)
            return candidate
        except RuntimeError:
            continue
    raise RuntimeError(f"{ref} is not a branch, tag or commit of {cache.name}")


def is_archive(addon: dict) -> bool:
    """Whether the addon is published as a release archive rather than a git repository."""
    return "archive" in addon


def sync_archive(addon: dict, fetch: bool = True) -> tuple[Path, str]:
    """Download the addon's release archive and unpack it into .addon_cache/<name>.

    Some addons (GodotSteam's GDExtension) are only published as a zip or tarball of prebuilt
    binaries, with no repository to clone. The archive is kept beside the unpacked tree as
    .addon_cache/<name>.<ext>, downloaded again only when the manifest names a different URL, and
    the lock records its URL and SHA-256 in place of a commit. Returns the unpacked tree and the digest.
    """
    import hashlib
    import shutil
    import tarfile
    import urllib.request
    import zipfile

    CACHE.mkdir(exist_ok=True)
    url = addon["archive"]
    ext = ".zip" if url.lower().endswith(".zip") else ".tar" + ("." + url.rsplit(".", 1)[-1] if not url.endswith(".tar") else "")
    archive = CACHE / (addon["name"] + ext)
    stamp = CACHE / (addon["name"] + ".url")
    path = CACHE / addon["name"]

    if fetch and not (archive.exists() and stamp.exists() and stamp.read_text(encoding="utf-8").strip() == url):
        print(f"  downloading {url}")
        with urllib.request.urlopen(url) as response, archive.open("wb") as out:
            shutil.copyfileobj(response, out)
        stamp.write_text(url + "\n", encoding="utf-8")
        if path.exists():
            shutil.rmtree(path)
    if not archive.exists():
        raise RuntimeError(f"{archive.name} is not in the cache; run without --offline")

    if not path.exists():
        path.mkdir()
        if ext == ".zip":
            with zipfile.ZipFile(archive) as z:
                z.extractall(path)
        else:
            with tarfile.open(archive) as t:
                t.extractall(path)
        # A single top-level folder is the archive's own wrapper, not part of the layout.
        entries = [p for p in path.iterdir() if not p.name.startswith("__MACOSX")]
        if len(entries) == 1 and entries[0].is_dir():
            inner = entries[0]
            for child in list(inner.iterdir()):
                shutil.move(str(child), str(path / child.name))
            inner.rmdir()

    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    return path, digest


def sync_cache(addon: dict, fetch: bool = True) -> Path:
    """Clone the addon's repository into .addon_cache/<name>, or fetch it if already there."""
    CACHE.mkdir(exist_ok=True)
    path = CACHE / addon["name"]

    if not (path / ".git").exists():
        print(f"  cloning {addon['repo']}")
        run(["git", "clone", "--quiet", addon["repo"], str(path)])
    elif fetch:
        run(["git", "fetch", "--quiet", "--tags", "origin"], cwd=path)

    return path


def addon_source(cache: Path, name: str) -> Path:
    """Where the addon itself sits inside its repository.

    The Godot Asset Library layout puts the addon at addons/<name>/ and makes the repository root a
    Godot project, so the repository can be opened and the addon edited in place. Repositories not
    yet converted still keep the addon at their root. Both are handled by looking for plugin.cfg.
    """
    nested = cache / "addons" / name
    if not nested.exists():
        # An archive may unpack with the addon folder at its root rather than under addons/.
        found = [p for p in cache.rglob(name) if p.is_dir() and (p / "plugin.cfg").exists()]
        if found:
            nested = found[0]
    # plugin.cfg marks an editor plugin; a GDExtension has a .gdextension file and no plugin.cfg.
    if (nested / "plugin.cfg").exists() or any(nested.glob("*.gdextension")):
        return nested
    return cache


def local_checkout(addon: dict) -> Path | None:
    r"""The sibling clone of the addon beside this project, if there is one.

    Every addon is also cloned under C:\GitHub with the name git clone produces, and that copy is
    the one worked in. Pushing through it rather than through .addon_cache/ means the local clone
    ends up holding the change too, instead of silently falling behind its own origin.
    """
    name = addon["repo"].rstrip("/").rsplit("/", 1)[-1]
    if name.endswith(".git"):
        name = name[:-4]
    path = ROOT.parent / name
    return path if (path / ".git").exists() else None


def payload_entries(source: Path) -> list[Path]:
    """The top-level entries of an addon repository that make up the addon itself."""
    return sorted(
        p for p in source.iterdir() if p.name not in EXCLUDED_TOP_LEVEL and not is_replace_fragment(p.name)
    )


def is_replace_fragment(name: str) -> bool:
    """Whether a file name is what Windows leaves behind when it replaces a file that is in use.

    Overwriting a DLL that a running program has loaded (an open Godot editor holding a GDExtension,
    say) cannot delete the old file, so Windows swaps the new one in and parks the old one beside it,
    hidden, as ~<name>~RF<hex>.TMP until whatever holds it lets go. It is never addon content: not
    something to copy into a repository, not something to count as a local change, and not something
    to treat as an upstream deletion. The mirror skips it on both sides and the pull sweeps up any it
    can remove.
    """
    upper = name.upper()
    return name.startswith("~") and "~RF" in upper and upper.endswith(".TMP")


def sweep_replace_fragments(root: Path) -> tuple[list[Path], list[Path]]:
    """Remove every replace fragment under root that can be removed.

    Returns (removed, held): a fragment whose original is still loaded by another program cannot be
    deleted yet and is reported in `held` so the caller can say so rather than fail on it.
    """
    removed: list[Path] = []
    held: list[Path] = []
    if not root.exists():
        return removed, held
    for path in root.rglob("*"):
        if not path.is_file() or not is_replace_fragment(path.name):
            continue
        try:
            path.unlink()
            removed.append(path)
        except OSError:
            held.append(path)
    return removed, held


def mirror(
    source: Path, dest: Path, dry_run: bool = False, protect: set[str] | None = None
) -> tuple[int, int]:
    """Make dest match source for the addon payload. Returns (copied, deleted) counts.

    Files present in dest but not in source are removed, so a deletion propagates. `protect` names
    top-level entries in dest that are never removed however absent they are from source.

    Getting `protect` wrong is destructive, so the two callers are deliberate about it. Pulling into
    addons/<name>/ protects nothing but .git, because that folder is wholly script-managed and
    leftovers such as a vendored demo/ must go. Pushing into a clone of the addon's repository
    protects all of EXCLUDED_TOP_LEVEL, because the repository's own demo/, .github/ and
    .gitmodules live there legitimately and are not ours to delete.
    """
    protect = (protect or set()) | {".git"}
    wanted = {p.name for p in payload_entries(source)}
    copied = 0
    removed: list[Path] = []

    if dest.exists():
        for entry in dest.iterdir():
            if entry.name in protect or is_replace_fragment(entry.name):
                continue
            if entry.name not in wanted:
                removed.extend(_files_under(entry))
                if not dry_run:
                    _rmtree(entry)

    for entry in payload_entries(source):
        target = dest / entry.name
        if entry.is_dir():
            copied += _mirror_dir(entry, target, dry_run, removed)
        else:
            if not _same_file(entry, target):
                copied += 1
                if not dry_run:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(entry, target)

    return copied, removed


def local_edits(source: Path, dest: Path) -> list[Path]:
    """Files in dest that differ from source, meaning they were changed here since that pull.

    Pass the addon at the commit tools/addons.lock.json says was last pulled. A difference against
    *that* is work done in this project's copy and never sent upstream; a difference against the
    incoming commit would just be an upstream change, and the two are indistinguishable from the
    filesystem alone. That is the whole reason the lock file is worth consulting here.

    Only files that exist in both are edits. One that is missing from dest is simply new upstream,
    and one that is missing from source is local-only, which mirror() already reports as a removal.
    """
    edited: list[Path] = []
    for entry in payload_entries(source):
        target = dest / entry.name
        if entry.is_dir():
            for path in _files_under(entry):
                mirrored = target / path.relative_to(entry)
                if mirrored.exists() and not _same_file(path, mirrored):
                    edited.append(mirrored)
        elif target.exists() and not _same_file(entry, target):
            edited.append(target)
    return sorted(edited)


def _mirror_dir(source: Path, dest: Path, dry_run: bool, removed: list[Path]) -> int:
    copied = 0
    source_names = set()

    for entry in source.iterdir():
        if entry.name in {"__pycache__", ".godot"} or is_replace_fragment(entry.name):
            continue
        source_names.add(entry.name)
        target = dest / entry.name
        if entry.is_dir():
            copied += _mirror_dir(entry, target, dry_run, removed)
        elif not _same_file(entry, target):
            copied += 1
            if not dry_run:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(entry, target)

    # Deletions here are the dangerous half: a file present locally but not upstream is either an
    # upstream removal or work that has not been pushed yet. Every one is recorded by name so the
    # caller can show it, because a silent delete of unpushed work is exactly the trap to avoid.
    if dest.exists():
        for entry in dest.iterdir():
            if is_replace_fragment(entry.name):
                continue
            if entry.name not in source_names:
                removed.extend(_files_under(entry))
                if not dry_run:
                    _rmtree(entry)

    if not dry_run:
        dest.mkdir(parents=True, exist_ok=True)

    return copied


def _same_file(a: Path, b: Path) -> bool:
    """Compare by content, not by timestamp.

    A fresh clone carries fresh mtimes, so a size-and-mtime check would call every file changed on
    every run. Size rejects almost everything cheaply; only same-size files are read, and a
    re-saved .tres that keeps its length is exactly the case that has to be caught.
    """
    if not b.exists():
        return False
    if a.stat().st_size != b.stat().st_size:
        return False
    return _digest(a) == _digest(b)


def _digest(path: Path) -> str:
    import hashlib

    h = hashlib.blake2b(digest_size=16)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _files_under(path: Path) -> list[Path]:
    if path.is_file():
        return [] if is_replace_fragment(path.name) else [path]
    return [p for p in path.rglob("*") if p.is_file() and not is_replace_fragment(p.name)]


def _rmtree(path: Path) -> None:
    import os
    import stat

    def on_error(func, target, _exc):
        os.chmod(target, stat.S_IWRITE)
        func(target)

    if path.is_dir():
        shutil.rmtree(path, onerror=on_error)
    else:
        path.unlink()
