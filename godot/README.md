# Riftward — progetto Godot

Requisito: Godot 4.7.1 o compatibile.

## Giocare

Dalla cartella principale fai doppio clic su `Avvia_Riftward_Godot.cmd`.

## Aprire nell'editor

Fai doppio clic su `Apri_Progetto_Godot.cmd`. In alternativa, nel Project Manager di Godot seleziona **Importa** e apri questo file `project.godot`.

## Shop sandbox

Lo Shop è una simulazione locale: tutti gli articoli costano €0,00, non usa Internet e non raccoglie dati di pagamento. Ogni articolo è riscattabile una volta per world e produce una ricevuta con prefisso `SIM-`.

## Modalità DEV / QA

Clicca il **Nexus Centrale** nella Base e scegli **Apri DEV / QA**. La modalità rende infinite Oro, Gemme, Pietre e materiali senza alterare i costi mostrati. Torre ed Eroi conservano tutte le informazioni normali del giocatore; in fondo alle rispettive schede compare un riquadro **Extra DEV** con potenziale, crescita, personalità, minaccia, durata e numero di ondate, senza codici o JSON. I comandi QA permettono di ripristinare il roster, sbloccare i contenuti, generare eroi 5★, impostare il pity a 99, resettare lo Shop e controllare la coerenza del save.

## Direzione visiva

La Base di livello 1 usa `assets/backgrounds/base_level_1_wide.png` e la piazza collegata `assets/buildings/summoning_plaza_connected.png`. Le aree cliccabili degli edifici sono completamente invisibili: niente contorni, nomi o anelli al passaggio del mouse e dopo il clic. Le altre schermate mantengono la codifica cromatica: ciano per il sistema, blu per le azioni, viola per evocazione e metagioco, rosso per il pericolo, oro per ricompense e alte rarità.

La suite `tests/visual_capture_runner.gd` salva anteprime di Base, pannello Training, Evocazione, Fusione e Roster per controllare rapidamente proporzioni e leggibilità nel formato PC 1920×890.

## Base/HUB visuale

La Home apre direttamente la Base Lv.1 popolata. La sidebar non viene più creata in nessuna schermata. Gli otto punti interattivi sono Alloggi, Training, Portale, Magazzino, Centro di Fusione, Centro Evocativo, Alchimia e Nexus Centrale. Ogni struttura apre prima un pannello contestuale mantenendo la base visibile; il pulsante nel pannello conduce poi al sistema richiesto. Nelle schermate interne usa **Torna alla Base** in alto a sinistra.

Collegamenti diegetici:

- Alloggi o Training → gestione Eroi;
- Portale → Torre e missioni;
- Magazzino → Shop e Archivio;
- Centro di Fusione → Fusione di tre eroi della stessa rarità;
- Centro Evocativo → Evocazione;
- Alchimia → servizi Base e crafting;
- Nexus Centrale → Squadra e DEV / QA.

Controlli desktop:

- clicca un edificio per evidenziarlo e lasciare che la camera lo inquadri;
- usa **RICENTRA BASE** per tornare all'inquadratura generale;
- la rotellina non modifica la visuale: lo zoom manuale è disattivato.

La mappa copre sempre tutta l'area di gioco e la camera resta confinata alla cittadella. Lo spostamento manuale è riservato al tasto centrale e al trascinamento touch con un dito; il pinch-to-zoom è disattivato. Gli Hero Agent usano una simulazione centralizzata con stati `IDLE`, `WALKING` e `ACTIVITY`; i loro percorsi seguono waypoint disposti sui sentieri e aggirano edifici e Nexus. Ogni agente conserva eroe associato, destinazione, edificio, attività, velocità e stato di occupazione. Training supporta già upgrade persistente e una seconda variante visiva. Le icone discrete sugli edifici segnalano missioni, crafting, ricerca e recupero.

La Base Lv.1 usa `assets/backgrounds/base_level_1_wide.png`, una variante panoramica che conserva l'intera isola e amplia solamente cielo e atmosfera laterali per adattarsi all'area PC 1920×890 senza tagliare gli edifici.

Il rapporto di stiramento è impostato su `expand`: quando la finestra viene massimizzata o assume proporzioni diverse, la UI e la mappa si espandono fino ai bordi invece di produrre fasce nere sopra e sotto.

Per la verifica dedicata usa `tests/base_hub_runner.gd`: controlla Home, edifici, agenti, selezione, blocco dello zoom, copertura dello schermo, pan, notifiche, upgrade e apertura dei sistemi collegati.

Le suite automatiche richiedono l'argomento `-- --test-mode`: in questa modalità il world rimane in memoria e `save_game()` non legge né sovrascrive il salvataggio del giocatore.

## Salvataggio

Godot salva automaticamente in `user://riftward_save.json`. Il reset del world è disponibile dalle impostazioni nel gioco.

## Esportazione Windows

Il preset `export_presets.cfg` è già pronto. Per generare un `.exe`, installa gli Export Templates della stessa versione di Godot, quindi usa **Progetto → Esporta → Windows Desktop**.
