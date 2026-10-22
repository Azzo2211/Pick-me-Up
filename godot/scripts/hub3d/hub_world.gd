extends Node3D
class_name HubWorld

## La base fisica: un'isola sospesa con piazza aperta, strutture, sentieri,
## vegetazione ed eroi che vivono il posto. Tutto è generato in codice
## e si aggiorna quando cambiano livello base, strutture o roster.

signal building_clicked(id: String)
signal hero_clicked(hero_id: String)

const BuildingModelScript := preload("res://scripts/hub3d/building_model.gd")
const WaterShader := preload("res://scripts/hub3d/water.gdshader")
const HubAgentScript := preload("res://scripts/hub3d/hub_agent.gd")

const PLAZA_RADIUS := 4.6
const POND := Vector2(11.6, 7.6)
const POND_RADIUS := 1.7
const MAX_AGENTS := 30
const GATE_PLATFORM := Vector3(15.2, 1.4, -15.6)

## Posizione e orientamento dei siti delle strutture (XZ, rotazione verso la piazza).
const SITES := {
	"training": Vector2(-7.6, -6.8),
	"dormitory": Vector2(-10.6, 1.4),
	"merging": Vector2(6.4, 7.2),
	"gate": Vector2(15.2, -15.6),
	"armory": Vector2(10.6, 0.6),
	"warehouse": Vector2(-8.4, 8.4),
	"workshop": Vector2(-0.6, 10.8),
	"alchemy": Vector2(1.6, -10.6),
}
const SITE_RADIUS := {"training": 4.6, "dormitory": 4.0, "merging": 3.8, "armory": 3.8, "warehouse": 3.8, "workshop": 3.4, "alchemy": 3.2, "gate": 0.0}

var rng := RandomNumberGenerator.new()
var camera: Camera3D
var sun: DirectionalLight3D
var terrain_root: Node3D
var path_root: Node3D
var veg_root: Node3D
var decor_root: Node3D
var building_root: Node3D
var agent_root: Node3D
var fx_root: Node3D

var buildings: Dictionary = {}          # id -> BuildingModel
var building_states: Dictionary = {}    # id -> "built:2" / "plot" / ""
var labels: Dictionary = {}             # id -> Label3D
var sublabels: Dictionary = {}          # id -> Label3D
var badges: Dictionary = {}             # id -> Node3D
var agents: Dictionary = {}             # hero_id -> HubAgent
var crystal: Node3D
var crystal_core: MeshInstance3D
var paths: Dictionary = {}              # id -> Array[Vector3]
var nav := AStar3D.new()
var nav_points: Dictionary = {}         # key -> point id
var plaza_nodes: Array[int] = []
var wander_nodes: Array[int] = []
var site_nodes: Dictionary = {}         # id -> {"door": int, "spots": Array[int]}
var tree_spots: Array[Vector3] = []
var shadow_spots: Array[Vector3] = []
var water_segments: Array = []
var current_base_level := -1
var occupied_signature := ""
var hovered_id := ""
var selected_id := ""
var time := 0.0
var clouds: Array[Node3D] = []
var islets: Array[Node3D] = []

func _ready() -> void:
	rng.seed = 424242
	_build_environment()
	terrain_root = _group("Terrain")
	path_root = _group("Paths")
	veg_root = _group("Vegetation")
	decor_root = _group("Decor")
	building_root = _group("Buildings")
	agent_root = _group("Agents")
	fx_root = _group("Fx")
	_build_island()
	_build_water()
	_build_gate_platform()
	_build_plaza()
	_build_sky_dressing()

func _group(name_text: String) -> Node3D:
	var n := Node3D.new()
	n.name = name_text
	add_child(n)
	return n

# =============================================================================
# Ambiente
# =============================================================================

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#4c9be8")
	sky_mat.sky_horizon_color = Color("#bfe2ff")
	sky_mat.ground_bottom_color = Color("#6fb2ec")
	sky_mat.ground_horizon_color = Color("#c4e4ff")
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color("#fff3df")
	sun.light_energy = 0.75
	# Ombre "blob" sotto alberi, eroi ed edifici: resa identica su ogni scheda video.
	sun.shadow_enabled = false
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 140, 0)
	fill.light_color = Color("#bcd8ff")
	fill.light_energy = 0.22
	add_child(fill)

# =============================================================================
# Isola
# =============================================================================

func island_radius(angle: float) -> float:
	return 16.2 + 0.9 * sin(2.0 * angle + 0.6) + 0.7 * sin(3.0 * angle + 1.9) + 0.45 * sin(5.0 * angle + 0.3) + 0.25 * sin(9.0 * angle + 2.0)

func is_on_island(p: Vector2, margin: float = 0.0) -> bool:
	return p.length() < island_radius(atan2(p.y, p.x)) - margin

func _build_island() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 120
	var rings := 9
	var grass_a := Color("#7cc65a")
	var grass_b := Color("#93d468")
	var grass_c := Color("#6bb84f")
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	# Superficie superiore
	var top: Array = []
	for k in rings + 1:
		var row: Array[Vector3] = []
		var f := float(k) / rings
		for s in segments:
			var a := TAU * s / segments
			var r := island_radius(a) * f
			var y := 0.0
			if f > 0.86: y = -pow((f - 0.86) / 0.14, 2.0) * 0.35
			row.append(Vector3(cos(a) * r, y, sin(a) * r))
		top.append(row)
	for k in rings:
		for s in segments:
			var s2 := (s + 1) % segments
			var a0: Vector3 = top[k][s]; var a1: Vector3 = top[k][s2]
			var b0: Vector3 = top[k + 1][s]; var b1: Vector3 = top[k + 1][s2]
			var c1 := _grass_color(noise, (a0 + b1) * 0.5, grass_a, grass_b, grass_c)
			var c2 := _grass_color(noise, (a1 + b0) * 0.5 + Vector3(0.3, 0, 0.3), grass_a, grass_b, grass_c)
			if k == 0:
				_tri(st, a0, b1, b0, c1)
			else:
				_tri(st, a0, b1, b0, c1)
				_tri(st, a0, a1, b1, c2)
	# Scogliera sotto l'isola: strati di roccia che si stringono verso il basso
	var edge: Array[Vector3] = top[rings]
	var layers := 7
	var prev := edge
	var rock_colors := [Color("#8b6b4d"), Color("#a3876a"), Color("#9a8a78"), Color("#8a7d70"), Color("#7b7068"), Color("#6c625c"), Color("#5e5652")]
	for l in range(1, layers + 1):
		var t := float(l) / layers
		var row: Array[Vector3] = []
		for s in segments:
			var a := TAU * s / segments
			var base_r := island_radius(a) * (1.0 - pow(t, 1.25) * 0.93)
			var jitter := noise.get_noise_2d(a * 20.0, l * 3.0) * 1.3 * (1.0 - t * 0.4)
			var y := -0.35 - t * 15.0 + noise.get_noise_2d(a * 9.0, l * 5.0) * 1.4 * t
			row.append(Vector3(cos(a) * (base_r + jitter), y, sin(a) * (base_r + jitter)))
		for s in segments:
			var s2 := (s + 1) % segments
			var col: Color = rock_colors[l - 1].lerp(Color("#b59a7c"), 0.15 * noise.get_noise_2d(s * 3.0, l * 7.0) + 0.1)
			if l == 1: col = Color("#6f9f45") if s % 3 != 0 else Color("#7a5a3e")
			_tri(st, prev[s], prev[s2], row[s2], col)
			_tri(st, prev[s], row[s2], row[s], col.darkened(0.06))
		prev = row
	var bottom := Vector3(0.5, -19.0, -0.4)
	for s in segments:
		_tri(st, prev[s], prev[(s + 1) % segments], bottom, Color("#544c49"))
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh.material_override = m
	terrain_root.add_child(mesh)

func _grass_color(noise: FastNoiseLite, p: Vector3, a: Color, b: Color, c: Color) -> Color:
	var n := noise.get_noise_2d(p.x, p.z)
	var col := a.lerp(b, clampf(n * 0.5 + 0.5, 0.0, 1.0))
	if n < -0.35: col = col.lerp(c, 0.6)
	return col

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0.0 and absf(normal.y) > 0.5:
		var tmp := b; b = c; c = tmp
		normal = -normal
	# Godot considera frontali i triangoli in senso orario rispetto alla normale.
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_normal(normal)
	st.add_vertex(b)

func _water_material(speed: float, stripes: float, alpha: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WaterShader
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("stripes", stripes)
	m.set_shader_parameter("alpha", alpha)
	return m

## Laghetto con ruscello che cade dal bordo dell'isola.
func _build_water() -> void:
	var kit := MeshKit.new(terrain_root)
	var pond_pos := Vector3(POND.x, 0.0, POND.y)
	kit.cyl(POND_RADIUS + 0.35, POND_RADIUS + 0.45, 0.1, Color("#c9b98f"), pond_pos + Vector3(0, 0.02, 0), 18)
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = POND_RADIUS
	disc.bottom_radius = POND_RADIUS
	disc.height = 0.06
	disc.radial_segments = 24
	water.mesh = disc
	water.material_override = _water_material(0.4, 3.0, 0.92)
	water.position = pond_pos + Vector3(0, 0.08, 0)
	terrain_root.add_child(water)
	for i in 9:
		var a := TAU * i / 9.0 + 0.2
		kit.rock(0.28 + (i % 3) * 0.06, Color("#b9b0a2"), pond_pos + Vector3(cos(a), 0, sin(a)) * (POND_RADIUS + 0.35) + Vector3(0, 0.12, 0), 60 + i)
	for i in 3:
		kit.sphere(0.22, Color("#7fca5a"), pond_pos + Vector3(-0.6 + i * 0.6, 0.12, 0.3 - i * 0.4), Vector3(1.2, 0.25, 1.2), 8)
	# Ruscello verso il bordo
	var dir := POND.normalized()
	var angle := atan2(dir.y, dir.x)
	var edge := dir * (island_radius(angle) - 0.25)
	var start := POND + dir * (POND_RADIUS - 0.3)
	var length := start.distance_to(edge)
	var stream := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, length)
	stream.mesh = quad
	stream.material_override = _water_material(1.6, length * 1.5, 0.95)
	var mid := (start + edge) * 0.5
	stream.position = Vector3(mid.x, 0.07, mid.y)
	stream.rotation = Vector3(-PI / 2, atan2(-dir.x, -dir.y), 0)
	terrain_root.add_child(stream)
	# Cascata lungo la scogliera
	var fall := MeshInstance3D.new()
	var fall_quad := QuadMesh.new()
	fall_quad.size = Vector2(1.0, 11.0)
	fall.mesh = fall_quad
	fall.material_override = _water_material(2.4, 9.0, 0.85)
	var outward := Vector3(dir.x, 0, dir.y)
	fall.position = Vector3(edge.x, -5.4, edge.y) + outward * 1.1
	fall.rotation = Vector3(-0.18, atan2(dir.x, dir.y), 0)
	terrain_root.add_child(fall)
	var mist := CPUParticles3D.new()
	mist.position = Vector3(edge.x, -10.5, edge.y) + outward * 2.0
	mist.amount = 14
	mist.lifetime = 2.2
	mist.direction = Vector3.UP
	mist.spread = 60.0
	mist.initial_velocity_min = 0.3
	mist.initial_velocity_max = 0.8
	mist.gravity = Vector3.ZERO
	mist.scale_amount_min = 1.0
	mist.scale_amount_max = 2.0
	var puff := SphereMesh.new(); puff.radius = 0.35; puff.height = 0.7; puff.radial_segments = 6; puff.rings = 3
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(1, 1, 1, 0.55)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = pm
	mist.mesh = puff
	terrain_root.add_child(mist)
	water_segments = [[start, edge]]

func _build_gate_platform() -> void:
	var kit := MeshKit.new(terrain_root)
	var p := GATE_PLATFORM
	# Zolla sospesa con fondo roccioso
	kit.cyl(4.7, 4.9, 0.5, Color("#86c45f"), p + Vector3(0, -0.25, 0), 18)
	kit.cyl(4.9, 3.2, 1.6, Color("#9a826a"), p + Vector3(0, -1.3, 0), 14)
	kit.cyl(3.2, 0.4, 3.6, Color("#7e6f63"), p + Vector3(0, -3.9, 0), 10)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		kit.rock(0.5, Color("#b0a493"), p + Vector3(cos(a) * 4.3, 0.0, sin(a) * 4.3), i + 40)
	# Ponte di pietra dal bordo dell'isola al portale, leggermente in salita
	var start := Vector3(9.6, 0.0, -9.9)
	var finish := p + Vector3(-2.9, 0.0, 3.0)
	finish.y = p.y
	var pieces := 12
	for i in pieces:
		var t := (i + 0.5) / pieces
		var pos := start.lerp(finish, t)
		pos.y = lerpf(start.y, finish.y, t) + sin(t * PI) * 0.35 - 0.12
		var dir := (finish - start).normalized()
		var yaw := atan2(dir.x, dir.z)
		kit.box(Vector3(1.9, 0.26, 0.92), Color("#d8cfbd") if i % 2 == 0 else Color("#cfc5b1"), pos, Vector3(0, yaw, 0))
		for side in [-1.0, 1.0]:
			var off: Vector3 = Vector3(cos(yaw), 0, -sin(yaw)) * 0.98 * float(side)
			kit.box(Vector3(0.18, 0.34, 0.92), Color("#b8ad99"), pos + off + Vector3(0, 0.18, 0), Vector3(0, yaw, 0))
	for i in 3:
		var t := 0.25 + i * 0.25
		var under := start.lerp(finish, t) + Vector3(0, -1.6 - i * 0.3, 0)
		var stone := kit.box(Vector3(0.6, 0.9, 0.5), Color("#b49cff"), under, Vector3(0.3, i, 0.2), 0.8)
		stone.set_meta("bob", under.y)
		islets.append(stone)
	paths["gate_bridge"] = [start, start.lerp(finish, 0.5) + Vector3(0, 0.25, 0), finish, p + Vector3(0, 0, 1.0)]

# =============================================================================
# Piazza e cristallo del Nexus
# =============================================================================

func _build_plaza() -> void:
	var kit := MeshKit.new(decor_root)
	kit.cyl(PLAZA_RADIUS, PLAZA_RADIUS + 0.15, 0.14, Color("#e2d3b6"), Vector3(0, 0.05, 0), 40)
	kit.cyl(PLAZA_RADIUS - 0.5, PLAZA_RADIUS - 0.5, 0.15, Color("#cdb994"), Vector3(0, 0.06, 0), 40)
	kit.cyl(PLAZA_RADIUS - 0.8, PLAZA_RADIUS - 0.8, 0.16, Color("#e9dcc2"), Vector3(0, 0.065, 0), 40)
	for i in 8:
		var a := TAU * i / 8.0
		kit.box(Vector3(0.18, 0.02, 2.4), Color("#cdbfa4"), Vector3(cos(a) * 2.0, 0.15, sin(a) * 2.0), Vector3(0, -a + PI / 2, 0))
	kit.cyl(1.0, 1.15, 0.45, Color("#e1d8c5"), Vector3(0, 0.3, 0), 16)
	kit.torus(0.95, 1.1, Color("#e0a93b"), Vector3(0, 0.53, 0), Vector3.ZERO, 0.3, 24)
	crystal = Node3D.new()
	crystal.position = Vector3(0, 2.0, 0)
	decor_root.add_child(crystal)
	var ckit := MeshKit.new(crystal)
	crystal_core = ckit.cyl(0.0, 0.75, 1.5, Color("#2fc0ff"), Vector3(0, 0.75, 0), 6, Vector3.ZERO, 1.2)
	ckit.cyl(0.75, 0.0, 1.1, Color("#2fc0ff"), Vector3(0, -0.55, 0), 6, Vector3.ZERO, 1.2)
	for i in 3:
		var shard := ckit.cyl(0.0, 0.12, 0.38, Color("#a6ecff"), Vector3.ZERO, 4, Vector3.ZERO, 2.4)
		shard.set_meta("angle", TAU * i / 3.0)
	var light := OmniLight3D.new()
	light.light_color = Color("#7fdcff")
	light.light_energy = 1.6
	light.omni_range = 7.0
	crystal.add_child(light)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.set_meta("facility_id", "crystal")
	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = 1.3
	cyl_shape.height = 3.6
	shape.shape = cyl_shape
	shape.position = Vector3(0, -0.2, 0)
	body.add_child(shape)
	crystal.add_child(body)
	_make_label("crystal", Vector3(0, 4.1, 0), "Cristallo del Nexus")

# =============================================================================
# Aggiornamento dallo stato di gioco
# =============================================================================

func refresh(state: RiftwardState) -> void:
	var base_level := state.base_level()
	var signature := ""
	for id in SITES:
		var status := ""
		if state.facility_built(id): status = "built:%d" % state.facility_level(id)
		elif state.facility_available(id): status = "plot"
		signature += id + "=" + status + ";"
		if building_states.get(id, "") != status:
			_place_building(id, status, base_level)
			building_states[id] = status
	var layout_changed := signature != occupied_signature or base_level != current_base_level
	if layout_changed:
		occupied_signature = signature
		current_base_level = base_level
		_build_paths(state)
		_build_vegetation()
		_build_decor(base_level)
		_build_navigation()
		for agent in agents.values(): agent.reset_route()
	_update_labels(state)
	_sync_agents(state)

func _site_position(id: String) -> Vector3:
	var s: Vector2 = SITES[id]
	if id == "gate": return GATE_PLATFORM
	return Vector3(s.x, 0.0, s.y)

func _site_yaw(id: String) -> float:
	if id == "gate": return -0.35
	var p := _site_position(id)
	return atan2(-p.x, -p.z)

func _place_building(id: String, status: String, base_level: int) -> void:
	if buildings.has(id):
		buildings[id].queue_free()
		buildings.erase(id)
	if status.is_empty():
		_set_label_visible(id, false)
		return
	var model: BuildingModel = BuildingModelScript.new()
	var level := int(status.split(":")[1]) if status.begins_with("built") else 0
	model.build("plot" if status == "plot" else id, level, base_level)
	model.facility_id = id
	for child in model.get_children():
		if child is StaticBody3D: child.set_meta("facility_id", id)
	model.position = _site_position(id)
	model.rotation.y = _site_yaw(id)
	if id == "gate" and status != "plot": model.scale = Vector3.ONE * 1.25
	building_root.add_child(model)
	buildings[id] = model
	_spawn_puff(model.position + Vector3(0, 1.0, 0))
	var label_y := model.top_height + 0.7
	if not labels.has(id): _make_label(id, Vector3.ZERO, "")
	labels[id].position = model.position + Vector3(0, label_y, 0)
	sublabels[id].position = labels[id].position + Vector3(0, -0.01, 0)
	badges[id].position = labels[id].position
	_set_label_visible(id, true)

func _make_label(id: String, pos: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.font = UIKit.head_font()
	label.font_size = 26
	label.outline_size = 12
	label.outline_modulate = Color("#1a2342")
	label.modulate = Color.WHITE
	label.pixel_size = 0.0007
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 2
	label.outline_render_priority = 1
	label.position = pos
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	fx_root.add_child(label)
	labels[id] = label
	var sub := Label3D.new()
	sub.font = UIKit.body_bold()
	sub.font_size = 17
	sub.outline_size = 9
	sub.outline_modulate = Color("#1a2342")
	sub.modulate = Color("#ffe39a")
	sub.pixel_size = 0.0007
	sub.fixed_size = true
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.no_depth_test = true
	sub.render_priority = 2
	sub.outline_render_priority = 1
	sub.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	sub.position = pos + Vector3(0, -0.01, 0)
	fx_root.add_child(sub)
	sublabels[id] = sub
	var badge := Sprite3D.new()
	badge.texture = MeshKit.circle_texture(48, Color("#ff4d6a"), Color.WHITE, 4.0)
	badge.pixel_size = 0.0006
	badge.fixed_size = true
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.render_priority = 3
	badge.position = pos
	badge.offset = Vector2(-140, 18)
	var mark := Label3D.new()
	mark.text = "!"
	mark.font = UIKit.head_font()
	mark.font_size = 32
	mark.pixel_size = 0.0006
	mark.fixed_size = true
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.render_priority = 4
	mark.outline_size = 0
	mark.offset = Vector2(-140, 20)
	badge.add_child(mark)
	badge.visible = false
	fx_root.add_child(badge)
	badges[id] = badge

## Il bollino rosso sta a sinistra del nome, così non finisce mai sotto l'HUD in alto.
func _place_badge(id: String) -> void:
	var label: Label3D = labels[id]
	var width := UIKit.head_font().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	var px := width * label.pixel_size / 0.0006 * 0.5 + 34.0
	badges[id].offset = Vector2(-px, 18)
	(badges[id].get_child(0) as Label3D).offset = Vector2(-px, 20)

func _set_label_visible(id: String, value: bool) -> void:
	if labels.has(id):
		labels[id].visible = value
		sublabels[id].visible = value
		if not value: badges[id].visible = false

func _update_labels(state: RiftwardState) -> void:
	for id in labels:
		if id == "crystal":
			sublabels[id].text = "Evocazione · Base Lv.%d" % state.base_level()
			badges[id].visible = state.can_upgrade_base().ok
			continue
		var status: String = building_states.get(id, "")
		if status.is_empty(): continue
		var info: Dictionary = state.FACILITIES[id]
		if status == "plot":
			labels[id].text = "Cantiere: " + str(info.short)
			sublabels[id].text = "Costruisci · %s Oro" % state.format_number(info.build_cost)
			badges[id].visible = state.can_afford({"gold": int(info.build_cost)})
			continue
		labels[id].text = str(info.short)
		var line := "Lv.%d" % state.facility_level(id)
		var alert := false
		match id:
			"training":
				line += "  ·  in allenamento %d/%d" % [state.assigned_to("training").size(), state.training_slots()]
				alert = state.assigned_to("training").size() < state.training_slots() and _has_trainable(state)
			"dormitory":
				line += "  ·  a riposo %d/%d" % [state.assigned_to("dormitory").size(), state.dormitory_slots()]
				alert = _has_tired(state)
			"merging":
				alert = _has_promotable(state)
			"gate":
				line += "  ·  Piano %d" % int(state.data.world.current_floor)
				alert = state.party_readiness().ready
		sublabels[id].text = line
		badges[id].visible = alert
	for id in badges:
		if badges[id].visible: _place_badge(id)

func _has_trainable(state: RiftwardState) -> bool:
	for hero in state.get_alive_heroes():
		if state.hero_activity(hero) == "idle" and int(hero.level) < state.level_cap(hero) and hero.injuries.is_empty() and int(hero.fatigue) < 60: return true
	return false

func _has_tired(state: RiftwardState) -> bool:
	for hero in state.get_alive_heroes():
		if state.data.assignments.has(hero.id): continue
		if not hero.injuries.is_empty() or int(hero.fatigue) >= 60: return true
	return false

func _has_promotable(state: RiftwardState) -> bool:
	for hero in state.get_alive_heroes():
		if state.promotion_requirements(hero).ok: return true
	return false

# =============================================================================
# Sentieri, vegetazione, decorazioni
# =============================================================================

func _path_target(id: String) -> Vector3:
	if id == "gate": return (paths["gate_bridge"][0] as Vector3)
	var model: BuildingModel = buildings.get(id)
	if model == null: return _site_position(id)
	return model.to_global(model.door_local) if model.is_inside_tree() else model.position + model.door_local.rotated(Vector3.UP, model.rotation.y)

func _build_paths(state: RiftwardState) -> void:
	UIKit.clear(path_root)
	var gate_bridge: Array = paths.get("gate_bridge", [])
	paths.clear()
	paths["gate_bridge"] = gate_bridge
	var stone := state.base_level() >= 3
	var color := Color("#d6ccb9") if stone else Color("#dcc596")
	var edge := Color("#c8bda6") if stone else Color("#c9ae7c")
	for id in SITES:
		if not buildings.has(id) and id != "gate": continue
		var target := _path_target(id)
		var dir := Vector3(target.x, 0, target.z).normalized()
		var start := dir * (PLAZA_RADIUS - 0.2)
		var mid := (start + Vector3(target.x, 0, target.z)) * 0.5
		var side := Vector3(-dir.z, 0, dir.x) * (0.9 if int(abs(id.hash())) % 2 == 0 else -0.9)
		var points: Array[Vector3] = []
		var samples := maxi(4, int(start.distance_to(target) / 1.1))
		for i in samples + 1:
			var t := float(i) / samples
			var p := start.lerp(mid + side, t).lerp((mid + side).lerp(Vector3(target.x, 0, target.z), t), t)
			p.y = 0.0
			points.append(p)
		paths[id] = points
		_ribbon(points, 1.45, edge, 0.02)
		_ribbon(points, 1.15, color, 0.03)
	_ribbon(paths["gate_bridge"].slice(0, 1) + [(paths["gate_bridge"][0] as Vector3) + Vector3(-0.6, 0, 0.6)], 1.4, color, 0.03)

func _ribbon(points: Array, width: float, color: Color, y: float) -> void:
	if points.size() < 2: return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in points.size():
		var p: Vector3 = points[i]
		var a: Vector3 = points[maxi(0, i - 1)]
		var b: Vector3 = points[mini(points.size() - 1, i + 1)]
		var d := (b - a); d.y = 0.0; d = d.normalized()
		var n := Vector3(-d.z, 0, d.x) * width * 0.5
		lefts.append(Vector3(p.x, y, p.z) + n)
		rights.append(Vector3(p.x, y, p.z) - n)
	for i in points.size() - 1:
		for tri in [[lefts[i], rights[i], lefts[i + 1]], [rights[i], rights[i + 1], lefts[i + 1]]]:
			for v in tri:
				st.set_normal(Vector3.UP)
				st.set_color(color)
				st.add_vertex(v)
	# tappi circolari alle estremità
	for end in [points[0], points[points.size() - 1]]:
		var c := Vector3(end.x, y, end.z)
		for s in 10:
			var a0 := TAU * s / 10.0
			var a1 := TAU * (s + 1) / 10.0
			for v in [c, c + Vector3(cos(a1), 0, sin(a1)) * width * 0.5, c + Vector3(cos(a0), 0, sin(a0)) * width * 0.5]:
				st.set_normal(Vector3.UP)
				st.set_color(color)
				st.add_vertex(v)
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh.material_override = m
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_root.add_child(mesh)

func _blocked(p: Vector2, clearance: float) -> bool:
	if p.length() < PLAZA_RADIUS + 1.4 + clearance: return true
	if p.distance_to(POND) < POND_RADIUS + 0.6 + clearance: return true
	for seg in water_segments:
		if Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) < 0.8 + clearance: return true
	for id in SITES:
		if id == "gate": continue
		if buildings.has(id) and p.distance_to(SITES[id]) < float(SITE_RADIUS[id]) + clearance: return true
	for key in paths:
		var pts: Array = paths[key]
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < 1.15 + clearance: return true
	return false

func _build_vegetation() -> void:
	UIKit.clear(veg_root)
	tree_spots.clear()
	shadow_spots.clear()
	for id in buildings:
		var model: BuildingModel = buildings[id]
		if id == "gate": continue
		shadow_spots.append(Vector3(model.position.x + 0.5, maxf(model.footprint.x, model.footprint.z) * 0.62, model.position.z + 0.4))
	var r := RandomNumberGenerator.new()
	r.seed = 9182
	var kit := MeshKit.new(veg_root)
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < 86 and attempts < 4000:
		attempts += 1
		var a := r.randf_range(0, TAU)
		var edge_bias := pow(r.randf(), 0.55)
		var dist := edge_bias * (island_radius(a) - 1.3)
		var p := Vector2(cos(a), sin(a)) * dist
		if not is_on_island(p, 1.1): continue
		if _blocked(p, 0.9): continue
		var too_close := false
		for q in placed:
			if q.distance_to(p) < 1.6:
				too_close = true
				break
		if too_close: continue
		placed.append(p)
		var kind := r.randf()
		var scale := r.randf_range(0.8, 1.3)
		var pos := Vector3(p.x, 0.0, p.y)
		if kind < 0.55: _tree_round(kit, pos, scale, r)
		elif kind < 0.82: _tree_pine(kit, pos, scale, r)
		else: _tree_blossom(kit, pos, scale, r)
		tree_spots.append(pos)
		shadow_spots.append(Vector3(pos.x + 0.25, scale * 1.25, pos.z + 0.2))
	# Cespugli e rocce
	for i in 70:
		var a := r.randf_range(0, TAU)
		var dist := r.randf_range(PLAZA_RADIUS + 1.0, island_radius(a) - 0.8)
		var p := Vector2(cos(a), sin(a)) * dist
		if _blocked(p, -0.4): continue
		var pos := Vector3(p.x, 0.0, p.y)
		if i % 6 == 0:
			kit.rock(r.randf_range(0.25, 0.5), Color("#b9b0a2"), pos + Vector3(0, 0.12, 0), i)
		else:
			var green := Color("#5fae4a").lerp(Color("#7fca5a"), r.randf())
			kit.sphere(r.randf_range(0.35, 0.55), green, pos + Vector3(0, 0.25, 0), Vector3(1.2, 0.8, 1.0), 8)
			kit.sphere(r.randf_range(0.25, 0.4), green.lightened(0.08), pos + Vector3(0.35, 0.2, 0.15), Vector3(1.1, 0.8, 1.0), 8)
			if r.randf() < 0.4: kit.sphere(0.07, [Color("#ff7fa3"), Color("#fff2a6"), Color("#ffffff")][i % 3], pos + Vector3(0.1, 0.55, 0.2), Vector3.ONE, 6)
	_build_flowers(r)
	_build_blob_shadows()

func _build_blob_shadows() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = MeshKit.soft_texture(64, Color(0.05, 0.12, 0.05, 0.55))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = shadow_spots.size()
	for i in shadow_spots.size():
		var spot: Vector3 = shadow_spots[i]
		var basis := Basis(Vector3.RIGHT, -PI / 2).scaled(Vector3(spot.y, spot.y, spot.y))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(spot.x, 0.04, spot.z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	veg_root.add_child(mmi)

func _tree_round(kit: MeshKit, pos: Vector3, s: float, r: RandomNumberGenerator) -> void:
	kit.cyl(0.13 * s, 0.2 * s, 1.3 * s, Color("#8a5a35"), pos + Vector3(0, 0.65 * s, 0), 7)
	var green := Color("#4fa94a").lerp(Color("#76c757"), r.randf())
	kit.sphere(0.95 * s, green, pos + Vector3(0, 1.75 * s, 0), Vector3(1, 0.9, 1), 10)
	kit.sphere(0.65 * s, green.lightened(0.1), pos + Vector3(0.45 * s, 2.15 * s, 0.25 * s), Vector3.ONE, 9)
	kit.sphere(0.6 * s, green.darkened(0.08), pos + Vector3(-0.5 * s, 1.5 * s, -0.2 * s), Vector3.ONE, 9)

func _tree_pine(kit: MeshKit, pos: Vector3, s: float, r: RandomNumberGenerator) -> void:
	kit.cyl(0.12 * s, 0.17 * s, 0.8 * s, Color("#7a4d2d"), pos + Vector3(0, 0.4 * s, 0), 6)
	var green := Color("#2f8f5a").lerp(Color("#49a868"), r.randf())
	for i in 3:
		kit.cone((1.05 - i * 0.28) * s, (1.25 - i * 0.15) * s, green.lightened(i * 0.06), pos + Vector3(0, (1.1 + i * 0.75) * s, 0), 8)

func _tree_blossom(kit: MeshKit, pos: Vector3, s: float, r: RandomNumberGenerator) -> void:
	kit.cyl(0.12 * s, 0.18 * s, 1.2 * s, Color("#7b4b3a"), pos + Vector3(0, 0.6 * s, 0), 7)
	var pink := Color("#ffb3cf").lerp(Color("#ff8fb8"), r.randf())
	kit.sphere(0.9 * s, pink, pos + Vector3(0, 1.7 * s, 0), Vector3(1.1, 0.85, 1.1), 10)
	kit.sphere(0.55 * s, pink.lightened(0.12), pos + Vector3(0.4 * s, 2.05 * s, -0.2 * s), Vector3.ONE, 9)

func _build_flowers(r: RandomNumberGenerator) -> void:
	var colors := [Color("#ff6f91"), Color("#ffd166"), Color("#ffffff"), Color("#c77dff"), Color("#7ad7ff"), Color("#ff9f43")]
	var transforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var tufts: Array[Transform3D] = []
	for i in 900:
		var a := r.randf_range(0, TAU)
		var dist := sqrt(r.randf()) * (island_radius(a) - 0.6)
		var p := Vector2(cos(a), sin(a)) * dist
		if _blocked(p, -0.7): continue
		var cluster := (int(abs(p.x * 3.0)) + int(abs(p.y * 2.0))) % 5 == 0
		if cluster or i % 4 == 0:
			transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r.randf_range(0.7, 1.2)), Vector3(p.x, 0.08, p.y)))
			tints.append(colors[(i + int(p.x)) % colors.size()])
		else:
			tufts.append(Transform3D(Basis(Vector3.UP, r.randf_range(0, TAU)).scaled(Vector3.ONE * r.randf_range(0.7, 1.3)), Vector3(p.x, 0.0, p.y)))
	var flower_mesh := SphereMesh.new()
	flower_mesh.radius = 0.08
	flower_mesh.height = 0.12
	flower_mesh.radial_segments = 6
	flower_mesh.rings = 3
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.vertex_color_is_srgb = true
	fm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	fm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	flower_mesh.material = fm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = flower_mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	veg_root.add_child(mmi)
	var tuft_mesh := CylinderMesh.new()
	tuft_mesh.top_radius = 0.0
	tuft_mesh.bottom_radius = 0.09
	tuft_mesh.height = 0.32
	tuft_mesh.radial_segments = 4
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("#5aa844")
	tm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	tm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	tuft_mesh.material = tm
	var tmm := MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.mesh = tuft_mesh
	tmm.instance_count = tufts.size()
	for i in tufts.size(): tmm.set_instance_transform(i, tufts[i].translated_local(Vector3(0, 0.14, 0)))
	var tmmi := MultiMeshInstance3D.new()
	tmmi.multimesh = tmm
	tmmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	veg_root.add_child(tmmi)

func _build_decor(base_level: int) -> void:
	for child in decor_root.get_children():
		if child.has_meta("decor"):
			decor_root.remove_child(child)
			child.queue_free()
	var holder := Node3D.new()
	holder.set_meta("decor", true)
	decor_root.add_child(holder)
	var kit := MeshKit.new(holder)
	# Panchine attorno alla piazza (sempre presenti)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0 + 0.35
		var pos := Vector3(cos(a), 0, sin(a)) * (PLAZA_RADIUS - 0.75)
		var bench := Node3D.new(); bench.position = pos; bench.rotation.y = atan2(-pos.x, -pos.z); holder.add_child(bench)
		kit.box(Vector3(1.1, 0.08, 0.35), Color("#9a6a40"), Vector3(0, 0.42, 0), Vector3.ZERO, 0.0, bench)
		kit.box(Vector3(1.1, 0.3, 0.06), Color("#9a6a40"), Vector3(0, 0.62, -0.16), Vector3.ZERO, 0.0, bench)
		for sx in [-0.45, 0.45]: kit.box(Vector3(0.08, 0.42, 0.3), Color("#6e4a2c"), Vector3(sx, 0.21, 0), Vector3.ZERO, 0.0, bench)
	if base_level >= 2:
		for key in paths:
			if key == "gate_bridge": continue
			var pts: Array = paths[key]
			if pts.size() < 4: continue
			var p: Vector3 = pts[pts.size() / 2]
			var q: Vector3 = pts[pts.size() / 2 + 1]
			var side := Vector3(-(q - p).normalized().z, 0, (q - p).normalized().x) * 1.0
			_lamp(kit, p + side)
		for i in 6:
			var a := TAU * i / 6.0
			var pos := Vector3(cos(a), 0, sin(a)) * (PLAZA_RADIUS + 0.5)
			if _blocked(Vector2(pos.x, pos.z), -1.4) and Vector2(pos.x, pos.z).length() > PLAZA_RADIUS + 0.9: continue
			kit.cyl(0.42, 0.48, 0.3, Color("#cfc4ae"), pos + Vector3(0, 0.15, 0), 10)
			for j in 5: kit.sphere(0.12, [Color("#ff6f91"), Color("#ffd166"), Color("#c77dff"), Color("#ffffff"), Color("#ff9f43")][(i + j) % 5], pos + Vector3(cos(j * 1.3) * 0.25, 0.38, sin(j * 1.3) * 0.25), Vector3.ONE, 6)
	if base_level >= 3:
		for i in 4:
			var a := TAU * i / 4.0
			var pos := Vector3(cos(a), 0, sin(a)) * (PLAZA_RADIUS - 0.25)
			kit.cyl(0.05, 0.05, 3.0, Color("#6e4a2c"), pos + Vector3(0, 1.5, 0), 6)
			kit.box(Vector3(0.05, 1.0, 0.6), Color("#21a99b") if i % 2 == 0 else Color("#e0a93b"), pos + Vector3(0, 2.4, 0.3), Vector3(0, a, 0))
	if base_level >= 4:
		kit.torus(PLAZA_RADIUS - 1.6, PLAZA_RADIUS - 1.35, Color("#7fd8ff"), Vector3(0, 0.16, 0), Vector3.ZERO, 1.4, 48)
	if base_level >= 5:
		for i in 8:
			var a := TAU * i / 8.0
			var lantern := kit.sphere(0.16, Color("#ffd27a"), Vector3(cos(a) * 3.0, 4.0 + (i % 3) * 0.5, sin(a) * 3.0), Vector3(1, 1.3, 1), 8, 2.5)
			lantern.set_meta("bob", lantern.position.y)
			islets.append(lantern)

func _lamp(kit: MeshKit, pos: Vector3) -> void:
	kit.cyl(0.05, 0.07, 1.8, Color("#3e4a5c"), pos + Vector3(0, 0.9, 0), 6)
	kit.sphere(0.16, Color("#ffd98a"), pos + Vector3(0, 1.85, 0), Vector3(1, 1.2, 1), 8, 2.2)
	kit.cone(0.2, 0.18, Color("#3e4a5c"), pos + Vector3(0, 2.05, 0), 6)

func _build_sky_dressing() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var holder := _group("Sky")
	var kit := MeshKit.new(holder)
	kit.cast_shadows = false
	for i in 6:
		var a := TAU * i / 6.0 + r.randf_range(-0.3, 0.3)
		var dist := r.randf_range(27.0, 36.0)
		var islet := Node3D.new()
		islet.position = Vector3(cos(a) * dist, r.randf_range(-5.0, 3.0), sin(a) * dist)
		holder.add_child(islet)
		var ik := MeshKit.new(islet)
		ik.cast_shadows = false
		var s := r.randf_range(0.8, 1.6)
		ik.cyl(1.6 * s, 1.7 * s, 0.4 * s, Color("#83c55c"), Vector3(0, 0, 0), 10)
		ik.cyl(1.7 * s, 0.2, 2.8 * s, Color("#8d7660"), Vector3(0, -1.6 * s, 0), 8)
		if i % 2 == 0:
			ik.cyl(0.08 * s, 0.12 * s, 0.8 * s, Color("#7a4d2d"), Vector3(0, 0.6 * s, 0), 6)
			ik.sphere(0.6 * s, Color("#5fb04f"), Vector3(0, 1.2 * s, 0), Vector3.ONE, 8)
		islet.set_meta("bob", islet.position.y)
		islets.append(islet)
	for i in 14:
		var cloud := Node3D.new()
		var a := r.randf_range(0, TAU)
		var dist := r.randf_range(22.0, 48.0)
		cloud.position = Vector3(cos(a) * dist, r.randf_range(-14.0, -3.0), sin(a) * dist)
		holder.add_child(cloud)
		var ck := MeshKit.new(cloud)
		ck.cast_shadows = false
		var puffs := r.randi_range(4, 7)
		for j in puffs:
			var size := r.randf_range(1.4, 2.6)
			ck.sphere(size, Color("#ffffff").lerp(Color("#dcecff"), r.randf() * 0.5), Vector3(j * 1.6 - puffs * 0.8, r.randf_range(-0.3, 0.6), r.randf_range(-0.8, 0.8)), Vector3(1.0, 0.7, 1.0), 10)
		cloud.set_meta("speed", r.randf_range(0.15, 0.35))
		clouds.append(cloud)

func _spawn_puff(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = true
	p.amount = 24
	p.lifetime = 1.2
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -1.5, 0)
	var mesh := SphereMesh.new(); mesh.radius = 0.18; mesh.height = 0.36; mesh.radial_segments = 6; mesh.rings = 3
	var m := StandardMaterial3D.new(); m.albedo_color = Color(1, 0.97, 0.85); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	p.mesh = mesh
	fx_root.add_child(p)
	if is_inside_tree(): get_tree().create_timer(2.0).timeout.connect(p.queue_free)

# =============================================================================
# Navigazione per gli eroi
# =============================================================================

func _nav_add(key: String, pos: Vector3) -> int:
	if nav_points.has(key): return nav_points[key]
	var id := nav.get_available_point_id()
	nav.add_point(id, pos)
	nav_points[key] = id
	return id

func _build_navigation() -> void:
	nav.clear()
	nav_points.clear()
	plaza_nodes.clear()
	wander_nodes.clear()
	site_nodes.clear()
	var ring := 10
	for i in ring:
		var a := TAU * i / ring
		plaza_nodes.append(_nav_add("plaza_%d" % i, Vector3(cos(a), 0, sin(a)) * 3.0))
		plaza_nodes.append(_nav_add("plaza_in_%d" % i, Vector3(cos(a + 0.3), 0, sin(a + 0.3)) * 1.8))
	for i in plaza_nodes.size():
		for j in range(i + 1, plaza_nodes.size()):
			if nav.get_point_position(plaza_nodes[i]).distance_to(nav.get_point_position(plaza_nodes[j])) < 2.3:
				nav.connect_points(plaza_nodes[i], plaza_nodes[j])
	wander_nodes.append_array(plaza_nodes)
	for key in paths:
		var pts: Array = paths[key]
		var prev := -1
		for i in pts.size():
			var node := _nav_add("%s_%d" % [key, i], pts[i])
			if prev >= 0: nav.connect_points(prev, node)
			prev = node
			if key != "gate_bridge" and i > 0 and i < pts.size() - 1 and i % 2 == 0: wander_nodes.append(node)
		if key != "gate_bridge" and not pts.is_empty():
			var first: int = nav_points["%s_0" % key]
			for pn in plaza_nodes:
				if nav.get_point_position(pn).distance_to(pts[0]) < 2.4: nav.connect_points(first, pn)
	# Collegamento piazza → ponte del portale
	if paths.has("gate"):
		var gate_last: int = nav_points["gate_%d" % (paths["gate"].size() - 1)]
		nav.connect_points(gate_last, nav_points["gate_bridge_0"])
	for id in buildings:
		var model: BuildingModel = buildings[id]
		var key_last := "%s_%d" % [id, paths.get(id, []).size() - 1]
		var entry: int = nav_points.get(key_last, -1)
		if id == "gate": entry = nav_points.get("gate_bridge_%d" % (paths["gate_bridge"].size() - 1), -1)
		if entry < 0: continue
		var door := _nav_add(id + "_door", _to_world(model, model.door_local))
		nav.connect_points(entry, door)
		var spots: Array[int] = []
		var via := door
		if id == "training":
			var top := _nav_add("training_top", _to_world(model, Vector3(0, 0.95, 3.0)))
			nav.connect_points(door, top)
			via = top
		for i in model.spots_local.size():
			var spot := _nav_add("%s_spot_%d" % [id, i], _to_world(model, model.spots_local[i]))
			nav.connect_points(via, spot)
			spots.append(spot)
		site_nodes[id] = {"door": door, "spots": spots}
		if id in ["merging", "dormitory"]: wander_nodes.append_array(spots)

func _to_world(model: BuildingModel, local: Vector3) -> Vector3:
	return model.position + (local * model.scale.x).rotated(Vector3.UP, model.rotation.y)

func nearest_node(pos: Vector3) -> int:
	return nav.get_closest_point(pos)

func route(from: Vector3, to_node: int) -> PackedVector3Array:
	var start := nearest_node(from)
	if start < 0 or to_node < 0: return PackedVector3Array()
	return nav.get_point_path(start, to_node)

func node_position(node: int) -> Vector3:
	return nav.get_point_position(node)

func facing_target_for(id: String, spot_index: int) -> Vector3:
	var model: BuildingModel = buildings.get(id)
	if model == null: return Vector3.ZERO
	if id == "training":
		var dummies := [Vector3(-1.4, 1.0, -0.6), Vector3(0.0, 1.0, -1.3), Vector3(1.4, 1.0, -0.6)]
		if spot_index < 3: return _to_world(model, dummies[spot_index])
		return _to_world(model, Vector3(0, 1.0, 0))
	return _to_world(model, Vector3(0, 0, 0))

# =============================================================================
# Eroi nella base
# =============================================================================

func _sync_agents(state: RiftwardState) -> void:
	var alive := state.get_alive_heroes()
	var keep := {}
	var training_index := 0
	for hero in alive:
		if keep.size() >= MAX_AGENTS: break
		var id := str(hero.id)
		keep[id] = true
		var agent: HubAgent = agents.get(id)
		if agent == null:
			agent = HubAgentScript.new()
			agent_root.add_child(agent)
			agent.setup(self, hero, state.hero_appearance(hero))
			var start_node: int = plaza_nodes[agents.size() % maxi(1, plaza_nodes.size())] if not plaza_nodes.is_empty() else -1
			agent.position = node_position(start_node) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)) if start_node >= 0 else Vector3.ZERO
			agents[id] = agent
		var activity := state.hero_activity(hero)
		var slot := -1
		if activity == "training":
			slot = training_index
			training_index += 1
		agent.set_activity(activity, slot, hero)
	for id in agents.keys():
		if not keep.has(id):
			agents[id].queue_free()
			agents.erase(id)

func agent_for(hero_id: String) -> HubAgent:
	return agents.get(hero_id)

## Animazione di partenza: la squadra raggiunge il portale e lo attraversa.
func play_deploy(party_ids: Array) -> void:
	var gate_spots: Array = site_nodes.get("gate", {}).get("spots", [])
	var i := 0
	for hero_id in party_ids:
		var agent: HubAgent = agents.get(str(hero_id))
		if agent == null: continue
		agent.force_goal(gate_spots[i % maxi(1, gate_spots.size())] if not gate_spots.is_empty() else -1, "cheer")
		i += 1
	var gate: BuildingModel = buildings.get("gate")
	var waited := 0.0
	while waited < 7.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var all_there := true
		for hero_id in party_ids:
			var agent: HubAgent = agents.get(str(hero_id))
			if agent != null and not agent.arrived: all_there = false
		if all_there: break
	if gate != null and gate.portal_material != null:
		var tween := create_tween()
		tween.tween_method(func(v): gate.portal_material.set_shader_parameter("intensity", v), 1.0, 3.5, 0.6)
		await tween.finished
	for hero_id in party_ids:
		var agent: HubAgent = agents.get(str(hero_id))
		if agent != null: agent.visible = false
	await get_tree().create_timer(0.3).timeout
	if gate != null and gate.portal_material != null: gate.portal_material.set_shader_parameter("intensity", 1.0)

func restore_agents() -> void:
	for agent in agents.values():
		agent.visible = true
		agent.release_goal()

# =============================================================================
# Interazione
# =============================================================================

func set_hovered(id: String) -> void:
	if id == hovered_id: return
	if buildings.has(hovered_id) and hovered_id != selected_id: buildings[hovered_id].kit.set_highlight(0.0)
	if labels.has(hovered_id): labels[hovered_id].modulate = Color.WHITE
	hovered_id = id
	if buildings.has(id) and id != selected_id: buildings[id].kit.set_highlight(0.16)
	if labels.has(id): labels[id].modulate = Color("#ffe39a")

func set_selected(id: String) -> void:
	if buildings.has(selected_id): buildings[selected_id].kit.set_highlight(0.0)
	selected_id = id
	if buildings.has(id): buildings[id].kit.set_highlight(0.22)

func focus_position(id: String) -> Vector3:
	if id == "crystal": return Vector3(0, 0.8, 0)
	if buildings.has(id): return buildings[id].position + Vector3(0, 1.0, 0)
	return Vector3.ZERO

func _process(delta: float) -> void:
	time += delta
	if crystal != null:
		crystal.position.y = 2.0 + sin(time * 1.4) * 0.12
		crystal.rotation.y = time * 0.5
		for child in crystal.get_children():
			if child.has_meta("angle"):
				var a := float(child.get_meta("angle")) + time * 1.2
				child.position = Vector3(cos(a) * 1.0, 0.2 + sin(time * 2.0 + a) * 0.2, sin(a) * 1.0)
	for c in clouds:
		c.position.x += float(c.get_meta("speed")) * delta
		if c.position.x > 55.0: c.position.x = -55.0
	for n in islets:
		if is_instance_valid(n): n.position.y = float(n.get_meta("bob")) + sin(time * 0.7 + n.position.x) * 0.25
	for agent in agents.values():
		agent.tick(delta)
	for id in badges:
		var badge: Sprite3D = badges[id]
		if badge.visible:
			var s := 1.0 + 0.12 * sin(time * 5.0)
			badge.scale = Vector3.ONE * s
