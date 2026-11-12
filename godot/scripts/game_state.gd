extends Node
class_name RiftwardState

## Stato persistente del gioco (autoload "GameState").
## Contiene world, roster, base, torre, economia e tutte le regole di progressione.
## La UI e la base 3D leggono da qui e chiamano solo le funzioni pubbliche.

signal state_changed
signal toast_requested(title: String, message: String, tone: String)
signal hero_leveled(hero_id: String, level: int)
## Emesso quando passa il tempo della base (addestramento, riposo) senza azioni del giocatore.
signal time_ticked

const CharacterGeneratorScript := preload("res://scripts/characters/character_generator.gd")
const HeroLookScript := preload("res://scripts/characters/hero_look.gd")
const SAVE_PATH := "user://riftward_save.json"
const SAVE_VERSION := 3
const PARTY_SIZE := 5
const MAX_FLOOR := 100
const OFFLINE_CAP_HOURS := 8.0
const TICK_SECONDS := 1.0
const AUTOSAVE_SECONDS := 20.0

# --- Rarità ------------------------------------------------------------------
## Livello massimo per rarità. Regola del proprietario (2026-11-12): il livello massimo è 99.
const RARITY_CAPS := {1: 10, 2: 20, 3: 30, 4: 50, 5: 70, 6: 99, 7: 99}
const MAX_LEVEL := 99
const RARITY_NAMES := {1: "Comune", 2: "Non comune", 3: "Raro", 4: "Epico", 5: "Leggendario", 6: "Mitico", 7: "Trascendente"}
## Pietre di promozione richieste per salire dalla rarità indicata alla successiva.
## La promozione arriva al massimo a 6★: la 7ª stella si ottiene solo evocando (regola del proprietario).
const PROMOTION_STONES := {1: 1, 2: 2, 3: 3, 4: 5, 5: 12}
const PROMOTION_MAX_RARITY := 6
## Piano minimo già superato per promuovere dalla rarità indicata (la 6★ è endgame).
const PROMOTION_FLOOR_GATE := {5: 30}

# --- Evocazione --------------------------------------------------------------
const SUMMON_POOLS := {
	"normal": {"name": "Richiamo del Nexus", "currency": "gold", "cost": 10000, "rates": [[1, 78.0], [2, 19.0], [3, 3.0]]},
	"high": {"name": "Giuramento Astrale", "currency": "gems", "cost": 500, "rates": [[3, 93.5], [4, 5.5], [5, 1.0]]},
	"transcendent": {"name": "Eco Trascendente", "currency": "gems", "cost": 4000, "rates": [[4, 78.0], [5, 20.0], [6, 1.8], [7, 0.2]], "unlock_floor": 20},
}
const HIGH_SOFT_PITY := 70
const HIGH_HARD_PITY := 100

# --- Ruoli -------------------------------------------------------------------
const ROLES := {
	"Guardian": {"line": "Front", "weights": [0.31, 0.04, 0.48, 0.17], "skill": "Scudo d'Egida", "icon": "G", "label": "Guardiano"},
	"Vanguard": {"line": "Front", "weights": [0.47, 0.04, 0.28, 0.21], "skill": "Fendente Travolgente", "icon": "V", "label": "Avanguardia"},
	"Lancer": {"line": "Mid", "weights": [0.39, 0.04, 0.27, 0.30], "skill": "Affondo Inchiodante", "icon": "L", "label": "Lanciere"},
	"Ranger": {"line": "Rear", "weights": [0.20, 0.08, 0.17, 0.55], "skill": "Colpo Mirato", "icon": "R", "label": "Ranger"},
	"Mage": {"line": "Rear", "weights": [0.05, 0.58, 0.18, 0.19], "skill": "Rete di Braci", "icon": "M", "label": "Mago"},
	"Support": {"line": "Mid", "weights": [0.08, 0.46, 0.30, 0.16], "skill": "Cura", "icon": "S", "label": "Supporto"},
}
## Slot di formazione: 2 Front, 2 Mid, 1 Rear.
const FORMATION_LINES := ["Front", "Front", "Mid", "Mid", "Rear"]

const FIRST_NAMES := ["Aella", "Bren", "Cael", "Doria", "Edrin", "Fara", "Galen", "Hesta", "Iven", "Kaia", "Loran", "Mira", "Neris", "Orin", "Pyria", "Quill", "Rhea", "Soren", "Tavia", "Ulric", "Veya", "Wren", "Yara", "Zephan"]
const LAST_NAMES := ["Ashfall", "Blackmere", "Cinder", "Dawnward", "Emberlain", "Frost", "Greywake", "Hollow", "Ironwood", "Jade", "Kestrel", "Lightfoot", "Mourn", "Nightglass", "Oakshield", "Pyre", "Rook", "Stoneveil", "Thorn", "Vale", "Yarrow", "Zephyr"]
const ORIGINS := ["Marche di Veyra", "Città sommersa di Oros", "Cintura mineraria di Khel", "Nomadi di Sable", "Isole di vetro", "Bosco di Talren", "Fortezza di Ardent", "Archivio di Myr"]
const PROFESSIONS := ["Fabbro", "Conciatore", "Cartografo", "Erborista", "Carpentiere", "Archivista", "Cuoco", "Minatore"]

# --- Popolani (1★ e 2★) --------------------------------------------------------
## Fino a 2★ il Nexus richiama persone comuni con un mestiere: il giocatore sceglie
## la classe, e loro consigliano quella che si adatta meglio a ciò che sanno fare.
const COMMONER_MAX_RARITY := 2
## mestiere → aspetto del foglio (guard, merchant, scholar, villager), categoria del
## generatore personaggi (colori), pesi [for, int, sta, agi], classe a cui pende, frase.
const COMMONER_JOBS := {
	"Contadino": {"look": "villager", "prop": "pitchfork", "category": "Villager", "weights": [0.34, 0.06, 0.40, 0.20], "lean": "Lancer", "tool": "Forcone", "line": "Ho zappato la terra da quando ero bambino."},
	"Fabbro": {"look": "villager", "prop": "hammer", "category": "Blacksmith", "weights": [0.47, 0.06, 0.35, 0.12], "lean": "Vanguard", "tool": "Martello da forgia", "line": "Ho passato anni all'incudine."},
	"Carpentiere": {"look": "villager", "prop": "axe", "category": "Villager", "weights": [0.38, 0.12, 0.28, 0.22], "lean": "Lancer", "tool": "Ascia da carpentiere", "line": "So alzare un tetto e tenere ferma una trave."},
	"Minatore": {"look": "villager", "prop": "pickaxe", "category": "Villager", "weights": [0.40, 0.04, 0.44, 0.12], "lean": "Guardian", "tool": "Piccone", "line": "Sotto terra ho imparato a resistere a tutto."},
	"Conciatore": {"look": "villager", "prop": "knife", "category": "Villager", "weights": [0.28, 0.12, 0.30, 0.30], "lean": "Ranger", "tool": "Coltello da concia", "line": "Lavoro le pelli che portano i cacciatori."},
	"Cuoco": {"look": "villager", "prop": "ladle", "category": "Villager", "weights": [0.22, 0.26, 0.32, 0.20], "lean": "Support", "tool": "Mestolo di ferro", "line": "Ho sfamato una locanda intera ogni sera."},
	"Cacciatore": {"look": "villager", "prop": "bow", "category": "Ranger", "weights": [0.20, 0.08, 0.18, 0.54], "lean": "Ranger", "tool": "Arco da caccia", "line": "Seguivo le tracce nei boschi per giorni."},
	"Mercante": {"look": "merchant", "prop": "staff", "category": "Merchant", "weights": [0.12, 0.42, 0.20, 0.26], "lean": "Mage", "tool": "Bastone da viaggio", "line": "Ho contato monete e letto contratti in dieci città."},
	"Bottegaio": {"look": "merchant", "prop": "pouch", "category": "Merchant", "weights": [0.16, 0.34, 0.30, 0.20], "lean": "Support", "tool": "Bilancia di ottone", "line": "Tenevo una bottega e conoscevo tutti nel quartiere."},
	"Locandiere": {"look": "merchant", "prop": "club", "category": "Merchant", "weights": [0.30, 0.16, 0.38, 0.16], "lean": "Guardian", "tool": "Randello da oste", "line": "Nella mia locanda le risse finivano in fretta."},
	"Archivista": {"look": "scholar", "prop": "book", "category": "Scholar", "weights": [0.06, 0.58, 0.18, 0.18], "lean": "Mage", "tool": "Tomo rilegato", "line": "Ho copiato a mano più libri di quanti ne ricordi."},
	"Cartografo": {"look": "scholar", "prop": "map", "category": "Scholar", "weights": [0.10, 0.42, 0.16, 0.32], "lean": "Ranger", "tool": "Compasso d'ottone", "line": "Ho disegnato mappe di posti che nessuno visitava."},
	"Erborista": {"look": "scholar", "prop": "sickle", "category": "Cleric", "weights": [0.08, 0.48, 0.26, 0.18], "lean": "Support", "tool": "Falcetto d'argento", "line": "Conosco ogni erba che cura e ogni erba che uccide."},
	"Accolito": {"look": "scholar", "prop": "staff", "category": "Cleric", "weights": [0.08, 0.46, 0.32, 0.14], "lean": "Support", "tool": "Bastone del tempio", "line": "Servivo al tempio e assistevo i malati."},
	"Guardia cittadina": {"look": "guard", "prop": "club", "category": "Tank", "weights": [0.38, 0.04, 0.38, 0.20], "lean": "Guardian", "tool": "Mazza da ronda", "line": "Facevo la ronda sulle mura della mia città."},
}
## Come ogni popolano motiva la classe che consiglia.
const ROLE_PITCH := {
	"Guardian": "Reggo i colpi meglio di chiunque: fammi Guardiano e starò davanti agli altri.",
	"Vanguard": "Ho braccia forti: mettimi in prima linea come Avanguardia.",
	"Lancer": "Ho forza e gambe buone: con una lancia in mano farei il Lanciere.",
	"Ranger": "Ho occhio e passo leggero: dammi un arco e farò il Ranger.",
	"Mage": "Imparo in fretta e ho la testa per i libri: potrei studiare da Mago.",
	"Support": "So prendermi cura degli altri: lasciami fare il Supporto.",
}
## Statistiche principali (regole del proprietario): chiave interna → [sigla, nome].
## Le chiavi restano quelle dei salvataggi: "sta" è HP (punti vita), "agi" è DEX (destrezza).
const STAT_LABELS := {"str": ["STR", "Forza"], "int": ["INT", "Intelligenza"], "sta": ["HP", "Punti vita"], "agi": ["DEX", "Destrezza"]}
const STAT_ORDER := ["str", "int", "sta", "agi"]
const TRAITS := ["Nervi saldi", "Istinto protettivo", "Passo leggero", "Tenace", "Occhio clinico", "Testardo", "Frugale", "Socievole", "Solitario", "Mano ferma", "Memoria lunga"]

# --- Abilità particolari --------------------------------------------------------
## Regola del proprietario (2026-11-12): le abilità possono essere comuni o uniche, alcuni
## eroi nascono senza abilità particolari, altri le hanno dall'evocazione. La tecnica della
## classe (ROLES[role].skill) è a parte: ce l'hanno tutti ed è sempre la prima della lista.
## Effetti: hp/atk/def = +% a vita, attacco (anche magia) e difesa; acc/eva/crit = punti di
## precisione, schivata e critico; heal = +% alle cure che dà; fear = quanto prima gli passa
## la paura (1 = non ne ha). Al livello 2 l'effetto vale ×1,5, al livello 3 ×2.
## `roles`: solo per queste classi (le cure servono solo a chi cura).
const SKILLS := {
	"Disciplina da Campo": {"kind": "common", "text": "Tiene la formazione sotto pressione: la paura gli passa prima.", "fear": 0.35},
	"Pelle dura": {"kind": "common", "text": "Incassa meglio degli altri.", "hp": 0.08},
	"Braccio pesante": {"kind": "common", "text": "Colpi più pesanti.", "atk": 0.06},
	"Occhio fino": {"kind": "common", "text": "Mira meglio e trova i punti deboli.", "acc": 6.0, "crit": 2.0},
	"Riflessi pronti": {"kind": "common", "text": "Schiva più spesso.", "eva": 4.0},
	"Guardia alta": {"kind": "common", "text": "Si copre meglio.", "def": 0.08},
	"Mani svelte": {"kind": "common", "text": "Cure più efficaci.", "heal": 0.15, "roles": ["Support"]},
	"Cuore d'acciaio": {"kind": "unique", "text": "Non conosce la paura e non arretra.", "fear": 1.0, "def": 0.05},
	"Lama del giuramento": {"kind": "unique", "text": "Colpi devastanti.", "atk": 0.12, "crit": 3.0},
	"Bastione vivente": {"kind": "unique", "text": "Un muro di carne e acciaio.", "hp": 0.15, "def": 0.10},
	"Occhio del falco": {"kind": "unique", "text": "Non sbaglia quasi mai un colpo.", "acc": 12.0, "crit": 5.0},
	"Mani di luce": {"kind": "unique", "text": "Le sue cure salvano vite.", "heal": 0.30, "hp": 0.05, "roles": ["Support"]},
	"Passo d'ombra": {"kind": "unique", "text": "Sparisce quando lo colpiscono.", "eva": 8.0, "atk": 0.05},
}
const SKILL_MAX_LEVEL := 3
## Abilità particolari al massimo per eroe (la tecnica di classe non conta).
const SKILL_SLOTS := 3
## Abilità alla nascita: più la rarità è alta, più è facile averne, ma non è una regola fissa.
## NONE = probabilità di nascere senza abilità comuni; SECOND = di averne una seconda;
## UNIQUE = di avere anche un'abilità unica.
const BORN_SKILL_NONE := {1: 0.75, 2: 0.6, 3: 0.4, 4: 0.25, 5: 0.15, 6: 0.1, 7: 0.05}
const BORN_SKILL_SECOND := {1: 0.0, 2: 0.05, 3: 0.12, 4: 0.22, 5: 0.32, 6: 0.42, 7: 0.5}
const BORN_SKILL_UNIQUE := {1: 0.0, 2: 0.0, 3: 0.02, 4: 0.06, 5: 0.25, 6: 0.45, 7: 0.7}

# --- Base e strutture ---------------------------------------------------------
## Livelli della base. Ogni livello alza il livello massimo delle strutture e sblocca nuovi cantieri.
## Con 100 piani nella Torre la base arriva al Lv.10 (decisione del proprietario, 2026-11-05):
## regola fissa: Lv.2 col Guardiano del Piano 5, poi un livello ogni 10 piani (10, 20 … 80),
## sempre un piano Guardiano, così la Torre e la base salgono insieme.
## dal Lv.6 si aggiungono isole collegate da ponti (vedi BASE_ISLANDS).
## look = come cambia il borgo (testo per il pannello del Cristallo).
const BASE_LEVELS := [
	{"level": 1, "floor": 0, "gold": 0, "look": "Sentieri di terra, palizzata di legno e tetti di paglia."},
	{"level": 2, "floor": 5, "gold": 40000, "look": "Piazza e strade principali lastricate, lampioni di ferro, una bancarella e una porta di pietra nella palizzata."},
	{"level": 3, "floor": 10, "gold": 120000, "look": "Tutte le strade lastricate, mura di pietra, fontana, mercato e tetti di ardesia."},
	{"level": 4, "floor": 20, "gold": 300000, "look": "Torri sulle mura con rune azzurre e statue lungo la strada del Portale."},
	{"level": 5, "floor": 30, "gold": 700000, "look": "Stendardi dorati, lanterne che fluttuano sulla piazza e l'aurora nel cielo."},
	{"level": 6, "floor": 40, "gold": 1200000, "look": "Prima isola nuova, collegata da un ponte."},
	{"level": 7, "floor": 50, "gold": 1900000, "look": "Anelli di pietra sospesi attorno al Cristallo e lampioni a rune lungo le strade."},
	{"level": 8, "floor": 60, "gold": 3000000, "look": "Seconda isola nuova, collegata da un ponte."},
	{"level": 9, "floor": 70, "gold": 4500000, "look": "Lanterne sospese sopra i ponti e le isole, fuochi azzurri sulle torri."},
	{"level": 10, "floor": 80, "gold": 6500000, "look": "Terza isola nuova, la più alta di tutte."},
]
## Livello massimo delle strutture (sempre entro il livello della base).
const FACILITY_MAX_LEVEL := 10
## Isole che la base aggiunge crescendo: livello della base che le porta e vantaggio.
const BASE_ISLANDS := [
	{"id": "campi", "level": 6, "name": "Isola dei Campi", "bonus": "+2 posti al Centro di Addestramento", "description": "Arena all'aperto, campi di grano e un mulino a vento."},
	{"id": "dimore", "level": 8, "name": "Isola delle Dimore", "bonus": "+6 letti nel Dormitorio", "description": "Case degli eroi attorno a una piazzetta con il campanile."},
	{"id": "santuario", "level": 10, "name": "Santuario del Nexus", "bonus": "+10% esperienza dalle missioni", "description": "Un tempio sospeso più in alto di tutto, con un frammento gigante del Nexus."},
]

## Catalogo strutture. unlock = livello base che rende disponibile il cantiere.
const FACILITIES := {
	"training": {"name": "Centro di Addestramento", "short": "Addestramento", "unlock": 1, "build_cost": 0, "upgrade_cost": 9000, "description": "Gli eroi si allenano sul campo rialzato e guadagnano esperienza nel tempo."},
	"dormitory": {"name": "Dormitorio", "short": "Dormitorio", "unlock": 1, "build_cost": 0, "upgrade_cost": 7000, "description": "Gli eroi riposano, recuperano la stanchezza, il morale e guariscono dalle ferite."},
	"merging": {"name": "Centro di Fusione", "short": "Fusione", "unlock": 1, "build_cost": 0, "upgrade_cost": 12000, "description": "La cupola azzurra dove gli eroi si fondono e vengono promossi di rarità."},
	"gate": {"name": "Portale delle Missioni", "short": "Portale", "unlock": 1, "build_cost": 0, "upgrade_cost": 15000, "description": "Il varco sospeso verso la Torre. Da qui parte la squadra."},
	"armory": {"name": "Armeria", "short": "Armeria", "unlock": 1, "unlock_floor": 3, "build_cost": 25000, "upgrade_cost": 14000, "description": "Forgia e assegna armi e armature agli eroi."},
	"warehouse": {"name": "Magazzino", "short": "Magazzino", "unlock": 3, "build_cost": 40000, "upgrade_cost": 16000, "description": "Deposito di materiali ed equipaggiamento. Aumenta le scorte massime."},
	"workshop": {"name": "Laboratorio", "short": "Laboratorio", "unlock": 3, "build_cost": 45000, "upgrade_cost": 18000, "description": "Raffina i materiali grezzi in componenti per la forgia e l'alchimia."},
	"alchemy": {"name": "Centro Alchemico", "short": "Alchimia", "unlock": 4, "build_cost": 80000, "upgrade_cost": 26000, "description": "Distilla tonici che curano ferite e risollevano il morale."},
}
const FACILITY_ORDER := ["training", "dormitory", "merging", "gate", "armory", "warehouse", "workshop", "alchemy"]

const MATERIALS := {
	"ore": {"name": "Ferro (C)", "icon": "⬢"}, "leather": {"name": "Pelle (C)", "icon": "◒"}, "wood": {"name": "Assi di legno (C)", "icon": "♣"},
	"herbs": {"name": "Erbe", "icon": "✿"}, "cores": {"name": "Nuclei", "icon": "✹"}, "medicine": {"name": "Medicine", "icon": "✚"},
}

# --- Torre -------------------------------------------------------------------
const STAGES := {
	1: {"type": "Subjugation", "name": "La strada spezzata", "biome": "Bosco cinereo", "objective": "Elimina tutte le minacce", "duration": 60.0, "color": "#3c7968", "description": "Predoni del Rift hanno chiuso l'unica via verso la torre.", "waves": [[0.0, "raider", 3], [10.0, "hound", 2]]},
	2: {"type": "Subjugation", "name": "Campana nella nebbia", "biome": "Borgo evacuato", "objective": "Elimina tutte le minacce", "duration": 75.0, "color": "#346b86", "description": "La campana ha attirato predoni tra le case vuote. Ripulisci il borgo.", "waves": [[0.0, "raider", 3], [12.0, "archer", 2], [24.0, "hound", 2]]},
	3: {"type": "Subjugation", "name": "Osservatorio sommerso", "biome": "Rovine allagate", "objective": "Elimina tutte le minacce", "duration": 80.0, "color": "#365c8c", "description": "Segugi del Rift si sono annidati nelle rovine allagate.", "waves": [[0.0, "hound", 3], [14.0, "raider", 3], [28.0, "archer", 2]]},
	4: {"type": "Subjugation", "name": "L'ultima lanterna", "biome": "Santuario in rovina", "objective": "Elimina tutte le minacce", "duration": 85.0, "color": "#94713c", "description": "L'ultimo presidio prima del Custode: i predoni hanno portato un bruto.", "waves": [[0.0, "raider", 4], [12.0, "archer", 2], [26.0, "brute", 1], [36.0, "hound", 2]]},
	5: {"type": "Boss", "name": "Custode delle radici", "biome": "Cuore del bosco", "objective": "Abbatti il Custode", "duration": 90.0, "color": "#537d3d", "description": "La minaccia nascosta dello Stream attende sotto la torre.", "waves": [[0.0, "boss", 1], [0.0, "raider", 2], [22.0, "hound", 3], [45.0, "archer", 2]]},
}
const STAGE_TYPE_CYCLE := ["Subjugation", "Survival", "Exploration", "Defense"]
const BIOMES := [
	{"name": "Bosco cinereo", "color": "#3c7968"}, {"name": "Borgo evacuato", "color": "#346b86"}, {"name": "Rovine allagate", "color": "#365c8c"},
	{"name": "Santuario in rovina", "color": "#94713c"}, {"name": "Pianure ventose", "color": "#6f8f3e"}, {"name": "Canyon ramato", "color": "#a0623a"},
	{"name": "Ghiacciaio sospeso", "color": "#4f86a8"}, {"name": "Giardini di cristallo", "color": "#6a5aa8"},
]
const STAGE_NAME_A := ["Passo", "Sentiero", "Bastione", "Volta", "Guado", "Cripta", "Altopiano", "Soglia", "Ponte", "Vigna"]
const STAGE_NAME_B := ["delle ceneri", "dei corvi", "senza nome", "del vento", "d'ambra", "dei giuramenti", "spezzato", "delle lanterne", "di vetro", "sommerso"]
const STAGE_OBJECTIVES := {
	"Subjugation": "Elimina tutte le minacce", "Survival": "Sopravvivi fino al termine", "Exploration": "Metti in sicurezza 3 punti d'interesse",
	"Defense": "Proteggi il faro del Rift", "Boss": "Abbatti il guardiano del piano",
}

# --- Difficoltà della Torre ----------------------------------------------------
# La Torre è divisa in scaglioni di 5 piani (1–5, 6–10, ...). Dentro uno scaglione
# ogni piano è un po' più duro del precedente; il 5° è la Prova del Guardiano, una
# missione speciale con regole in più (vedi TOWER_TRIALS). Superata la prova, lo
# scaglione successivo riparte da un gradino più alto. Numeri di Game Design:
# vedi docs/GAME_SYSTEMS.md e tests/tower_curve_runner.gd per la verifica.
const TOWER_TIER_FLOORS := 5
## Forza dei nemici al primo piano di ogni scaglione (moltiplica vita e attacco
## dei modelli in battle_scene.ENEMY_TEMPLATES). Oltre la tabella cresce del 5%.
const TOWER_TIER_POWER := [2.0, 3.69, 4.39, 5.14, 6.15, 7.59, 8.96, 9.85, 10.84, 11.92, 12.5, 13.1, 13.8, 14.5, 15.2, 16.0, 16.8, 17.6, 18.5, 19.4]
## +% a ogni piano dentro lo scaglione: il grosso del salto arriva a ogni nuovo scaglione.
const TOWER_STEP_GROWTH := 0.03
## Prova del Guardiano: le regole, i campioni e il guardiano infuriato la rendono già il
## muro dello scaglione, quindi la forza di base dei nemici è ridotta di questo fattore
## (tarato perché la squadra dello scaglione successivo la passi circa 2 volte su 3).
const TOWER_TRIAL_POWER := [1.02, 0.83, 0.81, 0.8, 0.79, 0.76, 0.68, 0.64, 0.6, 0.59, 0.58, 0.575, 0.565, 0.56, 0.545, 0.535, 0.525, 0.5, 0.49, 0.46]
## Campioni: nemici d'élite delle prove (e dei piani alti).
const ELITE_HP := 2.4
const ELITE_ATTACK := 1.35
## Regole della Prova del Guardiano. Ogni prova ne pesca alcune (di più negli scaglioni alti).
const TOWER_TRIALS := {
	"furia": {"name": "Furia", "text": "i nemici colpiscono più forte (+25% attacco)"},
	"corazza": {"name": "Corazza", "text": "i nemici sono corazzati (+60% difesa)"},
	"orda": {"name": "Orda", "text": "ondate più numerose (+50% nemici)"},
	"rapidi": {"name": "Passo rapido", "text": "i nemici corrono e attaccano più spesso"},
	"rigenerazione": {"name": "Carne del Rift", "text": "i nemici rigenerano l'1% della vita al secondo"},
	"nebbia": {"name": "Nebbia", "text": "gli eroi mirano peggio (−15 precisione)"},
	"ferite": {"name": "Ferite profonde", "text": "le cure valgono la metà"},
}
const GUARDIAN_TITLES := ["Custode delle radici", "Colosso di cenere", "Sentinella di vetro", "Signore del guado", "Il Senza Volto", "Araldo del Rift", "Gigante delle lanterne", "Cuore di ferro", "Il Giuramento infranto", "Re delle ceneri"]

# --- Dungeon giornalieri (richiesta del proprietario, 2026-11-12) ---------------
## Missioni facili per raccogliere materiali: mostri deboli, niente bruti né guardiani.
## Ogni dungeon si può vincere DUNGEON_RUNS_PER_DAY volte al giorno (si azzera a mezzanotte
## UTC, come il negozio). Il livello lo sceglie il giocatore: uno ogni 5 piani superati.
## Più è alto, più materiali; i nemici valgono meno della metà di quelli della Torre.
const DUNGEONS := {
	"miniera": {"name": "Miniera abbandonata", "material": "ore", "biome": "Canyon ramato", "color": "#b8865a", "description": "Gallerie piene di ferro, occupate da qualche predone.", "waves": ["raider", "raider", "archer"]},
	"riserva": {"name": "Riserva di caccia", "material": "leather", "biome": "Pianure ventose", "color": "#7a9a3a", "description": "Branchi di segugi del Rift: pelli buone per chi li abbatte.", "waves": ["hound", "hound", "raider"]},
	"segheria": {"name": "Segheria nel bosco", "material": "wood", "biome": "Bosco cinereo", "color": "#3c7968", "description": "Cataste di assi già tagliate, sorvegliate da pochi sbandati.", "waves": ["raider", "hound", "archer"]},
	"giardino": {"name": "Giardino selvatico", "material": "herbs", "biome": "Giardini di cristallo", "color": "#6c6a8a", "description": "Erbe rare cresciute tra i cristalli. Qualche segugio ci ha fatto la tana.", "waves": ["hound", "archer", "hound"]},
}
const DUNGEON_ORDER := ["miniera", "riserva", "segheria", "giardino"]
const DUNGEON_RUNS_PER_DAY := 2
const DUNGEON_MAX_LEVEL := 20
## Forza dei nemici rispetto al primo piano dello scaglione corrispondente della Torre.
const DUNGEON_POWER := 0.45

var data: Dictionary = {}
var is_test_mode := OS.get_cmdline_user_args().has("--test-mode")
var _tick_accumulator := 0.0
var _save_accumulator := 0.0

func _ready() -> void:
	if is_test_mode: new_world("automated-test-world")
	else: load_or_create()
	set_process(not is_test_mode)

func _process(delta: float) -> void:
	if data.is_empty(): return
	_tick_accumulator += delta
	_save_accumulator += delta
	if _tick_accumulator >= TICK_SECONDS:
		var changed := advance_time(_tick_accumulator)
		_tick_accumulator = 0.0
		if changed: time_ticked.emit()
	if _save_accumulator >= AUTOSAVE_SECONDS:
		_save_accumulator = 0.0
		save_game()

# =============================================================================
# Salvataggio
# =============================================================================

func load_or_create() -> void:
	var had_save := FileAccess.file_exists(SAVE_PATH)
	for path in [SAVE_PATH, SAVE_PATH + ".bak"]:
		var parsed: Variant = _read_save(path)
		if parsed is Dictionary and parsed.has("world") and parsed.has("heroes"):
			data = parsed
			_migrate()
			if path != SAVE_PATH: add_event("SYSTEM", "Salvataggio recuperato", "Il file principale era illeggibile: caricata la copia di sicurezza.", "warn")
			_apply_offline_progress()
			return
	if had_save:
		# Non sovrascrivere mai un salvataggio danneggiato: lo si conserva a parte.
		var kept := SAVE_PATH + ".danneggiato-%d" % int(Time.get_unix_time_from_system())
		DirAccess.rename_absolute(SAVE_PATH, kept)
		new_world()
		add_event("SYSTEM", "Salvataggio illeggibile", "Il vecchio file è stato conservato come %s e si riparte da un nuovo mondo." % kept.get_file(), "danger")
		return
	new_world()

func _read_save(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	return JSON.parse_string(file.get_as_text())

func new_world(seed_text: String = "") -> void:
	var world_seed := seed_text
	if world_seed.is_empty(): world_seed = "%x%x" % [Time.get_unix_time_from_system(), randi()]
	data = {
		"version": SAVE_VERSION,
		"world": {
			"id": "WORLD-%08X" % abs(world_seed.hash()), "seed": world_seed, "master_name": "Aster",
			"gold": 60000, "gems": 1500, "stones": 1, "current_floor": 1, "max_floor": 1, "completed": [],
			"base_level": 1, "seen_floor": 1,
			"materials": {"ore": 8, "leather": 6, "wood": 10, "herbs": 4, "cores": 0, "medicine": 2},
			"last_saved": Time.get_unix_time_from_system(),
		},
		"heroes": [], "party": [], "relationships": {}, "stages": {}, "events": [], "ledger": [], "memorial": [], "inventory": [],
		"facilities": _default_facilities(),
		"assignments": {},
		"pity": {"high": 0, "transcendent": 0}, "summon_counter": 0, "item_counter": 0,
		"active_mission": {}, "tutorial_seen": false, "settings": {"light": "dusk"},
		"dev": {"enabled": false, "unlimited_resources": false, "reveal_hidden": false, "god_mode": false, "all_content": false},
	}
	var starter_roles := ["Guardian", "Vanguard", "Lancer", "Ranger", "Support", "Mage"]
	for i in starter_roles.size(): data.heroes.append(generate_hero(world_seed + ":starter:" + str(i), 2 if i == 4 else 1, starter_roles[i]))
	for i in PARTY_SIZE: data.party.append(data.heroes[i].id)
	_materialize_stage(1)
	add_event("SYSTEM", "Il Nexus si risveglia", "Sei eroi sono arrivati alla base. Il Portale delle Missioni è pronto.", "good")
	add_ledger("gold", 60000, "Dotazione iniziale", "onboarding")
	save_game()
	state_changed.emit()

func _default_facilities() -> Dictionary:
	var output := {}
	for id in FACILITY_ORDER: output[id] = {"level": 1 if facility_starts_built(id) else 0}
	return output

## Strutture già in piedi in una partita nuova (l'Armeria arriva dopo il Piano 3).
static func facility_starts_built(id: String) -> bool:
	return int(FACILITIES[id].unlock) <= 1 and not FACILITIES[id].has("unlock_floor")

func _migrate() -> void:
	var from_version := int(data.get("version", 1))
	data.get_or_add("inventory", [])
	data.get_or_add("active_mission", {})
	data.get_or_add("tutorial_seen", true)
	data.get_or_add("assignments", {})
	data.get_or_add("item_counter", 0)
	data.get_or_add("memorial", [])
	data.get_or_add("relationships", {})
	data.get_or_add("pity", {"high": 0})
	data.pity.get_or_add("high", 0)
	data.pity.get_or_add("transcendent", 0)
	data.world.get_or_add("base_level", 1)
	data.world.get_or_add("materials", {})
	for key in MATERIALS: data.world.materials.get_or_add(key, 0)
	data.get_or_add("dev", {})
	for key in ["enabled", "unlimited_resources", "reveal_hidden", "god_mode", "all_content"]: data.dev.get_or_add(key, false)
	data.get_or_add("settings", {})
	data.settings.get_or_add("light", "dusk")
	if from_version < 3:
		# La v2 forzava la modalità sviluppo: la v3 torna a un'economia reale.
		data.dev.enabled = false
		data.dev.unlimited_resources = false
		data.dev.reveal_hidden = false
		data.dev.all_content = false
		data.facilities = _migrate_facilities(data.get("facilities", {}))
		for key in ["shop_claims", "shop_history", "cosmetics"]: data.erase(key)
	else:
		var facilities: Dictionary = data.get_or_add("facilities", {})
		for id in FACILITY_ORDER: facilities.get_or_add(id, {"level": 1 if facility_starts_built(id) else 0})
	_normalize_types()
	for hero in data.heroes: _normalize_hero(hero)
	if from_version < 3:
		# La vecchia esperienza accumulata diventa livelli veri.
		for hero in data.heroes:
			if hero.state == "ALIVE": add_xp(hero, 0.0)
	for id in FACILITY_ORDER:
		data.facilities[id].level = clampi(int(data.facilities[id].get("level", 0)), 0, base_level())
	for item in data.inventory:
		if not item.has("id") or str(item.id).is_empty():
			data.item_counter = int(data.item_counter) + 1
			item["id"] = "I-%05d" % int(data.item_counter)
		item.get_or_add("slot", "main")
		item.get_or_add("grade", "D")
	# Regole del proprietario (2026-11-12): i piani 1–4 sono annientamenti abbastanza facili
	for early in [2, 3, 4]:
		var early_record: Dictionary = data.get("stages", {}).get(str(early), {})
		if not early_record.is_empty() and not bool(early_record.get("cleared", false)) and str(early_record.get("descriptor", {}).get("type", "")) != "Subjugation":
			data.stages.erase(str(early))
			_materialize_stage(early).attempts = int(early_record.get("attempts", 0))
	for hero in data.heroes:
		if int(hero.get("level", 1)) > level_cap(hero):
			hero.level = level_cap(hero)
			hero.xp = 0
		# le vecchie valutazioni dicevano quanto l'eroe impara: ora lo scopre il giocatore
		hero.assessment = _assessment(hero)
	for stage_key in data.get("stages", {}):
		var stage_record: Dictionary = data.stages[stage_key]
		if not stage_record.has("descriptor"): continue
		var descriptor: Dictionary = stage_record.descriptor
		var stage_floor := int(descriptor.get("floor", int(stage_key)))
		# Prove del Guardiano (novembre 2026): i quinti piani non ancora superati diventano prove
		if is_trial_floor(stage_floor) and not descriptor.has("trial") and not bool(stage_record.get("cleared", false)):
			_add_trial(descriptor, stage_floor, str(data.world.seed) + ":floor:" + str(stage_floor))
		descriptor["tier"] = tower_tier(stage_floor) + 1
		var normalized_threat: int = tower_threat(stage_floor, descriptor)
		descriptor["threat_budget"] = normalized_threat
		descriptor["threat"] = normalized_threat
		stage_record.get_or_add("attempts", 0)
		stage_record.get_or_add("cleared", false)
		stage_record.get_or_add("best_time", 0.0)
	# Eroi dei salvataggi precedenti: ricevono un aspetto senza perdere livello, stats o equipaggiamento.
	for hero in data.heroes:
		# 1★-2★ già in squadra: diventano popolani che hanno già scelto la loro classe
		if not hero.has("commoner"):
			var commoner := int(hero.get("native_rarity", hero.get("current_rarity", 1))) <= COMMONER_MAX_RARITY
			hero["commoner"] = commoner
			hero["class_chosen"] = true
			if commoner:
				var job := str(hero.get("profession", ""))
				if not COMMONER_JOBS.has(job): job = _job_for_role(str(hero.get("role", "Guardian")), str(COMMONER_JOBS.keys()[0]))
				var advice := class_advice(hero.stats, job)
				hero["job"] = job
				hero["profession"] = job
				hero["recommended_role"] = str(advice.role)
				hero["alt_role"] = str(advice.alt)
				hero["advice"] = str(advice.text)
		hero.get_or_add("class_chosen", true)
		# aspetto a pezzi (foglio dei personaggi): colori dalla categoria del mestiere o della
		# classe, poi archetipo, volto, capigliatura, corporatura ed età
		var outdated := int(hero.get("look", {}).get("v", 0)) < HeroLookScript.VERSION
		if outdated or not hero.has("appearance"):
			var category := str(COMMONER_JOBS[hero.job].category) if is_commoner(hero) and COMMONER_JOBS.has(str(hero.get("job", ""))) else HeroLookScript.category_for_role(str(hero.get("role", "Guardian")), str(hero.get("id", "legacy")))
			hero["appearance"] = CharacterGeneratorScript.generate(str(hero.get("id", "legacy")) + ":appearance", category)
		hero["category"] = str(hero.appearance.get("category", "Villager"))
		if outdated: hero["look"] = HeroLookScript.generate(str(hero.get("id", "legacy")), base_archetype(hero), is_feminine(hero), int(hero.get("native_rarity", 1)), hero.appearance)
		for key in ["portrait", "portrait_v"]: hero.erase(key)
	while data.party.size() < PARTY_SIZE: data.party.append("")
	data.version = SAVE_VERSION
	if not data.active_mission.is_empty():
		# Chiudere il gioco durante una missione non la annulla: conta come sconfitta.
		var results := []
		for hero in get_party():
			if not hero.is_empty(): results.append({"id": hero.id, "alive": true, "hp_ratio": 0.5, "kills": 0, "fatigue": 15})
		finalize_mission({"victory": false, "reason": "abandoned", "duration": 0.0, "hero_results": results})
		add_event("MISSION", "Missione abbandonata", "Il gioco è stato chiuso durante la missione: conta come una ritirata. Le morti già avvenute restano.", "warn")

## Il JSON trasforma tutti i numeri in decimali: qui tornano interi dove serve.
func _normalize_types() -> void:
	for key in ["gold", "gems", "stones", "current_floor", "max_floor", "base_level"]:
		data.world[key] = int(data.world.get(key, 0))
	data.world.max_floor = maxi(1, int(data.world.max_floor))
	data.world.current_floor = clampi(int(data.world.current_floor), 1, int(data.world.max_floor))
	data.world.base_level = clampi(int(data.world.base_level), 1, BASE_LEVELS.size())
	data.world["seen_floor"] = int(data.world.get("seen_floor", data.world.max_floor))
	var completed: Array = []
	for value in data.world.get("completed", []):
		var floor_index := int(value)
		if not completed.has(floor_index): completed.append(floor_index)
	data.world.completed = completed
	for key in data.world.materials: data.world.materials[key] = int(data.world.materials[key])
	data.summon_counter = int(data.get("summon_counter", 0))
	data.item_counter = int(data.get("item_counter", 0))
	for key in data.pity: data.pity[key] = int(data.pity[key])
	for id in data.get("facilities", {}):
		var facility: Dictionary = data.facilities[id]
		facility.level = int(facility.get("level", 0))
	for stage_key in data.get("stages", {}):
		var record: Dictionary = data.stages[stage_key]
		record.attempts = int(record.get("attempts", 0))
		if record.has("descriptor"): record.descriptor.floor = int(record.descriptor.get("floor", int(stage_key)))
	for hero in data.heroes:
		for key in ["level", "native_rarity", "current_rarity", "missions", "victories", "kills", "potential", "hue"]:
			if hero.has(key): hero[key] = int(hero[key])
		for key in hero.get("stats", {}): hero.stats[key] = int(hero.stats[key])

func _migrate_facilities(old: Dictionary) -> Dictionary:
	var output := _default_facilities()
	output.training.level = clampi(int(old.get("Training Center", 1)), 1, 5)
	output.dormitory.level = clampi(int(old.get("Lodging", 1)), 1, 5)
	output.merging.level = clampi(maxi(1, int(old.get("Synthesis Chamber", 1))), 1, 5)
	# Le vecchie strutture non previste dalla Base Lv.1 tornano da costruire.
	return output

func _normalize_hero(hero: Dictionary) -> void:
	hero.get_or_add("xp", 0)
	hero.get_or_add("memories", [])
	hero.get_or_add("missions", 0)
	hero.get_or_add("victories", 0)
	hero.get_or_add("kills", 0)
	var injuries: Array = hero.get_or_add("injuries", [])
	for i in injuries.size():
		if injuries[i] is String: injuries[i] = {"name": injuries[i], "severity": "Moderata", "minutes": 20.0}
	var equipment: Dictionary = hero.get_or_add("equipment", _starter_equipment(str(hero.get("role", "Guardian"))))
	equipment.get_or_add("accessory", {})
	# nomi delle abilità dei salvataggi più vecchi (in inglese) → nomi di adesso
	for skill in hero.get_or_add("skills", []):
		if skill is Dictionary: skill.name = skill_label(str(skill.get("name", "")))

func _apply_offline_progress() -> void:
	var now := Time.get_unix_time_from_system()
	var elapsed: float = clampf(now - float(data.world.get("last_saved", now)), 0.0, OFFLINE_CAP_HOURS * 3600.0)
	if elapsed >= 30.0:
		var before_levels := {}
		for hero in data.heroes: before_levels[hero.id] = int(hero.level)
		# A passi di un minuto, come se il gioco fosse rimasto aperto.
		var remaining := elapsed
		while remaining > 0.0:
			var step := minf(60.0, remaining)
			advance_time(step)
			remaining -= step
		var gained := 0
		for hero in data.heroes: gained += int(hero.level) - int(before_levels.get(hero.id, hero.level))
		add_event("REPORT", "Mentre eri via", "Sono passati %d minuti alla base. Livelli guadagnati in addestramento: %d." % [roundi(elapsed / 60.0), gained], "info")
	data.world.last_saved = now
	save_game()

## Scrittura sicura: file temporaneo, copia di sicurezza, poi sostituzione.
func save_game() -> void:
	if data.is_empty() or is_test_mode: return
	data.world.last_saved = Time.get_unix_time_from_system()
	var tmp := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, SAVE_PATH + ".bak")
		if DirAccess.rename_absolute(tmp, SAVE_PATH) != OK:
			DirAccess.remove_absolute(SAVE_PATH)
			DirAccess.rename_absolute(tmp, SAVE_PATH)
	else:
		DirAccess.rename_absolute(tmp, SAVE_PATH)

func save_and_notify() -> void:
	save_game()
	state_changed.emit()

# =============================================================================
# Utilità
# =============================================================================

func rng_for(text: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(text.hash())
	return rng

func _pick(rng: RandomNumberGenerator, values: Array) -> Variant:
	return values[rng.randi_range(0, values.size() - 1)]

## Due valori diversi con lo stesso numero di estrazioni di due _pick.
func _pick_two(rng: RandomNumberGenerator, values: Array) -> Array:
	var i := rng.randi_range(0, values.size() - 1)
	var j := rng.randi_range(0, values.size() - 2)
	if j >= i: j += 1
	return [values[i], values[j]]

## Nomi delle abilità dei salvataggi precedenti, ancora in inglese.
const LEGACY_SKILL_NAMES := {"Aegis Brace": "Scudo d'Egida", "Driving Cleave": "Fendente Travolgente", "Pinning Thrust": "Affondo Inchiodante", "Marked Shot": "Colpo Mirato", "Ember Lattice": "Rete di Braci", "Mend": "Cura", "Field Discipline": "Disciplina da Campo"}

static func skill_label(name: String) -> String:
	return LEGACY_SKILL_NAMES.get(name, name)

func stars(rarity: int) -> String:
	return "★".repeat(rarity)

static func role_label(role: String) -> String:
	return str(ROLES.get(role, {}).get("label", role))

func format_number(value: float) -> String:
	var source := str(roundi(abs(value)))
	var output := ""
	var count := 0
	for i in range(source.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0: output = "." + output
		output = source[i] + output
		count += 1
	return ("-" if value < 0 else "") + output

func now() -> float:
	return Time.get_unix_time_from_system()

func is_dev_unlimited() -> bool:
	return bool(data.get("dev", {}).get("enabled", false)) and bool(data.dev.get("unlimited_resources", false))

func resource_amount(key: String) -> int:
	if key in ["gold", "gems", "stones"]: return int(data.world.get(key, 0))
	return int(data.world.materials.get(key, 0))

func display_resource(key: String) -> String:
	if is_dev_unlimited(): return "∞"
	return format_number(float(resource_amount(key)))

func can_afford(costs: Dictionary) -> bool:
	if is_dev_unlimited(): return true
	for key in costs:
		if resource_amount(key) < int(costs[key]): return false
	return true

func _can_pay(key: String, amount: int) -> bool:
	return can_afford({key: amount})

func pay(costs: Dictionary, reason: String, source: String) -> bool:
	if not can_afford(costs): return false
	for key in costs: _pay(key, int(costs[key]), reason, source)
	return true

func _pay(key: String, amount: int, reason: String, source: String) -> bool:
	if not _can_pay(key, amount): return false
	if is_dev_unlimited():
		add_ledger(key, 0, "DEV · costo simulato %d · %s" % [amount, reason], source)
		return true
	if key in ["gold", "gems", "stones"]: data.world[key] = int(data.world[key]) - amount
	else: data.world.materials[key] = int(data.world.materials.get(key, 0)) - amount
	add_ledger(key, -amount, reason, source)
	return true

func grant(key: String, amount: int, reason: String, source: String) -> void:
	if amount == 0: return
	if key in ["gold", "gems", "stones"]: data.world[key] = int(data.world.get(key, 0)) + amount
	else: data.world.materials[key] = mini(material_cap(), int(data.world.materials.get(key, 0)) + amount)
	add_ledger(key, amount, reason, source)

func cost_text(costs: Dictionary) -> String:
	var names := {"gold": "Oro", "gems": "Gemme", "stones": "Pietre"}
	var parts := []
	for key in costs:
		var label: String = names.get(key, MATERIALS.get(key, {}).get("name", key))
		parts.append("%s %s" % [format_number(costs[key]), label])
	return " · ".join(parts)

# =============================================================================
# Eroi
# =============================================================================

func generate_hero(seed_text: String, rarity: int, forced_role: String = "") -> Dictionary:
	var rng := rng_for(seed_text)
	# 1★-2★: persona comune con un mestiere. Le statistiche vengono dal mestiere,
	# la classe la sceglie il giocatore (la squadra iniziale l'ha già scelta).
	var commoner := rarity <= COMMONER_MAX_RARITY
	var job := ""
	var role: String
	var weights: Array
	if commoner:
		job = _pick(rng, COMMONER_JOBS.keys())
		if not forced_role.is_empty(): job = _job_for_role(forced_role, job)
		weights = COMMONER_JOBS[job].weights
	else:
		role = forced_role if not forced_role.is_empty() else _pick(rng, ROLES.keys())
		weights = ROLES[role].weights
	var name := "%s %s" % [_pick(rng, FIRST_NAMES), _pick(rng, LAST_NAMES)]
	var budget := 39 + rarity * 3 + rng.randi_range(0, 7)
	var stats := {"str": 7 + roundi(budget * weights[0]) + rng.randi_range(0, 2), "int": 7 + roundi(budget * weights[1]) + rng.randi_range(0, 2), "sta": 7 + roundi(budget * weights[2]) + rng.randi_range(0, 2), "agi": 7 + roundi(budget * weights[3]) + rng.randi_range(0, 2)}
	var advice := {}
	if commoner:
		advice = class_advice(stats, job)
		role = forced_role if not forced_role.is_empty() else str(advice.role)
	var potential_min := 20 + (rarity - 1) * 10
	var potential := clampi(rng.randi_range(potential_min, 88 + rarity * 2), 20, 100)
	var id := "H-%08X" % abs((seed_text + name).hash())
	var hero := {
		"id": id, "seed": "%08X" % abs(seed_text.hash()), "name": name, "native_rarity": rarity, "current_rarity": rarity, "level": 1, "xp": 0,
		"role": role, "class_name": role, "origin": _pick(rng, ORIGINS), "profession": job if commoner else _pick(rng, PROFESSIONS), "stats": stats, "potential": potential, "growth": 3.35 + rarity * 0.62 + potential * 0.004,
		"personality": {"courage": rng.randi_range(25, 95), "discipline": rng.randi_range(20, 96), "aggression": rng.randi_range(15, 95), "altruism": rng.randi_range(15, 95), "composure": rng.randi_range(20, 95), "loyalty": rng.randi_range(25, 90)},
		"traits": _pick_two(rng, TRAITS), "skills": [{"name": ROLES[role].skill, "level": 1, "xp": 0}],
		"morale": rng.randi_range(60, 84), "fatigue": rng.randi_range(0, 8), "injuries": [], "missions": 0, "victories": 0, "kills": 0, "state": "ALIVE", "hue": rng.randi_range(0, 359),
		"equipment": _starter_equipment(role), "memories": ["Ha attraversato il Rift e ha visto il Nexus per la prima volta."],
		"commoner": commoner, "class_chosen": not commoner or not forced_role.is_empty(),
	}
	if commoner:
		hero.job = job
		hero.recommended_role = str(advice.role)
		hero.alt_role = str(advice.alt)
		hero.advice = str(advice.text)
		if not bool(hero.class_chosen):
			# finché non ha una classe combatte con l'attrezzo del suo mestiere
			hero.equipment.main.name = str(COMMONER_JOBS[job].tool)
			hero.equipment.main.power = 11
			hero.equipment.armor.name = "Abiti da lavoro"
			hero.equipment.armor.defense = 4
			hero.skills[0] = {"name": "Mestiere: " + job, "level": 1, "xp": 0}
	hero.skills.append_array(_born_skills(id, rarity, role))
	hero.assessment = _assessment(hero)
	# Aspetto: colori dal generatore personaggi (categoria scelta da mestiere o classe),
	# pezzi del foglio (archetipo, volto, capigliatura, corporatura, età) dall'id.
	var category := str(COMMONER_JOBS[job].category) if commoner else HeroLookScript.category_for_role(role, id)
	hero.appearance = CharacterGeneratorScript.generate(id + ":appearance", category)
	hero.category = str(hero.appearance.category)
	hero.look = HeroLookScript.generate(id, base_archetype(hero), is_feminine(hero), rarity, hero.appearance)
	return hero

## Abilità particolari con cui nasce un eroe (estrazione a parte, non tocca il resto del seme).
func _born_skills(hero_id: String, rarity: int, role: String) -> Array:
	var rng := rng_for(hero_id + ":skills")
	var commons := []
	var uniques := []
	for key in SKILLS:
		var roles: Array = SKILLS[key].get("roles", [])
		if not roles.is_empty() and not role in roles: continue
		if str(SKILLS[key].kind) == "unique": uniques.append(key)
		else: commons.append(key)
	var names := []
	if rng.randf() < float(BORN_SKILL_UNIQUE.get(rarity, 0.0)): names.append(uniques[rng.randi_range(0, uniques.size() - 1)])
	if rng.randf() >= float(BORN_SKILL_NONE.get(rarity, 0.5)):
		var first: String = commons[rng.randi_range(0, commons.size() - 1)]
		names.append(first)
		if rng.randf() < float(BORN_SKILL_SECOND.get(rarity, 0.0)):
			var rest := commons.filter(func(n): return n != first)
			names.append(rest[rng.randi_range(0, rest.size() - 1)])
	var output := []
	for n in names: output.append({"name": n, "level": 1, "xp": 0})
	return output

## Abilità particolari dell'eroe (senza la tecnica di classe).
static func particular_skills(hero: Dictionary) -> Array:
	return hero.get("skills", []).filter(func(skill): return SKILLS.has(str(skill.get("name", ""))))

## Somma degli effetti delle abilità particolari, già moltiplicati per il livello.
static func skill_effects(hero: Dictionary) -> Dictionary:
	var output := {"hp": 0.0, "atk": 0.0, "def": 0.0, "acc": 0.0, "eva": 0.0, "crit": 0.0, "heal": 0.0, "fear": 0.0}
	for skill in particular_skills(hero):
		var info: Dictionary = SKILLS[str(skill.name)]
		var mult := 1.0 + 0.5 * (clampi(int(skill.get("level", 1)), 1, SKILL_MAX_LEVEL) - 1)
		for key in output:
			if info.has(key): output[key] += float(info[key]) * mult
	output.fear = minf(1.0, output.fear)
	return output

## Testo breve di un'abilità particolare per le schede: "Pelle dura Lv.2 (comune): incassa meglio".
static func skill_text(skill: Dictionary) -> String:
	var info: Dictionary = SKILLS.get(str(skill.get("name", "")), {})
	if info.is_empty(): return skill_label(str(skill.get("name", "")))
	return "%s Lv.%d (%s): %s" % [str(skill.name), int(skill.get("level", 1)), "unica" if str(info.kind) == "unique" else "comune", str(info.text).to_lower().trim_suffix(".")]

## Mestiere adatto a una classe già decisa (squadra iniziale): uno di quelli che pendono verso di lei.
func _job_for_role(role: String, fallback: String) -> String:
	var options := []
	for key in COMMONER_JOBS:
		if str(COMMONER_JOBS[key].lean) == role: options.append(key)
	if options.is_empty(): return fallback
	return options[abs(fallback.hash()) % options.size()]

## Classe che un popolano consiglia per sé: quella che sfrutta meglio le sue statistiche,
## con una spinta verso quella a cui pende il mestiere. Restituisce anche la seconda scelta.
func class_advice(stats: Dictionary, job: String) -> Dictionary:
	var total := float(stats.str + stats.int + stats.sta + stats.agi)
	var lean := str(COMMONER_JOBS.get(job, {}).get("lean", ""))
	var ranked := []
	for key in ROLES:
		var w: Array = ROLES[key].weights
		var score: float = (stats.str * w[0] + stats.int * w[1] + stats.sta * w[2] + stats.agi * w[3]) / maxf(1.0, total)
		if key == lean: score += 0.025
		ranked.append([score, key])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var best := str(ranked[0][1])
	var alt := str(ranked[1][1])
	var line := str(COMMONER_JOBS.get(job, {}).get("line", ""))
	var text := "«%s %s Se preferisci, me la caverei anche come %s.»" % [line, ROLE_PITCH[best], role_label(alt)]
	return {"role": best, "alt": alt, "text": text}

static func is_commoner(hero: Dictionary) -> bool:
	return bool(hero.get("commoner", false))

## Popolano che aspetta ancora che il giocatore gli dia una classe.
static func needs_class(hero: Dictionary) -> bool:
	return is_commoner(hero) and not bool(hero.get("class_chosen", true)) and str(hero.get("state", "ALIVE")) == "ALIVE"

## Nome della classe da mostrare: i popolani senza classe mostrano il mestiere.
static func hero_class_label(hero: Dictionary) -> String:
	if needs_class(hero): return "Popolano · " + str(hero.get("job", hero.get("profession", "")))
	return role_label(str(hero.get("role", "")))

## Il giocatore dà una classe a un popolano: abilità e armi da classe, il resto resta suo.
func choose_class(hero_id: String, role: String) -> Dictionary:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state != "ALIVE": return {"ok": false, "message": "Eroe non disponibile"}
	if not needs_class(hero): return {"ok": false, "message": "Ha già una classe"}
	if not ROLES.has(role): return {"ok": false, "message": "Classe sconosciuta"}
	hero.role = role
	hero.class_name = role
	hero.class_chosen = true
	hero.skills[0] = {"name": ROLES[role].skill, "level": 1, "xp": 0}
	var kit := _starter_equipment(role)
	var equipment: Dictionary = hero.equipment
	equipment.main = kit.main
	equipment.sub = kit.sub
	if str(equipment.armor.get("name", "")) == "Abiti da lavoro": equipment.armor = kit.armor
	var followed := role == str(hero.get("recommended_role", ""))
	hero.memories.push_front("Ha lasciato il mestiere di %s per diventare %s%s." % [str(hero.get("job", "")).to_lower(), role_label(role), " come aveva chiesto" if followed else ""])
	hero.morale = clampi(int(hero.morale) + (8 if followed else 2), 0, 100)
	add_event("HERO", "Nuova classe", "%s, ex %s, ora è %s." % [hero.name, str(hero.get("job", "")).to_lower(), role_label(role)], "good")
	state_changed.emit()
	save_game()
	return {"ok": true, "message": "%s ora è %s." % [hero.name, role_label(role)]}

## Aspetto deterministico derivato dall'id: non altera la sequenza RNG storica degli eroi.
func hero_appearance(hero: Dictionary) -> Dictionary:
	return appearance_for(hero)

const FEMININE_NAMES := ["Aella", "Doria", "Fara", "Hesta", "Kaia", "Mira", "Neris", "Pyria", "Rhea", "Tavia", "Veya", "Wren", "Yara"]
const HAIR_COLORS := ["#1b181d", "#1b181d", "#2a201b", "#2a201b", "#46301f", "#6a4429", "#9a6a43", "#c49a5e", "#dcc287", "#7d2a24", "#b0452f", "#bdb7bd", "#26304a", "#43263f"]
const EYE_COLORS := ["#4a2c1e", "#4a2c1e", "#6e2424", "#9c7426", "#3b6b49", "#3a5f8f", "#5d6470", "#5e4287"]
const SKIN_TONES := ["#f1dccc", "#ecd0bb", "#e4c0a2", "#d2a581", "#b98663", "#8f5f45", "#6b4533"]
const OUTFIT_COLORS := ["#3a2e29", "#2d3236", "#352c3f", "#2c3830", "#46322a", "#262c3c", "#472a2f", "#3d3a33"]

static func is_feminine(hero: Dictionary) -> bool:
	return FEMININE_NAMES.has(str(hero.get("name", "Hero")).split(" ")[0])

## Archetipo del foglio da cui vengono volto, capelli, corporatura ed età:
## il mestiere per i popolani, la classe per gli altri.
static func base_archetype(hero: Dictionary) -> String:
	var job := str(hero.get("job", ""))
	if bool(hero.get("commoner", false)) and COMMONER_JOBS.has(job): return str(COMMONER_JOBS[job].look)
	return str(HeroLookScript.CLASS_ARCHETYPE.get(str(hero.get("role", "Guardian")), "villager"))

## Vestiti di adesso: abiti da mestiere finché il popolano non ha una classe.
static func outfit_kind(hero: Dictionary) -> String:
	var job := str(hero.get("job", ""))
	if bool(hero.get("commoner", false)) and not bool(hero.get("class_chosen", true)) and COMMONER_JOBS.has(job): return str(COMMONER_JOBS[job].look)
	return str(HeroLookScript.CLASS_OUTFIT.get(str(hero.get("role", "Guardian")), "villager"))

## Tratti fisici del modello 3D (e quindi della carta), sempre uguali per lo stesso eroe.
## Pezzi dal foglio dei personaggi (archetipo, volto, capigliatura, corporatura, età),
## colori di pelle, capelli e occhi dal generatore personaggi.
static func appearance_for(hero: Dictionary) -> Dictionary:
	var id := str(hero.get("id", "x"))
	var h: int = abs(id.hash())
	var fem: bool = is_feminine(hero)
	var hue := float(hero.get("hue", 40)) / 360.0
	var gen: Dictionary = hero.get("appearance", {})
	if gen.is_empty(): gen = CharacterGeneratorScript.generate(id + ":appearance")
	var piece: Dictionary = hero.get("look", {})
	if piece.is_empty() or int(piece.get("v", 0)) < HeroLookScript.VERSION:
		piece = HeroLookScript.generate(id, base_archetype(hero), fem, int(hero.get("native_rarity", hero.get("current_rarity", 1))), gen)
	var age := int(piece.get("age", 28))
	var face := int(piece.get("face", 1))
	var archetype := str(piece.get("archetype", "villager"))
	var family := str(gen.get("hair_color", ""))
	var hair := Color(str(gen.get("hair_hex", HAIR_COLORS[(h / 3) % HAIR_COLORS.size()])))
	# capelli che ingrigiscono con l'età
	if age >= 46 and not family in ["white", "silver"]: hair = hair.lerp(Color("#cfc9c4"), clampf((age - 44) / 26.0, 0.0, 0.75))
	var beard := 0
	if not fem and age >= 20:
		match str(gen.get("facial_hair", "none")):
			"beard": beard = 2 if age >= 30 else 1
			"stubble", "moustache": beard = 1
		if face == 2 and age >= 26 and beard == 0 and (h / 17) % 2 == 0: beard = 1
	var body := str(piece.get("body", "average"))
	var job := str(hero.get("job", ""))
	return {
		"hair": hair,
		"hair_color": family,
		"skin": Color(str(gen.get("skin_hex", SKIN_TONES[(h / 11) % SKIN_TONES.size()]))),
		"eyes": Color(str(gen.get("eye_hex", EYE_COLORS[(h / 7) % EYE_COLORS.size()]))),
		"eye_color": str(gen.get("eye_color", "")),
		"fem": fem,
		"archetype": archetype,
		"outfit_kind": outfit_kind(hero),
		"face": face,
		"hair_kind": str(piece.get("hair", "short")),
		"body": body,
		"age": age,
		"beard": beard,
		# il volto "calmo" dello studioso porta gli occhiali, come nel foglio
		"glasses": bool(gen.get("glasses", false)) or (archetype == "scholar" and face == 1),
		"scar": (bool(gen.get("scar", false)) or str(gen.get("face_detail", "")) == "scar") and face != 0,
		"freckles": str(gen.get("face_detail", "")) == "freckles",
		"eye_size": 1.0 + (float(gen.get("eye_size", 1.0)) - 1.0) * 0.3,
		"height": 1.0 + (float(gen.get("height_scale", 1.0)) - 1.0) * 0.35,
		"outfit": Color(str(gen.get("outfit_hex", OUTFIT_COLORS[(h / 13) % OUTFIT_COLORS.size()]))),
		"accent": Color.from_hsv(hue, 0.52, 0.58),
		"category": str(gen.get("category", "")),
		"seed": h,
		"veteran": age >= 50,
		# attrezzo del mestiere in mano finché non ha una classe
		"prop": str(COMMONER_JOBS.get(job, {}).get("prop", "")) if bool(hero.get("commoner", false)) and not bool(hero.get("class_chosen", true)) else "",
		# disegno 2D di riserva (carte quando il 3D non è disponibile)
		"hair_style": {"long_straight": 2, "long_wavy": 2, "braid": 3, "tied_back": 3, "bun": 3, "messy": 1, "short": 0, "crop": 0, "slicked": 0}.get(str(piece.get("hair", "")), 5 if fem else 0),
		"portrait": "",
	}

func _starter_equipment(role: String) -> Dictionary:
	var names := {"Guardian": "Spada da presidio", "Vanguard": "Lama mercenaria", "Lancer": "Lancia d'acciaio", "Ranger": "Arco laminato", "Mage": "Verga di quarzo", "Support": "Mazza cerimoniale"}
	var armor := 18 if role == "Guardian" else 12 if role in ["Vanguard", "Lancer"] else 7
	return {"main": {"name": names.get(role, "Arma"), "grade": "D", "power": 15}, "sub": {"name": "Scudo" if role == "Guardian" else "Focus" if role in ["Mage", "Support"] else "Faretra" if role == "Ranger" else "Off-hand", "grade": "D", "block": 18 if role == "Guardian" else 0, "ammo": 24 if role == "Ranger" else 0}, "armor": {"name": "Equipaggiamento da campo", "grade": "D", "defense": armor}, "accessory": {}}

## Valutazione mostrata nella scheda. Non dice mai quanto in fretta l'eroe impara o
## quanto può crescere (potenziale): deve scoprirlo il giocatore (regola del proprietario).
func _assessment(hero: Dictionary) -> Array:
	var output := []
	var best_stat := "str"
	for key in hero.stats:
		if hero.stats[key] > hero.stats[best_stat]: best_stat = key
	output.append("Affinità evidente: %s (%s)" % [STAT_LABELS[best_stat][0], STAT_LABELS[best_stat][1]])
	return output

## Valutazione aggiornata alle statistiche di adesso (per la scheda).
func hero_assessment(hero: Dictionary) -> Array:
	return _assessment(hero)

## Livelli di stanchezza: da "min" in su l'eroe subisce questi malus, in missione
## e nella potenza. hp/atk/def moltiplicano vita, attacco/magia e difesa; acc e
## eva tolgono punti di precisione e schivata; speed rallenta il passo; cadence
## allunga la pausa tra un attacco e l'altro. Chi è Sfinito non può partire.
const FATIGUE_LEVELS := [
	{"min": 0, "name": "Riposato", "hp": 1.0, "atk": 1.0, "def": 1.0, "acc": 0.0, "eva": 0.0, "speed": 1.0, "cadence": 1.0},
	{"min": 40, "name": "Stanco", "hp": 1.0, "atk": 0.9, "def": 0.95, "acc": 5.0, "eva": 2.0, "speed": 0.92, "cadence": 1.1},
	{"min": 70, "name": "Esausto", "hp": 0.9, "atk": 0.75, "def": 0.85, "acc": 12.0, "eva": 5.0, "speed": 0.8, "cadence": 1.25},
	{"min": 90, "name": "Sfinito", "hp": 0.8, "atk": 0.6, "def": 0.7, "acc": 20.0, "eva": 10.0, "speed": 0.7, "cadence": 1.45},
]
## Stanchezza da cui l'eroe non può più partire per la Torre.
const FATIGUE_NO_DEPLOY := 90

func fatigue_level(hero: Dictionary) -> Dictionary:
	var fatigue := float(hero.get("fatigue", 0))
	var result: Dictionary = FATIGUE_LEVELS[0]
	for level in FATIGUE_LEVELS:
		if fatigue >= float(level.min): result = level
	return result

## Testo breve dei malus, per schede e avvisi ("" se l'eroe è riposato).
func fatigue_penalty_text(hero: Dictionary) -> String:
	var f := fatigue_level(hero)
	if float(f.atk) >= 1.0: return ""
	var parts := ["Attacco -%d%%" % roundi((1.0 - float(f.atk)) * 100), "Difesa -%d%%" % roundi((1.0 - float(f.def)) * 100)]
	if float(f.hp) < 1.0: parts.append("Vita -%d%%" % roundi((1.0 - float(f.hp)) * 100))
	parts.append("Precisione -%d" % roundi(float(f.acc)))
	parts.append("più lento")
	return "%s: %s" % [str(f.name), ", ".join(parts)]

func derived_stats(hero: Dictionary) -> Dictionary:
	var equipment: Dictionary = hero.equipment
	var accessory: Dictionary = equipment.get("accessory", {})
	var f := fatigue_level(hero)
	var k := skill_effects(hero)
	var max_hp := roundi((100 + hero.stats.sta * 12 + hero.level * 6 + int(accessory.get("hp", 0))) * float(f.hp) * (1.0 + k.hp))
	return {
		"max_hp": max_hp,
		"attack": (float(equipment.main.get("power", 0)) + hero.stats.str * 1.75) * float(f.atk) * (1.0 + k.atk),
		"magic": (hero.stats.int * 1.9 + (12 if hero.role in ["Mage", "Support"] else 0) + float(equipment.main.get("power", 0)) * (0.6 if hero.role in ["Mage", "Support"] else 0.0)) * float(f.atk) * (1.0 + k.atk),
		"defense": (float(equipment.armor.get("defense", 0)) + hero.stats.sta * 0.55) * float(f.def) * (1.0 + k.def),
		"accuracy": clampf(70 + hero.stats.agi * 0.45 - float(f.acc) + k.acc, 35, 98),
		"evasion": clampf(hero.stats.agi * 0.22 - float(f.eva) + k.eva, 0, 40),
		"crit": clampf(3 + hero.stats.agi * 0.08 + k.crit, 3, 35),
		"heal_mult": 1.0 + k.heal,
		"fear_resist": k.fear,
		"block": equipment.sub.get("block", 0),
		"ammo": equipment.sub.get("ammo", 0),
		"speed_mult": float(f.speed),
		"cadence_mult": float(f.cadence),
		"fatigue_state": str(f.name),
	}

func hero_power(hero: Dictionary) -> int:
	if hero.is_empty() or hero.state != "ALIVE": return 0
	var d := derived_stats(hero)
	var attack: float = max(d.attack * 0.75, d.magic) if hero.role in ["Mage", "Support"] else d.attack
	var injury_factor := 0.85 if not hero.get("injuries", []).is_empty() else 1.0
	return roundi((d.max_hp * 0.22 + attack * 3 + d.defense * 2) * (0.8 + hero.morale / 500.0) * injury_factor)

func level_cap(hero: Dictionary) -> int:
	return int(RARITY_CAPS.get(int(hero.current_rarity), 10))

func xp_to_next(level: int) -> int:
	return roundi(30.0 + 14.0 * pow(float(level), 1.45))

## Aggiunge esperienza applicando i level-up fino al cap della rarità corrente.
func add_xp(hero: Dictionary, amount: float) -> int:
	if hero.is_empty() or hero.state != "ALIVE": return 0
	var gained_levels := 0
	var cap := level_cap(hero)
	if int(hero.level) >= cap:
		hero.xp = 0
		return 0
	hero.xp = float(hero.get("xp", 0)) + amount
	while int(hero.level) < cap and float(hero.xp) >= xp_to_next(int(hero.level)):
		hero.xp = float(hero.xp) - xp_to_next(int(hero.level))
		_apply_level_up(hero)
		gained_levels += 1
	if int(hero.level) >= cap: hero.xp = 0
	return gained_levels

func _apply_level_up(hero: Dictionary) -> void:
	hero.level = int(hero.level) + 1
	for key in hero.stats: hero.stats[key] = int(hero.stats[key]) + max(1, roundi(float(hero.growth) * (0.42 if key in ["str", "sta"] else 0.30)))
	hero_leveled.emit(str(hero.id), int(hero.level))
	if int(hero.level) % 5 == 0 or int(hero.level) == level_cap(hero):
		add_event("HERO", "%s raggiunge il Lv.%d" % [hero.name, hero.level], "Crescita registrata dal Centro di Addestramento.", "good")

func get_alive_heroes() -> Array:
	return data.heroes.filter(func(hero): return hero.state == "ALIVE")

func hero_by_id(hero_id: String) -> Dictionary:
	for hero in data.heroes:
		if hero.id == hero_id: return hero
	return {}

## Stato leggibile dell'eroe nella base: "party", "training", "resting", "injured", "idle", "dead".
func hero_activity(hero: Dictionary) -> String:
	if hero.is_empty() or hero.state != "ALIVE": return "dead"
	var assignment: Dictionary = data.assignments.get(str(hero.id), {})
	if not assignment.is_empty(): return "training" if assignment.facility == "training" else "resting"
	if not hero.get("injuries", []).is_empty(): return "injured"
	if data.party.has(hero.id): return "party"
	return "idle"

# =============================================================================
# Party
# =============================================================================

func get_party() -> Array:
	var output := []
	for hero_id in data.party:
		var hero := hero_by_id(hero_id)
		output.append(hero if not hero.is_empty() and hero.state == "ALIVE" else {})
	return output

func assign_party(slot: int, hero_id: String) -> bool:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state != "ALIVE" or slot < 0 or slot >= PARTY_SIZE: return false
	var previous: int = data.party.find(hero_id)
	var displaced: String = data.party[slot]
	if previous >= 0: data.party[previous] = displaced if previous != slot else ""
	data.party[slot] = hero_id
	save_and_notify()
	return true

func remove_party(slot: int) -> void:
	if slot >= 0 and slot < PARTY_SIZE:
		data.party[slot] = ""
		save_and_notify()

func party_readiness() -> Dictionary:
	var party := get_party()
	var score := 0
	var warnings := []
	var alive := 0
	for i in party.size():
		var hero: Dictionary = party[i]
		if hero.is_empty(): continue
		alive += 1
		score += hero_power(hero)
		if float(hero.fatigue) >= FATIGUE_NO_DEPLOY: warnings.append(hero.name + " è sfinito: non può partire, mandalo al Dormitorio")
		elif float(hero.fatigue) >= 40: warnings.append(hero.name + " · " + fatigue_penalty_text(hero))
		if not hero.injuries.is_empty(): warnings.append(hero.name + " è ferito")
		if data.assignments.has(hero.id): warnings.append(hero.name + " lascerà la sua attività")
		var line: String = ROLES[hero.role].line
		if line != FORMATION_LINES[i]: warnings.append("%s (%s) è fuori ruolo in %s" % [hero.name, line, FORMATION_LINES[i]])
	if alive < PARTY_SIZE: warnings.append("Squadra incompleta: %d/%d" % [alive, PARTY_SIZE])
	var grade := "S" if score >= 2200 else "A" if score >= 1700 else "B" if score >= 1200 else "C" if score >= 800 else "D"
	var exhausted := party.filter(func(hero): return not hero.is_empty() and float(hero.fatigue) >= FATIGUE_NO_DEPLOY).size()
	return {"score": score, "grade": grade, "warnings": warnings, "ready": alive == PARTY_SIZE and exhausted == 0}

# =============================================================================
# Base e strutture
# =============================================================================

func base_level() -> int:
	return int(data.world.get("base_level", 1))

func facility_level(id: String) -> int:
	return int(data.facilities.get(id, {}).get("level", 0))

func facility_built(id: String) -> bool:
	return facility_level(id) > 0

## Sbloccata ma non ancora costruita: nella base appare come cantiere.
func facility_available(id: String) -> bool:
	return not facility_built(id) and base_level() >= int(FACILITIES[id].unlock) and floor_cleared(int(FACILITIES[id].get("unlock_floor", 0)))

## Messaggio su cosa manca per aprire il cantiere di una struttura.
func facility_unlock_text(id: String) -> String:
	var info: Dictionary = FACILITIES[id]
	if base_level() < int(info.unlock): return "Serve la Base Lv.%d" % int(info.unlock)
	if not floor_cleared(int(info.get("unlock_floor", 0))): return "Completa il Piano %d" % int(info.unlock_floor)
	return ""

## Il piano è stato completato almeno una volta (0 = nessun requisito).
func floor_cleared(floor_index: int) -> bool:
	if floor_index <= 0 or dev_override(): return true
	return bool(data.stages.get(str(floor_index), {}).get("cleared", false))

func facility_max_level() -> int:
	return mini(base_level(), FACILITY_MAX_LEVEL)

## Costo del prossimo livello: cresce del 85% a livello fino al Lv.5, poi del 40%.
func facility_upgrade_cost(id: String) -> Dictionary:
	var level := facility_level(id)
	var growth := pow(1.85, mini(level, 5) - 1) * pow(1.4, maxi(0, level - 5))
	return {"gold": roundi(float(FACILITIES[id].upgrade_cost) * growth)}

## Isole della base già aggiunte (in ordine).
func base_islands() -> Array:
	return BASE_ISLANDS.filter(func(island): return base_level() >= int(island.level))

func has_island(id: String) -> bool:
	for island in base_islands():
		if str(island.id) == id: return true
	return false

## Isola che arriverà con il prossimo livello della base (vuoto se nessuna).
func next_island() -> Dictionary:
	var next := next_base_level()
	if next.is_empty(): return {}
	for island in BASE_ISLANDS:
		if int(island.level) == int(next.level): return island
	return {}

func can_upgrade_facility(id: String) -> Dictionary:
	if not facility_built(id): return {"ok": false, "message": "Struttura non costruita"}
	if facility_level(id) >= FACILITY_MAX_LEVEL: return {"ok": false, "message": "Livello massimo raggiunto"}
	if facility_level(id) >= facility_max_level(): return {"ok": false, "message": "Serve la Base Lv.%d" % (facility_level(id) + 1)}
	if not can_afford(facility_upgrade_cost(id)): return {"ok": false, "message": "Oro insufficiente"}
	return {"ok": true, "message": ""}

func upgrade_facility(id: String) -> Dictionary:
	var check := can_upgrade_facility(id)
	if not check.ok: return check
	pay(facility_upgrade_cost(id), "Potenziamento " + FACILITIES[id].name, "facility")
	data.facilities[id].level = facility_level(id) + 1
	add_event("BASE", "%s Lv.%d" % [FACILITIES[id].name, facility_level(id)], "La struttura cresce di un piano." if facility_level(id) <= 3 else "La struttura si fa più imponente.", "good")
	save_and_notify()
	return {"ok": true, "level": facility_level(id)}

func build_facility(id: String) -> Dictionary:
	if not FACILITIES.has(id): return {"ok": false, "message": "Struttura sconosciuta"}
	if facility_built(id): return {"ok": false, "message": "Già costruita"}
	if not facility_available(id): return {"ok": false, "message": facility_unlock_text(id)}
	var cost := {"gold": int(FACILITIES[id].build_cost)}
	if not pay(cost, "Costruzione " + FACILITIES[id].name, "facility"): return {"ok": false, "message": "Oro insufficiente"}
	data.facilities[id].level = 1
	add_event("BASE", FACILITIES[id].name + " costruita", "Una nuova struttura si aggiunge alla base.", "good")
	save_and_notify()
	return {"ok": true}

func next_base_level() -> Dictionary:
	var level := base_level()
	if level >= BASE_LEVELS.size(): return {}
	return BASE_LEVELS[level]

func can_upgrade_base() -> Dictionary:
	var next := next_base_level()
	if next.is_empty(): return {"ok": false, "message": "La base è al livello massimo"}
	if cleared_floor_count() < int(next.floor) and not dev_override(): return {"ok": false, "message": "Completa il Piano %d" % int(next.floor)}
	if not can_afford({"gold": int(next.gold)}): return {"ok": false, "message": "Oro insufficiente"}
	return {"ok": true, "message": ""}

func upgrade_base() -> Dictionary:
	var check := can_upgrade_base()
	if not check.ok: return check
	var next := next_base_level()
	pay({"gold": int(next.gold)}, "Espansione della base", "base")
	data.world.base_level = int(next.level)
	var unlocked := []
	for id in FACILITY_ORDER:
		if int(FACILITIES[id].unlock) == int(next.level): unlocked.append(FACILITIES[id].name)
	var island := {}
	for candidate in BASE_ISLANDS:
		if int(candidate.level) == int(next.level): island = candidate
	var text := "Le strutture possono crescere di un livello."
	if not unlocked.is_empty(): text = "Nuovi cantieri: " + ", ".join(unlocked)
	if not island.is_empty(): text = "Nuova isola collegata da un ponte: %s (%s)." % [str(island.name), str(island.bonus)]
	add_event("BASE", "Base Lv.%d" % int(next.level), text, "good")
	save_and_notify()
	return {"ok": true, "level": int(next.level), "unlocked": unlocked, "island": island}

func cleared_floor_count() -> int:
	var count := 0
	for key in data.stages:
		if bool(data.stages[key].get("cleared", false)): count += 1
	return count

## Requisiti di progressione ignorati solo con la modalità sviluppo accesa.
func dev_override() -> bool:
	return bool(data.dev.get("enabled", false)) and bool(data.dev.get("all_content", false))

func material_cap() -> int:
	return 60 + 80 * facility_level("warehouse")

# --- Assegnazioni (addestramento e riposo) -----------------------------------

func training_slots() -> int:
	return 2 + facility_level("training") + (2 if has_island("campi") else 0)

func dormitory_slots() -> int:
	return 5 + 2 * (facility_level("dormitory") - 1) + (6 if has_island("dimore") else 0)

func assigned_to(facility: String) -> Array:
	var output := []
	for hero_id in data.assignments:
		if data.assignments[hero_id].facility == facility:
			var hero := hero_by_id(hero_id)
			if not hero.is_empty(): output.append(hero)
	return output

func training_xp_per_minute(hero: Dictionary) -> float:
	var level := maxi(1, facility_level("training"))
	return 14.0 * (1.0 + 0.35 * (level - 1)) * (0.8 + float(hero.get("potential", 50)) / 250.0) * (1.0 + float(hero.level) * 0.06)

func assign_hero(hero_id: String, facility: String) -> Dictionary:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state != "ALIVE": return {"ok": false, "message": "Eroe non disponibile"}
	if not facility in ["training", "dormitory"]: return {"ok": false, "message": "Attività non valida"}
	if not facility_built(facility): return {"ok": false, "message": "Struttura non costruita"}
	var current: Dictionary = data.assignments.get(hero_id, {})
	if not current.is_empty() and current.facility == facility: return {"ok": true}
	var used := assigned_to(facility).size()
	var slots := training_slots() if facility == "training" else dormitory_slots()
	if used >= slots: return {"ok": false, "message": "Posti esauriti (%d/%d)" % [used, slots]}
	if facility == "training":
		if int(hero.level) >= level_cap(hero): return {"ok": false, "message": "Cap di livello raggiunto: serve una promozione"}
		if not hero.injuries.is_empty(): return {"ok": false, "message": "Un eroe ferito non può allenarsi"}
		if int(hero.fatigue) >= 85: return {"ok": false, "message": "Troppo stanco per allenarsi"}
	data.assignments[hero_id] = {"facility": facility, "since": now()}
	save_and_notify()
	return {"ok": true}

func unassign_hero(hero_id: String) -> void:
	if data.assignments.erase(hero_id): save_and_notify()

## Avanza il tempo della base. Restituisce true se qualcosa di visibile è cambiato.
func advance_time(seconds: float) -> bool:
	if seconds <= 0.0 or data.is_empty(): return false
	var minutes := seconds / 60.0
	var changed := false
	var finished := []
	for hero_id in data.assignments.keys():
		var hero := hero_by_id(hero_id)
		var assignment: Dictionary = data.assignments[hero_id]
		if hero.is_empty() or hero.state != "ALIVE":
			finished.append(hero_id)
			continue
		if assignment.facility == "training":
			add_xp(hero, training_xp_per_minute(hero) * minutes)
			hero.fatigue = clampf(float(hero.fatigue) + 1.2 * minutes, 0.0, 100.0)
			if int(hero.level) >= level_cap(hero):
				finished.append(hero_id)
				add_event("TRAINING", hero.name + " ha raggiunto il cap", "Lv.%d: serve una promozione al Centro di Fusione." % hero.level, "warn")
			elif float(hero.fatigue) >= 90.0:
				finished.append(hero_id)
				add_event("TRAINING", hero.name + " interrompe l'allenamento", "Troppo stanco: mandalo al Dormitorio.", "warn")
			changed = true
		else:
			var level := maxi(1, facility_level("dormitory"))
			var rate := 1.0 + 0.25 * (level - 1)
			hero.fatigue = clampf(float(hero.fatigue) - 3.0 * rate * minutes, 0.0, 100.0)
			hero.morale = clampf(float(hero.morale) + 1.0 * rate * minutes, 0.0, 100.0)
			var injuries: Array = hero.injuries
			if not injuries.is_empty():
				injuries[0].minutes = float(injuries[0].minutes) - minutes * rate
				if float(injuries[0].minutes) <= 0.0:
					var healed: Dictionary = injuries.pop_front()
					add_event("DORMITORIO", hero.name + " è guarito", "%s risolta." % healed.name, "good")
			if float(hero.fatigue) <= 0.0 and float(hero.morale) >= 100.0 and injuries.is_empty():
				finished.append(hero_id)
			changed = true
	for hero_id in finished:
		data.assignments.erase(hero_id)
		var done := hero_by_id(hero_id)
		if not done.is_empty():
			done.fatigue = roundi(float(done.fatigue))
			done.morale = roundi(float(done.morale))
	return changed

# =============================================================================
# Evocazione, fusione e promozione
# =============================================================================

func summon_pool_unlocked(pool: String) -> bool:
	var info: Dictionary = SUMMON_POOLS.get(pool, {})
	if info.is_empty(): return false
	return cleared_floor_count() >= int(info.get("unlock_floor", 0)) or dev_override()

func summon(pool: String, count: int) -> Dictionary:
	var info: Dictionary = SUMMON_POOLS.get(pool, {})
	if info.is_empty(): return {"ok": false, "message": "Pool sconosciuto"}
	if not summon_pool_unlocked(pool): return {"ok": false, "message": "Si sblocca completando il Piano %d" % int(info.unlock_floor)}
	if not _pay(str(info.currency), int(info.cost) * count, "Evocazione " + str(info.name), "summon"): return {"ok": false, "message": "Risorse insufficienti"}
	var heroes := []
	for i in count:
		data.summon_counter += 1
		var rng := rng_for(str(data.world.seed) + ":summon:" + str(data.summon_counter))
		var roll := rng.randf_range(0.0, 100.0)
		var rarity := _roll_rarity(pool, roll)
		var hero := generate_hero(str(data.world.seed) + ":hero:" + str(data.summon_counter), rarity)
		data.heroes.append(hero)
		heroes.append(hero)
		if rarity >= 5: add_event("SUMMON", "%s %s risponde alla chiamata" % [stars(rarity), hero.name], "Una risonanza rara attraversa il Nexus.", "good")
	add_event("SUMMON", "%d evocazioni completate" % count, str(info.name) + " · nuovi eroi arrivati alla base.", "good")
	save_and_notify()
	return {"ok": true, "heroes": heroes}

## Anti-blocco: se restano meno di 5 eroi vivi, il Nexus richiama gratis un eroe 1★
## ogni 30 minuti. Non è una resurrezione: è sempre un eroe nuovo.
const EMERGENCY_COOLDOWN := 1800.0

func emergency_recruit_status() -> Dictionary:
	if get_alive_heroes().size() >= PARTY_SIZE: return {"ok": false, "message": "Hai già abbastanza eroi", "visible": false}
	var wait := float(data.world.get("emergency_at", 0.0)) + EMERGENCY_COOLDOWN - now()
	if wait > 0.0: return {"ok": false, "message": "Di nuovo disponibile tra %d min" % ceili(wait / 60.0), "visible": true}
	return {"ok": true, "message": "", "visible": true}

func emergency_recruit() -> Dictionary:
	var status := emergency_recruit_status()
	if not status.ok: return status
	data.summon_counter += 1
	var hero := generate_hero(str(data.world.seed) + ":emergency:" + str(data.summon_counter), 1)
	data.heroes.append(hero)
	data.world.emergency_at = now()
	add_event("SUMMON", hero.name + " risponde al richiamo", "Il Nexus ha chiamato una recluta per rimettere in piedi la squadra.", "info")
	save_and_notify()
	return {"ok": true, "hero": hero}

func _roll_rarity(pool: String, roll: float) -> int:
	if pool == "high":
		data.pity.high = int(data.pity.high) + 1
		var five_rate: float = 1.0 + max(0, int(data.pity.high) - (HIGH_SOFT_PITY - 1)) * 0.25
		if int(data.pity.high) >= HIGH_HARD_PITY or roll < five_rate:
			data.pity.high = 0
			return 5
		return 4 if roll < five_rate + 5.5 else 3
	var rates: Array = SUMMON_POOLS[pool].rates
	# Le rarità più alte vengono controllate per prime: roll basso = esito raro.
	var threshold := 0.0
	for index in range(rates.size() - 1, 0, -1):
		threshold += float(rates[index][1])
		if roll < threshold: return int(rates[index][0])
	return int(rates[0][0])

# --- Fusione (regola del proprietario, 2026-11-12) ------------------------------
## Si fondono due eroi: il primo resta, il secondo viene sacrificato per sempre. Chi resta
## prende una parte delle statistiche del sacrificato e a volte una sua abilità. La rarità
## non cambia (le stelle salgono solo con la promozione). Ogni eroe ha un margine nascosto
## (dal potenziale): quando l'ha riempito, la fusione non gli dà più statistiche.

## Quota delle statistiche del sacrificato che passa a chi resta: 10% + 1% per livello del Centro.
func merge_retention() -> float:
	return 0.10 + 0.01 * maxf(0.0, float(facility_level("merging") - 1))

## Margine nascosto: punti statistica che un eroe può prendere in tutto con le fusioni.
static func merge_capacity(hero: Dictionary) -> int:
	return roundi(float(hero.get("potential", 50)) * 4.0)

## Abilità particolari che il sacrificato può passare: nuove (se c'è posto) o da migliorare.
func inheritable_skills(survivor: Dictionary, sacrifice: Dictionary) -> Array:
	var owned := {}
	for skill in particular_skills(survivor): owned[str(skill.name)] = int(skill.get("level", 1))
	var output := []
	for skill in particular_skills(sacrifice):
		var skill_name := str(skill.name)
		if owned.has(skill_name):
			if int(owned[skill_name]) < SKILL_MAX_LEVEL: output.append(skill_name)
		elif owned.size() < SKILL_SLOTS: output.append(skill_name)
	return output

## Punti statistica che passerebbero (già limitati dal margine nascosto) e abilità possibili.
func _merge_plan(survivor: Dictionary, sacrifice: Dictionary) -> Dictionary:
	var retention := merge_retention()
	var gains := {}
	var total := 0
	for key in STAT_ORDER:
		gains[key] = maxi(1, roundi(float(sacrifice.stats.get(key, 0)) * retention))
		total += int(gains[key])
	var room := maxi(0, merge_capacity(survivor) - int(survivor.get("merge_gain", 0)))
	if total > room:
		var scale := float(room) / float(total)
		total = 0
		for key in gains:
			gains[key] = floori(float(gains[key]) * scale)
			total += int(gains[key])
	return {"gains": gains, "total": total, "skills": inheritable_skills(survivor, sacrifice)}

func validate_merge_heroes(hero_ids: Array) -> Dictionary:
	if hero_ids.size() != 2:
		return {"ok": false, "message": "Scegli due eroi: chi resta e chi viene sacrificato.", "heroes": []}
	if str(hero_ids[0]) == str(hero_ids[1]):
		return {"ok": false, "message": "Servono due eroi diversi.", "heroes": []}
	var heroes: Array = []
	for value in hero_ids:
		var hero := hero_by_id(str(value))
		if hero.is_empty() or str(hero.state) != "ALIVE":
			return {"ok": false, "message": "Uno degli eroi non è disponibile.", "heroes": []}
		heroes.append(hero)
	var sacrifice: Dictionary = heroes[1]
	if data.party.has(str(sacrifice.id)):
		return {"ok": false, "message": "%s è nella squadra: toglilo prima di sacrificarlo." % sacrifice.name, "heroes": []}
	var plan := _merge_plan(heroes[0], sacrifice)
	if int(plan.total) <= 0 and plan.skills.is_empty():
		return {"ok": false, "message": "%s ha raggiunto il suo limite: questa fusione non lo renderebbe più forte." % heroes[0].name, "heroes": []}
	return {"ok": true, "message": "Fusione pronta.", "heroes": heroes, "skills": plan.skills}

func merge_heroes(hero_ids: Array) -> Dictionary:
	var validation := validate_merge_heroes(hero_ids)
	if not bool(validation.ok): return validation
	var survivor: Dictionary = validation.heroes[0]
	var sacrifice: Dictionary = validation.heroes[1]
	var plan := _merge_plan(survivor, sacrifice)
	for key in plan.gains: survivor.stats[key] = int(survivor.stats[key]) + int(plan.gains[key])
	survivor.merge_gain = int(survivor.get("merge_gain", 0)) + int(plan.total)
	# abilità: al massimo una per fusione; le uniche passano più di rado
	var rng := rng_for(str(survivor.id) + ":" + str(sacrifice.id) + ":fusione")
	var bonus := 0.03 * maxf(0.0, float(facility_level("merging") - 1))
	var candidates: Array = plan.skills.duplicate()
	candidates.sort_custom(func(a, b): return str(SKILLS[a].kind) == "unique" and str(SKILLS[b].kind) != "unique")
	var learned := ""
	var improved := false
	for skill_name in candidates:
		if rng.randf() < (0.35 if str(SKILLS[skill_name].kind) == "unique" else 0.55) + bonus:
			learned = skill_name
			break
	if not learned.is_empty():
		for skill in survivor.skills:
			if str(skill.name) == learned:
				skill.level = mini(SKILL_MAX_LEVEL, int(skill.get("level", 1)) + 1)
				improved = true
		if not improved: survivor.skills.append({"name": learned, "level": 1, "xp": 0})
	survivor.morale = mini(100, int(survivor.morale) + 5)
	# l'equipaggiamento forgiato del sacrificato torna in magazzino
	for slot in sacrifice.equipment:
		var item = sacrifice.equipment[slot]
		if item is Dictionary and item.has("id"): data.inventory.append(item.duplicate())
	data.assignments.erase(str(sacrifice.id))
	for index in range(data.heroes.size() - 1, -1, -1):
		if str(data.heroes[index].id) == str(sacrifice.id): data.heroes.remove_at(index)
	survivor.memories.push_front("Ha assorbito l'eco di %s." % sacrifice.name)
	var parts := []
	for key in STAT_ORDER:
		if int(plan.gains[key]) > 0: parts.append("+%d %s" % [int(plan.gains[key]), STAT_LABELS[key][0]])
	var text := "%s è stato sacrificato. %s" % [sacrifice.name, ", ".join(parts) if not parts.is_empty() else "Nessuna statistica in più"]
	if not learned.is_empty(): text += " · %s %s" % ["migliora" if improved else "impara", learned]
	add_event("MERGE", survivor.name + " ha completato la fusione", text + ".", "good")
	save_and_notify()
	return {"ok": true, "hero": survivor, "consumed": [str(sacrifice.id)], "gains": plan.gains, "skill": learned, "improved": improved}

func promotion_requirements(hero: Dictionary) -> Dictionary:
	var rarity := int(hero.current_rarity)
	if rarity >= 7: return {"ok": false, "message": "Rarità massima", "stones": 0}
	if rarity >= PROMOTION_MAX_RARITY: return {"ok": false, "message": "La 7ª stella si ottiene solo con l'evocazione", "stones": 0}
	var stones := int(PROMOTION_STONES[rarity])
	if int(hero.level) < level_cap(hero): return {"ok": false, "message": "Raggiungi prima il Lv.%d" % level_cap(hero), "stones": stones}
	var gate := int(PROMOTION_FLOOR_GATE.get(rarity, 0))
	if gate > 0 and cleared_floor_count() < gate and not dev_override(): return {"ok": false, "message": "Completa il Piano %d" % gate, "stones": stones}
	if not can_afford({"stones": stones}): return {"ok": false, "message": "Servono %d Pietre" % stones, "stones": stones}
	return {"ok": true, "message": "", "stones": stones}

func promote_hero(hero_id: String) -> Dictionary:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state != "ALIVE": return {"ok": false, "message": "Eroe non disponibile"}
	var requirements := promotion_requirements(hero)
	if not requirements.ok: return requirements
	_pay("stones", int(requirements.stones), "Promozione " + hero.name, "promotion")
	hero.current_rarity = int(hero.current_rarity) + 1
	hero.xp = 0
	add_event("HERO", hero.name + " promosso", "Rarità corrente: " + stars(hero.current_rarity), "good")
	save_and_notify()
	return {"ok": true}

## Compatibilità: allenamento istantaneo usato dai vecchi strumenti di test.
func train_hero(hero_id: String) -> Dictionary:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state != "ALIVE": return {"ok": false, "message": "Eroe non disponibile"}
	if int(hero.level) >= level_cap(hero): return {"ok": false, "message": "Cap raggiunto: serve una promozione"}
	add_xp(hero, xp_to_next(int(hero.level)) - float(hero.xp))
	save_and_notify()
	return {"ok": true}

# =============================================================================
# Armeria, laboratorio, alchimia
# =============================================================================

const FORGE_RECIPES := {
	"weapon": {"name": "Arma forgiata", "slot": "main", "cost": {"gold": 4000, "ore": 3, "wood": 1}},
	"armor": {"name": "Armatura rinforzata", "slot": "armor", "cost": {"gold": 3500, "ore": 2, "leather": 2}},
	"charm": {"name": "Amuleto del Rift", "slot": "accessory", "cost": {"gold": 6000, "cores": 1, "leather": 1}},
}
## Gradi delle armi forgiate a mano, dal peggiore al migliore.
const GRADES := ["F", "E", "D", "C", "B", "A", "S"]
## Precisione minima (0..1) del minigioco di forgia per ogni grado.
const FORGE_GRADE_THRESHOLDS := [0.0, 0.25, 0.40, 0.55, 0.70, 0.82, 0.92]
## Sotto questa precisione il lavoro fallisce e i materiali sono persi (regola del proprietario).
const FORGE_FAIL_PRECISION := 0.25
## Moltiplicatore delle statistiche per grado (D = valori di prima).
const FORGE_GRADE_MULT := [0.55, 0.75, 1.0, 1.35, 1.75, 2.2, 2.8]
## Difficoltà della forgia: più è difficile, più il minigioco è veloce e stretto,
## ma più alto è il grado massimo che si può ottenere. `unlock` = livello Armeria.
const FORGE_DIFFICULTIES := {
	"easy": {"name": "Facile", "unlock": 1, "max_grade": 3, "speed": 0.75, "window": 1.3, "hits": 4, "gold_mult": 0.8},
	"normal": {"name": "Normale", "unlock": 1, "max_grade": 4, "speed": 1.0, "window": 1.0, "hits": 5, "gold_mult": 1.0},
	"hard": {"name": "Difficile", "unlock": 3, "max_grade": 5, "speed": 1.3, "window": 0.8, "hits": 6, "gold_mult": 1.35},
	"master": {"name": "Maestro", "unlock": 5, "max_grade": 6, "speed": 1.6, "window": 0.65, "hits": 7, "gold_mult": 1.8},
}
const WORKSHOP_RECIPES := {
	"cores": {"name": "Nucleo raffinato", "output": {"cores": 1}, "cost": {"gold": 1500, "ore": 3, "wood": 2}},
	"medicine": {"name": "Kit medico", "output": {"medicine": 1}, "cost": {"gold": 900, "herbs": 2, "leather": 1}},
}
const ALCHEMY_RECIPES := {
	"heal": {"name": "Tonico di sutura", "description": "Guarisce subito la ferita più grave.", "cost": {"gold": 2000, "herbs": 2, "medicine": 1}},
	"morale": {"name": "Elisir del coraggio", "description": "+25 morale, -20 stanchezza.", "cost": {"gold": 2500, "herbs": 3, "cores": 1}},
}

## Costo di una ricetta alla difficoltà scelta (cambia solo l'oro).
func forge_cost(recipe_id: String, difficulty: String = "normal") -> Dictionary:
	var cost: Dictionary = FORGE_RECIPES.get(recipe_id, {}).get("cost", {}).duplicate()
	if cost.has("gold"): cost.gold = roundi(float(cost.gold) * float(FORGE_DIFFICULTIES.get(difficulty, FORGE_DIFFICULTIES.normal).gold_mult))
	return cost

func forge_difficulty_unlocked(difficulty: String) -> bool:
	return FORGE_DIFFICULTIES.has(difficulty) and facility_level("armory") >= int(FORGE_DIFFICULTIES[difficulty].unlock)

## Margine in più nel minigioco: +5% di tolleranza per ogni livello dell'Armeria oltre il primo.
func forge_window_bonus() -> float:
	return 1.0 + 0.05 * maxf(0.0, float(facility_level("armory") - 1))

## Grado che corrisponde a una precisione (0..1), limitato dalla difficoltà.
func forge_grade_index(precision: float, difficulty: String) -> int:
	var index := 0
	for i in FORGE_GRADE_THRESHOLDS.size():
		if precision >= float(FORGE_GRADE_THRESHOLDS[i]): index = i
	return mini(index, int(FORGE_DIFFICULTIES.get(difficulty, FORGE_DIFFICULTIES.normal).max_grade))

func forge_pending() -> Dictionary:
	return data.get("forge_pending", {})

## Primo passo della forgia a mano: paga i materiali e mette il lavoro sull'incudine.
## Il grado arriva con `finish_forge`, dopo il minigioco. Se il gioco si chiude a metà
## la forgia resta in sospeso e si riprende dall'Armeria senza pagare di nuovo.
func begin_forge(recipe_id: String, difficulty: String = "normal") -> Dictionary:
	if not facility_built("armory"): return {"ok": false, "message": "Costruisci prima l'Armeria"}
	if not forge_pending().is_empty(): return {"ok": false, "message": "C'è già un lavoro sull'incudine"}
	var recipe: Dictionary = FORGE_RECIPES.get(recipe_id, {})
	if recipe.is_empty(): return {"ok": false, "message": "Ricetta sconosciuta"}
	if not FORGE_DIFFICULTIES.has(difficulty): return {"ok": false, "message": "Difficoltà sconosciuta"}
	if not forge_difficulty_unlocked(difficulty): return {"ok": false, "message": "Serve l'Armeria Lv.%d" % int(FORGE_DIFFICULTIES[difficulty].unlock)}
	if not pay(forge_cost(recipe_id, difficulty), "Forgia " + recipe.name, "armory"): return {"ok": false, "message": "Risorse insufficienti"}
	data.item_counter = int(data.get("item_counter", 0)) + 1
	data["forge_pending"] = {"recipe": recipe_id, "difficulty": difficulty, "number": int(data.item_counter)}
	save_and_notify()
	return {"ok": true, "pending": data.forge_pending}

## Secondo passo: la precisione del minigioco (0..1) decide il grado, da F a S.
func finish_forge(precision: float) -> Dictionary:
	var pending := forge_pending()
	if pending.is_empty(): return {"ok": false, "message": "Nessun lavoro sull'incudine"}
	var recipe: Dictionary = FORGE_RECIPES.get(str(pending.recipe), {})
	if recipe.is_empty():
		data.erase("forge_pending")
		return {"ok": false, "message": "Ricetta sconosciuta"}
	precision = clampf(precision, 0.0, 1.0)
	var difficulty := str(pending.difficulty)
	if precision < FORGE_FAIL_PRECISION:
		data.erase("forge_pending")
		add_event("ARMERIA", "Forgia fallita: " + str(recipe.name), "Precisione %d%%: il pezzo si è rotto, i materiali sono persi." % roundi(precision * 100.0), "danger")
		save_and_notify()
		return {"ok": true, "failed": true, "precision": roundi(precision * 100.0)}
	var grade_index := forge_grade_index(precision, difficulty)
	var grade: String = GRADES[grade_index]
	var quality := 0.95 + precision * 0.1
	var mult: float = float(FORGE_GRADE_MULT[grade_index]) * quality
	var item := {"id": "I-%05d" % int(pending.number), "name": "%s [%s]" % [recipe.name, grade], "slot": recipe.slot, "grade": grade, "precision": roundi(precision * 100.0), "difficulty": difficulty}
	match recipe.slot:
		"main": item.power = maxi(1, roundi(18.0 * mult))
		"armor": item.defense = maxi(1, roundi(14.0 * mult))
		"accessory": item.hp = maxi(1, roundi(30.0 * mult))
	data.inventory.append(item)
	data.erase("forge_pending")
	add_event("ARMERIA", "Forgiato: " + item.name, "Precisione %d%% · %s." % [int(item.precision), FORGE_DIFFICULTIES[difficulty].name], "good")
	save_and_notify()
	return {"ok": true, "item": item}

## Forgia in un colpo solo (test e strumenti): paga e chiude con la precisione data.
func forge_item(recipe_id: String, difficulty: String = "normal", precision: float = 0.75) -> Dictionary:
	var started := begin_forge(recipe_id, difficulty)
	if not started.ok: return started
	return finish_forge(precision)

func equip_item(hero_id: String, item_id: String) -> Dictionary:
	if item_id.is_empty(): return {"ok": false, "message": "Oggetto non valido"}
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state != "ALIVE": return {"ok": false, "message": "Eroe non disponibile"}
	var index := -1
	for i in data.inventory.size():
		if str(data.inventory[i].get("id", "")) == item_id: index = i
	if index < 0: return {"ok": false, "message": "Oggetto non trovato"}
	var item: Dictionary = data.inventory[index]
	var slot: String = item.slot
	var previous: Dictionary = hero.equipment.get(slot, {})
	var equipped := item.duplicate()
	if slot == "main": equipped.name = item.name
	hero.equipment[slot] = equipped
	data.inventory.remove_at(index)
	if not previous.is_empty() and previous.has("id"): data.inventory.append(previous)
	save_and_notify()
	return {"ok": true}

func refine_material(recipe_id: String) -> Dictionary:
	if not facility_built("workshop"): return {"ok": false, "message": "Costruisci prima il Laboratorio"}
	var recipe: Dictionary = WORKSHOP_RECIPES.get(recipe_id, {})
	if recipe.is_empty(): return {"ok": false, "message": "Ricetta sconosciuta"}
	if not pay(recipe.cost, recipe.name, "workshop"): return {"ok": false, "message": "Risorse insufficienti"}
	for key in recipe.output: grant(key, int(recipe.output[key]), recipe.name, "workshop")
	save_and_notify()
	return {"ok": true}

# --- Negozio -----------------------------------------------------------------
## Solo valute di gioco, prezzi e quantità sempre visibili. Niente che annulli il
## rischio: nessuna resurrezione o protezione dalla morte permanente.
## `limit` è il numero di acquisti per giorno (si azzera a mezzanotte UTC).
const SHOP_TABS := [["daily", "Offerte del giorno"], ["material", "Materiali"], ["premium", "Gemme"]]
const SHOP_OFFERS := {
	"daily_supplies": {"tab": "daily", "name": "Scorta da campo", "icon": "herbs", "color": "#4fe3a3", "price": {"gold": 1200}, "items": {"herbs": 4, "medicine": 2}, "limit": 1},
	"daily_forge": {"tab": "daily", "name": "Kit di forgia", "icon": "ore", "color": "#ffbb4d", "price": {"gold": 3200}, "items": {"ore": 5, "leather": 3}, "limit": 1},
	"daily_cores": {"tab": "daily", "name": "Nuclei instabili", "icon": "cores", "color": "#b57cff", "price": {"gold": 6000}, "items": {"cores": 2}, "limit": 1},
	"daily_gems": {"tab": "daily", "name": "Cambio in Gemme", "icon": "gems", "color": "#46dcf2", "price": {"gold": 20000}, "items": {"gems": 60}, "limit": 1},
	"mat_ore": {"tab": "material", "name": "Ferro (C)", "icon": "ore", "color": "#9aa6b6", "price": {"gold": 700}, "items": {"ore": 5}, "limit": 5},
	"mat_leather": {"tab": "material", "name": "Pelle (C)", "icon": "leather", "color": "#c08a5a", "price": {"gold": 700}, "items": {"leather": 5}, "limit": 5},
	"mat_wood": {"tab": "material", "name": "Assi di legno (C)", "icon": "wood", "color": "#6f8f3e", "price": {"gold": 500}, "items": {"wood": 5}, "limit": 5},
	"mat_herbs": {"tab": "material", "name": "Erbe", "icon": "herbs", "color": "#4fe3a3", "price": {"gold": 500}, "items": {"herbs": 5}, "limit": 5},
	"mat_medicine": {"tab": "material", "name": "Medicine", "icon": "medicine", "color": "#ff4f74", "price": {"gold": 1400}, "items": {"medicine": 3}, "limit": 3},
	"mat_cores": {"tab": "material", "name": "Nuclei", "icon": "cores", "color": "#b57cff", "price": {"gold": 3000}, "items": {"cores": 2}, "limit": 3},
	"gem_stone": {"tab": "premium", "name": "Pietra di promozione", "icon": "stones", "color": "#f052c8", "price": {"gems": 450}, "items": {"stones": 1}, "limit": 2},
	"gem_chest": {"tab": "premium", "name": "Forziere raro", "icon": "star", "color": "#ffbb4d", "price": {"gems": 300}, "items": {"ore": 6, "leather": 6, "wood": 6, "cores": 3}, "limit": 1},
	"gem_gold": {"tab": "premium", "name": "Sacca d'oro", "icon": "gold", "color": "#ffbb4d", "price": {"gems": 150}, "items": {"gold": 12000}, "limit": 3},
}

func shop_day() -> int:
	return int(now() / 86400.0)

func _shop_state() -> Dictionary:
	var shop: Dictionary = data.get_or_add("shop", {"day": -1, "bought": {}})
	if int(shop.get("day", -1)) != shop_day():
		shop.day = shop_day()
		shop.bought = {}
	return shop

func shop_remaining(offer_id: String) -> int:
	var offer: Dictionary = SHOP_OFFERS.get(offer_id, {})
	if offer.is_empty(): return 0
	return maxi(0, int(offer.limit) - int(_shop_state().bought.get(offer_id, 0)))

## Secondi al prossimo rinnovo delle offerte.
func shop_refresh_in() -> int:
	return int((shop_day() + 1) * 86400.0 - now())

func shop_buy(offer_id: String) -> Dictionary:
	var offer: Dictionary = SHOP_OFFERS.get(offer_id, {})
	if offer.is_empty(): return {"ok": false, "message": "Offerta sconosciuta"}
	if shop_remaining(offer_id) <= 0: return {"ok": false, "message": "Esaurito per oggi"}
	for key in offer.items:
		if MATERIALS.has(key) and resource_amount(key) >= material_cap(): return {"ok": false, "message": "Scorte piene di %s: potenzia il Magazzino" % MATERIALS[key].name}
	if not pay(offer.price, "Negozio · " + str(offer.name), "shop"): return {"ok": false, "message": "Non hai abbastanza " + cost_text(offer.price)}
	for key in offer.items: grant(key, int(offer.items[key]), "Negozio · " + str(offer.name), "shop")
	var shop := _shop_state()
	shop.bought[offer_id] = int(shop.bought.get(offer_id, 0)) + 1
	save_and_notify()
	return {"ok": true}

func brew_potion(recipe_id: String, hero_id: String) -> Dictionary:
	if not facility_built("alchemy"): return {"ok": false, "message": "Costruisci prima il Centro Alchemico"}
	var recipe: Dictionary = ALCHEMY_RECIPES.get(recipe_id, {})
	var hero := hero_by_id(hero_id)
	if recipe.is_empty() or hero.is_empty() or hero.state != "ALIVE": return {"ok": false, "message": "Selezione non valida"}
	if recipe_id == "heal" and hero.injuries.is_empty(): return {"ok": false, "message": "%s non è ferito" % hero.name}
	if not pay(recipe.cost, recipe.name, "alchemy"): return {"ok": false, "message": "Risorse insufficienti"}
	if recipe_id == "heal": hero.injuries.pop_front()
	else:
		hero.morale = mini(100, int(hero.morale) + 25)
		hero.fatigue = maxi(0, int(hero.fatigue) - 20)
	add_event("ALCHIMIA", recipe.name, "Somministrato a %s." % hero.name, "good")
	save_and_notify()
	return {"ok": true}

# =============================================================================
# Torre e missioni
# =============================================================================

func _materialize_stage(floor_index: int) -> Dictionary:
	var key := str(floor_index)
	if data.stages.has(key): return data.stages[key]
	var seed_text := str(data.world.seed) + ":floor:" + str(floor_index)
	var template: Dictionary
	if STAGES.has(floor_index): template = STAGES[floor_index].duplicate(true)
	else: template = _procedural_stage(floor_index, seed_text)
	template["floor"] = floor_index
	template["seed"] = "%08X" % abs(seed_text.hash())
	template["tier"] = tower_tier(floor_index) + 1
	if is_trial_floor(floor_index): _add_trial(template, floor_index, seed_text)
	template["threat_budget"] = tower_threat(floor_index, template)
	template["threat"] = template.threat_budget
	data.stages[key] = {"descriptor": template, "attempts": 0, "cleared": false, "best_time": 0.0}
	return data.stages[key]

## Scaglione (0 = piani 1–5, 1 = piani 6–10, ...).
static func tower_tier(floor_index: int) -> int:
	return (maxi(1, floor_index) - 1) / TOWER_TIER_FLOORS

## Il 5° piano di ogni scaglione è la Prova del Guardiano.
static func is_trial_floor(floor_index: int) -> bool:
	return floor_index > 0 and floor_index % TOWER_TIER_FLOORS == 0

## Solo per i banchi di prova del bilanciamento: moltiplica la forza dei nemici.
var debug_enemy_scale := 1.0

## Forza "di scaglione" di un piano, prima dello sconto delle prove.
static func floor_power(floor_index: int) -> float:
	var tier := tower_tier(floor_index)
	var step := (maxi(1, floor_index) - 1) % TOWER_TIER_FLOORS
	var last := TOWER_TIER_POWER.size() - 1
	var base: float = TOWER_TIER_POWER[mini(tier, last)] * pow(1.05, maxi(0, tier - last))
	return base * (1.0 + TOWER_STEP_GROWTH * step)

## Forza dei nemici di un piano: moltiplicatori per vita, attacco e difesa.
func enemy_scaling(floor_index: int) -> Dictionary:
	var tier := tower_tier(floor_index)
	var power := floor_power(floor_index) * debug_enemy_scale
	if is_trial_floor(floor_index): power *= float(TOWER_TRIAL_POWER[mini(tier, TOWER_TRIAL_POWER.size() - 1)])
	return scaling_for_power(power)

## Moltiplicatori dei nemici per una forza data. La vita cresce un po' meno dell'attacco
## (i piani a tempo restano fattibili, il pericolo per gli eroi no); la difesa ancora meno:
## con 100/(100+difesa) una difesa enorme renderebbe i nemici intoccabili.
static func scaling_for_power(power: float) -> Dictionary:
	return {"power": power, "hp": pow(power, 0.85), "attack": power, "defense": pow(power, 0.5)}

## Minaccia mostrata sulla mappa: segue la forza dei nemici. Una prova conta più dei piani
## normali dello scaglione (regole, campioni e guardiano valgono più dello sconto di forza).
func tower_threat(floor_index: int, descriptor: Dictionary = {}) -> int:
	var power := floor_power(floor_index)
	var trial: Dictionary = descriptor.get("trial", {})
	if not trial.is_empty(): power *= 1.2 + 0.06 * trial.get("rules", []).size()
	return roundi(120.0 * pow(power, 0.85))

## Prova del Guardiano: regole speciali, campioni di scorta e guardiano che si infuria.
func _add_trial(template: Dictionary, floor_index: int, seed_text: String) -> void:
	var rng := rng_for(seed_text + ":trial")
	var tier := tower_tier(floor_index)
	var count := 1 if tier < 2 else 2 if tier < 6 else 3
	var pool: Array = TOWER_TRIALS.keys()
	var rules: Array = []
	while rules.size() < count and not pool.is_empty():
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(pick)
		rules.append(pick)
	var elites := mini(1 + tier / 2, 5)
	var guardian: String = GUARDIAN_TITLES[tier % GUARDIAN_TITLES.size()]
	template["type"] = "Boss"
	template["trial"] = {"rules": rules, "elites": elites, "guardian": guardian}
	# i campioni arrivano a metà prova, insieme ai rinforzi
	var waves: Array = template.get("waves", []).duplicate(true)
	waves.append([30.0, "brute", elites, "elite"])
	template["waves"] = waves
	template["duration"] = maxf(float(template.get("duration", 90.0)), 100.0)
	var names: Array = rules.map(func(id): return "%s: %s" % [TOWER_TRIALS[id].name, TOWER_TRIALS[id].text])
	template["objective"] = "Abbatti %s. A metà vita si infuria." % guardian
	template["description"] = "Prova del Guardiano · fine dello scaglione %d. Regole: %s. Arrivano %d campioni. Superata la prova, i piani successivi sono più duri." % [tier + 1, "; ".join(names), elites]

func _procedural_stage(floor_index: int, seed_text: String) -> Dictionary:
	var rng := rng_for(seed_text + ":template")
	var is_boss := floor_index % 5 == 0
	var type: String = "Boss" if is_boss else STAGE_TYPE_CYCLE[(floor_index - 1) % STAGE_TYPE_CYCLE.size()]
	var biome: Dictionary = BIOMES[(floor_index / 5 + rng.randi_range(0, 1)) % BIOMES.size()]
	var extra := floor_index / 6
	var waves: Array = []
	var pool := ["raider", "hound", "archer", "brute"]
	if is_boss:
		waves = [[0.0, "boss", 1], [0.0, "raider", 2 + extra / 2], [20.0, "hound", 3 + extra / 2], [42.0, "archer", 2 + extra / 3]]
	else:
		var wave_count := 2 + mini(3, floor_index / 7)
		for w in wave_count:
			var kind: String = pool[rng.randi_range(0, mini(pool.size() - 1, 1 + floor_index / 4))]
			var amount := (1 if kind == "brute" else 2) + rng.randi_range(1, 2) + extra / 2
			waves.append([w * rng.randf_range(9.0, 13.0), kind, amount])
	var duration := 90.0 if is_boss else 45.0 if type == "Survival" else 70.0 if type == "Exploration" else 60.0
	return {
		"type": type, "name": "%s %s" % [_pick(rng, STAGE_NAME_A), _pick(rng, STAGE_NAME_B)], "biome": biome.name, "color": biome.color,
		"objective": STAGE_OBJECTIVES[type], "duration": duration, "waves": waves,
		"description": "Il piano %d della Torre si apre su %s." % [floor_index, str(biome.name).to_lower()],
	}

func get_stage(floor_index: int) -> Dictionary:
	return _materialize_stage(floor_index)

func floor_rewards(floor_index: int, attempt: int, first_clear: bool) -> Dictionary:
	var retry_multiplier: float = max(0.35, 1.0 - max(0, attempt - 1) * 0.12)
	# la Prova del Guardiano paga di più: è il muro di ogni scaglione
	var trial_bonus := 1.6 if is_trial_floor(floor_index) else 1.0
	# Santuario del Nexus (isola della Base Lv.10): +10% esperienza
	var xp_bonus := 1.1 if has_island("santuario") else 1.0
	var rewards := {"gold": roundi((7200 + floor_index * 2600) * retry_multiplier * trial_bonus), "xp": roundi((95 + floor_index * 34) * retry_multiplier * trial_bonus * xp_bonus)}
	# Gemme a ogni piano vinto: tante al primo completamento (doppie alla Prova
	# del Guardiano), poche quando lo si ripete, così farmare non sostituisce salire.
	var gem_trial := 2 if is_trial_floor(floor_index) else 1
	if first_clear:
		rewards.gems = (120 + floor_index * 10) * gem_trial
		if is_trial_floor(floor_index): rewards.stones = 1 + floor_index / 20
	else:
		rewards.gems = maxi(5, roundi((15 + floor_index * 1.5) * gem_trial * retry_multiplier))
	return rewards

## La squadra può partire? Vale per la Torre e per i dungeon.
func _party_can_deploy() -> Dictionary:
	var party := get_party()
	if party.filter(func(hero): return not hero.is_empty()).size() != PARTY_SIZE: return {"ok": false, "message": "Servono cinque eroi vivi in squadra"}
	for hero in party:
		if float(hero.fatigue) >= FATIGUE_NO_DEPLOY: return {"ok": false, "message": "%s è sfinito: deve riposare al Dormitorio" % hero.name}
	return {"ok": true, "party": party}

# --- Dungeon giornalieri -------------------------------------------------------

## Livello massimo dei dungeon: 1, poi uno in più ogni 5 piani della Torre superati.
func dungeon_max_level() -> int:
	return clampi(1 + cleared_floor_count() / TOWER_TIER_FLOORS, 1, DUNGEON_MAX_LEVEL)

func _dungeon_state() -> Dictionary:
	var state: Dictionary = data.get_or_add("dungeons", {"day": -1, "runs": {}})
	if int(state.get("day", -1)) != shop_day():
		state.day = shop_day()
		state.runs = {}
	return state

## Vittorie rimaste oggi in un dungeon. Solo lettura: non tocca il salvataggio.
func dungeon_runs_left(id: String) -> int:
	if not DUNGEONS.has(id): return 0
	var state: Dictionary = data.get("dungeons", {})
	var done := int(state.get("runs", {}).get(id, 0)) if int(state.get("day", -1)) == shop_day() else 0
	return maxi(0, DUNGEON_RUNS_PER_DAY - done)

## Bottino di una vittoria: soprattutto il materiale del dungeon, un po' di un altro, poco oro.
func dungeon_rewards(id: String, level: int) -> Dictionary:
	var info: Dictionary = DUNGEONS[id]
	var others := ["ore", "leather", "wood", "herbs"].filter(func(key): return key != str(info.material))
	var second: String = others[(level + DUNGEON_ORDER.find(id)) % others.size()]
	return {"gold": 600 + 300 * level, "xp": 20 + 8 * level, "materials": {str(info.material): 5 + 2 * level, second: 1 + level / 2}}

## Descrizione della missione di un dungeon al livello scelto (uguale per tutto il giorno).
func dungeon_stage(id: String, level: int) -> Dictionary:
	var info: Dictionary = DUNGEONS[id]
	level = clampi(level, 1, DUNGEON_MAX_LEVEL)
	var waves := []
	for index in info.waves.size():
		waves.append([index * 11.0, str(info.waves[index]), 2 + (1 if index == 0 else 0) + level / 7])
	var power := floor_power((level - 1) * TOWER_TIER_FLOORS + 1) * DUNGEON_POWER
	return {
		"type": "Subjugation", "name": str(info.name), "biome": str(info.biome), "color": str(info.color), "objective": "Elimina tutte le minacce",
		"duration": 90.0, "waves": waves, "description": str(info.description), "floor": 0, "dungeon": id, "level": level, "enemy_power": power,
		"seed": "%08X" % abs(("%s:dungeon:%s:%d:%d" % [str(data.world.seed), id, level, shop_day()]).hash()),
		"threat": roundi(120.0 * pow(power, 0.85)),
	}

func begin_dungeon(id: String, level: int) -> Dictionary:
	if not DUNGEONS.has(id): return {"ok": false, "message": "Dungeon sconosciuto"}
	if level < 1 or level > dungeon_max_level(): return {"ok": false, "message": "Livello non ancora aperto: sali nella Torre"}
	if dungeon_runs_left(id) <= 0: return {"ok": false, "message": "Già completato per oggi: torna domani"}
	var check := _party_can_deploy()
	if not check.ok: return check
	var party: Array = check.party
	for hero in party: data.assignments.erase(str(hero.id))
	var state := _dungeon_state()
	state["attempts"] = int(state.get("attempts", 0)) + 1
	data.active_mission = {"floor": 0, "dungeon": id, "level": level, "attempt": int(state.attempts), "started": now(), "deaths": []}
	save_game()
	return {"ok": true, "stage": dungeon_stage(id, level), "party": party, "attempt": int(state.attempts)}

func _finalize_dungeon(result: Dictionary, run: Dictionary) -> Dictionary:
	var id := str(run.dungeon)
	var level := int(run.level)
	var info: Dictionary = DUNGEONS[id]
	var rewards := {}
	var drops := {}
	var level_ups := []
	if bool(result.victory):
		var loot := dungeon_rewards(id, level)
		rewards = {"gold": int(loot.gold), "xp": int(loot.xp)}
		grant("gold", int(loot.gold), str(info.name), "dungeon")
		for key in loot.materials:
			drops[key] = int(loot.materials[key])
			grant(key, int(loot.materials[key]), str(info.name), "dungeon")
		var state := _dungeon_state()
		state.runs[id] = int(state.runs.get(id, 0)) + 1
		add_event("DUNGEON", "%s completato" % info.name, "Livello %d · %s." % [level, cost_text(drops)], "good")
	else:
		add_event("DUNGEON", "%s: squadra rientrata" % info.name, "Niente bottino. Il tentativo di oggi non è stato consumato.", "warn")
	for hero_result in result.get("hero_results", []):
		var hero := hero_by_id(str(hero_result.id))
		if hero.is_empty() or hero.state != "ALIVE": continue
		hero.missions += 1
		hero.kills += int(hero_result.get("kills", 0))
		# un dungeon stanca meno di un piano della Torre
		hero.fatigue = clampi(int(hero.fatigue) + roundi(float(hero_result.get("fatigue", 10)) * 0.6), 0, 100)
		hero.morale = clampi(int(hero.morale) + (2 if result.victory else -4), 0, 100)
		if result.victory:
			var before := int(hero.level)
			add_xp(hero, float(rewards.get("xp", 0)))
			if int(hero.level) > before: level_ups.append({"name": hero.name, "from": before, "to": int(hero.level)})
		var hp_ratio := float(hero_result.get("hp_ratio", 1.0))
		if hp_ratio < 0.3:
			var serious := hp_ratio < 0.12
			hero.injuries.append({"name": "Ferita grave" if serious else "Ferita da combattimento", "severity": "Grave" if serious else "Moderata", "minutes": 45.0 if serious else 20.0})
	var deaths: Array = run.deaths.duplicate()
	data.active_mission = {}
	save_and_notify()
	return {"ok": true, "gold": int(rewards.get("gold", 0)), "xp": int(rewards.get("xp", 0)), "rewards": rewards, "drops": drops, "level_ups": level_ups, "deaths": deaths, "first_clear": false, "title": "%s · Livello %d" % [info.name, level], "dungeon": id}

func begin_mission(floor_index: int) -> Dictionary:
	if floor_index < 1 or floor_index > int(data.world.max_floor): return {"ok": false, "message": "Piano non sbloccato"}
	var check := _party_can_deploy()
	if not check.ok: return check
	var party: Array = check.party
	for hero in party: data.assignments.erase(str(hero.id))
	var stage_state := _materialize_stage(floor_index)
	stage_state.attempts += 1
	data.active_mission = {"floor": floor_index, "attempt": stage_state.attempts, "started": now(), "deaths": []}
	save_game()
	return {"ok": true, "stage": stage_state.descriptor.duplicate(true), "party": party, "attempt": stage_state.attempts}

func record_death(hero_id: String, cause: String) -> void:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state == "DEAD": return
	var floor := int(data.active_mission.get("floor", data.world.current_floor))
	var place := "Piano %d" % floor
	if data.active_mission.has("dungeon"): place = str(DUNGEONS.get(str(data.active_mission.dungeon), {}).get("name", "Dungeon"))
	hero.state = "DEAD"
	hero.memories.push_front("Caduto (%s): %s" % [place, cause])
	data.assignments.erase(hero_id)
	var party_slot: int = data.party.find(hero_id)
	if party_slot >= 0: data.party[party_slot] = ""
	var tombstone := {"id": hero.id, "name": hero.name, "level": hero.level, "role": hero.role, "rarity": hero.current_rarity, "floor": floor, "cause": cause, "timestamp": now()}
	data.memorial.push_front(tombstone)
	if not data.active_mission.is_empty(): data.active_mission.deaths.append(tombstone)
	add_event("DEATH", hero.name + " è caduto", "%s · %s · morte permanente." % [place, cause], "danger")
	save_and_notify()

func finalize_mission(result: Dictionary) -> Dictionary:
	if data.active_mission.is_empty(): return {"ok": false, "message": "Nessuna missione attiva", "deaths": []}
	var run: Dictionary = data.active_mission
	if run.has("dungeon"): return _finalize_dungeon(result, run)
	var floor := int(run.floor)
	var stage_state: Dictionary = _materialize_stage(floor)
	var first_clear: bool = not bool(stage_state.cleared)
	var rewards := {}
	var level_ups := []
	var drops := {}
	if bool(result.victory):
		rewards = floor_rewards(floor, int(run.attempt), first_clear)
		for key in ["gold", "gems", "stones"]:
			if rewards.has(key): grant(key, int(rewards[key]), "Piano %d completato" % floor, "mission")
		var rng := rng_for(str(stage_state.descriptor.seed) + ":drops:" + str(run.attempt))
		for key in ["ore", "leather", "wood", "herbs"]:
			var amount := rng.randi_range(0, 2 + floor / 4)
			if amount > 0:
				drops[key] = amount
				grant(key, amount, "Bottino Piano %d" % floor, "mission")
		stage_state.cleared = true
		stage_state.best_time = float(result.duration) if float(stage_state.best_time) <= 0 else min(float(stage_state.best_time), float(result.duration))
		if not data.world.completed.has(floor): data.world.completed.append(int(floor))
		if floor < MAX_FLOOR and floor + 1 > int(data.world.max_floor):
			data.world.max_floor = floor + 1
			data.world.current_floor = floor + 1
			_materialize_stage(floor + 1)
		add_event("MISSION", "Piano %d completato" % floor, "%s Oro · %d XP per superstite." % [format_number(rewards.gold), rewards.xp], "good")
		if first_clear:
			for id in FACILITY_ORDER:
				if int(FACILITIES[id].get("unlock_floor", 0)) == floor and facility_available(id):
					add_event("BASE", "Nuovo cantiere: " + FACILITIES[id].name, "Il Piano %d è superato: nella base si apre il cantiere. %s" % [floor, FACILITIES[id].description], "good")
	else:
		add_event("MISSION", "Missione non completata", "Il Piano %d resta identico per il prossimo tentativo." % floor, "warn")
	for hero_result in result.get("hero_results", []):
		var hero := hero_by_id(str(hero_result.id))
		if hero.is_empty() or hero.state != "ALIVE": continue
		hero.missions += 1
		hero.kills += int(hero_result.get("kills", 0))
		hero.fatigue = clampi(int(hero.fatigue) + int(hero_result.get("fatigue", 10)), 0, 100)
		hero.morale = clampi(int(hero.morale) + (5 if result.victory else -8), 0, 100)
		if result.victory:
			hero.victories += 1
			var before := int(hero.level)
			add_xp(hero, float(rewards.get("xp", 0)))
			if int(hero.level) > before: level_ups.append({"name": hero.name, "from": before, "to": int(hero.level)})
		var hp_ratio := float(hero_result.get("hp_ratio", 1.0))
		if hp_ratio < 0.3:
			var serious := hp_ratio < 0.12
			hero.injuries.append({"name": "Ferita grave" if serious else "Ferita da combattimento", "severity": "Grave" if serious else "Moderata", "minutes": 45.0 if serious else 20.0})
	var deaths: Array = run.deaths.duplicate()
	data.active_mission = {}
	save_and_notify()
	return {"ok": true, "gold": int(rewards.get("gold", 0)), "xp": int(rewards.get("xp", 0)), "rewards": rewards, "drops": drops, "level_ups": level_ups, "deaths": deaths, "first_clear": first_clear and bool(result.victory)}

# =============================================================================
# Strumenti di sviluppo (attivabili dalle Impostazioni)
# =============================================================================

## Luce della base: "dusk" (crepuscolo), "day" (giorno) o "night" (notte).
func set_light(preset: String) -> void:
	if not preset in ["dusk", "day", "night"]: return
	data.settings.light = preset
	save_and_notify()

func light_preset() -> String:
	return str(data.get("settings", {}).get("light", "dusk"))

func set_dev_mode(enabled: bool) -> void:
	data.dev.enabled = enabled
	if not enabled: data.dev.all_content = false
	data.dev.unlimited_resources = enabled
	data.dev.reveal_hidden = enabled
	add_event("DEV", "Modalità sviluppo " + ("attiva" if enabled else "disattivata"), "Risorse infinite e valori nascosti " + ("visibili." if enabled else "nascosti."), "warn")
	save_and_notify()

func dev_unlock_all() -> void:
	data.dev.all_content = true
	data.world.max_floor = MAX_FLOOR
	for floor_index in range(1, MAX_FLOOR + 1): _materialize_stage(floor_index)
	add_event("DEV", "Contenuti sbloccati", "Tutti i %d piani della Torre si possono scegliere; requisiti di progressione ignorati." % MAX_FLOOR, "warn")
	save_and_notify()

## Segna come completati tutti i piani: sblocca evocazioni, espansioni e promozioni legate ai piani.
func dev_clear_all_floors() -> void:
	data.dev.all_content = true
	debug_clear_floors(MAX_FLOOR)
	data.world.max_floor = MAX_FLOOR
	add_event("DEV", "Torre completata", "Piani 1–%d segnati come completati." % MAX_FLOOR, "warn")
	save_and_notify()

## Base al livello massimo con tutte le strutture costruite e al massimo livello.
func dev_max_base() -> void:
	data.world.base_level = BASE_LEVELS.size()
	for id in FACILITY_ORDER:
		data.facilities.get_or_add(id, {"level": 0})
		data.facilities[id].level = mini(FACILITY_MAX_LEVEL, facility_max_level())
	add_event("DEV", "Base al massimo", "Base Lv.%d, tutte le strutture costruite e potenziate." % base_level(), "warn")
	save_and_notify()

## Porta tutti gli eroi vivi al livello massimo della loro rarità.
func dev_max_heroes() -> void:
	for hero in data.heroes:
		if hero.state != "ALIVE": continue
		var guard := 0
		while int(hero.level) < level_cap(hero) and guard < 200:
			_apply_level_up(hero)
			guard += 1
		hero.xp = 0
	add_event("DEV", "Eroi al livello massimo", "Ogni eroe vivo ha raggiunto il cap della sua rarità.", "warn")
	save_and_notify()

## Segna come completati i piani fino a `up_to` (strumenti di sviluppo e test).
func debug_clear_floors(up_to: int) -> void:
	for f in range(1, mini(up_to, MAX_FLOOR) + 1):
		var record := _materialize_stage(f)
		record.cleared = true
		if not data.world.completed.has(f): data.world.completed.append(f)
	data.world.max_floor = maxi(int(data.world.max_floor), mini(MAX_FLOOR, up_to + 1))
	data.world.current_floor = int(data.world.max_floor)
	_materialize_stage(int(data.world.max_floor))

func dev_restore_roster() -> void:
	for hero in data.heroes:
		hero.state = "ALIVE"
		hero.fatigue = 0
		hero.morale = 100
		hero.injuries = []
	data.memorial = []
	for i in PARTY_SIZE:
		if i < data.heroes.size(): data.party[i] = data.heroes[i].id
	add_event("DEV", "Roster ripristinato", "Eroi vivi, stanchezza 0, morale 100 e squadra ricostruita.", "warn")
	save_and_notify()

func dev_spawn_hero(rarity: int = 5) -> Dictionary:
	data.summon_counter += 1
	var hero := generate_hero(str(data.world.seed) + ":dev:" + str(Time.get_ticks_msec()) + ":" + str(data.summon_counter), clampi(rarity, 1, 7))
	data.heroes.append(hero)
	add_event("DEV", "Eroe di prova generato", hero.name + " · " + stars(hero.native_rarity), "warn")
	save_and_notify()
	return hero

func dev_set_pity(value: int = 99) -> void:
	data.pity.high = clampi(value, 0, 99)
	save_and_notify()

func dev_validate() -> Array:
	var issues := []
	var ids := {}
	for hero in data.heroes:
		if ids.has(hero.id): issues.append("Hero ID duplicato: " + hero.id)
		ids[hero.id] = true
		if hero.state == "DEAD" and data.party.has(hero.id): issues.append("Eroe morto nel party: " + hero.name)
	for hero_id in data.party:
		if not hero_id.is_empty() and not ids.has(hero_id): issues.append("Party reference mancante: " + hero_id)
	for hero_id in data.assignments:
		if not ids.has(hero_id): issues.append("Assegnazione orfana: " + hero_id)
	if data.party.size() != PARTY_SIZE: issues.append("Party size non valida: %d" % data.party.size())
	return issues

# =============================================================================
# Registri
# =============================================================================

func add_event(category: String, title: String, text: String, tone: String = "info") -> void:
	data.events.push_front({"category": category, "title": title, "text": text, "tone": tone, "timestamp": now(), "read": false})
	if data.events.size() > 120: data.events.resize(120)

func add_ledger(currency: String, delta: int, reason: String, source: String) -> void:
	data.ledger.push_front({"currency": currency, "delta": delta, "reason": reason, "source": source, "timestamp": now()})
	if data.ledger.size() > 180: data.ledger.resize(180)

func unread_events() -> int:
	var count := 0
	for event in data.events:
		if not bool(event.get("read", false)): count += 1
	return count

func mark_events_read() -> void:
	for event in data.events: event.read = true
	save_game()
