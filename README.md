# Riftward // The Last Ascent

**Riftward: The Last Ascent** è un autonomous squad-management roguelite in sviluppo come gioco completo. Il Master gestisce roster, crescita, equipaggiamento, facilities, formazione e intel; durante le missioni gli eroi combattono in tempo reale attraverso una Utility AI e ricevono soltanto ordini macro limitati.

Il progetto è originale nel marchio, nel mondo, nei personaggi, nella UI e negli asset. Può ispirarsi a principi sistemici e al feeling di opere di riferimento senza riprodurne personaggi, nomi, testi, UI, lore, grafica o asset protetti.

## Progetto attivo: Godot

Lo sviluppo attivo avviene esclusivamente nel progetto Godot:

- Per giocare: doppio clic su `Avvia_Riftward_Godot.cmd`.
- Per vedere e modificare il progetto: doppio clic su `Apri_Progetto_Godot.cmd`.
- Il progetto da importare manualmente è `godot/project.godot`.

La build Godot è la base ufficiale del gioco e deve ricevere tutte le nuove feature, correzioni, sistemi, UI e contenuti salvo diversa istruzione esplicita dell'utente.

## Codice web storico

Nel repository sono ancora presenti alcuni file della precedente implementazione web (`core.js`, `combat.js`, `app.js`, `index.html`, `styles.css`, `server.js`). Non rappresentano più una versione attiva del gioco e non devono essere sviluppati in parallelo. Possono essere consultati solo come riferimento storico o per recuperare logiche utili, quando questo aiuta lo sviluppo Godot.

## Stato attuale del gioco

La schermata principale **è la base**: un borgo cinto da mura su un'isola sospesa nel Rift, in 3D, con uno stile dark fantasy maturo ispirato ai manhwa (luce del crepuscolo, ombre morbide, nebbia, materiali in rilievo, alberi dipinti foglia per foglia), dove gli eroi vivono davvero.

- **Base Lv.1**: piazza aperta con il Cristallo del Nexus, strada ad anello, Centro di Addestramento rialzato, Dormitorio a graticcio per circa 5 eroi, Centro di Fusione (rotonda con cupola e luce blu), Magazzino, Alchimia, grande Portale sospeso su una rupe collegata da un ponte. Bosco tutto intorno, palizzata, laghetto, cascata e scogliere di roccia.
- **Crescita visibile**: livello N = N piani. Le strutture non sbloccate non esistono; quando la base sale di livello compare il cantiere, poi l'edificio. Anche il borgo migliora: strade di terra → selciato, palizzata → mura di pietra → torri, lampioni, bancarelle, fontana, statue, lanterne fluttuanti.
- **Eroi vivi** con proporzioni reali, corpi modellati e volti: camminano per le strade insieme agli abitanti, si allenano nel cortile, entrano nel Dormitorio a riposare, aspettano la missione sulla strada del Portale; nel tempo libero raggiungono gli amici e vanno dove li porta il carattere. Si toccano per aprire la loro scheda.
- **Legami tra eroi**: crescono combattendo, allenandosi e riposando insieme; in missione gli amici si danno forza e coraggio, i rivali no; se cade un amico arrivano lutto o furia.
- **Pannelli sopra la base** invece di schermate a elenco: Addestramento, Dormitorio, Fusione/Promozione, Portale (missione e squadra), Cristallo (evocazione ed espansione), Armeria, Magazzino, Laboratorio, Alchimia.
- **Sistemi**: economia reale (modalità sviluppo opzionale), addestramento e riposo nel tempo anche offline, livelli e cap per rarità 1★–7★, pool trascendente 6★/7★, fusione, promozioni endgame, Torre fino a 100 piani, ferite, legami, permadeath.
- **Interfaccia "Sistema" neon** sopra il mondo fantasy: pannelli quasi neri con cornici sottili e accenti neon, eroi come carte con cornice per rarità (6★ e 7★ animate), evocazione come evento a schermo intero, roster, memoriale dei caduti, ritratti in stile manhwa.
- **Missioni** in 3D con gli stessi personaggi in arene diverse per bioma: IA autonoma, solo ordini generali del Master, ritratti e vita della squadra a sinistra, barra del guardiano in alto.
- **Luce della base** a scelta nelle Impostazioni: Crepuscolo, Giorno o Notte.
- **Qualità grafica** nelle Impostazioni: Alta, Media o Bassa (per i PC meno potenti).

I contenuti presenti sono lo stato corrente dello sviluppo, non il limite finale del progetto.

## Comandi durante le missioni

| Tasto | Comando | Effetto |
|---|---|---|
| `1` | Postura | Cicla Avanza → Mantieni → Arretra |
| `2` | Alta minaccia | Prioritizza i bersagli pericolosi |
| `3` | Proteggi retro | Le prime linee intercettano chi minaccia la retroguardia |
| `4` | Tutto per tutto | Aumenta la cadenza per 10 secondi |
| `X` | Ritirata | Estrazione dopo 6 secondi (missione non completata) |

## Sviluppo e test

Dalla cartella del repository (sostituisci `godot` con il percorso dell'eseguibile Godot 4.7):

```powershell
godot --headless --path godot -s res://tests/test_runner.gd -- --test-mode
godot --headless --path godot -s res://tests/ui_smoke_runner.gd -- --test-mode
godot --path godot -s res://tests/visual_capture_runner.gd -- --test-mode
```

La prima suite controlla le regole di gioco, la seconda apre tutta l'interfaccia e completa una missione, la terza salva screenshot in `godot/tests/captures/`.

## Architettura principale

- `godot/scripts/game_state.gd` — regole, economia, progressione, legami, salvataggio (v4, con migrazione dei vecchi salvataggi).
- `godot/scripts/main.gd` — schermata principale: base, HUD, pannello laterale, finestre, flusso missione.
- `godot/scripts/ui/` — tema, widget e contenuti dei pannelli.
- `godot/scripts/hub3d/` — base 3D: isola, edifici procedurali, eroi, camera, shader dei materiali.
- `tools/gen_textures.py` — genera le texture di foglie, aghi ed erba in `godot/assets/textures/` (Python con numpy e Pillow).
- `godot/scripts/battle/` — missione in tempo reale.
- `docs/` — visione, sistemi, direzione artistica, stato corrente.

## Direzione del prodotto

Riftward non è più trattato come una demo o una vertical slice da completare e abbandonare. È il progetto di gioco principale, sviluppato progressivamente in Godot verso una versione completa. La documentazione, le decisioni di design più recenti e le richieste dell'utente hanno priorità sulle vecchie descrizioni del prototipo.
