# ART_DIRECTION.md

## Visual target
Riftward should communicate an original anime-isekai fantasy identity with readable game-space composition and strong visual progression.

## Rendering style
- Real-time 3D, procedural low-poly geometry with soft colours, Lambert shading and soft blob shadows (no dynamic shadow maps, so the look is identical on every GPU).
- Chibi heroes with big heads and big eyes; hair, eyes, skin and outfit derive deterministically from the hero id, and the 2D UI portraits use the same colours.
- UI: ivory panels with gold borders and navy headers, teal/sky/gold/violet accents, Fredoka for titles and Nunito for text (both SIL OFL, licences in `godot/assets/fonts`).

## Hub direction
The base should feel:
- compact and coherent;
- bright and inviting rather than grim;
- surrounded by vegetation, trees, paths, and environmental detail;
- clearly divided into functional areas without excessive fencing;
- populated by visible heroes who move and perform activities;
- physically believable as a place that grows over time.

Avoid:
- generic dark-dungeon presentation;
- oversized mega-castle silhouettes at early levels;
- facilities represented only as abstract cards when a physical world representation is expected;
- showing unavailable buildings as fully constructed locked structures unless explicitly requested;
- copying exact compositions, architecture, UI, symbols, or assets from reference IP.

## Facility progression
Visual upgrades should be obvious.
A strong default language is:
- Level 1: modest single-story/simple structure;
- later levels: additional floors/volume, richer materials, stronger magical effects, more props, more activity, more architectural detail.

Do not treat this as a rigid rule if another visual solution communicates progression better, but upgrades must remain visibly legible.

## Specific Level 1 notes
- Training Center: slightly raised/elevated.
- Lodging: simple and modest, but believable for roughly five heroes.
- Mission Gate: large ring portal on its own floating rock, linked to the island by a stone bridge.
- Merging Center: enclosed dome-like building, blue magical glow, available at Level 1.
- Workshop and Armory: absent physically until unlocked/built.
- Central square/plaza: open public space, not a facility building. The floating Nexus crystal in its centre is a clickable monument (summon and base expansion).
- Construction sites (wooden frame, planks, sign) appear only when a facility is unlocked but not built yet.

## UI relationship
UI should support the world rather than replace it. Clicking a physical facility may open contextual panels, but the player's first mental model should be “I am interacting with a place in my base.”
