# Weather FX for Godot 4.8+

A high-performance, modular climate and weather simulation system featuring 20 universal biomes, altitude- and time-based temperature curves, 4-minute forecasting cycles, rain drop ground impact effects (puddle ripples & splash droplets), global wind shader integration, and an interactive test lab (`demo.tscn`).

> [!NOTE]
> **Plugin Activation vs Scene Usage**:
> All core scripts use `class_name` (`WeatherFX`, `WeatherZone`, `WeatherForecastDisplay`, `TemperatureGaugeDisplay`, `ClimateData`).
> - **Direct Usage**: You can add and use these nodes immediately in your scenes, drag `.gd` scripts, or call them via code. Ensure the global shader parameters are added in **Project Settings > Shader Globals**.
> - **Enabling the Plugin**: Enabling `Weather FX` in **Project Settings > Plugins** registers the custom icons, adds the node types directly to Godot's "Create New Node" hierarchy dialog, and automatically configures the required **Shader Globals** in `ProjectSettings`.

---

## Interactive Demo Scene

Open and run **`res://addons/weather_fx/scenes/demo.tscn`** to explore the entire WeatherFX feature set:
- **Biome Traveling**: Instantly switch between all 20 biomes from a dropdown menu.
- **Weather Conditions**: Force or simulate Blue Sky, Cloudy, Rain, Heavy Rain, Storm, Snow, or Heavy Snow.
- **Rain Impacts**: Observe rain drops bursting into tiny splash droplets and expanding circular puddle ripples upon ground contact.
- **Time of Day Scrubber**: Drag time (0:00 to 24:00) to inspect diurnal temperature swings and lighting transitions.
- **Altitude Scrubber**: Test temperature lapse rate as altitude climbs from 0m to 1500m.
- **Free Camera Orbit**: Right-click drag or WASD/Arrow keys to orbit around the scene and inspect particle effects closely.

---

## Features

### 1. Rain Impact Effects (Puddle Ripples & Splashes)
- **Sub-Emitter Integration**: Rain drops spawn sub-emitter particles at their impact point.
- **Droplet Splashes (Pass 1)**: Tiny water beads bursting upward and spraying outward with realistic gravity.
- **Puddle Ripples (Pass 2)**: Expanding circular concentric water ripple rings fading smoothly on contact surfaces.

### 2. 20 Universal Biomes
Provides statistical probabilities and altitude curves across 20 distinct biomes:
- `TEMPERATE_PLAINS` (0), `NORTHERN_PLAINS` (1), `ARCTIC_TUNDRA` (2), `ARID_CANYON` (3), `ALPINE_PEAKS` (4)
- `DESERT_DUNES` (5), `DESERT_PLATEAU` (6), `VOLCANIC_FOOTHILLS` (7), `AUTUMN_HIGHLANDS` (8), `WETLANDS_VALLEY` (9)
- `COASTAL_PLAINS` (10), `TROPICAL_RAINFOREST` (11), `HUMID_COAST` (12), `VOLCANIC_CRATER` (13), `VOLCANIC_CALDERA` (14)
- `SHADOW_WOODS` (15), `MISTY_WOODS` (16), `DESERT_GLACIER` (17), `ANCIENT_FOREST` (18), `DEEP_DESERT` (19)

### 3. Temperature & Freezing Thresholds
- **Altitude-Based Interpolation**: Temperatures change smoothly as the player climbs from 0m to 1000m+ in altitude.
- **Diurnal (Day/Night) Curve**: Diurnal temperature swings calculated against the time of day.
- **Freezing Point Transition**: Whenever precipitation (Rain or Heavy Rain) is generated in subzero conditions (<= 0.0°C), it automatically manifests as **Light Snow** or **Heavy Snow / Blizzard**.
- **Sun-Showers**: Supports rare sun-shower weather patterns during sunny skies.

### 4. Forecast Queue & 4-Minute Cycles
- Generates a queue of upcoming weather conditions (default 7 cycles ahead).
- Advances automatically every 240 seconds (configurable) or manually in editor / via API.

### 5. Wind & Global Shader Integration (Foliage & Grass Sway)
Dynamically synchronizes weather parameters with Godot's global shader variables:
- `weather_wind_strength` (`float`): Current wind power multiplier (scales according to biome base power and active storm / blizzard multipliers).
- `weather_wind_direction` (`vec3`): Normalized 3D world-space wind direction.
- `weather_precipitation_strength` (`float`): Wetness and rain/snow intensity (0.0 to 1.2+).

These can be accessed directly in any Godot shader without extra script bindings. The project includes ready-to-use spatial shaders:
- **`materials/grass_wind.gdshader`**: Wind-reactive grass with macro sweeping waves, micro turbulence, tip-bending, root stability, and rain wetness glossiness.
- **`materials/foliage_wind.gdshader`**: Tree canopy and leaf flutter shader reacting to wind direction and velocity.
- **`scenes/grass_field.tscn` / `GrassField`**: High-performance instanced `MultiMeshInstance3D` grass generator.

```gdshader
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_toon;

global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;

uniform float sway_strength : hint_range(0.0, 2.0) = 0.45;

void vertex() {
    float height_factor = clamp(1.0 - UV.y, 0.0, 1.0);
    vec3 world_origin = MODEL_MATRIX[3].xyz;
    vec3 wind_dir = normalize(weather_wind_direction);
    
    float wave = sin(TIME * (1.5 + 0.2 * weather_wind_strength) + (world_origin.x + world_origin.z) * 0.1);
    vec3 sway = wind_dir * wave * sway_strength * max(weather_wind_strength, 0.5) * pow(height_factor, 1.5);
    sway.y -= length(sway.xz) * 0.25;
    
    VERTEX += (inverse(MODEL_MATRIX) * vec4(sway, 0.0)).xyz;
}
```

### 6. In-Editor `@tool` Controls
- **Play/Pause**: Toggle `is_playing` to freeze or progress weather in the viewport.
- **Biome Switching**: Change `current_biome` to preview climate behavior in real time.
- **Manual Overrides**: Toggle `force_weather` and select `manual_weather` to instantly test particle and audio effects.
- **Advance Cycle**: Click `trigger_advance_cycle` to step through forecast states immediately.

---

## Scene Tree Hierarchy

```text
Main (Node3D)
├── DateAndTime (Node)
├── WeatherFX (Node3D)
│   ├── RainParticles (GPUParticles3D)
│   │   └── Sub-Emitter -> RainSplashParticles
│   ├── RainSplashParticles (GPUParticles3D - Droplets & Ripples)
│   ├── SnowParticles (GPUParticles3D)
│   ├── RainLightSFX (AudioStreamPlayer)
│   ├── RainHeavySFX (AudioStreamPlayer)
│   ├── StormSFX (AudioStreamPlayer)
│   └── WindSFX (AudioStreamPlayer)
├── WorldEnvironment (WorldEnvironment)
├── DirectionalLight3D (Sun/Moon)
├── Zones (Node3D)
│   ├── PlainsZone (WeatherZone - Area3D)
│   └── MountainZone (WeatherZone - Area3D)
├── Player (CharacterBody3D)
└── HUD (CanvasLayer)
    ├── DateAndTimeDisplay (PanelContainer)
    ├── WeatherForecastDisplay (PanelContainer)
    └── TemperatureGaugeDisplay (Button)
```

---

## GDScript API Examples

```gdscript
extends Node3D

@onready var weather: WeatherFX = $WeatherFX
@onready var clock: DateAndTime = $DateAndTime

func _ready() -> void:
    weather.weather_changed.connect(_on_weather_changed)
    weather.temperature_changed.connect(_on_temperature_changed)
    weather.forecast_updated.connect(_on_forecast_updated)

func _on_weather_changed(new_weather: ClimateData.WeatherType, old_weather: ClimateData.WeatherType) -> void:
    print("Weather changed: ", new_weather)

func _on_temperature_changed(celsius: float) -> void:
    print("Current Temperature: %.1f°C" % celsius)

func force_rain_example() -> void:
    # Manually trigger rain with splashes & puddle ripples
    weather.set_weather(ClimateData.WeatherType.RAIN)

func resume_normal_forecast() -> void:
    # Return to procedural forecasting
    weather.resume_forecast()
```
