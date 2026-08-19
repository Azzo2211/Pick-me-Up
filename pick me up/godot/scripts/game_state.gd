extends Node
class_name RiftwardState

signal state_changed
signal toast_requested(title: String, message: String, tone: String)

const SAVE_PATH := "user://riftward_save.json"
const SAVE_VERSION := 2
const PARTY_SIZE := 5
const RARITY_CAPS := {1: 10, 2: 20, 3: 30, 4: 50, 5: 70, 6: 99, 7: 120}

const ROLES := {
	"Guardian": {"line": "Front", "weights": [0.31, 0.04, 0.48, 0.17], "skill": "Aegis Brace", "icon": "G"},
	"Vanguard": {"line": "Front", "weights": [0.47, 0.04, 0.28, 0.21], "skill": "Driving Cleave", "icon": "V"},
	"Lancer": {"line": "Mid", "weights": [0.39, 0.04, 0.27, 0.30], "skill": "Pinning Thrust", "icon": "L"},
	"Ranger": {"line": "Rear", "weights": [0.20, 0.08, 0.17, 0.55], "skill": "Marked Shot", "icon": "R"},
	"Mage": {"line": "Rear", "weights": [0.05, 0.58, 0.18, 0.19], "skill": "Ember Lattice", "icon": "M"},
	"Support": {"line": "Mid", "weights": [0.08, 0.46, 0.30, 0.16], "skill": "Mend", "icon": "S"},
}

const FIRST_NAMES := ["Aella", "Bren", "Cael", "Doria", "Edrin", "Fara", "Galen", "Hesta", "Iven", "Kaia", "Loran", "Mira", "Neris", "Orin", "Pyria", "Quill", "Rhea", "Soren", "Tavia", "Ulric", "Veya", "Wren", "Yara", "Zephan"]
const LAST_NAMES := ["Ashfall", "Blackmere", "Cinder", "Dawnward", "Emberlain", "Frost", "Greywake", "Hollow", "Ironwood", "Jade", "Kestrel", "Lightfoot", "Mourn", "Nightglass", "Oakshield", "Pyre", "Rook", "Stoneveil", "Thorn", "Vale", "Yarrow", "Zephyr"]
const ORIGINS := ["Marche di Veyra", "Città sommersa di Oros", "Cintura mineraria di Khel", "Nomadi di Sable", "Isole di vetro", "Bosco di Talren", "Fortezza di Ardent", "Archivio di Myr"]
const PROFESSIONS := ["Fabbro", "Conciatore", "Cartografo", "Erborista", "Carpentiere", "Archivista", "Cuoco", "Minatore"]
const TRAITS := ["Nervi saldi", "Istinto protettivo", "Passo leggero", "Tenace", "Occhio clinico", "Testardo", "Frugale", "Socievole", "Solitario", "Mano ferma", "Memoria lunga"]

const STAGES := {
	1: {"type": "Subjugation", "name": "La strada spezzata", "biome": "Bosco cinereo", "objective": "Elimina tutte le minacce", "duration": 48.0, "color": "#3c7968", "description": "Predoni del Rift hanno chiuso l'unica via verso la torre.", "waves": [[0.0, "raider", 4], [10.0, "hound", 2]]},
	2: {"type": "Survival", "name": "Campana nella nebbia", "biome": "Borgo evacuato", "objective": "Sopravvivi per 45 secondi", "duration": 45.0, "color": "#346b86", "description": "La campana attira sciami dalle case vuote. Munizioni e disciplina decidono la sopravvivenza.", "waves": [[0.0, "raider", 3], [9.0, "archer", 2], [20.0, "hound", 4], [31.0, "brute", 2]]},
	3: {"type": "Exploration", "name": "Osservatorio sommerso", "biome": "Rovine allagate", "objective": "Metti in sicurezza 3 punti d'interesse", "duration": 64.0, "color": "#365c8c", "description": "Le rovine nascondono informazioni persistenti sul climax dello Stream.", "waves": [[0.0, "hound", 3], [15.0, "raider", 3], [30.0, "archer", 2]]},
	4: {"type": "Defense", "name": "L'ultima lanterna", "biome": "Santuario in rovina", "objective": "Proteggi il faro del Rift", "duration": 50.0, "color": "#94713c", "description": "Il faro deve restare integro mentre l'Archivio decodifica le coordinate.", "waves": [[0.0, "raider", 4], [12.0, "archer", 2], [25.0, "brute", 2], [37.0, "hound", 4]]},
	5: {"type": "Boss", "name": "Custode delle radici", "biome": "Cuore del bosco", "objective": "Abbatti il Custode", "duration": 90.0, "color": "#537d3d", "description": "La minaccia nascosta dello Stream attende sotto la torre.", "waves": [[0.0, "boss", 1], [0.0, "raider", 2], [22.0, "hound", 3], [45.0, "archer", 2]]},
}

const SHOP_PRODUCTS := [
	{"id": "founder_cache", "name": "Cassa del Fondatore", "category": "RISORSE", "price": "€0,00", "description": "50.000 Oro e 500 Gemme per provare i sistemi del prototipo.", "limit": 1, "grant": {"gold": 50000, "gems": 500}},
	{"id": "field_kit", "name": "Kit da Spedizione", "category": "MATERIALI", "price": "€0,00", "description": "8 Minerale, 6 Pelle, 5 Razioni e 3 Medicine.", "limit": 1, "grant": {"ore": 8, "leather": 6, "food": 5, "medicine": 3}},
	{"id": "summoner_trial", "name": "Prova dell'Evocatore", "category": "EVOCAZIONE", "price": "€0,00", "description": "5.000 Gemme simulate per testare dieci risonanze high-grade.", "limit": 1, "grant": {"gems": 5000}},
	{"id": "aurora_livery", "name": "Livrea Aurora", "category": "COSMETICO", "price": "€0,00", "description": "Tema cromatico cosmetico per il profilo Master.", "limit": 1, "grant": {"cosmetic": "aurora"}},
	{"id": "pioneer_plate", "name": "Targa Pioniere", "category": "COSMETICO", "price": "€0,00", "description": "Nameplate commemorativo della vertical slice.", "limit": 1, "grant": {"cosmetic": "pioneer"}},
]

var data: Dictionary = {}
var is_test_mode := OS.get_cmdline_user_args().has("--test-mode")

func _ready() -> void:
	if is_test_mode: new_world("automated-test-world")
	else: load_or_create()

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
		"world": {"id": "WORLD-%08X" % abs(world_seed.hash()), "seed": world_seed, "master_name": "Aster", "gold": 220000, "gems": 2500, "stones": 1, "current_floor": 1, "max_floor": 1, "completed": [], "materials": {"ore": 8, "leather": 6, "wood": 7, "cores": 0, "food": 6, "medicine": 2}, "last_saved": Time.get_unix_time_from_system()},
		"heroes": [], "party": [], "relationships": {}, "stages": {}, "events": [], "ledger": [], "memorial": [], "inventory": [],
		"facilities": {"Summoning Hall": 1, "Training Center": 1, "Armory": 1, "Warehouse": 1, "Lodging": 1, "Smithy": 0, "Workshop": 0, "Archive": 0, "Infirmary": 0, "Synthesis Chamber": 0, "Magic Hall": 0, "Dimension Gate": 0},
		"pity": {"high": 0}, "summon_counter": 0, "shop_claims": {}, "shop_history": [], "cosmetics": [], "active_mission": {}, "tutorial_seen": false,
		"dev": {"enabled": true, "unlimited_resources": true, "reveal_hidden": true, "god_mode": false, "all_content": false},
	}
	var starter_roles := ["Guardian", "Vanguard", "Lancer", "Ranger", "Support", "Mage"]
	for i in starter_roles.size(): data.heroes.append(generate_hero(world_seed + ":starter:" + str(i), 2 if i == 4 else 1, starter_roles[i]))
	for i in PARTY_SIZE: data.party.append(data.heroes[i].id)
	_materialize_stage(1)
	add_event("SYSTEM", "Nexus riattivato", "Sei eroi attendono la prima valutazione. Modalità sviluppo attiva.", "good")
	add_event("DEV", "Strumenti QA abilitati", "Risorse infinite e dati nascosti visibili. I costi reali restano mostrati.", "warn")
	add_ledger("gold", 220000, "Dotazione iniziale del Nexus", "onboarding")
	save_game()
	state_changed.emit()

func _migrate() -> void:
	data.version = SAVE_VERSION
	data.get_or_add("shop_claims", {})
	data.get_or_add("shop_history", [])
	data.get_or_add("cosmetics", [])
	data.get_or_add("inventory", [])
	data.get_or_add("active_mission", {})
	data.get_or_add("tutorial_seen", true)
	data.get_or_add("dev", {"enabled": true, "unlimited_resources": true, "reveal_hidden": true, "god_mode": false, "all_content": false})
	data.dev.get_or_add("god_mode", false)
	data.dev.get_or_add("all_content", false)
	data.dev.enabled = true
	data.dev.unlimited_resources = true
	data.dev.reveal_hidden = true
	for stage_key in data.stages:
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

func _apply_offline_progress() -> void:
	var now := Time.get_unix_time_from_system()
	var elapsed_hours: float = min(8.0, max(0.0, (now - float(data.world.get("last_saved", now))) / 3600.0))
	var world_hours := elapsed_hours * 3.0
	if world_hours >= 0.1:
		var recovered := 0
		for hero in data.heroes:
			if hero.state != "ALIVE": continue
			var before: int = hero.fatigue
			hero.fatigue = clampi(hero.fatigue - roundi(world_hours * 6.0), 0, 100)
			hero.morale = clampi(hero.morale + roundi(world_hours * 1.4), 0, 100)
			recovered += before - hero.fatigue
		add_event("REPORT", "Rapporto offline", "%.1f ore-Nexus risolte. Fatigue recuperata: %d." % [world_hours, recovered], "info")
	data.world.last_saved = now
	save_game()

func save_game() -> void:
	if data.is_empty() or is_test_mode: return
	data.world.last_saved = Time.get_unix_time_from_system()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(data, "  "))

func rng_for(text: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(text.hash())
	return rng

func _pick(rng: RandomNumberGenerator, values: Array) -> Variant:
	return values[rng.randi_range(0, values.size() - 1)]

func stars(rarity: int) -> String:
	return "★".repeat(rarity)

func format_number(value: float) -> String:
	var source := str(roundi(value))
	var output := ""
	var count := 0
	for i in range(source.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0: output = "." + output
		output = source[i] + output
		count += 1
	return output

func is_dev_unlimited() -> bool:
	return bool(data.get("dev", {}).get("enabled", false)) and bool(data.dev.get("unlimited_resources", false))

func display_resource(key: String) -> String:
	if is_dev_unlimited(): return "∞"
	if key in ["gold", "gems", "stones"]: return format_number(float(data.world.get(key, 0)))
	return format_number(float(data.world.materials.get(key, 0)))

func _can_pay(key: String, amount: int) -> bool:
	if is_dev_unlimited(): return true
	if key in ["gold", "gems", "stones"]: return int(data.world.get(key, 0)) >= amount
	return int(data.world.materials.get(key, 0)) >= amount

func _pay(key: String, amount: int, reason: String, source: String) -> bool:
	if not _can_pay(key, amount): return false
	if is_dev_unlimited():
		add_ledger(key, 0, "DEV ∞ · costo simulato %d · %s" % [amount, reason], source)
		return true
	if key in ["gold", "gems", "stones"]: data.world[key] -= amount
	else: data.world.materials[key] = int(data.world.materials.get(key, 0)) - amount
	add_ledger(key, -amount, reason, source)
	return true

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

func _starter_equipment(role: String) -> Dictionary:
	var names := {"Guardian": "Spada da presidio", "Vanguard": "Lama mercenaria", "Lancer": "Lancia d'acciaio", "Ranger": "Arco laminato", "Mage": "Verga di quarzo", "Support": "Mazza cerimoniale"}
	var armor := 18 if role == "Guardian" else 12 if role in ["Vanguard", "Lancer"] else 7
	return {"main": {"name": names[role], "grade": "D", "power": 15}, "sub": {"name": "Scudo" if role == "Guardian" else "Focus" if role in ["Mage", "Support"] else "Faretra" if role == "Ranger" else "Off-hand", "grade": "D", "block": 18 if role == "Guardian" else 0, "ammo": 24 if role == "Ranger" else 0}, "armor": {"name": "Equipaggiamento da campo", "grade": "D", "defense": armor}, "accessory": {}}

func _assessment(hero: Dictionary) -> Array:
	var output := []
	if hero.potential >= 90: output.append("Ceiling impossibile da stimare")
	elif hero.potential >= 75: output.append("Margine di crescita eccezionale")
	elif hero.potential >= 58: output.append("Apprendimento sopra la media")
	else: output.append("Crescita metodica, non esplosiva")
	var best_stat := "str"
	for key in hero.stats:
		if hero.stats[key] > hero.stats[best_stat]: best_stat = key
	output.append("Affinità evidente: " + best_stat.to_upper())
	output.append("Potenziale numerico normalmente nascosto")
	return output

func derived_stats(hero: Dictionary) -> Dictionary:
	var equipment: Dictionary = hero.equipment
	var max_hp := roundi(100 + hero.stats.sta * 12 + hero.level * 6)
	return {"max_hp": max_hp, "attack": float(equipment.main.get("power", 0)) + hero.stats.str * 1.75, "magic": hero.stats.int * 1.9 + (12 if hero.role in ["Mage", "Support"] else 0), "defense": float(equipment.armor.get("defense", 0)) + hero.stats.sta * 0.55, "accuracy": clampf(70 + hero.stats.agi * 0.45, 35, 98), "evasion": clampf(hero.stats.agi * 0.22, 0, 35), "crit": clampf(3 + hero.stats.agi * 0.08, 3, 30), "block": equipment.sub.get("block", 0), "ammo": equipment.sub.get("ammo", 0)}

func hero_power(hero: Dictionary) -> int:
	if hero.is_empty() or hero.state != "ALIVE": return 0
	var d := derived_stats(hero)
	var attack: float = max(d.attack * 0.75, d.magic) if hero.role in ["Mage", "Support"] else d.attack
	return roundi((d.max_hp * 0.22 + attack * 3 + d.defense * 2) * (0.8 + hero.morale / 500.0) * (1.0 - max(0, hero.fatigue - 50) * 0.0035))

func get_alive_heroes() -> Array:
	return data.heroes.filter(func(hero): return hero.state == "ALIVE")

func hero_by_id(hero_id: String) -> Dictionary:
	for hero in data.heroes:
		if hero.id == hero_id: return hero
	return {}

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
	if previous >= 0: data.party[previous] = ""
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
	for hero in party:
		if hero.is_empty(): continue
		alive += 1
		score += hero_power(hero)
		if hero.fatigue >= 70: warnings.append(hero.name + " ha Fatigue critica")
		if not hero.injuries.is_empty(): warnings.append(hero.name + " è ferito")
	if alive < PARTY_SIZE: warnings.append("Party incompleto: %d/%d" % [alive, PARTY_SIZE])
	var grade := "S" if score >= 2200 else "A" if score >= 1700 else "B" if score >= 1200 else "C" if score >= 800 else "D"
	return {"score": score, "grade": grade, "warnings": warnings, "ready": alive == PARTY_SIZE}

func summon(pool: String, count: int) -> Dictionary:
	var cost_each := 500 if pool == "high" else 10000
	var currency := "gems" if pool == "high" else "gold"
	if not _pay(currency, cost_each * count, "Evocazione " + pool, "summon"): return {"ok": false, "message": "Risorse insufficienti"}
	var heroes := []
	for i in count:
		data.summon_counter += 1
		var rng := rng_for(str(data.world.seed) + ":summon:" + str(data.summon_counter))
		var roll := rng.randf_range(0.0, 100.0)
		var rarity := 1
		if pool == "high":
			data.pity.high += 1
			var five_rate: float = 1.0 + max(0, int(data.pity.high) - 69) * 0.25
			if data.pity.high >= 100 or roll < five_rate: rarity = 5; data.pity.high = 0
			elif roll < 6.5: rarity = 4
			else: rarity = 3
		else:
			rarity = 3 if roll < 3.0 else 2 if roll < 22.0 else 1
		var hero := generate_hero(str(data.world.seed) + ":hero:" + str(data.summon_counter), rarity)
		data.heroes.append(hero)
		heroes.append(hero)
	add_event("SUMMON", "%d risonanze completate" % count, "Pool %s · nuovi HeroSeed registrati." % pool, "good")
	save_and_notify()
	return {"ok": true, "heroes": heroes}

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
			return {"ok": false, "message": "%s è assegnato al party." % hero.name, "heroes": []}
		heroes.append(hero)
	var rarity := int(heroes[0].current_rarity)
	if rarity >= 7:
		return {"ok": false, "message": "La rarità massima non può essere fusa.", "heroes": []}
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
	for stat_key in core.stats:
		var absorbed := int(heroes[1].stats.get(stat_key, 0)) + int(heroes[2].stats.get(stat_key, 0))
		core.stats[stat_key] += maxi(1, roundi(float(absorbed) * 0.04))
	core.current_rarity = old_rarity + 1
	core.potential = mini(100, maxi(int(core.potential), maxi(int(heroes[1].potential), int(heroes[2].potential))) + 2)
	core.morale = mini(100, int(core.morale) + 5)
	var donor_ids := [str(heroes[1].id), str(heroes[2].id)]
	for index in range(data.heroes.size() - 1, -1, -1):
		if str(data.heroes[index].id) in donor_ids:
			data.heroes.remove_at(index)
	add_event("MERGE", core.name + " ha completato la fusione", "%s + %s assorbiti · rarità %s." % [heroes[1].name, heroes[2].name, stars(core.current_rarity)], "good")
	save_and_notify()
	return {"ok": true, "hero": core, "consumed": donor_ids}

func train_hero(hero_id: String) -> Dictionary:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state != "ALIVE": return {"ok": false, "message": "Eroe non disponibile"}
	if hero.level >= int(RARITY_CAPS[hero.current_rarity]): return {"ok": false, "message": "Cap raggiunto: serve una promozione"}
	var cost: int = 600 + int(hero.level) * 120
	if not _pay("gold", cost, "Training " + hero.name, "training"): return {"ok": false, "message": "Oro insufficiente"}
	hero.level += 1
	for key in hero.stats: hero.stats[key] += max(1, roundi(float(hero.growth) * (0.42 if key in ["str", "sta"] else 0.30)))
	hero.fatigue = clampi(hero.fatigue + 5, 0, 100)
	save_and_notify()
	return {"ok": true, "cost": cost}

func promote_hero(hero_id: String) -> Dictionary:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.current_rarity >= 7: return {"ok": false, "message": "Promozione non disponibile"}
	if hero.level < int(RARITY_CAPS[hero.current_rarity]): return {"ok": false, "message": "Raggiungi prima il level cap"}
	var stones_cost := maxi(1, int(hero.current_rarity) - 1)
	if not _pay("stones", stones_cost, "Promozione " + hero.name, "promotion"): return {"ok": false, "message": "Pietre insufficienti"}
	hero.current_rarity += 1
	add_event("HERO", hero.name + " promosso", "Rarità corrente: " + stars(hero.current_rarity), "good")
	save_and_notify()
	return {"ok": true}

func rest_roster() -> Dictionary:
	var cost := 1200
	if not _pay("gold", cost, "Riposo roster", "lodging"): return {"ok": false, "message": "Oro insufficiente"}
	var recovered := 0
	for hero in data.heroes:
		if hero.state != "ALIVE": continue
		var before: int = hero.fatigue
		hero.fatigue = maxi(0, hero.fatigue - 24)
		hero.morale = mini(100, hero.morale + 8)
		recovered += before - hero.fatigue
	save_and_notify()
	return {"ok": true, "recovered": recovered}

func craft_item() -> Dictionary:
	var cost := 4500 if int(data.facilities.get("Smithy", 0)) > 0 else 6500
	if not _pay("gold", cost, "Forgiatura", "smithy"): return {"ok": false, "message": "Oro insufficiente"}
	if not _pay("ore", 2, "Forgiatura", "smithy") or not _pay("leather", 1, "Forgiatura", "smithy"): return {"ok": false, "message": "Materiali insufficienti"}
	var rng := rng_for(str(Time.get_ticks_msec()))
	var grade: String = ["D", "D", "C", "C", "B"][rng.randi_range(0, 4)]
	var item := {"name": "Lama del Rift", "slot": "main", "grade": grade, "power": 17 + ["D", "C", "B"].find(grade) * 5}
	data.inventory.append(item)
	add_event("CRAFT", "Oggetto completato", "%s [%s] depositato nel Warehouse." % [item.name, grade], "good")
	save_and_notify()
	return {"ok": true, "item": item}

func _materialize_stage(floor_index: int) -> Dictionary:
	var key := str(floor_index)
	if data.stages.has(key): return data.stages[key]
	var template: Dictionary = STAGES.get(floor_index, STAGES[5]).duplicate(true)
	var seed_text := str(data.world.seed) + ":floor:" + str(floor_index)
	template["floor"] = floor_index
	template["seed"] = "%08X" % abs(seed_text.hash())
	template["threat_budget"] = 100 + floor_index * 36 + abs(seed_text.hash()) % 28
	template["threat"] = template.threat_budget
	data.stages[key] = {"descriptor": template, "attempts": 0, "cleared": false, "best_time": 0.0}
	return data.stages[key]

func get_stage(floor_index: int) -> Dictionary:
	return _materialize_stage(floor_index)

func begin_mission(floor_index: int) -> Dictionary:
	if floor_index < 1 or floor_index > int(data.world.max_floor): return {"ok": false, "message": "Piano non sbloccato"}
	var party := get_party()
	if party.filter(func(hero): return not hero.is_empty()).size() != PARTY_SIZE: return {"ok": false, "message": "Servono cinque eroi vivi"}
	var stage_state := _materialize_stage(floor_index)
	stage_state.attempts += 1
	data.active_mission = {"floor": floor_index, "attempt": stage_state.attempts, "started": Time.get_unix_time_from_system(), "deaths": []}
	save_game()
	return {"ok": true, "stage": stage_state.descriptor.duplicate(true), "party": party, "attempt": stage_state.attempts}

func record_death(hero_id: String, cause: String) -> void:
	var hero := hero_by_id(hero_id)
	if hero.is_empty() or hero.state == "DEAD": return
	var floor := int(data.active_mission.get("floor", data.world.current_floor))
	hero.state = "DEAD"
	hero.memories.push_front("Caduto al Piano %d: %s" % [floor, cause])
	var party_slot: int = data.party.find(hero_id)
	if party_slot >= 0: data.party[party_slot] = ""
	var tombstone := {"id": hero.id, "name": hero.name, "level": hero.level, "role": hero.role, "floor": floor, "cause": cause, "timestamp": Time.get_unix_time_from_system()}
	data.memorial.push_front(tombstone)
	if not data.active_mission.is_empty(): data.active_mission.deaths.append(tombstone)
	add_event("DEATH", hero.name + " è caduto", "Piano %d · %s · morte permanente." % [floor, cause], "danger")
	save_and_notify()

func finalize_mission(result: Dictionary) -> Dictionary:
	if data.active_mission.is_empty(): return {"ok": false, "message": "Nessuna missione attiva", "deaths": []}
	var run: Dictionary = data.active_mission
	var floor := int(run.floor)
	var stage_state: Dictionary = _materialize_stage(floor)
	var retry_multiplier: float = max(0.35, 1.0 - max(0, int(run.attempt) - 1) * 0.12)
	var reward_gold := 0
	var reward_xp := 0
	if bool(result.victory):
		reward_gold = roundi((7200 + floor * 2600) * retry_multiplier)
		reward_xp = roundi((95 + floor * 34) * retry_multiplier)
		data.world.gold += reward_gold
		add_ledger("gold", reward_gold, "Clear Piano %d" % floor, "mission")
		stage_state.cleared = true
		stage_state.best_time = float(result.duration) if float(stage_state.best_time) <= 0 else min(float(stage_state.best_time), float(result.duration))
		if not data.world.completed.has(floor): data.world.completed.append(floor)
		if floor < 5:
			data.world.max_floor = maxi(int(data.world.max_floor), floor + 1)
			data.world.current_floor = floor + 1
			_materialize_stage(floor + 1)
		if floor >= 5:
			data.facilities.Smithy = maxi(1, int(data.facilities.Smithy))
			data.facilities.Workshop = maxi(1, int(data.facilities.Workshop))
		add_event("MISSION", "Piano %d completato" % floor, "%d Oro · %d XP per superstite." % [reward_gold, reward_xp], "good")
	else:
		add_event("MISSION", "Missione non completata", "Il descriptor del Piano %d resta invariato." % floor, "warn")
	for hero_result in result.hero_results:
		var hero := hero_by_id(hero_result.id)
		if hero.is_empty() or hero.state != "ALIVE": continue
		hero.missions += 1
		hero.kills += int(hero_result.kills)
		hero.fatigue = clampi(hero.fatigue + int(hero_result.fatigue), 0, 100)
		hero.morale = clampi(hero.morale + (5 if result.victory else -8), 0, 100)
		if result.victory: hero.victories += 1
		hero.xp += reward_xp
		if float(hero_result.hp_ratio) < 0.30: hero.injuries.append("Ferita da combattimento")
	var deaths: Array = run.deaths.duplicate()
	data.active_mission = {}
	save_and_notify()
	return {"ok": true, "gold": reward_gold, "xp": reward_xp, "deaths": deaths}

func claim_shop_product(product_id: String) -> Dictionary:
	var product: Dictionary = {}
	for item in SHOP_PRODUCTS:
		if item.id == product_id: product = item; break
	if product.is_empty(): return {"ok": false, "message": "Prodotto non trovato"}
	var claimed := int(data.shop_claims.get(product_id, 0))
	if claimed >= int(product.limit): return {"ok": false, "message": "Articolo già riscattato in questo world"}
	for key in product.grant:
		if key in ["gold", "gems"]:
			data.world[key] += product.grant[key]
			add_ledger(key, product.grant[key], "Shop gratuito: " + product.name, "shop_sandbox")
		elif key == "cosmetic":
			if not data.cosmetics.has(product.grant[key]): data.cosmetics.append(product.grant[key])
		else: data.world.materials[key] = int(data.world.materials.get(key, 0)) + int(product.grant[key])
	data.shop_claims[product_id] = claimed + 1
	data.shop_history.push_front({"id": product_id, "name": product.name, "price": "€0,00", "timestamp": Time.get_unix_time_from_system(), "transaction": "SIM-%08X" % abs((product_id + str(Time.get_ticks_msec())).hash())})
	add_event("SHOP", "Articolo riscattato", product.name + " · €0,00 · nessuna transazione reale.", "good")
	save_and_notify()
	return {"ok": true, "product": product}

func dev_unlock_all() -> void:
	data.dev.all_content = true
	data.world.max_floor = 5
	for floor_index in range(1, 6): _materialize_stage(floor_index)
	for facility in data.facilities: data.facilities[facility] = maxi(1, int(data.facilities[facility]))
	add_event("DEV", "Contenuti sbloccati", "Piani 1–5 e tutte le facilities sono ora ispezionabili.", "warn")
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
	add_event("DEV", "Roster ripristinato", "Eroi vivi, Fatigue 0, morale 100 e party ricostruito.", "warn")
	save_and_notify()

func dev_spawn_hero(rarity: int = 5) -> Dictionary:
	data.summon_counter += 1
	var hero := generate_hero(str(data.world.seed) + ":dev:" + str(Time.get_ticks_msec()) + ":" + str(data.summon_counter), clampi(rarity, 1, 7))
	data.heroes.append(hero)
	add_event("DEV", "Eroe QA generato", hero.name + " · " + stars(hero.native_rarity), "warn")
	save_and_notify()
	return hero

func dev_reset_shop() -> void:
	data.shop_claims = {}
	data.shop_history = []
	add_event("DEV", "Shop resettato", "Limiti e ricevute sandbox azzerati.", "warn")
	save_and_notify()

func dev_set_pity(value: int = 99) -> void:
	data.pity.high = clampi(value, 0, 99)
	add_event("DEV", "Pity modificato", "High-grade pity impostato a %d/100." % data.pity.high, "warn")
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
	if data.party.size() != PARTY_SIZE: issues.append("Party size non valida: %d" % data.party.size())
	return issues

func add_event(category: String, title: String, text: String, tone: String = "info") -> void:
	data.events.push_front({"category": category, "title": title, "text": text, "tone": tone, "timestamp": Time.get_unix_time_from_system(), "read": false})
	if data.events.size() > 120: data.events.resize(120)

func add_ledger(currency: String, delta: int, reason: String, source: String) -> void:
	data.ledger.push_front({"currency": currency, "delta": delta, "reason": reason, "source": source, "timestamp": Time.get_unix_time_from_system()})
	if data.ledger.size() > 180: data.ledger.resize(180)

func save_and_notify() -> void:
	save_game()
	state_changed.emit()
