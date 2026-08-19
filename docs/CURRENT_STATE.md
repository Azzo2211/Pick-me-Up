# CURRENT_STATE.md

## Repository state
Primary repository: `Azzo2211/Pick-me-Up`.
Primary branch: `main`.
The user's local project is connected to this repository.

## Active implementation
Riftward is being developed as a full game in Godot. The active project is:

```text
godot/project.godot
```

The project is named **Riftward: The Last Ascent** and currently targets Godot 4.7 compatibility settings.

Relevant hub code currently includes:
- `godot/scripts/base/base_hub.gd`
- `godot/scripts/base/base_building.gd`
- `godot/scripts/base/building_data.gd`
- `godot/scripts/base/hero_agent.gd`
- `godot/scripts/base/building_upgrade_system.gd`
- `godot/scripts/base/base_notification_system.gd`

Visible hero agents already have movement/path/activity behavior and can choose unlocked facilities as destinations.

## Historical web code
The repository still contains files from the previous web implementation:
- `core.js`
- `combat.js`
- `app.js`
- `index.html`
- `styles.css`
- `server.js`

These files are **not an active version of the game** and must not receive parallel feature development. They may be inspected only as historical reference or as a source for logic worth porting into Godot.

## Current implemented systems
The current Godot project already contains or represents important parts of the game's foundation, including:
- playable mission/floor archetypes;
- party of five;
- autonomous Utility AI combat;
- macro Master commands;
- persistent heroes;
- summon/progression/equipment systems;
- permadeath;
- facilities and hub interactions;
- deterministic stage persistence.

This is the **current development state**, not a fixed vertical slice and not the final content boundary. The project should be expanded incrementally toward the full game.

## Important known design drift
Some older documentation/code represents facilities that conflict with newer hub decisions. In particular, existing hub code may currently visualize facilities such as Workshop earlier than the latest design direction allows.

When this happens, do not assume the existing implementation is authoritative. Follow the priority order in `AGENTS.md`, especially the newer decisions in `GAME_VISION.md` and `ART_DIRECTION.md`.

## Immediate engineering philosophy
The project is already functional enough that Agent A should improve it incrementally rather than rebuild it from scratch.
Before each task, identify the exact subsystem involved, inspect its current implementation, and preserve unrelated working behavior.
