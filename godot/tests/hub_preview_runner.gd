extends SceneTree

## Rende la sola base 3D e salva alcune inquadrature (sviluppo visivo).

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := RiftwardState.new()
	state.name = "GameState"
	state.is_test_mode = true
	root.add_child(state)
	state.new_world("hub-preview-seed")
	var args := OS.get_cmdline_user_args()
	if args.has("--base5"):
		state.data.world.base_level = 5
		for id in state.FACILITY_ORDER: state.data.facilities[id].level = 3
	elif args.has("--base2"):
		state.data.world.base_level = 2
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	var view := HubView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(view)
	await process_frame
	view.refresh(state)
	state.assign_hero(state.data.heroes[0].id, "training")
	state.assign_hero(state.data.heroes[1].id, "training")
	state.assign_hero(state.data.heroes[2].id, "dormitory")
	view.refresh(state)
	for i in 90: await process_frame
	await create_timer(4.0).timeout
	var tag := "base5" if args.has("--base5") else "base2" if args.has("--base2") else "base1"
	_capture("res://tests/captures/preview_%s_overview.png" % tag)
	view.focus_on("training", 0)
	await create_timer(1.0).timeout
	_capture("res://tests/captures/preview_%s_training.png" % tag)
	view.focus_on("merging", 0)
	await create_timer(1.0).timeout
	_capture("res://tests/captures/preview_%s_merging.png" % tag)
	view.focus_on("gate", 0)
	await create_timer(1.0).timeout
	_capture("res://tests/captures/preview_%s_gate.png" % tag)
	view.focus_on("dormitory", 0)
	await create_timer(1.0).timeout
	_capture("res://tests/captures/preview_%s_dormitory.png" % tag)
	quit(0)

func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("CAPTURE ", path)
