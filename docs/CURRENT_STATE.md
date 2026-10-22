# CURRENT_STATE.md

## Repository state
Primary repository: `Azzo2211/Pick-me-Up`.
Primary branch: `main`.
The user's local project is connected to this repository.

## Active implementation
Riftward is developed as a full game in Godot (4.7, Compatibility renderer):

```text
godot/project.godot
```

### Code map
| Area | Files |
|---|---|
| Game rules, save, economy, progression | `godot/scripts/game_state.gd` (autoload `GameState`, save v3) |
| Main screen, HUD, side panel, modals, mission flow | `godot/scripts/main.gd` |
| Building panels, hero dossier, journal, settings, mission report | `godot/scripts/ui/facility_panels.gd` |
| Shared theme and widgets (Fredoka/Nunito fonts) | `godot/scripts/ui/ui_kit.gd` |
| 3D base: island, plaza, paths, vegetation, labels, navigation | `godot/scripts/hub3d/hub_world.gd` |
| Camera, picking, hover/click | `godot/scripts/hub3d/hub_view.gd` |
| Procedural buildings (level N = N storeys) | `godot/scripts/hub3d/building_model.gd`, `portal.gdshader` |
| Heroes living in the base | `godot/scripts/hub3d/hub_agent.gd` |
| Chibi hero/monster models (shared with battle) | `godot/scripts/hub3d/chibi_model.gd`, `mesh_kit.gd` |
| Mission / battle | `godot/scripts/battle/battle_scene.gd` |
| 2D chibi portraits for UI | `godot/scripts/hero_portrait.gd` |

### Tests
Run from the repository root (Godot executable on PATH or full path):

```text
godot --headless --path godot -s res://tests/test_runner.gd -- --test-mode        # 17 rule tests
godot --headless --path godot -s res://tests/ui_smoke_runner.gd -- --test-mode    # 26 UI checks incl. a full mission
godot --path godot -s res://tests/visual_capture_runner.gd -- --test-mode         # screenshots → godot/tests/captures/
```

`tests/captures/` contains `.gdignore`, so screenshots are not imported as game assets.

## What the player sees now
- The home screen **is the base**: a 3D floating island with an open plaza (Nexus crystal in the centre), raised Training Center, simple Dormitory, blue-dome Merging Center and a large suspended Mission Gate connected by a stone bridge. Lots of trees, flowers and bushes, no fences.
- Tapping a building moves the camera to it and opens its panel on the right; the base stays visible behind.
- Heroes walk the paths: assigned heroes go to the training platform and swing at the dummies, resting heroes enter the Dormitory, injured heroes sit on its bench, the squad waits near the bridge, free heroes wander and chat. Tapping a hero opens their dossier.
- Missions start by watching the squad walk into the portal, then a 3D battle with the same characters.

## Implemented systems
- Real economy by default; development mode (infinite resources, hidden values) is an option in Settings.
- Base levels 1–5 (Nexus crystal). Each base level raises the facility level cap by one and opens new construction plots; facilities must then be built.
- Facilities: Training, Dormitory, Merging, Gate (Lv.1); Armory (Base Lv.2); Warehouse and Workshop (Base Lv.3); Alchemy (Base Lv.4).
- Timed training (XP over real time, offline up to 8 h), timed rest (fatigue, morale, injuries heal).
- XP and level-ups capped by rarity; promotions with stones (6★ needs Floor 30, 7★ needs Floor 60).
- Summon pools: Normal 78/19/3 (10.000 Gold), High-grade 93,5/5,5/1 with soft pity 70 and hard pity 100 (500 Gems), Transcendent 98/1,8/0,2 for 5★/6★/7★ (3.000 Gems, unlocks after Floor 20).
- Fusion of three same-rarity heroes up to 5★.
- Tower: floors 1–5 hand-made, 6–100 generated deterministically from the world seed; boss every 5 floors; retries keep the same floor, rewards shrink per attempt.
- Battle: party of 5 (2 Front / 2 Mid / 1 Rear), 20 ticks/s, decisions at 5 Hz, Utility-style target scoring, ranged kiting, ammo, healing, fear at low courage, boss slam, objectives (Subjugation, Survival, Exploration, Defense, Boss), macro orders only, permadeath.
- Armory forging and equipping, Workshop refining, Alchemy tonics.

## Historical web code
`core.js`, `combat.js`, `app.js`, `index.html`, `styles.css`, `server.js` are the old web prototype. Not active; reference only.

## Save compatibility
Saves from v2 migrate automatically to v3: development mode is switched off, old facility keys are mapped (Training Center → training, Lodging → dormitory, Synthesis Chamber → merging), facilities not allowed at Base Lv.1 return to "to be built", string injuries become timed injuries.
