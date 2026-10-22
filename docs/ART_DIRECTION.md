# ART_DIRECTION.md

## Visual target
Riftward is a mature anime-isekai dark fantasy, inspired by the feeling of Korean webtoons/manhwa about summoned heroes and towers, never copying them. It must not read as a children's game: no chibi proportions, no candy pastels, no toy-like UI. It must not read as grimdark either: warm light, rich dusk colours and lived-in places.

## Rendering style (3D)
- Real-time 3D generated in code, semi-realistic low-poly: procedural shaders give every surface a real material (stone blocks with mortar and moss, weathered plaster, timber grain, slate/shingle/thatch roofs, cobbles, dirt, grass, rock strata). UVs are in world units so patterns keep their scale.
- Lighting: golden-hour dusk by default (warm low sun, cool fill, indigo sky with stars, banked clouds), real directional shadows, depth and height fog, mist sea under the island, soft glow on emissive windows, lamps, runes and crystals. Players can switch the base to Day or Night in Settings.
- Characters have real human proportions (~1.8 m, 1 world unit = 2 m), role-specific clothing (plate and tabard, leather and pauldrons, hooded cloaks, long robes, capes from 4★), real weapons. Enemies: hooded raiders and archers, Rift wolves, ogre brutes, stone golem guardians with glowing runes.
- Performance: each building is one batched mesh (one surface per material); trees, bushes, rocks and grass use MultiMesh; few real lights, the rest are emissive surfaces and additive light pools on the ground.

## UI style (2D)
- Dark ornate panels (near-black violet with bronze double borders and corner ornaments), "system" windows in deep violet with lilac brackets for messages, toasts and summons.
- Fonts: Cinzel for titles, Alegreya SC for headings, Alegreya for text (all SIL OFL, licences in `godot/assets/fonts`).
- Heroes are shown as bronze-framed cards (emblem medallion, half-bust portrait, rarity stars, name plate); fallen heroes keep a dimmed card with "Caduto al Piano N".
- Portraits are drawn in code as adult manhwa-style busts; colours come from the same deterministic appearance as the 3D model.

## Hub direction
The base is a walled hamlet on a floating island in the Rift:
- an open plaza with the Nexus crystal on a stone pedestal at the centre;
- a ring street around the plaza, buildings facing the street, short paved aprons to each door;
- a town wall that grows with the base, forest and meadows between the wall and the cliff edge, a pond whose stream falls off the island;
- the Mission Gate on its own floating rock, a monumental stone arch with a dark swirling rift, reached by a chained stone bridge;
- heroes and a few villagers visibly living there.

Avoid:
- chibi heroes, pastel candy palettes, cartoon outlines;
- oversized mega-castle silhouettes at early levels;
- facilities represented only as abstract cards when a physical world representation is expected;
- showing unavailable buildings as fully constructed locked structures;
- copying exact compositions, architecture, UI, symbols, names or assets from reference IP.

## Facility progression
- Building level N = N storeys (or an equivalent growth: the training yard's barracks, the rotunda's drums, the gate's rings and floating stones).
- Level 1 buildings are modest; higher levels add floors, chimneys, jetties, lamps and magical details.

## Base level progression (whole area)
| Base | Streets | Wall | Details |
|---|---|---|---|
| 1 | narrow dirt tracks, earthen plaza with a stone ring | wooden palisade with a timber gate | torches, well, vegetable plots, thatch roofs |
| 2 | paved plaza and spokes | palisade with a stone gatehouse | iron lamp posts, market stall, shingle roofs |
| 3 | every street cobbled | low stone curtain wall | banners, three stalls, fountain, slate roofs |
| 4 | — | corner towers with blue rune lights | statues along the gate road |
| 5 | — | gilded banners | floating lanterns, aurora in the sky |

## Specific Level 1 notes
- Training Center: raised stone yard with stairs, dummies, weapon racks, target and a small barracks.
- Dormitory: timber-framed longhouse for about five heroes, benches by the door for the injured.
- Merging Center: enclosed classical rotunda, copper dome with a glass lantern, blue light from the windows, no fences.
- Mission Gate: present and large, suspended on its own rock, connected by the bridge.
- Workshop, Armory, Warehouse, Alchemy: absent until unlocked; then a construction site; then the building.
- Central plaza: open public space, not a facility. The crystal is a clickable monument (summon and base expansion).

## UI relationship
UI supports the world rather than replacing it. Clicking a physical facility opens a side panel over the base; the player's first mental model is "I am interacting with a place in my base".
