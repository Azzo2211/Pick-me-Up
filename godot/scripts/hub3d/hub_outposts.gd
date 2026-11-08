extends Node3D


## Isolotti della base: piccole zolle sospese che compaiono crescendo di livello
## (Lv.2, 3, 4, 5, 7), ognuna con un ponte di corda verso l'isola principale.
## Sono solo scenografia (niente bonus di gioco, niente percorsi degli eroi):
## servono a far vedere che la base si allarga a ogni livello, non solo in altezza.
## Coordinate locali come in HubIslands: +Z guarda verso l'isola principale.
## 1 unità = 2 metri.

## angle: gradi (come i siti); distance e height: centro della zolla; radius: raggio medio;
## shape: forma del contorno; depth: altezza della rupe sotto.
const LAYOUT := {
	"vedetta": {"level": 2, "angle": 322.0, "distance": 28.5, "radius": 3.4, "height": 0.9, "shape": 0.7, "depth": 6.0},
	"frutteto": {"level": 3, "angle": 148.0, "distance": 29.5, "radius": 4.4, "height": -0.4, "shape": 2.2, "depth": 7.0},
	"sorgente": {"level": 4, "angle": 34.0, "distance": 28.0, "radius": 3.9, "height": 1.8, "shape": 3.3, "depth": 6.5},
	"miniera": {"level": 5, "angle": 212.0, "distance": 29.0, "radius": 4.1, "height": -0.9, "shape": 4.6, "depth": 7.5},
	"faro": {"level": 7, "angle": 262.0, "distance": 30.5, "radius": 3.1, "height": 2.4, "shape": 5.4, "depth": 6.0},
}
const ORDER := ["vedetta", "frutteto", "sorgente", "miniera", "faro"]

var world: HubWorld
var ids: Array = []
var base_level := 0
var animated: Array[Node3D] = []
var time := 0.0
var noise := FastNoiseLite.new()

func setup(hub: HubWorld) -> void:
	world = hub
	name = "Outposts"
	noise.seed = 51
	noise.frequency = 0.3

## Isolotti presenti a un certo livello della base.
static func ids_for(level: int) -> Array:
	var out := []
	for id in ORDER:
		if level >= int(LAYOUT[id].level): out.append(id)
	return out

# =============================================================================
# Geometria
# =============================================================================

func center(id: String) -> Vector3:
	var info: Dictionary = LAYOUT[id]
	var a := deg_to_rad(float(info.angle))
	return Vector3(cos(a) * float(info.distance), float(info.height), sin(a) * float(info.distance))

func island_yaw(id: String) -> float:
	var c := center(id)
	return atan2(-c.x, -c.z)

func to_world(id: String, local: Vector3) -> Vector3:
	return center(id) + local.rotated(Vector3.UP, island_yaw(id))

func edge(id: String, theta: float) -> float:
	var info: Dictionary = LAYOUT[id]
	var k := float(info.shape)
	return float(info.radius) + 0.3 * sin(2.0 * theta + k) + 0.22 * sin(3.0 * theta + k * 1.7) + 0.12 * sin(5.0 * theta + k * 0.6)

func ground(id: String, p: Vector2) -> float:
	var r := p.length()
	var e := edge(id, atan2(p.y, p.x))
	var bumps := noise.get_noise_2d(p.x + float(LAYOUT[id].shape) * 40.0, p.y) * 0.14 * smoothstep(e - 2.4, e - 1.2, r)
	var rim := -pow(clampf((r - (e - 1.1)) / 1.1, 0.0, 1.0), 2.0) * 0.45
	return bumps + rim

## Il punto dell'isola principale è la testa di un ponte? (niente alberi lì)
func blocks_main(p: Vector2, clearance: float) -> bool:
	for id in ids:
		var a := deg_to_rad(float(LAYOUT[id].angle))
		var dir := Vector2(cos(a), sin(a))
		var start := dir * (world.island_radius(a) - 1.0)
		if Geometry2D.get_closest_point_to_segment(p, start - dir * 0.8, start + dir * 3.0).distance_to(p) < 1.1 + clearance: return true
	return false

## L'isolotto copre questo punto (XZ del mondo)? Serve a nascondere le rupi decorative.
func covers(p: Vector2, margin: float) -> bool:
	for id in ids:
		var c := center(id)
		if Vector2(c.x, c.z).distance_to(p) < float(LAYOUT[id].radius) + margin: return true
	return false

# =============================================================================
# Costruzione
# =============================================================================

func rebuild(level: int) -> void:
	base_level = level
	ids = ids_for(level)
	for child in get_children(): child.queue_free()
	animated.clear()
	for id in ids:
		var holder := Node3D.new()
		holder.name = "Isolotto_" + id
		holder.position = center(id)
		holder.rotation.y = island_yaw(id)
		add_child(holder)
		_build_top(id, holder)
		_build_rock(id, holder)
		var b := _builder()
		match id:
			"vedetta": _build_vedetta(id, holder, b)
			"frutteto": _build_frutteto(id, holder, b)
			"sorgente": _build_sorgente(id, holder, b)
			"miniera": _build_miniera(id, holder, b)
			"faro": _build_faro(id, holder, b)
		b.instance(holder)
		_build_vegetation(id, holder)
		_build_bridge(id)
	for f in world.floaters:
		if not is_instance_valid(f) or not f.has_meta("islet"): continue
		if covers(Vector2(f.position.x, f.position.z), 9.0): f.visible = false

func _builder() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.material("stone", WorldMaterials.stone("wall"))
	mb.material("dark", WorldMaterials.stone("dark"))
	mb.material("pale", WorldMaterials.stone("pale"))
	mb.material("timber", WorldMaterials.wood("timber"))
	mb.material("planks", WorldMaterials.wood("planks"))
	mb.material("light", WorldMaterials.wood("light"))
	mb.material("roof", WorldMaterials.roof("slate"))
	mb.material("shingle", WorldMaterials.roof("shingle"))
	mb.material("thatch", WorldMaterials.roof("thatch"))
	mb.material("metal", WorldMaterials.metal(Color.WHITE, 0.5, 0.7))
	mb.material("cloth", WorldMaterials.lit())
	mb.material("rock", WorldMaterials.terrain())
	mb.material("lamp", WorldMaterials.glow(Color("#ffb35c"), 3.2))
	mb.material("fire", WorldMaterials.glow(Color("#ff8a3a"), 4.0))
	mb.material("rune", WorldMaterials.glow(Color("#7fd2ff"), 2.4))
	return mb

## Maschera del terreno: R sterrato, G selciato, B roccia.
func _mask(id: String, p: Vector2) -> Color:
	var e := edge(id, atan2(p.y, p.x))
	var entry := Vector2(0, e)
	var dirt := smoothstep(0.85, 0.45, Geometry2D.get_closest_point_to_segment(p, entry, Vector2(0, 0.6)).distance_to(p))
	var paved := 0.0
	var rock := smoothstep(e - 0.8, e - 0.1, p.length()) * 0.7
	match id:
		"vedetta": dirt = maxf(dirt, smoothstep(1.6, 1.2, p.length()))
		"miniera": rock = maxf(rock, 0.35 + 0.4 * smoothstep(0.5, -1.5, p.y))
		"faro": paved = smoothstep(1.9, 1.5, p.length())
		"sorgente": rock = maxf(rock, smoothstep(2.2, 1.6, p.distance_to(Vector2(-0.3, -0.5))) * 0.8)
	return Color(clampf(dirt, 0, 1), clampf(paved, 0, 1), clampf(rock, 0, 1), 1.0)

func _build_top(id: String, holder: Node3D) -> void:
	var rings := 12
	var segments := 56
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.append(Vector3(0, ground(id, Vector2.ZERO), 0))
	cols.append(_mask(id, Vector2.ZERO))
	for k in range(1, rings + 1):
		var f := float(k) / rings
		for s in segments:
			var a := TAU * s / segments
			var p := Vector2(cos(a), sin(a)) * edge(id, a) * f
			verts.append(Vector3(p.x, ground(id, p), p.y))
			cols.append(_mask(id, p))
	var indices := PackedInt32Array()
	for s in segments:
		world._tri_idx(indices, verts, 0, 1 + s, 1 + (s + 1) % segments, Vector3.UP)
	for k in range(1, rings):
		var row0 := 1 + (k - 1) * segments
		var row1 := 1 + k * segments
		for s in segments:
			var s2 := (s + 1) % segments
			world._tri_idx(indices, verts, row0 + s, row1 + s, row1 + s2, Vector3.UP)
			world._tri_idx(indices, verts, row0 + s, row1 + s2, row0 + s2, Vector3.UP)
	var lip := verts.size()
	var outer := 1 + (rings - 1) * segments
	for s in segments:
		var v := verts[outer + s]
		var dir := Vector3(v.x, 0, v.z).normalized()
		verts.append(Vector3(v.x + dir.x * 0.25, -0.6, v.z + dir.z * 0.25))
		cols.append(Color(0, 0, 1, 0.8))
	for s in segments:
		var s2 := (s + 1) % segments
		var dir := Vector3(verts[outer + s].x, 0, verts[outer + s].z).normalized()
		world._tri_idx(indices, verts, outer + s, lip + s, lip + s2, dir)
		world._tri_idx(indices, verts, outer + s, lip + s2, outer + s2, dir)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = world._smooth_normals(verts, indices)
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, WorldMaterials.terrain())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)

func _build_rock(id: String, holder: Node3D) -> void:
	var segments := 40
	var layers := 6
	var depth := float(LAYOUT[id].depth)
	var cliff_noise := FastNoiseLite.new()
	cliff_noise.seed = 71 + int(float(LAYOUT[id].shape) * 10.0)
	cliff_noise.frequency = 0.9
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	for l in layers + 1:
		var t := float(l) / layers
		for s in segments:
			var a := TAU * s / segments
			var r := edge(id, a) * (1.0 - pow(t, 1.25) * 0.86) + 0.25 * (1.0 - t)
			var jitter := cliff_noise.get_noise_2d(a * 9.0, l * 2.0) * 0.6 * (1.0 - t * 0.5) * smoothstep(0.0, 0.15, t)
			var y := -0.6 - t * depth + cliff_noise.get_noise_2d(a * 6.0, l * 4.0) * 0.7 * t
			verts.append(Vector3(cos(a) * (r + jitter), y, sin(a) * (r + jitter)))
			cols.append(Color(0, 0, 1, lerpf(0.9, 0.5, t)))
	var tip := verts.size()
	verts.append(Vector3(0.2, -depth - 1.8, -0.2))
	cols.append(Color(0, 0, 1, 0.4))
	for l in layers:
		for s in segments:
			var s2 := (s + 1) % segments
			var a0 := l * segments + s
			var a1 := l * segments + s2
			var b0 := (l + 1) * segments + s
			var b1 := (l + 1) * segments + s2
			var out := Vector3(verts[a0].x, 0, verts[a0].z).normalized()
			world._tri_idx(indices, verts, a0, b0, b1, out)
			world._tri_idx(indices, verts, a0, b1, a1, out)
	for s in segments:
		var a0 := layers * segments + s
		var a1 := layers * segments + (s + 1) % segments
		world._tri_idx(indices, verts, a0, tip, a1, Vector3(verts[a0].x, -2.0, verts[a0].z).normalized())
	world._add_flat_mesh(holder, verts, cols, indices, WorldMaterials.terrain(), true)

## Punti liberi per gli alberi (fuori dal sentiero e dalla costruzione centrale).
func _free_spot(id: String, p: Vector2, clearance: float) -> bool:
	if p.length() < _core_radius(id) + clearance: return false
	if absf(p.x) < 0.9 + clearance and p.y > 0.0: return false
	if id == "frutteto" and p.y < 2.0 and absf(p.x) < 3.4: return false
	return true

func _core_radius(id: String) -> float:
	match id:
		"vedetta": return 1.7
		"frutteto": return 1.3
		"sorgente": return 2.8
		"miniera": return 2.0
		"faro": return 2.0
	return 1.5

func _build_vegetation(id: String, holder: Node3D) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 6100 + int(float(LAYOUT[id].shape) * 100.0)
	var groups := {}
	var placed: Array[Vector2] = []
	var target: int = {"vedetta": 5, "frutteto": 4, "sorgente": 2, "miniera": 3, "faro": 3}[id]
	var attempts := 0
	while placed.size() < target and attempts < 600:
		attempts += 1
		var a := r.randf_range(0, TAU)
		var e := edge(id, a)
		var p := Vector2(cos(a), sin(a)) * r.randf_range(e - 1.6, e - 0.6)
		if not _free_spot(id, p, 0.7) or (p.y > 1.0 and absf(p.x) < 2.0): continue
		var close := false
		for q in placed:
			if q.distance_to(p) < 1.4:
				close = true
				break
		if close: continue
		placed.append(p)
		var kind := "conifer" if r.randf() < (0.8 if id == "vedetta" or id == "faro" else 0.4) else "broadleaf"
		if id == "miniera" and r.randf() < 0.5: kind = "dead"
		var key := "%s_%d" % [kind, r.randi_range(0, 1 if kind == "dead" else 3)]
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(Vector3(p.x, ground(id, p) - 0.05, p.y), r.randf_range(0.6, 0.9), r.randf() * TAU))
	for i in 14:
		var a := r.randf_range(0, TAU)
		var p := Vector2(cos(a), sin(a)) * r.randf_range(1.0, edge(id, a) - 0.5)
		if not _free_spot(id, p, 0.0): continue
		var key := ("bush_%d" if i % 3 != 0 or id == "frutteto" else "rock_%d") % (i % 3)
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(Vector3(p.x, ground(id, p) - 0.05, p.y), r.randf_range(0.5, 0.95), r.randf() * TAU))
	for key in groups:
		var parts := str(key).split("_")
		NatureKit.scatter(holder, parts[0], int(parts[1]), groups[key], true)
	var tufts := [[], []]
	for i in 140:
		var a := r.randf_range(0, TAU)
		var p := Vector2(cos(a), sin(a)) * sqrt(r.randf()) * (edge(id, a) - 0.4)
		if p.length() < _core_radius(id) - 0.2 or absf(p.x) < 0.5 and p.y > 0.0: continue
		tufts[i % 2].append(NatureKit.placement(Vector3(p.x, ground(id, p), p.y), r.randf_range(0.7, 1.2), r.randf() * TAU))
	for v in 2: NatureKit.scatter(holder, "tuft", v, tufts[v], false)

func _g(id: String, x: float, z: float) -> Vector3:
	return Vector3(x, ground(id, Vector2(x, z)), z)

func _lamp(b: MeshBuilder, holder: Node3D, pos: Vector3) -> void:
	b.rod("timber", pos, pos + Vector3(0, 1.4, 0), 0.04, 0.035, Color.WHITE, 6)
	b.rod("timber", pos + Vector3(0, 1.35, 0), pos + Vector3(0.28, 1.35, 0), 0.025, 0.025, Color.WHITE, 4)
	b.box("lamp", Vector3(0.12, 0.17, 0.12), pos + Vector3(0.28, 1.2, 0))
	world._light_pool(pos + Vector3(0.28, 0.04, 0), Color("#ffae5a"), 1.3, 0.3, holder)

# -----------------------------------------------------------------------------
# Vedetta (Lv.2): torre di guardia in legno con braciere e stendardo
# -----------------------------------------------------------------------------

func _build_vedetta(id: String, holder: Node3D, b: MeshBuilder) -> void:
	var base := _g(id, 0, -0.3)
	var h := 3.6
	for sx in [-0.75, 0.75]:
		for sz in [-0.75, 0.75]:
			b.rod("timber", base + Vector3(sx, -0.2, sz), base + Vector3(sx * 0.7, h, sz * 0.7), 0.1, 0.08, Color.WHITE, 6)
	# croci di rinforzo tra le gambe
	var legs := [Vector3(-0.75, 0, -0.75), Vector3(0.75, 0, -0.75), Vector3(0.75, 0, 0.75), Vector3(-0.75, 0, 0.75)]
	for k in 4:
		var l0: Vector3 = legs[k]
		var l1: Vector3 = legs[(k + 1) % 4]
		b.rod("timber", base + l0 * 0.95 + Vector3(0, 0.2, 0), base + l1 * 0.8 + Vector3(0, 2.2, 0), 0.035, 0.035, Color.WHITE, 4)
		b.rod("timber", base + l1 * 0.95 + Vector3(0, 0.2, 0), base + l0 * 0.8 + Vector3(0, 2.2, 0), 0.035, 0.035, Color.WHITE, 4)
	# piattaforma, parapetto, tetto a punta
	b.box("planks", Vector3(1.9, 0.12, 1.9), base + Vector3(0, h, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	for k in 4:
		var a := k * PI / 2.0
		var side := Vector3(cos(a), 0, sin(a)) * 0.9
		b.box("planks", Vector3(0.08 if absf(side.x) > 0.1 else 1.85, 0.5, 1.85 if absf(side.x) > 0.1 else 0.08), base + side + Vector3(0, h + 0.3, 0), Color("#b9a58a"))
	for sx in [-0.85, 0.85]:
		for sz in [-0.85, 0.85]:
			b.rod("timber", base + Vector3(sx, h, sz), base + Vector3(sx, h + 1.25, sz), 0.05, 0.05, Color.WHITE, 5)
	b.cone_roof("thatch", 1.45, 1.1, h + 1.2, Color.WHITE, 8, base)
	b.box("fire", Vector3(0.28, 0.22, 0.28), base + Vector3(0, h + 0.2, 0))
	world._light_pool(base + Vector3(0, h + 0.1, 0), Color("#ff9a4a"), 1.6, 0.4, holder)
	# scala
	b.rod("timber", base + Vector3(-0.25, -0.1, 1.25), base + Vector3(-0.25, h, 0.8), 0.04, 0.04, Color.WHITE, 4)
	b.rod("timber", base + Vector3(0.25, -0.1, 1.25), base + Vector3(0.25, h, 0.8), 0.04, 0.04, Color.WHITE, 4)
	for i in 9:
		var t := (i + 0.5) / 9.0
		b.box("timber", Vector3(0.5, 0.04, 0.06), base + Vector3(0, -0.1 + t * (h + 0.1), lerpf(1.25, 0.8, t)))
	# stendardo
	b.rod("timber", base + Vector3(0.85, h, -0.85), base + Vector3(0.85, h + 2.6, -0.85), 0.03, 0.025, Color.WHITE, 5)
	var flag := MeshBuilder.new()
	flag.material("cloth", WorldMaterials.lit())
	flag.box("cloth", Vector3(0.75, 0.42, 0.02), Vector3(0.38, 0, 0), Color("#7a2f3a"))
	var fm := flag.instance(holder)
	fm.position = base + Vector3(0.85, h + 2.3, -0.85)
	fm.set_meta("wave", 0.0)
	animated.append(fm)
	# casse e una lanterna all'arrivo del ponte
	b.box("planks", Vector3(0.45, 0.4, 0.45), _g(id, 1.4, 0.6) + Vector3(0, 0.18, 0), Color.WHITE, Vector3(0, 0.3, 0))
	b.box("planks", Vector3(0.35, 0.32, 0.35), _g(id, 1.5, 1.1) + Vector3(0, 0.14, 0), Color.WHITE, Vector3(0, -0.4, 0))
	_lamp(b, holder, _g(id, -0.8, edge(id, PI / 2) - 0.9))

# -----------------------------------------------------------------------------
# Frutteto (Lv.3): filari di alberi da frutto, arnie e un capanno
# -----------------------------------------------------------------------------

func _build_frutteto(id: String, holder: Node3D, b: MeshBuilder) -> void:
	var trees: Array = []
	var fruit := MeshBuilder.new()
	fruit.material("fruit", WorldMaterials.lit(Color.WHITE, 0.6))
	for row in 3:
		for col in 3:
			var p := Vector2(-2.2 + col * 2.2, -1.9 + row * 1.6)
			if col == 1: p.x += 0.0
			if absf(p.x) < 0.5: continue
			var pos := _g(id, p.x, p.y)
			trees.append(NatureKit.placement(pos - Vector3(0, 0.05, 0), 0.55, (row * 3 + col) * 1.3))
			for k in 5:
				var a := k * 1.37 + row
				fruit.sphere("fruit", 0.07, pos + Vector3(cos(a) * 0.45, 1.25 + (k % 3) * 0.22, sin(a) * 0.45), Color("#d8432f") if (row + col) % 2 == 0 else Color("#e2a531"), Vector3.ONE, 6, 4)
	NatureKit.scatter(holder, "broadleaf", 2, trees, true)
	fruit.instance(holder)
	# capanno in fondo
	var shed := _g(id, 0.0, -2.5)
	b.push_at(shed, 0.0)
	b.box("planks", Vector3(1.6, 1.0, 1.1), Vector3(0, 0.5, 0), Color.WHITE)
	b.box("timber", Vector3(0.45, 0.75, 0.05), Vector3(0, 0.38, 0.56), Color("#5c4330"))
	b.gable_roof("thatch", 1.6, 1.1, 0.55, 1.0, Color.WHITE, 0.22, 0.06)
	b.pop()
	# arnie
	for k in 3:
		var hp := _g(id, 1.5 + k * 0.45, 1.6 - k * 0.15)
		b.box("light", Vector3(0.32, 0.32, 0.3), hp + Vector3(0, 0.2, 0), Color("#e8d9a8"))
		b.box("timber", Vector3(0.38, 0.05, 0.36), hp + Vector3(0, 0.38, 0))
	# staccionata bassa lungo il sentiero
	for i in 6:
		for sgn in [-1.0, 1.0]:
			var z := 0.6 + i * 0.55
			b.box("timber", Vector3(0.06, 0.4, 0.06), _g(id, sgn * 0.8, z) + Vector3(0, 0.2, 0))
			if i < 5: b.box("timber", Vector3(0.04, 0.05, 0.56), _g(id, sgn * 0.8, z + 0.27) + Vector3(0, 0.32, 0))
	# cesti di frutta
	for k in 2:
		var cp := _g(id, -1.2 + k * 0.4, 1.1)
		b.cylinder("light", 0.17, 0.13, 0.2, cp + Vector3(0, 0.1, 0), Color("#b38a52"), 8)
		b.sphere("lamp", 0.11, cp + Vector3(0, 0.2, 0), Color.WHITE, Vector3(1, 0.5, 1), 6, 4, true)
	_lamp(b, holder, _g(id, 1.0, edge(id, PI / 2) - 0.9))

# -----------------------------------------------------------------------------
# Sorgente (Lv.4): laghetto con rocce e una cascata che scende nel vuoto
# -----------------------------------------------------------------------------

func _build_sorgente(id: String, holder: Node3D, b: MeshBuilder) -> void:
	var pond := Vector2(-0.3, -0.5)
	var pr := 1.35
	var pos := _g(id, pond.x, pond.y)
	for i in 12:
		var a := TAU * i / 12.0 + 0.3
		b.rock("rock", 0.26 + (i % 3) * 0.08, pos + Vector3(cos(a), 0.0, sin(a)) * (pr + 0.25), Color(0, 0, 1, 1), Vector3(1.2, 0.7, 1.0), 300 + i, 0.25)
	# roccia alta da cui sgorga l'acqua
	var spring := pos + Vector3(-0.6, 0, -1.4)
	b.rock("rock", 0.9, spring, Color(0, 0, 1, 1), Vector3(1.0, 1.4, 0.9), 341, 0.3)
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = pr
	disc.bottom_radius = pr
	disc.height = 0.06
	disc.radial_segments = 24
	water.mesh = disc
	water.material_override = world._water_material(0.3, 2.0, 0.92)
	water.position = pos + Vector3(0, 0.02, 0)
	holder.add_child(water)
	# rivolo che va verso il bordo esterno (lato opposto al ponte) e cade
	var dir := Vector2(0.55, -1.0).normalized()
	var start := pond + dir * (pr - 0.2)
	var e := edge(id, atan2(dir.y, dir.x))
	var finish := dir * (e - 0.05)
	var length := start.distance_to(finish)
	var stream := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, length)
	stream.mesh = quad
	stream.material_override = world._water_material(1.4, length * 1.5, 0.95)
	var mid := (start + finish) * 0.5
	stream.position = Vector3(mid.x, ground(id, mid) + 0.05, mid.y)
	stream.rotation = Vector3(-PI / 2, atan2(-dir.x, -dir.y), 0)
	holder.add_child(stream)
	var fall := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.6, 9.0)
	fall.mesh = fq
	fall.material_override = world._water_material(2.2, 7.0, 0.8)
	var outward := Vector3(dir.x, 0, dir.y)
	fall.position = Vector3(finish.x, -4.6, finish.y) + outward * 0.9
	fall.rotation = Vector3(-0.1, atan2(dir.x, dir.y), 0)
	holder.add_child(fall)
	# piccolo altare di pietre con una runa (la sorgente è "benedetta")
	var shrine := _g(id, 1.5, 0.5)
	b.box("pale", Vector3(0.5, 0.5, 0.4), shrine + Vector3(0, 0.25, 0), Color.WHITE, Vector3(0, -0.5, 0))
	b.box("pale", Vector3(0.62, 0.08, 0.5), shrine + Vector3(0, 0.54, 0), Color.WHITE, Vector3(0, -0.5, 0))
	b.sphere("rune", 0.1, shrine + Vector3(0, 0.7, 0), Color.WHITE, Vector3(0.7, 1.4, 0.7), 6, 3)
	world._light_pool(shrine + Vector3(0, 0.05, 0), Color("#7fd2ff"), 1.2, 0.35, holder)
	# pietre da guado e panchina
	for k in 3:
		b.rock("rock", 0.18, _g(id, 0.2 + k * 0.35, 1.0 + k * 0.4), Color(0, 0, 1, 1), Vector3(1.2, 0.4, 1.0), 360 + k, 0.2)
	_lamp(b, holder, _g(id, -1.0, edge(id, PI / 2) - 0.9))

# -----------------------------------------------------------------------------
# Miniera (Lv.5): ingresso in una collinetta di roccia, cristalli e carrello
# -----------------------------------------------------------------------------

func _build_miniera(id: String, holder: Node3D, b: MeshBuilder) -> void:
	var hill := _g(id, 0.0, -1.6)
	b.rock("rock", 2.0, hill + Vector3(0, -0.2, 0), Color(0, 0, 1, 1), Vector3(1.25, 0.9, 0.9), 410, 0.32)
	b.rock("rock", 1.1, hill + Vector3(1.6, -0.1, 0.3), Color(0, 0, 1, 1), Vector3(1.0, 1.0, 0.9), 411, 0.3)
	# ingresso con travi
	var door := _g(id, 0.0, -0.1)
	b.box("dark", Vector3(1.0, 1.05, 0.3), door + Vector3(0, 0.5, -0.25), Color("#151214"))
	for sx in [-0.55, 0.55]:
		b.box("timber", Vector3(0.14, 1.25, 0.14), door + Vector3(sx, 0.6, 0))
	b.box("timber", Vector3(1.35, 0.16, 0.18), door + Vector3(0, 1.25, 0))
	_lamp(b, holder, door + Vector3(0.75, 0, 0.3))
	# binari e carrello
	for i in 8:
		var z := 0.2 + i * 0.35
		b.box("timber", Vector3(0.62, 0.04, 0.09), _g(id, 0, z) + Vector3(0, 0.02, 0))
	for sx in [-0.22, 0.22]:
		b.box("metal", Vector3(0.04, 0.04, 2.8), _g(id, sx, 1.4) + Vector3(0, 0.06, 0), Color("#4a4440"))
	var cart := _g(id, 0, 1.3)
	b.box("planks", Vector3(0.55, 0.32, 0.7), cart + Vector3(0, 0.3, 0), Color("#6b5038"))
	for sx in [-0.3, 0.3]:
		for sz in [-0.22, 0.22]:
			b.cylinder("metal", 0.09, 0.09, 0.05, cart + Vector3(sx, 0.1, sz), Color("#3a3634"), 8, Vector3(0, 0, PI / 2))
	# cristalli che spuntano dalla roccia e nel carrello
	var spots := [[Vector3(-1.4, 0.6, -1.0), 0.32, -0.4], [Vector3(-1.0, 0.9, -1.8), 0.4, 0.2], [Vector3(1.2, 0.9, -1.2), 0.3, 0.5], [Vector3(2.0, 0.4, -0.2), 0.26, 0.9], [Vector3(-2.2, 0.2, 0.3), 0.24, -0.8], [Vector3(0, 0.55, 1.3), 0.16, 0.0]]
	var cb := MeshBuilder.new()
	cb.material("core", WorldMaterials.glow(Color("#6f7dff"), 2.6))
	cb.material("inner", WorldMaterials.glow(Color("#b48cff"), 2.6))
	for k in spots.size():
		var s: Array = spots[k]
		var p: Vector3 = s[0]
		var base := Vector3(p.x, ground(id, Vector2(p.x, p.z)) + p.y * 0.4, p.z)
		var size := float(s[1]) * 1.7
		for j in 3:
			var tilt := Vector3(0.35 * sin(j * 2.1 + k), 0, 0.35 * cos(j * 2.1 + k)) + Vector3(0, 0, float(s[2]) * 0.4)
			cb.sphere("core" if j != 1 else "inner", size * (1.0 - j * 0.2), base + Vector3(sin(j * 2.1 + k) * 0.18, size * 0.8, cos(j * 2.1 + k) * 0.18), Color.WHITE, Vector3(0.45, 1.7, 0.45), 6, 2, false, tilt)
		world._light_pool(base + Vector3(0, 0.05, 0), Color("#8a7cff"), 1.1 + size, 0.35, holder)
	var cm := cb.instance(holder, false)
	cm.set_meta("pulse", 0.0)

# -----------------------------------------------------------------------------
# Faro (Lv.7): torre di pietra con un cristallo che illumina il Rift
# -----------------------------------------------------------------------------

func _build_faro(id: String, holder: Node3D, b: MeshBuilder) -> void:
	var base := _g(id, 0, -0.4)
	b.cylinder("pale", 1.65, 1.75, 0.25, base + Vector3(0, 0.1, 0), Color.WHITE, 16)
	b.cylinder("stone", 0.85, 1.15, 4.6, base + Vector3(0, 2.4, 0), Color.WHITE, 12)
	for k in 3:
		b.cylinder("pale", 0.98 - k * 0.09, 1.08 - k * 0.09, 0.14, base + Vector3(0, 1.1 + k * 1.4, 0), Color.WHITE, 12)
	# porta e finestrelle
	b.box("timber", Vector3(0.5, 0.85, 0.1), base + Vector3(0, 0.6, 1.08), Color("#4a3424"), Vector3(0.12, 0, 0))
	for k in 2:
		b.box("lamp", Vector3(0.16, 0.3, 0.06), base + Vector3(0, 2.2 + k * 1.3, 1.0 - k * 0.1), Color.WHITE)
	# balconata e lanterna
	var top := base + Vector3(0, 4.7, 0)
	b.cylinder("dark", 1.2, 1.0, 0.2, top, Color.WHITE, 14)
	for k in 10:
		var a := TAU * k / 10.0
		b.box("metal", Vector3(0.04, 0.45, 0.04), top + Vector3(cos(a) * 1.12, 0.32, sin(a) * 1.12), Color("#2e2c2a"))
	b.torus("metal", 1.12, 0.03, top + Vector3(0, 0.55, 0), Color("#2e2c2a"), Vector3.ZERO, 24, 4)
	for k in 6:
		var a := TAU * k / 6.0
		b.box("metal", Vector3(0.06, 1.0, 0.06), top + Vector3(cos(a) * 0.6, 0.6, sin(a) * 0.6), Color("#2e2c2a"))
	b.cone_roof("roof", 0.95, 0.9, 1.1, Color.WHITE, 12, top)
	b.sphere("rune", 0.12, top + Vector3(0, 2.1, 0), Color.WHITE, Vector3.ONE, 6, 4)
	var gem := MeshBuilder.new()
	gem.material("core", WorldMaterials.glow(Color("#7fd2ff"), 2.8))
	gem.sphere("core", 0.34, Vector3.ZERO, Color.WHITE, Vector3(0.65, 1.4, 0.65), 6, 2)
	var gm := gem.instance(holder, false)
	gm.position = top + Vector3(0, 0.62, 0)
	gm.set_meta("spin", 0.8)
	animated.append(gm)
	# fascio di luce che ruota
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.9
	bm.bottom_radius = 0.06
	bm.height = 9.0
	bm.radial_segments = 10
	bm.cap_top = false
	bm.cap_bottom = false
	beam.mesh = bm
	beam.material_override = WorldMaterials.transparent(Color(0.55, 0.85, 1.0, 0.1), true, 0.0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pivot := Node3D.new()
	pivot.position = gm.position
	holder.add_child(pivot)
	beam.position = Vector3(0, 0, -4.5)
	beam.rotation = Vector3(-PI / 2 - 0.08, 0, 0)
	pivot.add_child(beam)
	pivot.set_meta("spin", 0.5)
	animated.append(pivot)
	world._light_pool(base + Vector3(0, 0.25, 0), Color("#7fd2ff"), 2.4, 0.3, holder)
	_lamp(b, holder, _g(id, 0.9, edge(id, PI / 2) - 0.9))

# -----------------------------------------------------------------------------
# Ponte di corda e assi dall'isola principale all'isolotto
# -----------------------------------------------------------------------------

func _build_bridge(id: String) -> void:
	var a := deg_to_rad(float(LAYOUT[id].angle))
	var dir := Vector3(cos(a), 0, sin(a))
	var side := Vector3(-dir.z, 0, dir.x)
	var start := dir * (world.island_radius(a) - 1.0)
	start.y = world.ground_height(Vector2(start.x, start.z))
	var end_z := edge(id, PI / 2) - 0.7
	var finish := to_world(id, Vector3(0, ground(id, Vector2(0, end_z)), end_z))
	var flat := Vector3(finish.x - start.x, 0, finish.z - start.z)
	var yaw := atan2(flat.x, flat.z)
	var length := Vector3(finish.x - start.x, finish.y - start.y, finish.z - start.z).length()
	var b := _builder()
	var planks := maxi(8, int(length / 0.42))
	var sag := 0.35 + length * 0.03
	var deck: Array[Vector3] = []
	for i in planks + 1:
		var t := float(i) / planks
		deck.append(start.lerp(finish, t) - Vector3(0, sin(t * PI) * sag, 0))
	for i in planks:
		var p := (deck[i] + deck[i + 1]) * 0.5
		var pitch := atan2(deck[i + 1].y - deck[i].y, Vector2(deck[i + 1].x - deck[i].x, deck[i + 1].z - deck[i].z).length())
		b.box("planks", Vector3(1.05, 0.06, 0.34), p, Color.WHITE.darkened(0.12 * (i % 3)), Vector3(-pitch, yaw, 0))
	# pali alle due teste e corde (mancorrenti e corde sotto le assi)
	for sgn in [-1.0, 1.0]:
		for end in [start, finish]:
			b.rod("timber", end + side * float(sgn) * 0.62 - Vector3(0, 0.3, 0), end + side * float(sgn) * 0.62 + Vector3(0, 1.0, 0), 0.07, 0.06, Color.WHITE, 6)
		for i in planks:
			var p0 := deck[i] + side * float(sgn) * 0.6
			var p1 := deck[i + 1] + side * float(sgn) * 0.6
			var lift0 := 0.8 + sin(float(i) / planks * PI) * sag * 0.45
			var lift1 := 0.8 + sin(float(i + 1) / planks * PI) * sag * 0.45
			b.rod("timber", p0 + Vector3(0, lift0, 0), p1 + Vector3(0, lift1, 0), 0.022, 0.022, Color("#8a6f4a"), 4, false)
			b.rod("timber", p0 - Vector3(0, 0.04, 0), p1 - Vector3(0, 0.04, 0), 0.02, 0.02, Color("#8a6f4a"), 4, false)
			if i % 2 == 0: b.rod("timber", p0 + Vector3(0, lift0, 0), p0, 0.012, 0.012, Color("#8a6f4a"), 3, false)
	b.instance(self)

# =============================================================================
# Animazioni leggere
# =============================================================================

func _process(delta: float) -> void:
	if animated.is_empty(): return
	time += delta
	for n in animated:
		if not is_instance_valid(n): continue
		if n.has_meta("spin"): n.rotation.y = time * float(n.get_meta("spin"))
		elif n.has_meta("wave"): n.rotation.y = sin(time * 2.2) * 0.25
