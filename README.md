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

Il progetto contiene già una base funzionante di sistemi che continuerà a essere ampliata verso il gioco completo, tra cui:

- party da 5 in formazione 2 Front / 2 Mid / 1 Rear;
- 6 ruoli: Guardian, Vanguard, Lancer, Ranger, Mage e Support;
- combattimento autonomo real-time con Utility AI;
- ordini Master macro e nessun controllo diretto completo degli eroi;
- stage deterministici e retry senza reroll del piano;
- permadeath e conseguenze persistenti;
- HeroSeed unici, rarità, crescita, personalità, morale e fatigue;
- evocazione, leveling, training, promotion, equipment e facilities;
- relazioni, bond, memorie ed event log;
- hub fisico Godot con edifici e agenti/eroi visibili.

I contenuti presenti oggi sono lo stato corrente dello sviluppo, non il limite finale del progetto. Nuovi piani, sistemi, facilities, contenuti e profondità di gioco verranno aggiunti progressivamente.

## Comandi durante le missioni

| Tasto | Comando | Effetto |
|---|---|---|
| `1` | Postura | Cicla Avanza → Mantieni → Arretra |
| `2` | Alta minaccia | Prioritizza i bersagli pericolosi |
| `3` | Proteggi rear | Aumenta la priorità di intercettazione |
| `4` | Tutto per tutto | Aumenta la cadenza per 10 secondi |
| `X` | Estrazione | Tenta il disimpegno |

## Sviluppo e test

La priorità è testare direttamente il progetto Godot e i runner presenti sotto `godot/tests/` quando pertinenti.

Il vecchio test JavaScript:

```powershell
node tests/core.test.js
```

può essere usato esclusivamente come controllo storico di logiche ereditate quando una modifica Godot dipende ancora da quelle regole.

## Architettura principale

- `godot/project.godot` — progetto Godot ufficiale.
- `godot/Main.tscn` — scena principale.
- `godot/scripts/game_state.gd` — stato e persistenza del gioco.
- `godot/scripts/base/` — hub, facilities, edifici, agenti e progressione della base.
- `godot/tests/` — runner e verifiche Godot.

La struttura può evolvere con il progetto: l'obiettivo non è conservare l'architettura attuale a ogni costo, ma migliorarla senza riscritture inutili o regressioni.

## Direzione del prodotto

Riftward non è più trattato come una demo o una vertical slice da completare e abbandonare. È il progetto di gioco principale, sviluppato progressivamente in Godot verso una versione completa. La documentazione, le decisioni di design più recenti e le richieste dell'utente hanno priorità sulle vecchie descrizioni del prototipo.
