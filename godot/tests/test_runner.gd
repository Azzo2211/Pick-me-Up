extends SceneTree

## Test delle regole di gioco (GameState). Avvio:
## godot --headless --path godot -s res://tests/test_runner.gd -- --test-mode

var passed := 0
var failed := 0

func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Avvia questa suite con: -- --test-mode")
		quit(2)
		return
	print("Riftward Godot test suite")
	_test("generazione eroi deterministica", _test_deterministic_heroes)
	_test("world iniziale: base Lv.1 e party da cinque", _test_initial_world)
	_test("summon: costi e pool di rarità", _test_summon)
	_test("pool trascendente 6★/7★ bloccato fino al Piano 20", _test_transcendent)
	_test("fusione di tre eroi", _test_merge)
	_test("fusione oltre 5★ rifiutata", _test_merge_cap)
	_test("modalità sviluppo opzionale a risorse infinite", _test_dev_unlimited)
	_test("addestramento nel tempo con level-up e cap", _test_training)
	_test("dormitorio: recupero e guarigione", _test_dormitory)
	_test("espansione base e cantieri", _test_base_upgrade)
	_test("stanchezza: malus reali e sfiniti a casa", _test_fatigue_penalties)
	_test("gemme a ogni piano vinto", _test_floor_gems)
	_test("livello strutture limitato dal livello base", _test_facility_cap)
	_test("base fino al Lv.10, strutture fino al Lv.10, isole e vantaggi", _test_base_islands)
	_test("descriptor persistente e piani procedurali", _test_stage_persistence)
	_test("torre: scaglioni di 5 piani e Prova del Guardiano", _test_tower_tiers)
	_test("migrazione salvataggi v2", _test_legacy_migration)
	_test("permadeath e tombstone", _test_permadeath)
	_test("clear, sblocco piano ed esperienza", _test_clear)
	_test("promozioni 6★ riservate all'endgame", _test_promotion_gate)
	_test("armeria: forgia ed equipaggiamento", _test_armory)
	_test("armeria: forgia a mano, gradi da F a S e difficoltà", _test_forge_minigame_rules)
	_test("richiamo d'emergenza contro il blocco", _test_emergency)
	_test("ricarica JSON: niente piani completati falsi", _test_json_reload)
	_test("sblocchi di sviluppo non sopravvivono", _test_dev_leak)
	_test("addestramento offline rispetta la stanchezza", _test_offline_steps)
	_test("chiudere in missione conta come sconfitta", _test_abandoned_mission)
	_test("oggetti vecchi senza id ricevono un id", _test_item_ids)
	_test("luce della base salvata e migrata", _test_light_setting)
	_test("tratti diversi e abilità in italiano", _test_traits_skills)
	_test("sviluppo: tutti i piani, base e eroi al massimo", _test_dev_tools)
	_test("negozio: prezzi, limiti giornalieri e scorte", _test_shop)
	_test("pacchetto personaggi: aspetto salvato e migrato", _test_character_pack)
	_test("popolani 1★-2★: mestiere, consiglio e scelta della classe", _test_commoners)
	_test("aspetto a pezzi: archetipo, volto, capelli, età", _test_modular_look)
	_test("kit 3D: corpi vestiti, teste, capelli e accessori", _test_character_kit)
	_test("pacchetto animazioni: 40 clip sullo scheletro", _test_motion_pack)
	_test("consigli del Sistema: squadra bloccata, formazione consigliata, nessun cambio di stato", _test_system_advisor)
	print("\nRisultato: %d passati, %d falliti" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _fresh(seed_text: String) -> RiftwardState:
	var game := RiftwardState.new()
	game.is_test_mode = true
	game.new_world(seed_text)
	return game

func _test(name: String, callable: Callable) -> void:
	var result: Variant = callable.call()
	var ok: bool = false
	var message := ""
	if result is Array:
		ok = result[0]
		message = result[1] if result.size() > 1 else ""
	else:
		ok = bool(result)
	if ok:
		passed += 1
		print("PASS  " + name)
	else:
		failed += 1
		push_error("FAIL  %s%s" % [name, " // " + message if not message.is_empty() else ""])

func _test_deterministic_heroes() -> Array:
	var a := _fresh("deterministic-seed")
	var b := _fresh("deterministic-seed")
	var same: bool = a.data.heroes[0].id == b.data.heroes[0].id and a.data.heroes[0].stats == b.data.heroes[0].stats and a.data.stages["1"].descriptor.seed == b.data.stages["1"].descriptor.seed
	same = same and a.hero_appearance(a.data.heroes[0]) == b.hero_appearance(b.data.heroes[0])
	a.free(); b.free()
	return [same, "HeroSeed, aspetto o stage seed differiscono"]

func _test_initial_world() -> Array:
	var game := _fresh("initial-seed")
	var valid: bool = game.data.heroes.size() == 6 and game.get_party().filter(func(hero): return not hero.is_empty()).size() == 5
	valid = valid and game.base_level() == 1 and not game.is_dev_unlimited()
	for id in ["training", "dormitory", "merging", "gate"]: valid = valid and game.facility_built(id) and game.facility_level(id) == 1
	for id in ["armory", "workshop", "warehouse", "alchemy"]: valid = valid and not game.facility_built(id) and not game.facility_available(id)
	game.free()
	return [valid, "Roster, party o strutture della Base Lv.1 non conformi"]

func _test_summon() -> Array:
	var game := _fresh("summon-seed")
	game.data.world.gold = 1000000
	game.data.world.gems = 50000
	var normal := game.summon("normal", 10)
	var high := game.summon("high", 10)
	var valid: bool = normal.ok and high.ok and game.data.world.gold == 900000 and game.data.world.gems == 45000
	for hero in normal.heroes: valid = valid and hero.native_rarity >= 1 and hero.native_rarity <= 3
	for hero in high.heroes: valid = valid and hero.native_rarity >= 3 and hero.native_rarity <= 5
	game.data.world.gems = 0
	valid = valid and not game.summon("high", 1).ok
	game.free()
	return [valid, "Costo o pool rarità non conforme"]

func _test_transcendent() -> Array:
	var game := _fresh("transcendent-seed")
	game.data.world.gems = 100000
	var locked: bool = not game.summon("transcendent", 1).ok
	game.debug_clear_floors(20)
	var result := game.summon("transcendent", 20)
	var valid: bool = locked and result.ok
	for hero in result.heroes: valid = valid and int(hero.native_rarity) >= 4 and int(hero.native_rarity) <= 7
	game.free()
	return [valid, "Pool trascendente non conforme"]

func _test_merge() -> Array:
	var game := _fresh("merge-seed")
	var merge_ids: Array[String] = []
	for index in range(3):
		var hero := game.generate_hero("merge-candidate-%d" % index, 1, "Ranger")
		game.data.heroes.append(hero)
		merge_ids.append(str(hero.id))
	game.assign_hero(merge_ids[1], "training")
	var before: int = game.data.heroes.size()
	var result: Dictionary = game.merge_heroes(merge_ids)
	var core: Dictionary = game.hero_by_id(merge_ids[0])
	var valid: bool = bool(result.ok) and game.data.heroes.size() == before - 2
	valid = valid and not core.is_empty() and int(core.current_rarity) == 2
	valid = valid and game.hero_by_id(merge_ids[1]).is_empty() and game.hero_by_id(merge_ids[2]).is_empty()
	valid = valid and not game.data.assignments.has(merge_ids[1])
	game.free()
	return [valid, "Nucleo, rarità o consumo dei donatori non conforme"]

func _test_merge_cap() -> Array:
	var game := _fresh("merge-cap-seed")
	var ids: Array[String] = []
	for index in range(3):
		var hero := game.generate_hero("merge-cap-%d" % index, 5, "Mage")
		game.data.heroes.append(hero)
		ids.append(str(hero.id))
	var valid: bool = not game.merge_heroes(ids).ok
	game.free()
	return [valid, "La fusione 5★ → 6★ non deve essere possibile"]

func _test_dev_unlimited() -> Array:
	var game := _fresh("dev-unlimited-seed")
	game.set_dev_mode(true)
	game.data.world.gold = 0
	game.data.world.gems = 0
	var normal := game.summon("normal", 10)
	var high := game.summon("high", 10)
	var valid: bool = normal.ok and high.ok and game.data.world.gold == 0 and game.data.world.gems == 0 and game.display_resource("gold") == "∞"
	game.set_dev_mode(false)
	valid = valid and game.display_resource("gold") == "0"
	game.free()
	return [valid, "Le risorse DEV sono state consumate o il display non è corretto"]

func _test_training() -> Array:
	var game := _fresh("training-seed")
	var hero: Dictionary = game.data.heroes[0]
	hero.fatigue = 0
	var assigned := game.assign_hero(hero.id, "training")
	game.advance_time(600.0)
	var leveled: bool = int(hero.level) > 1 and game.data.assignments.has(hero.id)
	hero.fatigue = 0
	game.advance_time(3600.0 * 8.0)
	var capped: bool = int(hero.level) <= game.level_cap(hero)
	var released: bool = not game.data.assignments.has(hero.id)
	var slots_ok: bool = game.training_slots() == 3
	game.free()
	return [assigned.ok and leveled and capped and released and slots_ok, "Allenamento, cap o rilascio non conformi"]

func _test_dormitory() -> Array:
	var game := _fresh("dorm-seed")
	var hero: Dictionary = game.data.heroes[1]
	hero.fatigue = 80
	hero.morale = 40
	hero.injuries.append({"name": "Ferita da combattimento", "severity": "Moderata", "minutes": 20.0})
	var refused_training: bool = not game.assign_hero(hero.id, "training").ok
	var ok: bool = game.assign_hero(hero.id, "dormitory").ok
	game.advance_time(60.0 * 40.0)
	var valid: bool = refused_training and ok and hero.injuries.is_empty() and float(hero.fatigue) < 80 and float(hero.morale) > 40
	valid = valid and game.dormitory_slots() == 5
	game.free()
	return [valid, "Riposo o guarigione non conformi"]

func _test_base_upgrade() -> Array:
	var game := _fresh("base-seed")
	game.data.world.gold = 500000
	game.debug_clear_floors(4)
	var blocked: bool = not game.upgrade_base().ok
	game.debug_clear_floors(5)
	var upgraded := game.upgrade_base()
	var plot: bool = game.facility_available("armory") and not game.facility_built("armory")
	var built := game.build_facility("armory")
	var valid: bool = blocked and upgraded.ok and game.base_level() == 2 and plot and built.ok and game.facility_level("armory") == 1
	game.free()
	return [valid, "Requisiti base, cantiere o costruzione non conformi"]

func _test_facility_cap() -> Array:
	var game := _fresh("cap-seed")
	game.data.world.gold = 1000000
	var blocked: bool = not game.upgrade_facility("training").ok
	game.data.world.base_level = 2
	var ok := game.upgrade_facility("training")
	var valid: bool = blocked and ok.ok and game.facility_level("training") == 2 and game.training_slots() == 4
	valid = valid and not game.upgrade_facility("training").ok
	game.free()
	return [valid, "Il livello struttura deve restare entro il livello base"]

func _test_base_islands() -> Array:
	var game := _fresh("islands-seed")
	var valid: bool = game.BASE_LEVELS.size() == 10 and game.FACILITY_MAX_LEVEL == 10 and game.base_islands().is_empty()
	# i livelli 6–10 chiedono piani sempre più alti e più oro
	for i in range(1, game.BASE_LEVELS.size()):
		valid = valid and int(game.BASE_LEVELS[i].floor) > int(game.BASE_LEVELS[i - 1].floor) and int(game.BASE_LEVELS[i].gold) > int(game.BASE_LEVELS[i - 1].gold)
	var slots_before := game.training_slots()
	var beds_before := game.dormitory_slots()
	var xp_before := int(game.floor_rewards(30, 1, true).xp)
	game.data.world.gold = 10000000
	game.debug_clear_floors(40)
	for k in 5: game.upgrade_base()
	valid = valid and game.base_level() == 6 and game.has_island("campi") and not game.has_island("dimore")
	valid = valid and game.training_slots() == slots_before + 2 and game.dormitory_slots() == beds_before
	valid = valid and str(game.next_island().get("id", "")) == ""
	# una struttura arriva al Lv.6 solo con la base al Lv.6, e mai oltre il 10
	for k in 5: valid = valid and game.upgrade_facility("training").ok
	valid = valid and game.facility_level("training") == 6 and not game.upgrade_facility("training").ok
	var cost_5 := int(game.FACILITIES.training.upgrade_cost) * pow(1.85, 4)
	game.data.world.base_level = 10
	valid = valid and game.has_island("dimore") and game.has_island("santuario") and game.dormitory_slots() == beds_before + 6
	valid = valid and int(game.floor_rewards(30, 1, true).xp) == roundi(xp_before * 1.1)
	valid = valid and int(game.facility_upgrade_cost("training").gold) == roundi(cost_5 * 1.4)
	for k in 4: valid = valid and game.upgrade_facility("training").ok
	valid = valid and game.facility_level("training") == 10 and not game.upgrade_facility("training").ok
	game.data.world.base_level = 7
	valid = valid and str(game.next_island().get("id", "")) == "dimore"
	game.free()
	return [valid, "Livelli della base, strutture fino al 10 o isole non conformi"]

func _test_stage_persistence() -> Array:
	var game := _fresh("stage-seed")
	var first: Dictionary = game.get_stage(1).descriptor
	var second: Dictionary = game.get_stage(1).descriptor
	var other := _fresh("stage-seed")
	var proc_a: Dictionary = game.get_stage(7).descriptor
	var proc_b: Dictionary = other.get_stage(7).descriptor
	var boss: Dictionary = game.get_stage(10).descriptor
	var valid: bool = first.seed == second.seed and first == second and proc_a == proc_b and str(boss.type) == "Boss" and not proc_a.waves.is_empty()
	game.free(); other.free()
	return [valid, "Il descriptor è stato rigenerato o i piani procedurali non sono deterministici"]

func _test_tower_tiers() -> Array:
	var game := _fresh("tower-seed")
	var p := func(f: int) -> float: return float(game.enemy_scaling(f).power)
	# dentro lo scaglione cresce poco, al nuovo scaglione salta
	var valid: bool = p.call(2) > p.call(1) and p.call(4) > p.call(3) and p.call(6) > p.call(4) * 1.15 and p.call(11) > p.call(9) and p.call(100) > p.call(50)
	# il 5° piano di ogni scaglione è la prova: guardiano, regole e campioni
	var trial_5: Dictionary = game.get_stage(5).descriptor
	var trial_40: Dictionary = game.get_stage(40).descriptor
	valid = valid and trial_5.type == "Boss" and trial_5.trial.rules.size() == 1 and int(trial_5.trial.elites) == 1
	valid = valid and trial_40.trial.rules.size() == 3 and trial_40.waves.any(func(w): return w.size() > 3 and w[3] == "elite")
	valid = valid and not game.get_stage(7).descriptor.has("trial") and int(trial_40.tier) == 8
	for id in trial_40.trial.rules: valid = valid and game.TOWER_TRIALS.has(id)
	# stesso seme, stessa prova; la minaccia della prova supera quella dei piani prima
	var other := _fresh("tower-seed")
	valid = valid and other.get_stage(40).descriptor.trial == trial_40.trial
	valid = valid and int(trial_40.threat_budget) > int(game.get_stage(39).descriptor.threat_budget)
	# ricompense della prova: gemme doppie al primo completamento e Pietre
	var normal := game.floor_rewards(9, 1, true)
	var trial := game.floor_rewards(10, 1, true)
	valid = valid and int(trial.gems) == (120 + 100) * 2 and trial.has("stones") and not normal.has("stones") and int(trial.gold) > int(normal.gold)
	# salvataggi vecchi: il 5° piano non superato diventa prova, quello superato no
	game.get_stage(15)
	game.get_stage(20)
	game.data.stages["15"].descriptor.erase("trial")
	game.data.stages["20"].descriptor.erase("trial")
	game.data.stages["20"].cleared = true
	game._migrate()
	valid = valid and game.data.stages["15"].descriptor.has("trial") and not game.data.stages["20"].descriptor.has("trial")
	game.free(); other.free()
	return [valid, "Scaglioni, prove o ricompense della Torre non conformi"]

func _test_legacy_migration() -> Array:
	var game := _fresh("legacy-seed")
	game.data.version = 2
	game.data.facilities = {"Summoning Hall": 1, "Training Center": 2, "Armory": 1, "Warehouse": 1, "Lodging": 1, "Smithy": 0, "Workshop": 0, "Synthesis Chamber": 0}
	game.data.dev = {"enabled": true, "unlimited_resources": true, "reveal_hidden": true}
	game.data.heroes[0].injuries = ["Ferita da combattimento"]
	game.data.erase("assignments")
	var descriptor: Dictionary = game.data.stages["1"].descriptor
	descriptor["threat"] = descriptor.threat_budget
	descriptor.erase("threat_budget")
	game._migrate()
	var valid: bool = int(game.data.version) == 3 and not game.is_dev_unlimited()
	valid = valid and game.facility_level("training") == 1 and game.facility_built("merging") and not game.facility_built("armory")
	valid = valid and game.data.heroes[0].injuries[0] is Dictionary and game.data.has("assignments")
	valid = valid and descriptor.has("threat_budget") and int(descriptor.threat_budget) == int(descriptor.threat)
	game.free()
	return [valid, "Migrazione v2 → v3 non conforme"]

func _test_permadeath() -> Array:
	var game := _fresh("death-seed")
	var start := game.begin_mission(1)
	if not start.ok:
		game.free()
		return [false, start.message]
	var victim: Dictionary = game.get_party()[0]
	game.record_death(victim.id, "Test controllato")
	var valid: bool = victim.state == "DEAD" and not game.data.party.has(victim.id) and game.data.memorial.size() == 1
	game.free()
	return [valid, "Tombstone o rimozione party mancante"]

func _test_clear() -> Array:
	var game := _fresh("clear-seed")
	game.assign_hero(game.data.party[0], "training")
	var start := game.begin_mission(1)
	if not start.ok:
		game.free()
		return [false, start.message]
	var pulled: bool = not game.data.assignments.has(game.data.party[0])
	var gold_before := int(game.data.world.gold)
	var results := []
	for hero in game.get_party(): results.append({"id": hero.id, "alive": true, "hp_ratio": 0.8, "kills": 1, "fatigue": 10})
	results[1].hp_ratio = 0.1
	var finish := game.finalize_mission({"victory": true, "reason": "test", "duration": 20.0, "hero_results": results})
	var valid: bool = finish.ok and pulled and game.data.world.max_floor == 2 and game.data.stages["1"].cleared and game.data.stages.has("2")
	valid = valid and int(game.data.world.gold) > gold_before and int(game.get_party()[0].level) > 1
	valid = valid and not game.get_party()[1].injuries.is_empty() and finish.first_clear
	game.free()
	return [valid, "Progressione, ricompense, XP o ferite non aggiornate"]

func _test_promotion_gate() -> Array:
	var game := _fresh("promotion-seed")
	var hero := game.generate_hero("promo-hero", 5, "Guardian")
	game.data.heroes.append(hero)
	hero.level = 70
	game.data.world.stones = 99
	var blocked: bool = not game.promote_hero(hero.id).ok
	game.debug_clear_floors(30)
	var ok := game.promote_hero(hero.id)
	var valid: bool = blocked and ok.ok and int(hero.current_rarity) == 6 and int(game.data.world.stones) == 99 - 12
	# la 7ª stella non si ottiene con la promozione; il livello massimo è 99
	hero.level = game.level_cap(hero)
	game.debug_clear_floors(60)
	valid = valid and not game.promote_hero(hero.id).ok and int(hero.current_rarity) == 6
	valid = valid and game.RARITY_CAPS[7] == 99 and game.RARITY_CAPS[6] == 99
	game.free()
	return [valid, "Promozione 6★ non conforme"]

func _test_armory() -> Array:
	var game := _fresh("armory-seed")
	game.data.world.gold = 500000
	var blocked: bool = not game.forge_item("weapon").ok
	# l'Armeria si apre dopo il Piano 3, anche con la base al Lv.1
	blocked = blocked and not game.facility_available("armory")
	game.debug_clear_floors(3)
	blocked = blocked and game.base_level() == 1 and game.facility_available("armory")
	game.build_facility("armory")
	var forged := game.forge_item("weapon")
	var hero: Dictionary = game.data.heroes[0]
	var before := float(game.derived_stats(hero).attack)
	var equipped := game.equip_item(hero.id, str(forged.item.id))
	var valid: bool = blocked and forged.ok and equipped.ok and game.data.inventory.is_empty() and float(game.derived_stats(hero).attack) != before
	game.free()
	return [valid, "Forgia o equipaggiamento non conformi"]

func _test_forge_minigame_rules() -> Array:
	var game := _fresh("forge-seed")
	game.data.world.gold = 2000000
	game.data.world.base_level = 5
	game.debug_clear_floors(3)
	game.build_facility("armory")
	var materials_ok := true
	for key in ["ore", "wood", "leather", "cores"]: game.grant(key, 200, "test", "test")
	# Precisione → grado, con il tetto della difficoltà
	var ladder: bool = game.forge_grade_index(0.0, "master") == 0 and game.forge_grade_index(0.3, "master") == 1 and game.forge_grade_index(0.95, "master") == 6
	var capped: bool = game.forge_grade_index(1.0, "easy") == 3 and game.forge_grade_index(1.0, "normal") == 4 and game.forge_grade_index(1.0, "hard") == 5
	# Difficile e Maestro bloccati all'Armeria Lv.1
	var locked: bool = not game.begin_forge("weapon", "hard").ok and not game.begin_forge("weapon", "master").ok
	# Un lavoro alla volta; i materiali si pagano all'inizio
	var gold_before := game.resource_amount("gold")
	var started := game.begin_forge("weapon", "normal")
	var paid: bool = game.resource_amount("gold") < gold_before and not game.forge_pending().is_empty()
	var second_blocked: bool = not game.begin_forge("armor", "normal").ok
	var bad := game.finish_forge(0.0)
	var no_pending: bool = game.forge_pending().is_empty() and not game.finish_forge(0.5).ok
	# Armeria Lv.5: Maestro sbloccato, S con precisione alta e più forte del grado F
	game.data.facilities.armory.level = 5
	var great := game.forge_item("weapon", "master", 0.97)
	var valid: bool = materials_ok and ladder and capped and locked and started.ok and paid and second_blocked
	# sotto il 25% di precisione il pezzo si rompe: niente oggetto, materiali persi
	valid = valid and bad.ok and bool(bad.get("failed", false)) and not bad.has("item") and no_pending
	var poor := game.forge_item("weapon", "normal", 0.3)
	valid = valid and poor.ok and str(poor.item.grade) == "E"
	valid = valid and great.ok and str(great.item.grade) == "S" and int(great.item.power) > int(poor.item.power) * 3
	valid = valid and game.forge_window_bonus() > 1.0
	game.free()
	return [valid, "Forgia a mano non conforme"]

func _test_emergency() -> Array:
	var game := _fresh("emergency-seed")
	var hidden: bool = not game.emergency_recruit_status().visible
	for hero in game.data.heroes.slice(0, 3): game.record_death(hero.id, "test")
	var first := game.emergency_recruit()
	var second := game.emergency_recruit()
	var valid: bool = hidden and first.ok and not second.ok and int(first.hero.native_rarity) == 1 and game.get_alive_heroes().size() == 4
	game.free()
	return [valid, "Richiamo d'emergenza non conforme"]

func _reload(game: RiftwardState) -> void:
	game.data = JSON.parse_string(JSON.stringify(game.data))
	game._migrate()

func _test_json_reload() -> Array:
	var game := _fresh("reload-seed")
	var start := game.begin_mission(1)
	var results := []
	for hero in game.get_party(): results.append({"id": hero.id, "alive": true, "hp_ratio": 0.9, "kills": 0, "fatigue": 5})
	game.finalize_mission({"victory": true, "reason": "test", "duration": 10.0, "hero_results": results})
	_reload(game)
	var before := game.cleared_floor_count()
	game.begin_mission(1)
	game.finalize_mission({"victory": true, "reason": "test", "duration": 10.0, "hero_results": results})
	_reload(game)
	var valid: bool = before == 1 and game.cleared_floor_count() == 1 and game.data.world.completed == [1]
	valid = valid and typeof(game.data.summon_counter) == TYPE_INT and typeof(game.data.heroes[0].level) == TYPE_INT
	game.free()
	return [valid, "Ricaricare il salvataggio altera i piani completati o i tipi"]

func _test_dev_leak() -> Array:
	var game := _fresh("dev-leak-seed")
	game.data.version = 2
	game.data.dev = {"enabled": true, "unlimited_resources": true, "reveal_hidden": true, "all_content": true}
	game._migrate()
	var migrated_ok: bool = not game.dev_override() and not game.summon_pool_unlocked("transcendent")
	game.set_dev_mode(true)
	game.dev_unlock_all()
	var unlocked: bool = game.summon_pool_unlocked("transcendent")
	game.set_dev_mode(false)
	var relocked: bool = not game.summon_pool_unlocked("transcendent")
	game.free()
	return [migrated_ok and unlocked and relocked, "Gli sblocchi di sviluppo restano attivi"]

func _test_offline_steps() -> Array:
	var game := _fresh("offline-seed")
	var hero: Dictionary = game.data.heroes[0]
	hero.fatigue = 0
	game.assign_hero(hero.id, "training")
	game.data.world.last_saved = Time.get_unix_time_from_system() - 8 * 3600
	game._apply_offline_progress()
	var valid: bool = not game.data.assignments.has(hero.id) and float(hero.fatigue) >= 89.0 and int(hero.level) < 10
	game.free()
	return [valid, "L'addestramento offline ha ignorato la stanchezza (Lv.%d)" % int(hero.level)]

func _test_abandoned_mission() -> Array:
	var game := _fresh("abandon-seed")
	var morale_before := int(game.get_party()[0].morale)
	game.begin_mission(1)
	_reload(game)
	var valid: bool = game.data.active_mission.is_empty() and int(game.data.stages["1"].attempts) == 1 and int(game.get_party()[0].morale) < morale_before and not bool(game.data.stages["1"].cleared)
	game.free()
	return [valid, "La missione abbandonata non è stata chiusa come sconfitta"]

func _test_item_ids() -> Array:
	var game := _fresh("item-seed")
	game.data.inventory = [{"name": "Lama del Rift", "slot": "main", "grade": "C", "power": 22}]
	game._migrate()
	var item: Dictionary = game.data.inventory[0]
	var valid: bool = str(item.get("id", "")) != "" and not game.equip_item(game.data.heroes[0].id, "").ok
	valid = valid and game.equip_item(game.data.heroes[0].id, str(item.id)).ok
	game.free()
	return [valid, "Gli oggetti senza id non sono stati sistemati"]

func _test_light_setting() -> Array:
	var game := _fresh("light-seed")
	var valid: bool = game.light_preset() == "dusk"
	game.set_light("night")
	valid = valid and game.light_preset() == "night"
	game.set_light("sunset-of-doom")
	valid = valid and game.light_preset() == "night"
	game.data.erase("settings")
	game._migrate()
	valid = valid and game.light_preset() == "dusk"
	game.free()
	return [valid, "Impostazione della luce non coerente"]

func _test_traits_skills() -> Array:
	var game := _fresh("traits-seed")
	var valid := true
	for i in 40:
		var hero := game.generate_hero("trait-%d" % i, 1 + i % 5)
		if hero.traits[0] == hero.traits[1]: valid = false
		if RiftwardState.skill_label(str(hero.skills[1].name)) != "Disciplina da Campo": valid = false
	valid = valid and RiftwardState.skill_label("Mend") == "Cura"
	game.free()
	return [valid, "Tratti duplicati o abilità non tradotte"]

func _test_dev_tools() -> Array:
	var game := _fresh("dev-tools-seed")
	game.set_dev_mode(true)
	game.dev_unlock_all()
	var valid: bool = int(game.data.world.max_floor) == game.MAX_FLOOR and game.get_stage(game.MAX_FLOOR).has("descriptor")
	game.dev_clear_all_floors()
	valid = valid and game.cleared_floor_count() == game.MAX_FLOOR and game.summon_pool_unlocked("transcendent")
	game.dev_max_base()
	valid = valid and game.base_level() == game.BASE_LEVELS.size()
	for id in game.FACILITY_ORDER: valid = valid and game.facility_level(id) == game.FACILITY_MAX_LEVEL
	var top := game.dev_spawn_hero(7)
	game.dev_max_heroes()
	valid = valid and int(top.current_rarity) == 7 and int(top.level) == game.level_cap(top)
	game.free()
	return [valid, "Gli strumenti di sviluppo non sbloccano tutto"]

func _test_shop() -> Array:
	var game := _fresh("shop-seed")
	var gold := game.resource_amount("gold")
	var ore := game.resource_amount("ore")
	var bought: bool = game.shop_buy("mat_ore").ok
	var valid: bool = bought and game.resource_amount("gold") == gold - 700 and game.resource_amount("ore") == ore + 5
	valid = valid and game.shop_remaining("mat_ore") == 4
	game.shop_buy("daily_supplies")
	valid = valid and not game.shop_buy("daily_supplies").ok
	# un nuovo giorno azzera i limiti
	game.data.shop.day = game.shop_day() - 1
	valid = valid and game.shop_remaining("daily_supplies") == 1
	# niente acquisti senza fondi
	game.data.world.gems = 10
	valid = valid and not game.shop_buy("gem_stone").ok and int(game.data.world.stones) == 1
	# scorte piene: l'acquisto viene rifiutato senza pagare
	game.data.world.materials.wood = game.material_cap()
	var before := game.resource_amount("gold")
	valid = valid and not game.shop_buy("mat_wood").ok and game.resource_amount("gold") == before
	game.free()
	return [valid, "Il negozio non rispetta prezzi o limiti"]

func _test_character_pack() -> Array:
	var game := _fresh("character-pack-seed")
	var hero: Dictionary = game.data.heroes[0]
	var generator := load("res://scripts/characters/character_generator.gd")
	var valid: bool = hero.has("appearance") and generator.CATEGORIES.has(hero.category)
	var look := RiftwardState.appearance_for(hero)
	valid = valid and look.eyes == Color(str(hero.appearance.eye_hex))
	# capelli dal generatore (ingrigiti solo con l'età)
	if int(look.age) < 46: valid = valid and look.hair == Color(str(hero.appearance.hair_hex)) and look.hair_color == str(hero.appearance.hair_color)
	# salvataggio vecchio senza aspetto: la migrazione lo aggiunge senza toccare il resto
	var level := int(hero.level)
	var expected: Dictionary = hero.appearance.duplicate()
	hero.erase("appearance")
	hero.erase("category")
	game._migrate()
	valid = valid and hero.appearance == expected and int(hero.level) == level
	# stesso id, stesso aspetto
	valid = valid and generator.generate("abc:appearance") == generator.generate("abc:appearance")
	game.free()
	return [valid, "Aspetto del generatore assente, diverso o perso nella migrazione"]

func _test_commoners() -> Array:
	var game := _fresh("commoner-seed")
	var valid := true
	var look_script := load("res://scripts/characters/hero_look.gd")
	# evocati a 1★-2★: persone comuni con un mestiere, senza classe, che ne consigliano una
	for i in 24:
		var hero := game.generate_hero("commoner-%d" % i, 1 + i % 2)
		var job := str(hero.get("job", ""))
		valid = valid and bool(hero.commoner) and not bool(hero.class_chosen) and game.COMMONER_JOBS.has(job)
		valid = valid and game.ROLES.has(str(hero.recommended_role)) and str(hero.role) == str(hero.recommended_role)
		valid = valid and str(hero.alt_role) != str(hero.recommended_role) and str(hero.advice).contains(game.role_label(str(hero.alt_role)))
		valid = valid and str(hero.equipment.main.name) == str(game.COMMONER_JOBS[job].tool)
		valid = valid and str(hero.look.archetype) == str(game.COMMONER_JOBS[job].look)
		valid = valid and RiftwardState.outfit_kind(hero) == str(game.COMMONER_JOBS[job].look)
	# il consiglio segue le statistiche: un archivista consiglia una classe di intelletto
	var scholar := {"str": 9, "int": 34, "sta": 14, "agi": 12}
	valid = valid and str(game.class_advice(scholar, "Archivista").role) in ["Mage", "Support"]
	var smith := {"str": 30, "int": 9, "sta": 24, "agi": 12}
	valid = valid and str(game.class_advice(smith, "Fabbro").role) in ["Vanguard", "Guardian", "Lancer"]
	# il giocatore sceglie: anche una classe diversa da quella consigliata
	var hero := game.generate_hero("commoner-choice", 1)
	game.data.heroes.append(hero)
	valid = valid and game.needs_class(hero) and game.hero_class_label(hero).begins_with("Popolano")
	var pick := str(hero.alt_role)
	var result: Dictionary = game.choose_class(str(hero.id), pick)
	valid = valid and bool(result.ok) and str(hero.role) == pick and bool(hero.class_chosen) and not game.needs_class(hero)
	valid = valid and str(hero.skills[0].name) == str(game.ROLES[pick].skill)
	valid = valid and str(hero.equipment.main.name) == str(game._starter_equipment(pick).main.name)
	valid = valid and str(hero.equipment.armor.name) != "Abiti da lavoro"
	valid = valid and RiftwardState.outfit_kind(hero) == str(look_script.CLASS_OUTFIT[pick])
	valid = valid and not bool(game.choose_class(str(hero.id), "Mage").ok)
	# dal 3★ in su: classe dal Nexus, nessuna scelta
	var rare := game.generate_hero("rare-hero", 3)
	valid = valid and not bool(rare.commoner) and bool(rare.class_chosen) and not game.needs_class(rare)
	# squadra iniziale: popolani che hanno già la loro classe
	for starter in game.data.heroes.slice(0, 5):
		valid = valid and not game.needs_class(starter)
	# salvataggio vecchio: i 1★-2★ diventano popolani con la classe che avevano
	var legacy: Dictionary = game.data.heroes[0]
	var role := str(legacy.role)
	for key in ["commoner", "class_chosen", "job", "recommended_role", "alt_role", "advice"]: legacy.erase(key)
	game._migrate()
	valid = valid and bool(legacy.commoner) and bool(legacy.class_chosen) and str(legacy.role) == role and game.COMMONER_JOBS.has(str(legacy.job))
	game.free()
	return [valid, "Popolani senza mestiere, consiglio sbagliato o scelta della classe non applicata"]

func _test_character_kit() -> Array:
	var kit := load("res://scripts/characters/character_kit.gd")
	var look_script := load("res://scripts/characters/hero_look.gd")
	var valid := true
	var missing := []
	for outfit in ["villager", "guard", "merchant", "scholar", "hunter"]:
		var inst: Node = kit.body_instance(outfit)
		if inst == null:
			missing.append("body_" + outfit)
			continue
		var skels := inst.find_children("*", "Skeleton3D", true, false)
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		valid = valid and skels.size() == 1 and meshes.size() == 1
		if skels.size() == 1:
			var sk := skels[0] as Skeleton3D
			for joint in CharacterModel.JOINT_NAMES: valid = valid and sk.find_bone(joint) >= 0
		if meshes.size() == 1:
			var mi := meshes[0] as MeshInstance3D
			for key in ["fem", "slim", "athletic", "muscular", "chubby"]: valid = valid and mi.find_blend_shape_by_name(key) >= 0
		inst.free()
	var pieces := ["head", "glasses", "headband", "beard_short", "beard_goatee"]
	for arch in look_script.ARCHETYPES.values():
		for h in arch.hair_m + arch.hair_f:
			if not pieces.has("hair_" + str(h)): pieces.append("hair_" + str(h))
	for piece in pieces:
		if kit.part(piece) == null: missing.append(piece)
	# un eroe costruito dal kit ha lo scheletro e la testa con il volto
	var game := _fresh("kit-seed")
	var hero: Dictionary = game.data.heroes[0]
	var model := CharacterModel.new()
	var look: Dictionary = RiftwardState.appearance_for(hero)
	look["outfit_kind"] = "villager" # la Guardia maschio usa il modello 3D dell'utente, non il kit
	model.build_hero(hero, look)
	valid = valid and model._skel != null and model._face_mat != null and model._head_kit != null and model._head_kit.get_child_count() >= 2
	model.free()
	# modello 3D dell'utente (Guardia): scheletro del kit corretto dalla posa a T, arma in mano
	if kit.has_user_body("guard"):
		look["outfit_kind"] = "guard"
		look["fem"] = false
		var guard := CharacterModel.new()
		guard.build_hero(hero, look)
		valid = valid and guard._skel != null and guard._bone_fix.size() == CharacterModel.JOINT_NAMES.size()
		valid = valid and not guard._bone_ids.has(-1) and guard._skel.find_children("Hold_*", "", true, false).size() >= 1
		# Avanguardia e Lanciere col Guerriero del foglio "turntable", se c'è
		if kit.has_user_body("warrior"):
			valid = valid and CharacterModel._user_model("guard", "Vanguard") == "warrior" and CharacterModel._user_model("guard", "Guardian") == "guard"
		# con i capelli dell'eroe sulla testa calva del modello
		valid = valid and (str(look.get("hair_kind", "short")) == "none" or guard._skel.find_children("UserHair", "", true, false).size() == 1)
		guard.free()
	game.free()
	valid = valid and missing.is_empty()
	return [valid, "pezzi mancanti: %s" % [missing] if not missing.is_empty() else "5 vestiti, %d pezzi della testa" % pieces.size()]

func _test_modular_look() -> Array:
	var game := _fresh("modular-look-seed")
	var look_script := load("res://scripts/characters/hero_look.gd")
	var valid := true
	var face_sum := {1: 0, 6: 0}
	for i in 120:
		for rarity in [1, 6]:
			var hero := game.generate_hero("look-%d-%d" % [rarity, i], rarity)
			var piece: Dictionary = hero.look
			var arch: Dictionary = look_script.ARCHETYPES[piece.archetype]
			var hairs: Array = arch.hair_f if RiftwardState.is_feminine(hero) else arch.hair_m
			valid = valid and int(piece.face) >= 0 and int(piece.face) <= 2 and hairs.has(str(piece.hair))
			valid = valid and (arch.bodies as Array).has(str(piece.body)) and int(piece.age) >= 16 and int(piece.age) <= 62
			face_sum[rarity] += int(piece.face)
			if rarity == 6: valid = valid and str(piece.archetype) == str(look_script.CLASS_ARCHETYPE[str(hero.role)])
	# più rara, più spesso il volto bello (indice 0)
	valid = valid and face_sum[6] < face_sum[1]
	# stesso eroe, stesso aspetto; la migrazione lo ricrea uguale
	var first: Dictionary = game.data.heroes[0]
	var before: Dictionary = first.look.duplicate()
	first.erase("look")
	game._migrate()
	valid = valid and first.look == before
	var look := RiftwardState.appearance_for(first)
	valid = valid and look.eyes == Color(str(first.appearance.eye_hex)) and str(look.hair_kind) == str(before.hair)
	game.free()
	return [valid, "Pezzi dell'aspetto fuori dal foglio o non deterministici"]

func _test_motion_pack() -> Array:
	var motion := load("res://scripts/hub3d/motion_library.gd")
	var valid: bool = motion.ensure() and motion.clip_names().size() == 40
	for clip in ["Idle", "Walk_F", "Interact", "Cheer", "Death", "Bow_Shot", "Cast_Spell"]:
		var pose: Dictionary = motion.sample(clip, 0.4)
		valid = valid and pose.size() == motion.JOINTS.size() + 1
	return [valid, "Clip mancanti o scheletro non compatibile"]

func _test_fatigue_penalties() -> Array:
	var game := _fresh("fatigue-seed")
	var hero: Dictionary = game.get_party()[0]
	hero.fatigue = 0
	var fresh: Dictionary = game.derived_stats(hero)
	var fresh_power := game.hero_power(hero)
	hero.fatigue = 45
	var tired: Dictionary = game.derived_stats(hero)
	hero.fatigue = 75
	var exhausted: Dictionary = game.derived_stats(hero)
	var exhausted_power := game.hero_power(hero)
	var worse: bool = float(tired.attack) < float(fresh.attack) and float(exhausted.attack) < float(tired.attack)
	worse = worse and int(exhausted.max_hp) < int(fresh.max_hp) and float(exhausted.accuracy) < float(fresh.accuracy) and exhausted_power < fresh_power
	worse = worse and float(exhausted.speed_mult) < 1.0 and float(exhausted.cadence_mult) > 1.0
	hero.fatigue = 95
	var blocked: bool = not game.begin_mission(1).ok and not game.party_readiness().ready
	hero.fatigue = 0
	game.free()
	return [worse and blocked, "La stanchezza non penalizza o uno sfinito può partire"]

func _test_floor_gems() -> Array:
	var game := _fresh("gems-seed")
	var ok := true
	for floor_index in [1, 2, 3, 4, 6, 7]:
		ok = ok and int(game.floor_rewards(floor_index, 1, true).get("gems", 0)) > 0
		ok = ok and int(game.floor_rewards(floor_index, 5, false).get("gems", 0)) > 0
	ok = ok and int(game.floor_rewards(5, 1, true).gems) > int(game.floor_rewards(4, 1, true).gems)
	ok = ok and int(game.floor_rewards(3, 1, true).gems) > int(game.floor_rewards(3, 2, false).gems)
	game.free()
	return [ok, "Qualche piano non dà gemme"]

func _test_system_advisor() -> Array:
	var game := _fresh("advisor-seed")
	var before := JSON.stringify(game.data)
	var list: Array = SystemAdvisor.advice(game)
	# leggere i consigli non cambia il gioco
	var valid: bool = JSON.stringify(game.data) == before
	for item in list:
		valid = valid and item.has("id") and item.has("title") and not str(item.text).is_empty()
	# uno sfinito in squadra blocca la partenza: è il consiglio più urgente
	var first := game.hero_by_id(str(game.data.party[0]))
	first.fatigue = 95
	list = SystemAdvisor.advice(game)
	valid = valid and not list.is_empty() and str(list[0].id) == "party_spent"
	# la formazione consigliata lascia fuori lo sfinito
	var best: Dictionary = SystemAdvisor.recommended_party(game)
	valid = valid and not best.ids.has(str(first.id))
	SystemAdvisor.apply_recommended_party(game)
	valid = valid and not game.data.party.has(str(first.id))
	valid = valid and not str(SystemAdvisor.tip().text).is_empty()
	return [valid, "consigli %d, primo %s" % [list.size(), str(list[0].id) if not list.is_empty() else "-"]]
