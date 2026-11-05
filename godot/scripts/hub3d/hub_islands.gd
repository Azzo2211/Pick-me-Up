extends Node3D
class_name HubIslands

## Isole che la base aggiunge crescendo (Base Lv.6, 8 e 10: GameState.BASE_ISLANDS).
## Ogni isola è una zolla sospesa con la sua scogliera, collegata all'isola
## principale da un ponte; sull'isola principale ci si arriva con un sentiero
## che gira fuori dalle mura partendo dalla strada del Portale.
## Ogni isola è costruita in coordinate locali: +Z guarda verso l'isola
## principale (da lì arriva il ponte). 1 unità = 2 metri.

const BuildingModelScript := preload("res://scripts/hub3d/building_model.gd")

## angle: gradi (come i siti delle strutture); distance e height: centro della zolla;
## radius: raggio medio; shape: forma del contorno; depth: altezza della scogliera.
const LAYOUT := {
	"campi": {"angle": 6.0, "distance": 35.5, "radius": 8.6, "height": -0.6, "shape": 1.3, "depth": 8.0},
	"dimore": {"angle": 184.0, "distance": 34.0, "radius": 8.6, "height": 0.5, "shape": 2.9, "depth": 8.5},
	"santuario": {"angle": 243.0, "distance": 41.5, "radius": 6.4, "height": 4.6, "shape": 4.1, "depth": 9.5},
}
const NAMES := {"campi": "Isola dei Campi", "dimore": "Isola delle Dimore", "santuario": "Santuario del Nexus"}
const TREES := {"campi": 16, "dimore": 18, "santuario": 9}
const LABEL_HEIGHT := {"campi": 7.0, "dimore": 10.4, "santuario": 7.2}
## Sentiero che gira fuori dalle mura (tra le mura e la scogliera).
const OUTER_PATH_RADIUS := 17.8
## Direzione (nel mondo) da cui la camera della base guarda di solito: sud, un po' a est.
const VIEW_DIRECTION := Vector3(0.31, 0.0, 0.95)
const GOLD := Color("#d9b45a")

var world: HubWorld
var ids: Array = []
var base_level := 0
var plans: Dictionary = {}
var holders: Dictionary = {}
var bridges: Dictionary = {}
var animated: Array[Node3D] = []
var time := 0.0
var noise := FastNoiseLite.new()

func setup(hub: HubWorld) -> void:
	world = hub
	name = "Islands"
	noise.seed = 23
	noise.frequency = 0.25

# =============================================================================
# Geometria
# =============================================================================

func center(id: String) -> Vector3:
	var info: Dictionary = LAYOUT[id]
	var a := deg_to_rad(float(info.angle))
	return Vector3(cos(a) * float(info.distance), float(info.height), sin(a) * float(info.distance))

## Rotazione dell'isola: il suo +Z locale guarda verso il centro della base.
func island_yaw(id: String) -> float:
	var c := center(id)
	return atan2(-c.x, -c.z)

func to_world(id: String, local: Vector3) -> Vector3:
	return center(id) + local.rotated(Vector3.UP, island_yaw(id))

## Raggio del bordo dell'isola nella direzione "theta" (coordinate locali).
func edge(id: String, theta: float) -> float:
	var info: Dictionary = LAYOUT[id]
	var k := float(info.shape)
	return float(info.radius) + 0.55 * sin(2.0 * theta + k) + 0.35 * sin(3.0 * theta + k * 1.7) + 0.2 * sin(5.0 * theta + k * 0.6)

## Quota locale del terreno: piatto all'interno, qualche gobba e il bordo che scende.
func ground(id: String, p: Vector2) -> float:
	var r := p.length()
	var e := edge(id, atan2(p.y, p.x))
	var bumps := noise.get_noise_2d(p.x + float(LAYOUT[id].shape) * 40.0, p.y) * 0.18 * smoothstep(e - 3.2, e - 1.8, r)
	var rim := -pow(clampf((r - (e - 1.6)) / 1.6, 0.0, 1.0), 2.0) * 0.55
	return bumps + rim

## Il punto (coordinate dell'isola principale) è riservato a un ponte?
## (Calcolato dalla disposizione: serve anche prima che i ponti siano costruiti.)
func blocks_main(p: Vector2, clearance: float) -> bool:
	for id in ids:
		var a := deg_to_rad(float(LAYOUT[id].angle))
		var dir := Vector2(cos(a), sin(a))
		var start := dir * (world.island_radius(a) - 1.6)
		if Geometry2D.get_closest_point_to_segment(p, start, dir * (start.length() + 3.0)).distance_to(p) < 1.6 + clearance: return true
		if p.distance_to(start) < 2.2 + clearance: return true
	return false

## Archi del sentiero esterno (gradi): dalla strada del Portale fino alle isole.
func outer_arcs() -> Array:
	var gate := rad_to_deg(HubWorld.GATE_ANGLE)
	var west := gate
	var east := gate
	for id in ids:
		var a := float(LAYOUT[id].angle)
		var delta := wrapf(a - gate, -180.0, 180.0)
		if delta < 0.0: west = minf(west, gate + delta)
		else: east = maxf(east, gate + delta)
	var arcs := []
	if west < gate: arcs.append([west, gate])
	if east > gate: arcs.append([gate, east])
	return arcs

# =============================================================================
# Costruzione
# =============================================================================

## Ricostruisce le isole se sono cambiate (o se cambia il livello della base).
func rebuild(new_ids: Array, level: int) -> void:
	ids = new_ids.duplicate()
	base_level = level
	for child in get_children(): child.queue_free()
	holders.clear()
	plans.clear()
	bridges.clear()
	animated.clear()
	for id in ids:
		plans[id] = _plan(id)
		var holder := Node3D.new()
		holder.name = "Isola_" + id
		holder.position = center(id)
		holder.rotation.y = island_yaw(id)
		add_child(holder)
		holders[id] = holder
		_build_top(id, holder)
		_build_rock(id, holder)
		match id:
			"campi": _build_campi(id, holder)
			"dimore": _build_dimore(id, holder)
			"santuario": _build_santuario(id, holder)
		_build_vegetation(id, holder)
		bridges[id] = _build_bridge(id)
		if base_level >= 9: _sky_lanterns(id, holder)
	# le rupi decorative non devono finire dentro un'isola
	for f in world.floaters:
		if not is_instance_valid(f) or not f.has_meta("islet"): continue
		var hidden := false
		for id in ids:
			var c := center(id)
			if Vector2(f.position.x - c.x, f.position.z - c.z).length() < float(LAYOUT[id].radius) + 9.0: hidden = true
		f.visible = not hidden

func _builder() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.material("stone", WorldMaterials.stone("wall"))
	mb.material("dark", WorldMaterials.stone("dark"))
	mb.material("pale", WorldMaterials.stone("pale"))
	mb.material("paving", WorldMaterials.stone("paving"))
	mb.material("basalt", WorldMaterials.stone("basalt"))
	mb.material("plaster", WorldMaterials.plaster("white"))
	mb.material("timber", WorldMaterials.wood("timber"))
	mb.material("planks", WorldMaterials.wood("planks"))
	mb.material("light", WorldMaterials.wood("light"))
	mb.material("roof", WorldMaterials.roof("slate"))
	mb.material("shingle", WorldMaterials.roof("shingle"))
	mb.material("thatch", WorldMaterials.roof("thatch"))
	mb.material("metal", WorldMaterials.metal(Color.WHITE, 0.5, 0.7))
	mb.material("cloth", WorldMaterials.lit())
	mb.material("crops", WorldMaterials.foliage(false))
	mb.material("ground", WorldMaterials.terrain())
	mb.material("window", WorldMaterials.window())
	mb.material("lamp", WorldMaterials.glow(Color("#ffb35c"), 3.2))
	mb.material("rune", WorldMaterials.glow(Color("#7fd2ff"), 2.4))
	mb.material("blue_fire", WorldMaterials.glow(Color("#8fb4ff"), 3.4))
	return mb

# -----------------------------------------------------------------------------
# Disegno delle isole: sentieri, zone occupate e punti per la navigazione
# -----------------------------------------------------------------------------

func _v(x: float, z: float, y: float = 0.0) -> Vector3:
	return Vector3(x, y, z)

func _plan(id: String) -> Dictionary:
	var e := edge(id, PI / 2) - 1.6
	var plan := {"paths": [], "plazas": [], "blocks": [], "nodes": {"entry": _v(0, e)}, "links": [], "wander": [], "train": [], "rest": []}
	match id:
		"campi":
			var cross := _v(0, 2.4)
			var fork := _v(0.41, -0.65)
			var arena := Vector2(-3.1, 0.4)
			var gate_dir := (Vector2(cross.x, cross.z) - arena).normalized()
			var gate := arena + gate_dir * 3.0
			plan.arena = arena
			plan.mill = Vector2(1.1, -4.6)
			plan.barn = Vector2(-3.5, -4.9)
			plan.fields = [[Vector2(1.5, 0.0), Vector2(5.7, 3.3)], [Vector2(1.5, -3.7), Vector2(5.7, -1.3)]]
			plan.nodes["cross"] = cross
			plan.nodes["fork"] = fork
			plan.nodes["arena_gate"] = _v(gate.x, gate.y)
			plan.nodes["mill"] = _v(0.85, -3.2)
			plan.nodes["barn"] = _v(-2.55, -3.05)
			plan.nodes["field"] = _v(3.4, -0.65)
			plan.nodes["field_end"] = _v(5.6, -0.65)
			plan.paths = [[Vector2(0, e + 1.4), Vector2(cross.x, cross.z), 1.5, "dirt"], [Vector2(cross.x, cross.z), Vector2(0.85, -3.2), 1.2, "dirt"], [Vector2(cross.x, cross.z), gate, 1.1, "dirt"], [Vector2(0.4, -0.65), Vector2(5.9, -0.65), 0.8, "dirt"], [Vector2(fork.x, fork.z), Vector2(-2.55, -3.05), 1.0, "dirt"]]
			plan.plazas = [[arena, 2.45, "dirt"]]
			plan.blocks = [[arena, 3.7], [plan.mill, 1.9], [plan.barn, 2.5], ["rect", Vector2(1.2, -4.0), Vector2(6.0, 3.6)]]
			plan.links = [["entry", "cross"], ["cross", "arena_gate"], ["cross", "fork"], ["fork", "mill"], ["fork", "field"], ["field", "field_end"], ["fork", "barn"]]
			# allenamento all'aperto: due coppie che si affrontano al centro dell'arena
			for k in 4:
				var a := atan2(gate_dir.y, gate_dir.x) + PI / 4.0 + k * PI / 2.0
				var name := "train_%d" % k
				plan.nodes[name] = _v(arena.x + cos(a) * 0.9, arena.y + sin(a) * 0.9)
				plan.links.append(["arena_gate", name])
				plan.train.append(name)
			plan.focus = _v(arena.x, arena.y)
			plan.wander = ["cross", "arena_gate", "mill", "barn", "field", "field_end"]
		"dimore":
			var piazza := Vector2(0, 0.4)
			plan.piazza = piazza
			plan.tower = Vector2(0, -4.3)
			plan.houses = []
			plan.nodes["gate"] = _v(0, 3.2)
			plan.paths = [[Vector2(0, e + 1.4), Vector2(0, 2.7), 1.6, "paved"]]
			plan.plazas = [[piazza, 2.65, "paved"]]
			plan.blocks = [[piazza, 3.0], [plan.tower, 1.6]]
			plan.links = [["entry", "gate"]]
			for k in 6:
				var a := PI / 2 + TAU * k / 6.0
				var name := "p_%d" % k
				plan.nodes[name] = _v(piazza.x + cos(a) * 1.5, piazza.y + sin(a) * 1.5)
				plan.links.append([name, "p_%d" % ((k + 1) % 6)])
				plan.wander.append(name)
			plan.links.append(["gate", "p_0"])
			# panchine per chi si riprende (posti in più del Dormitorio)
			plan.benches = []
			for k in 4:
				var a := PI / 4 + k * PI / 2
				plan.benches.append(Vector2(piazza.x + cos(a) * 2.1, piazza.y + sin(a) * 2.1))
				var name := "rest_%d" % k
				var spot := Vector2(piazza.x + cos(a) * 1.85, piazza.y + sin(a) * 1.85)
				plan.nodes[name] = _v(spot.x, spot.y)
				plan.links.append([name, "p_%d" % _nearest_ring(plan, spot)])
				plan.rest.append(name)
			plan.focus = _v(piazza.x, piazza.y)
			# case attorno alla piazzetta, con la porta verso il centro
			var spots := []
			for deg in [145.0, 35.0, 215.0, 325.0]: spots.append(piazza + Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * 4.5)
			for k in spots.size():
				var pos: Vector2 = spots[k]
				var yaw := atan2(piazza.x - pos.x, piazza.y - pos.y)
				var variant: int = [1, 2, 3, 0][k]
				var w := 2.7 + float(variant % 3) * 0.3
				var d := 2.2 + float((variant / 3) % 2) * 0.3
				var door := pos + Vector2(-w * 0.22, d * 0.5 + 0.75).rotated(-yaw)
				plan.houses.append([pos, yaw, variant])
				var name := "house_%d" % k
				plan.nodes[name] = _v(door.x, door.y)
				var toward := piazza + (door - piazza).normalized() * 2.7
				plan.paths.append([door, toward, 0.9, "paved"])
				plan.links.append([name, "p_%d" % _nearest_ring(plan, door)])
				plan.blocks.append([pos, 2.6])
				plan.wander.append(name)
			plan.nodes["tower"] = _v(0, -2.95)
			plan.paths.append([Vector2(0, -3.3), Vector2(0, -2.0), 1.0, "paved"])
			plan.links.append(["tower", "p_3"])
			plan.wander.append_array(["gate", "tower"])
		"santuario":
			var temple := Vector2(0, -0.5)
			plan.temple = temple
			plan.nodes["steps"] = _v(0, 3.0)
			plan.paths = [[Vector2(0, e + 1.4), Vector2(0, 2.6), 1.5, "paved"]]
			plan.plazas = [[temple, 3.5, "paved"]]
			plan.blocks = [[temple, 3.9]]
			plan.links = [["entry", "steps"]]
			for k in 6:
				var a := PI / 2 + TAU * k / 6.0
				var name := "t_%d" % k
				plan.nodes[name] = _v(temple.x + cos(a) * 1.55, temple.y + sin(a) * 1.55, 0.48)
				plan.links.append([name, "t_%d" % ((k + 1) % 6)])
				plan.wander.append(name)
			plan.links.append(["steps", "t_0"])
			plan.focus = _v(temple.x, temple.y, 0.48)
			plan.wander.append("steps")
	return plan

func _nearest_ring(plan: Dictionary, p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for k in 6:
		var n: Vector3 = plan.nodes["p_%d" % k]
		var d := Vector2(n.x, n.z).distance_to(p)
		if d < best_d:
			best_d = d
			best = k
	return best

## Il punto (coordinate locali) è occupato da sentieri, piazze o costruzioni?
func _blocked(id: String, p: Vector2, clearance: float) -> bool:
	var plan: Dictionary = plans[id]
	for path in plan.paths:
		if Geometry2D.get_closest_point_to_segment(p, path[0], path[1]).distance_to(p) < float(path[2]) * 0.5 + 0.3 + clearance: return true
	for block in plan.blocks:
		if block[0] is String:
			var lo: Vector2 = block[1]
			var hi: Vector2 = block[2]
			if p.x > lo.x - clearance and p.x < hi.x + clearance and p.y > lo.y - clearance and p.y < hi.y + clearance: return true
		elif p.distance_to(block[0]) < float(block[1]) + clearance: return true
	var entry: Vector3 = plan.nodes.entry
	if p.distance_to(Vector2(entry.x, entry.z)) < 1.8 + clearance: return true
	return false

## Maschere del terreno (come l'isola principale): R sterrato, G selciato, B roccia, A occlusione.
func _mask(id: String, p: Vector2) -> Color:
	var plan: Dictionary = plans[id]
	var dirt := 0.0
	var paved := 0.0
	for path in plan.paths:
		var d := Geometry2D.get_closest_point_to_segment(p, path[0], path[1]).distance_to(p)
		var w := float(path[2]) * 0.5
		var m := smoothstep(w + 0.3, w - 0.15, d)
		if str(path[3]) == "paved": paved = maxf(paved, m)
		else: dirt = maxf(dirt, m)
	for plaza in plan.plazas:
		var m := smoothstep(float(plaza[1]) + 0.35, float(plaza[1]) - 0.1, p.distance_to(plaza[0]))
		if str(plaza[2]) == "paved": paved = maxf(paved, m)
		else: dirt = maxf(dirt, m)
	for field in plan.get("fields", []):
		var lo: Vector2 = field[0]
		var hi: Vector2 = field[1]
		var inside := minf(minf(p.x - lo.x, hi.x - p.x), minf(p.y - lo.y, hi.y - p.y))
		dirt = maxf(dirt, smoothstep(-0.3, 0.2, inside) * 0.85)
	var r := p.length()
	var e := edge(id, atan2(p.y, p.x))
	var rock := smoothstep(e - 0.9, e - 0.1, r) * 0.7
	return Color(clampf(dirt, 0, 1), clampf(paved, 0, 1), rock, 1.0)

# -----------------------------------------------------------------------------
# Zolla e scogliera
# -----------------------------------------------------------------------------

func _build_top(id: String, holder: Node3D) -> void:
	var rings := 22
	var segments := 96
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.append(Vector3(0, ground(id, Vector2.ZERO), 0))
	cols.append(_mask(id, Vector2.ZERO))
	var edges: Array[float] = []
	for s in segments: edges.append(edge(id, TAU * s / segments))
	for k in range(1, rings + 1):
		var f := float(k) / rings
		for s in segments:
			var a := TAU * s / segments
			var p := Vector2(cos(a), sin(a)) * edges[s] * f
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
	# bordo che scende verso la scogliera
	var lip := verts.size()
	var outer := 1 + (rings - 1) * segments
	for s in segments:
		var v := verts[outer + s]
		var dir := Vector3(v.x, 0, v.z).normalized()
		verts.append(Vector3(v.x + dir.x * 0.3, -0.7, v.z + dir.z * 0.3))
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
	var segments := 64
	var layers := 7
	var depth := float(LAYOUT[id].depth)
	var cliff_noise := FastNoiseLite.new()
	cliff_noise.seed = 31 + int(float(LAYOUT[id].shape) * 10.0)
	cliff_noise.frequency = 0.9
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	for l in layers + 1:
		var t := float(l) / layers
		for s in segments:
			var a := TAU * s / segments
			var e := edge(id, a)
			var r := e * (1.0 - pow(t, 1.3) * 0.88) + 0.3 * (1.0 - t)
			var jitter := cliff_noise.get_noise_2d(a * 9.0, l * 2.0) * 0.9 * (1.0 - t * 0.5) * smoothstep(0.0, 0.15, t)
			var y := -0.7 - t * depth + cliff_noise.get_noise_2d(a * 6.0, l * 4.0) * 0.9 * t
			verts.append(Vector3(cos(a) * (r + jitter), y, sin(a) * (r + jitter)))
			cols.append(Color(0, 0, 1, lerpf(0.9, 0.5, t)))
	var tip := verts.size()
	verts.append(Vector3(0.4, -depth - 2.6, -0.3))
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

func _build_vegetation(id: String, holder: Node3D) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4400 + int(float(LAYOUT[id].shape) * 100.0)
	var groups := {}
	var placed: Array[Vector2] = []
	var target: int = TREES[id]
	var attempts := 0
	while placed.size() < target and attempts < 2000:
		attempts += 1
		var a := r.randf_range(0, TAU)
		var e := edge(id, a)
		var dist := r.randf_range(e - 3.4, e - 0.9)
		var p := Vector2(cos(a), sin(a)) * dist
		if _blocked(id, p, 0.9): continue
		# davanti all'isola (verso la base) restano pochi alberi: le costruzioni si vedono
		if p.y > 2.5 and absf(p.x) < 4.0: continue
		var close := false
		for q in placed:
			if q.distance_to(p) < 1.6:
				close = true
				break
		if close: continue
		placed.append(p)
		var kind := "conifer" if r.randf() < (0.7 if id == "santuario" else 0.45) else "broadleaf"
		var key := "%s_%d" % [kind, r.randi_range(0, 3 if kind == "conifer" else 4)]
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(Vector3(p.x, ground(id, p) - 0.05, p.y), r.randf_range(0.7, 1.05), r.randf() * TAU))
	for i in 40:
		var a := r.randf_range(0, TAU)
		var p := Vector2(cos(a), sin(a)) * r.randf_range(1.0, edge(id, a) - 0.6)
		if _blocked(id, p, 0.0): continue
		var key := ("bush_%d" if i % 3 != 0 else "rock_%d") % (i % 3)
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(Vector3(p.x, ground(id, p) - 0.05, p.y), r.randf_range(0.6, 1.1), r.randf() * TAU))
	for key in groups:
		var parts := str(key).split("_")
		NatureKit.scatter(holder, parts[0], int(parts[1]), groups[key], true)
	var tufts := [[], []]
	for i in 420:
		var a := r.randf_range(0, TAU)
		var p := Vector2(cos(a), sin(a)) * sqrt(r.randf()) * (edge(id, a) - 0.5)
		if _blocked(id, p, -0.3): continue
		tufts[i % 2].append(NatureKit.placement(Vector3(p.x, ground(id, p), p.y), r.randf_range(0.7, 1.3), r.randf() * TAU))
	for v in 2: NatureKit.scatter(holder, "tuft", v, tufts[v], false)

# -----------------------------------------------------------------------------
# Elementi comuni
# -----------------------------------------------------------------------------

func _lamp_post(b: MeshBuilder, holder: Node3D, pos: Vector3) -> void:
	b.cylinder("metal", 0.035, 0.05, 1.7, pos + Vector3(0, 0.85, 0), Color("#2b2a28"), 8)
	b.box("metal", Vector3(0.2, 0.04, 0.2), pos + Vector3(0, 1.72, 0), Color("#2b2a28"))
	b.box("lamp", Vector3(0.13, 0.2, 0.13), pos + Vector3(0, 1.84, 0))
	b.cone("metal", 0.14, 0.12, pos + Vector3(0, 2.0, 0), Color("#2b2a28"), 4)
	if base_level >= 7: b.sphere("rune", 0.06, pos + Vector3(0, 2.13, 0), Color.WHITE, Vector3(0.7, 1.6, 0.7), 4, 2)
	world._light_pool(pos + Vector3(0, 0.04, 0), Color("#ffae5a"), 1.6, 0.32, holder)

func _bench(b: MeshBuilder, pos: Vector3, yaw: float) -> void:
	b.push_at(pos, yaw)
	b.box("planks", Vector3(0.95, 0.05, 0.26), Vector3(0, 0.23, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("planks", Vector3(0.95, 0.24, 0.04), Vector3(0, 0.38, -0.12), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	for sx in [-0.4, 0.4]: b.box("stone", Vector3(0.08, 0.22, 0.24), Vector3(sx, 0.11, 0))
	b.pop()

func _banner_pole(b: MeshBuilder, pos: Vector3, color: Color, height: float = 2.4) -> void:
	b.rod("timber", pos, pos + Vector3(0, height, 0), 0.04, 0.03, Color.WHITE, 6)
	b.box("cloth", Vector3(0.42, 0.8, 0.02), pos + Vector3(0.23, height - 0.5, 0), color)
	b.box("metal", Vector3(0.48, 0.03, 0.03), pos + Vector3(0.23, height - 0.08, 0), Color("#b39a62"))

## Casa del villaggio (BuildingModel "house"), con la porta verso "yaw".
func _house(holder: Node3D, pos: Vector2, yaw: float, variant: int, id: String) -> void:
	var house: BuildingModel = BuildingModelScript.new()
	house.build("house", variant, base_level)
	house.position = Vector3(pos.x, ground(id, pos), pos.y)
	house.rotation.y = yaw
	holder.add_child(house)

## Cristallo del Nexus (nucleo e cuore) come nella piazza.
func _crystal_node(size: float, color: Color = Color("#3f8fe0")) -> MeshInstance3D:
	var cb := MeshBuilder.new()
	cb.material("core", WorldMaterials.glow(color, 1.5))
	cb.material("inner", WorldMaterials.glow(color.lightened(0.5), 2.6))
	cb.sphere("core", size, Vector3.ZERO, Color.WHITE, Vector3(0.62, 1.55, 0.62), 6, 2)
	cb.sphere("inner", size * 0.62, Vector3(0, size * 0.3, 0), Color.WHITE, Vector3(0.48, 1.4, 0.48), 6, 2, false, Vector3(0, PI / 6, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = cb.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Lanterne che fluttuano sopra l'isola (Base Lv.9+).
func _sky_lanterns(id: String, holder: Node3D) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 990 + int(float(LAYOUT[id].shape) * 10.0)
	for i in 5:
		var a := TAU * i / 5.0 + r.randf_range(-0.3, 0.3)
		var p := Vector2(cos(a), sin(a)) * r.randf_range(2.0, edge(id, a) - 1.5)
		_floating_lantern(holder, Vector3(p.x, 4.2 + r.randf_range(0.0, 1.4), p.y), i * 1.7)

func _floating_lantern(parent: Node3D, pos: Vector3, phase: float) -> void:
	var lb := MeshBuilder.new()
	lb.material("g", WorldMaterials.glow(Color("#ffd27a"), 3.0))
	lb.sphere("g", 0.14, Vector3.ZERO, Color.WHITE, Vector3(1, 1.3, 1), 8, 5)
	var mi := lb.instance(parent, false)
	mi.position = pos
	mi.set_meta("bob", pos.y)
	mi.set_meta("phase", phase)
	animated.append(mi)

# -----------------------------------------------------------------------------
# Isola dei Campi: arena all'aperto, campi di grano, mulino a vento, fienile
# -----------------------------------------------------------------------------

func _build_campi(id: String, holder: Node3D) -> void:
	var plan: Dictionary = plans[id]
	var b := _builder()
	var arena: Vector2 = plan.arena
	var a3 := Vector3(arena.x, 0.0, arena.y)
	var gate: Vector3 = plan.nodes.arena_gate
	var gate_angle := atan2(gate.z - arena.y, gate.x - arena.x)
	# arena: fondo battuto, muretto con due varchi, gradinate sul lato lontano
	b.cylinder("ground", 2.38, 2.45, 0.08, a3 + Vector3(0, 0.02, 0), Color(1, 0, 0, 0.95), 40)
	for i in 26:
		var a := TAU * (i + 0.5) / 26.0
		var diff := absf(wrapf(a - gate_angle, -PI, PI))
		if diff < 0.32 or diff > PI - 0.32: continue
		var p := a3 + Vector3(cos(a), 0, sin(a)) * 2.58
		b.box("stone", Vector3(0.66, 0.62, 0.3), p + Vector3(0, 0.31, 0), Color.WHITE, Vector3(0, -a - PI / 2, 0))
		b.box("dark", Vector3(0.68, 0.08, 0.36), p + Vector3(0, 0.66, 0), Color.WHITE, Vector3(0, -a - PI / 2, 0))
	# gradinate verso l'esterno dell'isola (ovest), lontano dal fienile
	var seats := PI
	for tier in 2:
		var tr := 2.98 + tier * 0.36
		var th := 0.38 + tier * 0.32
		for i in 9:
			var a := seats + (i - 4) * 0.16
			var p := a3 + Vector3(cos(a), 0, sin(a)) * tr
			b.box("stone", Vector3(0.5, th, 0.38), p + Vector3(0, th * 0.5, 0), Color(0.96, 0.95, 0.93) if tier == 0 else Color.WHITE, Vector3(0, -a - PI / 2, 0))
	# pali con gli stendardi ai varchi, manichini e rastrelliera
	for side in [-0.45, 0.45, PI - 0.45, PI + 0.45]:
		var a: float = gate_angle + side
		_banner_pole(b, a3 + Vector3(cos(a), 0, sin(a)) * 2.78, Color("#7a2f2f") if base_level < 9 else Color("#8a6a2a"))
	for k in 2:
		var a := gate_angle + PI + (k - 0.5) * 1.1
		var p := a3 + Vector3(cos(a), 0, sin(a)) * 1.75
		b.rod("timber", p, p + Vector3(0, 1.0, 0), 0.04, 0.035, Color.WHITE, 6)
		b.cylinder("cloth", 0.13, 0.15, 0.42, p + Vector3(0, 0.62, 0), Color("#a88a58"), 8)
		b.sphere("cloth", 0.1, p + Vector3(0, 0.95, 0), Color("#b29462"), Vector3.ONE, 8, 5)
		b.box("timber", Vector3(0.62, 0.05, 0.05), p + Vector3(0, 0.78, 0), Color.WHITE, Vector3(0, -a, 0), MeshBuilder.UV.LONG)
	# mulino a vento: torre bianca, cappello di scandole, pale che girano verso la base
	var mill: Vector2 = plan.mill
	var m3 := Vector3(mill.x, 0, mill.y)
	b.cylinder("stone", 1.2, 1.26, 0.5, m3 + Vector3(0, 0.25, 0), Color.WHITE, 18)
	b.cylinder("plaster", 0.84, 1.08, 4.0, m3 + Vector3(0, 2.5, 0), Color(1.0, 0.98, 0.95), 18)
	b.cylinder("dark", 0.93, 0.93, 0.16, m3 + Vector3(0, 4.56, 0), Color.WHITE, 18)
	b.cone_roof("shingle", 1.04, 1.5, 4.62, Color.WHITE, 18, m3)
	b.sphere("metal", 0.07, m3 + Vector3(0, 6.18, 0), Color("#b39a62"), Vector3.ONE, 6, 4)
	b.box("planks", Vector3(0.55, 1.05, 0.14), m3 + Vector3(0, 1.02, 1.0), Color(0.9, 0.85, 0.8))
	b.box("timber", Vector3(0.7, 0.1, 0.18), m3 + Vector3(0, 1.58, 1.0))
	for k in 2:
		var wy := 2.3 + k * 1.1
		var a := PI / 2 + (1.0 if k == 0 else -1.0) * 1.2
		var rad := lerpf(1.08, 0.84, (wy - 0.5) / 4.0) + 0.02
		b.push_at(m3 + Vector3(cos(a) * rad, wy, sin(a) * rad), atan2(cos(a), sin(a)))
		b.box("timber", Vector3(0.34, 0.44, 0.05), Vector3.ZERO)
		b.box("window", Vector3(0.26, 0.36, 0.05), Vector3(0, 0, 0.012))
		b.pop()
	var sails := MeshInstance3D.new()
	var sb := _builder()
	sb.cylinder("timber", 0.13, 0.13, 0.45, Vector3(0, 0, -0.1), Color.WHITE, 8, Vector3(PI / 2, 0, 0))
	sb.sphere("timber", 0.16, Vector3(0, 0, 0.14), Color.WHITE, Vector3.ONE, 8, 5)
	for k in 4:
		sb.push(Transform3D(Basis(Vector3.BACK, TAU * k / 4.0 + 0.35), Vector3.ZERO))
		sb.box("timber", Vector3(0.08, 2.7, 0.08), Vector3(0, 1.4, 0.16), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
		sb.box("light", Vector3(0.04, 2.0, 0.04), Vector3(0.56, 1.72, 0.17))
		for j in 6: sb.box("light", Vector3(0.6, 0.03, 0.03), Vector3(0.28, 0.72 + j * 0.4, 0.17))
		sb.box("cloth", Vector3(0.5, 1.95, 0.015), Vector3(0.29, 1.72, 0.19), Color("#ddd1b8"))
		sb.pop()
	sails.mesh = sb.commit()
	# le pale guardano verso chi osserva la base (la camera sta a sud-est)
	var view := VIEW_DIRECTION.rotated(Vector3.UP, -island_yaw(id))
	sails.position = m3 + Vector3(view.x, 0, view.z) * 1.12 + Vector3(0, 4.1, 0)
	sails.rotation.y = atan2(view.x, view.z)
	sails.set_meta("roll", 0.5)
	holder.add_child(sails)
	animated.append(sails)
	# fienile e covoni
	var barn: Vector2 = plan.barn
	_house(holder, barn, atan2(0.41 - barn.x, -0.65 - barn.y), 4, id)
	for k in 3:
		var hp := Vector3(barn.x + 1.7 + k * 0.6, 0, barn.y - 0.9 - (k % 2) * 0.55)
		b.cylinder("thatch", 0.32, 0.34, 0.5, hp + Vector3(0, 0.25, 0), Color.WHITE, 10)
		b.dome("thatch", 0.33, hp + Vector3(0, 0.5, 0), Color.WHITE, 0.7, 10, 4)
	# campi di grano con la staccionata e uno spaventapasseri
	for field in plan.fields:
		var lo: Vector2 = field[0]
		var hi: Vector2 = field[1]
		var rows := int((hi.y - lo.y - 0.2) / 0.38)
		for row in rows:
			var z := lo.y + 0.28 + row * 0.38
			var n := int((hi.x - lo.x - 0.5) / 0.3)
			for k in n:
				var x := lo.x + 0.33 + k * 0.3 + (0.1 if row % 2 == 0 else 0.0)
				var tone: Color = [Color("#c9a24a"), Color("#b8903c"), Color("#d6b25a")][(row + k) % 3]
				# ciuffo di spighe: tre steli sottili un po' inclinati
				for j in 3:
					var ja := TAU * j / 3.0 + float(row + k)
					var tilt := Vector3(cos(ja), 0, sin(ja)) * 0.25
					b.cone("crops", 0.045, 0.5, Vector3(x + cos(ja) * 0.05, 0.25, z + sin(ja) * 0.05), tone.darkened(0.08 * j), 4, Vector3(tilt.z, 0, -tilt.x))
					b.sphere("crops", 0.035, Vector3(x + cos(ja) * 0.11, 0.5, z + sin(ja) * 0.11), tone.lightened(0.15), Vector3(1.0, 2.2, 1.0), 4, 2)
		var corners := [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]
		for c in 4:
			var p0: Vector2 = corners[c]
			var p1: Vector2 = corners[(c + 1) % 4]
			var len_side := p0.distance_to(p1)
			var posts := maxi(2, int(len_side / 0.75) + 1)
			for k in posts:
				var p := p0.lerp(p1, float(k) / (posts - 1))
				b.box("timber", Vector3(0.06, 0.5, 0.06), Vector3(p.x, 0.25, p.y), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
			var mid := (p0 + p1) * 0.5
			var yaw := atan2(p1.x - p0.x, p1.y - p0.y)
			for h in [0.22, 0.42]: b.box("timber", Vector3(0.04, 0.05, len_side), Vector3(mid.x, h, mid.y), Color.WHITE, Vector3(0, yaw, 0), MeshBuilder.UV.LONG)
	var sc := Vector3(3.6, 0, 1.7)
	b.rod("timber", sc, sc + Vector3(0, 1.5, 0), 0.04, 0.035, Color.WHITE, 5)
	b.box("timber", Vector3(0.9, 0.05, 0.05), sc + Vector3(0, 1.15, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("cloth", Vector3(0.5, 0.5, 0.2), sc + Vector3(0, 1.0, 0), Color("#6b4a32"))
	b.sphere("cloth", 0.14, sc + Vector3(0, 1.45, 0), Color("#c9b48a"), Vector3.ONE, 8, 5)
	b.cone("thatch", 0.26, 0.24, sc + Vector3(0, 1.62, 0), Color.WHITE, 10)
	# lampioni lungo il sentiero
	_lamp_post(b, holder, Vector3(0.95, 0, 5.2))
	_lamp_post(b, holder, Vector3(-0.95, 0, 3.0))
	b.instance(holder)

# -----------------------------------------------------------------------------
# Isola delle Dimore: case degli eroi, piazzetta con la fontana, campanile
# -----------------------------------------------------------------------------

func _build_dimore(id: String, holder: Node3D) -> void:
	var plan: Dictionary = plans[id]
	var b := _builder()
	var piazza: Vector2 = plan.piazza
	var p3 := Vector3(piazza.x, 0, piazza.y)
	b.cylinder("paving", 2.62, 2.66, 0.06, p3 + Vector3(0, 0.02, 0), Color.WHITE, 40)
	b.torus("dark", 2.62, 0.06, p3 + Vector3(0, 0.05, 0), Color.WHITE, Vector3.ZERO, 40, 4)
	# fontana
	b.cylinder("pale", 0.72, 0.78, 0.38, p3 + Vector3(0, 0.19, 0), Color.WHITE, 18)
	b.cylinder("pale", 0.13, 0.17, 0.85, p3 + Vector3(0, 0.6, 0), Color.WHITE, 8)
	b.cylinder("pale", 0.34, 0.28, 0.1, p3 + Vector3(0, 1.0, 0), Color.WHITE, 12)
	b.sphere("pale", 0.1, p3 + Vector3(0, 1.12, 0), Color.WHITE, Vector3.ONE, 8, 5)
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.64
	disc.bottom_radius = 0.64
	disc.height = 0.04
	disc.radial_segments = 20
	water.mesh = disc
	water.material_override = world._water_material(0.3, 2.0, 0.9)
	water.position = p3 + Vector3(0, 0.34, 0)
	holder.add_child(water)
	for k in plan.benches.size():
		var bp: Vector2 = plan.benches[k]
		_bench(b, Vector3(bp.x, 0, bp.y), atan2(piazza.x - bp.x, piazza.y - bp.y))
	for k in 4:
		var a := k * PI / 2.0
		if k == 1: continue
		_lamp_post(b, holder, p3 + Vector3(cos(a), 0, sin(a)) * 2.9)
	# case
	for house in plan.houses:
		_house(holder, house[0], house[1], house[2], id)
	# aiuole davanti alle case
	for house in plan.houses:
		var hp: Vector2 = house[0]
		var out := (hp - piazza).normalized()
		var side := Vector2(-out.y, out.x)
		var bed := hp - out * 0.2 + side * 2.0
		b.box("stone", Vector3(0.9, 0.18, 0.5), Vector3(bed.x, 0.09, bed.y), Color.WHITE, Vector3(0, atan2(side.x, side.y), 0))
		for k in 5: b.sphere("crops", 0.12, Vector3(bed.x, 0.26, bed.y) + Vector3(side.x, 0, side.y) * (-0.32 + k * 0.16), [Color("#b8475a"), Color("#d9b04a"), Color("#4f7a2c"), Color("#8b5fbf"), Color("#e8e0d0")][k], Vector3.ONE, 6, 4)
	# campanile
	var tower: Vector2 = plan.tower
	var t3 := Vector3(tower.x, 0, tower.y)
	var half := 0.82
	b.box("stone", Vector3(half * 2.0 + 0.3, 0.4, half * 2.0 + 0.3), t3 + Vector3(0, 0.2, 0))
	b.box("stone", Vector3(half * 2.0, 5.0, half * 2.0), t3 + Vector3(0, 2.9, 0))
	for y in [1.9, 3.7]: b.box("dark", Vector3(half * 2.0 + 0.1, 0.12, half * 2.0 + 0.1), t3 + Vector3(0, y, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box("pale", Vector3(0.16, 5.0, 0.16), t3 + Vector3(sx * (half - 0.05), 2.9, sz * (half - 0.05)), Color(1.0, 0.98, 0.94))
	b.box("planks", Vector3(0.55, 1.05, 0.08), t3 + Vector3(0, 0.92, half + 0.02), Color(0.9, 0.85, 0.8))
	b.arch("dark", 0.28, 0.38, 0.12, t3 + Vector3(0, 1.45, half + 0.02), Color.WHITE, Vector3.ZERO, 8)
	for y in [2.6, 4.4]:
		b.box("window", Vector3(0.18, 0.42, 0.05), t3 + Vector3(0, y, half + 0.02))
	b.box("dark", Vector3(half * 2.0 + 0.24, 0.16, half * 2.0 + 0.24), t3 + Vector3(0, 5.46, 0))
	# cella campanaria aperta con la campana
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box("stone", Vector3(0.3, 1.4, 0.3), t3 + Vector3(sx * (half - 0.15), 6.24, sz * (half - 0.15)))
	for yaw in [0.0, PI / 2, PI, -PI / 2]:
		b.push_at(t3 + Vector3(0, 6.62, 0), yaw)
		b.arch("stone", 0.38, 0.52, 0.2, Vector3(0, 0, half - 0.1), Color.WHITE, Vector3.ZERO, 8)
		b.pop()
	b.cylinder("metal", 0.17, 0.34, 0.5, t3 + Vector3(0, 6.2, 0), Color("#a8823a"), 12)
	b.sphere("metal", 0.17, t3 + Vector3(0, 6.45, 0), Color("#a8823a"), Vector3.ONE, 10, 5, true)
	b.box("dark", Vector3(half * 2.0 + 0.3, 0.2, half * 2.0 + 0.3), t3 + Vector3(0, 7.04, 0))
	b.push_at(t3, PI / 4)
	b.cone_roof("roof", (half + 0.3) * sqrt(2.0), 1.9, 7.14, Color.WHITE, 4)
	b.pop()
	b.rod("metal", t3 + Vector3(0, 9.0, 0), t3 + Vector3(0, 9.55, 0), 0.03, 0.02, GOLD, 5)
	b.sphere("metal", 0.08, t3 + Vector3(0, 9.6, 0), GOLD, Vector3.ONE, 6, 4)
	b.instance(holder)

# -----------------------------------------------------------------------------
# Santuario del Nexus: tempio rotondo a cielo aperto con un frammento gigante
# -----------------------------------------------------------------------------

func _build_santuario(id: String, holder: Node3D) -> void:
	var plan: Dictionary = plans[id]
	var b := _builder()
	var temple: Vector2 = plan.temple
	var t3 := Vector3(temple.x, 0, temple.y)
	for k in 3:
		b.cylinder("pale", 3.3 - k * 0.3, 3.36 - k * 0.3, 0.16, t3 + Vector3(0, 0.08 + k * 0.16, 0), Color(1.0 - k * 0.02, 0.99 - k * 0.02, 0.97 - k * 0.02), 44)
	# cerchio di rune sul pavimento
	b.torus("rune", 1.95, 0.035, t3 + Vector3(0, 0.5, 0), Color.WHITE, Vector3.ZERO, 48, 4)
	b.torus("rune", 1.25, 0.02, t3 + Vector3(0, 0.5, 0), Color.WHITE, Vector3.ZERO, 40, 3)
	for i in 12:
		var a := TAU * i / 12.0
		b.box("rune", Vector3(0.05, 0.02, 0.5), t3 + Vector3(cos(a), 0, sin(a)) * 1.6 + Vector3(0, 0.5, 0), Color.WHITE, Vector3(0, -a + PI / 2, 0))
	# colonnato aperto
	for i in 10:
		var a := TAU * (i + 0.5) / 10.0 + PI / 2
		var p := t3 + Vector3(cos(a), 0, sin(a)) * 2.35
		b.box("pale", Vector3(0.38, 0.14, 0.38), p + Vector3(0, 0.55, 0), Color(0.96, 0.95, 0.93))
		b.cylinder("pale", 0.14, 0.17, 2.6, p + Vector3(0, 1.92, 0), Color(1.03, 1.01, 0.98), 10)
		b.box("pale", Vector3(0.4, 0.14, 0.4), p + Vector3(0, 3.29, 0), Color(0.96, 0.95, 0.93))
	for i in 30:
		var a := TAU * (i + 0.5) / 30.0
		var p := t3 + Vector3(cos(a), 0, sin(a)) * 2.35
		b.box("pale", Vector3(0.52, 0.3, 0.46), p + Vector3(0, 3.5, 0), Color(0.98, 0.97, 0.95), Vector3(0, -a - PI / 2, 0))
		b.box("metal", Vector3(0.52, 0.05, 0.05), p + Vector3(0, 3.68, 0) + Vector3(cos(a), 0, sin(a)) * 0.2, GOLD, Vector3(0, -a - PI / 2, 0))
	# piedistallo
	b.cylinder("dark", 0.75, 0.9, 0.5, t3 + Vector3(0, 0.73, 0), Color.WHITE, 8)
	b.cylinder("pale", 0.6, 0.7, 0.16, t3 + Vector3(0, 1.06, 0), Color.WHITE, 8)
	# obelischi sul bordo e bracieri azzurri all'ingresso
	for k in 4:
		var a := PI / 4 + k * PI / 2
		var p := Vector2(cos(a), sin(a)) * minf(4.9, edge(id, a) - 1.4)
		var o := Vector3(p.x, 0, p.y)
		b.box("basalt", Vector3(0.6, 0.3, 0.6), o + Vector3(0, 0.15, 0))
		b.cylinder("basalt", 0.14, 0.24, 2.4, o + Vector3(0, 1.5, 0), Color.WHITE, 4, Vector3(0, PI / 4, 0))
		b.cone("basalt", 0.15, 0.32, o + Vector3(0, 2.86, 0), Color.WHITE, 4, Vector3(0, PI / 4, 0))
		b.sphere("blue_fire", 0.08, o + Vector3(0, 3.1, 0), Color.WHITE, Vector3.ONE, 6, 4)
	for sx in [-1.0, 1.0]:
		var base := Vector3(sx * 1.25, 0, 3.0)
		b.cylinder("dark", 0.15, 0.2, 0.75, base + Vector3(0, 0.375, 0), Color.WHITE, 8)
		b.cylinder("metal", 0.28, 0.17, 0.18, base + Vector3(0, 0.84, 0), Color("#2d2b29"), 10)
		b.sphere("blue_fire", 0.15, base + Vector3(0, 0.96, 0), Color.WHITE, Vector3(1.2, 0.8, 1.2), 8, 4)
		world._light_pool(base + Vector3(0, 0.05, 0), Color("#8fb4ff"), 1.4, 0.35, holder)
	b.instance(holder)
	# il grande frammento del Nexus sospeso sopra il tempio, con schegge che gli girano attorno
	var crystal := _crystal_node(1.0)
	crystal.position = t3 + Vector3(0, 4.7, 0)
	crystal.set_meta("bob", 4.7)
	crystal.set_meta("bob_amp", 0.25)
	crystal.set_meta("bob_speed", 0.8)
	crystal.set_meta("spin", 0.35)
	holder.add_child(crystal)
	animated.append(crystal)
	for i in 4:
		var shard := _crystal_node(0.2, Color("#5fa8ff"))
		shard.set_meta("orbit", [t3 + Vector3(0, 4.5, 0), 1.6, 0.55, TAU * i / 4.0, (i % 2) * 0.6 - 0.3])
		holder.add_child(shard)
		animated.append(shard)
	var light := OmniLight3D.new()
	light.light_color = Color("#6fd0ff")
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	light.position = t3 + Vector3(0, 4.2, 0)
	holder.add_child(light)
	world._light_pool(t3 + Vector3(0, 0.52, 0), Color("#5fb8ff"), 3.4, 0.4, holder)

# -----------------------------------------------------------------------------
# Ponti
# -----------------------------------------------------------------------------

## Ponte di pietra dal bordo dell'isola principale all'isola. Se il dislivello è
## grande diventa una scalinata. Restituisce i punti per la navigazione.
func _build_bridge(id: String) -> Dictionary:
	var a := deg_to_rad(float(LAYOUT[id].angle))
	var dir := Vector3(cos(a), 0, sin(a))
	var side := Vector3(-dir.z, 0, dir.x)
	var start := dir * (world.island_radius(a) - 1.6)
	start.y = world.ground_height(Vector2(start.x, start.z))
	var end_z := edge(id, PI / 2) - 0.9
	var finish := to_world(id, Vector3(0, ground(id, Vector2(0, end_z)), end_z))
	var yaw := atan2(dir.x, dir.z)
	var flat_len := Vector2(finish.x - start.x, finish.z - start.z).length()
	var rise := finish.y - start.y
	var stairs := absf(rise) > 2.0
	var b := _builder()
	var points: Array[Vector3] = []
	if stairs:
		var steps := maxi(4, int(flat_len / 0.7))
		for i in steps:
			var t := (i + 0.5) / steps
			var pos := start.lerp(finish, t)
			var top := start.y + rise * float(i + 1) / steps
			b.box("paving", Vector3(1.9, 0.2, flat_len / steps + 0.03), Vector3(pos.x, top - 0.1, pos.z), Color.WHITE, Vector3(0, yaw, 0))
			if i % 3 == 1: points.append(Vector3(pos.x, top + 0.02, pos.z))
		var pitch := atan2(rise, flat_len)
		var length3 := sqrt(flat_len * flat_len + rise * rise)
		var mid := (start + finish) * 0.5
		b.box("stone", Vector3(2.1, 0.55, length3), mid + Vector3(0, -0.42, 0), Color.WHITE, Vector3(-pitch, yaw, 0))
		for sgn in [-1.0, 1.0]:
			b.box("stone", Vector3(0.2, 0.46, length3), mid + side * float(sgn) * 0.98 + Vector3(0, 0.2, 0), Color.WHITE, Vector3(-pitch, yaw, 0))
		for t in [0.3, 0.68]:
			var p := start.lerp(finish, t)
			b.cylinder("stone", 0.42, 0.22, 5.0, Vector3(p.x, p.y - 3.1, p.z), Color.WHITE, 8)
	else:
		var pieces := maxi(5, int(flat_len / 0.75))
		for i in pieces:
			var t := (i + 0.5) / pieces
			var pos := start.lerp(finish, t)
			pos.y = lerpf(start.y, finish.y, t) + sin(t * PI) * 0.16
			var len_piece := flat_len / pieces + 0.05
			b.box("paving", Vector3(1.9, 0.22, len_piece), pos + Vector3(0, -0.05, 0), Color.WHITE, Vector3(0, yaw, 0))
			b.box("stone", Vector3(2.1, 0.35, len_piece), pos + Vector3(0, -0.3, 0), Color.WHITE, Vector3(0, yaw, 0))
			for sgn in [-1.0, 1.0]:
				b.box("stone", Vector3(0.2, 0.42, len_piece), pos + side * float(sgn) * 0.98 + Vector3(0, 0.22, 0), Color.WHITE, Vector3(0, yaw, 0))
		for k in 5:
			var t := float(k + 1) / 6.0
			var p := start.lerp(finish, t)
			points.append(Vector3(p.x, lerpf(start.y, finish.y, t) + sin(t * PI) * 0.16 + 0.06, p.z))
		var mid := start.lerp(finish, 0.5)
		b.cylinder("stone", 0.45, 0.25, 3.8, Vector3(mid.x, mid.y - 2.4, mid.z), Color.WHITE, 8)
	# piloni con lanterne ai due capi
	for p in [start, finish]:
		for sgn in [-1.0, 1.0]:
			var post: Vector3 = p + side * float(sgn) * 1.12
			b.box("dark", Vector3(0.36, 1.1, 0.36), post + Vector3(0, 0.55, 0))
			b.box("lamp", Vector3(0.14, 0.2, 0.14), post + Vector3(0, 1.22, 0))
			b.cone("metal", 0.14, 0.14, post + Vector3(0, 1.4, 0), Color("#2b2a28"), 4)
		world._light_pool(p + Vector3(0, 0.1, 0), Color("#ffae5a"), 1.8, 0.3, self)
	b.instance(self)
	if base_level >= 9:
		for k in 3:
			var t := (k + 1) / 4.0
			_floating_lantern(self, start.lerp(finish, t) + Vector3(0, 3.0 + (k % 2) * 0.6, 0), k * 2.3)
	return {"start": start, "finish": finish, "points": points}

# =============================================================================
# Navigazione e punti utili (coordinate del mondo)
# =============================================================================

## Nodi dell'isola per la navigazione: nome -> posizione nel mondo.
func nav_nodes(id: String) -> Dictionary:
	var out := {}
	var plan: Dictionary = plans[id]
	for name in plan.nodes:
		var local: Vector3 = plan.nodes[name]
		var y := local.y if local.y != 0.0 else ground(id, Vector2(local.x, local.z))
		out[name] = to_world(id, Vector3(local.x, y, local.z))
	return out

func focus(id: String) -> Vector3:
	var plan: Dictionary = plans.get(id, {})
	if not plan.has("focus"): return center(id)
	return to_world(id, plan.focus)

## Punto per l'etichetta con il nome dell'isola.
func label_position(id: String) -> Vector3:
	var height: float = LABEL_HEIGHT[id]
	var plan: Dictionary = plans[id]
	var anchor: Vector2 = plan.get("mill", plan.get("tower", plan.get("temple", Vector2.ZERO)))
	return to_world(id, Vector3(anchor.x, height, anchor.y))

func _process(delta: float) -> void:
	time += delta
	for n in animated:
		if not is_instance_valid(n): continue
		if n.has_meta("roll"): n.rotate_object_local(Vector3.BACK, delta * float(n.get_meta("roll")))
		if n.has_meta("bob"): n.position.y = float(n.get_meta("bob")) + sin(time * float(n.get_meta("bob_speed", 0.9)) + float(n.get_meta("phase", 0.0))) * float(n.get_meta("bob_amp", 0.18))
		if n.has_meta("spin"): n.rotation.y = time * float(n.get_meta("spin"))
		if n.has_meta("orbit"):
			var o: Array = n.get_meta("orbit")
			var ang: float = float(o[3]) + time * float(o[2])
			n.position = (o[0] as Vector3) + Vector3(cos(ang) * float(o[1]), float(o[4]) + sin(time * 1.3 + float(o[3])) * 0.2, sin(ang) * float(o[1]))
			n.rotation.y = -ang
