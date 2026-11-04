# Riftward — progetto Godot

Requisito: Godot 4.7.1 o compatibile (renderer Compatibility).

## Giocare

Dalla cartella principale fai doppio clic su `Avvia_Riftward_Godot.cmd`.

## Aprire nell'editor

Fai doppio clic su `Apri_Progetto_Godot.cmd`. In alternativa, nel Project Manager di Godot seleziona **Importa** e apri questo file `project.godot`.

## Come si gioca

- **La base è la schermata principale.** Trascina per spostare la vista, rotellina (o pizzico) per lo zoom, **Vista base** per tornare alla visuale intera.
- **Tocca un edificio** per entrarci: la camera si avvicina e il pannello si apre a destra, con la base sempre visibile. **Esc** chiude pannelli e finestre.
- **Tocca un eroe** per aprire la sua scheda.
- **Centro di Addestramento**: assegna eroi; guadagnano esperienza nel tempo, anche a gioco chiuso (fino a 8 ore).
- **Dormitorio**: recuperano stanchezza e morale e guariscono le ferite.
- **Centro di Fusione**: fondi tre eroi della stessa rarità o promuovi chi ha raggiunto il livello massimo.
- **Portale delle Missioni**: scegli il piano e la squadra (2 in prima linea · 2 al centro · 1 in retroguardia), poi parti. In missione dai solo ordini generali; un eroe che cade muore per sempre.
- **Impostazioni**: luce della base (Crepuscolo, Giorno, Notte), modalità sviluppo, nuovo mondo.
- **Cristallo del Nexus** (al centro della piazza): evoca nuovi eroi ed espandi la base. Ogni livello base permette un piano in più agli edifici e apre nuovi cantieri (Armeria, Magazzino, Laboratorio, Alchimia).

## Modalità sviluppo

In **Impostazioni** puoi attivare la modalità sviluppo: risorse infinite, valori nascosti visibili, requisiti di progressione ignorabili, eroi 5★ di prova e avanzamento del tempo. Di base è spenta.

## Test

```text
godot --headless --path . -s res://tests/test_runner.gd -- --test-mode        # regole di gioco
godot --headless --path . -s res://tests/ui_smoke_runner.gd -- --test-mode    # interfaccia + missione completa
godot --headless --path . -s res://tests/balance_probe_runner.gd -- --test-mode  # simulazione bilanciamento
godot --path . -s res://tests/visual_capture_runner.gd -- --test-mode         # screenshot in tests/captures
godot --path . -s res://tests/battle_preview_runner.gd -- --test-mode         # screenshot battaglie
godot --path . -s res://tests/hub_preview_runner.gd -- --test-mode --base5   # anteprime della base (--base2/3/5, --light=day|night)
godot --path . -s res://tests/character_probe_runner.gd -- --test-mode       # fila di personaggi
```

## Grafica

Tutta la grafica 3D è generata dal codice (geometria e shader procedurali, nessun asset esterno). L'interfaccia usa i font Oxanium ed Exo 2 (licenza SIL Open Font License, in `assets/fonts`).
