# Matrice di conformità alle specifiche (build Godot)

Stato della build Godot rispetto alla specifica di game design e alle decisioni sulla base.

| Area | Stato | Implementazione |
|---|---|---|
| Base come luogo fisico | Completo | Isola 3D: piazza aperta, cristallo, edifici veri, sentieri, vegetazione; i pannelli si aprono sopra la base. |
| Base Lv.1 | Completo | Addestramento rialzato, Dormitorio per ~5 eroi, Fusione a cupola blu, Portale sospeso collegato; niente Armeria/Laboratorio/Magazzino. |
| Crescita visiva | Completo | Livello N = N piani; cantieri solo dopo lo sblocco; la zona migliora con il livello base. |
| Eroi vivi nella base | Completo | Camminano sui sentieri, si allenano, riposano, aspettano la missione, partono dal portale. |
| Rarità 1★–7★ e cap | Completo | 10/20/30/50/70/99/120. |
| Evocazione | Completo | Normale 78/19/3; High-grade 93,5/5,5/1 con pity 70/100; Trascendente 98/1,8/0,2 (5★/6★/7★) dal Piano 20. |
| Leveling e addestramento | Completo | XP nel tempo (anche offline, max 8 h), XP da missione, level-up con crescita nascosta. |
| Fusione e promozione | Completo | Fusione 3→1 fino a 5★; promozioni con Pietre, 6★ dal Piano 30 e 7★ dal Piano 60. |
| Riposo, morale, ferite | Completo | Dormitorio a tempo; ferite moderate/gravi che guariscono riposando. |
| Party e formazione | Completo | 5 eroi, 2 Front / 2 Mid / 1 Rear, formazione consigliata automatica. |
| Combattimento | Completo | 20 tick/s, decisioni 5 Hz, punteggio bersagli, kiting, frecce, cure, paura, colpo ad area del boss. |
| Ordini del Master | Completo | Postura, alta minaccia, proteggi retro, tutto per tutto, ritirata. |
| Tipi di missione | Completo | Sterminio, Sopravvivenza, Esplorazione (3 punti), Difesa (faro), Guardiano. |
| Torre | Completo | Piani 1–5 scritti a mano, 6–100 generati dal seme del mondo; boss ogni 5 piani; retry senza reroll. |
| Permadeath | Completo | Morte definitiva, memoriale, nessuna resurrezione. |
| Economia | Completo | Oro, Gemme, Pietre, materiali con capienza; modalità sviluppo opzionale. |
| Strutture successive | Base | Armeria (forgia/equipaggia), Magazzino (capienza), Laboratorio (raffinazione), Alchimia (tonici). |
| Relazioni e legami | Roadmap | Campo dati presente, logica da sviluppare. |
| Online, classifiche | Roadmap | Non previsti nella build locale. |

## Parametri bloccati verificati dai test
- Party size 5; Torre fino a 100 piani.
- Statistiche base FOR / INT / STA / AGI.
- Costi evocazione 10.000 Oro e 500 Gemme.
- Nessuna energia account; nessuna resurrezione a pagamento; nessun reroll del piano al retry.
- Simulazione 20 tick/s, IA 5 Hz.
