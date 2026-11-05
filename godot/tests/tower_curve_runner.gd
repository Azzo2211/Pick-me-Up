extends SceneTree

## Banco di prova della difficoltà della Torre (scaglioni di 5 piani).
## Simula le battaglie con una "squadra di riferimento" per ogni scaglione: quella che
## un giocatore ha di solito quando arriva al primo piano dello scaglione.
##
##   godot --headless --path godot -s res://tests/tower_curve_runner.gd -- --test-mode [--tiers=0,1,2] [--trials=6]
##       per ogni scaglione: piani 1–5 con la squadra di riferimento, poi la prova
##       con la squadra dello scaglione successivo (quella che serve per passarla)
##   ... --calibrate-trials [--target=0.65]
##       per le prove: fattore di forza con cui la squadra dello scaglione dopo vince
##   ... --calibrate [--target=0.6]
##       cerca la forza dei nemici che dà quella percentuale di vittorie (media dei
##       piani 1–4 dello scaglione) e stampa i valori per TOWER_TIER_POWER

## Squadra di riferimento per scaglione: rarità dei 5 eroi, livello, grado dell'equipaggiamento (0 = D … 4 = S).
## Il livello si ferma al massimo della rarità. Tabella di Game Design: vedi docs/GAME_SYSTEMS.md.
const REFERENCE := [
	[[1, 1, 1, 1, 2], 5, 0], [[2, 1, 2, 1, 2], 14, 0], [[2, 2, 3, 2, 3], 22, 1], [[3, 3, 3, 3, 3], 29, 1],
	[[4, 3, 4, 3, 4], 36, 2], [[4, 4, 4, 4, 4], 44, 2], [[5, 4, 5, 4, 5], 52, 3], [[5, 5, 5, 5, 5], 60, 3],
	[[5, 5, 5, 5, 5], 68, 3], [[6, 5, 6, 5, 6], 74, 4], [[6, 6, 6, 6, 6], 80, 4], [[6, 6, 6, 6, 6], 86, 4],
	[[6, 6, 6, 6, 6], 92, 4], [[7, 6, 7, 6, 7], 98, 4], [[7, 7, 7, 7, 7], 103, 4], [[7, 7, 7, 7, 7], 107, 4],
	[[7, 7, 7, 7, 7], 111, 4], [[7, 7, 7, 7, 7], 114, 4], [[7, 7, 7, 7, 7], 117, 4], [[7, 7, 7, 7, 7], 120, 4],
]
const ROLES := ["Guardian", "Vanguard", "Lancer", "Support", "Ranger"]

var state
var battle_script: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.get_slice("=", 1)
	return fallback

func _run() -> void:
	state = root.get_node("GameState")
	battle_script = load("res://scripts/battle/battle_scene.gd")
	var tiers: Array = Array(_arg("tiers", "0,1,2,3,4,6,9,13,19").split(",")).map(func(v): return int(v))
	var trials := int(_arg("trials", "6"))
	if OS.get_cmdline_user_args().has("--calibrate-trials"):
		var target := float(_arg("target", "0.65"))
		for tier in tiers: await _calibrate_trial(tier, trials, target)
	elif OS.get_cmdline_user_args().has("--calibrate"):
		var target := float(_arg("target", "0.6"))
		for tier in tiers: await _calibrate(tier, trials, target)
	else:
		for tier in tiers: await _check(tier, trials)
	quit(0)

## Una serie di battaglie: [vittorie, morti totali, durata media].
func _series(floor_index: int, tier_squad: int, trials: int, scale: float = 1.0) -> Array:
	var wins := 0
	var deaths := 0
	var total_time := 0.0
	for trial in trials:
		state.new_world("curve-%d-%d-%d" % [floor_index, tier_squad, trial])
		state.debug_enemy_scale = scale
		_reference_squad(tier_squad, trial)
		state.data.world.max_floor = floor_index
		var start: Dictionary = state.begin_mission(floor_index)
		var battle = battle_script.new()
		battle.setup(start.stage, start.party, int(start.attempt))
		root.add_child(battle)
		var guard := 0
		while not battle.completed and guard < 4000:
			battle.accumulator += 0.1
			while battle.accumulator >= battle.TICK and not battle.completed:
				battle._tick(battle.TICK)
				battle.accumulator -= battle.TICK
			guard += 1
		if battle.completed and battle.result_victory: wins += 1
		for u in battle.units:
			if u.hero and not u.alive: deaths += 1
		total_time += battle.elapsed
		battle.queue_free()
		await process_frame
	state.debug_enemy_scale = 1.0
	return [wins, deaths, total_time / maxf(1.0, trials)]

func _reference_squad(tier: int, variant: int) -> void:
	var row: Array = REFERENCE[clampi(tier, 0, REFERENCE.size() - 1)]
	var ids := []
	state.data.heroes.clear()
	for i in 5:
		var rarity: int = row[0][i]
		var role: String = ROLES[i]
		if i == 4 and variant % 2 == 1: role = "Mage"
		var hero: Dictionary = state.generate_hero("ref-%d-%d-%d" % [tier, i, variant], rarity, role)
		hero.class_chosen = true
		var level := mini(int(row[1]), int(state.RARITY_CAPS[rarity]))
		for l in level - 1: state._apply_level_up(hero)
		var grade: int = row[2]
		hero.equipment.main.power = 18 + grade * 7
		hero.equipment.main.grade = state.GRADES[grade]
		hero.equipment.armor.defense = 14 + grade * 6 + (4 if role == "Guardian" else 0)
		hero.equipment.armor.grade = state.GRADES[grade]
		hero.equipment.accessory = {"name": "Amuleto", "grade": state.GRADES[grade], "hp": 30 + grade * 22}
		hero.morale = 75
		hero.fatigue = 0
		state.data.heroes.append(hero)
		ids.append(hero.id)
	state.data.party = ids

func _check(tier: int, trials: int) -> void:
	var squad_power := 0
	_reference_squad(tier, 0)
	for hero in state.get_party(): squad_power += state.hero_power(hero)
	print("\n== Scaglione %d (piani %d–%d) · squadra di riferimento: potenza %d" % [tier + 1, tier * 5 + 1, tier * 5 + 5, squad_power])
	for step in 5:
		var floor_index: int = tier * 5 + step + 1
		var r := await _series(floor_index, tier, trials)
		var threat: int = state.get_stage(floor_index).descriptor.threat_budget
		print("  Piano %3d %-8s minaccia %5d  vittorie %d/%d  morti %2d  durata %3ds" % [floor_index, "PROVA" if state.is_trial_floor(floor_index) else "", threat, r[0], trials, r[1], roundi(r[2])])
	var trial_floor: int = tier * 5 + 5
	var stronger := await _series(trial_floor, tier + 1, trials)
	var trial: Dictionary = state.get_stage(trial_floor).descriptor.get("trial", {})
	print("  Piano %3d PROVA con la squadra dello scaglione dopo: vittorie %d/%d  morti %2d  (regole %s, campioni %d)" % [trial_floor, stronger[0], trials, stronger[1], ", ".join(trial.get("rules", [])), int(trial.get("elites", 0))])

## Cerca il moltiplicatore che dà, in media sui piani 1–4 dello scaglione (tipi di missione
## diversi), la percentuale di vittorie voluta con la squadra di riferimento.
func _calibrate(tier: int, trials: int, target: float) -> void:
	var low := 0.1
	var high := 40.0
	for i in 8:
		var mid := sqrt(low * high)
		var wins := 0
		for step in 4:
			var r := await _series(tier * 5 + step + 1, tier, trials, mid)
			wins += int(r[0])
		if float(wins) / (trials * 4) >= target: low = mid
		else: high = mid
	var table: float = state.enemy_scaling(tier * 5 + 1).power
	print("Scaglione %2d: forza attuale %.3f · consigliata %.3f" % [tier + 1, table, table * sqrt(low * high)])

## Prova del Guardiano: moltiplicatore che dà quella percentuale di vittorie alla squadra
## dello scaglione successivo (quella che dovrebbe riuscire a passarla).
func _calibrate_trial(tier: int, trials: int, target: float) -> void:
	var floor_index := tier * 5 + 5
	var low := 0.05
	var high := 4.0
	for i in 8:
		var mid := sqrt(low * high)
		var r := await _series(floor_index, tier + 1, trials, mid)
		if float(r[0]) / trials >= target: low = mid
		else: high = mid
	print("Prova %3d: fattore consigliato %.3f" % [floor_index, sqrt(low * high)])
