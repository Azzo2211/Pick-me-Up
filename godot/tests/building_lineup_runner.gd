extends SceneTree

## Galleria degli edifici: rende una struttura a più livelli, un'immagine per livello
## (da unire con montage). Serve a controllare come cresce un edificio dal Lv.1 al Lv.10.
##   xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/building_lineup_runner.gd -- --test-mode
##       --id=dormitory[,training,...] [--levels=1,2,3,4,5,6,7,8,9,10] [--base=0] [--light=dusk] [--size=640x520] [--out=/cartella]
## --base=0: la base ha lo stesso livello dell'edificio (minimo 1, massimo 10).
## File: <out>/<id>_lv01.png ...

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.get_slice("=", 1)
	return fallback

func _run() -> void:
	# se qualcosa va storto la galleria non resta appesa
	create_timer(float(_arg("timeout", "300"))).timeout.connect(func(): quit(1))
	var out := _arg("out", ProjectSettings.globalize_path("res://tests/captures/lineup"))
	DirAccess.make_dir_recursive_absolute(out)
	var size := _arg("size", "640x520").split("x")
	root.size = Vector2i(int(size[0]), int(size[1]))
	var levels: Array[int] = []
	for l in _arg("levels", "1,2,3,4,5,6,7,8,9,10").split(","): levels.append(int(l))
	var base_arg := int(_arg("base", "0"))
	var world := Node3D.new()
	root.add_child(world)
	WorldLook.setup(world, _arg("light", "dusk"), {}, 80.0)
	var gb := MeshBuilder.new()
	gb.material("ground", WorldMaterials.terrain())
	gb.box("ground", Vector3(70, 0.2, 70), Vector3(0, -0.1, 0), Color(0.0, 0.0, 0.0, 1.0))
	gb.instance(world)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.far = 300.0
	world.add_child(camera)
	camera.current = true
	for id in _arg("id", "dormitory").split(","):
		var models: Array[BuildingModel] = []
		var reach := 0.0
		var top := 0.0
		for level in levels:
			var model := BuildingModel.new()
			model.build(id, level, clampi(level, 1, 10) if base_arg <= 0 else base_arg)
			model.visible = false
			world.add_child(model)
			models.append(model)
			reach = maxf(reach, maxf(model.footprint.x, model.footprint.z))
			top = maxf(top, model.top_height)
		# stessa inquadratura per tutti i livelli: le altezze si confrontano a colpo d'occhio
		var yaw := deg_to_rad(32.0)
		var pitch := deg_to_rad(24.0)
		var target := Vector3(0, top * 0.42, 0)
		var dist := maxf(reach * 1.75, top * 2.35) + 4.0
		camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
		camera.look_at(target, Vector3.UP)
		for i in models.size():
			for m in models: m.visible = false
			models[i].visible = true
			for f in 6: await process_frame
			var path := out.path_join("%s_lv%02d.png" % [id, levels[i]])
			root.get_texture().get_image().save_png(path)
			print("CAPTURE ", path)
		for m in models: m.queue_free()
		await process_frame
	quit(0)
