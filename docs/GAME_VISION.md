# GAME_VISION.md

## Product vision
**Riftward: The Last Ascent** is an original autonomous squad-management roguelite with persistent heroes, indirect Master control, irreversible consequences, facility progression, and a physical base that grows alongside the player's account.

The intended emotional loop is:
**prepare → deploy → watch autonomous heroes act → intervene only at macro level → accept consequences → improve roster/base → climb again.**

## Non-negotiable identity
- The player is a **Master/manager**, not an action-RPG character directly controlling every hero.
- Heroes must feel like individuals with roles, personalities, growth, fatigue, morale, relationships, and risk.
- Missions should create tension because losses matter. Permadeath is part of the identity.
- The base is a real visual place populated by heroes, not merely a list of menu buttons.
- Progression should be readable visually: stronger facilities become larger, richer, and more developed.
- The game may draw inspiration from the systemic feeling of “Pick Me Up” style fiction, but must remain original in names, world, characters, UI, assets, layouts, dialogue, and presentation.

## Current product direction
The Godot build is the main product direction. The base is a real-time 3D place (semi-realistic, mature anime-isekai dark fantasy at dusk) rendered behind a dark ornate HUD; building interfaces open as side panels over the base. The older web implementation is only a historical systems reference.

## Base / hub vision
The early base should feel like a compact, lived-in fantasy hamlet (warm dusk light, rich colours, never childish) rather than a mega-castle or dark dungeon.

Key principles:
- coherent physical hub;
- heroes visibly move through and use facilities;
- more vegetation, trees, paths, and environmental life;
- warm, rich dusk palette rather than oppressive dark-fantasy architecture or toy-like pastels;
- facilities appear physically only after they are unlocked/built;
- level upgrades should visibly increase structure size/detail, commonly by adding floors/stories or equivalent architectural growth;
- the central square is an open plaza, not a separate building/facility.

### Level 1 base decisions currently authoritative
- Training Center exists and is slightly elevated (raised stone platform with stairs, dummies, target, weapon rack).
- Dormitory/Lodging exists, simple but large enough to plausibly host about five heroes.
- Mission Gate exists, large, on its own floating rock, physically connected to the island by a stone bridge.
- Merging Center exists at Level 1; it is enclosed, dome-shaped with blue magical light, no fences around it.
- The central plaza is open space. The Nexus crystal floating in its centre is the access point for summoning and for expanding the base; it is a monument, not a building.
- Workshop, Armory, Warehouse and Alchemy are not physically present at Level 1.
- Unknown/unbuilt facilities are not shown. When a base level unlocks a facility, a small construction site appears in its spot; the building appears only after it is built.

### Growth rules
- Building level N = N storeys (or an equivalent architectural growth for non-house shapes, e.g. the training pavilion and the gate rings).
- Facility level can never exceed the base level.
- Each base level also improves the whole area: Lv.2 paved plaza, lamp posts, stone gatehouse; Lv.3 cobbled streets, stone wall, banners, fountain; Lv.4 wall towers with rune lights, statues; Lv.5 floating lanterns and an aurora.

These decisions override older hub code or documents when they conflict.

## Experience target
The player should increasingly feel that they are responsible for a living organization rather than manipulating spreadsheet units. The base, roster, missions, progression, and losses should reinforce one another.
