extends Node

## Studio fotografico delle carte: costruisce il personaggio 3D dell'eroe in una
## scena a parte, lo fotografa a mezzo busto e restituisce la texture. Così la
## carta mostra esattamente il personaggio che cammina nella base e combatte.
## Le foto restano in memoria e su disco (user://portraits3d): cambiano solo se
## cambia l'aspetto (classe scelta, rarità, versione dello studio).
## Senza schermo (test headless) non fotografa: la carta usa il disegno di riserva.

const VERSION := 1
const SIZE := Vector2i(384, 480)
const CACHE_DIR := "user://portraits3d"

static var _instance: Node = null

var _cache: Dictionary = {}
var _waiting: Dictionary = {}
var _queue: Array = []
var _busy := false
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D

static func instance() -> Node:
	if _instance == null or not is_instance_valid(_instance):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null: return null
		_instance = load("res://scripts/ui/portrait_studio.gd").new()
		_instance.name = "PortraitStudio"
		tree.root.add_child.call_deferred(_instance)
	return _instance

static func can_shoot() -> bool:
	return DisplayServer.get_name() != "headless"

static func key_for(hero: Dictionary, look: Dictionary) -> String:
	var parts := [VERSION, str(hero.get("id", "")), str(hero.get("role", "")), int(hero.get("current_rarity", 1)), str(look)]
	return "%s_%08x" % [str(hero.get("id", "x")).validate_filename(), abs(str(parts).hash())]

## Texture della foto se è già pronta; altrimenti la mette in coda e chiama `done(texture)` appena c'è.
func request(hero: Dictionary, done: Callable) -> Texture2D:
	var look := RiftwardState.appearance_for(hero)
	var key := key_for(hero, look)
	if _cache.has(key): return _cache[key]
	var path := CACHE_DIR.path_join(key + ".png")
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_cache[key] = tex
			return tex
	if not can_shoot(): return null
	if not _waiting.has(key):
		_waiting[key] = []
		_queue.append([key, hero.duplicate(true), look])
	(_waiting[key] as Array).append(done)
	_pump()
	return null

func _pump() -> void:
	if _busy or _queue.is_empty(): return
	_busy = true
	_shoot.call_deferred()

func _setup() -> void:
	if _vp != null: return
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b4b9d6")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	# luce principale da davanti in alto a destra, riempimento freddo da sinistra
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-28, 28, 0)
	key_light.light_energy = 1.25
	key_light.light_color = Color("#fff3e2")
	_world.add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -60, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("#a9b8ff")
	_world.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 18.0
	_world.add_child(_cam)
	_cam.current = true

func _shoot() -> void:
	var job: Array = _queue.pop_front()
	var key: String = job[0]
	var hero: Dictionary = job[1]
	var look: Dictionary = job[2]
	_setup()
	var model := CharacterModel.new()
	model.outline_px = 2.4
	_world.add_child(model)
	model.build_hero(hero, look)
	model.use_clips = false
	model.play("idle")
	model.update_animation(0.0)
	model.rotation.y = 0.32
	# mezzo busto: testa nel terzo alto, spalle e petto sotto
	var head_y: float = model.head.global_position.y + 0.07
	_cam.position = Vector3(0.0, head_y + 0.02, 1.12)
	_cam.look_at(Vector3(0.0, head_y - 0.075, 0.0))
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	model.queue_free()
	var tex: Texture2D = null
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
		_cache[key] = tex
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		img.save_png(CACHE_DIR.path_join(key + ".png"))
	for done in _waiting.get(key, []):
		if (done as Callable).is_valid(): (done as Callable).call(tex)
	_waiting.erase(key)
	_busy = false
	_pump()
