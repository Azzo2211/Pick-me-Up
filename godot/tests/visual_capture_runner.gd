extends SceneTree

## Cattura schermate reali del gioco (serve un display, es. xvfb-run):
## godot --path godot -s res://tests/visual_capture_runner.gd -- --test-mode

var main: Control
var state: RiftwardState

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Avvia questa suite con: -- --test-mode")
		quit(2)
		return
	state = root.get_node("GameState")
	state.new_world("visual-reference-seed")
	state.data.tutorial_seen = true
	state.assign_hero(state.data.heroes[0].id, "training")
	state.assign_hero(state.data.heroes[3].id, "training")
	state.data.heroes[2].fatigue = 72
	state.assign_hero(state.data.heroes[2].id, "dormitory")
	state.advance_time(240.0)
	var main_scene: PackedScene = load("res://Main.tscn")
	main = main_scene.instantiate()
	root.add_child(main)
	await _wait(3.0)
	_capture("res://tests/captures/capture_hub.png")
	for id in ["training", "dormitory", "merging", "gate", "crystal"]:
		main.open_panel(id)
		await _wait(1.0)
		_capture("res://tests/captures/capture_panel_%s.png" % id)
	main.panels.gate_tab = "squad"
	main.open_panel("gate")
	await _wait(0.8)
	_capture("res://tests/captures/capture_panel_squad.png")
	main.panels.gate_tab = "mission"
	main.close_panel()
	main.open_panel("roster")
	await _wait(0.8)
	_capture("res://tests/captures/capture_panel_roster.png")
	main.close_panel()
	main.open_roster()
	await _wait(0.8)
	_capture("res://tests/captures/capture_roster_screen.png")
	main.close_all_modals()
	main.open_hero(state.data.heroes[4].id)
	await _wait(0.8)
	_capture("res://tests/captures/capture_dossier.png")
	main.close_all_modals()
	await _wait(0.3)
	state.data.world.gems = 5000
	main.open_panel("crystal")
	await _wait(0.6)
	main.panels._summon("high", 10)
	await _wait(1.2)
	_capture("res://tests/captures/capture_summon_charge.png")
	await _wait(5.5)
	_capture("res://tests/captures/capture_summon.png")
	main.close_all_modals()
	await _wait(0.3)
	# Carte 1★–7★ affiancate: le cornici crescono con la rarità
	var gallery := HBoxContainer.new()
	gallery.add_theme_constant_override("separation", 18)
	for r in range(1, 8):
		var sample: Dictionary = state.data.heroes[r % state.data.heroes.size()].duplicate(true)
		sample["current_rarity"] = r
		sample["id"] = "sample_%d" % r
		var card: HeroCard = preload("res://scripts/ui/hero_card.gd").new()
		card.setup(sample, 200.0)
		gallery.add_child(card)
	main.open_modal("Rarità 1★–7★", "Cornici del Sistema", gallery, 1640, [], Callable(), "system")
	await _wait(1.0)
	_capture("res://tests/captures/capture_rarity.png")
	main.close_all_modals()
	main.close_panel()
	# Negozio
	main.open_shop()
	await _wait(0.8)
	_capture("res://tests/captures/capture_shop.png")
	main.close_all_modals()
	# Mappa della Torre (piani 1–10 con alcuni completati)
	state.debug_clear_floors(3)
	main.open_panel("gate")
	await _wait(0.4)
	main.panels.open_tower_map()
	await _wait(1.0)
	_capture("res://tests/captures/capture_tower_map.png")
	main.close_all_modals()
	main.close_panel()
	# Caricamento
	var loading: Control = load("res://scripts/ui/loading_screen.gd").new()
	loading.setup("PIANO 6", "APERTURA DEL VARCO…", "CUSTODE DELLE RADICI · CUORE DEL BOSCO")
	loading.progress = 0.62
	main.add_child(loading)
	await _wait(1.4)
	_capture("res://tests/captures/capture_loading.png")
	loading.queue_free()
	# Stage Clear e Eroe perduto (dati di esempio)
	var party := state.get_party()
	var hero_results := []
	for hero in party: hero_results.append({"id": hero.id, "alive": true, "hp_ratio": 0.8, "kills": 2})
	var clear: Control = load("res://scripts/ui/mission_result_screen.gd").new()
	clear.setup({"victory": true, "floor": 5, "reason": "boss", "hero_results": hero_results}, {"rewards": {"gold": 4200, "xp": 840, "gems": 120, "stones": 1}, "drops": {"ore": 3, "wood": 2, "herbs": 1}, "level_ups": [{"name": party[0].name, "from": 4, "to": 5}], "deaths": [], "first_clear": true})
	main.modal_layer.add_child(clear)
	await _wait(1.8)
	_capture("res://tests/captures/capture_stage_clear.png")
	clear.queue_free()
	var fallen: Dictionary = party[1]
	hero_results[1].alive = false
	var tombstone := {"id": fallen.id, "name": fallen.name, "level": fallen.level, "role": fallen.role, "rarity": fallen.current_rarity, "floor": 5, "cause": "Ucciso da Custode delle radici", "timestamp": 0}
	var lost: Control = load("res://scripts/ui/mission_result_screen.gd").new()
	lost.setup({"victory": false, "floor": 5, "reason": "party_wipe", "hero_results": hero_results}, {"deaths": [tombstone]})
	main.modal_layer.add_child(lost)
	await _wait(1.2)
	_capture("res://tests/captures/capture_hero_lost.png")
	lost.call("skip_to_summary")
	await _wait(0.8)
	_capture("res://tests/captures/capture_mission_failed.png")
	lost.queue_free()
	await _wait(0.2)
	# Base più avanzata: Lv.3 con nuove strutture
	state.data.world.base_level = 3
	state.debug_clear_floors(6)
	state.data.facilities.training.level = 3
	state.data.facilities.dormitory.level = 2
	state.data.facilities.merging.level = 2
	state.data.facilities.armory.level = 1
	state.save_and_notify()
	await _wait(2.5)
	_capture("res://tests/captures/capture_hub_level3.png")
	# Battaglia
	main.deploy(1)
	# su PC lenti (o senza scheda video) l'ingresso nel portale dura di più:
	# si aspetta che la battaglia esista davvero, poi che il varco si dissolva
	var waited := 0.0
	while main.battle == null and waited < 120.0:
		await _wait(0.5)
		waited += 0.5
	await _wait(5.0)
	_capture("res://tests/captures/capture_battle.png")
	if main.battle != null:
		main.battle.speed_scale = 2.0
		await _wait(5.0)
		_capture("res://tests/captures/capture_battle_late.png")
	main.queue_free()
	await process_frame
	quit(0)

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame

func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	print("CAPTURE  %s  %dx%d  error=%d" % [path, image.get_width(), image.get_height(), error])
