# Riftward // The Last Ascent

Riftward è un vertical slice giocabile di un **autonomous squad management roguelite**: il Master gestisce roster, crescita, equipaggiamento, facilities, formazione e intel; durante le missioni gli eroi combattono in tempo reale attraverso una Utility AI e ricevono soltanto ordini macro limitati.

Il progetto è originale nel marchio, nel mondo, nei personaggi, nella UI e negli asset. Implementa i principi sistemici descritti nei documenti forniti senza riprodurre personaggi, nomi, testi o grafica dell'opera di riferimento.

## Versione Godot nativa

- Per giocare: doppio clic su `Avvia_Riftward_Godot.cmd`.
- Per vedere e modificare il progetto: doppio clic su `Apri_Progetto_Godot.cmd`.
- Il progetto da importare manualmente è `godot/project.godot`.

La build Godot include lo Shop gratuito e una modalità **DEV / QA**: risorse infinite, valori nascosti presentati in forma leggibile, sblocco dei contenuti, ripristino roster, generazione eroi, controllo pity e validazione del salvataggio.

## Avvio versione web precedente

Non servono installazioni o dipendenze esterne.

1. Apri PowerShell nella cartella del progetto.
2. Esegui:

   ```powershell
   node server.js
   ```

3. Apri [http://127.0.0.1:4173](http://127.0.0.1:4173).

In alternativa puoi aprire direttamente `index.html`, ma il server locale è consigliato.

## Contenuto giocabile

- Stream persistente di 5 piani: Subjugation, Survival, Exploration, Defense e Boss.
- Stage generati deterministicamente per world seed e salvati: il retry non rerolla il piano.
- Party da 5 in formazione 2 Front / 2 Mid / 1 Rear.
- 6 ruoli: Guardian, Vanguard, Lancer, Ranger, Mage e Support.
- Combattimento autonomo real-time: 20 tick/s, decisioni Utility AI a 5 Hz.
- Ordini Master con cooldown: postura, focus, protezione rear, tutto per tutto, estrazione.
- Munizioni reali per Ranger, skill, cura, morale, Fear, Fatigue e ferite.
- Permadeath a 0 HP con salvataggio immediato e tombstone nel Memoriale.
- HeroSeed unici, rarità nativa/corrente, potential nascosto, growth vector e personalità.
- Evocazione Normal e High-grade con costi, probabilità dichiarate e hard pity.
- Leveling, training, promotion, equipment, auto-equip, crafting e facilities.
- Relazioni pairwise, bonus Bond, memorie persistenti, event log e ledger economico.
- Salvataggio automatico in `localStorage`, recupero offline, import/export JSON e reset protetto.
- Layout adattivo desktop/mobile e preferenza `prefers-reduced-motion`.

## Comandi durante le missioni

| Tasto | Comando | Effetto |
|---|---|---|
| `1` | Postura | Cicla Avanza → Mantieni → Arretra |
| `2` | Alta minaccia | Prioritizza i bersagli pericolosi |
| `3` | Proteggi rear | Aumenta la priorità di intercettazione |
| `4` | Tutto per tutto | Aumenta la cadenza per 10 secondi |
| `X` | Estrazione | Tenta il disimpegno in 6 secondi |

## Test

```powershell
node tests/core.test.js
```

I test verificano determinismo, roster e party iniziali, pool/rates, hard pity, HeroSeed unici, stage persistenti, permadeath/tombstone, sblocco dei piani e reward scaling dei retry.

## Architettura

- `core.js` — stato del mondo, RNG deterministico, eroi, economia, progressione e risoluzione missioni.
- `combat.js` — simulazione real-time, Utility AI, obiettivi, rendering Canvas e ordini macro.
- `app.js` — UI, flussi di gioco, salvataggio, modali, eventi e integrazione del combattimento.
- `styles.css` — design system dark-fantasy/system UI e responsive layout.
- `index.html` — shell semantica e HUD missione.
- `tests/core.test.js` — regressione delle regole irreversibili e deterministiche.

## Nota sul perimetro

La specifica completa descrive 100 piani e sistemi live-service/server-authoritative. Questa build realizza la milestone **MVP/vertical slice** indicata nel GDD: il core loop completo è giocabile localmente, mentre World Raid, Ruins, Dimension Gate, Engraving, Synthesis e rarità Transcendent restano rappresentati nell'architettura/UI come sistemi post-slice.
