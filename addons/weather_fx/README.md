# Weather FX for Godot 4.8+

A high-performance, modular climate, weather, and atmospheric wind simulation system for Godot 4.8+. Features 20 universal biomes, altitude- and time-based temperature lapse curves, procedural 4-minute forecasting cycles, rain ground impact effects (puddle ripples & splash droplets), global wind shader integration with stylized foliage sway, interactive Zelda-inspired HUD widgets, and a comprehensive test lab (`demo.tscn`).

> [!NOTE]
> **Plugin Activation vs Direct Scene Usage**:
> All core scripts register global class names with editor icons (`WeatherFX`, `PrecipitationFX`, `WeatherAudio`, `WeatherZone`, `WeatherForecastDisplay`, `TemperatureGaugeDisplay`, `GaugeNeedle`, `WindDirectionDial`, `WindVFX`, `FallingLeaves`, `FireFX`, `GrassField`, `BurnableGrass`, `FireTrailNode`, `ClimateData`), so they appear in the *Create New Node* dialog whether or not the plugin is enabled.
> - **Direct Usage**: Instance `scenes/weather_fx.tscn` (or add a `WeatherFX` node) and control it via GDScript immediately. Ensure the global shader parameters are added under **Project Settings > Shader Globals**.
> - **Enabling the Plugin**: Enabling `Weather FX` in **Project Settings > Plugins** registers all required **Shader Globals** in `ProjectSettings` automatically.

---

## Interactive Demo Scene

Open and run **`res://addons/weather_fx/scenes/demo/demo.tscn`** to explore the complete feature suite in real time:

- **20 Biome Explorer**: Instantly travel between all 20 biomes from a dropdown menu.
- **Weather Simulation & Overrides**: Force or procedurally simulate Blue Sky, Cloudy, Rain, Heavy Rain, Storm, Snow, or Heavy Snow.
- **Interactive 360° Wind Direction Dial**: Click and drag the circular compass dial on the HUD to rotate the global wind vector in real time.
- **Wind Multiplier Scrubber**: Adjust wind power from `0.0x` (calm) to `3.0x` (gale force) to test foliage sway and particle velocities.
- **Rain Impact Physics**: Observe raindrops bursting into upward water splashes and concentric expanding puddle ripples on ground contact.
- **Time-of-Day Scrubber**: Scrub time from 0:00 to 24:00 to test diurnal temperature swings, sunrise/sunset lighting, and day/night transitions.
- **Altitude Scrubber**: Test temperature lapse rate as altitude climbs from 0m to 1500m.
- **Unit Toggle**: Instantly switch between Celsius (`°C`) and Fahrenheit (`°F`) across all HUD displays and gauges.
- **Diagnostic Info & FPS Counter**: HUD readout (refreshed by a `StatusTimer`) of FPS, current temperature, active biome, wind speed & cardinal direction, altitude, and cycle countdown.
- **Free Camera Orbit**: Right-click drag or WASD/Arrow keys to orbit around the scene and zoom in/out with the mouse scroll wheel.

All demo UI and `WeatherFX` signal connections are wired in `demo.tscn`; `demo.gd` only holds the handlers.

---

## Core Features

### 1. 20 Universal Biomes
Provides statistical weather distribution tables, diurnal temperature ranges, altitude lapse rates, and baseline wind power across 20 distinct biomes (`ClimateData.BIOME_DEFINITIONS`):
- `TEMPERATE_PLAINS` (0), `NORTHERN_PLAINS` (1), `ARCTIC_TUNDRA` (2), `ARID_CANYON` (3), `ALPINE_PEAKS` (4)
- `DESERT_DUNES` (5), `DESERT_PLATEAU` (6), `VOLCANIC_FOOTHILLS` (7), `AUTUMN_HIGHLANDS` (8), `WETLANDS_VALLEY` (9)
- `COASTAL_PLAINS` (10), `TROPICAL_RAINFOREST` (11), `HUMID_COAST` (12), `VOLCANIC_CRATER` (13), `VOLCANIC_CALDERA` (14)
- `SHADOW_WOODS` (15), `MISTY_WOODS` (16), `DESERT_GLACIER` (17), `ANCIENT_FOREST` (18), `DEEP_DESERT` (19)

### 2. Signal-Driven Architecture
`WeatherFX` is the single simulation source. Everything else subscribes to its signals and caches the values it needs; per-frame work is reserved for continuous animation (particle drift, creeper advance, needle lerp).

- **The `"WeatherFX"` group**: every `WeatherFX` node adds itself to the `WeatherFX` group when it enters the tree. Consumers expose `@export var weather_fx: WeatherFX`; when it is left unassigned they fall back to `get_tree().get_first_node_in_group("WeatherFX")` in `_ready()`, so a single `WeatherFX` in the scene needs no manual wiring.
- **Child nodes of `weather_fx.tscn`** (each has `weather_fx` pointing at the parent):
  - `PrecipitationFX` (Node3D): rain, splash and snow `GPUParticles3D`; reacts to `weather_changed`, `wind_changed`, `playback_changed`; follows `weather_fx.target_node` and keeps the splash emitter on the ground via a raycast.
  - `WeatherAudio` (Node): weather SFX players (`audio_rain_light`, `audio_rain_heavy`, `audio_storm`, `audio_wind`) and six optional background-ambience (`bgs_*`) slots. BGS is re-evaluated only on `weather_changed`, `daylight_changed` and `playback_changed`; a player that stays the target is never restarted.
  - `WindVFX` (Node3D): wind ribbons, leaf streams (`airflow_particles` / `leaf_particles` arrays) and gust sweeps driven by `GustTimer` / `TreeCheckTimer` Timer nodes. Leaves only appear in tree biomes and, with `require_nearby_trees`, when a node in the `Tree`, `Trees`, `Foliage` or `Choppable` group is within `tree_detection_radius` (the addon's `tree_*.tscn` scenes are in `Tree`).
  - `CycleTimer` (Timer): drives `advance_cycle()`; `get_cycle_progress()` reads it.
- **Other consumers**: `FallingLeaves`, `FireFX`, `GrassField`, `BurnableGrass`, `FireTrailNode`, `WeatherZone`, `WeatherForecastDisplay`, `TemperatureGaugeDisplay` and `WindDirectionDial` all follow the same `weather_fx` export + group fallback pattern.

### 3. Atmospheric Wind & Foliage System
- **Global Shader Uniforms** (written by `WeatherFX`):
  - `weather_wind_strength` (`float`), `weather_wind_direction` (`vec3`), `weather_precipitation_strength` (`float`, `0.0` to `1.2`)
  - `weather_foliage_tint` / `weather_grass_tint` (`color`): biome tints blended over `biome_tint_transition_speed`.
- **Stylized Wind Shaders** (`resources/`): `grass_wind.gdshader` (multi-octave sway, vertical color gradient, wetness), `foliage_wind.gdshader` (trunk lean, branch sway, leaf flutter), `pond_water.gdshader` (see below).
- **Instanced Grass Generator (`GrassField`)**: `MultiMeshInstance3D` field using the preloaded Quaternius grass meshes (`Common Short`, `Common Tall`, `Wispy Short`, `Wispy Tall`) or a custom mesh, with circular exclusion zones.

### 4. Rain Ground Impact Effects (Splashes & Ripples)
- Falling raindrops spawn a sub-emitter at ground impact (disabled automatically on Web / Compatibility renderers).
- Draw pass 1: droplet splashes; draw pass 2: expanding puddle ripples.

### 5. Interactive Zelda-Inspired HUD Widgets
Instance the widget scenes (they carry their layout, `StyleBox` and shader material) and assign `weather_fx`, or rely on the group fallback:
- **`scenes/weather_forecast_display.tscn`** (`WeatherForecastDisplay`, PanelContainer): pill-shaped forecast strip with SVG icons. The strip scrolls with a `Tween` synchronized to the cycle timer (restarted on `forecast_updated` / `playback_changed`).
- **`scenes/temperature_gauge_display.tscn`** (`TemperatureGaugeDisplay`, Control with `mouse_filter = Ignore`): circular segmented thermometer (`temperature_gauge.gdshader`) with a `GaugeNeedle` child (`%GaugeNeedle`).
- **`WindDirectionDial`** (Control, drawn in code): interactive 360° compass with cardinal points and click-drag vector rotation.
- Shared pill style: `resources/hud_panel_style.tres`.

### 6. Temperature Curves, Lapse Rates & Freezing Transitions
- Smooth altitude lapse (0m–1500m+) and a diurnal solar curve.
- Precipitation generated at or below 0°C becomes **Snow** / **Heavy Snow**; rare sun-showers during daylight.

### 7. Procedural Forecasting Queue
- Generates a queue of upcoming weather conditions (default 7 cycles ahead).
- `CycleTimer` advances it every `cycle_duration_seconds` (default 240) or manually via `advance_cycle()`.

### 8. BotW-Style Wildfire & Thermal Updrafts
Fully self-contained within the addon:

- **`GrassField` creeping wildfire**: `ignite_at(world_pos)` spawns `CreeperHead`s that advance the fire front downwind at a clamped **1.2–1.8 m/s** (`fire_spread_speed`) with organic meandering and branch splits. Wind and rain come from `wind_changed` / `weather_changed`. Consumed grass is looked up through a coarse origin grid (`BUCKET_SIZE`).
- **`FireTrailNode` life cycle**: a `Tween` runs grow (0.8s) → peak flicker (2.8s) → decay (1.4s) → `extinguish()`; the updraft area leaves the `Updraft`/`Thermal` groups on burnout (no ghost lift).
- **`BurnableGrass` interactive patches** (`scenes/burnable_grass.tscn`): ignite via the scene-wired `HitboxArea` (`area_entered` from any `Fire`-group area) or the `ignite_action` input (`&"action"` by default, ignored when the action is not in the `InputMap`) while the player stands in the hitbox. `BurnTimer` / `SpreadTimer` drive burnout and downwind spreading; ignition is refused while it rains. Delegates field-wide creeping to any overlapping `GrassField`.
- **Thermal updrafts**: every burning node registers a vertical `Area3D` cylinder (20 m tall; 2 m radius for `FireTrailNode`, 4.5 m for `BurnableGrass`; groups `Updraft` + `Thermal`) that paragliders can catch for lift.
- **Proximity VFX culling**: updraft wind streaks only render while the player (via the `Player` group, `class_name` fallback, camera fallback) is within 5m.
- **Shared wind spread math**: `WeatherFX.get_wind_spread_factor()` (downwind boost, capped; upwind suppression).

### 9. Interactive Pond Water (`resources/pond_water.gdshader`)
Toon-banded pond surface with wind-driven waves, contact/edge foam, and rain impact ripples. Exposes swimmer interaction uniforms (`swimmer_active`, `swimmer_position`, `swimmer_direction`, `swimmer_speed`) — feed them from any character controller for a V wake while moving and treading ripples at rest.

---

## Scene Tree Architecture

```text
WeatherFXDemo (Node3D)
├── WorldEnvironment
├── DirectionalLight3D (Sun/Moon Light, oriented by WeatherFX)
├── DemonstrationTarget (Node3D - target_node)
├── Ground (CSGBox3D)
├── Scenery (Node3D)
│   ├── GrassField (grass_field.tscn)
│   ├── Fire (FireFX campfire)
│   └── Tree1..5 (tree_*.tscn, group "Tree")
│       ├── Mesh (Bark & Foliage Wind Shaders)
│       └── FallingLeaves (falling_leaves.tscn)
├── CameraPivot / Camera3D
├── DateAndTime (demo clock; emits time_changed)
├── WeatherFX (weather_fx.tscn - group "WeatherFX")
│   ├── CycleTimer (Timer -> advance_cycle)
│   ├── PrecipitationFX
│   │   ├── RainParticles (sub-emitter -> RainSplashParticles)
│   │   ├── RainSplashParticles
│   │   └── SnowParticles
│   ├── WindVFX (wind_vfx.tscn: ribbons, leaves, GustTimer, TreeCheckTimer)
│   └── WeatherAudio
│       ├── RainLightSFX / RainHeavySFX / StormSFX / WindSFX
│       └── (bgs_* exports -> BackGroundSounds players in the demo)
├── BackGroundSounds (bgs.tscn - day/night ambience players)
├── StatusTimer (Timer -> status readout)
└── HUD (CanvasLayer)
    ├── ControlPanel (biome, weather, time, altitude, wind controls)
    └── BottomRight
        ├── WeatherForecastDisplay (weather_forecast_display.tscn)
        ├── TemperatureGaugeDisplay (temperature_gauge_display.tscn)
        └── HUDWindDial (WindDirectionDial)
```

---

## GDScript API Reference

### Signals

| Signal | Emitted when |
| --- | --- |
| `weather_changed(new_weather, old_weather)` | the active `ClimateData.WeatherType` changes |
| `forecast_updated(forecast: Array[ClimateData.WeatherType])` | the queue is regenerated or advanced |
| `cycle_advanced(current_weather)` | `advance_cycle()` runs |
| `biome_changed(new_biome, old_biome)` | `current_biome` changes |
| `temperature_changed(temp_celsius)` | time, altitude or biome moves the temperature |
| `wind_changed(strength, direction)` | wind strength/direction, weather multiplier or playback changes |
| `daylight_changed(is_day)` | the clock crosses 06:00 / 18:00 |
| `playback_changed(active)` | the simulation starts or stops ticking (`is_playing`, editor toggle) |

### Consumer Pattern

```gdscript
extends GPUParticles3D

@export var weather_fx: WeatherFX # assign in the scene, or leave empty for the group fallback

func _ready() -> void:
    if weather_fx == null:
        weather_fx = get_tree().get_first_node_in_group(&"WeatherFX") as WeatherFX
    if is_instance_valid(weather_fx):
        weather_fx.wind_changed.connect(_on_wind_changed)
        _on_wind_changed(weather_fx.current_wind_strength, weather_fx.wind_direction)

func _on_wind_changed(strength: float, direction: Vector3) -> void:
    emitting = strength > 4.0 # cache what you need; animate in _process from the cached values
```

### Controlling Weather & Wind

```gdscript
weather.current_biome = ClimateData.BiomeZone.ARCTIC_TUNDRA   # switch biome
weather.set_weather(ClimateData.WeatherType.RAIN)              # force weather (force_weather + manual_weather)
weather.resume_forecast()                                      # back to the procedural forecast
weather.wind_direction = Vector3(0.0, 0.0, -1.0)               # blow North (-Z)
weather.wind_strength_multiplier = 1.5
weather.advance_cycle()                                        # next forecast cycle now
weather.is_playing = false                                     # pause cycle, VFX and audio
var progress: float = weather.get_cycle_progress()             # 0.0 .. 1.0 of the current cycle
var queue: Array[ClimateData.WeatherType] = weather.get_forecast()
var hours: float = weather.get_current_time_hours()            # from date_and_time_node or manual_time_of_day
```

`date_and_time_node` accepts any node exposing `current_time` (hours) and a `time_changed(float)` signal, such as the `DateAndTime` addon; `manual_time_of_day` is the fallback.

### Static Helper Methods

For scripts that cannot hold a node reference (e.g. other addons), the last simulated values are mirrored in statics. Addon scripts subscribe to the signals above instead of polling these.

```gdscript
var wind_spd: float = WeatherFX.get_wind_strength()
var wind_dir: Vector3 = WeatherFX.get_wind_direction()
var wetness: float = WeatherFX.get_precipitation_strength()
var factor: float = WeatherFX.get_wind_spread_factor(wind_alignment, wind_spd)
var is_player: bool = WeatherFX.is_player_node(body)   # "Player" group, then `class_name Player`
var player: Node3D = WeatherFX.find_player(get_tree())

var temp_f: float = ClimateData.celsius_to_fahrenheit(20.0)
var icon: Texture2D = ClimateData.get_weather_icon(ClimateData.WeatherType.STORM)   # preloaded SVG
var wet: float = ClimateData.get_precipitation_strength(ClimateData.WeatherType.RAIN) # 0.5
```

---

## Global Shader Parameters

```gdshader
shader_type spatial;

global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;

void vertex() {
    vec3 wind_displacement = weather_wind_direction * weather_wind_strength * 0.05 * VERTEX.y;
    VERTEX += (inverse(MODEL_MATRIX) * vec4(wind_displacement, 0.0)).xyz;
}

void fragment() {
    float wetness = clamp(weather_precipitation_strength, 0.0, 1.0);
    ALBEDO *= (1.0 - wetness * 0.25);
    ROUGHNESS = mix(ROUGHNESS, 0.1, wetness);
    SPECULAR = mix(SPECULAR, 0.8, wetness);
}
```

---

## Tests

```powershell
& 'C:\Godot\godot.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://addons/weather_fx/tests -gexit
```

---

## Credits & Attributions

- **Quaternius** – *Stylized Nature Megakit* ([quaternius.com](https://quaternius.com/), CC0) — tree and grass models, bark and foliage textures (`assets/models/quaternius/`).
- **BinbunVFX** – *Fire Effects Pack* ([binbunvfx.itch.io](https://binbunvfx.itch.io/)) — the billboard flame shader in `assets/vfx/fire/flame_01.gdshader` is adapted from this pack.
- **TomMusic** – *Fantasy SFX* ([tommusic.itch.io](https://tommusic.itch.io/)) — torch/fire crackle loop in `assets/audio/tommusic/sfx/Torch/`.
- **Gravity Sound** – *Weather Sound Pack* ([gravity-sound.itch.io](https://gravity-sound.itch.io/)) — rain, thunder and wind ambience (`assets/audio/gravitysound/`).
- **ambientCG** – *Grass 004* ([ambientcg.com/view?id=Grass004](https://ambientcg.com/view?id=Grass004), CC0) — `assets/textures/Grass004_1K-JPG_Color.jpg` ground texture.
- **Godot Shaders** – *Stylized BOTW Fire* ([godotshaders.com/shader/stylized-botw-fire](https://godotshaders.com/shader/stylized-botw-fire/)) and *Stylized Smoke Shader* ([godotshaders.com/shader/stylized-smoke-shader](https://godotshaders.com/shader/stylized-smoke-shader/)) — shaders, meshes, and textures in `assets/models/loop_box/`. License not recorded — fill in.
- **`assets/vfx/wind/`** (wind ribbon/streak VFX scenes, meshes, shaders, and textures) — source/license not recorded — fill in.
- **`assets/audio/tommusic/bgs/`** (Forest Day / Forest Night ambient loops) — source/license not recorded — fill in.

---

## License

This project is licensed under the [MIT License](LICENSE).
