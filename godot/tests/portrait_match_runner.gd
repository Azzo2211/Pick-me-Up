extends SceneTree

## Ritratti dipinti sopra e modelli 3D sotto: controlla che capelli, pelle,
## barba, occhiali, orecchie da elfo e uomini-bestia corrispondano.
## Salva tests/captures/portrait_match.png (serve un display).
## xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/portrait_match_runner.gd -- --test-mode

const PICKS := [
	["p054", "Mage"], ["p038", "Support"], ["p009", "Vanguard"], ["p097", "Guardian"], ["p292", "Vanguard"],
	["p087", "Ranger"], ["p003", "Lancer"], ["p046", "Mage"], ["p144", "Guardian"], ["p070", "Lancer"],
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	state.new_world("portrait-match")
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.build_theme()
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color("#0d0a10")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var row := HBoxContainer.new()
	row.position = Vector2(150, 20)
	row.add_theme_constant_override("separation", 22)
	ui.add_child(row)
	var holder := SubViewportContainer.new()
	holder.position = Vector2(0, 200)
	holder.size = Vector2(1920, 760)
	ui.add_child(holder)
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 760)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	WorldLook.setup(world, "day", {"sun_rot": Vector3(-38, 200, 0)})
	var models: Array = []
	for i in PICKS.size():
		var hero: Dictionary = state.generate_hero("match-%d" % i, 3, PICKS[i][1])
		hero.portrait = PICKS[i][0]
		var p = load("res://scripts/hero_portrait.gd").new()
		p.setup(hero, 150)
		row.add_child(p)
		var m := CharacterModel.new()
		world.add_child(m)
		m.build_hero(hero, RiftwardState.appearance_for(hero))
		m.position = Vector3(-3.15 + i * 0.7, 0, 0)
		m.play("idle")
		models.append(m)
	var cam := Camera3D.new()
	cam.fov = 21
	cam.position = Vector3(0.0, 1.0, 8.2)
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 0.82, 0.0))
	cam.current = true
	for f in 30:
		for m in models: (m as CharacterModel).update_animation(0.012)
		await process_frame
	root.get_texture().get_image().save_png("res://tests/captures/portrait_match.png")
	# primo piano delle teste: orecchie, occhiali, corna
	cam.fov = 9
	cam.position = Vector3(-2.1, 1.05, 6.0)
	cam.look_at(Vector3(-2.1, 0.8, 0.0))
	for f in 4: await process_frame
	vp.get_texture().get_image().save_png("res://tests/captures/portrait_match_close.png")
	print("CAPTURE portrait_match")
	quit(0)
