# Matrice di conformità alle specifiche (build Godot)

Stato della build Godot rispetto alla specifica di game design e alle decisioni sulla base.

| Area | Stato | Implementazione |
|---|---|---|
| Base come luogo fisico | Completo | Borgo cinto da mura su un'isola sospesa: piazza col cristallo, strada ad anello, edifici veri, bosco, abitanti; i pannelli si aprono sopra la base. |
| Base Lv.1 | Completo | Addestramento rialzato, Dormitorio per ~5 eroi, Fusione a cupola blu, Portale sospeso collegato, Magazzino e Alchimia; niente Armeria/Laboratorio. |
| Crescita visiva | Completo | Livello N = N piani; cantieri solo dopo lo sblocco; con il livello base cambiano strade (terra → selciato), mura (palizzata → pietra → torri) e decorazioni. |
| Eroi vivi nella base | Completo | Camminano sui sentieri, si allenano, riposano, aspettano la missione, partono dal portale; nel tempo libero raggiungono gli amici e vanno dove li porta il carattere. |
| Rarità 1★–7★ e cap | Completo | 10/20/30/50/70/99/120. |
| Evocazione | Completo | Normale 78/19/3 (1–3★); High-grade 93,5/5,5/1 (3–5★) con pity 70/100; Trascendente 78/20/1,8/0,2 (4–7★) dal Piano 20; carte che si girano. |
| Leveling e addestramento | Completo | XP nel tempo (anche offline, max 8 h), XP da missione, level-up con crescita nascosta. |
| Fusione e promozione | Completo | Fusione 3→1 fino a 5★; promozioni con Pietre, 6★ dal Piano 30 e 7★ dal Piano 60. |
| Riposo, morale, ferite | Completo | Dormitorio a tempo; ferite moderate/gravi che guariscono riposando. |
| Party e formazione | Completo | 5 eroi, 2 Front / 2 Mid / 1 Rear, formazione consigliata automatica. |
| Combattimento | Completo | 20 tick/s, decisioni 5 Hz, punteggio bersagli, kiting, frecce, cure (mai fuoco amico), paura, colpo ad area del boss; arene per bioma, HUD con ritratti a sinistra e barra del boss. |
| Ordini del Master | Completo | Postura, alta minaccia, proteggi retro, tutto per tutto, ritirata. |
| Tipi di missione | Completo | Sterminio, Sopravvivenza, Esplorazione (3 punti, un eroe va a prenderli), Difesa (vinta se il faro resiste fino alla fine), Guardiano. |
| Torre | Completo | Piani 1–5 scritti a mano, 6–100 generati dal seme del mondo; boss ogni 5 piani; retry senza reroll. |
| Permadeath | Completo | Morte definitiva, memoriale con carte "Caduto al Piano N", nessuna resurrezione. |
| Economia | Completo | Oro, Gemme, Pietre, materiali con capienza; modalità sviluppo opzionale. |
| Strutture successive | Base | Armeria (forgia/equipaggia), Magazzino (capienza), Laboratorio (raffinazione), Alchimia (tonici); notifiche sugli edifici solo per novità reali. Potenziamenti a tempo (upgradeTime) non ancora presenti: il potenziamento è immediato. |
| Relazioni e legami | Completo | Affinità per ogni coppia di eroi (−100…+100) che cresce in missione, allenamento e riposo; tratti Socievole/Solitario; in battaglia gli amici danno forza e coraggio, i rivali lo tolgono; lutto e furia quando cade un amico; legami nella scheda eroe. |
| Online, classifiche | Roadmap | Non previsti nella build locale. |
| Stile grafico | Completo | Dark fantasy manhwa-ispirato (non copiato): interfaccia "Sistema" al neon, carte eroe, ritratti a pennello; renderer Forward+ con materiali in rilievo, ombre morbide e occlusione ambientale, alberi dipinti a foglie, personaggi con corpi e volti modellati; luce Giorno/Notte e Qualità grafica nelle Impostazioni. |

## Parametri bloccati verificati dai test
- Party size 5; Torre fino a 100 piani.
- Statistiche base FOR / INT / STA / AGI.
- Costi evocazione 10.000 Oro e 500 Gemme.
- Nessuna energia account; nessuna resurrezione a pagamento; nessun reroll del piano al retry.
- Simulazione 20 tick/s, IA 5 Hz.
