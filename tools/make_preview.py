#!/usr/bin/env python3
"""Turn an in-engine screenshot into a repository preview image.

Previews are 960x540, the size the portfolio site at kirbycope.github.io uses, and are compressed
through TinyPNG before they are committed.

    python tools/make_preview.py <screenshot.png> <destination.png>

The source should already be 16:9. A Godot project whose stretch aspect is "keep" on a 16:10 base
letterboxes every window size back to 16:10, so set the root's content_scale_aspect to EXPAND at
runtime before capturing rather than cropping afterwards and losing the edges of the HUD.
"""

from __future__ import annotations

import sys
from pathlib import Path

WIDTH, HEIGHT = 960, 540


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    source, dest = Path(sys.argv[1]), Path(sys.argv[2])
    if not source.exists():
        sys.exit(f"No such screenshot: {source}")

    from PIL import Image

    image = Image.open(source)
    ratio = image.width / image.height
    target = WIDTH / HEIGHT
    if abs(ratio - target) > 0.01:
        print(f"[Warning] {source.name} is {image.width}x{image.height} ({ratio:.2f}), not 16:9 "
              f"({target:.2f}). It will be centre-cropped, which trims the edges of the HUD.")
        if ratio > target:
            new_width = int(image.height * target)
            left = (image.width - new_width) // 2
            image = image.crop((left, 0, left + new_width, image.height))
        else:
            new_height = int(image.width / target)
            top = (image.height - new_height) // 2
            image = image.crop((0, top, image.width, top + new_height))

    image = image.convert("RGB").resize((WIDTH, HEIGHT), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest, "PNG", optimize=True)
    resized = dest.stat().st_size

    sys.path.insert(0, str(Path(__file__).parent))
    import tinyify

    key = tinyify.load_api_key(Path.cwd())
    if key is None:
        print(f"{dest}: {WIDTH}x{HEIGHT}, {resized:,} bytes. No TinyPNG key found, not compressed.")
        return 0

    tinify = tinyify.get_tinify_module(key)
    tinify.from_file(str(dest)).to_file(str(dest))
    final = dest.stat().st_size
    print(f"{dest}: {WIDTH}x{HEIGHT}, {resized:,} -> {final:,} bytes "
          f"({100 - final * 100 // resized}% off with TinyPNG)")
    print(f"TinyPNG compressions used this month: {tinify.compression_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
