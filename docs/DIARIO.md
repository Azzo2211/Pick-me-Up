# DIARIO.md — Diario di lavoro condiviso

Qui ogni Claude (o altro agente) che lavora sul repository scrive **cosa sta facendo e cosa ha fatto**, così gli altri lo vedono prima di mettere mano agli stessi file.

## Come si scrive
- Una voce per lavoro, **la più recente in alto**.
- Titolo: data, reparto, argomento e numero dell'issue.
- Stato: **in corso** quando inizi, **fatto** quando hai finito (con il commit).
- Poche righe: cosa cambia per chi gioca, quali file hai toccato, cosa resta da fare o da controllare.
- Scrivi in italiano.

---

## 2026-11-08 · Art · Occhi e capelli colorati dei ritratti — fatto
Segnalazione del proprietario: con occhi o capelli colorati i ritratti si vedono male.
- **Cosa non andava**: le iridi ricolorate erano dischetti più piccoli dell'iride e più chiari del disegno (puntini che brillano, spesso sulla palpebra); i capelli ricolorati avevano macchie sulla pelle tra le ciocche e colori piatti.
- **Shader** (`godot/scripts/hero_portrait.gd`, `RECOLOR_SHADER`): colore in OKLab; capelli con ombre e riflessi del disegno e tinta un po' smorzata, la pelle tra le ciocche (più chiara dei capelli dipinti) non si tocca; iridi con la luminosità dipinta e solo la tinta nuova, pupilla e riflessi restano.
- **Maschere e catalogo** (`godot/assets/portraits/pNNN_mask.png`, `portraits.json`, strumento nuovo `tools/character_kit/portrait_masks.py`): iridi intere dai punti dell'iride di MediaPipe dentro l'apertura dell'occhio; controllate a occhio una per una, 127 volti le hanno (prima 140, con dischetti spesso fuori posto), gli altri tengono gli occhi dipinti. Capelli scuri senza i pezzi di pelle del viso. Luminosità in OKLab.
- **Scelta del colore** (`godot/scripts/portrait_library.gd`): i capelli si ricolorano solo tra colori vicini (`HAIR_COMPAT`); prima anche nero → biondo, che veniva grigio.
- Test: regole 37 su 37, interfaccia 35 su 35 (con i test dei piani appena allineati ai nuovi requisiti della base).
- Strumento: si rilancia senza problemi per le iridi; sui capelli già puliti toglie ancora un po' di pixel, quindi per rifare tutto si riparte dalle maschere di prima (commit 106589f).
- Documento: `ART_DIRECTION.md`. Immagine prima/dopo: `/mnt/project-files/riftward-personaggi/prima_dopo_occhi_capelli.png`.
- Da controllare (QA): carte e dossier di eroi con capelli blu, rosa, verdi o viola e con occhi colorati.

## 2026-11-08 · Design + Programming + UI · Armeria con forgia a mano — fatto
Richiesta del proprietario: l'armeria deve essere completamente diversa, le armi si forgiano a mano con minigiochi di precisione e difficoltà, grado da F a S.
- **Minigioco** (`godot/scripts/ui/forge_minigame.gd`, nuovo): Scalda → Martella i punti → Tempra, a tutto schermo; mouse o Spazio/Invio; scintille e giudizio a ogni colpo; alla fine il grado grande con l'oggetto ottenuto.
- **Regole** (`godot/scripts/game_state.gd`): gradi F–S, `FORGE_DIFFICULTIES`, `begin_forge` (paga) e `finish_forge(precisione)`; `forge_item` resta per test e strumenti. Lavoro sospeso salvato in `forge_pending`.
- **Pannello Armeria** (`godot/scripts/ui/facility_panels.gd`): scelta della difficoltà, ricette con costo aggiornato, "Riprendi la forgia", precisione degli oggetti in deposito.
- Test: nuovo test di regole in `test_runner.gd`, smoke aggiornato. Documento: `GAME_SYSTEMS.md`.
- Da controllare (QA): giocare le quattro difficoltà, chiudere il gioco a metà forgia e riprenderla.
## 2026-11-08 · Design + Programming · Stanchezza con malus veri, base legata ai Guardiani, gemme a ogni piano — fatto
Richiesta del proprietario: la stanchezza non cambiava niente; i requisiti piano/base non erano coerenti; i piani davano gemme solo al primo completamento.
- **Stanchezza** (`game_state.gd` `FATIGUE_LEVELS`, `fatigue_level`, `derived_stats`; `battle_scene.gd` passo e cadenza): 4 livelli (Riposato, Stanco 40+, Esausto 70+, Sfinito 90+) con malus a vita, attacco, difesa, precisione, schivata, passo e velocità d'attacco. Sfinito = non parte. Avvisi nel Portale e riga nella scheda eroe (`facility_panels.gd`).
- **Base**: Lv.2 al Piano 5, poi Piani 10, 20 … 80 (sempre un Guardiano). La mappa della Torre dice quale piano sblocca un livello della base.
- **Gemme**: ogni vittoria dà gemme; il primo completamento come prima, le ripetizioni 15+1,5×piano (×2 ai Guardiani, ridotte dai tentativi).
- Test nuovi in `tests/test_runner.gd` (stanchezza, gemme) e test della base aggiornato. Non eseguiti nel cloud (Godot non avviabile qui): da lanciare sul PC.

## 2026-11-05 · Design + Programming + Art + UI · Base fino al Lv.10, edifici e isole (#16) — fatto
Commit bfdc4e6, 1b4b769, d32d4ba, ea965f6, d4eb248 (etichette che non si accavallano). Richiesta del proprietario: non gli piace il cerchio iniziale dell'evocazione; più livelli per base ed edifici (il massimo non può essere 5 con 100 piani); se serve spazio, altre isole.
- **Evocazione** (`godot/scripts/ui/summon_event.gd`): niente più cerchio; il Rift si apre con uno squarcio verticale e fulmini, le carte escono dallo squarcio.
- **Regole** (`godot/scripts/game_state.gd`): base fino al Lv.10 (Piani 25/35/50/65/80), strutture fino al Lv.10 (costo +85% a livello fino al 5, poi +40%), tre isole con un vantaggio ciascuna (`BASE_ISLANDS`): Campi +2 posti in Addestramento, Dimore +6 letti nel Dormitorio, Santuario +10% esperienza. Pannelli e tutorial aggiornati (`facility_panels.gd`, `main.gd`).
- **Edifici** (`godot/scripts/hub3d/building_model.gd`): piani solo fino al Lv.3, poi pietra (4), torretta (5), seconda torretta e abbaini (6), rune (7), cristalli (8), aureola (9), guglia d'oro (10). Galleria: `godot/tests/building_lineup_runner.gd`.
- **Isole** (`godot/scripts/hub3d/hub_islands.gd`, agganci in `hub_world.gd`, `hub_view.gd`, `hub_agent.gd`): Campi (Lv.6), Dimore (Lv.8), Santuario (Lv.10) con ponti e sentiero fuori dalle mura; eroi e abitanti ci camminano. Base Lv.7 e Lv.9 con nuovi dettagli in piazza e sulle torri.
- Test: 34 + 33 passati. Documenti: `GAME_SYSTEMS.md`, `ART_DIRECTION.md`.
- Da controllare (QA): potenziare la base dal Lv.5 al Lv.10 con le Impostazioni di sviluppo e guardare che le isole compaiano e che la camera le inquadri; un eroe in allenamento oltre i posti del cortile deve andare nell'arena dei Campi.

## 2026-11-05 · Art + UI · Animazioni di uccisioni ed evocazioni (#15) — fatto
Commit 0c48a8c. Richiesta del proprietario: migliorare le animazioni di tutto, soprattutto uccisioni in battaglia ed evocazioni (pull); prima gli piacevano solo le carte Trascendenti.
- **Evocazione** (`godot/scripts/ui/summon_event.gd`): il varco risucchia particelle e poi esplode (lampo, onda d'urto, schegge, scossa); le carte escono dal varco e volano al loro posto; rivelazione diversa per rarità (tabelle `ANTICIPATION`, `AFTER`, `BURST` in cima al file): da 4★ fascio di luce e aura, da 5★ attesa con la carta che trema, raggi e lampo, da 6★ scossa forte e nome in alto.
- **Carte** (`godot/scripts/ui/hero_card.gd`): ora si animano anche 4★ (bagliori agli angoli) e 5★ (polvere d'oro, alone che pulsa), con un riflesso che attraversa la carta ogni pochi secondi.
- **Battaglia** (`godot/scripts/battle/battle_scene.gd`, solo aspetto): scintille sui colpi, numeri che saltano e si impilano, nemici che esplodono in schegge e si dissolvono in cenere, campioni e Guardiano con scritta, rallentatore e scossa; eroe caduto con rallentatore, bordo rosso, colonna di luce e scritta "CADUTO". Funzioni: `_hit_fx`, `_kill_fx`, `_update_fx`, `_draw_fx`. Gli effetti usano `fx_rng`, separato da `rng`: i risultati delle battaglie non cambiano.
- **Banco di prova**: `godot/tests/fx_probe_runner.gd` salva i fotogrammi di un'evocazione o di una battaglia (con `--fixed-fps 30`) da montare in video.
- Da controllare (QA): evocazione x1 e x10, "Salta" a metà, una battaglia con un eroe caduto e il Guardiano del Piano 5.

## 2026-11-05 · Design + Programming · Torre a scaglioni e Prova del Guardiano (#13) — fatto
Commit 39f308d e 5d5c18b.
- La Torre è divisa in scaglioni di 5 piani: dentro lo scaglione i nemici crescono poco, a ogni nuovo scaglione c'è un salto netto.
- Ogni 5 piani c'è la Prova del Guardiano: guardiano che si infuria a metà vita, campioni d'élite, 1–3 regole speciali, ricompense più alte.
- File: `godot/scripts/game_state.gd` (tabelle `TOWER_TIER_POWER`, `TOWER_TRIAL_POWER`, `TOWER_TRIALS`), `godot/scripts/battle/battle_scene.gd` (regole in battaglia), `godot/tests/tower_curve_runner.gd` (taratura), `docs/GAME_SYSTEMS.md`.
- Da fare per UI: mostrare le regole della prova sulla mappa (#14).
