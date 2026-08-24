# Weather FX for Godot 4.8+

A high-performance, modular climate and weather simulation system featuring 20 universal biomes, altitude- and time-based temperature curves, 4-minute forecasting cycles, global wind shader integration, and in-editor `@tool` controls.

> [!NOTE]
> **Plugin Activation vs Scene Usage**:
> All core scripts use `class_name` (`WeatherFX`, `WeatherZone`, `WeatherForecastDisplay`, `ClimateData`).
> - **Direct Usage**: You can add and use these nodes immediately in your scenes, drag `.gd` scripts, or call them via code without enabling anything in Project Settings.
> - **Enabling the Plugin**: Enabling `Weather FX` in **Project Settings > Plugins** registers the custom icons and adds the node types directly to Godot's "Create New Node" hierarchy dialog.

---

## Features

### 1. 20 Universal Biomes
Provides concise, universal biome definitions with exact statistical probabilities:
- `TEMPERATE_PLAINS` (0)
- `NORTHERN_PLAINS` (1)
- `ARCTIC_TUNDRA` (2)
- `ARID_CANYON` (3)
- `ALPINE_PEAKS` (4)
- `DESERT_DUNES` (5)
- `DESERT_PLATEAU` (6)
- `VOLCANIC_FOOTHILLS` (7)
- `AUTUMN_HIGHLANDS` (8)
- `WETLANDS_VALLEY` (9)
- `COASTAL_PLAINS` (10)
- `TROPICAL_RAINFOREST` (11)
- `HUMID_COAST` (12)
- `VOLCANIC_CRATER` (13)
- `VOLCANIC_CALDERA` (14)
- `SHADOW_WOODS` (15)
- `MISTY_WOODS` (16)
- `DESERT_GLACIER` (17)
- `ANCIENT_FOREST` (18)
- `DEEP_DESERT` (19)

### 2. Temperature & Freezing Thresholds
- **Altitude-Based Interpolation**: Temperatures change smoothly as the player climbs from 0m to 1000m+ in altitude.
- **Diurnal (Day/Night) Curve**: Diurnal temperature swings calculated against the time of day.
- **Freezing Point Transition**: Whenever precipitation (Rain or Heavy Rain) is generated in subzero conditions (<= 0.0°C), it automatically manifests as **Light Snow** or **Heavy Snow / Blizzard**.
- **Sun-Showers**: Supports rare sun-shower weather patterns during sunny skies.

### 3. Forecast Queue & 4-Minute Cycles
- Generates a queue of upcoming weather conditions (default 5 cycles ahead).
- Advances automatically every 240 seconds (configurable) or manually in editor / via API.

### 4. Wind & Shader Integration
- Dynamically updates global shader uniforms:
  - `weather_wind_strength` (float)
  - `weather_wind_direction` (Vector3)
  - `weather_precipitation_strength` (float)
- Foliage, grass, and water shaders can read these uniforms without manual wiring.

### 5. In-Editor `@tool` Controls
- **Play/Pause**: Toggle `is_playing` to freeze or progress weather in the viewport.
- **Biome Switching**: Change `current_biome` to preview climate behavior in real time.
- **Manual Overrides**: Toggle `force_weather` and select `manual_weather` to instantly test particle and audio effects.
- **Advance Cycle**: Click `trigger_advance_cycle` to step through forecast states immediately.

---

## How to Add Weather and Time to Your Scene

### Recommended Scene Tree Hierarchy

```text
Main (Node3D)
├── DateAndTime (Node)
├── WeatherFX (Node3D)
│   ├── RainParticles (GPUParticles3D)
│   ├── SnowParticles (GPUParticles3D)
│   ├── RainLightSFX (AudioStreamPlayer)
│   ├── RainHeavySFX (AudioStreamPlayer)
│   ├── StormSFX (AudioStreamPlayer)
│   └── WindSFX (AudioStreamPlayer)
├── WorldEnvironment (WorldEnvironment)
├── DirectionalLight3D (Sun/Moon)
├── Zones (Node3D)
│   ├── PlainsZone (WeatherZone - Area3D)
│   │   └── CollisionShape3D (Box/Cylinder shape)
│   └── MountainZone (WeatherZone - Area3D)
│       └── CollisionShape3D (Box/Cylinder shape)
├── Player (CharacterBody3D)
└── HUD (CanvasLayer)
    ├── DateAndTimeDisplay (PanelContainer)
    └── WeatherForecastDisplay (PanelContainer)
```

---

### Step-by-Step Setup Guide

#### 1. Enable the Plugins (Optional but Recommended)
Open **Project > Project Settings > Plugins** and enable:
- `Date and Time`
- `Weather FX`

*(Enabling adds custom icons and displays nodes in Godot's Add Node dialog, but is not strictly required if adding nodes by class name or code).*

#### 2. Add `DateAndTime`
1. In your main scene, right-click the root node and click **Add Child Node**.
2. Select **`DateAndTime`** (found under `Node`).
3. In the Inspector:
   - Set **`Minutes Per Day`** (e.g. `24.0` real minutes for a full 24h day).
   - Set **`Current Time`** (e.g. `8.0` for 8:00 AM or `12.0` for noon).
   - Check **`Is Running`** to let time flow.

#### 3. Add `WeatherFX`
1. Right-click the root node and add **`WeatherFX`** (found under `Node3D`).
2. In the Inspector:
   - **`Current Biome`**: Choose your starting biome (e.g. `TEMPERATE_PLAINS`, `ARCTIC_TUNDRA`, `DESERT_DUNES`).
   - **`Date And Time Node`**: Assign your `DateAndTime` node (or leave empty to auto-detect).
   - **`Target Node`**: Assign your `Player` node so `WeatherFX` automatically calculates temperature based on player altitude.
   - **`Cycle Duration Seconds`**: Default `240.0` (4 minutes per forecast cycle).
   - **`Rain Particles` / `Snow Particles`**: (Optional) Assign your particle nodes.
   - **`Audio Rain Light` / `Audio Rain Heavy` / `Audio Storm` / `Audio Wind`**: (Optional) Assign your ambient audio players.
   - **`World Environment`**: (Optional) Assign your `WorldEnvironment` node to enable automatic dynamic fog.

#### 4. Add Spatial Biome Zones (`WeatherZone`)
To make weather and temperature change when the player walks into different areas of the map:
1. Add a **`WeatherZone`** node (found under `Area3D`).
2. Add a child **`CollisionShape3D`** (e.g. `BoxShape3D` or `CylinderShape3D`) covering that region of the map.
3. In the `WeatherZone` inspector, select the **`Biome`** (e.g. `ARCTIC_TUNDRA` for a snowy mountain or `TROPICAL_RAINFOREST` for a jungle).
4. When the player enters the zone collision shape, `WeatherFX` will automatically transition to that biome, update temperature, and refresh the forecast and HUD display.

#### 5. Add HUD UI Widgets
To show the current date/time and the 5-cycle weather forecast on screen:
1. Under your `HUD` (`CanvasLayer` or `Control`), add:
   - **`WeatherForecastDisplay`**: Displays the active weather icon + 4 upcoming cycles, biome name, and live temperature in °C.
   - **`DateAndTimeDisplay`**: Displays live time and date (supports 12h/24h formats).
2. The widgets will automatically link to `WeatherFX` and `DateAndTime` in the scene and update reactively as you change regions.

---

### GDScript API Examples

```gdscript
extends Node3D

@onready var weather: WeatherFX = $WeatherFX
@onready var clock: DateAndTime = $DateAndTime

func _ready() -> void:
    # Connect to weather events
    weather.weather_changed.connect(_on_weather_changed)
    weather.temperature_changed.connect(_on_temperature_changed)
    weather.forecast_updated.connect(_on_forecast_updated)
    
    # Connect to clock events
    clock.hour_changed.connect(_on_hour_changed)
    clock.day_changed.connect(_on_day_changed)

func _on_weather_changed(new_weather: ClimateData.WeatherType, old_weather: ClimateData.WeatherType) -> void:
    print("Weather changed to: ", ClimateData.get_weather_name(new_weather))

func _on_temperature_changed(celsius: float) -> void:
    print("Current Temperature: %.1f°C" % celsius)

func _on_hour_changed(hour: int) -> void:
    print("Current Hour: %02d:00" % hour)

func force_storm_example() -> void:
    # Manually force a thunderstorm
    weather.set_weather(ClimateData.WeatherType.STORM)

func resume_normal_forecast() -> void:
    # Return to procedural forecasting
    weather.resume_forecast()
```
