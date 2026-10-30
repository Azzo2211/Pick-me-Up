extends SceneTree

## Fila di personaggi (eroi per ruolo, abitanti, nemici) per controllare
## proporzioni, vestiti e pose. Salva tests/captures/characters.png
## xvfb-run godot --path godot -s res://tests/character_probe_runner.gd -- --test-mode

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state: RiftwardState = root.get_node("GameState")
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 760)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	WorldLook.setup(world, "dusk", {"sun_rot": Vector3(-38, 200, 0)})
	var ground := MeshBuilder.new()
	ground.material("t", WorldMaterials.terrain())
	ground.box("t", Vector3(30, 0.1, 12), Vector3(0, -0.05, 0), Color(0.6, 0.0, 0, 1))
	ground.instance(world)
	var roles := ["Guardian", "Vanguard", "Lancer", "Ranger", "Mage", "Support"]
	var models: Array = []
	var poses := ["idle", "walk", "attack", "attack", "attack", "idle"]
	var x := -5.4
	for i in roles.size():
		for fem_pass in 2:
			var hero := state.generate_hero("probe-%d-%d" % [i, fem_pass * 7 + 3], 3 + fem_pass * 2, roles[i])
			var appearance := RiftwardState.appearance_for(hero)
			var m := CharacterModel.new()
			world.add_child(m)
			m.build_hero(hero, appearance)
			m.position = Vector3(x, 0, 0)
			m.rotation.y = 0.25
			m.phase = i * 0.7
			var pose: String = poses[i] if fem_pass == 0 else "idle"
			m.play(pose)
			models.append(m)
			x += 0.85
	var mx := -5.0
	for kind in ["raider", "archer", "hound", "brute", "boss"]:
		var m := CharacterModel.new()
		world.add_child(m)
		m.build_monster(kind, {"raider": Color("#c0453a"), "archer": Color("#c4467e"), "hound": Color("#7b4fb8"), "brute": Color("#a8653a"), "boss": Color("#4f8a3a")}[kind])
		m.position = Vector3(mx, 0, -2.4)
		m.rotation.y = 0.4
		models.append(m)
		mx += 1.6 if kind != "brute" else 2.6
	var v := CharacterModel.new()
	world.add_child(v)
	v.build_villager(77)
	v.position = Vector3(5.6, 0, -0.6)
	v.play("talk")
	models.append(v)
	var sitter := CharacterModel.new()
	world.add_child(sitter)
	sitter.build_villager(78)
	sitter.position = Vector3(6.4, 0, -0.6)
	sitter.play("sit")
	models.append(sitter)
	var dead := CharacterModel.new()
	world.add_child(dead)
	dead.build_villager(79)
	dead.position = Vector3(6.6, 0, 0.6)
	dead.play("dead")
	models.append(dead)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0.3, 3.4, 10.5)
	world.add_child(cam)
	cam.look_at(Vector3(0.3, 0.6, -1.0))
	cam.current = true
	for f in 40:
		for m in models: (m as CharacterModel).update_animation(0.012)
		await process_frame
	vp.get_texture().get_image().save_png("res://tests/captures/characters.png")
	cam.fov = 22
	cam.position = Vector3(-3.6, 1.15, 2.6)
	cam.look_at(Vector3(-3.6, 0.55, 0.0))
	for f in 6: await process_frame
	vp.get_texture().get_image().save_png("res://tests/captures/characters_close.png")
	print("CAPTURE characters")
	quit(0)
