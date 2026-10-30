# GAME_SYSTEMS.md

## Purpose
This file records the core gameplay rules that any developer or coding agent should preserve unless the user explicitly changes them.

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
Current implemented roles:
- Guardian
- Vanguard
- Lancer
- Ranger
- Mage
- Support

Heroes are persistent individuals with identity/seed, role, personality, potential/growth, skills, equipment, morale, fatigue, relationships, wounds, and memories/events.

### Bonds (relationships)
- Every pair of heroes has a bond from −100 to +100 (`data.relationships`, key `idA::idB`). The starting value is deterministic from the world seed (−8…+26); *Socievole* adds 6, *Solitario* removes 6.
- Labels: Rival ≤ −25, Acquaintance, Companion ≥ 15, Friend ≥ 40, Trusted friend ≥ 65 (shown in the hero dossier, "LEGAMI").
- Growth: surviving a mission together +3 (victory) / +1.5 (defeat); training together +0.05 per minute; resting together +0.03 per minute. *Socievole* grows bonds ×1.35, *Solitario* ×0.65.
- In battle: each trusted friend in the squad gives +5% attack and +8 courage, each friend +2% and +4 (max two of each); each rival −8 courage. When an ally falls, trusted friends react with fury (attack ×1.12, +10 courage), friends lose 12 courage.
- After a mission, survivors who lost someone with bond ≥ 20 lose morale and keep a memory of it.
- In the base, heroes with free time walk to a friend who is also idle, and personality picks their haunts (*Testardo/Tenace* near the training yard, *Occhio clinico/Memoria lunga/Frugale* near alchemy, storage or workshop, *Socievole* in the plaza, *Solitario* along the outer ring).

## Progression and rarity
Modeled rarity/level caps:
- 1★ → Lv.10
- 2★ → Lv.20
- 3★ → Lv.30
- 4★ → Lv.50
- 5★ → Lv.70
- 6★ → Lv.99
- 7★ → Lv.120

Higher-rarity and endgame systems can be expanded progressively as the full game develops. Do not expose unfinished systems merely because data structures already exist.

## Failure and persistence
- Permadeath is active.
- No paid resurrection.
- Retrying a floor does not reroll the stage.
- Death, tombstones/memorial state, attempts, rewards, wounds, morale, fatigue, and persistent consequences are part of the game's identity.

## Missions and tower
Mission archetypes: Subjugation, Survival, Exploration, Defense and Boss. Floors 1–5 are hand-made; floors 6–100 are generated deterministically from the world seed (boss every 5 floors). Rewards: Gold and XP every clear (reduced on retries), Gems on first clear, Stones on first clear of boss floors, materials as loot. Heroes below 30% HP at the end get a timed injury.

These are the **currently implemented contents**, not the final scope of the game. Riftward is intended to continue expanding with more floors, mission types, systems and content while preserving the core identity and progression logic.

## Economy and summon
Locked reference values:
- Normal summon: 10,000 Gold — 1★ 78% · 2★ 19% · 3★ 3%.
- High-grade summon: 500 Gems — 3★ 93.5% · 4★ 5.5% · 5★ 1% (soft pity from pull 70, hard pity at 100).
- Transcendent summon: 3,000 Gems, unlocked after Floor 20 — 5★ 98% · 6★ 1.8% · 7★ 0.2%.
- No account energy system. Real economy by default; development mode is optional (Settings). Settings also hold the base light (dusk/day/night) and the graphics quality (high/medium/low).
- Starting resources: 60,000 Gold, 1,500 Gems, 1 Stone.
- Shop (`GameState.SHOP_OFFERS`): only Gold and Gems, prices and quantities always shown, daily purchase limits (reset at midnight UTC). Purchases are refused when the Warehouse cap for that material is full. No item may undo risk (no revive, no death protection).

## Base, time and progression
- Base level 1–5 (Nexus crystal). Requirements: Lv.2 Floor 3 + 40k Gold, Lv.3 Floor 6 + 120k, Lv.4 Floor 10 + 300k, Lv.5 Floor 15 + 700k.
- Facility level ≤ base level. Upgrading a facility adds one storey.
- Training: slots = 2 + level; XP accrues over real time (offline capped at 8 h); fatigue grows; stops at level cap or fatigue 90.
- Dormitory: beds = 5 + 2 × (level − 1); restores fatigue and morale, heals injuries over time; heroes leave when fully recovered.
- XP curve: `30 + 14 × level^1.45`; level-ups add stats from the hidden growth value.
- Fusion: three same-rarity heroes (≤4★) → core gains one star. 6★/7★ only through Transcendent summon or promotion.
- Promotion at level cap with Stones: 1★→2★ 1, 2★→3★ 2, 3★→4★ 3, 4★→5★ 5, 5★→6★ 12 (Floor 30), 6★→7★ 30 (Floor 60).

## Facilities
Facilities are both gameplay systems and physical places in the Godot hub.

Availability: Training, Dormitory, Merging, Gate, **Warehouse and Alchemy** are built at Base Lv.1 (user decision, 2026-10-29); Armory unlocks at Base Lv.2 and Workshop at Base Lv.3, then must be built. Building badges flag real news only: idle trainees, tired heroes, a new floor at the Gate, gear waiting in storage for the Armory, a full Warehouse, injured heroes the Alchemy can treat.
Important rule: **system availability and visual presence must stay coherent**. A facility that has not been built/unlocked should not appear as a finished physical building unless the user explicitly wants a construction/preview representation.

Newer base/hub decisions in `GAME_VISION.md` override older facility visualization assumptions.

## Determinism and save integrity
Existing deterministic world/stage behavior, HeroSeed uniqueness, irreversible results, and save integrity are regression-sensitive. Changes touching RNG, mission generation, hero creation, death, economy, progression, or persistence require extra caution and relevant tests.

## Active implementation rule
All new gameplay development targets Godot. JavaScript/web files in the repository are historical reference material only and must not be treated as a second active implementation.
