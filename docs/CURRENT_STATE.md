# CURRENT_STATE.md

## Repository state
Primary repository: `Azzo2211/Pick-me-Up`.
Primary branch: `main`.
The user's local project is connected to this repository.

## Active implementation
Riftward is developed as a full game in Godot (4.7, Forward+ renderer with automatic fallback to D3D12/OpenGL):

```text
godot/project.godot
```

### Code map
| Area | Files |
|---|---|
| Game rules, save, economy, progression | `godot/scripts/game_state.gd` (autoload `GameState`, save v4) |
| Main screen, HUD, side panel, modals, mission flow | `godot/scripts/main.gd` |
| Building panels, hero dossier, journal, settings, mission report | `godot/scripts/ui/facility_panels.gd` |
| Neon "System" theme, widgets, icons (Oxanium/Exo 2 fonts) | `godot/scripts/ui/ui_kit.gd`, `ornate_style.gd`, `ornate_divider.gd`, `ui_icon.gd` |
| Hero cards (summons, roster, memorial, dossier) | `godot/scripts/ui/hero_card.gd` |
| Summon event (full-screen rift, colour shift, card reveal) | `godot/scripts/ui/summon_event.gd` |
| Tower map (10 floors per page, zig-zag path, boss diamonds) | `godot/scripts/ui/tower_map.gd` |
| Mission end: Hero Lost cards, then Stage Clear / failure summary | `godot/scripts/ui/mission_result_screen.gd` |
| Loading screen (startup and before each mission) | `godot/scripts/ui/loading_screen.gd` |
| 2D manhwa-style portraits | `godot/scripts/hero_portrait.gd` |
| 3D base: island, walls, streets, plaza, forest, navigation, labels | `godot/scripts/hub3d/hub_world.gd` |
| Camera, picking, hover/click | `godot/scripts/hub3d/hub_view.gd` |
| Buildings (level N = N storeys, batched meshes) | `godot/scripts/hub3d/building_model.gd`, `portal.gdshader` |
| People living in the base (heroes and villagers) | `godot/scripts/hub3d/hub_agent.gd` |
| Human characters and monsters (shared with battle) | `godot/scripts/hub3d/character_model.gd` |
| Mesh batching, materials, light presets and graphics quality, trees and rocks | `mesh_builder.gd`, `world_materials.gd`, `world_look.gd`, `nature_kit.gd`, `shaders/*.gdshader` |
| Leaf, needle and grass textures (generated, committed) | `tools/gen_textures.py` → `godot/assets/textures/` |
| Mission / battle (biome arenas, HUD) | `godot/scripts/battle/battle_scene.gd` |

### Tests
Run from the repository root (Godot executable on PATH or full path):

```text
godot --headless --path godot -s res://tests/test_runner.gd -- --test-mode          # 29 rule tests
godot --headless --path godot -s res://tests/ui_smoke_runner.gd -- --test-mode      # 29 UI checks incl. a full mission
godot --headless --path godot -s res://tests/balance_probe_runner.gd -- --test-mode # balance table (optional --levels= --floors=)
godot --path godot -s res://tests/visual_capture_runner.gd -- --test-mode           # UI screenshots → godot/tests/captures/
godot --path godot -s res://tests/hub_preview_runner.gd -- --test-mode --base5      # base previews (--base2/3/5, --light=day|night)
godot --path godot -s res://tests/battle_preview_runner.gd -- --test-mode           # battle screenshots
godot --path godot -s res://tests/character_probe_runner.gd -- --test-mode          # character line-up
godot --path godot -s res://tests/portrait_quality_runner.gd -- --test-mode         # every portrait style, large and small
godot --path godot -s res://tests/quality_probe_runner.gd -- --test-mode --scene=nature   # close-up test bench (nature|single|buildings|building|people)
```

Screenshot runners need a display and a GPU renderer (Forward+); on Linux without a GPU they run under `xvfb-run` with Mesa lavapipe (`--rendering-driver vulkan`), slowly.

`tests/captures/` contains `.gdignore`, so screenshots are not imported as game assets.

## What the player sees now
- The home screen **is the base**: a walled hamlet on a floating island at dusk. Open plaza with the faceted Nexus crystal, ring street, raised Training yard, timber Dormitory, rotunda Merging Center with a dome and blue light, timber Warehouse, round Alchemy hut with a green cauldron glow, a painterly forest of leaf-card trees, pond and waterfall, layered rock cliffs, and the Mission Gate on its own rock reached by a chained bridge.
- Every surface has per-pixel relief and soft shadows with ambient occlusion; characters have smooth bodies and faces. Settings → "Qualità grafica" (Alta/Media/Bassa) lowers effects on slower PCs.
- The town grows with the base level: palisade → stone wall → towers; dirt tracks → cobbles; torches → lamp posts, market stalls, fountain, statues, floating lanterns.
- Tapping a building moves the camera to it and opens its panel on the right; the base stays visible behind. Labels never overlap; status lines appear on hover; badges mark only real news (new floor at the Gate, idle trainees, tired heroes, promotions, affordable plots, gear to equip, a full Warehouse, injured heroes Alchemy can treat).
- Heroes and villagers walk the streets: trainees spar on the yard, resting heroes enter the Dormitory, injured heroes sit on its benches, the squad waits by the gate road. Idle heroes meet their friends and go where their personality takes them. Tapping a hero opens their dossier (with their strongest bonds).
- Bottom dock: Heroes (full roster with role / stars / state filters and sorting), Squad (drag heroes onto Front / Mid / Rear slots), Tower (map of the floors with risk, squad power and rewards), Shop, Journal, Settings.
- A loading screen ("connessione al Nexus") opens the game; another one ("apertura del varco") covers the jump into a mission.
- Missions start with the squad walking into the portal, then a 3D battle in a biome arena with the same characters and a HUD with party portraits on the left and the boss bar on top.

## Implemented systems
- Real economy by default; development mode (infinite resources, hidden values) is an option in Settings. Settings also switch the base light (dusk, day, night).
- Base levels 1–5 (Nexus crystal). Each base level raises the facility level cap by one and opens new construction plots; facilities must then be built.
- Facilities: Training, Dormitory, Merging, Gate, Warehouse, Alchemy (Base Lv.1); Armory (Base Lv.2); Workshop (Base Lv.3).
- Timed training (XP over real time, offline up to 8 h), timed rest (fatigue, morale, injuries heal).
- XP and level-ups capped by rarity; promotions with stones (6★ needs Floor 30, 7★ needs Floor 60).
- Summon pools: Normal 78/19/3 for 1–3★ (10.000 Gold), High-grade 93,5/5,5/1 for 3–5★ with soft pity 70 and hard pity 100 (500 Gems), Transcendent 78/20/1,8/0,2 for 4–7★ (4.000 Gems, unlocks after Floor 20). Summons are revealed as cards that flip.
- Fusion of three same-rarity heroes up to 5★.
- Tower: floors 1–5 hand-made, 6–100 generated deterministically from the world seed; boss every 5 floors; retries keep the same floor, rewards shrink per attempt.
- Battle: party of 5 (2 Front / 2 Mid / 1 Rear), 20 ticks/s, decisions at 5 Hz, Utility-style target scoring, ranged kiting, ammo, healing (never on enemies, never hitting allies), fear at low courage, boss slam, objectives (Subjugation, Survival, Exploration with a hero running to free points, Defense won if the beacon survives the timer, Boss), macro orders only, permadeath.
- Armory forging and equipping, Workshop refining, Alchemy tonics.
- Shop with in-game currencies only: daily offers, material packs (Gold) and Gem offers (Stones, chest, Gold). Each offer has a daily limit that resets at midnight UTC; nothing in the shop revives heroes or protects from permadeath.
- Mission end: one silent "Eroe perduto" card per fallen hero, then a Stage Clear screen with a 3-star grade (victory, nobody fell, nobody under 30% HP), rewards, survivors and the floor unlocked, or a failure summary.
- Emergency recruit: a free 1★ every 30 minutes when fewer than five heroes are alive.
- Bonds between heroes (see `GAME_SYSTEMS.md`): grow on missions, training and rest; change attack and courage in battle; a fallen friend causes grief or fury and costs morale.

## Historical web code
`core.js`, `combat.js`, `app.js`, `index.html`, `styles.css`, `server.js` are the old web prototype. Not active; reference only.

## Save compatibility
Saves from v3 migrate to v4: Warehouse and Alchemy become built (level 1) if they were not, and the graphics quality defaults to "high". Saves from v2 migrate automatically to v3 first: development mode is switched off, old facility keys are mapped (Training Center → training, Lodging → dormitory, Synthesis Chamber → merging), facilities not allowed at Base Lv.1 return to "to be built", string injuries become timed injuries.
