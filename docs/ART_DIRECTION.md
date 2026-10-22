# ART_DIRECTION.md

## Visual target
Riftward should communicate an original anime-isekai fantasy identity with readable game-space composition and strong visual progression.

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
- Mission Gate: suspended/floating fantasy element, yet linked physically to the base circulation.
- Merging Center: enclosed dome-like building, blue magical glow, available at Level 1.
- Workshop and Armory: absent physically until unlocked/built.
- Central square/plaza: open public space, not a labeled facility building.

## UI relationship
UI should support the world rather than replace it. Clicking a physical facility may open contextual panels, but the player's first mental model should be “I am interacting with a place in my base.”

### Hub integration and labels
- The summoning area is a low courtyard on the main island, with a flat ritual sigil and paths connecting it to the public square and Merging Center.
- Use a unified terrain illustration for the courtyard and its access paths; pasted extensions with visible seams are not acceptable.
- Paths must join another path, reach an entrance, or end at a clearly enclosed destination. They must not continue into empty sky.
- Facility names are permanent Godot UI signs, positioned away from entrances and circulation. Keep them legible and update their level from runtime data. Keep the public square unlabelled.
- Facility hit areas remain invisible during hover and selection. No contour, ring, or repeated name is added after clicking.
