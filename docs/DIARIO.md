# DIARIO.md — Diario di lavoro condiviso

Qui ogni Claude (o altro agente) che lavora sul repository scrive **cosa sta facendo e cosa ha fatto**, così gli altri lo vedono prima di mettere mano agli stessi file.

## Come si scrive
- Una voce per lavoro, **la più recente in alto**.
- Titolo: data, reparto, argomento e numero dell'issue.
- Stato: **in corso** quando inizi, **fatto** quando hai finito (con il commit).
- Poche righe: cosa cambia per chi gioca, quali file hai toccato, cosa resta da fare o da controllare.
- Scrivi in italiano.

---

## 2026-11-14 · Production · Regole aggiornate del proprietario distribuite ai reparti — fatto
Il proprietario ha mandato la versione aggiornata delle regole (sezioni 5 allenamento, 9 tempo, 14 professioni) e ha chiesto i dungeon giornalieri con materiali da comuni a rari.
- Documento di riferimento nuovo: `docs/REGOLE_DI_GIOCO.md` (regole + sezione 18 Dungeon giornalieri + stato nel gioco + cose da decidere). `GAME_SYSTEMS.md` ora rimanda lì.
- Cosa manca davvero: allenamento a scelta con limite per eroe, skill imparate al Training Center, disobbedienza, intesa in battaglia, moderatrice, MVP, materiali rari nei dungeon. Da decidere: esperienza dall'allenamento, probabilità del fabbro, gradi rari dei materiali, cibo.
- Un'issue per reparto con il proprio pezzo (vedi `REGOLE_DI_GIOCO.md`, "Lavoro dei reparti"). Il lavoro di codice continua nella voce #18 qui sotto.

## 2026-11-12 · Art + Programming · Personaggi 3D uguali ai ritratti, tutti nella base, grafica più viva — fatto
Richiesta del proprietario: "migliora tutta la grafica… allinea le immagini ai personaggi 3D, ogni personaggio dell'immagine devi metterlo anche nella base".
- **Stessa persona in carta e in 3D**: ogni eroe ha un ritratto fisso salvato (`hero.portrait_id`, `GameState.assign_portraits`; i salvataggi vecchi tengono gli stessi volti). `appearance_for` prende dal ritratto sesso, pelle, taglio dei capelli, barba, occhiali, cicatrice, età, corporatura, elfi, nani, pelleverde, uomini-bestia e copricapo. Prima il 3D seguiva solo il generatore: pelle, barba, occhiali e capelli spesso non c'entravano col ritratto.
- **Catalogo dei ritratti** (`godot/assets/portraits/portraits.json`): per ognuno dei 300 volti, guardati uno per uno, taglio dei capelli del kit, copricapo con colore e tipo di cappello, barba lunga, colori dei vestiti. Strumento nuovo `tools/character_kit/portrait_traits.py` (il file ora ha un volto per riga).
- **Modello 3D** (`godot/scripts/hub3d/character_model.gd`): `_portrait_details` modella fazzoletti, bandane, cappucci, veli, otto cappelli, occhialoni, cerchietti, bende, fiori, barbe lunghe, orecchie da elfo e teste da uomo-bestia attorno ai capelli; i capelli sotto un copricapo si schiacciano un po' (`HAIR_PRESSED`). Vale anche sui corpi dell'utente (il viso dipinto resta il loro).
- **Tutti nella base** (`hub_world.gd`): fino a 80 eroi (prima 30), squadra sempre per prima; il personaggio si rifà se cambiano classe, stelle o ritratto.
- **Luce e colore** (`world_look.gd`, `mist.gdshader`, `battle_scene.gd`): sole più caldo, ombre più fredde, colori più pieni, alone "screen", mare di nubi acceso dal sole, lucciole a crepuscolo e notte, in battaglia foschia ridotta al 42%.
- Test: regole 40 su 40 (nuovo: ritratto e 3D corrispondono, il ritratto resta fisso), interfaccia 37 su 37. Strumenti: `tests/portrait_match_runner.gd`, `tests/graphics_compare_runner.gd`.
- Da controllare (QA): prestazioni della base con più di 40 eroi su un PC lento; cappelli a falda in battaglia (barre della vita); se il crepuscolo più saturo piace al proprietario.

## 2026-11-12 · Design + Programming + UI · Regole del proprietario: allineare il gioco al documento (#18) — in corso
Il proprietario ha mandato le regole aggiornate. Lavoro a blocchi: correzioni (Lv max 99, 7ª stella solo da evocazione, Armeria dopo il Piano 3, piani 1–4 annientamento, statistiche STR/INT/HP/DEX, materiali di grado C, forgia che può fallire), Fusione a due eroi, dungeon giornalieri, mestieri e vita quotidiana, emozioni e intesa in battaglia, moderatrice.
- Precisazioni del proprietario dopo il documento: il **cibo compare da solo** alla base (niente da comprare o gestire, il cuoco migliora i pasti); l'**allenamento resta com'era**, ma le schede non devono dire se un eroe impara più in fretta: lo scopre il giocatore; servono **dungeon giornalieri** facili, con mostri deboli, soprattutto per i materiali.
- Blocco 1 fatto (vedi commit "Regole del proprietario, blocco 1"): correzioni e potenziale nascosto. Resta da ritarare la curva dei piani 71–100 (con il Lv max a 99 è troppo dura): la ritaro alla fine, dopo emozioni e intesa in battaglia, che cambiano anche loro gli esiti.
- Blocco 4 fatto: **mestieri, lavori e orologio**. `hero.trade` (competenza 1–10), nove posti di lavoro al Cristallo (scheda "Lavori"), grado della forgia limitato da fabbro, carpentiere e conciatore al lavoro (senza nessuno: E), pasti del cuoco, sconto dell'emporio, esperienza dell'archivio, scorte del giorno, orologio di gioco 1:3 in alto a sinistra. Il cibo compare da solo (precisazione del proprietario).
- Blocco 3 fatto: **dungeon giornalieri** al Portale (scheda "Dungeon"): quattro missioni facili, una per materiale, mostri deboli, due vittorie al giorno, livello a scelta. Nuova prova `tower_curve_runner.gd --dungeons`.
- **Pausa sul documento**: il proprietario ha chiesto di migliorare la grafica e di rendere i personaggi 3D della base uguali ai ritratti delle carte. Fatto (voce sopra). Restano: emozioni e intesa in battaglia, moderatrice, curva dei piani 71–100.
- Blocco 2 fatto: Fusione a due eroi (uno resta, uno sacrificato; statistiche e a volte un'abilità; margine nascosto; niente stelle) e abilità particolari comuni o uniche (alcuni eroi nascono senza). `tower_curve_runner.gd` ora dà alle squadre degli scaglioni 15–20 una parte del margine di fusione (`MERGE_FILL`).
- Sto toccando soprattutto: `godot/scripts/game_state.gd`, `godot/scripts/battle/battle_scene.gd`, `godot/scripts/ui/facility_panels.gd`, `godot/scripts/system_advisor.gd`, `godot/scripts/ui/advisor_card.gd`, `godot/scripts/main.gd`, test e documenti. Per favore non modificateli finché la voce non passa a "fatto".

## 2026-11-12 · Programming + UI · Consigli del Sistema (#17) — fatto
Richiesta del proprietario: un assistente che non si chatta ma dà consigli sul gioco e su altre cose.
- **Logica** (`godot/scripts/system_advisor.gd`, nuovo): guarda lo stato e propone consigli ordinati per urgenza: squadra bloccata o incompleta, stanchi e feriti, eroi fuori ruolo, squadra migliore disponibile, Prova del Guardiano in arrivo, piano su cui si è bloccati, popolani senza classe, posti liberi in Addestramento e nel Dormitorio, promozioni e fusioni pronte, espansione della base, cantieri e potenziamenti, pity vicino al 5★, scorte piene, offerte del giorno, Diario. Più un "Lo sapevi?" sulle regole del gioco. Legge soltanto: non cambia mai il salvataggio (c'è un test).
- **Riquadro "Sistema"** (`godot/scripts/ui/advisor_card.gd`, nuovo; collegato in `main.gd`): in alto a sinistra sotto il Maestro, un consiglio alla volta con il pulsante che porta dove serve, frecce, "Nascondi" e riduzione a icona. Se arriva un consiglio urgente il riquadro si riapre e lampeggia.
- **Formazione consigliata** (`facility_panels.gd`): ora usa la stessa scelta del Sistema e lascia fuori gli sfiniti (prima poteva metterli in squadra e bloccare la partenza).
- Test: regole 38 su 38 (nuovo: consigli del Sistema), interfaccia 35 su 35.
- Da controllare (QA): che il riquadro non copra niente a 1280x720 e che i pulsanti dei consigli aprano la struttura giusta.

## 2026-11-10 · Art · Mostri rifatti e movimenti a tutto corpo — fatto
Richiesta del proprietario: migliorare personaggi 3D, movimenti e mostri, "che sono stati un problema nel gioco". Tutto in `godot/scripts/hub3d/character_model.gd` (più due righe in `hub_agent.gd`); `battle_scene.gd` non è stato toccato.
- **Segugio**: lupo vero (torace profondo, vita stretta, collo, criniera, zampe dietro col garretto, coda attaccata, mascella che si apre, cristalli del Varco sulla schiena). Trotta o galoppa secondo la velocità, morde con un balzo, sussulta ai colpi, cade sul fianco.
- **Bruto**: orco curvo e massiccio (spalle enormi, braccia lunghe, zanne, spallaccio, mazza ferrata). Passo pesante che dondola, colpo dall'alto con tutto il corpo, crolla in ginocchio e poi a terra.
- **Guardiano**: colosso di massi con avambracci enormi, nucleo e crepe accesi nel colore del piano, cristalli sulle spalle. Stessi movimenti pesanti del bruto, pugni a terra.
- **Eroi e predoni**: fendente, spadone a due mani e affondo di lancia ora muovono tutto il corpo (carica, passo, peso in avanti, piedi piantati). Il passo segue la velocità vera: camminata, corsa o scatto, così i piedi non pattinano più in battaglia. Chi viene colpito incassa all'indietro (parte dal lampo di `flash()`). Alla base si cammina soltanto (`calm`).
- Il danno arriva sempre all'inizio del colpo, come prima: l'impatto dell'animazione cade a circa un terzo della durata. Durate nuove in `ATTACK_LENGTHS` (mischia 0,55 s, spadone 0,74, lancia 0,52, morso 0,55, mostri grossi 0,95).
- Test: regole 37 su 37, interfaccia 35 su 35. Battaglie di prova ai piani 2, 4 e 5 senza errori.
- Immagini: `/mnt/project-files/riftward-personaggi/mostri_prima_dopo.png`, `/mnt/project-files/riftward-personaggi/movimenti_eroi.png`.
- Da controllare (QA): in battaglia, altezza delle barre vita su bruto e Guardiano, e se la corsa degli eroi a velocità ×2 e ×4 resta leggibile. Per Programmazione: se volete l'impatto preciso, il momento è `attack_length * 0.31` (0,38 per i mostri grossi).

## 2026-11-08 · Art · Ritratti: occhi colorati rimessi al loro posto — fatto
Segnalazione del proprietario (scheda di Doria Rook): l'azzurro degli occhi non era messo bene.
- **Doria** (`p293`): MediaPipe metteva l'iride sinistra 8 pixel accanto a quella dipinta, così metà occhio restava marrone. Spostata a mano sull'iride dipinta.
- **Occhio lontano**: nei volti di tre quarti l'occhio più lontano è mezzo nascosto da palpebra o naso, e colorato diventava una striscia sulla palpebra. In 52 volti ora resta dipinto (si vede appena) e si colora solo l'occhio vicino. 6 volti con occhi socchiusi o iride spostata tengono gli occhi dipinti: restano 121 volti con occhi colorabili.
- **Strumento** (`tools/character_kit/portrait_masks.py`): `EYE_FIX` (correzioni a mano per occhio: "via" o spostamento) e `BAD_EYES`; rifatte con `--occhi` solo le iridi di quei 59 volti, capelli identici. Controllo fatto ingrandendo ogni occhio con contorno della maschera e colore azzurro.
- I puntini arancioni nella scheda di Doria sono le braci delle carte a 6 stelle (`godot/scripts/ui/hero_card.gd`, UI), non il ritratto.
- Test: regole 37 su 37, interfaccia 35 su 35.
- Immagine prima/dopo: `/mnt/project-files/riftward-personaggi/occhi_doria_pyria_rhea.png`.
- Da controllare (QA): schede grandi di eroi con occhi azzurri, dorati o viola, soprattutto volti di tre quarti.

## 2026-11-08 · Art · Ritratti: occhi con la pupilla, capelli solo dove la maschera è pulita — fatto
Segnalazione del proprietario (immagini di Pyria, Rhea e Iven): alcuni ritratti ancora sbagliati; gli occhi dorati vanno bene, ma si deve vedere che sono occhi; Iven ha la benda sugli occhi gialla.
- **Occhi** (`godot/scripts/hero_portrait.gd`, `eye_lab`): il colore resta acceso, ma al centro dell'iride c'è una pupilla scura e il bordo dell'iride è più scuro; ombra della palpebra e toni scuri restano scuri. Usa il blu delle maschere (distanza dal centro dell'iride), scritto da `tools/character_kit/portrait_masks.py` (opzione nuova `--occhi`: rifà solo iridi e pupille, i capelli restano come sono).
- **Capelli** (`godot/assets/portraits/portraits.json`, `hair_ok`): i 99 volti con capelli ricolorabili ricolorati per prova nel colore più lontano permesso e guardati uno per uno. 32 coloravano anche bende (Iven: `p060`), colletti, pellicce, occhiali, orecchini grandi o pelle, oppure lasciavano metà capelli col colore vecchio: ora tengono i capelli dipinti e vanno solo a eroi con quel colore. Lista `BAD_HAIR` nello strumento, così una nuova passata la rispetta.
- **Cosa cambia in gioco**: Iven (biondo) e pochi altri eroi che avevano uno di quei 32 volti ricolorati prendono un altro volto. Simulazione: con 40 eroi quasi nessuno cambia, con 120 eroi in media 4.
- Test: regole 37 su 37, interfaccia 35 su 35.
- Immagine prima/dopo: `/mnt/project-files/riftward-personaggi/prima_dopo_pupille_capelli.png`.
- Da controllare (QA): carte di eroi con occhi dorati, viola o rossi (pupilla visibile) e un roster grande (nessun capello colorato su bende, colletti o pellicce).

## 2026-11-08 · Art · La base cresce in larghezza e con isolotti — fatto
Richiesta del proprietario: la base cresceva solo in altezza (piani degli edifici), poco bello; farla crescere in grandezza o con isole.
- **Isola principale più grande a ogni livello** (`godot/scripts/hub3d/hub_world.gd`, `ISLAND_GROWTH`): raggio medio 18,6 al Lv.1 → 21,2 al Lv.5. Scogliera, ponte del Portale e laghetto seguono il bordo (`_build_shore()`, `pond_center()`). Borgo e mura restano dove sono.
- **Isolotti con ponte di corda** (`godot/scripts/hub3d/hub_outposts.gd`, nuovo): Vedetta (Lv.2), Frutteto (Lv.3), Sorgente con cascata (Lv.4), Miniera di cristalli (Lv.5), Faro (Lv.7). Solo scenografia: niente bonus, eroi e abitanti non ci vanno. Le isole con vantaggio (Lv.6, 8, 10) restano com'erano.
- Camera iniziale un po' più lontana per ogni isolotto; `focus_on("isolotto:<id>")` per inquadrarli; `hub_preview_runner.gd --shots=isolotto:faro`.
- Test: 34 + 33 passati.
- Da controllare (QA): potenziare la base dal Lv.1 al Lv.7 con le Impostazioni di sviluppo e guardare che gli isolotti compaiano senza tagli in camera.

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
