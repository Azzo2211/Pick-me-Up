extends SceneTree

## Scena di prova dello stile 3D (materiali, alberi, luce del crepuscolo).
## xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/style_probe_runner.gd -- --test-mode


func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	WorldLook.setup(world, OS.get_environment("LOOK") if not OS.get_environment("LOOK").is_empty() else "dusk")
	# terreno
	var b := MeshBuilder.new()
	b.material("terrain", WorldMaterials.terrain())
	var size := 30
	var step := 0.5
	for zi in int(size / step):
		for xi in int(size / step):
			var x0 := -size * 0.5 + xi * step
			var z0 := -size * 0.5 + zi * step
			var pts := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			var cols := []
			for p in pts:
				var v: Vector3 = p
				var road := clampf(1.0 - absf(v.x - 2.0) / 1.4, 0.0, 1.0)
				var plaza := clampf(1.0 - Vector2(v.x - 2.0, v.z + 3.0).length() / 3.0, 0.0, 1.0) * 1.6
				cols.append(Color(clampf(road * 1.4, 0, 1), clampf(plaza, 0, 1), 0, 1))
			b.tri("terrain", pts[0], pts[1], pts[2], Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cols[0], cols[1], cols[2])
			b.tri("terrain", pts[0], pts[2], pts[3], Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cols[0], cols[2], cols[3])
	b.instance(world)
	# casa di prova
	var h := MeshBuilder.new()
	h.material("stone", WorldMaterials.stone("wall"))
	h.material("plaster", WorldMaterials.plaster("warm"))
	h.material("timber", WorldMaterials.wood("timber"))
	h.material("roof", WorldMaterials.roof("slate"))
	h.material("window", WorldMaterials.window())
	h.push_at(Vector3(-3, 0, -2), 0.3)
	h.box("stone", Vector3(5.4, 0.6, 3.8), Vector3(0, 0.3, 0))
	h.box("plaster", Vector3(5.2, 1.5, 3.6), Vector3(0, 1.35, 0))
	h.box("plaster", Vector3(5.2, 1.5, 3.6), Vector3(0, 2.85, 0))
	for x in [-2.6, -1.3, 0.0, 1.3, 2.6]:
		h.box("timber", Vector3(0.14, 3.0, 0.14), Vector3(x, 2.1, 1.82), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	h.box("timber", Vector3(5.4, 0.16, 0.16), Vector3(0, 2.1, 1.84), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	h.box("timber", Vector3(5.4, 0.16, 0.16), Vector3(0, 3.55, 1.84), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	for x in [-1.95, -0.65, 0.65, 1.95]:
		h.box("window", Vector3(0.5, 0.7, 0.06), Vector3(x, 2.85, 1.81))
		h.box("window", Vector3(0.5, 0.7, 0.06), Vector3(x, 1.4, 1.81))
	h.gable_roof("roof", 5.2, 3.6, 1.6, 3.6, Color.WHITE, 0.35, 0.1)
	h.gable_wall("plaster", 3.6, 1.6, 3.6, 2.6, Color.WHITE, 1.0)
	h.gable_wall("plaster", 3.6, 1.6, 3.6, -2.6, Color.WHITE, -1.0)
	h.box("stone", Vector3(0.6, 1.8, 0.6), Vector3(1.6, 5.0, -0.6))
	h.pop()
	h.instance(world)
	# torre di pietra
	var t := MeshBuilder.new()
	t.material("stone", WorldMaterials.stone("wall"))
	t.material("roof", WorldMaterials.roof("slate_blue"))
	t.cylinder("stone", 1.3, 1.45, 5.0, Vector3(6, 2.5, -4), Color.WHITE, 16)
	t.cone_roof("roof", 1.8, 2.4, 5.0, Color.WHITE, 16, Vector3(6, 0, -4))
	t.instance(world)
	# alberi
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for kind in ["conifer", "broadleaf"]:
		for v in 3:
			var xs: Array = []
			for i in 6:
				var p := Vector3(r.randf_range(-14, 14), 0, r.randf_range(-14, -5))
				if absf(p.x - 2.0) < 2.5: continue
				xs.append(NatureKit.placement(p, r.randf_range(0.8, 1.2), r.randf() * TAU))
			NatureKit.scatter(world, kind, v, xs)
	var tufts: Array = []
	for i in 900:
		var p := Vector3(r.randf_range(-14, 14), 0, r.randf_range(-14, 14))
		if absf(p.x - 2.0) < 1.6: continue
		tufts.append(NatureKit.placement(p, r.randf_range(0.7, 1.3), r.randf() * TAU))
	NatureKit.scatter(world, "tuft", 0, tufts.slice(0, 450), false)
	NatureKit.scatter(world, "tuft", 1, tufts.slice(450), false)
	var rocks: Array = []
	for i in 8: rocks.append(NatureKit.placement(Vector3(r.randf_range(-12, 12), 0, r.randf_range(2, 10)), r.randf_range(0.6, 1.4), r.randf() * TAU))
	NatureKit.scatter(world, "rock", 0, rocks)
	var bushes: Array = []
	for i in 10: bushes.append(NatureKit.placement(Vector3(r.randf_range(-12, 12), 0, r.randf_range(-4, 8)), r.randf_range(0.8, 1.3), r.randf() * TAU))
	NatureKit.scatter(world, "bush", 0, bushes)
	var cam := Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(4, 9, 16)
	world.add_child(cam)
	cam.look_at(Vector3(0, 1.5, -3))
	cam.current = true
	for i in 40: await process_frame
	vp.get_texture().get_image().save_png("res://tests/captures/style_probe.png")
	print("CAPTURE style_probe")
	quit(0)
