extends SceneTree

## Tutti i tagli di capelli del kit sulla stessa testa: davanti, tre quarti e dietro.
## xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/hair_sheet_runner.gd -- --test-mode --out DIR

const STYLES := ["short", "crop", "wavy", "medium", "tied_back", "slicked", "layered", "messy", "long_straight", "braid", "bun", "long_wavy", "bob"]
const COLORS := ["#2a2420", "#d9c27a", "#6b4a2e", "#c9c6c2", "#a0522d", "#3a2a20"]

var vp: SubViewport
var world: Node3D
var cam: Camera3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := "res://tests/captures/hair"
	var oi := args.find("--out")
	if oi >= 0 and oi + 1 < args.size(): out_dir = args[oi + 1]
	var styles := STYLES
	var oa := args.find("--only")
	if oa >= 0 and oa + 1 < args.size(): styles = Array(args[oa + 1].split(","))
	var fem := args.has("--fem")
	DirAccess.make_dir_recursive_absolute(out_dir)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(240, 280)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#30364e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b4b9d6")
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 28, 0)
	key.light_energy = 1.25
	world.add_child(key)
	cam = Camera3D.new()
	cam.fov = 20
	world.add_child(cam)
	cam.current = true
	var i := 0
	for style in styles:
		var look := {"skin": Color("#f2d3b8"), "hair": Color(COLORS[i % COLORS.size()]), "eyes": Color("#4a6a9a"), "fem": fem,
			"archetype": "villager", "outfit_kind": "villager", "face": 1, "hair_kind": style, "body": "average", "age": 28,
			"beard": 0, "glasses": false, "seed": 1, "outfit": Color("#7a4a3a"), "class_chosen": false}
		var m := CharacterModel.new()
		m.outline_px = 1.6
		world.add_child(m)
		m._build_anime(look, "Villager", 2, "villager", "")
		m.use_clips = false
		m.update_animation(0.0)
		var hy: float = m.head.global_position.y
		for view in [["front", 0.0], ["three", 0.75], ["side", PI * 0.5], ["back", PI]]:
			m.rotation.y = view[1]
			cam.position = Vector3(0, hy + 0.06, 1.05)
			cam.look_at(Vector3(0, hy + 0.03, 0))
			for f in 3: await process_frame
			vp.get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [style, view[0]]))
		m.queue_free()
		i += 1
	quit()
