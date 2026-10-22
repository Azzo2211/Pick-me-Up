extends Node3D
class_name HubWorld

## La base fisica: un'isola sospesa nel Rift con un borgo cinto da mura.
## Piazza del Nexus al centro, strada ad anello, edifici affacciati sulla strada,
## bosco tra le mura e la scogliera, Portale sospeso su una rupe collegata da un
## ponte. Il livello della base cambia strade, mura e decorazioni.
## Tutto è generato in codice; 1 unità = 2 metri.

signal building_clicked(id: String)
signal hero_clicked(hero_id: String)

const BuildingModelScript := preload("res://scripts/hub3d/building_model.gd")
const WaterShader := preload("res://scripts/hub3d/water.gdshader")
const HubAgentScript := preload("res://scripts/hub3d/hub_agent.gd")

const PLAZA_RADIUS := 4.4
const RING_RADIUS := 7.2
const RING_WIDTH := 1.5
const WALL_RADIUS := 15.2
const ISLAND_BASE := 21.2
const GATE_ANGLE := 4.9742
const GATE_DISTANCE := 27.0
const GATE_HEIGHT := 1.4
const GATE_PLATFORM_RADIUS := 4.6
const POND_ANGLE := 0.96
const POND_DISTANCE := 18.2
const POND_RADIUS := 1.6
const SPOKES := [4.9742, 0.2618, 1.8326, 3.4034]
const MAX_AGENTS := 30

## Siti delle strutture: angolo (gradi) e distanza dal centro. L'ingresso guarda la piazza.
const SITES := {
	"dormitory": Vector2(168, 10.9),
	"training": Vector2(212, 12.0),
	"alchemy": Vector2(250, 10.2),
	"armory": Vector2(326, 10.6),
	"merging": Vector2(22, 11.0),
	"workshop": Vector2(72, 10.5),
	"warehouse": Vector2(120, 10.6),
	"gate": Vector2(285, 27.0),
}
const SITE_RADIUS := {"training": 4.4, "dormitory": 3.9, "merging": 3.2, "armory": 3.9, "warehouse": 3.6, "workshop": 3.4, "alchemy": 2.8, "gate": 0.0}
const GARDENS := [Vector2(190, 13.6), Vector2(96, 13.4), Vector2(345, 13.2)]
const FOUNTAIN := Vector2(46, 9.6)

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var sun: DirectionalLight3D
var look: Dictionary = {}
var terrain_root: Node3D
var veg_root: Node3D
var decor_root: Node3D
var building_root: Node3D
var agent_root: Node3D
var fx_root: Node3D
var sky_root: Node3D

var buildings: Dictionary = {}
var building_states: Dictionary = {}
var labels: Dictionary = {}
var sublabels: Dictionary = {}
var badges: Dictionary = {}
var agents: Dictionary = {}
var villagers: Array = []
var crystal: Node3D
var nav := AStar3D.new()
var nav_points: Dictionary = {}
var plaza_nodes: Array[int] = []
var ring_nodes: Array[int] = []
var wander_nodes: Array[int] = []
var site_nodes: Dictionary = {}
var current_base_level := -1
var occupied_signature := ""
var hovered_id := ""
var selected_id := ""
var time := 0.0
var floaters: Array[Node3D] = []
var road_segments: Array = []
var _terrain_mesh: MeshInstance3D
var active_sites: Dictionary = {}
var _label_timer := 0.0
var _decor_holder: Node3D
var _wall_holder: Node3D

func _ready() -> void:
	rng.seed = 424242
	noise.seed = 7
	noise.frequency = 0.07
	_apply_light("dusk")
	terrain_root = _group("Terrain")
	veg_root = _group("Vegetation")
	decor_root = _group("Decor")
	building_root = _group("Buildings")
	agent_root = _group("Agents")
	fx_root = _group("Fx")
	sky_root = _group("Sky")
	_define_roads()
	_build_cliffs()
	_build_gate_platform()
	_build_water()
	_build_plaza()
	_build_sky_dressing()
	_tint_world()

var light_preset := ""
var _mists: Array[ShaderMaterial] = []
var _waters: Array[ShaderMaterial] = []

## Cambia luce e cielo della base (crepuscolo, giorno, notte).
func _apply_light(preset: String) -> void:
	if preset == light_preset: return
	light_preset = preset
	for key in ["world_environment", "sun", "fill"]:
		if look.has(key) and is_instance_valid(look[key]): (look[key] as Node).queue_free()
	look = WorldLook.setup(self, preset, {}, 140.0)
	sun = look.sun
	_tint_world()
	if look.has("sky"): (look.sky as ShaderMaterial).set_shader_parameter("aurora", 1.0 if current_base_level >= 5 else 0.0)

## Nebbie e acqua seguono i colori della luce scelta.
func _tint_world() -> void:
	var p: Dictionary = look.get("preset", {})
	for m in _mists:
		m.set_shader_parameter("color_low", p.get("mist_low", Color("#3b2c48")))
		m.set_shader_parameter("color_high", p.get("mist_high", Color("#c79486")))
	for m in _waters:
		m.set_shader_parameter("base_color", p.get("water_base", Color("#1a2133")))
		m.set_shader_parameter("sky_color", p.get("water_sky", Color("#9e666b")))
		m.set_shader_parameter("foam_color", p.get("water_foam", Color("#d9ccd9")))

func _group(name_text: String) -> Node3D:
	var n := Node3D.new()
	n.name = name_text
	add_child(n)
	return n

# =============================================================================
# Geometria di base: contorno, quote, strade
# =============================================================================

func island_radius(angle: float) -> float:
	return ISLAND_BASE + 1.1 * sin(2.0 * angle + 0.6) + 0.8 * sin(3.0 * angle + 1.9) + 0.45 * sin(5.0 * angle + 0.3) + 0.25 * sin(9.0 * angle + 2.0)

func is_on_island(p: Vector2, margin: float = 0.0) -> bool:
	return p.length() < island_radius(atan2(p.y, p.x)) - margin

func polar(angle_deg: float, radius: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(cos(a), sin(a)) * radius

func ground_height(p: Vector2) -> float:
	var r := p.length()
	var edge := island_radius(atan2(p.y, p.x))
	var outside := smoothstep(WALL_RADIUS + 0.6, WALL_RADIUS + 3.2, r)
	var hills := 0.0
	if outside > 0.0:
		hills = (noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5) * 1.1 * outside
		hills *= smoothstep(0.8, 2.6, _road_distance(p, "gate"))
	var rim := -pow(clampf((r - (edge - 2.4)) / 2.4, 0.0, 1.0), 2.0) * 0.7
	return hills + rim

func _site_position(id: String) -> Vector3:
	if id == "gate": return gate_center()
	var s: Vector2 = SITES[id]
	var p := polar(s.x, s.y)
	return Vector3(p.x, 0.0, p.y)

func gate_center() -> Vector3:
	return Vector3(cos(GATE_ANGLE), 0, sin(GATE_ANGLE)) * GATE_DISTANCE + Vector3(0, GATE_HEIGHT, 0)

func _site_yaw(id: String) -> float:
	var p := _site_position(id)
	return atan2(-p.x, -p.z)

## Segmenti delle strade (XZ) con larghezza: usati per terreno, alberi e percorsi.
func _define_roads() -> void:
	road_segments.clear()
	var narrow := current_base_level <= 1
	for a in SPOKES:
		var dir := Vector2(cos(a), sin(a))
		road_segments.append([dir * (PLAZA_RADIUS - 0.4), dir * (RING_RADIUS + 0.2), 1.0 if narrow else 1.35, "spoke"])
	var gate_dir := Vector2(cos(GATE_ANGLE), sin(GATE_ANGLE))
	road_segments.append([gate_dir * RING_RADIUS, gate_dir * (island_radius(GATE_ANGLE) - 0.3), 1.2 if narrow else 1.5, "gate"])
	var steps := 48
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		road_segments.append([Vector2(cos(a0), sin(a0)) * RING_RADIUS, Vector2(cos(a1), sin(a1)) * RING_RADIUS, 1.0 if narrow else RING_WIDTH, "ring"])
	for id in SITES:
		if id == "gate" or not active_sites.has(id): continue
		var s: Vector2 = SITES[id]
		var dir := polar(s.x, 1.0)
		road_segments.append([dir * RING_RADIUS, dir * (s.y - 2.2), 1.0 if narrow else 1.3, "apron:" + id])

func _road_distance(p: Vector2, kinds: String = "") -> float:
	var best := 99.0
	for seg in road_segments:
		if not kinds.is_empty() and not str(seg[3]).begins_with(kinds): continue
		var d := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) - float(seg[2]) * 0.5
		best = minf(best, d)
	return best

# =============================================================================
# Terreno (ricostruito quando cambia il livello della base)
# =============================================================================

func _build_terrain(base_level: int) -> void:
	if _terrain_mesh != null: _terrain_mesh.queue_free()
	var rings := 64
	var segments := 200
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.append(Vector3(0, 0, 0))
	cols.append(_terrain_mask(Vector2.ZERO, base_level))
	var edge_r: Array[float] = []
	for s in segments: edge_r.append(island_radius(TAU * s / segments))
	for k in range(1, rings + 1):
		var f := float(k) / rings
		for s in segments:
			var a := TAU * s / segments
			var r := edge_r[s] * f
			var p := Vector2(cos(a), sin(a)) * r
			verts.append(Vector3(p.x, ground_height(p), p.y))
			cols.append(_terrain_mask(p, base_level))
	var indices := PackedInt32Array()
	for s in segments:
		_tri_idx(indices, verts, 0, 1 + s, 1 + (s + 1) % segments, Vector3.UP)
	for k in range(1, rings):
		var row0 := 1 + (k - 1) * segments
		var row1 := 1 + k * segments
		for s in segments:
			var s2 := (s + 1) % segments
			_tri_idx(indices, verts, row0 + s, row1 + s, row1 + s2, Vector3.UP)
			_tri_idx(indices, verts, row0 + s, row1 + s2, row0 + s2, Vector3.UP)
	# bordo che scende verso la scogliera
	var lip_start := verts.size()
	var outer := 1 + (rings - 1) * segments
	for s in segments:
		var v := verts[outer + s]
		var dir := Vector3(v.x, 0, v.z).normalized()
		verts.append(Vector3(v.x + dir.x * 0.35, -0.85, v.z + dir.z * 0.35))
		cols.append(Color(0, 0, 1, 0.8))
	for s in segments:
		var s2 := (s + 1) % segments
		var dir := Vector3(verts[outer + s].x, 0, verts[outer + s].z).normalized()
		_tri_idx(indices, verts, outer + s, lip_start + s, lip_start + s2, dir)
		_tri_idx(indices, verts, outer + s, lip_start + s2, outer + s2, dir)
	var normals := _smooth_normals(verts, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, WorldMaterials.terrain())
	_terrain_mesh = MeshInstance3D.new()
	_terrain_mesh.mesh = mesh
	_terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_root.add_child(_terrain_mesh)

## Maschere del terreno: R sterrato, G selciato, B roccia, A occlusione.
func _terrain_mask(p: Vector2, base_level: int) -> Color:
	var r := p.length()
	var dirt := 0.0
	var paved := 0.0
	var ao := 1.0
	# piazza
	var plaza := smoothstep(PLAZA_RADIUS + 0.25, PLAZA_RADIUS - 0.25, r)
	if base_level >= 2: paved = maxf(paved, plaza)
	else:
		dirt = maxf(dirt, plaza)
		paved = maxf(paved, smoothstep(2.6, 2.2, r))
	# strade
	for seg in road_segments:
		var kind := str(seg[3])
		var d := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p)
		var w := float(seg[2]) * 0.5
		var m := smoothstep(w + 0.3, w - 0.15, d)
		if m <= 0.0: continue
		var stone := false
		match kind:
			"spoke": stone = base_level >= 2
			"gate": stone = base_level >= 2 and r < WALL_RADIUS + 0.5 or base_level >= 4
			"ring": stone = base_level >= 3
			_: stone = base_level >= 3
		if stone: paved = maxf(paved, m)
		else: dirt = maxf(dirt, m)
	# terra calpestata attorno agli edifici e negli orti
	for id in SITES:
		if id == "gate" or not active_sites.has(id): continue
		var site := polar(SITES[id].x, SITES[id].y)
		var d := p.distance_to(site)
		var rad := float(SITE_RADIUS[id])
		dirt = maxf(dirt, smoothstep(rad + 0.4, rad - 0.6, d) * 0.75)
		ao = minf(ao, lerpf(0.72, 1.0, smoothstep(rad - 1.2, rad + 0.5, d)))
	for g in GARDENS:
		var gp := polar(g.x, g.y)
		dirt = maxf(dirt, smoothstep(1.5, 1.1, maxf(absf(p.x - gp.x), absf(p.y - gp.y))))
	# sentiero lungo le mura (dall'interno)
	dirt = maxf(dirt, smoothstep(0.9, 0.3, absf(r - (WALL_RADIUS - 0.9))) * 0.55)
	# pozza e ruscello
	var pond := polar(rad_to_deg(POND_ANGLE), POND_DISTANCE)
	dirt = maxf(dirt, smoothstep(POND_RADIUS + 0.9, POND_RADIUS + 0.2, p.distance_to(pond)) * 0.6)
	var edge := island_radius(atan2(p.y, p.x))
	var rock := smoothstep(edge - 0.9, edge - 0.1, r) * 0.7
	return Color(clampf(dirt, 0, 1), clampf(paved, 0, 1), rock, ao)

func _tri_idx(indices: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int, hint: Vector3) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(hint) < 0.0:
		var t := b; b = c; c = t
	# Godot: frontali i triangoli in senso orario rispetto alla normale
	indices.append(a)
	indices.append(c)
	indices.append(b)

func _smooth_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var c := indices[i + 1]
		var b := indices[i + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		normals[a] += n
		normals[b] += n
		normals[c] += n
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length() > 0.00001 else Vector3.UP
	return normals

## Scogliera sotto l'isola: strati di roccia che si stringono verso il basso.
func _build_cliffs() -> void:
	var segments := 200
	var layers := 9
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var cliff_noise := FastNoiseLite.new()
	cliff_noise.seed = 31
	cliff_noise.frequency = 0.9
	for l in layers + 1:
		var t := float(l) / layers
		for s in segments:
			var a := TAU * s / segments
			var edge := island_radius(a)
			var r := edge * (1.0 - pow(t, 1.35) * 0.9) + 0.35 * (1.0 - t)
			var jitter := cliff_noise.get_noise_2d(a * 12.0, l * 2.0) * 1.4 * (1.0 - t * 0.5) * smoothstep(0.0, 0.12, t)
			var y := -0.85 - t * 17.0 + cliff_noise.get_noise_2d(a * 7.0, l * 4.0) * 1.6 * t
			verts.append(Vector3(cos(a) * (r + jitter), y, sin(a) * (r + jitter)))
			cols.append(Color(0, 0, 1, lerpf(0.9, 0.5, t)))
	var tip := verts.size()
	verts.append(Vector3(1.0, -21.0, -0.6))
	cols.append(Color(0, 0, 1, 0.4))
	for l in layers:
		for s in segments:
			var s2 := (s + 1) % segments
			var a0 := l * segments + s
			var a1 := l * segments + s2
			var b0 := (l + 1) * segments + s
			var b1 := (l + 1) * segments + s2
			var out := Vector3(verts[a0].x, 0, verts[a0].z).normalized()
			_tri_idx(indices, verts, a0, b0, b1, out)
			_tri_idx(indices, verts, a0, b1, a1, out)
	for s in segments:
		var a0 := layers * segments + s
		var a1 := layers * segments + (s + 1) % segments
		_tri_idx(indices, verts, a0, tip, a1, Vector3(verts[a0].x, -2.0, verts[a0].z).normalized())
	_add_flat_mesh(terrain_root, verts, cols, indices, WorldMaterials.terrain(), true)

func _add_flat_mesh(parent: Node3D, verts: PackedVector3Array, cols: PackedColorArray, indices: PackedInt32Array, mat: Material, shadows: bool) -> MeshInstance3D:
	# normali per faccia (vertici duplicati) per un aspetto roccioso
	var fv := PackedVector3Array()
	var fn := PackedVector3Array()
	var fc := PackedColorArray()
	for i in range(0, indices.size(), 3):
		var a := verts[indices[i]]
		var c := verts[indices[i + 1]]
		var b := verts[indices[i + 2]]
		var n := (b - a).cross(c - a).normalized()
		for k in 3:
			fv.append(verts[indices[i + k]])
			fn.append(n)
			fc.append(cols[indices[i + k]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = fv
	arrays[Mesh.ARRAY_NORMAL] = fn
	arrays[Mesh.ARRAY_COLOR] = fc
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# =============================================================================
# Rupe del Portale e ponte sospeso
# =============================================================================

func _build_gate_platform() -> void:
	var c := gate_center()
	var b := MeshBuilder.new()
	b.material("ground", WorldMaterials.terrain())
	b.material("paving", WorldMaterials.stone("paving"))
	b.material("stone", WorldMaterials.stone("wall"))
	b.material("dark", WorldMaterials.stone("dark"))
	b.material("metal", WorldMaterials.metal(Color.WHITE, 0.5, 0.7))
	# zolla superiore e rupe rovesciata
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a), sin(a)) * (GATE_PLATFORM_RADIUS + 0.35 * sin(a * 3.0 + 1.0)))
	b.extrude("ground", pts, c.y - 0.4, c.y, Color(0.15, 0.0, 0.0, 1.0), true, false, Vector3(c.x, 0, c.z))
	var layers := 6
	for l in layers:
		var t0 := float(l) / layers
		var t1 := float(l + 1) / layers
		var r0 := GATE_PLATFORM_RADIUS * (1.0 - pow(t0, 1.2) * 0.92)
		var r1 := GATE_PLATFORM_RADIUS * (1.0 - pow(t1, 1.2) * 0.92)
		b.cylinder("ground", r0, r1, 1.6, Vector3(c.x, c.y - 0.4 - 0.8 - l * 1.6, c.z), Color(0, 0, 1, lerpf(0.9, 0.5, t0)), 14, Vector3(0, l * 0.4, 0), false, MeshBuilder.UV.FACE, TAU, false)
	b.cone("ground", GATE_PLATFORM_RADIUS * 0.08, 1.4, Vector3(c.x, c.y - 0.4 - layers * 1.6 - 0.7, c.z), Color(0, 0, 1, 0.45), 8, Vector3(PI, 0, 0))
	# piazzola lastricata
	b.cylinder("paving", 3.9, 4.0, 0.08, Vector3(c.x, c.y + 0.02, c.z), Color.WHITE, 28)
	# ponte: dal bordo dell'isola alla rupe, con parapetti e piloni
	var dir := Vector3(cos(GATE_ANGLE), 0, sin(GATE_ANGLE))
	var side := Vector3(-dir.z, 0, dir.x)
	var start_r := island_radius(GATE_ANGLE) - 1.6
	var start := dir * start_r
	start.y = ground_height(Vector2(start.x, start.z))
	var finish := c - dir * (GATE_PLATFORM_RADIUS - 0.8)
	var pieces := 9
	for i in pieces:
		var t := (i + 0.5) / pieces
		var pos := start.lerp(finish, t)
		pos.y = lerpf(start.y, finish.y, t) + sin(t * PI) * 0.18
		var yaw := atan2(dir.x, dir.z)
		var len_piece := start.distance_to(finish) / pieces + 0.05
		b.box("paving", Vector3(1.9, 0.22, len_piece), pos + Vector3(0, -0.05, 0), Color.WHITE, Vector3(0, yaw, 0))
		b.box("stone", Vector3(2.1, 0.35, len_piece), pos + Vector3(0, -0.3, 0), Color.WHITE, Vector3(0, yaw, 0))
		for sgn in [-1.0, 1.0]:
			b.box("stone", Vector3(0.2, 0.42, len_piece), pos + side * float(sgn) * 0.98 + Vector3(0, 0.22, 0), Color.WHITE, Vector3(0, yaw, 0))
	# arco di sostegno sotto il ponte
	var mid := start.lerp(finish, 0.5)
	b.cylinder("stone", 0.45, 0.25, 3.8, mid + Vector3(0, -2.4, 0), Color.WHITE, 8)
	# catene dai piloni del ponte alla rupe
	for sgn in [-1.0, 1.0]:
		var top := finish + side * float(sgn) * 1.2 + Vector3(0, 1.8, 0)
		var post := start + side * float(sgn) * 1.1
		b.box("dark", Vector3(0.4, 1.6, 0.4), post + Vector3(0, 0.8, 0))
		b.box("dark", Vector3(0.4, 2.0, 0.4), finish + side * float(sgn) * 1.2 + Vector3(0, 1.0, 0))
		var links := 12
		for i in links:
			var t0 := float(i) / links
			var t1 := float(i + 1) / links
			var p0 := (post + Vector3(0, 1.55, 0)).lerp(top, t0) + Vector3(0, -sin(t0 * PI) * 0.7, 0)
			var p1 := (post + Vector3(0, 1.55, 0)).lerp(top, t1) + Vector3(0, -sin(t1 * PI) * 0.7, 0)
			b.rod("metal", p0, p1, 0.035, 0.035, Color("#2e2c2a"), 4)
	b.instance(terrain_root)
	set_meta("gate_bridge", [start, finish])

# =============================================================================
# Acqua: laghetto fuori dalle mura e cascata giù dalla scogliera
# =============================================================================

func _water_material(speed: float, stripes: float, alpha: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WaterShader
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("stripes", stripes)
	m.set_shader_parameter("alpha", alpha)
	_waters.append(m)
	return m

func _build_water() -> void:
	var pond2 := polar(rad_to_deg(POND_ANGLE), POND_DISTANCE)
	var pond := Vector3(pond2.x, ground_height(pond2) - 0.05, pond2.y)
	var b := MeshBuilder.new()
	b.material("rock", WorldMaterials.terrain())
	for i in 11:
		var a := TAU * i / 11.0 + 0.2
		b.rock("rock", 0.3 + (i % 3) * 0.08, pond + Vector3(cos(a), 0.05, sin(a)) * (POND_RADIUS + 0.25), Color(0, 0, 1, 1), Vector3(1.2, 0.7, 1.0), 60 + i, 0.25)
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = POND_RADIUS
	disc.bottom_radius = POND_RADIUS
	disc.height = 0.06
	disc.radial_segments = 28
	water.mesh = disc
	water.material_override = _water_material(0.3, 2.5, 0.92)
	water.position = pond + Vector3(0, 0.06, 0)
	terrain_root.add_child(water)
	var dir := pond2.normalized()
	var edge := dir * (island_radius(POND_ANGLE) - 0.1)
	var start := pond2 + dir * (POND_RADIUS - 0.3)
	var length := start.distance_to(edge)
	var stream := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, length)
	stream.mesh = quad
	stream.material_override = _water_material(1.4, length * 1.5, 0.95)
	var mid := (start + edge) * 0.5
	stream.position = Vector3(mid.x, ground_height(mid) + 0.06, mid.y)
	stream.rotation = Vector3(-PI / 2, atan2(-dir.x, -dir.y), 0)
	terrain_root.add_child(stream)
	for i in 6:
		var t := (i + 0.5) / 6.0
		var p := start.lerp(edge, t) + Vector2(-dir.y, dir.x) * (0.55 if i % 2 == 0 else -0.55)
		b.rock("rock", 0.18, Vector3(p.x, ground_height(p) + 0.05, p.y), Color(0, 0, 1, 1), Vector3(1.1, 0.6, 1.0), 80 + i, 0.25)
	b.instance(terrain_root)
	var fall := MeshInstance3D.new()
	var fall_quad := QuadMesh.new()
	fall_quad.size = Vector2(0.9, 14.0)
	fall.mesh = fall_quad
	fall.material_override = _water_material(2.2, 10.0, 0.8)
	var outward := Vector3(dir.x, 0, dir.y)
	fall.position = Vector3(edge.x, -7.0, edge.y) + outward * 1.3
	fall.rotation = Vector3(-0.12, atan2(dir.x, dir.y), 0)
	terrain_root.add_child(fall)
	var mist := CPUParticles3D.new()
	mist.position = Vector3(edge.x, -13.5, edge.y) + outward * 2.2
	mist.amount = 16
	mist.lifetime = 2.6
	mist.direction = Vector3.UP
	mist.spread = 70.0
	mist.initial_velocity_min = 0.3
	mist.initial_velocity_max = 0.7
	mist.gravity = Vector3.ZERO
	mist.scale_amount_min = 1.2
	mist.scale_amount_max = 2.4
	var puff := QuadMesh.new()
	puff.size = Vector2(1.2, 1.2)
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = WorldMaterials.soft_texture(48, Color(1, 1, 1, 0.5))
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff.material = pm
	mist.mesh = puff
	terrain_root.add_child(mist)

# =============================================================================
# Piazza e Cristallo del Nexus
# =============================================================================

func _build_plaza() -> void:
	var b := MeshBuilder.new()
	b.material("pale", WorldMaterials.stone("pale"))
	b.material("dark", WorldMaterials.stone("dark"))
	b.material("rune", WorldMaterials.glow(Color("#7fd2ff"), 2.0))
	var pts8 := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		pts8.append(Vector2(cos(a), sin(a)))
	b.extrude("pale", _scaled(pts8, 2.05), 0.0, 0.18, Color(0.95, 0.95, 0.95))
	b.extrude("pale", _scaled(pts8, 1.55), 0.18, 0.4, Color.WHITE)
	b.extrude("dark", _scaled(pts8, 0.9), 0.4, 1.15, Color.WHITE)
	b.extrude("pale", _scaled(pts8, 1.05), 1.15, 1.3, Color.WHITE)
	for i in 8:
		var a := TAU * i / 8.0
		b.box("rune", Vector3(0.05, 0.42, 0.02), Vector3(cos(a), 0, sin(a)) * 0.9 + Vector3(0, 0.78, 0), Color.WHITE, Vector3(0, -a + PI / 2, 0))
	b.torus("rune", 2.75, 0.03, Vector3(0, 0.03, 0), Color.WHITE, Vector3.ZERO, 48, 4)
	b.instance(decor_root)
	crystal = Node3D.new()
	crystal.position = Vector3(0, 2.6, 0)
	decor_root.add_child(crystal)
	var cb := MeshBuilder.new()
	cb.material("core", WorldMaterials.glow(Color("#3f8fe0"), 1.5))
	cb.material("inner", WorldMaterials.glow(Color("#a9dcff"), 2.6))
	cb.sphere("core", 0.62, Vector3.ZERO, Color.WHITE, Vector3(0.62, 1.55, 0.62), 6, 2)
	cb.sphere("inner", 0.3, Vector3.ZERO, Color.WHITE, Vector3(0.5, 1.4, 0.5), 6, 2)
	var core := cb.instance(crystal, false)
	core.set_meta("spin", true)
	for i in 3:
		var shard := MeshBuilder.new()
		shard.material("s", WorldMaterials.glow(Color("#7fc0ff"), 2.0))
		shard.sphere("s", 0.13, Vector3.ZERO, Color.WHITE, Vector3(0.6, 1.7, 0.6), 4, 2)
		var mi := shard.instance(crystal, false)
		mi.set_meta("angle", TAU * i / 3.0)
	var light := OmniLight3D.new()
	light.light_color = Color("#6fd0ff")
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	crystal.add_child(light)
	_light_pool(Vector3(0, 0.05, 0), Color("#5fb8ff"), 5.5, 0.35)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.set_meta("facility_id", "crystal")
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.6
	cyl.height = 4.4
	shape.shape = cyl
	shape.position = Vector3(0, 2.2, 0)
	body.add_child(shape)
	decor_root.add_child(body)
	_make_label("crystal", Vector3(0, 4.1, 0), "Cristallo del Nexus")

func _scaled(pts: PackedVector2Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts: out.append(p * s)
	return out

## Chiazza di luce sul terreno (le luci vere sono poche per non pesare).
func _light_pool(pos: Vector3, color: Color, radius: float, strength: float = 0.5, parent: Node3D = null) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = WorldMaterials.soft_texture(64, Color(color.r, color.g, color.b, 1.0))
	m.albedo_color = Color(1, 1, 1, strength)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.rotation.x = -PI / 2
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else fx_root).add_child(mi)
	return mi

# =============================================================================
# Vegetazione (fissa: i siti delle strutture restano sempre liberi)
# =============================================================================

func _blocked(p: Vector2, clearance: float) -> bool:
	var r := p.length()
	if r < PLAZA_RADIUS + 1.0 + clearance: return true
	if _road_distance(p) < 0.5 + clearance: return true
	if absf(r - WALL_RADIUS) < 0.9 + clearance: return true
	for id in SITES:
		if id == "gate": continue
		var reserve := float(SITE_RADIUS[id]) if active_sites.has(id) else float(SITE_RADIUS[id]) * 0.55
		if p.distance_to(polar(SITES[id].x, SITES[id].y)) < reserve + clearance: return true
	for g in GARDENS:
		var gp := polar(g.x, g.y)
		if maxf(absf(p.x - gp.x), absf(p.y - gp.y)) < 1.6 + clearance: return true
	var pond := polar(rad_to_deg(POND_ANGLE), POND_DISTANCE)
	if p.distance_to(pond) < POND_RADIUS + 0.8 + clearance: return true
	if p.distance_to(polar(FOUNTAIN.x, FOUNTAIN.y)) < 1.6 + clearance: return true
	var edge_dir := pond.normalized()
	if Geometry2D.get_closest_point_to_segment(p, pond, edge_dir * island_radius(POND_ANGLE)).distance_to(p) < 0.8 + clearance: return true
	return false

func _build_vegetation() -> void:
	UIKit.clear(veg_root)
	var r := RandomNumberGenerator.new()
	r.seed = 9182
	var groups := {}
	var placed: Array[Vector2] = []
	var attempts := 0
	var target := 170
	while placed.size() < target and attempts < 9000:
		attempts += 1
		var a := r.randf_range(0, TAU)
		var edge := island_radius(a)
		var inside := r.randf() < 0.1
		var dist := r.randf_range(10.0, WALL_RADIUS - 1.2) if inside else r.randf_range(WALL_RADIUS + 1.3, edge - 0.9)
		var p := Vector2(cos(a), sin(a)) * dist
		if _blocked(p, 0.8): continue
		var too_close := false
		for q in placed:
			if q.distance_to(p) < (1.7 if not inside else 3.0):
				too_close = true
				break
		if too_close: continue
		placed.append(p)
		var roll := r.randf()
		var kind := "conifer" if roll < 0.52 else "broadleaf"
		if not inside and dist > edge - 2.6 and r.randf() < 0.18: kind = "dead"
		var variant := r.randi_range(0, 3 if kind == "conifer" else 4 if kind == "broadleaf" else 1)
		var scale := r.randf_range(0.85, 1.25) * (0.9 if inside else 1.0)
		var pos := Vector3(p.x, ground_height(p) - 0.05, p.y)
		var key := "%s_%d" % [kind, variant]
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(pos, scale, r.randf() * TAU, Vector3(r.randf_range(-0.04, 0.04), 0, r.randf_range(-0.04, 0.04))))
	# cespugli
	for i in 140:
		var a := r.randf_range(0, TAU)
		var dist := r.randf_range(8.6, island_radius(a) - 0.7)
		var p := Vector2(cos(a), sin(a)) * dist
		if _blocked(p, 0.0): continue
		var key := "bush_%d" % (i % 3)
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(Vector3(p.x, ground_height(p) - 0.03, p.y), r.randf_range(0.7, 1.3), r.randf() * TAU))
	# rocce
	for i in 46:
		var a := r.randf_range(0, TAU)
		var dist := r.randf_range(WALL_RADIUS + 1.0, island_radius(a) - 0.4)
		var p := Vector2(cos(a), sin(a)) * dist
		if _blocked(p, -0.2): continue
		var key := "rock_%d" % (i % 3)
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(Vector3(p.x, ground_height(p) - 0.12, p.y), r.randf_range(0.6, 1.5), r.randf() * TAU))
	for key in groups:
		var parts := str(key).split("_")
		NatureKit.scatter(veg_root, parts[0], int(parts[1]), groups[key], parts[0] != "tuft")
	# ciuffi d'erba
	var tufts := [[], []]
	for i in 3400:
		var a := r.randf_range(0, TAU)
		var dist := sqrt(r.randf()) * (island_radius(a) - 0.5)
		var p := Vector2(cos(a), sin(a)) * dist
		if p.length() < PLAZA_RADIUS + 0.6 or _road_distance(p) < 0.2: continue
		var site_hit := false
		for id in SITES:
			if id != "gate" and active_sites.has(id) and p.distance_to(polar(SITES[id].x, SITES[id].y)) < float(SITE_RADIUS[id]) - 0.4:
				site_hit = true
				break
		if site_hit: continue
		tufts[i % 2].append(NatureKit.placement(Vector3(p.x, ground_height(p), p.y), r.randf_range(0.7, 1.35), r.randf() * TAU))
	for v in 2: NatureKit.scatter(veg_root, "tuft", v, tufts[v], false)

# =============================================================================
# Cielo: nebbie sotto l'isola, rupi lontane
# =============================================================================

func _build_sky_dressing() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for layer in [[-9.0, 220.0, 0.85, 0.02], [-16.0, 260.0, 0.95, 0.014], [-3.5, 150.0, 0.35, 0.03]]:
		var plane := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(layer[1], layer[1])
		plane.mesh = pm
		var mist_mat := WorldMaterials.mist(Color("#3b2c48"), Color("#c79486"), layer[2], layer[3])
		_mists.append(mist_mat)
		plane.material_override = mist_mat
		plane.position = Vector3(0, layer[0], 0)
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky_root.add_child(plane)
	for i in 7:
		var a := TAU * i / 7.0 + r.randf_range(-0.3, 0.3)
		if absf(wrapf(a - GATE_ANGLE, -PI, PI)) < 0.5: a += 0.8
		var dist := r.randf_range(42.0, 62.0)
		var islet := Node3D.new()
		islet.position = Vector3(cos(a) * dist, r.randf_range(-6.0, 4.0), sin(a) * dist)
		sky_root.add_child(islet)
		var b := MeshBuilder.new()
		b.material("ground", WorldMaterials.terrain())
		var s := r.randf_range(1.2, 2.6)
		b.cylinder("ground", 2.0 * s, 2.2 * s, 0.5 * s, Vector3.ZERO, Color(0.1, 0, 0, 1), 10, Vector3.ZERO, true, MeshBuilder.UV.FACE, TAU, false)
		b.cylinder("ground", 2.2 * s, 0.3, 4.0 * s, Vector3(0, -2.25 * s, 0), Color(0, 0, 1, 0.7), 9, Vector3.ZERO, false, MeshBuilder.UV.FACE, TAU, false)
		b.instance(islet, false)
		if i % 2 == 0:
			var trees: Array = []
			for k in r.randi_range(2, 4):
				trees.append(NatureKit.placement(Vector3(r.randf_range(-1.2, 1.2) * s, 0.25 * s, r.randf_range(-1.2, 1.2) * s), s * 0.55, r.randf() * TAU))
			NatureKit.scatter(islet, "conifer", i % 4, trees, false)
		islet.set_meta("bob", islet.position.y)
		floaters.append(islet)

# =============================================================================
# Mura, strade e decorazioni secondo il livello della base
# =============================================================================

func _build_walls(base_level: int) -> void:
	if _wall_holder != null: _wall_holder.queue_free()
	_wall_holder = Node3D.new()
	_wall_holder.name = "Walls"
	decor_root.add_child(_wall_holder)
	var b := MeshBuilder.new()
	b.material("stone", WorldMaterials.stone("wall"))
	b.material("dark", WorldMaterials.stone("dark"))
	b.material("timber", WorldMaterials.wood("timber"))
	b.material("weathered", WorldMaterials.wood("weathered"))
	b.material("roof", WorldMaterials.roof("slate"))
	b.material("metal", WorldMaterials.metal(Color.WHITE, 0.5, 0.7))
	b.material("rune", WorldMaterials.glow(Color("#8fb4ff"), 2.4))
	b.material("cloth", WorldMaterials.lit())
	var sides := 18
	var gate_half := deg_to_rad(5.2)
	var corners: Array[Vector2] = []
	for i in sides:
		var a := TAU * i / sides + 0.11
		corners.append(Vector2(cos(a), sin(a)) * (WALL_RADIUS + 0.25 * sin(i * 2.3)))
	for i in sides:
		var p0: Vector2 = corners[i]
		var p1: Vector2 = corners[(i + 1) % sides]
		var length := p0.distance_to(p1)
		var pieces := maxi(1, int(length / 0.3) if base_level <= 2 else int(length / 0.45))
		for k in pieces:
			var t0 := float(k) / pieces
			var t1 := float(k + 1) / pieces
			var q0 := p0.lerp(p1, t0)
			var q1 := p0.lerp(p1, t1)
			var mid := (q0 + q1) * 0.5
			var a := atan2(mid.y, mid.x)
			if absf(wrapf(a - GATE_ANGLE, -PI, PI)) < gate_half: continue
			var dir := (q1 - q0).normalized()
			var yaw := atan2(dir.x, dir.y)
			var h := ground_height(mid)
			if base_level <= 2:
				# palizzata di pali appuntiti
				var stake_h := 1.45 + 0.18 * sin(k * 3.7 + i)
				b.cylinder("weathered", 0.14, 0.15, stake_h, Vector3(mid.x, h + stake_h * 0.5 - 0.1, mid.y), Color(1, 1, 1) if k % 2 == 0 else Color(0.9, 0.88, 0.85), 7, Vector3(0, k, 0), false, MeshBuilder.UV.LONG)
				b.cone("weathered", 0.14, 0.3, Vector3(mid.x, h + stake_h + 0.05, mid.y), Color(0.95, 0.92, 0.88), 7)
			else:
				b.box("stone", Vector3(0.7, 1.35, q0.distance_to(q1) + 0.02), Vector3(mid.x, h + 0.6, mid.y), Color.WHITE, Vector3(0, yaw, 0))
				if k % 2 == 0: b.box("stone", Vector3(0.74, 0.3, q0.distance_to(q1) * 0.6), Vector3(mid.x, h + 1.42, mid.y), Color(0.95, 0.95, 0.95), Vector3(0, yaw, 0))
		if base_level <= 2:
			# traverse della palizzata
			var mid_seg := (p0 + p1) * 0.5
			var a2 := atan2(mid_seg.y, mid_seg.x)
			if absf(wrapf(a2 - GATE_ANGLE, -PI, PI)) > gate_half + 0.12:
				var dir2 := (p1 - p0).normalized()
				b.box("timber", Vector3(0.08, 0.1, length), Vector3(mid_seg.x, ground_height(mid_seg) + 0.6, mid_seg.y) - Vector3(dir2.y, 0, -dir2.x) * 0.12, Color.WHITE, Vector3(0, atan2(dir2.x, dir2.y), 0), MeshBuilder.UV.LONG)
	# porta verso il Portale
	var gdir := Vector3(cos(GATE_ANGLE), 0, sin(GATE_ANGLE))
	var gside := Vector3(-gdir.z, 0, gdir.x)
	var gpos := gdir * WALL_RADIUS
	var gyaw := atan2(gdir.x, gdir.z)
	if base_level <= 1:
		for s in [-1.0, 1.0]:
			b.cylinder("timber", 0.16, 0.18, 2.4, gpos + gside * float(s) * 1.25 + Vector3(0, 1.1, 0), Color.WHITE, 7, Vector3.ZERO, true, MeshBuilder.UV.LONG)
		b.box("timber", Vector3(3.0, 0.22, 0.22), gpos + Vector3(0, 2.2, 0), Color.WHITE, Vector3(0, gyaw, 0), MeshBuilder.UV.LONG)
	else:
		for s in [-1.0, 1.0]:
			var tower := gpos + gside * float(s) * 1.75
			b.box("stone", Vector3(1.3, 2.9, 1.3), tower + Vector3(0, 1.4, 0), Color.WHITE, Vector3(0, gyaw, 0))
			b.box("dark", Vector3(1.45, 0.25, 1.45), tower + Vector3(0, 2.95, 0), Color.WHITE, Vector3(0, gyaw, 0))
			b.cone("roof", 1.05, 1.3, tower + Vector3(0, 3.7, 0), Color.WHITE, 4, Vector3(0, gyaw + PI / 4, 0))
		b.box("stone", Vector3(1.0, 0.7, 2.3), gpos + Vector3(0, 2.6, 0), Color.WHITE, Vector3(0, gyaw + PI / 2, 0))
		b.push(Transform3D(Basis(Vector3.UP, gyaw), gpos + Vector3(0, 2.25, 0)))
		b.arch("stone", 1.05, 1.3, 1.0, Vector3.ZERO, Color.WHITE, Vector3.ZERO, 10)
		b.pop()
		if base_level >= 5:
			for s in [-1.0, 1.0]: b.box("cloth", Vector3(0.05, 1.2, 0.6), gpos + gside * float(s) * 1.75 + gdir * -0.68 + Vector3(0, 2.0, 0), Color("#7a5a20"), Vector3(0, gyaw + PI / 2, 0))
	# torri sulle mura
	if base_level >= 4:
		for deg in [40.0, 130.0, 220.0]:
			var tp := polar(deg, WALL_RADIUS)
			var tpos := Vector3(tp.x, ground_height(tp), tp.y)
			b.cylinder("stone", 1.0, 1.15, 3.6, tpos + Vector3(0, 1.8, 0), Color.WHITE, 12)
			b.cylinder("dark", 1.2, 1.2, 0.25, tpos + Vector3(0, 3.65, 0), Color.WHITE, 12)
			b.cone_roof("roof", 1.4, 1.9, 3.75, Color.WHITE, 12, tpos)
			b.box("rune", Vector3(0.08, 0.6, 0.02), tpos + Vector3(0, 2.2, 0) - Vector3(tp.x, 0, tp.y).normalized() * 1.0, Color.WHITE, Vector3(0, atan2(tp.x, tp.y), 0))
			if base_level >= 5: b.box("cloth", Vector3(0.05, 1.1, 0.55), tpos + Vector3(0, 2.4, 0) - Vector3(tp.x, 0, tp.y).normalized() * 1.08 + Vector3(-tp.y, 0, tp.x).normalized() * 0.5, Color("#7a5a20"), Vector3(0, atan2(tp.x, tp.y), 0))
	b.instance(_wall_holder)

func _build_decor(base_level: int) -> void:
	if _decor_holder != null: _decor_holder.queue_free()
	for f in floaters.duplicate():
		if f.has_meta("decor"):
			floaters.erase(f)
	_decor_holder = Node3D.new()
	_decor_holder.name = "TownDecor"
	decor_root.add_child(_decor_holder)
	var b := MeshBuilder.new()
	b.material("stone", WorldMaterials.stone("wall"))
	b.material("pale", WorldMaterials.stone("pale"))
	b.material("dark", WorldMaterials.stone("dark"))
	b.material("timber", WorldMaterials.wood("timber"))
	b.material("planks", WorldMaterials.wood("planks"))
	b.material("light", WorldMaterials.wood("light"))
	b.material("metal", WorldMaterials.metal(Color.WHITE, 0.5, 0.7))
	b.material("cloth", WorldMaterials.lit())
	b.material("roof", WorldMaterials.roof("shingle" if base_level < 3 else "slate"))
	b.material("thatch", WorldMaterials.roof("thatch"))
	b.material("lamp", WorldMaterials.glow(Color("#ffb35c"), 3.2))
	b.material("rune", WorldMaterials.glow(Color("#7fd2ff"), 2.0))
	b.material("crops", WorldMaterials.foliage(false))
	b.material("ground", WorldMaterials.terrain())
	# pozzo vicino alla piazza
	var well := polar(150, PLAZA_RADIUS + 1.3)
	var wp := Vector3(well.x, 0, well.y)
	b.cylinder("stone", 0.5, 0.55, 0.62, wp + Vector3(0, 0.31, 0), Color.WHITE, 12)
	b.cylinder("cloth", 0.4, 0.4, 0.02, wp + Vector3(0, 0.55, 0), Color("#14202a"), 12)
	for s in [-1.0, 1.0]: b.box("timber", Vector3(0.08, 1.1, 0.08), wp + Vector3(s * 0.48, 0.85, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.push_at(wp + Vector3(0, 1.45, 0))
	b.gable_roof("roof" if base_level >= 2 else "thatch", 1.1, 0.8, 0.35, 0.0, Color.WHITE, 0.12, 0.05)
	b.pop()
	b.cylinder("light", 0.06, 0.06, 0.95, wp + Vector3(0, 1.22, 0), Color.WHITE, 6, Vector3(0, 0, PI / 2))
	# orti
	for g in GARDENS:
		var gp := polar(g.x, g.y)
		var yaw := deg_to_rad(-g.x) + PI / 2
		b.push_at(Vector3(gp.x, ground_height(gp), gp.y), yaw)
		for row in 4:
			b.box("ground", Vector3(2.2, 0.08, 0.32), Vector3(0, 0.04, -0.75 + row * 0.5), Color(1, 0, 0, 0.9))
			for k in 6:
				var green := Color("#4f7a2c") if row % 2 == 0 else Color("#6b8a34")
				b.sphere("crops", 0.13, Vector3(-0.9 + k * 0.36, 0.14, -0.75 + row * 0.5), green, Vector3(1.0, 0.8, 1.0), 6, 4)
		for s in [-1.0, 1.0]:
			for k in 5:
				b.box("timber", Vector3(0.06, 0.5, 0.06), Vector3(-1.3 + k * 0.65, 0.25, s * 1.1), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
			b.box("timber", Vector3(2.7, 0.05, 0.04), Vector3(0, 0.38, s * 1.1), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
		b.pop()
	# torce attorno alla piazza (Lv.1) o lampioni (Lv.2+)
	var lamp_spots: Array[Vector3] = []
	for a in SPOKES:
		for s in [-1.0, 1.0]:
			var dir := Vector2(cos(a), sin(a))
			var p := dir * (PLAZA_RADIUS + 0.4) + Vector2(-dir.y, dir.x) * 1.15 * float(s)
			lamp_spots.append(Vector3(p.x, 0, p.y))
	if base_level >= 2:
		for i in 12:
			var a := TAU * i / 12.0 + 0.13
			var p := Vector2(cos(a), sin(a)) * (RING_RADIUS + RING_WIDTH * 0.5 + 0.35)
			if _road_distance(p, "apron") < 0.4 or _road_distance(p, "gate") < 0.4: continue
			lamp_spots.append(Vector3(p.x, 0, p.y))
	var lamp_count := 0
	for spot_index in lamp_spots.size():
		var spot: Vector3 = lamp_spots[spot_index]
		if base_level <= 1:
			if spot_index % 2 == 1: continue
			b.cylinder("timber", 0.04, 0.05, 1.35, spot + Vector3(0, 0.67, 0), Color.WHITE, 6, Vector3.ZERO, true, MeshBuilder.UV.LONG)
			b.cylinder("metal", 0.08, 0.05, 0.12, spot + Vector3(0, 1.4, 0), Color("#2f2c29"), 8)
			b.sphere("lamp", 0.08, spot + Vector3(0, 1.52, 0), Color.WHITE, Vector3(1, 1.5, 1), 6, 4)
		else:
			b.cylinder("metal", 0.035, 0.05, 1.7, spot + Vector3(0, 0.85, 0), Color("#2b2a28"), 8)
			b.box("metal", Vector3(0.2, 0.04, 0.2), spot + Vector3(0, 1.72, 0), Color("#2b2a28"))
			b.box("lamp", Vector3(0.13, 0.2, 0.13), spot + Vector3(0, 1.84, 0))
			b.cone("metal", 0.14, 0.12, spot + Vector3(0, 2.0, 0), Color("#2b2a28"), 4)
			if base_level >= 3 and lamp_count % 3 == 0:
				b.box("cloth", Vector3(0.03, 0.55, 0.28), spot + Vector3(0, 1.35, 0.15), Color("#6e2a2a") if base_level < 5 else Color("#7a5a20"))
		_light_pool(spot + Vector3(0, 0.04, 0), Color("#ffae5a"), 1.6, 0.32, _decor_holder)
		lamp_count += 1
	# panchine attorno alla piazza
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0 + 0.1
		var p := Vector2(cos(a), sin(a)) * (PLAZA_RADIUS - 0.7)
		b.push_at(Vector3(p.x, 0, p.y), atan2(-p.x, -p.y))
		b.box("planks", Vector3(1.0, 0.05, 0.26), Vector3(0, 0.23, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
		b.box("planks", Vector3(1.0, 0.24, 0.04), Vector3(0, 0.38, -0.12), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
		for s in [-0.4, 0.4]: b.box("stone" if base_level >= 3 else "timber", Vector3(0.08, 0.22, 0.24), Vector3(s, 0.11, 0))
		b.pop()
	# bancarelle del mercato
	if base_level >= 2:
		var stalls := [Vector2(60, 3.1)] if base_level < 3 else [Vector2(60, 3.1), Vector2(240, 3.1), Vector2(330, 3.2)]
		var cloths := [Color("#7a3b2c"), Color("#3f5a6b"), Color("#6b5a2c")]
		for i in stalls.size():
			var sp := polar(stalls[i].x, stalls[i].y)
			b.push_at(Vector3(sp.x, 0, sp.y), atan2(-sp.x, -sp.y))
			b.box("planks", Vector3(1.3, 0.08, 0.6), Vector3(0, 0.55, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
			for sx in [-0.6, 0.6]:
				for sz in [-0.26, 0.26]: b.box("timber", Vector3(0.06, 1.25 if sz < 0 else 0.55, 0.06), Vector3(sx, (1.25 if sz < 0 else 0.55) * 0.5, sz), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
			b.push(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 1.15, 0.05)))
			b.box("cloth", Vector3(1.45, 0.03, 0.85), Vector3.ZERO, cloths[i % cloths.size()])
			b.pop()
			for k in 4: b.sphere("cloth", 0.08, Vector3(-0.45 + k * 0.3, 0.64, 0.05), [Color("#b8475a"), Color("#d9a94a"), Color("#7a9a3a"), Color("#c96a2a")][k], Vector3(1, 0.8, 1), 6, 4)
			b.pop()
	# fontana (Lv.3+)
	if base_level >= 3:
		var fp := polar(FOUNTAIN.x, FOUNTAIN.y)
		b.cylinder("pale", 0.75, 0.8, 0.35, Vector3(fp.x, 0.175, fp.y), Color.WHITE, 16)
		b.cylinder("cloth", 0.66, 0.66, 0.02, Vector3(fp.x, 0.32, fp.y), Color("#33475a"), 16)
		b.cylinder("pale", 0.12, 0.16, 0.8, Vector3(fp.x, 0.55, fp.y), Color.WHITE, 8)
		b.cylinder("pale", 0.35, 0.3, 0.1, Vector3(fp.x, 0.95, fp.y), Color.WHITE, 12)
	# statue ai lati della strada del Portale (Lv.4+)
	if base_level >= 4:
		var gdir := Vector2(cos(GATE_ANGLE), sin(GATE_ANGLE))
		for s in [-1.0, 1.0]:
			var p := gdir * (RING_RADIUS + 2.6) + Vector2(-gdir.y, gdir.x) * 1.6 * float(s)
			var pos := Vector3(p.x, 0, p.y)
			b.box("pale", Vector3(0.7, 0.7, 0.7), pos + Vector3(0, 0.35, 0))
			b.cylinder("pale", 0.16, 0.2, 1.1, pos + Vector3(0, 1.25, 0), Color.WHITE, 8)
			b.sphere("pale", 0.13, pos + Vector3(0, 1.95, 0), Color.WHITE, Vector3(0.9, 1.1, 1.0), 8, 5)
			b.rod("pale", pos + Vector3(0.18, 1.3, 0), pos + Vector3(0.22, 2.3, 0.1), 0.03, 0.025, Color.WHITE, 5)
			b.box("rune", Vector3(0.05, 0.3, 0.02), pos + Vector3(0, 0.4, 0.36), Color.WHITE, Vector3(0, atan2(-p.x, -p.y), 0))
	# carretti, casse e barili sparsi
	var props := [[200.0, 8.6], [44.0, 8.7], [300.0, 9.0]]
	for i in props.size():
		var pp := polar(props[i][0], props[i][1])
		if _road_distance(pp) < 0.3: continue
		var pos := Vector3(pp.x, 0, pp.y)
		if i == 0:
			b.push_at(pos, deg_to_rad(props[i][0]))
			b.box("planks", Vector3(1.2, 0.35, 0.7), Vector3(0, 0.5, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
			for s in [-1.0, 1.0]: b.cylinder("timber", 0.32, 0.32, 0.06, Vector3(0.1, 0.32, s * 0.38), Color.WHITE, 12, Vector3(PI / 2, 0, 0))
			b.rod("timber", Vector3(0.6, 0.45, 0.15), Vector3(1.4, 0.15, 0.2), 0.03, 0.03, Color.WHITE, 5)
			b.rod("timber", Vector3(0.6, 0.45, -0.15), Vector3(1.4, 0.15, -0.2), 0.03, 0.03, Color.WHITE, 5)
			b.pop()
		else:
			for k in 2: b.box("planks", Vector3(0.36, 0.36, 0.36), pos + Vector3(k * 0.4, 0.18, 0), Color(1, 0.95, 0.85))
			b.cylinder("planks", 0.16, 0.16, 0.42, pos + Vector3(-0.35, 0.21, 0.2), Color.WHITE, 10, Vector3.ZERO, true, MeshBuilder.UV.LONG)
	b.instance(_decor_holder)
	# lanterne sospese che fluttuano (Lv.5)
	if base_level >= 5:
		for i in 10:
			var a := TAU * i / 10.0
			var lantern := MeshBuilder.new()
			lantern.material("g", WorldMaterials.glow(Color("#ffd27a"), 3.0))
			lantern.sphere("g", 0.14, Vector3.ZERO, Color.WHITE, Vector3(1, 1.3, 1), 8, 5)
			var mi := lantern.instance(_decor_holder, false)
			mi.position = Vector3(cos(a) * (PLAZA_RADIUS + 1.5), 4.2 + (i % 3) * 0.6, sin(a) * (PLAZA_RADIUS + 1.5))
			mi.set_meta("bob", mi.position.y)
			mi.set_meta("decor", true)
			floaters.append(mi)
	if look.has("sky"): (look.sky as ShaderMaterial).set_shader_parameter("aurora", 1.0 if base_level >= 5 else 0.0)

# =============================================================================
# Aggiornamento dallo stato di gioco
# =============================================================================

func refresh(state: RiftwardState) -> void:
	_apply_light(state.light_preset())
	var base_level := state.base_level()
	var signature := ""
	var level_changed := base_level != current_base_level
	var sites_now := {}
	for id in SITES:
		var status := ""
		if state.facility_built(id): status = "built:%d" % state.facility_level(id)
		elif state.facility_available(id): status = "plot"
		if not status.is_empty(): sites_now[id] = true
		signature += id + "=" + status + ";"
		if building_states.get(id, "") != status or (level_changed and not status.is_empty()):
			_place_building(id, status, base_level)
			building_states[id] = status
	var layout_changed := sites_now.keys() != active_sites.keys()
	active_sites = sites_now
	if level_changed:
		current_base_level = base_level
	if level_changed or layout_changed:
		_define_roads()
		_build_terrain(base_level)
		_build_vegetation()
	if level_changed:
		_build_walls(base_level)
		_build_decor(base_level)
	if signature != occupied_signature or level_changed:
		occupied_signature = signature
		_build_navigation()
		for agent in agents.values(): agent.reset_route()
		_sync_villagers(base_level)
	_update_labels(state)
	_sync_agents(state)

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
	if id == "gate" and status != "plot": model.scale = Vector3.ONE * 1.15
	building_root.add_child(model)
	buildings[id] = model
	if current_base_level >= 0: _spawn_dust(model.position + Vector3(0, 0.6, 0))
	if not labels.has(id): _make_label(id, Vector3.ZERO, "")
	var label_height := model.top_height * model.scale.y + 0.5
	if id == "gate": label_height = model.top_height * model.scale.y * 0.78
	labels[id].position = model.position + Vector3(0, label_height, 0)
	sublabels[id].position = labels[id].position
	badges[id].position = labels[id].position
	_set_label_visible(id, true)

# =============================================================================
# Etichette e segnalazioni
# =============================================================================

func _make_label(id: String, pos: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.font = UIKit.title_font()
	label.font_size = 19
	label.outline_size = 10
	label.outline_modulate = Color(0.06, 0.04, 0.07, 0.92)
	label.modulate = Color("#f1e6cf")
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
	sub.outline_size = 8
	sub.outline_modulate = Color(0.06, 0.04, 0.07, 0.92)
	sub.modulate = Color("#e2c08a")
	sub.pixel_size = 0.0007
	sub.fixed_size = true
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.no_depth_test = true
	sub.render_priority = 2
	sub.outline_render_priority = 1
	sub.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	sub.position = pos
	sub.visible = false
	fx_root.add_child(sub)
	sublabels[id] = sub
	var badge := Sprite3D.new()
	badge.texture = _badge_texture()
	badge.pixel_size = 0.0005
	badge.fixed_size = true
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.render_priority = 3
	badge.position = pos
	badge.offset = Vector2(-140, 16)
	badge.visible = false
	fx_root.add_child(badge)
	badges[id] = badge

static var _badge_tex: ImageTexture

## Losanga dorata con il punto esclamativo: segnala solo novità reali.
static func _badge_texture() -> ImageTexture:
	if _badge_tex != null: return _badge_tex
	var size := 56
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var d := (absf(p.x) + absf(p.y)) / (size * 0.5)
			var col := Color(0, 0, 0, 0)
			if d < 0.98: col = Color("#e2c08a")
			if d < 0.84: col = Color("#8a1f2c")
			if d < 0.84 and d > 0.76: col = Color("#5c121c")
			var ex := absf(p.x) < 2.6 and p.y > -13.0 and p.y < 4.0
			var dot := Vector2(p.x, p.y - 9.0).length() < 3.0
			if (ex or dot) and d < 0.84: col = Color("#f6ead2")
			col.a *= clampf((0.98 - d) * 30.0, 0.0, 1.0)
			img.set_pixel(x, y, col)
	_badge_tex = ImageTexture.create_from_image(img)
	return _badge_tex

func _place_badge(id: String) -> void:
	var label: Label3D = labels[id]
	var width := UIKit.title_font().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	badges[id].offset.x = -(width * label.pixel_size / 0.0005 * 0.5 + 34.0)

func _set_label_visible(id: String, value: bool) -> void:
	if labels.has(id):
		labels[id].visible = value
		if not value:
			sublabels[id].visible = false
			badges[id].visible = false

func _update_labels(state: RiftwardState) -> void:
	for id in labels:
		if id == "crystal":
			sublabels[id].text = "Evocazione · Base Lv.%d" % state.base_level()
			badges[id].visible = state.can_upgrade_base().ok or state.emergency_recruit_status().ok
			continue
		var status: String = building_states.get(id, "")
		if status.is_empty(): continue
		var info: Dictionary = state.FACILITIES[id]
		if status == "plot":
			labels[id].text = str(info.short)
			if id != hovered_id: labels[id].modulate = _label_color(id)
			sublabels[id].text = "Cantiere · %s Oro" % state.format_number(info.build_cost)
			badges[id].visible = state.can_afford({"gold": int(info.build_cost)})
			continue
		labels[id].text = str(info.short)
		if id != hovered_id: labels[id].modulate = _label_color(id)
		var line := "Lv.%d" % state.facility_level(id)
		var alert := false
		match id:
			"training":
				line += " · in allenamento %d/%d" % [state.assigned_to("training").size(), state.training_slots()]
				alert = state.assigned_to("training").is_empty() and _has_trainable(state)
			"dormitory":
				line += " · a riposo %d/%d" % [state.assigned_to("dormitory").size(), state.dormitory_slots()]
				alert = _has_tired(state) and state.assigned_to("dormitory").size() < state.dormitory_slots()
			"merging":
				alert = _has_promotable(state)
			"gate":
				line += " · Piano %d" % int(state.data.world.current_floor)
				alert = int(state.data.world.max_floor) > int(state.data.world.get("seen_floor", 0))
		sublabels[id].text = line
		badges[id].visible = alert
	for id in badges:
		if badges[id].visible: _place_badge(id)
	_refresh_sublabels()

func _refresh_sublabels() -> void:
	for id in sublabels:
		sublabels[id].visible = labels[id].visible and (id == hovered_id or id == selected_id)

## Evita che le etichette si sovrappongano sullo schermo: quelle più lontane
## (più in alto sullo schermo) salgono quanto basta.
func _declutter_labels() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null: return
	var items := []
	for id in labels:
		var l: Label3D = labels[id]
		if not l.visible or cam.is_position_behind(l.global_position): continue
		var w := UIKit.title_font().get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x
		var extra := 22.0 if sublabels[id].visible else 0.0
		items.append({"id": id, "pos": cam.unproject_position(l.global_position), "w": w + 8.0, "h": 26.0 + extra})
	items.sort_custom(func(a, b): return a.pos.y > b.pos.y)
	var placed: Array[Rect2] = []
	for item in items:
		var rect := Rect2(item.pos + Vector2(-item.w * 0.5, -26.0), Vector2(item.w, item.h))
		var lift := 0.0
		for attempt in 6:
			var hit := false
			for r in placed:
				if r.intersects(rect):
					var needed: float = rect.end.y - r.position.y + 3.0
					rect.position.y -= needed
					lift += needed
					hit = true
					break
			if not hit: break
		placed.append(rect)
		var id: String = item.id
		labels[id].offset = Vector2(0, lift)
		sublabels[id].offset = Vector2(0, lift)
		badges[id].offset.y = 18.0 + lift / 0.0005 * 0.0007

func _has_trainable(state: RiftwardState) -> bool:
	for hero in state.get_alive_heroes():
		if state.hero_activity(hero) == "idle" and int(hero.level) < state.level_cap(hero) and hero.injuries.is_empty() and int(hero.fatigue) < 60: return true
	return false

func _has_tired(state: RiftwardState) -> bool:
	for hero in state.get_alive_heroes():
		if state.data.assignments.has(hero.id): continue
		if not hero.injuries.is_empty() or int(hero.fatigue) >= 70: return true
	return false

func _has_promotable(state: RiftwardState) -> bool:
	for hero in state.get_alive_heroes():
		if state.promotion_requirements(hero).ok: return true
	return false

func _spawn_dust(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = true
	p.amount = 22
	p.lifetime = 1.4
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 85.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -0.8, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.albedo_texture = WorldMaterials.soft_texture(48, Color(0.75, 0.68, 0.58, 0.55))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = m
	p.mesh = mesh
	fx_root.add_child(p)
	if is_inside_tree(): get_tree().create_timer(2.0).timeout.connect(p.queue_free)

# =============================================================================
# Navigazione: piazza, raggi, anello, ingressi
# =============================================================================

func _nav_add(key: String, pos: Vector3) -> int:
	if nav_points.has(key): return nav_points[key]
	var id := nav.get_available_point_id()
	nav.add_point(id, pos)
	nav_points[key] = id
	return id

func _nav_link(a: int, b: int) -> void:
	if a >= 0 and b >= 0 and a != b: nav.connect_points(a, b)

func _build_navigation() -> void:
	nav.clear()
	nav_points.clear()
	plaza_nodes.clear()
	ring_nodes.clear()
	wander_nodes.clear()
	site_nodes.clear()
	# piazza: due anelli attorno al piedistallo
	for i in 12:
		var a := TAU * i / 12.0
		plaza_nodes.append(_nav_add("plaza_o_%d" % i, Vector3(cos(a), 0, sin(a)) * 3.5))
	for i in 12:
		var a := TAU * (i + 0.5) / 12.0
		plaza_nodes.append(_nav_add("plaza_i_%d" % i, Vector3(cos(a), 0, sin(a)) * 2.6))
	for i in plaza_nodes.size():
		for j in range(i + 1, plaza_nodes.size()):
			if nav.get_point_position(plaza_nodes[i]).distance_to(nav.get_point_position(plaza_nodes[j])) < 1.95: _nav_link(plaza_nodes[i], plaza_nodes[j])
	wander_nodes.append_array(plaza_nodes)
	# anello
	var ring_count := 40
	for i in ring_count:
		var a := TAU * i / ring_count
		ring_nodes.append(_nav_add("ring_%d" % i, Vector3(cos(a), 0, sin(a)) * RING_RADIUS))
	for i in ring_count:
		_nav_link(ring_nodes[i], ring_nodes[(i + 1) % ring_count])
		if i % 3 == 0: wander_nodes.append(ring_nodes[i])
	# raggi
	for s in SPOKES.size():
		var a: float = SPOKES[s]
		var dir := Vector3(cos(a), 0, sin(a))
		var prev := _nearest_of(plaza_nodes, dir * 3.5)
		var steps := 3
		for k in range(1, steps):
			var node := _nav_add("spoke_%d_%d" % [s, k], dir * lerpf(3.5, RING_RADIUS, float(k) / steps))
			_nav_link(prev, node)
			prev = node
		_nav_link(prev, _nearest_of(ring_nodes, dir * RING_RADIUS))
	# strada del Portale fino alla rupe
	var gdir := Vector3(cos(GATE_ANGLE), 0, sin(GATE_ANGLE))
	var bridge: Array = get_meta("gate_bridge", [gdir * 19.0, gate_center()])
	var prev_gate := _nearest_of(ring_nodes, gdir * RING_RADIUS)
	var road_pts: Array[Vector3] = []
	var start_r := RING_RADIUS + 1.2
	var end_r := Vector2(bridge[0].x, bridge[0].z).length()
	var count := int((end_r - start_r) / 1.4)
	for k in count + 1:
		var r := lerpf(start_r, end_r, float(k) / count)
		var p := gdir * r
		p.y = ground_height(Vector2(p.x, p.z))
		road_pts.append(p)
	var bridge_start: Vector3 = bridge[0]
	var bridge_end: Vector3 = bridge[1]
	for k in 5:
		var t := float(k + 1) / 5.0
		var p := bridge_start.lerp(bridge_end, t)
		p.y = lerpf(bridge_start.y, bridge_end.y, t) + sin(t * PI) * 0.18 + 0.06
		road_pts.append(p)
	for k in road_pts.size():
		var node := _nav_add("gate_road_%d" % k, road_pts[k])
		_nav_link(prev_gate, node)
		prev_gate = node
	# ingressi e posti di ogni struttura
	for id in buildings:
		var model: BuildingModel = buildings[id]
		var door := _nav_add(id + "_door", _to_world(model, model.door_local))
		if id == "gate": _nav_link(prev_gate, door)
		else:
			var site_dir := Vector3(model.position.x, 0, model.position.z).normalized()
			var ring_entry := _nearest_of(ring_nodes, site_dir * RING_RADIUS)
			_nav_link(ring_entry, door)
		var via := door
		if id == "training":
			var top := _nav_add("training_top", _to_world(model, Vector3(0, 1.1, 1.6)))
			var mid := _nav_add("training_steps", _to_world(model, Vector3(0, 0.55, 2.9)))
			_nav_link(door, mid)
			_nav_link(mid, top)
			via = top
		var spots: Array[int] = []
		for i in model.spots_local.size():
			var spot := _nav_add("%s_spot_%d" % [id, i], _to_world(model, model.spots_local[i]))
			_nav_link(via, spot)
			spots.append(spot)
		site_nodes[id] = {"door": door, "spots": spots}
	# panchine e orti come mete di passeggio
	for g in GARDENS:
		var gp := polar(g.x, g.y - 1.6)
		var node := _nav_add("garden_%d" % int(g.x), Vector3(gp.x, 0, gp.y))
		_nav_link(node, _nearest_of(ring_nodes, Vector3(gp.x, 0, gp.y).normalized() * RING_RADIUS))
		wander_nodes.append(node)

func _nearest_of(nodes: Array[int], pos: Vector3) -> int:
	var best := -1
	var best_d := INF
	for n in nodes:
		var d := nav.get_point_position(n).distance_to(pos)
		if d < best_d:
			best_d = d
			best = n
	return best

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
		var dummies: Array = model.get_meta("dummies", [])
		if spot_index < dummies.size(): return _to_world(model, dummies[spot_index] + Vector3(0, 0.5, 0))
		if spot_index == 3: return _to_world(model, model.spots_local[4] if model.spots_local.size() > 4 else Vector3.ZERO)
		if spot_index == 4: return _to_world(model, model.spots_local[3])
		return _to_world(model, Vector3(0, 1.0, 0))
	return _to_world(model, Vector3.ZERO)

# =============================================================================
# Eroi e abitanti
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

## Pochi abitanti che animano il borgo: crescono con il livello della base.
func _sync_villagers(base_level: int) -> void:
	var wanted := 2 + base_level
	while villagers.size() > wanted:
		villagers.pop_back().queue_free()
	while villagers.size() < wanted:
		var v: HubAgent = HubAgentScript.new()
		agent_root.add_child(v)
		v.setup_villager(self, 9000 + villagers.size() * 37)
		var node: int = wander_nodes[(villagers.size() * 7) % maxi(1, wander_nodes.size())] if not wander_nodes.is_empty() else -1
		v.position = node_position(node) if node >= 0 else Vector3(0, 0, 4)
		villagers.append(v)
	for v in villagers: v.reset_route()

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
		agent.speed = 3.2
		i += 1
	var gate: BuildingModel = buildings.get("gate")
	var waited := 0.0
	while waited < 8.0:
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
		if agent != null:
			agent.visible = false
			agent.set_collision_enabled(false)
	await get_tree().create_timer(0.3).timeout
	if gate != null and gate.portal_material != null: gate.portal_material.set_shader_parameter("intensity", 1.0)

func restore_agents() -> void:
	for agent in agents.values():
		agent.release_goal()

# =============================================================================
# Interazione
# =============================================================================

func set_hovered(id: String) -> void:
	if id == hovered_id: return
	if buildings.has(hovered_id) and hovered_id != selected_id: buildings[hovered_id].set_highlight(0.0)
	if labels.has(hovered_id): labels[hovered_id].modulate = _label_color(hovered_id)
	hovered_id = id
	if buildings.has(id) and id != selected_id: buildings[id].set_highlight(0.12)
	if labels.has(id): labels[id].modulate = Color("#ffdf9e")
	_refresh_sublabels()

func _label_color(id: String) -> Color:
	return Color("#c9b99a") if building_states.get(id, "") == "plot" else Color("#f1e6cf")

func set_selected(id: String) -> void:
	if buildings.has(selected_id): buildings[selected_id].set_highlight(0.0)
	selected_id = id
	if buildings.has(id): buildings[id].set_highlight(0.18)
	_refresh_sublabels()

func focus_position(id: String) -> Vector3:
	if id == "crystal": return Vector3(0, 1.2, 0)
	if id == "gate" and buildings.has(id): return buildings[id].position + Vector3(0, 3.6, 0)
	if buildings.has(id): return buildings[id].position + Vector3(0, 1.4, 0)
	return Vector3.ZERO

func _process(delta: float) -> void:
	time += delta
	if crystal != null:
		crystal.position.y = 2.6 + sin(time * 1.2) * 0.12
		for child in crystal.get_children():
			if child.has_meta("spin"): child.rotation.y = time * 0.45
			elif child.has_meta("angle"):
				var a := float(child.get_meta("angle")) + time * 0.9
				child.position = Vector3(cos(a) * 1.15, 0.2 + sin(time * 1.6 + a) * 0.25, sin(a) * 1.15)
				child.rotation.y = -a
	for n in floaters:
		if is_instance_valid(n): n.position.y = float(n.get_meta("bob")) + sin(time * 0.6 + n.position.x * 0.3) * 0.3
	for agent in agents.values():
		agent.tick(delta)
	for v in villagers:
		v.tick(delta)
	for id in badges:
		var badge: Sprite3D = badges[id]
		if badge.visible: badge.scale = Vector3.ONE * (1.0 + 0.1 * sin(time * 4.0))
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 0.2
		_declutter_labels()
