extends SceneTree

## Foglio dei personaggi in 3D, come il riferimento: per ogni archetipo il corpo
## davanti, di lato e dietro, i tre volti e le quattro capigliature. Salva le
## singole tessere in una cartella (primo argomento dopo --out), da comporre.
## xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/look_sheet_runner.gd -- --test-mode --out /percorso

const LookScript := preload("res://scripts/characters/hero_look.gd")
const GeneratorScript := preload("res://scripts/characters/character_generator.gd")
const JOBS := {"guard": "Guardia cittadina", "merchant": "Mercante", "scholar": "Archivista", "villager": "Contadino"}

var state: RiftwardState
var vp: SubViewport
var world: Node3D
var cam: Camera3D
var out_dir := "res://tests/captures/sheet"

func _initialize() -> void:
	call_deferred("_run")

func _hero(archetype: String, face: int, hair: String, fem: bool, tag: String, role: String = "") -> Dictionary:
	var job: String = JOBS[archetype]
	var h := state.generate_hero("sheet-%s-%s" % [archetype, tag], 1)
	h.name = ("Mira" if fem else "Bren") + " Sheet"
	h.job = job
	h.profession = job
	h.commoner = true
	h.class_chosen = not role.is_empty()
	if not role.is_empty(): h.role = role
	h.appearance = GeneratorScript.generate(str(h.id) + ":appearance", str(state.COMMONER_JOBS[job].category))
	h.look = LookScript.generate(str(h.id), archetype, fem, 3, h.appearance)
	h.look.face = face
	h.look.hair = hair
	if archetype == "scholar" and face == 2: h.look.age = 56
	elif face == 0: h.look.age = 22
	else: h.look.age = 30
	return h

func _model(hero: Dictionary) -> CharacterModel:
	var m := CharacterModel.new()
	m.outline_px = 2.0
	world.add_child(m)
	m.build_hero(hero, RiftwardState.appearance_for(hero))
	m.use_clips = false
	m.play("idle")
	m.update_animation(0.0)
	return m

func _shot(file: String, size: Vector2i, eye: Vector3, target: Vector3, fov: float) -> void:
	vp.size = size
	cam.fov = fov
	cam.position = eye
	cam.look_at(target)
	for f in 4: await process_frame
	vp.get_texture().get_image().save_png(out_dir.path_join(file))

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var oi := args.find("--out")
	if oi >= 0 and oi + 1 < args.size(): out_dir = args[oi + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	state = root.get_node("GameState")
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	WorldLook.setup(world, "day", {"sun_rot": Vector3(-40, 30, 0)})
	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	var only := []
	var oa := args.find("--only")
	if oa >= 0 and oa + 1 < args.size(): only = args[oa + 1].split(",")
	for archetype in ["guard", "merchant", "scholar", "villager"]:
		if not only.is_empty() and not archetype in only: continue
		var arch: Dictionary = LookScript.ARCHETYPES[archetype]
		# corpo intero: davanti, lato, dietro
		var body := _model(_hero(archetype, 1, str(arch.hair_m[0]), false, "body"))
		for view in [["front", 0.0], ["side", PI * 0.5], ["back", PI]]:
			body.rotation.y = view[1]
			await _shot("%s_body_%s.png" % [archetype, view[0]], Vector2i(360, 560), Vector3(0, 0.5, 3.3), Vector3(0, 0.48, 0), 18)
		body.queue_free()
		# tre volti con la stessa capigliatura
		for face in 3:
			var m := _model(_hero(archetype, face, str(arch.hair_m[1]), false, "face%d" % face))
			m.rotation.y = 0.25
			await _shot("%s_face_%d.png" % [archetype, face], Vector2i(220, 220), Vector3(0.0, 0.83, 1.15), Vector3(0, 0.81, 0), 13)
			m.queue_free()
		# quattro capigliature, volto comune
		for i in 4:
			var m := _model(_hero(archetype, 1, str(arch.hair_m[i]), false, "hair%d" % i))
			m.rotation.y = 0.55
			await _shot("%s_hair_%d.png" % [archetype, i], Vector2i(220, 220), Vector3(0.0, 0.84, 1.2), Vector3(0, 0.8, 0), 14)
			m.queue_free()
		# variante femminile
		for i in 2:
			var m := _model(_hero(archetype, i, str(arch.hair_f[i * 2 + 1]), true, "fem%d" % i))
			m.rotation.y = 0.3
			await _shot("%s_fem_%d.png" % [archetype, i], Vector2i(220, 220), Vector3(0.0, 0.8, 1.15), Vector3(0, 0.78, 0), 14)
			m.queue_free()
	quit()
