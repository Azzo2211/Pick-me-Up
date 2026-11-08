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
	# --base=N [--facility=M]: base al livello N, tutte le strutture disponibili al livello M (di solito N)
	var base_arg := 0
	var facility_arg := 0
	for arg in args:
		if arg.begins_with("--base="): base_arg = int(arg.trim_prefix("--base="))
		if arg.begins_with("--facility="): facility_arg = int(arg.trim_prefix("--facility="))
	if base_arg > 0:
		state.data.world.base_level = base_arg
		for id in state.FACILITY_ORDER:
			if base_arg >= int(state.FACILITIES[id].unlock): state.data.facilities[id].level = clampi(facility_arg if facility_arg > 0 else base_arg, 1, base_arg)
	elif args.has("--base5"):
		state.data.world.base_level = 5
		for id in state.FACILITY_ORDER: state.data.facilities[id].level = 3
	elif args.has("--base3"):
		state.data.world.base_level = 3
		for id in ["training", "dormitory", "merging", "gate", "armory"]: state.data.facilities[id].level = 2
	elif args.has("--base2"):
		state.data.world.base_level = 2
	for arg in args:
		if arg.begins_with("--light="): state.set_light(arg.trim_prefix("--light="))
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
	var tag := "base5" if args.has("--base5") else "base3" if args.has("--base3") else "base2" if args.has("--base2") else "base1"
	if base_arg > 0: tag = "base%d" % base_arg + ("_f%d" % facility_arg if facility_arg > 0 else "")
	if state.light_preset() != "dusk": tag += "_" + state.light_preset()
	_capture("res://tests/captures/preview_%s_overview.png" % tag)
	if args.has("--overview-only"):
		quit(0)
		return
	# --shots=a,b,c: inquadrature da salvare (strutture o isole, es. isola:campi)
	var shots := "training,merging,gate,dormitory"
	for arg in args:
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	for id in shots.split(","):
		view.focus_on(id, 0)
		await create_timer(1.0).timeout
		_capture("res://tests/captures/preview_%s_%s.png" % [tag, id.replace("isola:", "isola_").replace("isolotto:", "isolotto_")])
	quit(0)

func _capture(path: String) -> void:
	# --out=/cartella: salva lì invece che in tests/captures (le catture di QA restano intatte)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): path = arg.trim_prefix("--out=").path_join(path.get_file())
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("CAPTURE ", path)
