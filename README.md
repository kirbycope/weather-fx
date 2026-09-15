![Preview](addons/weather_fx/assets/weather-fx.png)

# Weather FX for Godot 4.8+

Biomes, precipitation, wind, wildfire, lightning, a stylized sky and water ripples, driven from
one node.

**[Read the full documentation](addons/weather_fx/README.md)**, which ships with the addon so it is
there however you installed it.

## This repository

It uses the layout the [Godot Asset Library](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html) expects, so it is both the addon and a
project you can open and edit it in:

```
project.godot       the demo project, which is this repository
addons/weather_fx/  the addon itself
addons/gut/         the test runner
```

Clone it, open `project.godot` in Godot, and run the demo scene. The addon is mounted at
`res://addons/weather_fx/` exactly as it is in a game, so it is edited in place with nothing copied
anywhere first. Installing through the Asset Library takes `addons/` and skips the root
`project.godot` as a conflict, which is why that file can live here harmlessly.

## Textures import Lossless

Every texture here imports with `compress/mode=0` (Lossless) and `detect_3d/compress_to=1`, so the
editor promotes one to VRAM Compressed the first time it sees it used in 3D. That is Godot's own
default.

This repository used to force `compress/mode=1` (Lossy) with promotion disabled, project wide. That
re-encoded every image through WebP at quality 0.7 before Godot saw it, and still uploaded
uncompressed to VRAM, so it lost real data in the cloud and particle textures and bought nothing at run time. It existed only to
squeeze a built `.pck` under GitHub's 100 MB limit, and nothing built is committed any more.

`python ../godot-3d-player-controller-v3/tools/texture_import_policy.py --root .` puts the
repository back on that policy, and `--check` reports without writing.

## Installing it in a game

Copy `addons/weather_fx/` into your project's `addons/`. See the
[addon's README](addons/weather_fx/README.md) for what it needs and how to use it.
