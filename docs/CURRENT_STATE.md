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
| Neon "System" theme, widgets, icons (Oxanium/Exo 2 fonts) | `godot/scripts/ui/ui_kit.gd`, `ornate_style.gd`, `ornate_divider.gd`, `ui_icon.gd` |
| Hero cards (summons, roster, memorial, dossier) | `godot/scripts/ui/hero_card.gd` |
| Summon event (full-screen rift, colour shift, card reveal) | `godot/scripts/ui/summon_event.gd` |
| Tower map (10 floors per page, zig-zag path, boss diamonds) | `godot/scripts/ui/tower_map.gd` |
| Mission end: Hero Lost cards, then Stage Clear / failure summary | `godot/scripts/ui/mission_result_screen.gd` |
| Loading screen (startup and before each mission) | `godot/scripts/ui/loading_screen.gd` |
| Hero portraits: photo of the hero's 3D character, procedural drawing as fallback (headless) | `godot/scripts/hero_portrait.gd`, `godot/scripts/ui/portrait_studio.gd` |
| Modular hero look from the user's character sheet (archetype, 3 faces, 4 hairstyles, body, age) | `godot/scripts/characters/hero_look.gd` |
| Anime shading: two-tone toon light, outline, drawn face | `godot/scripts/hub3d/shaders/toon.gdshader(inc)`, `outline.gdshader`, `face.gdshader` |
| 3D base: island, walls, streets, plaza, forest, navigation, labels | `godot/scripts/hub3d/hub_world.gd` |
| Camera, picking, hover/click | `godot/scripts/hub3d/hub_view.gd` |
| Buildings (level N = N storeys, batched meshes) | `godot/scripts/hub3d/building_model.gd`, `portal.gdshader` |
| People living in the base (heroes and villagers) | `godot/scripts/hub3d/hub_agent.gd` |
| Human characters and monsters (shared with battle) | `godot/scripts/hub3d/character_model.gd` |
| 3D motion clips (40 original clips, 19-bone rig) mapped onto the character joints | `godot/scripts/hub3d/motion_library.gd`, `godot/assets/animations/riftward_original_motions.glb` |
| Character generator (16 look categories, hair/eye colours, red eyes 1 in 100,000) | `godot/scripts/characters/character_generator.gd` |
| Preview scenes (F6 in the editor, not part of the game) | `godot/CharacterPreview.tscn`, `godot/RiftwardMotionPreview.tscn` |
| Mesh batching, materials, light presets, trees and rocks | `mesh_builder.gd`, `world_materials.gd`, `world_look.gd`, `nature_kit.gd`, `shaders/*.gdshader` |
| Mission / battle (biome arenas, HUD) | `godot/scripts/battle/battle_scene.gd` |

### Tests
Run from the repository root (Godot executable on PATH or full path):

```text
godot --headless --path godot -s res://tests/test_runner.gd -- --test-mode          # 31 rule tests
godot --headless --path godot -s res://tests/ui_smoke_runner.gd -- --test-mode      # 29 UI checks incl. a full mission
godot --headless --path godot -s res://tests/balance_probe_runner.gd -- --test-mode # balance table (optional --levels= --floors=)
godot --path godot -s res://tests/visual_capture_runner.gd -- --test-mode           # UI screenshots → godot/tests/captures/
godot --path godot -s res://tests/hub_preview_runner.gd -- --test-mode --base5      # base previews (--base2/3/5, --light=day|night)
godot --path godot -s res://tests/battle_preview_runner.gd -- --test-mode           # battle screenshots
godot --path godot -s res://tests/character_probe_runner.gd -- --test-mode          # character line-up
godot --path godot -s res://tests/look_sheet_runner.gd -- --test-mode --out DIR    # character sheet tiles: 4 archetypes front/side/back, 3 faces, 4 hairstyles
godot --path godot -s res://tests/portrait_preview_runner.gd -- --test-mode         # cards and portraits with the 3D photos
```

`tests/captures/` contains `.gdignore`, so screenshots are not imported as game assets.

## What the player sees now
- The home screen **is the base**: a walled hamlet on a floating island at dusk. Open plaza with the Nexus crystal, ring street, raised Training yard, timber Dormitory, rotunda Merging Center with a copper dome and blue light, forest, pond and waterfall, and the Mission Gate on its own rock reached by a chained bridge.
- The town grows with the base level: palisade → stone wall → towers; dirt tracks → cobbles; torches → lamp posts, market stalls, fountain, statues, floating lanterns.
- Tapping a building moves the camera to it and opens its panel on the right; the base stays visible behind. Labels never overlap; status lines appear on hover; badges mark only real news (new floor at the Gate, idle trainees, tired heroes, promotions, affordable plots).
- Heroes and villagers walk the streets: trainees spar on the yard, resting heroes enter the Dormitory, injured heroes sit on its benches, the squad waits by the gate road. Tapping a hero opens their dossier.
- Bottom dock: Heroes (full roster with role / stars / state filters and sorting), Squad (drag heroes onto Front / Mid / Rear slots), Tower (map of the floors with risk, squad power and rewards), Shop, Journal, Settings.
- A loading screen ("connessione al Nexus") opens the game; another one ("apertura del varco") covers the jump into a mission.
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
- Shop with in-game currencies only: daily offers, material packs (Gold) and Gem offers (Stones, chest, Gold). Each offer has a daily limit that resets at midnight UTC; nothing in the shop revives heroes or protects from permadeath.
- 1★ and 2★ heroes are commoners summoned at random with a job (`COMMONER_JOBS` in `game_state.gd`: farmer, smith, merchant, archivist, town guard…). Their stats come from the job. They recommend a class that suits their stats and job (`class_advice`, with a second choice and an in-character line) but the player chooses it in the dossier (`choose_class`): the class brings its skill and starter weapons. Until then they fight with their job tool as the recommended class. The starter squad and older saves count as having chosen. From 3★ the Nexus gives a class.
- Hero looks follow the user's character sheet (Guard, Merchant, Scholar, Villager): `hero.look` = archetype, face (3 per archetype; the rarer the hero, the likelier the handsome face), hairstyle (4 per archetype and sex, 13 meshes), body (slim, average, athletic, muscular, chubby) and age (greying hair, wrinkles). Commoners take the archetype of their job, others of their class (Ranger dresses as a hunter). Clothes change when a commoner picks a class; face and hair stay. Colours come from the character generator, with the category chosen by job or class.
- Cards show a photo of the same 3D character (`portrait_studio.gd`): a bust shot in its own viewport with a transparent background, cached in memory and in `user://portraits3d`, retaken only when the look, class or rarity changes. Without a display (headless tests) the old drawn portrait is used.
- Characters use a two-tone toon shader with a pixel-width outline (inverted hull); the face is drawn by a shader on the base head (anime eyes with gradient iris and highlights, brows, mouth, blush, stubble, age lines). The Compatibility renderer lights in sRGB space, so the toon shaders use vertex colours as they are.
- Hero looks come from the character generator (saved as `appearance` and `category` on each hero; older saves get one on load): hair, eye and skin colour, beard, scars, freckles, glasses, eye size, height and build. Red eyes are 1 in 100,000. Look never affects role, stars or stats.
- Humans in the base and in battle play the motion clips for idle, walk, talk, cheer, death, bow shots and spells, with short blends between them. Sitting, resting, training and sword/spear swings stay procedural. If the GLB is missing or not imported yet, every pose falls back to procedural.
- Mission end: one silent "Eroe perduto" card per fallen hero, then a Stage Clear screen with a 3-star grade (victory, nobody fell, nobody under 30% HP), rewards, survivors and the floor unlocked, or a failure summary.
- Emergency recruit: a free 1★ every 30 minutes when fewer than five heroes are alive.

## Historical web code
`core.js`, `combat.js`, `app.js`, `index.html`, `styles.css`, `server.js` are the old web prototype. Not active; reference only.

## Save compatibility
Saves from v2 migrate automatically to v3: development mode is switched off, old facility keys are mapped (Training Center → training, Lodging → dormitory, Synthesis Chamber → merging), facilities not allowed at Base Lv.1 return to "to be built", string injuries become timed injuries.
