# Weather FX for Godot 4.8+

Biomes, precipitation, wind, wildfire, lightning, a stylized sky and water ripples, driven from one node.

**[Read the full documentation](addons/weather_fx/README.md)**, which ships with the addon so it is
there however you installed it.

## This repository

It uses the layout the [Godot Asset Library](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html) expects, so it is both the addon and a
project you can open and edit it in:

```
project.godot        the demo project, which is this repository
addons/weather_fx/        the addon itself
addons/gut/          the test runner
```

Clone it, open `project.godot` in Godot, and run the demo scene. The addon is mounted at
`res://addons/weather_fx/` exactly as it is in a game, so it is edited in place with nothing
copied anywhere first. Installing through the Asset Library takes `addons/` and skips the root
`project.godot` as a conflict, which is why that file can live here harmlessly.

## Installing it in a game

Copy `addons/weather_fx/` into your project's `addons/`. See the
[addon's README](addons/weather_fx/README.md) for what it needs and how to use it.
