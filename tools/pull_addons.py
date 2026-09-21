#!/usr/bin/env python3
"""Pull the addons named in tools/addons.json into addons/, like an install step.

Each addon's repository is cloned into .addon_cache/ (git-ignored), checked out at the ref the
manifest asks for, and its payload copied into addons/<name>/. The resolved commit of each is
written to tools/addons.lock.json, so what is vendored is always traceable to a commit upstream.

    python tools/pull_addons.py                 every addon in the manifest
    python tools/pull_addons.py controls gta    only these
    python tools/pull_addons.py --dry-run       report what would change, touch nothing
    python tools/pull_addons.py --locked        take the commits in the lock file, not the ref

The copies under addons/ are git-ignored, GUT and the other third-party addons included; only
the manifest and the lock are committed, so a fresh clone runs this once before anything else.
A third-party addon (`"third_party": true`) is pinned to a release tag or commit and never pushed
to; one published only as a release archive names it with `"archive": <url>` instead of a repo.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone

from addon_common import (
    ROOT,
    addon_source,
    load_lock,
    load_manifest,
    local_edits,
    mirror,
    run,
    is_archive,
    resolve_ref,
    sync_archive,
    save_lock,
    sweep_replace_fragments,
    sync_cache,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Vendor the addons into addons/")
    parser.add_argument("names", nargs="*", help="Only these addons (default: all)")
    parser.add_argument("--dry-run", action="store_true", help="Report, change nothing")
    parser.add_argument(
        "--locked",
        action="store_true",
        help="Check out the commits recorded in tools/addons.lock.json instead of the manifest ref",
    )
    parser.add_argument("--offline", action="store_true", help="Do not fetch, use the cache as is")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite files edited here and delete local files that are not upstream. Without it, "
        "a pull that would destroy either stops so the work can be pushed first.",
    )
    args = parser.parse_args()

    addons = load_manifest()
    if args.names:
        wanted = set(args.names)
        unknown = wanted - {a["name"] for a in addons}
        if unknown:
            sys.exit(f"Not in the manifest: {', '.join(sorted(unknown))}")
        addons = [a for a in addons if a["name"] in wanted]

    lock = load_lock()
    changed = False
    blocked = False

    print(f"Project:  {ROOT}")
    print(f"Addons:   {len(addons)}")
    print()

    for addon in addons:
        name = addon["name"]
        dest = ROOT / "addons" / name

        if is_archive(addon):
            # A release archive: no repository, no commits. The lock holds the URL and a digest, and
            # the edit guard below has no earlier tree to diff against, so the removal guard is all.
            try:
                if args.locked and name in lock and "archive" in lock[name]:
                    addon = dict(addon, archive=lock[name]["archive"])
                cache, commit = sync_archive(addon, fetch=not args.offline)
            except (RuntimeError, OSError) as exc:
                print(f"{name:<28} FAILED  {exc}")
                continue
            subject = addon["archive"].rsplit("/", 1)[-1]
            previous = None
        else:
            try:
                cache = sync_cache(addon, fetch=not args.offline)
            except RuntimeError as exc:
                print(f"{name:<28} FAILED  {exc}")
                continue

            try:
                if args.locked and name in lock:
                    target = lock[name]["commit"]
                else:
                    # A branch on origin, a release tag (a third-party addon is pinned to one) or a commit.
                    target = resolve_ref(cache, addon["ref"])
                run(["git", "checkout", "--quiet", "--force", target], cwd=cache)
            except RuntimeError as exc:
                print(f"{name:<28} FAILED  cannot check out {addon['ref']}: {exc}")
                continue

            commit = run(["git", "rev-parse", "HEAD"], cwd=cache)
            subject = run(["git", "log", "-1", "--pretty=%s"], cwd=cache)
            previous = lock.get(name, {}).get("commit")

        # Look before touching anything, so a pull that would destroy unpushed work can stop.
        origin = addon_source(cache, name)
        copied, removed = mirror(origin, dest, dry_run=True)

        # mirror() copies whenever a file differs, which includes a file edited here and never
        # pushed. That is how hand-tuned animation .tres files were lost twice: the pull reported
        # them as "file(s) in" and said nothing about what it wrote over. Diffing against the commit
        # the lock recorded is what separates an edit made here from a change made upstream.
        # Both halves matter. Differing from the locked commit makes it an edit made here; differing
        # from the incoming one makes it something mirror() is about to write over. A file that has
        # drifted from the lock but already matches what is arriving is in no danger at all, and
        # counting it would cry wolf over every addon whose lock has simply fallen behind.
        edited: list = []
        if previous and previous != commit:
            incoming = set(local_edits(origin, dest))
            try:
                run(["git", "checkout", "--quiet", "--force", previous], cwd=cache)
                edited = [p for p in local_edits(addon_source(cache, name), dest) if p in incoming]
            except RuntimeError:
                edited = []  # The recorded commit is gone; report nothing rather than block blindly.
            finally:
                run(["git", "checkout", "--quiet", "--force", target], cwd=cache)
                origin = addon_source(cache, name)
        elif previous:
            # Nothing new upstream, so anything mirror() would copy is an edit made here.
            edited = local_edits(origin, dest)

        if edited:
            noun = "file(s) edited here since the last pull"
            if args.force:
                print(f"{name:<28} {commit[:7]}  OVERWRITING {len(edited)} {noun}")
            elif args.dry_run:
                print(f"{name:<28} {commit[:7]}  WOULD OVERWRITE {len(edited)} {noun}")
            else:
                print(f"{name:<28} {commit[:7]}  STOPPED: {len(edited)} {noun}")
            for path in edited[:10]:
                print(f"{'':<28}   {path.relative_to(dest)}")
            if len(edited) > 10:
                print(f"{'':<28}   ... and {len(edited) - 10} more")
            if not (args.force or args.dry_run):
                print(f"{'':<28} push them first with tools/push_addons.py, or re-run with --force to overwrite")
                blocked = True
                continue

        if removed and not (args.force or args.dry_run):
            print(f"{name:<28} {commit[:7]}  STOPPED: {len(removed)} local file(s) are not upstream")
            for path in removed[:10]:
                print(f"{'':<28}   {path.relative_to(dest)}")
            if len(removed) > 10:
                print(f"{'':<28}   ... and {len(removed) - 10} more")
            print(f"{'':<28} push them first, or re-run with --force to delete them")
            blocked = True
            continue

        held: list = []
        if not args.dry_run:
            copied, removed = mirror(origin, dest, dry_run=False)
            # A file that another program has loaded, a GDExtension DLL held by an open editor, cannot be
            # deleted when it is replaced; Windows parks the old copy beside the new one, hidden, as
            # ~<name>~RF<hex>.TMP. Sweep up any that are free now; name the ones still held.
            _swept, held = sweep_replace_fragments(dest)

        if copied or removed:
            changed = True
            verb = "would update" if args.dry_run else "updated"
            print(f"{name:<28} {commit[:7]}  {verb}: {copied} file(s) in, {len(removed)} removed")
            for path in removed[:10]:
                print(f"{'':<28}   removed {path.relative_to(dest)}")
            if len(removed) > 10:
                print(f"{'':<28}   ... and {len(removed) - 10} more removed")
        elif previous != commit:
            changed = True
            print(f"{name:<28} {commit[:7]}  same files, new commit recorded")
        else:
            print(f"{name:<28} {commit[:7]}  up to date")

        if subject:
            print(f"{'':<28} {subject[:70]}")
        for path in held:
            original = path.name[1:].split("~RF")[0]
            print(f"{'':<28} {original} is held open by another program (an open editor?); its old copy is "
                  f"parked beside it until that closes")

        if not args.dry_run:
            lock[name] = {
                "commit": commit,
                "subject": subject,
                "pulled": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            }
            if is_archive(addon):
                lock[name]["archive"] = addon["archive"]  # commit holds the archive's SHA-256
            else:
                lock[name]["repo"] = addon["repo"]
                lock[name]["ref"] = addon["ref"]

    print()

    if args.dry_run:
        print("Dry run, nothing was written.")
        return 0

    save_lock(lock)

    if blocked:
        print("Some addons were left alone because a pull would have deleted local work.")
        print("Send it upstream with tools/push_addons.py, then pull again.")
        return 1

    if not changed:
        print("Everything already matches upstream.")
        return 0

    print("Vendored copies updated. Review and commit:")
    print("  git add addons tools/addons.lock.json")
    print('  git commit -m "Update the vendored addons"')
    return 0


if __name__ == "__main__":
    sys.exit(main())
