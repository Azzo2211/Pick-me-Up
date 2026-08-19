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
The Godot build is the main product direction. The older web implementation is useful as a systems reference and regression source, but should not dictate the visual or architectural future of the Godot version.

## Base / hub vision
The early base should feel like a compact, colorful anime-isekai fantasy settlement rather than a mega-castle or dark dungeon.

Key principles:
- coherent physical hub;
- heroes visibly move through and use facilities;
- more vegetation, trees, paths, and environmental life;
- bright fantasy palette rather than oppressive dark-fantasy architecture;
- facilities appear physically only after they are unlocked/built;
- level upgrades should visibly increase structure size/detail, commonly by adding floors/stories or equivalent architectural growth;
- the central square is an open plaza, not a separate building/facility.

### Level 1 base decisions currently authoritative
- Training Center exists and is slightly elevated.
- Dormitory/Lodging exists, simple but large enough to plausibly host about five heroes.
- Mission Gate exists, visually suspended/floating but physically connected to the base circulation.
- Merging Center exists at Level 1; it is enclosed/dome-like with blue magical light and is not shown as locked.
- Workshop is not yet physically present at Level 1.
- Armory is not yet physically present at Level 1.
- Unknown/unbuilt facilities should not be physically shown merely as locked placeholders.

These newer decisions override older hub code or documents when they conflict.

## Experience target
The player should increasingly feel that they are responsible for a living organization rather than manipulating spreadsheet units. The base, roster, missions, progression, and losses should reinforce one another.
