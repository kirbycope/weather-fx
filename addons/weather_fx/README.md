# Weather FX for Godot 4.8+

A high-performance, modular climate, weather, and atmospheric wind simulation system for Godot 4.8+. Features 20 universal biomes, altitude- and time-based temperature lapse curves, procedural 4-minute forecasting cycles, rain ground impact effects (puddle ripples & splash droplets), global wind shader integration with stylized foliage sway, interactive Zelda-inspired HUD widgets, and a comprehensive test lab (`demo.tscn`).

> [!NOTE]
> **Plugin Activation vs Direct Scene Usage**:
> All core scripts register standalone global class names (`WeatherFX`, `WeatherZone`, `WeatherForecastDisplay`, `TemperatureGaugeDisplay`, `WindDirectionDial`, `WindVFX`, `FallingLeaves`, `GrassField`, `ClimateData`).
> - **Direct Usage**: You can add these nodes to your scenes, attach scripts, or control them via GDScript immediately. Ensure global shader parameters are added under **Project Settings > Shader Globals**.
> - **Enabling the Plugin**: Enabling `Weather FX` in **Project Settings > Plugins** registers custom editor icons, adds node types directly to Godot's *Create New Node* dialog, and automatically registers all required **Shader Globals** in `ProjectSettings`.

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
- **Diagnostic Info & FPS Counter**: Real-time HUD readout of FPS, current temperature, active biome, wind speed & cardinal direction, altitude, and cycle progress timer.
- **Free Camera Orbit**: Right-click drag or WASD/Arrow keys to orbit around the scene and zoom in/out with the mouse scroll wheel.

---

## Core Features

### 1. 20 Universal Biomes
Provides statistical weather distribution tables, diurnal temperature ranges, altitude lapse rates, and baseline wind power across 20 distinct biomes:
- `TEMPERATE_PLAINS` (0), `NORTHERN_PLAINS` (1), `ARCTIC_TUNDRA` (2), `ARID_CANYON` (3), `ALPINE_PEAKS` (4)
- `DESERT_DUNES` (5), `DESERT_PLATEAU` (6), `VOLCANIC_FOOTHILLS` (7), `AUTUMN_HIGHLANDS` (8), `WETLANDS_VALLEY` (9)
- `COASTAL_PLAINS` (10), `TROPICAL_RAINFOREST` (11), `HUMID_COAST` (12), `VOLCANIC_CRATER` (13), `VOLCANIC_CALDERA` (14)
- `SHADOW_WOODS` (15), `MISTY_WOODS` (16), `DESERT_GLACIER` (17), `ANCIENT_FOREST` (18), `DEEP_DESERT` (19)

### 2. Atmospheric Wind & Foliage System
WeatherFX synchronizes real-time atmospheric wind parameters across GPU shaders and CPU particle systems:

- **Global Shader Uniforms**: Automatically updates Godot's `RenderingServer` global shader variables:
  - `weather_wind_strength` (`float`): Current wind power multiplier (scales with biome baseline and storm intensity).
  - `weather_wind_direction` (`vec3`): Normalized 3D world-space wind direction vector.
  - `weather_precipitation_strength` (`float`): Wetness and rain/snow intensity factor (`0.0` to `1.2+`).
- **Wind VFX Ribbons (`WindVFX`)**: Dynamic environmental wind particle system featuring stylized air flow ribbons, wind streaks, and periodic gust sweeps that automatically align their yaw rotation with the 3D wind vector.
- **Drifting Foliage Particles (`FallingLeaves`)**: Particle system attached to trees that sheds leaves drifting and swirling in direct response to global wind direction and strength.
- **Stylized Wind Shaders**:
  - `res://addons/weather_fx/resources/grass_wind.gdshader`: Multi-octave harmonic grass sway, tip-bending vertical dip conservation, 3-stop vertical color gradient (`color_base`, `color_mid`, `color_tip`), root AO darkening, rolling pasture macro-tint, sunlit blade backlight translucency, player/entity displacement interaction, and rain-soaked wetness darkening with glossy specular highlights.
  - `res://addons/weather_fx/resources/foliage_wind.gdshader`: Trunk lean, undulating branch sway, high-frequency leaf flutter, upward normal blending for fluffy Ghibli/BotW-style canopy lighting, and rain wetness response.
- **Instanced Grass Generator (`GrassField`)**: High-performance `MultiMeshInstance3D` field generator supporting Quaternius stylized grass models (`Common Short`, `Common Tall`, `Wispy Short`, `Wispy Tall`) and custom meshes.

### 3. Rain Ground Impact Effects (Splashes & Ripples)
- **Sub-Emitter Integration**: Primary falling raindrops dynamically spawn sub-emitter particles at their point of ground impact.
- **Water Droplet Splashes (Draw Pass 1)**: Tiny water droplets bursting upward and spraying outward under gravity.
- **Puddle Ripples (Draw Pass 2)**: Expanding circular concentric water ripple rings fading smoothly on surface contact.

### 4. Interactive Zelda-Inspired HUD Widgets
- **`WeatherForecastDisplay`**: Pill-shaped glassmorphic HUD widget featuring SVG vector weather icons and smooth timeline scrolling synchronized with the in-game clock and cycle timer.
- **`TemperatureGaugeDisplay`**: Circular segmented thermometer widget rendered with procedural shaders (`temperature_gauge.gdshader`), smooth cold-to-hot color interpolation (cyan -> mild gray -> warm orange), and a real-time needle indicator (`GaugeNeedle`).
- **`WindDirectionDial`**: Interactive 360° compass dial widget with cardinal points (`N`, `E`, `S`, `W`), directional wind arrow, and interactive click-and-drag vector rotation.

### 5. Temperature Curves, Lapse Rates & Freezing Transitions
- **Altitude-Based Interpolation**: Smooth temperature lapse rate as altitude climbs from 0m to 1500m+.
- **Diurnal (Day/Night) Solar Curve**: Solar angle calculations mapping time of day to realistic ambient and directional sun lighting.
- **Freezing Point Transition**: Whenever precipitation (Rain or Heavy Rain) is generated in subzero conditions ($\le 0.0^\circ\text{C}$), it automatically transitions into **Light Snow** or **Heavy Snow / Blizzard**.
- **Sun-Showers**: Supports rare sun-shower weather patterns during daylight conditions.

### 6. Procedural Forecasting Queue
- Generates a queue of upcoming weather conditions (default 7 cycles ahead).
- Advances automatically every 240 seconds (configurable) or manually via API / UI controls.

---

## Scene Tree Architecture

```text
WeatherFXDemo (Node3D)
├── WorldEnvironment (WorldEnvironment)
├── DirectionalLight3D (Sun/Moon Light)
├── DemonstrationTarget (Node3D - Target Marker)
├── Ground (StaticBody3D)
├── Scenery (Node3D)
│   ├── GrassField (MultiMeshInstance3D - Stylized Grass Generator)
│   ├── Tree1..5 (Node3D)
│   │   ├── Mesh (MeshInstance3D - Bark & Foliage Wind Shaders)
│   │   └── FallingLeaves (GPUParticles3D - Wind-Reactive Leaf Particle System)
├── CameraPivot (Node3D)
│   └── Camera3D (Orbit Camera)
├── DateAndTime (Node - Day/Night Time Clock)
├── WeatherFX (Node3D - Core Climate Controller)
│   ├── WindVFX (Node3D - Environmental Wind Ribbons & Gust Sweeps)
│   ├── RainParticles (GPUParticles3D)
│   │   └── Sub-Emitter -> RainSplashParticles
│   ├── RainSplashParticles (GPUParticles3D - Droplet Splashes & Concentric Ripples)
│   ├── SnowParticles (GPUParticles3D - Billboarding Snowflakes)
│   ├── RainLightSFX (AudioStreamPlayer)
│   ├── RainHeavySFX (AudioStreamPlayer)
│   ├── StormSFX (AudioStreamPlayer)
│   └── WindSFX (AudioStreamPlayer)
└── HUD (CanvasLayer)
    ├── ControlPanel (PanelContainer - Biome, Weather, Altitude & Wind Controls)
    └── BottomRight (Control)
        ├── DateAndTimeDisplay (PanelContainer)
        ├── WeatherForecastDisplay (PanelContainer - Zelda-style Timeline)
        ├── TemperatureGaugeDisplay (Button - Circular Segmented Gauge)
        └── HUDWindDial (Control - Glance Compass Dial)
```

---

## GDScript API Reference

### Basic Setup & Signals

```gdscript
extends Node3D

@onready var weather: WeatherFX = $WeatherFX

func _ready() -> void:
    weather.weather_changed.connect(_on_weather_changed)
    weather.temperature_changed.connect(_on_temperature_changed)
    weather.wind_changed.connect(_on_wind_changed)
    weather.forecast_updated.connect(_on_forecast_updated)

func _on_weather_changed(new_weather: ClimateData.WeatherType, old_weather: ClimateData.WeatherType) -> void:
    print("Weather transitioned to: ", new_weather)

func _on_temperature_changed(celsius: float) -> void:
    print("Current Temperature: %.1f°C / %.1f°F" % [celsius, ClimateData.celsius_to_fahrenheit(celsius)])

func _on_wind_changed(strength: float, direction: Vector3) -> void:
    print("Wind updated: %.1f m/s towards %s" % [strength, direction])

func _on_forecast_updated(forecast_array: Array) -> void:
    print("New forecast queue: ", forecast_array)
```

### Controlling Weather & Wind

```gdscript
# Switch biome
weather.current_biome = ClimateData.BiomeZone.ARCTIC_TUNDRA

# Force specific weather override (Rain, Storm, Snow, Blue Sky, etc.)
weather.force_weather = true
weather.manual_weather = ClimateData.WeatherType.RAIN

# Resume procedural forecast simulation
weather.force_weather = false
weather.resume_forecast()

# Change wind direction vector (normalized 3D vector)
weather.wind_direction = Vector3(0.0, 0.0, -1.0) # Blow North (-Z)

# Adjust global wind strength multiplier
weather.wind_strength_multiplier = 1.5

# Step to the next forecast cycle immediately
weather.advance_cycle()
```

### Static Helper Methods

```gdscript
# Read global atmospheric parameters from anywhere in code
var wind_spd: float = WeatherFX.get_wind_strength()
var wind_dir: Vector3 = WeatherFX.get_wind_direction()
var wetness: float = WeatherFX.get_precipitation_strength()

# Temperature conversions
var temp_f: float = ClimateData.celsius_to_fahrenheit(20.0) # 68.0°F
var temp_c: float = ClimateData.fahrenheit_to_celsius(68.0) # 20.0°C
```

---

## Global Shader Parameters

If creating custom shaders for characters, terrain, or water, you can read WeatherFX atmospheric globals directly:

```gdshader
shader_type spatial;

global uniform float weather_wind_strength;
global uniform vec3 weather_wind_direction;
global uniform float weather_precipitation_strength;

void vertex() {
    // Displace vertex along wind vector
    vec3 wind_displacement = weather_wind_direction * weather_wind_strength * 0.05 * VERTEX.y;
    VERTEX += (inverse(MODEL_MATRIX) * vec4(wind_displacement, 0.0)).xyz;
}

void fragment() {
    // Darken wet surfaces during rain/snow
    float wetness = clamp(weather_precipitation_strength, 0.0, 1.0);
    ALBEDO *= (1.0 - wetness * 0.25);
    ROUGHNESS = mix(ROUGHNESS, 0.1, wetness);
    SPECULAR = mix(SPECULAR, 0.8, wetness);
}
```

---

## Credits & Attributions

Special thanks and attributions to open-source creators whose models, textures, shaders, and techniques inspired WeatherFX:

- **Quaternius** – *Stylized Nature Megakit* ([CC0 Public Domain / quaternius.com](https://quaternius.com/)) for tree models, bark, and foliage textures.

---

## License

This project is licensed under the [MIT License](LICENSE).
