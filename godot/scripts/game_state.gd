extends Node
class_name RiftwardState

## Stato persistente del gioco (autoload "GameState").
## Contiene world, roster, base, torre, economia e tutte le regole di progressione.
## La UI e la base 3D leggono da qui e chiamano solo le funzioni pubbliche.

signal state_changed
signal toast_requested(title: String, message: String, tone: String)
signal hero_leveled(hero_id: String, level: int)

const SAVE_PATH := "user://riftward_save.json"
const SAVE_VERSION := 3
const PARTY_SIZE := 5
const MAX_FLOOR := 100
const OFFLINE_CAP_HOURS := 8.0
const TICK_SECONDS := 1.0
const AUTOSAVE_SECONDS := 20.0

# --- Rarità ------------------------------------------------------------------
const RARITY_CAPS := {1: 10, 2: 20, 3: 30, 4: 50, 5: 70, 6: 99, 7: 120}
const RARITY_NAMES := {1: "Comune", 2: "Non comune", 3: "Raro", 4: "Epico", 5: "Leggendario", 6: "Mitico", 7: "Trascendente"}
## Pietre di promozione richieste per salire dalla rarità indicata alla successiva.
const PROMOTION_STONES := {1: 1, 2: 2, 3: 3, 4: 5, 5: 12, 6: 30}
## Piano minimo già superato per promuovere dalla rarità indicata (6★ e 7★ sono endgame).
const PROMOTION_FLOOR_GATE := {5: 30, 6: 60}

# --- Evocazione --------------------------------------------------------------
const SUMMON_POOLS := {
	"normal": {"name": "Richiamo del Nexus", "currency": "gold", "cost": 10000, "rates": [[1, 78.0], [2, 19.0], [3, 3.0]]},
	"high": {"name": "Giuramento Astrale", "currency": "gems", "cost": 500, "rates": [[3, 93.5], [4, 5.5], [5, 1.0]]},
	"transcendent": {"name": "Eco Trascendente", "currency": "gems", "cost": 3000, "rates": [[5, 98.0], [6, 1.8], [7, 0.2]], "unlock_floor": 20},
}
const HIGH_SOFT_PITY := 70
const HIGH_HARD_PITY := 100

# --- Ruoli -------------------------------------------------------------------
const ROLES := {
	"Guardian": {"line": "Front", "weights": [0.31, 0.04, 0.48, 0.17], "skill": "Aegis Brace", "icon": "G", "label": "Guardiano"},
	"Vanguard": {"line": "Front", "weights": [0.47, 0.04, 0.28, 0.21], "skill": "Driving Cleave", "icon": "V", "label": "Avanguardia"},
	"Lancer": {"line": "Mid", "weights": [0.39, 0.04, 0.27, 0.30], "skill": "Pinning Thrust", "icon": "L", "label": "Lanciere"},
	"Ranger": {"line": "Rear", "weights": [0.20, 0.08, 0.17, 0.55], "skill": "Marked Shot", "icon": "R", "label": "Ranger"},
	"Mage": {"line": "Rear", "weights": [0.05, 0.58, 0.18, 0.19], "skill": "Ember Lattice", "icon": "M", "label": "Mago"},
	"Support": {"line": "Mid", "weights": [0.08, 0.46, 0.30, 0.16], "skill": "Mend", "icon": "S", "label": "Supporto"},
}
## Slot di formazione: 2 Front, 2 Mid, 1 Rear.
const FORMATION_LINES := ["Front", "Front", "Mid", "Mid", "Rear"]

const FIRST_NAMES := ["Aella", "Bren", "Cael", "Doria", "Edrin", "Fara", "Galen", "Hesta", "Iven", "Kaia", "Loran", "Mira", "Neris", "Orin", "Pyria", "Quill", "Rhea", "Soren", "Tavia", "Ulric", "Veya", "Wren", "Yara", "Zephan"]
const LAST_NAMES := ["Ashfall", "Blackmere", "Cinder", "Dawnward", "Emberlain", "Frost", "Greywake", "Hollow", "Ironwood", "Jade", "Kestrel", "Lightfoot", "Mourn", "Nightglass", "Oakshield", "Pyre", "Rook", "Stoneveil", "Thorn", "Vale", "Yarrow", "Zephyr"]
const ORIGINS := ["Marche di Veyra", "Città sommersa di Oros", "Cintura mineraria di Khel", "Nomadi di Sable", "Isole di vetro", "Bosco di Talren", "Fortezza di Ardent", "Archivio di Myr"]
const PROFESSIONS := ["Fabbro", "Conciatore", "Cartografo", "Erborista", "Carpentiere", "Archivista", "Cuoco", "Minatore"]
const TRAITS := ["Nervi saldi", "Istinto protettivo", "Passo leggero", "Tenace", "Occhio clinico", "Testardo", "Frugale", "Socievole", "Solitario", "Mano ferma", "Memoria lunga"]

# --- Base e strutture ---------------------------------------------------------
## Livelli della base. Ogni livello alza il livello massimo delle strutture e sblocca nuovi cantieri.
const BASE_LEVELS := [
	{"level": 1, "floor": 0, "gold": 0},
	{"level": 2, "floor": 3, "gold": 40000},
	{"level": 3, "floor": 6, "gold": 120000},
	{"level": 4, "floor": 10, "gold": 300000},
	{"level": 5, "floor": 15, "gold": 700000},
]

## Catalogo strutture. unlock = livello base che rende disponibile il cantiere.
const FACILITIES := {
	"training": {"name": "Centro di Addestramento", "short": "Addestramento", "unlock": 1, "build_cost": 0, "upgrade_cost": 9000, "description": "Gli eroi si allenano sul campo rialzato e guadagnano esperienza nel tempo."},
	"dormitory": {"name": "Dormitorio", "short": "Dormitorio", "unlock": 1, "build_cost": 0, "upgrade_cost": 7000, "description": "Gli eroi riposano, recuperano la stanchezza, il morale e guariscono dalle ferite."},
	"merging": {"name": "Centro di Fusione", "short": "Fusione", "unlock": 1, "build_cost": 0, "upgrade_cost": 12000, "description": "La cupola azzurra dove gli eroi si fondono e vengono promossi di rarità."},
	"gate": {"name": "Portale delle Missioni", "short": "Portale", "unlock": 1, "build_cost": 0, "upgrade_cost": 15000, "description": "Il varco sospeso verso la Torre. Da qui parte la squadra."},
	"armory": {"name": "Armeria", "short": "Armeria", "unlock": 2, "build_cost": 25000, "upgrade_cost": 14000, "description": "Forgia e assegna armi e armature agli eroi."},
	"warehouse": {"name": "Magazzino", "short": "Magazzino", "unlock": 3, "build_cost": 40000, "upgrade_cost": 16000, "description": "Deposito di materiali ed equipaggiamento. Aumenta le scorte massime."},
	"workshop": {"name": "Laboratorio", "short": "Laboratorio", "unlock": 3, "build_cost": 45000, "upgrade_cost": 18000, "description": "Raffina i materiali grezzi in componenti per la forgia e l'alchimia."},
	"alchemy": {"name": "Centro Alchemico", "short": "Alchimia", "unlock": 4, "build_cost": 80000, "upgrade_cost": 26000, "description": "Distilla tonici che curano ferite e risollevano il morale."},
}
const FACILITY_ORDER := ["training", "dormitory", "merging", "gate", "armory", "warehouse", "workshop", "alchemy"]

const MATERIALS := {
	"ore": {"name": "Minerale", "icon": "⬢"}, "leather": {"name": "Pelle", "icon": "◒"}, "wood": {"name": "Legno", "icon": "♣"},
	"herbs": {"name": "Erbe", "icon": "✿"}, "cores": {"name": "Nuclei", "icon": "✹"}, "medicine": {"name": "Medicine", "icon": "✚"},
}

# --- Torre -------------------------------------------------------------------
const STAGES := {
	1: {"type": "Subjugation", "name": "La strada spezzata", "biome": "Bosco cinereo", "objective": "Elimina tutte le minacce", "duration": 60.0, "color": "#3c7968", "description": "Predoni del Rift hanno chiuso l'unica via verso la torre.", "waves": [[0.0, "raider", 4], [10.0, "hound", 2]]},
	2: {"type": "Survival", "name": "Campana nella nebbia", "biome": "Borgo evacuato", "objective": "Sopravvivi per 45 secondi", "duration": 45.0, "color": "#346b86", "description": "La campana attira sciami dalle case vuote. Munizioni e disciplina decidono la sopravvivenza.", "waves": [[0.0, "raider", 3], [9.0, "archer", 2], [20.0, "hound", 4], [31.0, "brute", 2]]},
	3: {"type": "Exploration", "name": "Osservatorio sommerso", "biome": "Rovine allagate", "objective": "Metti in sicurezza 3 punti d'interesse", "duration": 70.0, "color": "#365c8c", "description": "Le rovine nascondono informazioni persistenti sul climax dello Stream.", "waves": [[0.0, "hound", 3], [15.0, "raider", 3], [30.0, "archer", 2]]},
	4: {"type": "Defense", "name": "L'ultima lanterna", "biome": "Santuario in rovina", "objective": "Proteggi il faro del Rift", "duration": 50.0, "color": "#94713c", "description": "Il faro deve restare integro mentre l'Archivio decodifica le coordinate.", "waves": [[0.0, "raider", 4], [12.0, "archer", 2], [25.0, "brute", 2], [37.0, "hound", 4]]},
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
		if changed: state_changed.emit()
	if _save_accumulator >= AUTOSAVE_SECONDS:
		_save_accumulator = 0.0
		save_game()

# =============================================================================
# Salvataggio
# =============================================================================

func load_or_create() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary and parsed.has("world"):
			data = parsed
			_migrate()
			_apply_offline_progress()
			return
	new_world()

func new_world(seed_text: String = "") -> void:
	var world_seed := seed_text
	if world_seed.is_empty(): world_seed = "%x%x" % [Time.get_unix_time_from_system(), randi()]
	data = {
		"version": SAVE_VERSION,
		"world": {
			"id": "WORLD-%08X" % abs(world_seed.hash()), "seed": world_seed, "master_name": "Aster",
			"gold": 60000, "gems": 1500, "stones": 1, "current_floor": 1, "max_floor": 1, "completed": [],
			"base_level": 1,
			"materials": {"ore": 8, "leather": 6, "wood": 10, "herbs": 4, "cores": 0, "medicine": 2},
			"last_saved": Time.get_unix_time_from_system(),
		},
		"heroes": [], "party": [], "relationships": {}, "stages": {}, "events": [], "ledger": [], "memorial": [], "inventory": [],
		"facilities": _default_facilities(),
		"assignments": {},
		"pity": {"high": 0, "transcendent": 0}, "summon_counter": 0, "item_counter": 0,
		"active_mission": {}, "tutorial_seen": false,
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
	for id in FACILITY_ORDER:
		var built: bool = int(FACILITIES[id].unlock) <= 1
		output[id] = {"level": 1 if built else 0}
	return output

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
	if from_version < 3:
		# La v2 forzava la modalità sviluppo: la v3 torna a un'economia reale.
		data.dev.enabled = false
		data.dev.unlimited_resources = false
		data.dev.reveal_hidden = false
		data.facilities = _migrate_facilities(data.get("facilities", {}))
		for key in ["shop_claims", "shop_history", "cosmetics"]: data.erase(key)
	else:
		var facilities: Dictionary = data.get_or_add("facilities", {})
		for id in FACILITY_ORDER: facilities.get_or_add(id, {"level": 1 if int(FACILITIES[id].unlock) <= 1 else 0})
	for hero in data.heroes: _normalize_hero(hero)
	for stage_key in data.get("stages", {}):
		var stage_record: Dictionary = data.stages[stage_key]
		if not stage_record.has("descriptor"): continue
		var descriptor: Dictionary = stage_record.descriptor
		var normalized_threat: int = int(descriptor.get("threat_budget", descriptor.get("threat", 100)))
		descriptor["threat_budget"] = normalized_threat
		descriptor["threat"] = normalized_threat
		stage_record.get_or_add("attempts", 0)
		stage_record.get_or_add("cleared", false)
		stage_record.get_or_add("best_time", 0.0)
	while data.party.size() < PARTY_SIZE: data.party.append("")
	if not data.active_mission.is_empty():
		data.active_mission = {}
		add_event("MISSION", "Collegamento interrotto", "Missione incompleta chiusa; le morti già registrate restano definitive.", "warn")
	data.version = SAVE_VERSION

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

func _apply_offline_progress() -> void:
	var now := Time.get_unix_time_from_system()
	var elapsed: float = clampf(now - float(data.world.get("last_saved", now)), 0.0, OFFLINE_CAP_HOURS * 3600.0)
	if elapsed >= 30.0:
		var before_levels := {}
		for hero in data.heroes: before_levels[hero.id] = int(hero.level)
		advance_time(elapsed)
		var gained := 0
		for hero in data.heroes: gained += int(hero.level) - int(before_levels.get(hero.id, hero.level))
		add_event("REPORT", "Mentre eri via", "Sono passati %d minuti alla base. Livelli guadagnati in addestramento: %d." % [roundi(elapsed / 60.0), gained], "info")
	data.world.last_saved = now
	save_game()

func save_game() -> void:
	if data.is_empty() or is_test_mode: return
	data.world.last_saved = Time.get_unix_time_from_system()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(data, "  "))

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

func stars(rarity: int) -> String:
	return "★".repeat(rarity)

func role_label(role: String) -> String:
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
	var role: String = forced_role if not forced_role.is_empty() else _pick(rng, ROLES.keys())
	var name := "%s %s" % [_pick(rng, FIRST_NAMES), _pick(rng, LAST_NAMES)]
	var weights: Array = ROLES[role].weights
	var budget := 39 + rarity * 3 + rng.randi_range(0, 7)
	var stats := {"str": 7 + roundi(budget * weights[0]) + rng.randi_range(0, 2), "int": 7 + roundi(budget * weights[1]) + rng.randi_range(0, 2), "sta": 7 + roundi(budget * weights[2]) + rng.randi_range(0, 2), "agi": 7 + roundi(budget * weights[3]) + rng.randi_range(0, 2)}
	var potential_min := 20 + (rarity - 1) * 10
	var potential := clampi(rng.randi_range(potential_min, 88 + rarity * 2), 20, 100)
	var id := "H-%08X" % abs((seed_text + name).hash())
	var hero := {
		"id": id, "seed": "%08X" % abs(seed_text.hash()), "name": name, "native_rarity": rarity, "current_rarity": rarity, "level": 1, "xp": 0,
		"role": role, "class_name": role, "origin": _pick(rng, ORIGINS), "profession": _pick(rng, PROFESSIONS), "stats": stats, "potential": potential, "growth": 3.35 + rarity * 0.62 + potential * 0.004,
		"personality": {"courage": rng.randi_range(25, 95), "discipline": rng.randi_range(20, 96), "aggression": rng.randi_range(15, 95), "altruism": rng.randi_range(15, 95), "composure": rng.randi_range(20, 95), "loyalty": rng.randi_range(25, 90)},
		"traits": [_pick(rng, TRAITS), _pick(rng, TRAITS)], "skills": [{"name": ROLES[role].skill, "level": 1, "xp": 0}, {"name": "Field Discipline", "level": 1, "xp": 0}],
		"morale": rng.randi_range(60, 84), "fatigue": rng.randi_range(0, 8), "injuries": [], "missions": 0, "victories": 0, "kills": 0, "state": "ALIVE", "hue": rng.randi_range(0, 359),
		"equipment": _starter_equipment(role), "memories": ["Ha attraversato il Rift e ha visto il Nexus per la prima volta."],
	}
	hero.assessment = _assessment(hero)
	return hero

## Aspetto deterministico derivato dall'id: non altera la sequenza RNG storica degli eroi.
func hero_appearance(hero: Dictionary) -> Dictionary:
	var h: int = abs(str(hero.get("id", "x")).hash())
	var skins := [Color("#ffe3cf"), Color("#f6d2b4"), Color("#e8b98f"), Color("#c98e63"), Color("#9b6644")]
	var eyes := [Color("#3b6fd8"), Color("#2e9e6a"), Color("#8a4fd6"), Color("#c0502e"), Color("#d9a72c"), Color("#2f8fb5")]
	return {
		"hair": Color.from_hsv(float(hero.get("hue", 40)) / 360.0, 0.62, 0.86),
		"skin": skins[h % skins.size()],
		"eyes": eyes[(h / 7) % eyes.size()],
		"hair_style": (h / 53) % 4,
		"outfit": Color.from_hsv(fmod(float(hero.get("hue", 40)) / 360.0 + 0.45, 1.0), 0.45, 0.62),
	}

func _starter_equipment(role: String) -> Dictionary:
	var names := {"Guardian": "Spada da presidio", "Vanguard": "Lama mercenaria", "Lancer": "Lancia d'acciaio", "Ranger": "Arco laminato", "Mage": "Verga di quarzo", "Support": "Mazza cerimoniale"}
	var armor := 18 if role == "Guardian" else 12 if role in ["Vanguard", "Lancer"] else 7
	return {"main": {"name": names.get(role, "Arma"), "grade": "D", "power": 15}, "sub": {"name": "Scudo" if role == "Guardian" else "Focus" if role in ["Mage", "Support"] else "Faretra" if role == "Ranger" else "Off-hand", "grade": "D", "block": 18 if role == "Guardian" else 0, "ammo": 24 if role == "Ranger" else 0}, "armor": {"name": "Equipaggiamento da campo", "grade": "D", "defense": armor}, "accessory": {}}

func _assessment(hero: Dictionary) -> Array:
	var output := []
	if hero.potential >= 90: output.append("Ceiling impossibile da stimare")
	elif hero.potential >= 75: output.append("Margine di crescita eccezionale")
	elif hero.potential >= 58: output.append("Apprendimento sopra la media")
	else: output.append("Crescita metodica, non esplosiva")
	var best_stat := "str"
	for key in hero.stats:
		if hero.stats[key] > hero.stats[best_stat]: best_stat = key
	output.append("Affinità evidente: " + {"str": "Forza", "int": "Intelletto", "sta": "Stamina", "agi": "Agilità"}[best_stat])
	return output

func derived_stats(hero: Dictionary) -> Dictionary:
	var equipment: Dictionary = hero.equipment
	var accessory: Dictionary = equipment.get("accessory", {})
	var max_hp := roundi(100 + hero.stats.sta * 12 + hero.level * 6 + int(accessory.get("hp", 0)))
	return {
		"max_hp": max_hp,
		"attack": float(equipment.main.get("power", 0)) + hero.stats.str * 1.75,
		"magic": hero.stats.int * 1.9 + (12 if hero.role in ["Mage", "Support"] else 0) + float(equipment.main.get("power", 0)) * (0.6 if hero.role in ["Mage", "Support"] else 0.0),
		"defense": float(equipment.armor.get("defense", 0)) + hero.stats.sta * 0.55,
		"accuracy": clampf(70 + hero.stats.agi * 0.45, 35, 98),
		"evasion": clampf(hero.stats.agi * 0.22, 0, 35),
		"crit": clampf(3 + hero.stats.agi * 0.08, 3, 30),
		"block": equipment.sub.get("block", 0),
		"ammo": equipment.sub.get("ammo", 0),
	}

func hero_power(hero: Dictionary) -> int:
	if hero.is_empty() or hero.state != "ALIVE": return 0
	var d := derived_stats(hero)
	var attack: float = max(d.attack * 0.75, d.magic) if hero.role in ["Mage", "Support"] else d.attack
	var injury_factor := 0.85 if not hero.get("injuries", []).is_empty() else 1.0
	return roundi((d.max_hp * 0.22 + attack * 3 + d.defense * 2) * (0.8 + hero.morale / 500.0) * (1.0 - max(0, hero.fatigue - 50) * 0.0035) * injury_factor)

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
		if hero.fatigue >= 70: warnings.append(hero.name + " è molto stanco")
		if not hero.injuries.is_empty(): warnings.append(hero.name + " è ferito")
		if data.assignments.has(hero.id): warnings.append(hero.name + " lascerà la sua attività")
		var line: String = ROLES[hero.role].line
		if line != FORMATION_LINES[i]: warnings.append("%s (%s) è fuori ruolo in %s" % [hero.name, line, FORMATION_LINES[i]])
	if alive < PARTY_SIZE: warnings.append("Squadra incompleta: %d/%d" % [alive, PARTY_SIZE])
	var grade := "S" if score >= 2200 else "A" if score >= 1700 else "B" if score >= 1200 else "C" if score >= 800 else "D"
	return {"score": score, "grade": grade, "warnings": warnings, "ready": alive == PARTY_SIZE}

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
	return not facility_built(id) and base_level() >= int(FACILITIES[id].unlock)

func facility_max_level() -> int:
	return base_level()

func facility_upgrade_cost(id: String) -> Dictionary:
	var level := facility_level(id)
	return {"gold": roundi(float(FACILITIES[id].upgrade_cost) * pow(1.85, level - 1))}

func can_upgrade_facility(id: String) -> Dictionary:
	if not facility_built(id): return {"ok": false, "message": "Struttura non costruita"}
	if facility_level(id) >= 5: return {"ok": false, "message": "Livello massimo raggiunto"}
	if facility_level(id) >= facility_max_level(): return {"ok": false, "message": "Serve la Base Lv.%d" % (facility_level(id) + 1)}
	if not can_afford(facility_upgrade_cost(id)): return {"ok": false, "message": "Oro insufficiente"}
	return {"ok": true, "message": ""}

func upgrade_facility(id: String) -> Dictionary:
	var check := can_upgrade_facility(id)
	if not check.ok: return check
	pay(facility_upgrade_cost(id), "Potenziamento " + FACILITIES[id].name, "facility")
	data.facilities[id].level = facility_level(id) + 1
	add_event("BASE", "%s Lv.%d" % [FACILITIES[id].name, facility_level(id)], "La struttura cresce di un piano.", "good")
	save_and_notify()
	return {"ok": true, "level": facility_level(id)}

func build_facility(id: String) -> Dictionary:
	if not FACILITIES.has(id): return {"ok": false, "message": "Struttura sconosciuta"}
	if facility_built(id): return {"ok": false, "message": "Già costruita"}
	if not facility_available(id): return {"ok": false, "message": "Serve la Base Lv.%d" % int(FACILITIES[id].unlock)}
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
	if cleared_floor_count() < int(next.floor) and not bool(data.dev.get("all_content", false)): return {"ok": false, "message": "Completa il Piano %d" % int(next.floor)}
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
	add_event("BASE", "Base Lv.%d" % int(next.level), ("Nuovi cantieri: " + ", ".join(unlocked)) if not unlocked.is_empty() else "Le strutture possono crescere di un piano.", "good")
	save_and_notify()
	return {"ok": true, "level": int(next.level), "unlocked": unlocked}

func cleared_floor_count() -> int:
	return data.world.completed.size()

func material_cap() -> int:
	return 60 + 80 * facility_level("warehouse")

# --- Assegnazioni (addestramento e riposo) -----------------------------------

func training_slots() -> int:
	return 2 + facility_level("training")

func dormitory_slots() -> int:
	return 5 + 2 * (facility_level("dormitory") - 1)

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
	return cleared_floor_count() >= int(info.get("unlock_floor", 0)) or bool(data.dev.get("all_content", false))

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

func validate_merge_heroes(hero_ids: Array) -> Dictionary:
	if hero_ids.size() != 3:
		return {"ok": false, "message": "Seleziona esattamente tre eroi.", "heroes": []}
	var unique_ids: Dictionary = {}
	var heroes: Array = []
	for value in hero_ids:
		var hero_id := str(value)
		if unique_ids.has(hero_id):
			return {"ok": false, "message": "Lo stesso eroe non può occupare più slot.", "heroes": []}
		unique_ids[hero_id] = true
		var hero := hero_by_id(hero_id)
		if hero.is_empty() or str(hero.state) != "ALIVE":
			return {"ok": false, "message": "Uno degli eroi non è disponibile.", "heroes": []}
		if data.party.has(hero_id):
			return {"ok": false, "message": "%s è nella squadra." % hero.name, "heroes": []}
		heroes.append(hero)
	var rarity := int(heroes[0].current_rarity)
	if rarity >= 5:
		return {"ok": false, "message": "Oltre le 5★ si sale solo con la promozione.", "heroes": []}
	for hero in heroes:
		if int(hero.current_rarity) != rarity:
			return {"ok": false, "message": "I tre eroi devono avere la stessa rarità.", "heroes": []}
	return {"ok": true, "message": "Fusione pronta.", "heroes": heroes}

func merge_heroes(hero_ids: Array) -> Dictionary:
	var validation := validate_merge_heroes(hero_ids)
	if not bool(validation.ok): return validation
	var heroes: Array = validation.heroes
	var core: Dictionary = heroes[0]
	var old_rarity := int(core.current_rarity)
	var retention := 0.04 + 0.01 * (facility_level("merging") - 1)
	for stat_key in core.stats:
		var absorbed := int(heroes[1].stats.get(stat_key, 0)) + int(heroes[2].stats.get(stat_key, 0))
		core.stats[stat_key] += maxi(1, roundi(float(absorbed) * retention))
	core.current_rarity = old_rarity + 1
	core.potential = mini(100, maxi(int(core.potential), maxi(int(heroes[1].potential), int(heroes[2].potential))) + 2)
	core.morale = mini(100, int(core.morale) + 5)
	var donor_ids := [str(heroes[1].id), str(heroes[2].id)]
	for donor_id in donor_ids: data.assignments.erase(donor_id)
	for index in range(data.heroes.size() - 1, -1, -1):
		if str(data.heroes[index].id) in donor_ids:
			data.heroes.remove_at(index)
	core.memories.push_front("Ha assorbito l'eco di %s e %s." % [heroes[1].name, heroes[2].name])
	add_event("MERGE", core.name + " ha completato la fusione", "%s + %s assorbiti · rarità %s." % [heroes[1].name, heroes[2].name, stars(core.current_rarity)], "good")
	save_and_notify()
	return {"ok": true, "hero": core, "consumed": donor_ids}

func promotion_requirements(hero: Dictionary) -> Dictionary:
	var rarity := int(hero.current_rarity)
	if rarity >= 7: return {"ok": false, "message": "Rarità massima", "stones": 0}
	var stones := int(PROMOTION_STONES[rarity])
	if int(hero.level) < level_cap(hero): return {"ok": false, "message": "Raggiungi prima il Lv.%d" % level_cap(hero), "stones": stones}
	var gate := int(PROMOTION_FLOOR_GATE.get(rarity, 0))
	if gate > 0 and cleared_floor_count() < gate and not bool(data.dev.get("all_content", false)): return {"ok": false, "message": "Completa il Piano %d" % gate, "stones": stones}
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
const GRADES := ["D", "C", "B", "A", "S"]
const WORKSHOP_RECIPES := {
	"cores": {"name": "Nucleo raffinato", "output": {"cores": 1}, "cost": {"gold": 1500, "ore": 3, "wood": 2}},
	"medicine": {"name": "Kit medico", "output": {"medicine": 1}, "cost": {"gold": 900, "herbs": 2, "leather": 1}},
}
const ALCHEMY_RECIPES := {
	"heal": {"name": "Tonico di sutura", "description": "Guarisce subito la ferita più grave.", "cost": {"gold": 2000, "herbs": 2, "medicine": 1}},
	"morale": {"name": "Elisir del coraggio", "description": "+25 morale, -20 stanchezza.", "cost": {"gold": 2500, "herbs": 3, "cores": 1}},
}

func forge_item(recipe_id: String) -> Dictionary:
	if not facility_built("armory"): return {"ok": false, "message": "Costruisci prima l'Armeria"}
	var recipe: Dictionary = FORGE_RECIPES.get(recipe_id, {})
	if recipe.is_empty(): return {"ok": false, "message": "Ricetta sconosciuta"}
	if not pay(recipe.cost, "Forgia " + recipe.name, "armory"): return {"ok": false, "message": "Risorse insufficienti"}
	data.item_counter = int(data.get("item_counter", 0)) + 1
	var rng := rng_for(str(data.world.seed) + ":item:" + str(data.item_counter))
	var level := facility_level("armory")
	var grade_index := clampi(int(rng.randf_range(0.0, 1.0 + level * 0.55)), 0, mini(GRADES.size() - 1, level))
	var grade: String = GRADES[grade_index]
	var quality := rng.randf_range(0.9, 1.15)
	var item := {"id": "I-%05d" % data.item_counter, "name": "%s [%s]" % [recipe.name, grade], "slot": recipe.slot, "grade": grade}
	match recipe.slot:
		"main": item.power = roundi((18 + grade_index * 7) * quality)
		"armor": item.defense = roundi((14 + grade_index * 6) * quality)
		"accessory": item.hp = roundi((30 + grade_index * 22) * quality)
	data.inventory.append(item)
	add_event("ARMERIA", "Forgiato: " + item.name, "Disponibile in Armeria.", "good")
	save_and_notify()
	return {"ok": true, "item": item}

func equip_item(hero_id: String, item_id: String) -> Dictionary:
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
	template["threat_budget"] = 100 + floor_index * 36 + abs(seed_text.hash()) % 28
	template["threat"] = template.threat_budget
	data.stages[key] = {"descriptor": template, "attempts": 0, "cleared": false, "best_time": 0.0}
	return data.stages[key]

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
	var rewards := {"gold": roundi((7200 + floor_index * 2600) * retry_multiplier), "xp": roundi((95 + floor_index * 34) * retry_multiplier)}
	if first_clear:
		rewards.gems = 120 + floor_index * 10
		if floor_index % 5 == 0: rewards.stones = 1 + floor_index / 20
	return rewards

func begin_mission(floor_index: int) -> Dictionary:
	if floor_index < 1 or floor_index > int(data.world.max_floor): return {"ok": false, "message": "Piano non sbloccato"}
	var party := get_party()
	if party.filter(func(hero): return not hero.is_empty()).size() != PARTY_SIZE: return {"ok": false, "message": "Servono cinque eroi vivi in squadra"}
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
	hero.state = "DEAD"
	hero.memories.push_front("Caduto al Piano %d: %s" % [floor, cause])
	data.assignments.erase(hero_id)
	var party_slot: int = data.party.find(hero_id)
	if party_slot >= 0: data.party[party_slot] = ""
	var tombstone := {"id": hero.id, "name": hero.name, "level": hero.level, "role": hero.role, "rarity": hero.current_rarity, "floor": floor, "cause": cause, "timestamp": now()}
	data.memorial.push_front(tombstone)
	if not data.active_mission.is_empty(): data.active_mission.deaths.append(tombstone)
	add_event("DEATH", hero.name + " è caduto", "Piano %d · %s · morte permanente." % [floor, cause], "danger")
	save_and_notify()

func finalize_mission(result: Dictionary) -> Dictionary:
	if data.active_mission.is_empty(): return {"ok": false, "message": "Nessuna missione attiva", "deaths": []}
	var run: Dictionary = data.active_mission
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
		if not data.world.completed.has(floor): data.world.completed.append(floor)
		if floor < MAX_FLOOR and floor + 1 > int(data.world.max_floor):
			data.world.max_floor = floor + 1
			data.world.current_floor = floor + 1
			_materialize_stage(floor + 1)
		add_event("MISSION", "Piano %d completato" % floor, "%s Oro · %d XP per superstite." % [format_number(rewards.gold), rewards.xp], "good")
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

func set_dev_mode(enabled: bool) -> void:
	data.dev.enabled = enabled
	data.dev.unlimited_resources = enabled
	data.dev.reveal_hidden = enabled
	add_event("DEV", "Modalità sviluppo " + ("attiva" if enabled else "disattivata"), "Risorse infinite e valori nascosti " + ("visibili." if enabled else "nascosti."), "warn")
	save_and_notify()

func dev_unlock_all() -> void:
	data.dev.all_content = true
	data.world.max_floor = maxi(int(data.world.max_floor), 5)
	for floor_index in range(1, int(data.world.max_floor) + 1): _materialize_stage(floor_index)
	add_event("DEV", "Contenuti sbloccati", "Piani e requisiti di progressione ignorati per i test.", "warn")
	save_and_notify()

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
