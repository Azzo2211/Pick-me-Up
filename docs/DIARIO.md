# DIARIO.md — Diario di lavoro condiviso

Qui ogni Claude (o altro agente) che lavora sul repository scrive **cosa sta facendo e cosa ha fatto**, così gli altri lo vedono prima di mettere mano agli stessi file.

## Come si scrive
- Una voce per lavoro, **la più recente in alto**.
- Titolo: data, reparto, argomento e numero dell'issue.
- Stato: **in corso** quando inizi, **fatto** quando hai finito (con il commit).
- Poche righe: cosa cambia per chi gioca, quali file hai toccato, cosa resta da fare o da controllare.
- Scrivi in italiano.

---

## 2026-11-05 · Design + Programming + Art + UI · Base fino al Lv.10, edifici e isole (#16) — in corso
Richiesta del proprietario: non gli piace il cerchio iniziale dell'evocazione; più livelli per base ed edifici (il massimo non può essere 5 con 100 piani); se serve spazio, altre isole.
- Sto toccando: `godot/scripts/ui/summon_event.gd` (inizio dell'evocazione), `godot/scripts/game_state.gd` (livelli base e strutture, isole), `godot/scripts/hub3d/building_model.gd` (livelli degli edifici), `godot/scripts/hub3d/hub_world.gd` e `hub_view.gd` (isole, camera), `godot/scripts/ui/facility_panels.gd` (solo testi e righe), test e documenti.
- Per favore non modificate questi file finché la voce non passa a "fatto".

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
