# DIARIO.md — Diario di lavoro condiviso

Qui ogni Claude (o altro agente) che lavora sul repository scrive **cosa sta facendo e cosa ha fatto**, così gli altri lo vedono prima di mettere mano agli stessi file.

## Come si scrive
- Una voce per lavoro, **la più recente in alto**.
- Titolo: data, reparto, argomento e numero dell'issue.
- Stato: **in corso** quando inizi, **fatto** quando hai finito (con il commit).
- Poche righe: cosa cambia per chi gioca, quali file hai toccato, cosa resta da fare o da controllare.
- Scrivi in italiano.

---

## 2026-11-05 · Art + UI · Animazioni di uccisioni ed evocazioni (#15) — in corso
Richiesta del proprietario: migliorare le animazioni di tutto, soprattutto uccisioni in battaglia ed evocazioni (pull); oggi gli piacciono solo le carte Trascendenti.
- Evocazione (`godot/scripts/ui/summon_event.gd`, `godot/scripts/ui/hero_card.gd`): varco che risucchia particelle ed esplode, carte che escono dal varco, rivelazione diversa per ogni rarità, aura sulle carte alte.
- Battaglia (`godot/scripts/battle/battle_scene.gd`, solo aspetto): scintille sui colpi, numeri che saltano, nemici che si dissolvono in cenere, rallentatore e scossa su campioni, Guardiano ed eroi caduti.
- Banco di prova: `godot/tests/fx_probe_runner.gd` (fotogrammi da montare in GIF).

## 2026-11-05 · Design + Programming · Torre a scaglioni e Prova del Guardiano (#13) — fatto
Commit 39f308d e 5d5c18b.
- La Torre è divisa in scaglioni di 5 piani: dentro lo scaglione i nemici crescono poco, a ogni nuovo scaglione c'è un salto netto.
- Ogni 5 piani c'è la Prova del Guardiano: guardiano che si infuria a metà vita, campioni d'élite, 1–3 regole speciali, ricompense più alte.
- File: `godot/scripts/game_state.gd` (tabelle `TOWER_TIER_POWER`, `TOWER_TRIAL_POWER`, `TOWER_TRIALS`), `godot/scripts/battle/battle_scene.gd` (regole in battaglia), `godot/tests/tower_curve_runner.gd` (taratura), `docs/GAME_SYSTEMS.md`.
- Da fare per UI: mostrare le regole della prova sulla mappa (#14).
