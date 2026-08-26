# GitHub Copilot Instructions

## Core Project Skills & Architecture

- Whenever the user asks you to write code, design systems, or implement features, you MUST read and conform to the guidelines, architectural patterns, and project rules defined in the following files located in this project:

* `.agents/skills/*/SKILL.md`
* `.github/skills/*/SKILL.md`
* `.github/rules/*.md`

### Exceptions

- Allow one-line `if` statements for the ternary operator.

## Additional Rules:

- Never assume use Vector3.UP for player.up_direction, use player.up direction instead.
  - Also, never assume positive Y is up, use player.up_direction instead.
- When writing GDScript, prefer explicit local variable type annotations over `:=` for any generated or edited code, especially for expressions involving math operators, `clamp()`, `min()`, `max()`, `lerp()`, `move_toward()`, `dot()`, `slide()`, node/property access, enum values, or function return values. After editing GDScript, check diagnostics for inference errors such as `Cannot infer the type of ... variable because the value doesn't have a set type` and fix them before finishing.
- For Player child manager scripts (for example, `inventory.gd`), prefer `@export var player: Player` wired in the scene over runtime parent discovery or assignment in `_ready()` / `_process()`. Avoid per-frame wiring for player references.
- Use the `.agents/mcp_config.json` file for configuring the MCP (Multi-Component Project) settings.
  - Always use the `godot-mcp-runtime` to test code changes.
  - Write tests using `gut`
- Favor Node over Code. Nodes are a core part of Godot's design. Edit .tscn files to add connections instead of using \_ready() functions.
- Use signals and getters/setters to avoid constant checks in process or physics_process.
- Look for MIT or CC0 based solutions from,
  - Code: https://github.com/search
    - Also a good place to look for shaders
  - Materials: https://ambientcg.com/list?type=material%2Cdecal%2Catlas&sort=popular
  - Models: https://sketchfab.com/search
  - Shaders: https://godotshaders.com/shader)
- I have a private collection of assets I keep in [macOS](tbd) [Windows](C:\GitHub\godot-private-asset-library)
  - Check the /resources directory for \*.tres files that describe the content
    - Use mcp to check the assets as needed
- Ask me for sound effects and music when needed, I have some (or can get some) from Itch.io
  - I like the mostly free https://tommusic.itch.io/ and the paid https://gravity-sound.itch.io/
  - Keep addons atomic, they should allow interoperability (like `addons/date-and-time` can work with `weather-fx` but the demos are independent)
- Addons should follow this directory structure:
  ```text
  addons/<addon_name>/
  ├── assets/       # Raw media assets (textures, audio SFX/music, models, icons)
  ├── resources/    # Godot resource files (.tres, materials, custom resources, themes)
  ├── scenes/       # Reusable component and prefab scenes (.tscn)
  │   └── demo/     # Standalone demo showcase scenes and interactive test harnesses
  ├── scripts/      # GDScript source code files and node controllers (.gd)
  ├── tests/        # GUT automated unit and integration test suites (test_*.gd)
  ├── .gutconfig.json # GUT configuration file
  ├── plugin.cfg      # Plugin configuration file
  ├── plugin.gd       # Plugin entry point
  └── README.md       # Plugin documentation
  ```

## Acknowledgment

- Before responding to any user request, you MUST acknowledge that you have read and understood the above instructions. You MUST also acknowledge that you will follow the rules and guidelines defined in the above files when writing code, designing systems, or implementing features for this project.
