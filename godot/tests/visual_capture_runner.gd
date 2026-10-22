extends SceneTree

## Cattura schermate reali del gioco (serve un display, es. xvfb-run):
## godot --path godot --rendering-driver opengl3 -s res://tests/visual_capture_runner.gd -- --test-mode

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
	main.open_hero(state.data.heroes[4].id)
	await _wait(0.8)
	_capture("res://tests/captures/capture_dossier.png")
	main.close_all_modals()
	await _wait(0.3)
	state.data.world.gems = 5000
	main.open_panel("crystal")
	await _wait(0.6)
	main.panels._summon("high", 10)
	await _wait(1.5)
	_capture("res://tests/captures/capture_summon.png")
	main.close_all_modals()
	main.close_panel()
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
	await _wait(9.0)
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
