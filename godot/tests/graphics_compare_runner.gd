extends SceneTree

## Catture "prima/dopo" della grafica: stesse inquadrature della base e della battaglia,
## con lo stesso mondo, da confrontare tra due versioni del gioco (serve un display).
## xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/graphics_compare_runner.gd -- --test-mode --out=/cartella [--heroes=24] [--base=3] [--light=dusk] [--only-base]

var main: Control
var state

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.get_slice("=", 1)
	return fallback

func _wait(t: float) -> void:
	await create_timer(t).timeout

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _arg("out", "res://tests/captures").path_join(name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func _run() -> void:
	state = root.get_node("GameState")
	state.new_world("graphics-compare-seed")
	state.data.tutorial_seen = true
	var base := int(_arg("base", "3"))
	state.debug_clear_floors(maxi(5, (base - 1) * 10))
	state.data.world.base_level = base
	for id in state.FACILITY_ORDER:
		if base >= int(state.FACILITIES[id].unlock): state.data.facilities[id].level = base
	for i in int(_arg("heroes", "24")) - state.data.heroes.size():
		var hero: Dictionary = state.generate_hero("compare-%d" % i, 1 + (i * 3) % 7)
		hero.class_chosen = true
		state.data.heroes.append(hero)
	state.data.settings.light = _arg("light", "dusk")
	state.assign_hero(state.data.heroes[6].id, "training")
	state.assign_hero(state.data.heroes[7].id, "training")
	state.assign_hero(state.data.heroes[8].id, "dormitory")
	if state.has_method("assign_portraits"): state.assign_portraits()
	var main_scene: PackedScene = load("res://Main.tscn")
	main = main_scene.instantiate()
	root.add_child(main)
	await _wait(6.0)
	# la base da lontano, senza interfaccia
	main.hud.visible = false
	await _wait(0.4)
	await _capture("base_lontano")
	# la piazza da vicino: gli eroi si riconoscono?
	main.hub._kill_tween()
	main.hub.target = Vector3(0.0, 0.0, 1.5)
	main.hub.distance = 15.0
	main.hub._apply_camera()
	await _wait(1.2)
	await _capture("base_piazza")
	main.hub.target = Vector3(-7.0, 0.0, -3.0)
	main.hub.distance = 24.0
	main.hub._apply_camera()
	await _wait(1.0)
	await _capture("base_addestramento")
	main.hud.visible = true
	main.hub.reset_view()
	await _wait(0.8)
	if OS.get_cmdline_user_args().has("--only-base"):
		quit(0)
		return
	# battaglia: Piano 3 a metà scontro
	main.deploy(3)
	var waited := 0.0
	while main.battle == null and waited < 25.0:
		await _wait(0.1)
		waited += 0.1
	if main.battle != null:
		await _wait(9.0)
		await _capture("battaglia")
		main.battle.speed_scale = 8.0
	quit(0)
