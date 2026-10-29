extends SceneTree

## Banco di prova della qualità grafica: pochi oggetti ripresi da vicino con la
## stessa luce della base. Uso: -- --test-mode [--scene=nature|buildings|people] [--light=dusk|day|night]

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.get_slice("=", 1)
	return fallback

func _run() -> void:
	var scene := _arg("scene", "nature")
	var world := Node3D.new()
	root.add_child(world)
	WorldLook.setup(world, _arg("light", "dusk"), {}, 60.0)
	var gb := MeshBuilder.new()
	gb.material("ground", WorldMaterials.terrain())
	gb.box("ground", Vector3(40, 0.2, 40), Vector3(0, -0.1, 0), Color(0, 0, 0, 1))
	gb.instance(world)
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	match scene:
		"nature":
			NatureKit.scatter(world, "conifer", 0, [NatureKit.placement(Vector3(-3, 0, 0), 1.0, 0.0)], true)
			NatureKit.scatter(world, "broadleaf", 1, [NatureKit.placement(Vector3(0.5, 0, -1), 1.0, 0.5)], true)
			NatureKit.scatter(world, "bush", 0, [NatureKit.placement(Vector3(3, 0, 1), 1.0, 0.0)], true)
			NatureKit.scatter(world, "rock", 0, [NatureKit.placement(Vector3(1.5, 0, 2.2), 0.8, 0.3)], true)
			var tufts: Array = []
			for i in 60: tufts.append(NatureKit.placement(Vector3(randf_range(-5, 5), 0, randf_range(-1, 4)), 1.0, randf() * TAU))
			NatureKit.scatter(world, "tuft", 0, tufts, false)
			cam.position = Vector3(0, 5.5, 11)
			cam.look_at(Vector3(0, 1.6, 0))
		"single":
			var kind := _arg("kind", "bush")
			NatureKit.scatter(world, kind, int(_arg("variant", "0")), [NatureKit.placement(Vector3(0, 0, 0), 1.0, 0.0)], true)
			cam.position = Vector3(0, 4.2, 4.6) * (2.2 if kind in ["conifer", "broadleaf"] else 1.0)
			cam.look_at(Vector3(0, 0.6 * (3.0 if kind in ["conifer", "broadleaf"] else 1.0), 0))
		"buildings":
			var ids := ["dormitory", "merging", "training"]
			for i in ids.size():
				var b := BuildingModel.new()
				world.add_child(b)
				b.build(ids[i], int(_arg("level", "1")), int(_arg("base", "1")))
				b.position = Vector3((i - 1) * 9.0, 0, 0)
			cam.position = Vector3(0, 11, 17)
			cam.look_at(Vector3(0, 1.5, 0))
		"building":
			# un solo edificio da vicino, con l'inquadratura della base (pitch ~40°)
			var bm := BuildingModel.new()
			world.add_child(bm)
			bm.build(_arg("id", "dormitory"), int(_arg("level", "1")), int(_arg("base", "1")))
			var dist := float(_arg("dist", "13"))
			var yaw := deg_to_rad(float(_arg("yaw", "20")))
			cam.position = Vector3(sin(yaw), 0.0, cos(yaw)) * dist * 0.77 + Vector3(0, dist * 0.64, 0)
			cam.look_at(Vector3(0, bm.top_height * 0.35, 0))
		"smoke":
			var holder := BuildingModel.new()
			world.add_child(holder)
			for i in 3:
				holder._smoke(Vector3((i - 1) * 1.5, 0.5, 0))
			var k := 0
			for child in holder.get_children():
				if child is CPUParticles3D:
					var mat: StandardMaterial3D = (child as CPUParticles3D).mesh.material
					if k == 1: mat.vertex_color_use_as_albedo = false
					if k == 2: mat.vertex_color_is_srgb = true
					k += 1
			cam.position = Vector3(0, 2.5, 5)
			cam.look_at(Vector3(0, 1.2, 0))
		"people":
			var gs := RiftwardState.new()
			gs.is_test_mode = true
			root.add_child(gs)
			gs.new_world("quality-probe")
			var heroes: Array = gs.data.heroes
			for i in mini(5, heroes.size()):
				var m := CharacterModel.new()
				world.add_child(m)
				m.build_hero(heroes[i], gs.hero_appearance(heroes[i]) if gs.has_method("hero_appearance") else {})
				m.position = Vector3((i - 2) * 1.1, 0, 0)
				m.rotation.y = float(_arg("turn", "0"))
			cam.fov = float(_arg("fov", "30"))
			var close := _arg("close", "0") == "1"
			cam.position = Vector3(0, 0.9, 1.6) if close else Vector3(0, 1.6, 5.2)
			cam.look_at(Vector3(0, 0.82 if close else 0.5, 0))
	for i in int(_arg("frames", "12")): await process_frame
	var image := root.get_texture().get_image()
	var path := "res://tests/captures/probe_%s_%s.png" % [scene, _arg("kind", _arg("id", _arg("tag", "x")))]
	image.save_png(ProjectSettings.globalize_path(path))
	print("CAPTURE ", path)
	quit(0)
