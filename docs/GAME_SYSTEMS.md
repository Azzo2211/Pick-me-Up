# GAME_SYSTEMS.md

## Purpose
This file records the core gameplay rules Agent A should preserve unless the user explicitly changes them.

## Core loop
Master preparation → party formation → mission deployment → autonomous real-time combat → outcome/consequences → roster/base progression.

## Party and combat
- Party size: 5.
- Formation: 2 Front / 2 Mid / 1 Rear.
- Simulation target: 20 ticks/s.
- Hero Utility AI decisions: 5 Hz.
- The player issues limited macro orders rather than directly controlling individual hero skills.
- Current macro orders include posture, high-threat focus, protect rear, all-out, extraction.

## Heroes
Current MVP roles:
- Guardian
- Vanguard
- Lancer
- Ranger
- Mage
- Support

Heroes are persistent individuals with identity/seed, role, personality, potential/growth, skills, equipment, morale, fatigue, relationships, wounds, and memories/events.

## Progression and rarity
Modeled rarity/level caps:
- 1★ → Lv.10
- 2★ → Lv.20
- 3★ → Lv.30
- 4★ → Lv.50
- 5★ → Lv.70
- 6★ → Lv.99
- 7★ → Lv.120

The current standard acquisition space is early/mid-game focused; higher rarity/endgame systems should not be casually exposed merely because data structures exist.

## Failure and persistence
- Permadeath is active.
- No paid resurrection.
- Retrying a floor does not reroll the stage.
- Death, tombstones/memorial state, attempts, rewards, wounds, morale, fatigue, and persistent consequences are part of the game's identity.

## Missions
The current vertical slice contains five playable mission/floor archetypes:
- Subjugation
- Survival
- Exploration
- Defense
- Boss

The architecture may model a much larger tower, but Agent A should distinguish between implemented slice content and roadmap/data scaffolding.

## Economy and summon
Current known locked reference values from the existing specification:
- Normal summon: 10,000 Gold.
- High-grade summon: 500 Gems.
- No account energy system.
- Existing pity/rate behavior should not be changed accidentally.

## Facilities
Facilities are both gameplay systems and physical places in the Godot hub.
Important rule: **system availability and visual presence must stay coherent**. A facility that has not been built/unlocked should not appear as a finished physical building unless the user explicitly wants a construction/preview representation.

Newer base/hub decisions in `GAME_VISION.md` override older facility visualization assumptions.

## Determinism and save integrity
Existing deterministic world/stage behavior, HeroSeed uniqueness, irreversible results, and save integrity are regression-sensitive. Changes touching RNG, mission generation, hero creation, death, economy, progression, or persistence require extra caution and relevant tests.
