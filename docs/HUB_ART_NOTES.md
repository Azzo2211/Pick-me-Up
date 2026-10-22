# Level 1 HUB art integration

## Current asset

- File: `godot/assets/backgrounds/base_level_1_integrated.png`.
- Produced with the built-in ImageGen tool, editing the existing project background.
- Output: 1939×811 PNG, displayed in Godot's 1920×804 terrain coordinate space.
- Existing backgrounds and detached summoning overlays are retained for history; the live scene only renders the integrated background.
- Facility labels are authored in Godot and are deliberately absent from the bitmap.

## Accepted changes

The summoning circle is a low courtyard on the island. Its paving joins the public square and the path around the Merging Center. The southern road closes into that circulation instead of leaving the cliff. The public square is open; Workshop and Armory are not built at Level 1.

Gameplay IDs, save keys, summon rates, merge rules and economy are unchanged. Base services remain available from Warehouse.

## Generation prompt

Use case: precise-object-edit. Asset: final unified panoramic game HUB background for the original game Riftward, to be displayed at 1920x804 beneath the game HUD.

The supplied image is the exact edit target. Edit the terrain and architecture coherently in a single illustration. Keep its panoramic aspect ratio, full island in frame, bright daytime painterly isometric art style, blue sky and clouds. Preserve the dormitory at upper-left, elevated training arena at upper-middle, large blue mission gate at upper-right, wooden storage at left-middle, and enclosed blue-domed merging building at lower-middle. Retain their exact positions, silhouettes, scale, lighting and the surrounding existing paths as closely as possible.

REQUIRED EDITS:

1. Remove ALL black labels and ALL words/icons/text on the map. Reconstruct the natural sky, foliage or cobblestones behind those labels. Names will be actual UI text in the game; the image must contain zero lettering.
2. Remove only the big blue crystal and its pedestal in the CENTRAL public square. Restore a plain open circular paved social plaza with a subtle stone mosaic at ground level. It is public space, not an extra building.
3. Remove the small purple-roofed alchemy/workshop building at right-middle, its bottles and chimney. Its space becomes a beautifully integrated LOW CIRCULAR SUMMONING COURTYARD directly on the island terrain, about the same footprint as that former building. A flat violet-blue engraved sigil in the floor, warm pale stone, up to four tiny knee-high rune posts, moss and plants. No tower, no arch, no floating crystal, no roof. The summoning courtyard must be supported by the same solid rocky island, and connected smoothly to the existing central ring-road with continuous matching cobblestone paving and a shared ground level. No detached floating annex, no texture pasted over existing roads, no visible seam, no overlaps.
4. Fix the bottom path directly in front of the domed merging building: make the path curve rightwards to JOIN the summoning courtyard access path on the island. At the southern cliff edge replace the old dead-end vertical strip with grass, bushes, flowers and a short natural low stone parapet. Every visible road has a clear destination or closes into a loop. No road ending in empty sky.

Avoid extra buildings, extra platforms, huge castles, new labels, UI, borders, black bars, characters, watermarks. Only the required changes; preserve the other existing structures and their locations.

## Verification

Use `tests/base_hub_runner.gd` with `-- --test-mode` for UI access, path clearance and label separation. The visual runner accepts `--hub-only` for the general view, contextual panels and a simulated minute of hero activity; `--resized-hub` saves a separate capture for a taller maximized window.

Verified in Godot 4.7.1: 39 HUB checks, 10 gameplay checks and all 11 UI screens passed. Real renderer captures were inspected at 1920×890 and 1908×990. Test mode isolates the player's save. Headless runs in the sandbox print a Windows certificate-store warning at startup; the suites complete successfully, and the windowed rendering runs do not produce that warning.

The background remains Level 1 art after facility upgrades; the permanent signs reflect the saved level. Separate visual upgrade tiers remain future work, not an implemented feature of this change.
