extends SceneTree

const VIEWS := ["hub", "tower", "heroes", "squad", "summon", "merge", "base", "shop", "archive", "dev"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Avvia questa suite con: -- --test-mode")
		quit(2)
		return
	print("Riftward Godot UI smoke suite")
	var state := RiftwardState.new()
	state.name = "GameState"
	root.add_child(state)
	state.new_world("ui-smoke-seed")
	state.data.tutorial_seen = true
	state.data.stages["1"].descriptor["threat"] = state.data.stages["1"].descriptor.threat_budget
	state.data.stages["1"].descriptor.erase("threat_budget")

	var main_scene: PackedScene = load("res://Main.tscn")
	var main: Control = main_scene.instantiate()
	root.add_child(main)
	await process_frame

	for view in VIEWS:
		main._set_view(view)
		await process_frame
		print("PASS  schermata " + view)

	main.selected_hero_id = state.data.heroes[0].id
	main._set_view("hero")
	await process_frame
	print("PASS  schermata dettaglio eroe")

	main.queue_free()
	state.queue_free()
	await process_frame
	print("\nRisultato: %d schermate caricate senza errori" % (VIEWS.size() + 1))
	quit(0)
