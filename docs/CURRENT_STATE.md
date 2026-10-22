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
| Dark ornate theme, widgets, icons (Cinzel/Alegreya fonts) | `godot/scripts/ui/ui_kit.gd`, `ornate_style.gd`, `ornate_divider.gd`, `ui_icon.gd` |
| Hero cards (summons, roster, memorial, dossier) | `godot/scripts/ui/hero_card.gd` |
| 2D manhwa-style portraits | `godot/scripts/hero_portrait.gd` |
| 3D base: island, walls, streets, plaza, forest, navigation, labels | `godot/scripts/hub3d/hub_world.gd` |
| Camera, picking, hover/click | `godot/scripts/hub3d/hub_view.gd` |
| Buildings (level N = N storeys, batched meshes) | `godot/scripts/hub3d/building_model.gd`, `portal.gdshader` |
| People living in the base (heroes and villagers) | `godot/scripts/hub3d/hub_agent.gd` |
| Human characters and monsters (shared with battle) | `godot/scripts/hub3d/character_model.gd` |
| Mesh batching, materials, light presets, trees and rocks | `mesh_builder.gd`, `world_materials.gd`, `world_look.gd`, `nature_kit.gd`, `shaders/*.gdshader` |
| Mission / battle (biome arenas, HUD) | `godot/scripts/battle/battle_scene.gd` |

### Tests
Run from the repository root (Godot executable on PATH or full path):

```text
godot --headless --path godot -s res://tests/test_runner.gd -- --test-mode          # 25 rule tests
godot --headless --path godot -s res://tests/ui_smoke_runner.gd -- --test-mode      # 26 UI checks incl. a full mission
godot --headless --path godot -s res://tests/balance_probe_runner.gd -- --test-mode # balance table (optional --levels= --floors=)
godot --path godot -s res://tests/visual_capture_runner.gd -- --test-mode           # UI screenshots → godot/tests/captures/
godot --path godot -s res://tests/hub_preview_runner.gd -- --test-mode --base5      # base previews (--base2/3/5, --light=day|night)
godot --path godot -s res://tests/battle_preview_runner.gd -- --test-mode           # battle screenshots
godot --path godot -s res://tests/character_probe_runner.gd -- --test-mode          # character line-up
```

`tests/captures/` contains `.gdignore`, so screenshots are not imported as game assets.

## What the player sees now
- The home screen **is the base**: a walled hamlet on a floating island at dusk. Open plaza with the Nexus crystal, ring street, raised Training yard, timber Dormitory, rotunda Merging Center with a copper dome and blue light, forest, pond and waterfall, and the Mission Gate on its own rock reached by a chained bridge.
- The town grows with the base level: palisade → stone wall → towers; dirt tracks → cobbles; torches → lamp posts, market stalls, fountain, statues, floating lanterns.
- Tapping a building moves the camera to it and opens its panel on the right; the base stays visible behind. Labels never overlap; status lines appear on hover; badges mark only real news (new floor at the Gate, idle trainees, tired heroes, promotions, affordable plots).
- Heroes and villagers walk the streets: trainees spar on the yard, resting heroes enter the Dormitory, injured heroes sit on its benches, the squad waits by the gate road. Tapping a hero opens their dossier.
- Missions start with the squad walking into the portal, then a 3D battle in a biome arena with the same characters and a HUD with party portraits on the left and the boss bar on top.

## Implemented systems
- Real economy by default; development mode (infinite resources, hidden values) is an option in Settings. Settings also switch the base light (dusk, day, night).
- Base levels 1–5 (Nexus crystal). Each base level raises the facility level cap by one and opens new construction plots; facilities must then be built.
- Facilities: Training, Dormitory, Merging, Gate (Lv.1); Armory (Base Lv.2); Warehouse and Workshop (Base Lv.3); Alchemy (Base Lv.4).
- Timed training (XP over real time, offline up to 8 h), timed rest (fatigue, morale, injuries heal).
- XP and level-ups capped by rarity; promotions with stones (6★ needs Floor 30, 7★ needs Floor 60).
- Summon pools: Normal 78/19/3 for 1–3★ (10.000 Gold), High-grade 93,5/5,5/1 for 3–5★ with soft pity 70 and hard pity 100 (500 Gems), Transcendent 78/20/1,8/0,2 for 4–7★ (4.000 Gems, unlocks after Floor 20). Summons are revealed as cards that flip.
- Fusion of three same-rarity heroes up to 5★.
- Tower: floors 1–5 hand-made, 6–100 generated deterministically from the world seed; boss every 5 floors; retries keep the same floor, rewards shrink per attempt.
- Battle: party of 5 (2 Front / 2 Mid / 1 Rear), 20 ticks/s, decisions at 5 Hz, Utility-style target scoring, ranged kiting, ammo, healing (never on enemies, never hitting allies), fear at low courage, boss slam, objectives (Subjugation, Survival, Exploration with a hero running to free points, Defense won if the beacon survives the timer, Boss), macro orders only, permadeath.
- Armory forging and equipping, Workshop refining, Alchemy tonics.
- Emergency recruit: a free 1★ every 30 minutes when fewer than five heroes are alive.

## Historical web code
`core.js`, `combat.js`, `app.js`, `index.html`, `styles.css`, `server.js` are the old web prototype. Not active; reference only.

## Save compatibility
Saves from v2 migrate automatically to v3: development mode is switched off, old facility keys are mapped (Training Center → training, Lodging → dormitory, Synthesis Chamber → merging), facilities not allowed at Base Lv.1 return to "to be built", string injuries become timed injuries.
