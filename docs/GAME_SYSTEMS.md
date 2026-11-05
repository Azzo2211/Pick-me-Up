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

### Tower difficulty: tiers of 5 floors and the Guardian Trial
Owner decision (2026-11-05, issue #13): climbing must be **very hard**, and difficulty must jump every 5 floors with a special mission.
- The Tower is split into **tiers of 5 floors** (1–5, 6–10, …). Enemy strength = `TOWER_TIER_POWER[tier] × (1 + 0.03 × floor-in-tier)` (`game_state.gd`): almost flat inside a tier, a clear **step up at every new tier** (+84% after floor 5, then +10–23% per tier up to floor 50, +5% per tier after that). Life grows as strength^0.85, attack as strength, defense as strength^0.5, so timed missions stay possible while the danger for heroes keeps rising.
- The 5th floor of every tier is the **Guardian Trial** (Prova del Guardiano), a special mission: a named guardian that **enrages at half life** (+30% attack, faster attacks and ground slams), **elite champions** (brutes with ×2.4 life, ×1.35 attack, bigger) arriving after 30 s (1 at tiers 1–2, then one more every two tiers, max 5), and **special rules** drawn from the world seed: 1 rule in tiers 1–2, 2 up to tier 6, then 3. Rules: Furia (+25% enemy attack), Corazza (+60% enemy defense), Orda (+50% enemies per wave), Passo rapido (faster enemies, faster attacks), Carne del Rift (enemies regenerate 1% life/s), Nebbia (−15 hero accuracy), Ferite profonde (heals halved). Because of all this the base strength of a Trial is scaled by `TOWER_TRIAL_POWER[tier]` (1.02 → 0.46).
- Trial rewards: Gold and XP ×1.6, Gems ×2 on first clear, Stones as before.
- The map's **Threat** follows the enemy strength; a Trial shows a higher Threat than the floors before it.
- Floor 1 is the gentlest fight (3 raiders, 2 hounds): an untrained starting squad wins it, usually without losses.
- Saves from before this change: 5th floors not yet cleared become Trials on load.

**Reference squad** (what a player usually has when reaching the first floor of a tier; `tests/tower_curve_runner.gd` simulates it to tune the two tables):

| Tier (floors) | Squad | Level | Gear |
|---|---|---|---|
| 1 (1–5) | 4×1★, 1×2★ | 5 | D |
| 2 (6–10) | 1★–2★ | 14 | D |
| 3 (11–15) | 2★–3★ | 22 | C |
| 4 (16–20) | 3★ | 29 | C |
| 5 (21–25) | 3★–4★ | 36 | B |
| 6 (26–30) | 4★ | 44 | B |
| 7–9 (31–45) | 4★–5★ | 52–68 | A |
| 10–13 (46–65) | 5★–6★ | 74–92 | S |
| 14–20 (66–100) | 6★–7★ | 98–120 | S |

Measured with the simulation (6 battles per floor, 2026-11-05): with the reference squad the normal floors of a tier are won from 0 to 6 times out of 6 depending on the mission type, almost always with heroes lost; the Trial is won 0–2 times out of 6 by the reference squad and 3–5 times out of 6 by the squad of the **next** tier. The last floors (91–100) are hard even for a full 7★ Lv.120 squad.

These are the **currently implemented contents**, not the final scope of the game. Riftward is intended to continue expanding with more floors, mission types, systems and content while preserving the core identity and progression logic.

## Economy and summon
Locked reference values:
- Normal summon: 10,000 Gold — 1★ 78% · 2★ 19% · 3★ 3%.
- High-grade summon: 500 Gems — 3★ 93.5% · 4★ 5.5% · 5★ 1% (soft pity from pull 70, hard pity at 100).
- Transcendent summon: 3,000 Gems, unlocked after Floor 20 — 5★ 98% · 6★ 1.8% · 7★ 0.2%.
- No account energy system. Real economy by default; development mode is optional (Settings).
- Starting resources: 60,000 Gold, 1,500 Gems, 1 Stone.
- Shop (`GameState.SHOP_OFFERS`): only Gold and Gems, prices and quantities always shown, daily purchase limits (reset at midnight UTC). Purchases are refused when the Warehouse cap for that material is full. No item may undo risk (no revive, no death protection).

## Base, time and progression
- Base level 1–5 (Nexus crystal). Requirements: Lv.2 Floor 3 + 40k Gold, Lv.3 Floor 6 + 120k, Lv.4 Floor 10 + 300k, Lv.5 Floor 15 + 700k.
- Facility level ≤ base level. Upgrading a facility adds one storey.
- Training: slots = 2 + level; XP accrues over real time (offline capped at 8 h); fatigue grows; stops at level cap or fatigue 90.
- Dormitory: beds = 5 + 2 × (level − 1); restores fatigue and morale, heals injuries over time; heroes leave when fully recovered.
- XP curve: `30 + 14 × level^1.45`; level-ups add stats from the hidden growth value.
- Fusion: three heroes of the same rarity, 1★–4★ → the core gains one star (so fusion reaches 5★ at most). 6★/7★ only through Transcendent summon or promotion.
- Promotion at level cap with Stones: 1★→2★ 1, 2★→3★ 2, 3★→4★ 3, 4★→5★ 5, 5★→6★ 12 (Floor 30), 6★→7★ 30 (Floor 60).

## Facilities
Facilities are both gameplay systems and physical places in the Godot hub.
Important rule: **system availability and visual presence must stay coherent**. A facility that has not been built/unlocked should not appear as a finished physical building unless the user explicitly wants a construction/preview representation.

Newer base/hub decisions in `GAME_VISION.md` override older facility visualization assumptions.

## Determinism and save integrity
Existing deterministic world/stage behavior, HeroSeed uniqueness, irreversible results, and save integrity are regression-sensitive. Changes touching RNG, mission generation, hero creation, death, economy, progression, or persistence require extra caution and relevant tests.

## Active implementation rule
All new gameplay development targets Godot. JavaScript/web files in the repository are historical reference material only and must not be treated as a second active implementation.
