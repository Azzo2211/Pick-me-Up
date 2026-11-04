# REPARTI.md — Chi lavora su cosa in Riftward

Il progetto è diviso in reparti. Ogni reparto ha un ambito e delle cartelle/file di sua proprietà.
Più account e abbonamenti (Claude, Codex, Agent A) committano sullo stesso repository: questa tabella serve a non pestarsi i piedi.

## Regole

1. **Tocca solo le tue cartelle.** Se ti serve una modifica in un file di un altro reparto, chiedila a quel reparto (o in Production) invece di farla tu.
2. **Pull prima di ogni commit**: `git pull origin main`, poi commit, poi push. Se c'è un conflitto in un file non tuo, non risolverlo a mano: fermati e chiedi.
3. **File condivisi** (segnati sotto): modifiche piccole e mirate, mai riscritture. Un solo reparto alla volta.
4. Il progetto attivo è solo `godot/`. La vecchia versione web (`app.js`, `core.js`, ...) è storica: non si modifica.
5. Valgono sempre le regole di `AGENTS.md` (test dopo le modifiche, niente operazioni git distruttive, niente asset copiati da altre opere).

## Tabella dei reparti

| # | Reparto | Di cosa si occupa | Cartelle e file di proprietà | Account / abbonamento |
|---|---|---|---|---|
| 1 | **Programming + Technical Operations** | Codice di gioco, IA degli eroi, sistemi di combattimento, fisica, ottimizzazione, salvataggi, build, strumenti interni, test automatici, CI | `godot/scripts/game_state.gd`, `godot/scripts/battle/`, `godot/scripts/main.gd` (condiviso), `godot/project.godot`, `godot/export_presets.cfg`, `godot/tests/` (runner), `scripts/`, `.github/`, `Avvia_Riftward_Godot.cmd`, `Apri_Progetto_Godot.cmd`, `godot/README.md` | da definire |
| 2 | **Game Design + Narrative** | Meccaniche, regole, progressione, difficoltà, bilanciamento; storia, dialoghi, personaggi, missioni, mondo | `docs/GAME_VISION.md`, `docs/GAME_SYSTEMS.md`, `docs/NARRATIVE.md` (da creare), `godot/data/` (da creare: tabelle di bilanciamento, testi, missioni) | da definire |
| 3 | **Art & Animation** | Personaggi, ambientazioni, modelli 2D/3D, animazioni, effetti visivi, ritratti | `docs/ART_DIRECTION.md`, `godot/scripts/hub3d/` (base 3D, modelli, shader, animazioni), `godot/scripts/hero_portrait.gd`, `godot/assets/` tranne `fonts/` e `audio/` | da definire |
| 4 | **UI/UX Design** | Menu, HUD, inventario, pannelli, carte eroe, facilità d'uso | `godot/scripts/ui/`, `godot/assets/fonts/`, `godot/Main.tscn` (condiviso con Programming) | da definire |
| 5 | **Audio** | Musiche, effetti sonori, doppiaggio, implementazione audio | `godot/assets/audio/` (da creare), `godot/scripts/audio/` (da creare) | da definire |
| 6 | **Quality Assurance (QA)** | Test manuali, ricerca bug, verifica funzionalità, screenshot di controllo | `godot/tests/captures/`, `docs/QA.md` (da creare: bug aperti e checklist). I bug si segnalano al reparto proprietario, QA non corregge il codice degli altri | da definire |
| 7 | **Production** | Pianificazione, coordinamento dei reparti, priorità, scadenze | `REPARTI.md`, `docs/CURRENT_STATE.md`, `README.md`, `AGENTS.md`, `docs/DEVELOPMENT_RULES.md`, `docs/AGENT_A.md` | chat del progetto (coordinatore) |
| — | Marketing & Publishing | Trailer, community, distribuzione, lancio | più avanti | da definire |

## File condivisi: chi fa cosa

- **`godot/scripts/game_state.gd`**: il codice è di Programming. I numeri di bilanciamento (costi, probabilità, curve) li decide Game Design; quando saranno spostati in `godot/data/` Game Design potrà cambiarli senza toccare il codice.
- **`godot/scripts/main.gd`** e **`godot/Main.tscn`**: collegano base 3D, interfaccia e battaglia. Programming ne è responsabile; UI/UX può aggiungere i propri pannelli con modifiche piccole.
- **`godot/scripts/battle/battle_scene.gd`**: logica e IA di Programming; l'aspetto (effetti, animazioni) va chiesto ad Art & Animation, l'HUD a UI/UX.

## Fuori da tutti i reparti (non modificare)

- Versione web storica: `app.js`, `combat.js`, `core.js`, `index.html`, `styles.css`, `server.js`, `package.json`, `tests/core.test.js`, `SPEC_COMPLIANCE.md`.
- `tmp/`: materiale di riferimento estratto dai PDF.
