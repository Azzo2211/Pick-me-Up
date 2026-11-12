extends SceneTree

## Confronto tra il ritratto dipinto di ogni eroe e il suo personaggio 3D (busto e figura
## intera), per controllare che si somiglino: sesso, capelli, pelle, barba, occhiali, vestiti.
## xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/portrait_match_runner.gd -- --test-mode [--count=12] [--offset=0] [--seed=match] [--ids=p003,p017] [--out=/percorso/file.png]

const HeroPortraitScript := preload("res://scripts/hero_portrait.gd")
const CELL := 150.0

var state: RiftwardState

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.get_slice("=", 1)
	return fallback

## Una foto 3D dell'eroe in un riquadro: "bust" (mezzo busto) o "body" (figura intera).
func _shot(hero: Dictionary, size: Vector2i, mode: String) -> Array:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b4b9d6")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-28, 28, 0)
	key_light.light_energy = 1.25
	key_light.light_color = Color("#fff3e2")
	world.add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -60, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("#a9b8ff")
	world.add_child(fill)
	var model := CharacterModel.new()
	model.outline_px = 2.0
	world.add_child(model)
	model.build_hero(hero, state.hero_appearance(hero))
	model.use_clips = false
	model.play("idle")
	model.update_animation(0.0)
	model.rotation.y = 0.3 if mode == "bust" else 0.2
	var cam := Camera3D.new()
	cam.fov = 18.0
	world.add_child(cam)
	var s: float = model.rig.scale.y if model.rig != null else 0.5
	var head_y: float = model.head.global_position.y
	var top := head_y + 0.4 * s
	var bottom := head_y - 0.22 * s if mode == "bust" else -0.04
	if mode == "body": top = head_y + 0.62 * s
	var mid := (top + bottom) * 0.5
	var dist := (top - bottom) * 0.5 / tan(deg_to_rad(cam.fov * 0.5))
	cam.position = Vector3(0.0, mid + 0.012, dist)
	cam.look_at(Vector3(0.0, mid, 0.0))
	cam.current = true
	return [vp, model]

func _run() -> void:
	state = root.get_node("GameState")
	var count := int(_arg("count", "12"))
	var offset := int(_arg("offset", "0"))
	var seed_text := _arg("seed", "match")
	var out := _arg("out", "res://tests/captures/portrait_match.png")
	state.new_world("portrait-match-seed")
	state.data.tutorial_seen = true
	var heroes := []
	var forced: PackedStringArray = _arg("ids", "").split(",", false)
	if not forced.is_empty(): count = forced.size()
	# gli eroi prima di `offset` vengono generati lo stesso: prendono i loro ritratti, come in una partita vera
	for i in offset + count:
		var hero: Dictionary = state.generate_hero("%s-%d" % [seed_text, i], 1 + (i * 3) % 7)
		hero.class_chosen = true
		# --ids=p003,p017: volti scelti a mano, per controllare copricapi, barbe e uomini-bestia
		if not forced.is_empty(): hero["portrait_id"] = forced[i]
		state.data.heroes.append(hero)
		if i >= offset: heroes.append(hero)
	state.assign_portraits()
	var width := int(CELL * count + 40)
	root.size = Vector2i(width, 780)
	var bg := ColorRect.new()
	bg.color = Color("#121722")
	bg.size = Vector2(width, 780)
	root.add_child(bg)
	var models := []
	for i in heroes.size():
		var hero: Dictionary = heroes[i]
		var x := 20.0 + i * CELL
		var portrait: HeroPortrait = HeroPortraitScript.new()
		portrait.setup(hero, CELL - 12.0)
		portrait.position = Vector2(x + 6, 14)
		bg.add_child(portrait)
		var bust := _shot(hero, Vector2i(int(CELL - 12), 180), "bust")
		var bust_rect := TextureRect.new()
		bust_rect.texture = (bust[0] as SubViewport).get_texture()
		bust_rect.position = Vector2(x + 6, 14 + CELL)
		bg.add_child(bust_rect)
		var body := _shot(hero, Vector2i(int(CELL - 12), 330), "body")
		var body_rect := TextureRect.new()
		body_rect.texture = (body[0] as SubViewport).get_texture()
		body_rect.position = Vector2(x + 6, 14 + CELL + 190)
		bg.add_child(body_rect)
		models.append(bust[1])
		models.append(body[1])
		var name_label := Label.new()
		name_label.text = "%s\n%s %d★ · %s" % [str(hero.name), RiftwardState.role_label(str(hero.role)), int(hero.current_rarity), HeroPortrait.painted_for(hero)]
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.position = Vector2(x + 6, 14 + CELL + 190 + 334)
		name_label.size = Vector2(CELL - 12, 40)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bg.add_child(name_label)
	for f in 30:
		for m in models: (m as CharacterModel).update_animation(0.012)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("CAPTURE ", out)
	quit(0)
