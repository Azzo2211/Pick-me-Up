# ART_DIRECTION.md

## Visual target
Riftward is a mature anime-isekai dark fantasy, inspired by the feeling of Korean webtoons/manhwa about summoned heroes and towers, never copying them. It must not read as a children's game: no chibi proportions, no candy pastels, no toy-like UI. It must not read as grimdark either: warm light, rich dusk colours and lived-in places.

## Rendering style (3D)
- Real-time 3D generated in code, semi-realistic low-poly: procedural shaders give every surface a real material (stone blocks with mortar and moss, weathered plaster, timber grain, slate/shingle/thatch roofs, cobbles, dirt, grass, rock strata). UVs are in world units so patterns keep their scale.
- Lighting: golden-hour dusk by default (warm low sun, cool fill, indigo sky with stars, banked clouds), real directional shadows, depth and height fog, mist sea under the island, soft glow on emissive windows, lamps, runes and crystals. Players can switch the base to Day or Night in Settings.
- Characters have real human proportions (~1.8 m, 1 world unit = 2 m), role-specific clothing (plate and tabard, leather and pauldrons, hooded cloaks, long robes, capes from 4★), real weapons. Enemies: hooded raiders and archers, Rift wolves, ogre brutes, stone golem guardians with glowing runes.
- Monsters and motion (2026-11-10, owner request). Each monster has its own silhouette and its own movement, never a recoloured human: the Rift hound is a lean wolf with a mane, hocked hind legs, an opening jaw and Rift crystals on its back (trot or gallop by speed, leaping bite); the brute is a hunched ogre with huge shoulders, long arms, tusks and an iron-bound club; the Guardian is a colossus of boulders with oversized forearms, a glowing core and cracks in the floor colour. Brute and Guardian share heavy poses (`_animate_heavy`: swaying stomp, overhead smash, knees buckle then fall). Heroes and raiders strike with the whole body (wind-up, step, weight forward, planted feet), their gait follows the real speed (walk, jog, sprint: no sliding feet) and they recoil when hit. Damage still lands when the attack starts, so the visible impact sits at about a third of the animation. Check every change with side-view strips (idle, step, wind-up, hit, fall), not single stills.
- User-made 3D bodies (2026-11-05): a painted glb from the owner replaces the kit body for that outfit (first: male Guard, `godot/assets/characters/user/guard.glb`). Rig it with `tools/character_kit/import_user_model.py` (same 13 bones as the kit, at the model's own T-pose joints; arm mask and arm depth in the vertex colour). In game `CharacterModel` turns the T-pose into the rig pose at runtime (`_user_rest_fix`), draws it with `painted_model.gdshader` (painted light kept, soft real light, arms drawn in front of the cape) and `painted_outline.gdshader`. The hero's own kit hair (cut and colour) goes on the bald painted head, fitted per model in `CharacterModel.user_hair_fit`. Second model (2026-11-05): the Warrior, built by `tools/character_kit/sheet_to_model.py` from the owner's turntable sheet (front, side and back views: depth comes from the side profiles, so it is not a bas-relief), used by Vanguard and Lancer while Guardian keeps the tabard Guard (`CharacterModel.USER_MODELS`); its painted hair is tinted with the hero's hair colour (texture alpha = hair mask). Women with that outfit keep the kit body. Limits: the source is an image projection, so it is thin from the side and every Guard has the same painted face.
- Performance: each building is one batched mesh (one surface per material); trees, bushes, rocks and grass use MultiMesh; few real lights, the rest are emissive surfaces and additive light pools on the ground.

## UI style (2D) — "mixed" direction
The 3D world stays fantasy; the interface is the System that summoned the Master (user decision, 2026-10-29, based on the Pick Me Up visual direction board).
- Near-black blue panels, thin neon borders, cut corners and technical corner brackets. Accent colour by system: cyan for base/system windows, magenta for summoning, amber for resources and key actions, red for danger.
- Fonts: Oxanium for titles and headings, Exo 2 for text (both SIL OFL, licences in `godot/assets/fonts`). Cinzel/Alegreya files are kept but no longer used by the UI.
- Hero cards: neon frame in the rarity colour, rarity tag on top (COMMON, TRAINED, RARE, ELITE, EPIC, LEGEND, TRANSCEND), portrait, stars and name plate. The frame grows with rarity: 1★–2★ single line, 3★ double, 4★–5★ corner brackets and halo, 6★ pulsing halo with rising embers, 7★ animated iridescent frame with sparkles. 6★ and 7★ must be recognisable in half a second. Fallen heroes keep a grey card with "Caduto al Piano N".
- L'evocazione è un evento a schermo intero: il Sistema strappa il Rift con uno squarcio verticale e fulmini (niente cerchi, decisione del proprietario 2026-11-05, #16), il colore della scena vira verso la rarità migliore prima che compaia un eroe (6★/7★ con un avviso del Sistema), un lampo, poi le carte escono dallo squarcio e si girano una alla volta. "Salta" rivela tutto subito.
- **Animazioni di evocazione e uccisioni (2026-11-05, #15).** Evocazione: durante la carica il varco risucchia particelle; poi esplode con lampo, onda d'urto, schegge e scossa, e le carte escono dal varco volando al loro posto. Ogni carta si rivela in modo diverso per rarità: 1★–3★ veloci con poche scintille; 4★ attesa breve, fascio di luce verticale e aura; 5★ attesa più lunga (la carta trema e si carica), raggi, lampo dorato e stelline; 6★–7★ lampo forte e scossa, e il nome compare in alto. Le carte da 4★ in su restano circondate da un'aura. Sulle carte anche 4★ e 5★ si animano piano: riflesso che passa ogni pochi secondi, bagliori agli angoli (4★), polvere d'oro (5★). Battaglia: scintille sui colpi, numeri che nascono grandi e si assestano (i critici tremano), nemici uccisi che esplodono in schegge del Rift e poi si dissolvono in cenere; campioni e Guardiano con scritta, rallentatore e scossa; eroe caduto con rallentatore, bordo rosso, colonna di luce, particelle che salgono e scritta "CADUTO". Gli effetti non toccano la simulazione (generatore casuale separato).
- **Ritratti (2026-11-05, colori rifatti 2026-11-08).** Sulle carte ci sono i ritratti dipinti dalle immagini del proprietario (`godot/assets/portraits/`, sua scelta), con capelli e occhi del colore del generatore. Iridi: si ricolorano solo nei 121 volti controllati a occhio, ingranditi (iride intera, tinta nuova sulla luminosità dipinta: niente puntini che brillano); anche un colore acceso come l'oro resta un occhio, con pupilla scura al centro e bordo dell'iride più scuro (blu della maschera); nei volti di tre quarti l'occhio lontano, mezzo nascosto da palpebra o naso, resta dipinto e si colora solo quello vicino (correzioni a mano in `EYE_FIX`); gli altri volti tengono gli occhi dipinti. Capelli: solo tra colori vicini (`PortraitLibrary.HAIR_COMPAT`, per esempio nero → castano, blu o viola; biondo, argento e bianco → colori chiari e pastello), tenendo ombre e pennellate del disegno; nero → biondo o bianco verrebbe grigio, quindi resta il colore dipinto e la scelta del volto evita questi casi. Solo nei 67 volti la cui maschera dei capelli è stata controllata a occhio: i 32 che coloravano bende, colletti, pellicce, occhiali, orecchini grandi o pelle, o lasciavano metà capelli col colore vecchio (`BAD_HAIR` in `portrait_masks.py`), tengono i capelli dipinti e vanno solo a eroi con quel colore. Maschere e catalogo: `tools/character_kit/portrait_masks.py`. Il busto disegnato in codice resta solo di riserva.

## Hub direction
The base is a walled hamlet on a floating island in the Rift:
- an open plaza with the Nexus crystal on a stone pedestal at the centre;
- a ring street around the plaza, buildings facing the street, short paved aprons to each door;
- a town wall that grows with the base, forest and meadows between the wall and the cliff edge, a pond whose stream falls off the island;
- the Mission Gate on its own floating rock, a monumental stone arch with a dark swirling rift, reached by a chained stone bridge;
- heroes and a few villagers visibly living there;
- **isole della base** (Base Lv.6, 8 e 10; `godot/scripts/hub3d/hub_islands.gd`): zolle sospese ai lati e dietro l'isola principale (Campi a est, Dimore a ovest, Santuario a nord-ovest e più in alto), ognuna con la sua scogliera e un ponte di pietra (per il Santuario una scalinata). Dalla strada del Portale un sentiero gira fuori dalle mura fino ai ponti. La disposizione del borgo resta quella di sempre: le isole si aggiungono. Quando ci sono isole la camera iniziale si allontana per inquadrarle tutte.
- **crescita dell'isola e isolotti** (`godot/scripts/hub3d/hub_outposts.gd`, `HubWorld.ISLAND_GROWTH`): dal Lv.1 al Lv.5 l'isola principale si allarga (raggio medio 18,6 → 21,2; scogliera, ponte del Portale e laghetto seguono il bordo). Ogni livello aggiunge anche un isolotto con ponte di corda, solo scenografia: Vedetta (Lv.2, torre di guardia), Frutteto (Lv.3, alberi da frutto e arnie), Sorgente (Lv.4, laghetto e cascata), Miniera (Lv.5, cristalli e carrello), Faro (Lv.7, fascio di luce che ruota). La camera iniziale si allontana un po' per ogni isolotto.

Avoid:
- chibi heroes, pastel candy palettes, cartoon outlines;
- oversized mega-castle silhouettes at early levels;
- facilities represented only as abstract cards when a physical world representation is expected;
- showing unavailable buildings as fully constructed locked structures;
- copying exact compositions, architecture, UI, symbols, names or assets from reference IP.

## Facility progression
Decisione del proprietario (2026-11-05, #16): gli edifici arrivano al Lv.10 senza diventare torri di piani impilati.
- **Lv.1–3**: ogni livello aggiunge un piano (o l'equivalente: le baracche del cortile, i tamburi della rotonda, gli anelli e le pietre del Portale). Il Lv.1 è modesto.
- **Lv.4**: il pianterreno viene rifatto in pietra con i cantonali chiari; lanterne alla porta. Addestramento: parapetto merlato; Fusione: peristilio di colonne attorno alla rotonda; Alchimia: contrafforti e ballatoio di legno; Armeria: scudi in facciata; Portale: obelischi con rune.
- **Lv.5**: una torretta su un angolo posteriore, più alta del colmo. Laboratorio: torre dell'orologio; Magazzino: silo; Addestramento e Armeria: torri quadrate; Fusione: pinnacoli con la punta luminosa; Alchimia: torretta addossata; Portale: secondo anello che gira al contrario.
- **Lv.6**: seconda torretta, abbaini, cresta di ferro sul colmo, pinnacoli dorati. Fusione: costoloni d'oro sulla cupola; Portale: due guardiani di pietra.
- **Lv.7**: rune azzurre attorno all'edificio, sulle torri e ai lati della porta. Addestramento e Portale: cerchio di rune a terra.
- **Lv.8**: cristalli del Nexus sospesi attorno alla torre. **Lv.9**: aureola di luce che gira attorno al tetto della torre. **Lv.10**: il tetto della torre diventa una guglia con anelli d'oro, con un grande cristallo sospeso sopra e stendardi d'oro.
- Per controllare un edificio a tutti i livelli: `godot/tests/building_lineup_runner.gd` (un'immagine per livello).

## Base level progression (whole area)
| Base | Streets | Wall | Details |
|---|---|---|---|
| 1 | narrow dirt tracks, earthen plaza with a stone ring | wooden palisade with a timber gate | torches, well, vegetable plots, thatch roofs |
| 2 | paved plaza and spokes | palisade with a stone gatehouse | iron lamp posts, market stall, shingle roofs |
| 3 | every street cobbled | low stone curtain wall | banners, three stalls, fountain, slate roofs |
| 4 | — | corner towers with blue rune lights | statues along the gate road |
| 5 | — | gilded banners | floating lanterns, aurora in the sky |
| 6 | sentiero fuori dalle mura fino al ponte | — | Isola dei Campi: arena all'aperto, campi di grano, mulino a vento, fienile |
| 7 | lampioni a rune (cristallo azzurro in cima) | — | anelli di pietra sospesi attorno al Cristallo |
| 8 | — | — | Isola delle Dimore: case degli eroi, piazzetta con fontana e panchine, campanile |
| 9 | sentiero esterno lastricato | fuochi azzurri sopra le torri | lanterne sospese sopra i ponti e le isole |
| 10 | scalinata sospesa fino al Santuario | — | Santuario del Nexus: tempio rotondo a cielo aperto con un frammento gigante del Nexus |

## Specific Level 1 notes
- Training Center: raised stone yard with stairs, dummies, weapon racks, target and a small barracks.
- Dormitory: timber-framed longhouse for about five heroes, benches by the door for the injured.
- Merging Center: enclosed classical rotunda, copper dome with a glass lantern, blue light from the windows, no fences.
- Mission Gate: present and large, suspended on its own rock, connected by the bridge.
- Workshop, Armory, Warehouse, Alchemy: absent until unlocked; then a construction site; then the building.
- Central plaza: open public space, not a facility. The crystal is a clickable monument (summon and base expansion).

## UI relationship
UI supports the world rather than replacing it. Clicking a physical facility opens a side panel over the base; the player's first mental model is "I am interacting with a place in my base".
