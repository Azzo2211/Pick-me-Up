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
	_test("livello strutture limitato dal livello base", _test_facility_cap)
	_test("descriptor persistente e piani procedurali", _test_stage_persistence)
	_test("migrazione salvataggi v2", _test_legacy_migration)
	_test("permadeath e tombstone", _test_permadeath)
	_test("clear, sblocco piano ed esperienza", _test_clear)
	_test("promozioni 6★ riservate all'endgame", _test_promotion_gate)
	_test("armeria: forgia ed equipaggiamento", _test_armory)
	_test("richiamo d'emergenza contro il blocco", _test_emergency)
	_test("ricarica JSON: niente piani completati falsi", _test_json_reload)
	_test("sblocchi di sviluppo non sopravvivono", _test_dev_leak)
	_test("addestramento offline rispetta la stanchezza", _test_offline_steps)
	_test("chiudere in missione conta come sconfitta", _test_abandoned_mission)
	_test("oggetti vecchi senza id ricevono un id", _test_item_ids)
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
	var blocked: bool = not game.upgrade_base().ok
	game.debug_clear_floors(3)
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
	game.free()
	return [valid, "Promozione 6★ non conforme"]

func _test_armory() -> Array:
	var game := _fresh("armory-seed")
	game.data.world.gold = 500000
	var blocked: bool = not game.forge_item("weapon").ok
	game.data.world.base_level = 2
	game.build_facility("armory")
	var forged := game.forge_item("weapon")
	var hero: Dictionary = game.data.heroes[0]
	var before := float(game.derived_stats(hero).attack)
	var equipped := game.equip_item(hero.id, str(forged.item.id))
	var valid: bool = blocked and forged.ok and equipped.ok and game.data.inventory.is_empty() and float(game.derived_stats(hero).attack) != before
	game.free()
	return [valid, "Forgia o equipaggiamento non conformi"]

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
