extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Avvia questa suite con: -- --test-mode")
		quit(2)
		return
	print("Riftward Godot test suite")
	_test("generazione eroi deterministica", _test_deterministic_heroes)
	_test("world iniziale e party da cinque", _test_initial_world)
	_test("summon e costi", _test_summon)
	_test("fusione di tre eroi", _test_merge)
	_test("modalità sviluppo a risorse infinite", _test_dev_unlimited)
	_test("shop €0,00 e limite per world", _test_shop)
	_test("descriptor persistente", _test_stage_persistence)
	_test("compatibilità piani dei salvataggi precedenti", _test_legacy_stage_compatibility)
	_test("permadeath e tombstone", _test_permadeath)
	_test("clear e sblocco piano", _test_clear)
	print("\nRisultato: %d passati, %d falliti" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _fresh(seed_text: String) -> RiftwardState:
	var game := RiftwardState.new()
	game.new_world(seed_text)
	return game

func _test(name: String, callable: Callable) -> void:
	var ok := false
	var message := ""
	var result: Variant = callable.call()
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
	a.free()
	b.free()
	return [same, "HeroSeed o stage seed differiscono"]

func _test_initial_world() -> Array:
	var game := _fresh("initial-seed")
	var valid: bool = game.data.heroes.size() == 6 and game.get_party().filter(func(hero): return not hero.is_empty()).size() == 5
	game.free()
	return [valid, "Roster/party iniziale non valido"]

func _test_summon() -> Array:
	var game := _fresh("summon-seed")
	game.data.dev.unlimited_resources = false
	game.data.world.gold = 1000000
	game.data.world.gems = 50000
	var normal := game.summon("normal", 10)
	var high := game.summon("high", 10)
	var valid: bool = normal.ok and high.ok and game.data.world.gold == 900000 and game.data.world.gems == 45000
	for hero in normal.heroes: valid = valid and hero.native_rarity >= 1 and hero.native_rarity <= 3
	for hero in high.heroes: valid = valid and hero.native_rarity >= 3 and hero.native_rarity <= 5
	game.free()
	return [valid, "Costo o pool rarità non conforme"]

func _test_merge() -> Array:
	var game := _fresh("merge-seed")
	var merge_ids: Array[String] = []
	for index in range(3):
		var hero := game.generate_hero("merge-candidate-%d" % index, 1, "Ranger")
		game.data.heroes.append(hero)
		merge_ids.append(str(hero.id))
	var before: int = game.data.heroes.size()
	var result: Dictionary = game.merge_heroes(merge_ids)
	var core: Dictionary = game.hero_by_id(merge_ids[0])
	var valid: bool = bool(result.ok) and game.data.heroes.size() == before - 2
	valid = valid and not core.is_empty() and int(core.current_rarity) == 2
	valid = valid and game.hero_by_id(merge_ids[1]).is_empty() and game.hero_by_id(merge_ids[2]).is_empty()
	game.free()
	return [valid, "Nucleo, rarità o consumo dei due donatori non conforme"]

func _test_dev_unlimited() -> Array:
	var game := _fresh("dev-unlimited-seed")
	game.data.world.gold = 0
	game.data.world.gems = 0
	var normal := game.summon("normal", 10)
	var high := game.summon("high", 10)
	var valid: bool = normal.ok and high.ok and game.data.world.gold == 0 and game.data.world.gems == 0 and game.display_resource("gold") == "∞"
	game.free()
	return [valid, "Le risorse DEV sono state consumate o il display non è infinito"]

func _test_shop() -> Array:
	var game := _fresh("shop-seed")
	var before: int = game.data.world.gold
	var first := game.claim_shop_product("founder_cache")
	var second := game.claim_shop_product("founder_cache")
	var valid: bool = first.ok and not second.ok and game.data.world.gold == before + 50000 and game.data.shop_history.size() == 1 and game.data.shop_history[0].price == "€0,00"
	game.free()
	return [valid, "Riscatto, prezzo o limite Shop errato"]

func _test_stage_persistence() -> Array:
	var game := _fresh("stage-seed")
	var first: Dictionary = game.get_stage(1).descriptor
	var second: Dictionary = game.get_stage(1).descriptor
	var valid: bool = first.seed == second.seed and first == second
	game.free()
	return [valid, "Il descriptor è stato rigenerato"]

func _test_legacy_stage_compatibility() -> Array:
	var game := _fresh("legacy-stage-seed")
	var descriptor: Dictionary = game.data.stages["1"].descriptor
	descriptor["threat"] = descriptor.threat_budget
	descriptor.erase("threat_budget")
	game._migrate()
	var valid: bool = descriptor.has("threat_budget") and int(descriptor.threat_budget) == int(descriptor.threat)
	game.free()
	return [valid, "Il vecchio campo threat non è stato convertito"]

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
	var start := game.begin_mission(1)
	if not start.ok:
		game.free()
		return [false, start.message]
	var results := []
	for hero in game.get_party(): results.append({"id": hero.id, "alive": true, "hp_ratio": 0.8, "kills": 1, "fatigue": 10})
	var finish := game.finalize_mission({"victory": true, "reason": "test", "duration": 20.0, "hero_results": results})
	var valid: bool = finish.ok and game.data.world.max_floor == 2 and game.data.stages["1"].cleared and game.data.stages.has("2")
	game.free()
	return [valid, "Progressione della torre non aggiornata"]
