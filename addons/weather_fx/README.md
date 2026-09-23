![Preview](./assets/weather-fx.png)

# Weather FX for Godot 4.8+

A high-performance, modular climate, weather, and atmospheric wind simulation system for Godot 4.8+. Features 20 universal biomes, altitude- and time-based temperature lapse curves, procedural 4-minute forecasting cycles, rain ground impact effects (puddle ripples & splash droplets), global wind shader integration with stylized foliage sway, interactive Zelda-inspired HUD widgets, and a comprehensive test lab (`demo.tscn`).

> [!NOTE]
> **Plugin Activation vs Direct Scene Usage**:
> All core scripts register global class names with editor icons (`WeatherFX`, `PrecipitationFX`, `WeatherAudio`, `WeatherZone`, `WeatherForecastDisplay`, `TemperatureGaugeDisplay`, `GaugeNeedle`, `WindDirectionDial`, `WindVFX`, `FallingLeaves`, `FireFX`, `GrassField`, `BurnableGrass`, `FireTrailNode`, `ClimateData`, `WaterRipples`), so they appear in the *Create New Node* dialog whether or not the plugin is enabled.
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

## Playing the demo

The demo runs in a browser at <https://timothycope.com/weather-fx/>. A GitHub Action exports it on every
push to `main` and hands it straight to Pages, so the export itself is never committed: the projects that use this
addon fetch it with a script, and a web export is tens of megabytes that git cannot compress.

This repository **is** that project. It uses the layout the
[Godot Asset Library](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html) expects, with the addon at `addons/weather_fx/` and a
`project.godot` at the root, so cloning it and opening it in Godot is all it takes. The
addon is mounted at `res://addons/weather_fx/` exactly as it is in a game, so it is
edited in place with nothing copied first, and the root `project.godot` is skipped as a
conflict when the asset is installed from the library.


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
  - `PrecipitationFX` (Node3D): rain, splash and snow `GPUParticles3D`; reacts to `weather_changed`, `wind_changed`, `playback_changed`; follows `weather_fx.target_node`; on Forward+/Mobile the rain collides with the `RainGround` heightfield (`GPUParticlesCollisionHeightField3D` following the target, 56 m wide, 512 resolution, always updated) and every splash/ripple is sub-emitted where its drop lands, so they sit on ramps, roofs and grass; the Compatibility renderer has no particle collision, so there the splash emitter is a plane on the ground found under the target.
  - `WeatherAudio` (Node): weather SFX players (`audio_rain_light`, `audio_rain_heavy`, `audio_storm`, `audio_wind`) and the background ambience: `WeatherFX.bgs_sets` is one `BiomeAmbience` per kind of place, and this node makes one non-positional player per loop they carry at ready (on `bgs_bus` at `bgs_volume_db`), playing the loop the biome, the weather and the hour call for. BGS is re-evaluated only on `weather_changed`, `biome_changed`, `daylight_changed` and `playback_changed`; a player that stays the target is never restarted.
  - `WindVFX` (Node3D): wind ribbons, leaf streams (`airflow_particles` / `leaf_particles` arrays) and gust sweeps driven by `GustTimer` / `TreeCheckTimer` Timer nodes. Leaves only appear in tree biomes and, with `require_nearby_trees`, when a node in the `Tree`, `Trees`, `Foliage` or `Choppable` group is within `tree_detection_radius` (the addon's `tree_*.tscn` scenes are in `Tree`).
  - `CycleTimer` (Timer): drives `advance_cycle()`; `get_cycle_progress()` reads it.
- **Other consumers**: `FallingLeaves`, `FireFX`, `GrassField`, `BurnableGrass`, `FireTrailNode`, `WeatherZone`, `WeatherForecastDisplay`, `TemperatureGaugeDisplay` and `WindDirectionDial` all follow the same `weather_fx` export + group fallback pattern.
- **Multiplayer**: put a `MultiplayerSynchronizer` under the `WeatherFX` node carrying `.:synced_weather` and `.:synced_biome` (Always, with a `replication_interval` of a second or so), and the host's weather is every peer's. The authority writes them as its weather and biome change; a peer that is not the authority (`is_puppet()`) takes the weather as forced (`set_weather`), since its own forecast would otherwise overrule it, and takes the biome only when it is not reading it off the `WeatherZone`s around a target of its own. No RPC needed.

### 3. Atmospheric Wind & Foliage System
- **Global Shader Uniforms** (written by `WeatherFX`):
  - `weather_wind_strength` (`float`), `weather_wind_direction` (`vec3`), `weather_precipitation_strength` (`float`, `0.0` to `1.2`)
  - `weather_foliage_tint` / `weather_grass_tint` (`color`): biome tints blended over `biome_tint_transition_speed`.
- **Stylized Wind Shaders** (`resources/`): `grass_wind.gdshader` (multi-octave sway, vertical color gradient, wetness, and combustion driven by `burn_progress`, the `instance_burn_progress` instance uniform, or per-blade MultiMesh custom data against `fire_clock`), `foliage_wind.gdshader` (trunk lean, branch sway, leaf flutter), `pond_water.gdshader` (see below).
- **Instanced Grass Generator (`GrassField`)**: `MultiMeshInstance3D` field using the preloaded Quaternius grass meshes (`Common Short`, `Common Tall`, `Wispy Short`, `Wispy Tall`) or a custom mesh. Blades grow only on ground: each drops a ray straight down and grows where the first thing it meets is a collider in `ground_group` (`GRASS` by default, the player controller's footstep group), so rocks, walls, trunks and props keep themselves clear, a pond with no bed under it grows nothing, ground steeper than `max_slope_degrees` stays bare, and an `Area3D` in `water_group` (`WATER`) holds no grass. Players, NPCs, rigid props and moving platforms are looked past, since where they stand when the field grows says nothing about the ground. `instance_count` is the number of blades tried, not the number that grow, so density stays even rather than crowding around an obstacle, and every blade keeps its spot, size and turn when something elsewhere on the field moves. Scenery that should clear grass is a `StaticBody3D`, like the campfire in the demo: the field is grown once, so a rigid prop taken for an obstacle would leave a grass-shaped hole the day it was knocked over. A `water_group` area has to reach the bed, which is what the player controller's swimming and water footsteps need of it anyway. `probe_height` is metres along the field's own up, whatever the node is scaled to. Clear `ground_group` for a flat field on the node's own plane, as the tests do. A probing field starts growing two physics frames after it enters the tree, once a CSG collider (built in a deferred call) exists and any body a level script moved in its own `_ready` has its new transform, and then casts its rays a slice per physics frame within `GROW_BUDGET_USEC` (4 ms, shared by every field in the level), so a level with tens of thousands of blades never stalls a frame long enough to leave the engine catching up on physics with nothing drawn in between; the grass appears when the last slice is done. A flat field grows at once. The field's `grown` signal fires each time it finishes growing and `is_growing()` says whether a grow is still to come, which is what to wait on before lighting or reading a field that has just been added. Calling `regenerate()` still grows the whole field at once, as the property setters and the Regrow button do. In the editor the field regrows when it is saved and when it is moved onto other ground, and the **Regrow** button in the inspector regrows it against the colliders as they stand now, after moving a rock or a tree beside it. A field that meets no collider in its `ground_group` at all grows nothing, shows a node warning in the editor and pushes one at run time, naming the group it looked for. The hand-placed `exclusion_radius`, `exclusion_center` and `additional_exclusion_zones` exports and `is_point_excluded()` are gone: give whatever should stand clear of the grass a collider instead.
- **Pressing**: the same bodies the blades are grown straight through bend them at run time, so anything that does not clear the grass treads it down instead: the Player, an NPC, a rideable, a rolling ball, a moving platform. A static body never presses, having cleared the grass where it stands. A `PressArea` child sized to the grass notices them coming and going; it is on no collision layer, so interaction and projectile rays pass straight through it, and it sees bodies on layer 1 (its default mask; widen it on the node for bodies on other layers). Each idle frame up to `MAX_PRESSERS` (8, matching the shader's array) are handed to the field's own copy of the material as `press_points`, one `vec4` each of world position and the radius that body presses. When more than eight stand in one field the slots go to the widest presses nearest the camera, so a horse beside you beats a ragdoll's finger bone, and a body more than `press_height` above or below the blades (a bird, someone on a walkway) is not given one at all. The radius comes off the body's enabled collision shapes with their scale, counting only shapes that have one, so a horse and a beach ball do not press the same circle and a Player's sideways step ray does not widen the Player's; `press_radius_fallback` covers a body whose shapes have no radius. A field nobody is standing in writes nothing and the shader's loop runs zero times, so it is free until someone walks in. How it looks is on the material: `press_strength` (how far the blades lean away), `press_flatten` (how far they are trodden down) and `press_height`. `enable_pressing` on the node turns the whole thing off. This replaces the old single-body `player_position` instance uniform and its `enable_player_displacement` / `player_displacement_*` parameters, which nothing ever set.
- **Blade texture (`assets/textures/grass_blades.png`)**: the blades sample a flat colour, not an atlas. Quaternius ships one 512 pixel palette image whose colour bands are 28 pixels wide, and the grass meshes sample a strip of barely thirteen of them, so from mip level four a single texel straddled the band, the bands beside it and the white fill: a field across the map went muddy brown while the same grass underfoot stayed green. `grass_blades.png` holds only the two bands the four meshes use, each widened to own its side of the image (wispy to the left of column 56, common from there on), and `texture_albedo` is declared `repeat_disable` so the left edge cannot wrap onto the other band. It is 512 x 32: the blades run the whole height of the texture, so at 512 rows a blade a few pixels tall picked a mip coarse enough to blend the two sides again, while at 32 rows the blade's width decides the level. The mesh UVs are unchanged and the colours underfoot are the same; a custom mesh with its own UVs should point `texture_albedo` at its own texture. `tests/test_grass_blade_texture.gd` reads the UVs back out of each mesh and fails if the colour is not flat for 32 pixels either side of them, or if the texture grows taller.

### 4. Rain Ground Impact Effects (Splashes & Ripples)
- Falling raindrops spawn a sub-emitter at ground impact (disabled automatically on Web / Compatibility renderers).
- Draw pass 1: droplet splashes; draw pass 2: expanding puddle ripples, kept on the node but switched off (`draw_passes = 1`) because rings on every surface were too much; set `draw_passes` back to 2 on `RainSplashParticles` to bring them back. Ripples on water come from the pond shader's `rain_ripples`, driven by `weather_precipitation_strength`, and are unaffected.
- Placement: each drop stops on the `RainGround` heightfield (rigid collision, no bounce; a hidden drop would not sub-emit) and sub-emits its splash there (`SUB_EMITTER_AT_COLLISION`), so ripples follow the real surface under every drop instead of one plane at the target's feet. The splash emitter has to keep emitting for sub-emission to work, so it is parked 500 m below the target with a tall visibility box; its own particles are never seen. The heightfield is 56 m wide and 40 m tall around the target; lower its `resolution` if the extra depth pass costs too much.

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

- **`GrassField` creeping wildfire**: `ignite_at(world_pos, radius, duration)` lights the grass cells around the point and the front then grows as a cellular fire on the field's origin grid (`BUCKET_SIZE`, 2 m cells): every lit cell passes the fire to its eight neighbours after a delay set by the creep speed (clamped to the BotW **1.2–1.8 m/s** band, `fire_spread_speed`) and the wind, which only slows the front across and against it (`UPWIND_SPEED_FACTOR`), so the fire spreads as a ragged ring leaning downwind rather than a line. Cells with no grass (a pond, the ground under a rock, bare dirt) never catch, so anything that cleared the grass is a firebreak, and neither does grass on another level: each 2 m cell holds its grass as levels (heights closer together than `IGNITE_HEIGHT` are one level, so a bank is a single wide one and the edge of a ledge gives the cell two), the front carries the level it is burning on, and it can only cross to a level within `IGNITE_HEIGHT` of that one. So it walks up a bank however long the slope is, and a cliff stops it even where the ledge falls in the middle of a cell rather than on its edge, a flame more than `IGNITE_HEIGHT` (1 m) above or below the blades lights nothing (a torch on a platform over the grass), the front stops growing after `duration`, lit cells flame for `CELL_BURN_SECONDS` and stay ash for good, and a `FireTrailNode` sits on each lit cell while the `MAX_TRAIL_NODES` budget allows. The blades themselves burn through the grass shader: each blade's MultiMesh custom data records when it caught (plus a jitter) and the shader reads that against the material's `fire_clock`, so embers travel down the blade, it chars and collapses to ash, and the field owns a runtime copy of the material for its clock. Wind and rain come from `wind_changed` / `weather_changed`; rain douses the front, chars whatever was lit, and nothing catches while it rains. `douse_at(world_pos, radius)` puts out just the cells and flames within reach (a water spell) and leaves the rest of the front burning.
- **`FireTrailNode` life cycle**: a `Tween` runs grow (0.8s) → peak flicker (2.8s) → decay (1.4s) → `extinguish()`; the updraft area leaves the `Updraft`/`Thermal` groups on burnout (no ghost lift).
- **`BurnableGrass` interactive patches** (`scenes/burnable_grass.tscn`): ignite via the scene-wired `HitboxArea` (`area_entered` from any `Fire`-group area) or the `ignite_action` input (`&"action"` by default, ignored when the action is not in the `InputMap`) while the player stands in the hitbox. `BurnTimer` / `SpreadTimer` drive burnout and downwind spreading; ignition is refused while it rains. Delegates field-wide creeping to any overlapping `GrassField`.
- **Thermal updrafts**: every burning node registers a vertical `Area3D` cylinder (20 m tall; 2 m radius for `FireTrailNode`, 4.5 m for `BurnableGrass`; groups `Updraft` + `Thermal`) that paragliders can catch for lift.
- **Proximity VFX culling**: updraft wind streaks only render while the player (via the `Player` group, `class_name` fallback, camera fallback) is within 5m.
- **Shared wind spread math**: `WeatherFX.get_wind_spread_factor()` (downwind boost, capped; upwind suppression).

### 10. Thunderstorm Lightning (`scripts/lightning_fx.gd`)
`LightningFX` sits under the WeatherFX node in `weather_fx.tscn`. While `active_weather` is `STORM` (and the weather is simulating) it rolls a strike every `strike_interval` seconds, `strike_distance` metres from `target_node` in a random direction, on the ground found by a ray. A strike is a `LightningBolt` (`scenes/lightning_bolt.tscn`): a jagged additive ribbon redrawn with fresh jitter every frame for `life` seconds so it crackles, an `OmniLight3D` flash that fades with it, and thunder from the vendored Gravity Sound pack (`thunder strike`, `heavy thunder 1/2`, `distant thunder 1`) that plays after the sound has travelled from the foot to the camera at `speed_of_sound`, so a far strike flashes first and rumbles later. Under the foot, anything within `damage_radius` with a `take_hit(damage, from)` method takes `damage` (physics shape query, duck-typed, so the addon stays independent of the player controller), and the grass within `ignite_radius` catches through the `GrassField` and `BurnableGrass` groups, as a wildfire would. A storm always rains and rain otherwise keeps grass from catching, so the strike passes `force` to `ignite_at` and `ignite`: a bolt is hot enough for wet grass, and the fire then burns until the next weather change douses it. Random strikes roll on the multiplayer authority and `strike_at` replicates as an RPC, so every peer sees the same bolt. The same node is an API for the game: `strike_at(position, hit_damage)` calls a sky bolt onto a point (0 damage for a purely visual one, negative for the storm's own), `arc(from, to)` draws a silent bolt between two points, `bodies_near(position, radius)` lists what a strike would hit, and `struck(position)` fires for each strike. The player controller demo's Lightning and Chain Lightning spells draw with these, so the storm and the spells share one lightning.

### 9. Interactive Pond Water (`resources/pond_water.gdshader`)
Toon-banded pond surface with real wind waves, contact/edge foam, and scattered rain impact ripples (hashed per cell and staggered in time, so they never form a grid). The wind waves are a sum of six Gerstner (trochoidal) waves fanned around the wind direction, a fixed table in the shader (`WAVES`: angle from the wind, wave number as a multiple of `wave_frequency`, share of `wave_amplitude`; the shares sum to 1 so the tallest crest never exceeds the active amplitude): each wave moves the water sideways toward its crest as well as up, which pinches the crests sharp and leaves the troughs broad, the vertex normal is the cross product of the displaced surface's tangents, and the Jacobian of the displacement is passed to the fragment stage so the most pinched crests foam (`crest_foam`) and brighten toward the shallow colour (`crest_light`), the way [GodotOceanWaves](https://github.com/2Retr0/GodotOceanWaves) (MIT) foams the peaks of its FFT surface; a pond only needs a handful of waves instead of an FFT. `wave_steepness` (0-1) sets how far the crests pinch before they would loop over, `wave_speed` is a tempo on the deep-water dispersion (1 is physical: longer waves travel faster), and the wind strength scales amplitude and tempo. Gameplay code that needs the surface height mirrors the table and undoes the sideways travel with a few fixed-point steps (see `Buoyancy.get_wave_displacement` in the player controller demo).  Bodies in the water ripple it for real through the `WaterRipples` node (`scenes/water_ripples.tscn`): wire the water `Area3D`'s `body_entered` / `body_exited` to its `_on_body_entered` / `_on_body_exited` and point `water_mesh` at the surface. Every body in the water has its meshes put on visual layer 10; an orthographic `MaskCamera` sits `depth_below` under the surface looking straight up, rendering only that layer up to `depth_above` over the water line, so its `MaskViewport` holds the underside outline of everything in the water (from above, the near plane would slice the tops off the bodies and leave only culled back faces). The `SimulationViewport` runs a height-field wave simulation at `texels_per_metre` (default 32, 3 cm texels; `resources/water_ripples_sim.gdshader`, a never-cleared viewport that reads its own last frame through a `BackBufferCopy`; R = height, G = previous height, B = last footprint, alpha unused because the render target does not return it reliably): the footprint is softened by `mask_blur` texels so it never reads as pixels, the surface under a body settles into a hollow of the footprint's shape (`sink`, `sink_rate`), wherever the footprint changed since the last frame the water is pushed (`push`, up where a body arrives, down where it leaves), and the wave equation (`wave_speed`, `damping`) carries it out, so a moving body throws a bow wave ahead and a wake behind on its own. A hull leaves a hull-shaped wake and bow wave, a bobbing float leaves rings, a swimmer's strokes leave the shape of the strokes, and a body sitting still leaves nothing. The node fills the surface material's `ripple_texture`, `ripple_area` (world X, Z, width, depth) and `ripple_height` (m per simulated unit, default 4 cm) uniforms on ready; the shader displaces the vertices by that height in `vertex()` and lights the fragments by its slope, tilts the surface normal by the slope (`ripple_shading` exaggerates it for the toon look), brightens crests toward the shallow colour (`ripple_crest_light`) and foams only the tallest crests; nothing is drawn around a body's outline. Subdivide the water mesh to roughly 10-15 cm cells so the geometry can carry the waves. A surface without a `WaterRipples` node (zero `ripple_area`) is unaffected. `edge_foam_width` (0 disables the radial rim band, leaving the contact foam to find the walls of a rectangular pool), `depth_foam_distance` and `foam_softness` size the rim and contact foam. The surface reads the stencil buffer (`stencil_mode read, compare_not_equal, 1`), so any mesh drawn with a stencil-writing mask (a boat hull) cuts a hole in the water; the vertex waves are a plain function of position, TIME, the wave uniforms and the wind globals, so gameplay code can mirror them for buoyancy. The drawn caustic web of earlier versions is gone: the crests carry the light themselves.

### 11. Sky Clouds (`WeatherFX`'s `cloud_*` properties) and the Binbun sky
`WeatherFX` drives a Binbun sky shader from the weather. The skies in `assets/BinbunSky/skies/` (basic, stylized and experimental variants of Godot Skies by Binbun) are `Sky` resources whose `ShaderMaterial` reads the scene's directional light for its own day, sunset and night colours and scrolls two layers of noise cloud, so they run the same on every renderer, the web export included, where compositor effects and volumetric fog do not (the addon's copy of Binbun's `main.gdshader` fixes two `clamp()` calls whose arguments were in the wrong order, `clamp(0.0, 1.0, x)`: undefined in GLSL, it happened to work on Vulkan and turned the whole sky white on the Compatibility renderer and WebGL). `WeatherFX.fog_sky_affect` (0.3) keeps the weather's fog from painting the sky flat: at Godot's default of 1 any fog at all (cloudy, rain, snow, storm) replaces the sky with the fog colour, clouds and all. It sets that material's `cloud_density`, `cloud_color` and `wind_speed`: a thin bright scatter in blue sky (`cloud_clear_density`, `cloud_clear_color`), a grey sheet when cloudy (`cloud_cloudy_density`, `cloud_cloudy_color`) and a dark one in rain, snow and storms (`cloud_rain_density`, `cloud_rain_color`), eased over `cloud_transition_seconds` so a change rolls in rather than snaps; the easing stops once every value has settled. The clouds scroll down the wind at `cloud_wind_scroll_scale` per unit of the weather's wind strength and never slower than `cloud_wind_min_scroll`. With `sun_light` set the clouds dim as the sun sets: the colour is scaled down to `cloud_night_dim` with the sun below the horizon, kept at full brightness above `cloud_night_dusk_height` (the sun's height, 1 = overhead) and eased between, retargeting whenever the clock moves the sun. It works on a copy of the sky and its material, made when the game runs (never in the editor), so the asset on disk is never edited, and a `WorldEnvironment` whose sky is not a Binbun one is left alone.

Wiring: a `WorldEnvironment` with one of the Binbun skies as its `Environment.sky`, set as the `WeatherFX` node's `world_environment`; its `sun_light` is the sun the clouds dim by (leave it empty for no dimming). Nothing else to add. `demo.tscn` does exactly this.

### 12. Background sounds (`BiomeAmbience`, `resources/ambience/`)
The ambience is a `BiomeAmbience` resource per kind of place: the biomes it belongs to and a loop for each of clear, rain and storm by day and by night (`stream_for(weather, is_day)`; blue sky, cloudy and snow share the clear loop). `WeatherFX.bgs_sets` holds the sets a level has; the first whose `biomes` include the current biome plays, a biome no set covers plays `WeatherFX.bgs_default`, and nothing when that is empty too. `weather_fx.tscn` ships a set for every biome: `forest.tres` (Shadow Woods, Misty Woods, Ancient Forest), `beach.tres` (Coastal Plains, Humid Coast), `plains.tres` (Temperate Plains, Northern Plains, Autumn Highlands), `desert.tres` (Arid Canyon, Desert Dunes, Desert Plateau, Deep Desert), `arctic.tres` (Arctic Tundra, Alpine Peaks, Desert Glacier), `jungle.tres` (Tropical Rainforest), `swamp.tres` (Wetlands Valley) and `volcano.tres` (Volcanic Foothills, Crater, Caldera). The last six are one Gravity Sound loop each, day and night, rain and storm alike, since the rain and storm sounds play over them. `sea.tres`, `cave.tres` and `interior.tres` are there for a game to put on a boat, in a cave or indoors, and belong to no biome. `WeatherAudio` makes one player per loop at ready and never restarts the one that stays the target, so a change of weather within the same loop is seamless.

---

## How to Use

### Nodes to add and where

| Node | Where it goes | Set in the Inspector |
|---|---|---|
| `WeatherFX` (instance `scenes/weather_fx.tscn`) | Once per level, as a child of the level root | `sun_light` -> your `DirectionalLight3D`; `world_environment` -> your `WorldEnvironment`; `target_node` -> the node the rain and snow follow (usually the player); `date_and_time_node` -> a clock node with a `time_changed(hours)` signal (the Date and Time addon's `DateAndTime`), or leave it empty and drive `manual_time_of_day`; `current_biome`, `force_weather` / `manual_weather`, `wind_direction`, `wind_strength_multiplier` |
| `WeatherAudio` (inside `weather_fx.tscn`) | Nothing to add | The ambience is `WeatherFX.bgs_sets`, a `BiomeAmbience` per kind of place (`weather_fx.tscn` ships the forest and beach sets), with `bgs_default` for the rest, `bgs_bus` and `bgs_volume_db` |
| `GrassField` (instance `scenes/grass_field.tscn`) | Under your scenery, at the centre of the field | `instance_count`, `field_size`, `min_scale` / `max_scale`; `ground_group` / `water_group` / `max_slope_degrees` / `probe_height` / `probe_mask` for where it grows; `enable_pressing` / `press_radius_fallback` for what bends it; `weather_fx` and `enable_wildfire` for fire |
| `tree_1.tscn` .. `tree_5.tscn` | Anywhere; each carries its wind-shader mesh, a `FallingLeaves` emitter and a `Trunk` StaticBody3D (a 4 m cylinder at the trunk's own radius, on layer 1) | Nothing required; the `Tree` group is set in the scene. The trunk is solid, so the Player, cameras and projectiles meet it, and a `GrassField` grows around it rather than through it |
| `FireFX` (`assets/models/loop_box/Scenes/Fire.tscn`, or the script on your own fire) | On a campfire or torch | `smoke_particles`, `spark_particles`, `fire_light` -> its own children; `weather_fx` optional |
| `WeatherForecastDisplay`, `TemperatureGaugeDisplay` (instance their scenes), `WindDirectionDial` (script on a `Control`) | Under your HUD `CanvasLayer` | `weather_fx` -> the WeatherFX node |
| Pond water: a `MeshInstance3D` with `resources/pond_water_material.tres` | Sunk into a hole in the ground | Subdivide the mesh to 10-15 cm cells. For wakes and rings, add `scenes/water_ripples.tscn` next to it, set `water_mesh`, and wire the water `Area3D`'s `body_entered` / `body_exited` to its `_on_body_entered` / `_on_body_exited` |
| `WeatherZone` (script on an `Area3D`) | Around a region that should switch biome when entered | `biome`, `weather_fx` |
| `BurnableGrass`, `FireTrailNode` | Individual burnable props | See section 8 |

Minimum scene:

```text
Level (Node3D)
├── WorldEnvironment
├── DirectionalLight3D
├── DateAndTime                         (optional clock)
├── WeatherFX (weather_fx.tscn)         sun_light, world_environment (Binbun sky), target_node, date_and_time_node; cloud_* and bgs_* on it
└── HUD (CanvasLayer)
    ├── WeatherForecastDisplay          weather_fx
    └── TemperatureGaugeDisplay         weather_fx
```

Everything talks through exports and signals, so weather, wind, precipitation and the HUD run without a line of script. Enable the plugin once so the shader globals are registered (or add them by hand; see Global Shader Parameters).

### How `demo.tscn` does it

| Demo node | What it demonstrates |
|---|---|
| `WeatherFX` | `weather_fx.tscn` instanced with `sun_light`, `world_environment`, `target_node` (`DemonstrationTarget`) and `date_and_time_node` (`DateAndTime`) all set in the Inspector; `manual_time_of_day` matches the clock's 7:00 start. |
| `WeatherFX/WeatherAudio` | Makes one player per loop in `WeatherFX.bgs_sets` at ready and plays the one the biome, the weather and the hour call for. |
| `WorldEnvironment` | The environment's sky is `assets/BinbunSky/skies/stylized/stylized_sky_01.tres`, and it is `WeatherFX`'s `world_environment`, so the sky's clouds thicken and darken with the weather, scroll with the wind and dim at night by `sun_light`. |
| `DateAndTime` | A small `@tool` stand-in clock (`demo_date_and_time.gd`) with only `current_time` and `time_changed`, so the demo runs without the Date and Time addon. The real addon's `DateAndTime` node drops into the same slot. |
| `Ground/Water` | A `PlaneMesh` with `pond_water_material.tres` sitting in the `Ground/Hole` cut-out: wind waves, rain rings and edge foam with no extra nodes. No `WaterRipples` here because nothing enters the water. |
| `Scenery/GrassField` | 10 000 blades tried over 50 x 50 m; they grow on the `GRASS` ground and clear themselves around the campfire, the tree trunks and the pond. |
| `Scenery/Fire` | A `FireFX` campfire; its smoke and sparks lean with the wind. |
| `Scenery/Tree1` .. `Tree5` | The five tree scenes; canopies sway and drop leaves with the wind and tint by biome. |
| `HUD/BottomRight/WeatherForecastDisplay`, `TemperatureGaugeDisplay`, `HUDWindDial` | The HUD widgets with `weather_fx` set in the Inspector. |
| `HUD/ControlPanel/...` | Sliders, dropdowns and buttons whose signals are connected in the scene to `demo.gd` handlers that set `current_biome`, `force_weather` / `manual_weather`, `manual_time_of_day`, `current_altitude`, `wind_strength_multiplier` and `wind_direction`; `AdvanceCycleButton.pressed` goes straight to `WeatherFX.advance_cycle`. |
| `WeatherFX` signals -> root | `biome_changed`, `weather_changed`, `temperature_changed` and `wind_changed` are connected in the scene to `_update_ui_state`, so the panel follows the simulation. |
| `StatusTimer` | Refreshes the readout once a second instead of every frame. |

---

## Scene Tree Architecture

```text
WeatherFXDemo (Node3D)
├── WorldEnvironment (Binbun sky: assets/BinbunSky/skies/stylized/stylized_sky_01.tres)
├── DirectionalLight3D (Sun/Moon Light, oriented by WeatherFX)
├── DemonstrationTarget (Node3D - target_node)
├── Ground (CSGBox3D)
│   ├── Hole (CSGCylinder3D, subtracted)
│   └── Water (MeshInstance3D - pond_water_material.tres)
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
│       └── one player per loop in WeatherFX.bgs_sets, made at ready
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

Third-party assets are credited in [CREDITS.md](CREDITS.md).

## License

This project is licensed under the [MIT License](LICENSE).
