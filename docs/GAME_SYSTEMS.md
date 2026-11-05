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

### Difficoltà della Torre: scaglioni di 5 piani e Prova del Guardiano
Decisione del proprietario (2026-11-05, issue #13): salire deve essere **molto difficile**, e ogni 5 piani la difficoltà deve salire con una missione speciale.
- La Torre è divisa in **scaglioni di 5 piani** (1–5, 6–10, …). Forza dei nemici = `TOWER_TIER_POWER[scaglione] × (1 + 0,03 × piano dentro lo scaglione)` (`game_state.gd`): quasi piatta dentro lo scaglione, con un **gradino netto a ogni nuovo scaglione** (+84% dopo il Piano 5, poi +10–23% a scaglione fino al Piano 50, +5% a scaglione dopo). La vita cresce come forza^0,85, l'attacco come la forza, la difesa come forza^0,5: le missioni a tempo restano fattibili, mentre il pericolo per gli eroi continua a salire.
- Il 5° piano di ogni scaglione è la **Prova del Guardiano**, una missione speciale:
  - un guardiano con un nome proprio che **si infuria a metà vita** (+30% attacco, attacchi e colpi a terra più frequenti);
  - **campioni d'élite** (bruti con vita ×2,4, attacco ×1,35, più grandi) che arrivano dopo 30 secondi: 1 negli scaglioni 1–2, poi uno in più ogni due scaglioni, massimo 5;
  - **regole speciali** pescate dal seme del mondo: 1 regola negli scaglioni 1–2, 2 fino allo scaglione 6, poi 3. Regole: Furia (+25% attacco dei nemici), Corazza (+60% difesa dei nemici), Orda (+50% nemici per ondata), Passo rapido (nemici più veloci, attacchi più frequenti), Carne del Rift (i nemici rigenerano l'1% di vita al secondo), Nebbia (−15 precisione degli eroi), Ferite profonde (cure dimezzate).
  - Per tutto questo la forza di base di una prova è moltiplicata per `TOWER_TRIAL_POWER[scaglione]` (da 1,02 a 0,46).
- Ricompense della prova: Oro ed esperienza ×1,6, Gemme ×2 al primo completamento, Pietre come prima.
- La **Minaccia** della mappa segue la forza dei nemici; una prova mostra una Minaccia più alta dei piani prima.
- Il Piano 1 è lo scontro più leggero (3 predoni, 2 segugi): la squadra di partenza lo vince anche senza allenamento, di solito senza caduti.
- Salvataggi precedenti a questa modifica: i quinti piani non ancora superati diventano prove al caricamento.

**Squadra di riferimento** (quella che un giocatore ha di solito quando arriva al primo piano di uno scaglione; `tests/tower_curve_runner.gd` la simula per tarare le due tabelle):

| Scaglione (piani) | Squadra | Livello | Equipaggiamento |
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

Misurato con la simulazione (6 battaglie per piano, 2026-11-05): con la squadra di riferimento i piani normali di uno scaglione si vincono da 0 a 6 volte su 6 a seconda del tipo di missione, quasi sempre con caduti; la prova la vince 0–2 volte su 6 la squadra di riferimento e 3–5 volte su 6 la squadra dello scaglione **successivo**. Gli ultimi piani (91–100) sono duri anche per una squadra completa di 7★ al Lv.120.

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
