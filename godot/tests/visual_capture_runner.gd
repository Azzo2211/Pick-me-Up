extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Avvia questa suite con: -- --test-mode")
		quit(2)
		return
	var state := RiftwardState.new()
	state.name = "GameState"
	root.add_child(state)
	state.new_world("visual-reference-seed")
	state.data.tutorial_seen = true
	var main_scene: PackedScene = load("res://Main.tscn")
	var main: Control = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await create_timer(0.35).timeout
	for child in main.get_children():
		if child is Window:
			child.queue_free()
	await process_frame
	if OS.get_cmdline_user_args().has("--resized-hub"):
		_capture("res://tests/capture_hub_resized.png")
		main.queue_free()
		state.queue_free()
		await process_frame
		quit(0)
		return
	_capture("res://tests/capture_hub.png")
	main.base_hub._select_building(main.base_hub.building_by_id["training"])
	await create_timer(0.45).timeout
	await process_frame
	_capture("res://tests/capture_hub_training.png")
	if OS.get_cmdline_user_args().has("--hub-only"):
		main.base_hub.reset_camera()
		main.base_hub._select_building(main.base_hub.building_by_id["summoning"])
		await create_timer(0.45).timeout
		await process_frame
		_capture("res://tests/capture_hub_summoning.png")
		main.base_hub.reset_camera()
		for tick in range(600):
			for agent in main.base_hub.hero_agents:
				agent.step(0.1, main.base_hub.building_data)
		await process_frame
		_capture("res://tests/capture_hub_living.png")
		main.queue_free()
		state.queue_free()
		await process_frame
		quit(0)
		return
	main._set_view("summon")
	await process_frame
	await process_frame
	_capture("res://tests/capture_summon.png")
	main._set_view("merge")
	await process_frame
	await process_frame
	_capture("res://tests/capture_merge.png")
	main._set_view("heroes")
	await process_frame
	await process_frame
	_capture("res://tests/capture_heroes.png")
	main.queue_free()
	state.queue_free()
	await process_frame
	quit(0)

func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	print("CAPTURE  %s  %dx%d  error=%d" % [path, image.get_width(), image.get_height(), error])
