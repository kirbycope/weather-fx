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

## Acknowledgment

- Before responding to any user request, you MUST acknowledge that you have read and understood the above instructions. You MUST also acknowledge that you will follow the rules and guidelines defined in the above files when writing code, designing systems, or implementing features for this project.
