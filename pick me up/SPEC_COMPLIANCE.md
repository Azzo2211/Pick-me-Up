# Matrice di conformità alle specifiche

Questa matrice distingue ciò che è giocabile nella build locale da ciò che appartiene alla roadmap server/live-service della specifica.

| Area del GDD | Stato | Implementazione |
|---|---|---|
| Identità e core loop | Completo | Master indiretto → preparazione → deployment → auto-combat → conseguenze → meta progressione. |
| Account, world seed e tower | Vertical slice | World seed persistente; 5 piani giocabili su architettura da 100. |
| Rarità 1★–7★ | Dati completi / acquisizione parziale | Cap 1★–7★ modellati; pool giocabili 1★–5★; 6★–7★ riservate all'endgame. |
| Summon e probabilità | Completo per MVP | Normal 78/19/3%; High-grade 93,5/5,5/1%; costi LOCK; soft/hard pity; no clone identico. |
| Generazione eroi | Completo | Identity seed, origine, background, professione, potential hidden, growth vector, personality, traits, assessment. |
| Statistiche e formule | Completo | STR/INT/STA/AGI, HP, attacco, magia, defense, accuracy, evasion, crit, block e ammo. |
| Leveling e promotion | Completo per early game | Curva XP, growth per livello, cap per rarità, pietre e promozione. |
| Classi e ruoli | Completo per MVP | Guardian, Vanguard, Lancer, Ranger, Mage e Support con policy e skill distinte. |
| Skill e mastery | Vertical slice | Skill attive/passive, cooldown, XP/level e uso contestuale AI. Evoluzioni avanzate restano post-slice. |
| Traits, personality e autonomia | Completo | 7 assi di personalità; Utility AI valuta bersagli, rischio, ruolo, risorse e contesto. |
| Relazioni, trust e morale | Completo per MVP | Bond pairwise, bonus squadra, morale, Fatigue e memory events. |
| Combat system | Completo | Party 5, 20 tick/s, AI 5 Hz, front/mid/rear, munizioni, macro command e nessun controllo diretto. |
| Status effects | Vertical slice | Fear, Low morale, Fatigue, ferite e protezione; catalogo esteso predisposto nella struttura. |
| Mission e stage design | Completo per slice | Subjugation, Survival, Exploration, Defense e Boss con condizioni diverse. |
| Stream generator | Completo per slice | 5 missioni collegate, seed derivati, indizi e climax persistenti. |
| Difficulty e scaling | Completo per slice | Threat budget e scaling per floor/varianza deterministica. |
| Failure, morte e retry | Completo | Permadeath immediato, tombstone, party wipe, estrazione, stage invariato e reward ridotte fino a ×0,35. |
| Waiting Room e facilities | Vertical slice | 12 facilities visualizzate; Summoning, Training, Armory, Warehouse, Lodging e crafting operativi. |
| Unlock facilities | Completo nei milestone slice | Smithy e Workshop al Floor 5; milestone successive rappresentate e bloccate. |
| Economy e reward budget | Completo per slice | Oro, Gemme, pietre, materiali, ledger, sink e formula reward/first attempt/retry. |
| Equipment e itemization | Completo per slice | 4 slot, grade D–B generabili, qualità individuale, inventory e auto-equip. |
| Synthesis | Roadmap | Facility e data boundary presenti; distruzione donor non esposta nel vertical slice per evitare un flusso incompleto. |
| Wounds, recovery e fatigue | Completo per MVP | Ferite Moderate/Serious, Fatigue persistente, Lodging e recupero offline ×3. |
| Master actions e limiti | Completo | 5 ordini macro con cooldown; nessuna hotbar di skill individuali. |
| Online, ranking e meta | Roadmap | Dimension Gate presente; server/social modes non simulati localmente. |
| Transcendent endgame | Dati/Roadmap | Cap e rarità previsti; nessun 7★ obbligatorio o venduto nel pool standard. |
| Data schema | Completo local-first | World, Hero, Skill, Equipment, Facility, StageDescriptor, MissionRun, Relationship, Ledger ed Event. |
| Server architecture | Non deployata | La demo è offline; confini Economy/Mission/Summon sono mantenuti come funzioni atomiche e ledger/event log. |
| AI degli eroi | Completo | Perception locale, target scoring, role policy, personality modifiers, resource state e squad commands. |
| Telemetry e balancing | Strumenti locali | Event log, ledger, risultati missione, kill/damage/healing, attempts e death causes. |
| UI/UX | Completo | Hub, hero screen, party formation, summon disclosure, mission HUD, report e mobile responsive. |
| Legal/etica | Conforme al perimetro | Titolo, lore, UI e personaggi originali; nessun pagamento, paid resurrection, dark pattern o loss-triggered sale. |

## Parametri LOCK verificati

- Party size: 5.
- Tower data model: 100 floor; contenuto slice: 5.
- Core stats: STR / INT / STA / AGI.
- Rarity e level cap: 1★ Lv.10, 2★ Lv.20, 3★ Lv.30, 4★ Lv.50, 5★ Lv.70, 6★ Lv.99, 7★ Lv.120.
- Normal summon: 10.000 Oro.
- High-grade summon: 500 Gemme.
- Nessuna account energy.
- Permadeath: attivo; paid resurrection: assente.
- Reroll del piano al retry: assente.
- Bond: −100…+100; morale/Fatigue: 0…100.
- AI decision rate: 5 Hz; simulation rate: 20 tick/s.
