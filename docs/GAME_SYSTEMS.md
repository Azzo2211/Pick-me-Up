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

- **Statistiche principali** (regola del proprietario, 2026-11-12): STR (forza), INT (intelligenza), HP (punti vita), DEX (destrezza). Nel salvataggio restano le chiavi di prima (`str`, `int`, `sta` = HP, `agi` = DEX); sigle e nomi in `GameState.STAT_LABELS`.
- **Abilità** (regola del proprietario, 2026-11-12; `GameState.SKILLS`): ogni eroe ha la **tecnica della sua classe** (sempre la prima, è il colpo speciale in battaglia) e da 0 a 3 **abilità particolari**, comuni o uniche. Alcuni eroi nascono senza: più la rarità è alta, più è facile averne (nessuna abilità comune: 1★ 75%, 2★ 60%, 3★ 40%, 4★ 25%, 5★ 15%, 6★ 10%, 7★ 5%; abilità unica: 3★ 2%, 4★ 6%, 5★ 25%, 6★ 45%, 7★ 70%), ma non è una regola fissa. Effetti veri: vita, attacco, difesa in percentuale; precisione, schivata, critico in punti; cure più forti (solo Supporti); paura che passa prima (Disciplina da Campo) o assente (Cuore d'acciaio). Livello 1–3: al Lv.2 l'effetto vale ×1,5, al Lv.3 ×2. Le abilità si ottengono alla nascita o con la Fusione (l'allenamento resta com'era, precisazione del proprietario). Gli eroi dei salvataggi vecchi tengono la Disciplina da Campo che avevano tutti.
- **Potenziale nascosto** (regola del proprietario, 2026-11-12): quanto in fretta un eroe impara e quanto può crescere (`potential`, `growth`) non è scritto da nessuna parte nel gioco, né nella scheda né nella valutazione del Sistema né nell'Addestramento (niente "esperienza al minuto"). Il giocatore lo scopre guardando come crescono. Si vede solo in modalità sviluppo con i valori nascosti accesi.

## Progression and rarity
Modeled rarity/level caps:
- 1★ → Lv.10
- 2★ → Lv.20
- 3★ → Lv.30
- 4★ → Lv.50
- 5★ → Lv.70
- 6★ → Lv.99
- 7★ → Lv.99

Livello massimo 99 per tutti (regola del proprietario, 2026-11-12; prima la 7★ arrivava al Lv.120). I salvataggi con eroi oltre il 99 vengono riportati al 99.

Higher-rarity and endgame systems can be expanded progressively as the full game develops. Do not expose unfinished systems merely because data structures already exist.

## Failure and persistence
- Permadeath is active.
- No paid resurrection.
- Retrying a floor does not reroll the stage.
- Death, tombstones/memorial state, attempts, rewards, wounds, morale, fatigue, and persistent consequences are part of the game's identity.

## Missions and tower
Mission archetypes: Subjugation (in gioco "Annientamento"), Survival, Exploration, Defense and Boss. Floors 1–5 are hand-made: **floors 1–4 are fairly easy annihilation missions** and floor 5 is the first Guardian, very hard even for 1★ heroes at Lv.8 (regola del proprietario, 2026-11-12; older saves rebuild floors 2–4 if not cleared yet); floors 6–100 are generated deterministically from the world seed (boss every 5 floors). Rewards: Gold, XP and Gems every clear (reduced on retries; Gems: 120+10×floor on first clear, 15+1.5×floor on replays, ×2 on Guardian floors), Stones on first clear of boss floors, materials as loot. Heroes below 30% HP at the end get a timed injury.

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
| 14 (66–70) | 6★–7★ | 98 | S |
| 15–20 (71–100) | 7★ | 99 (massimo) | S |

Misurato con la simulazione (6 battaglie per piano, 2026-11-05): con la squadra di riferimento i piani normali di uno scaglione si vincono da 0 a 6 volte su 6 a seconda del tipo di missione, quasi sempre con caduti; la prova la vince 0–2 volte su 6 la squadra di riferimento e 3–5 volte su 6 la squadra dello scaglione **successivo**.

**Da ritarare (2026-11-12):** la tabella era tarata con la 7★ fino al Lv.120. Con il massimo a 99 la squadra smette di salire di livello dal Piano 71 e gli scaglioni 15–20 sono troppo duri (simulazione: piani 76–100 vinti 0–1 volte su 4). Oltre il Lv.99 gli eroi cresceranno con la nuova Fusione (statistiche dall'eroe sacrificato); la curva degli ultimi scaglioni si ritara insieme a quella.

These are the **currently implemented contents**, not the final scope of the game. Riftward is intended to continue expanding with more floors, mission types, systems and content while preserving the core identity and progression logic.

## Economy and summon
Locked reference values:
- Normal summon: 10,000 Gold — 1★ 78% · 2★ 19% · 3★ 3%.
- High-grade summon: 500 Gems — 3★ 93.5% · 4★ 5.5% · 5★ 1% (soft pity from pull 70, hard pity at 100).
- Transcendent summon: 4,000 Gems, unlocked after Floor 20 — 4★ 78% · 5★ 20% · 6★ 1.8% · 7★ 0.2%. È l'unico modo di avere un eroe 7★.
- Materiali da costruzione e forgia (regola del proprietario, 2026-11-12): **Ferro (C)**, **Pelle (C)**, **Assi di legno (C)** (chiavi `ore`, `leather`, `wood`), più Erbe, Nuclei e Medicine.
- No account energy system. Real economy by default; development mode is optional (Settings).
- Starting resources: 60,000 Gold, 1,500 Gems, 1 Stone.
- Shop (`GameState.SHOP_OFFERS`): only Gold and Gems, prices and quantities always shown, daily purchase limits (reset at midnight UTC). Purchases are refused when the Warehouse cap for that material is full. No item may undo risk (no revive, no death protection).

## Base, time and progression
- **Stanchezza** (2026-11-08, `FATIGUE_LEVELS` in `game_state.gd`): Riposato 0–39 nessun malus; Stanco 40–69 attacco −10%, difesa −5%, precisione −5, passo −8%, attacchi +10% più lenti; Esausto 70–89 vita −10%, attacco −25%, difesa −15%, precisione −12, passo −20%, attacchi +25% più lenti; Sfinito 90+ vita −20%, attacco −40%, difesa −30%, precisione −20, passo −30%, attacchi +45% più lenti e **non può partire** per la Torre. I malus valgono in battaglia, nella potenza della squadra e nella scheda dell'eroe.
- **Livelli della base 1–10** (Cristallo del Nexus). Decisione del proprietario (2026-11-05, #16): con 100 piani nella Torre il massimo non può essere 5. Requisiti (2026-11-08, regola fissa: sempre un piano Guardiano, Lv.2 al Piano 5 e poi un livello ogni 10 piani): Lv.2 Piano 5 + 40k Oro, Lv.3 Piano 10 + 120k, Lv.4 Piano 20 + 300k, Lv.5 Piano 30 + 700k, Lv.6 Piano 40 + 1,2M, Lv.7 Piano 50 + 1,9M, Lv.8 Piano 60 + 3M, Lv.9 Piano 70 + 4,5M, Lv.10 Piano 80 + 6,5M. La mappa della Torre segnala i piani che sbloccano un livello della base (`GameState.BASE_LEVELS`, con una riga "look" che il pannello del Cristallo mostra come anteprima).
- **Strutture fino al Lv.10**, sempre entro il livello della base (`FACILITY_MAX_LEVEL`). Costo del potenziamento: costo di partenza × 1,85 a livello fino al Lv.5, poi × 1,4 a livello. I livelli 1–3 aggiungono un piano; dal Lv.4 l'edificio cresce in altri modi (vedi `ART_DIRECTION.md`).
- **Isole della base** (`GameState.BASE_ISLANDS`): dal Lv.6 la base aggiunge isole collegate da ponti, ognuna con un vantaggio:
  - Isola dei Campi (Base Lv.6): +2 posti al Centro di Addestramento (chi è in più si allena nell'arena dell'isola);
  - Isola delle Dimore (Base Lv.8): +6 letti nel Dormitorio (le panchine della piazzetta accolgono chi si riprende);
  - Santuario del Nexus (Base Lv.10): +10% esperienza dalle missioni.
- Training: slots = 2 + level (+2 con l'Isola dei Campi); XP accrues over real time (offline capped at 8 h); fatigue grows; stops at level cap or fatigue 90.
- Dormitory: beds = 5 + 2 × (level − 1) (+6 con l'Isola delle Dimore); restores fatigue and morale, heals injuries over time; heroes leave when fully recovered.
- XP curve: `30 + 14 × level^1.45`; level-ups add stats from the hidden growth value.
- **Fusione a due eroi** (regola del proprietario, 2026-11-12; `merge_heroes`): il primo eroe resta, il secondo viene **sacrificato per sempre** (non può essere in squadra; chi resta sì). Chi resta prende il 10% delle statistiche del sacrificato (+1% per livello del Centro di Fusione, minimo 1 per statistica) e a volte una sua abilità particolare: una nuova se ha meno di 3 abilità, oppure quella che hanno già in comune sale di livello. Probabilità per fusione: 55% (abilità comune) o 35% (unica), +3% per livello del Centro, al massimo una abilità a fusione. **Le stelle non cambiano**: salgono solo con la promozione. **Margine nascosto**: in tutto un eroe può prendere con le fusioni al massimo potenziale × 4 punti statistica (`merge_capacity`); quando è pieno la fusione gli dà meno e poi niente (si può ancora fondere se passa un'abilità). Il margine non si vede nel gioco. Gli oggetti forgiati del sacrificato tornano in magazzino. Oltre il Lv.99 la fusione è l'unico modo di far crescere un eroe.
- Promotion at level cap with Stones: 1★→2★ 1, 2★→3★ 2, 3★→4★ 3, 4★→5★ 5, 5★→6★ 12 (Floor 30). **La promozione arriva al massimo a 6★**: la 7ª stella non si ottiene promuovendo, solo con l'Eco Trascendente (regola del proprietario, 2026-11-12).

## Consigli del Sistema
Decisione del proprietario (2026-11-12): un assistente che **non si chatta** ma osserva e consiglia da solo, sul gioco e su altre cose utili (`godot/scripts/system_advisor.gd`, riquadro `godot/scripts/ui/advisor_card.gd`). Legge soltanto lo stato e non cambia il salvataggio; l'unica azione è la "Formazione consigliata", che il giocatore sceglie con un pulsante (esclude gli sfiniti, penalizza feriti e molto stanchi). Quando non c'è niente di urgente mostra un suggerimento sulle regole ("Lo sapevi?").

## Facilities
Facilities are both gameplay systems and physical places in the Godot hub.
Important rule: **system availability and visual presence must stay coherent**. A facility that has not been built/unlocked should not appear as a finished physical building unless the user explicitly wants a construction/preview representation.

Newer base/hub decisions in `GAME_VISION.md` override older facility visualization assumptions.

### Armeria: forgia a mano (novembre 2026)
Richiesta del proprietario: le armi non escono più a caso, si forgiano a mano con un minigioco di precisione.
- **Si sblocca dopo il Piano 3** (regola del proprietario, 2026-11-12): il cantiere compare alla Base Lv.1 appena il Piano 3 è superato (`FACILITIES.armory.unlock_floor`, `facility_unlock_text`). Prima serviva la Base Lv.2.
- **Il lavoro può fallire**: sotto il 25% di precisione (`FORGE_FAIL_PRECISION`) il pezzo si rompe e i materiali pagati sono persi.
- **Tre fasi**: *Scalda* (ferma il cursore nella zona incandescente della barra), *Martella* (sulla lama compaiono dei punti, un anello si stringe su ognuno: colpisci quando combacia con il bordo; con il mouse conta anche la mira), *Tempra* (come Scalda, zona più stretta e cursore più veloce).
- **Precisione** = calore 20% + media dei colpi di martello 60% + tempra 20%.
- **Gradi da E a S** (`GRADES`): sotto il 25% il lavoro fallisce, E 25%, D 40%, C 55%, B 70%, A 82%, S 92% (`FORGE_GRADE_THRESHOLDS`). Il grado F resta solo per gli oggetti vecchi. Statistiche per grado: ×0,55 / 0,75 / 1 / 1,35 / 1,75 / 2,2 / 2,8 sui valori base (arma 18 attacco, armatura 14 difesa, amuleto 30 vita), più fino al +10% per la precisione.
- **Difficoltà** (`FORGE_DIFFICULTIES`): Facile (max C, 4 punti, oro ×0,8), Normale (max B, 5 punti), Difficile (max A, 6 punti, oro ×1,35, Armeria Lv.3), Maestro (max S, 7 punti, oro ×1,8, Armeria Lv.5). Più è difficile, più tutto è veloce e le zone sono strette.
- **Livello dell'Armeria**: sblocca le difficoltà e allarga le zone buone del 5% per livello oltre il primo.
- I materiali si pagano all'inizio; se il gioco si chiude a metà, il lavoro resta sull'incudine e si riprende dall'Armeria senza pagare di nuovo. Gli oggetti vecchi (D–S) restano validi.

## Determinism and save integrity
Existing deterministic world/stage behavior, HeroSeed uniqueness, irreversible results, and save integrity are regression-sensitive. Changes touching RNG, mission generation, hero creation, death, economy, progression, or persistence require extra caution and relevant tests.

## Active implementation rule
All new gameplay development targets Godot. JavaScript/web files in the repository are historical reference material only and must not be treated as a second active implementation.
