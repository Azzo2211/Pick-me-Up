extends Control
class_name BattleScene

## Missione in tempo reale. Gli eroi agiscono da soli con una Utility AI
## (bersagli, distanza, ruolo, coraggio); il Master dà solo ordini generali.
## Simulazione deterministica a 20 tick/s, decisioni a 5 Hz.

signal battle_finished(result: Dictionary)
signal hero_died(hero_id: String, cause: String)

const HeroPortraitScript := preload("res://scripts/hero_portrait.gd")

const TICK := 0.05
const DECISION := 0.2
const ARENA_X := 15.0
const ARENA_Z := 7.0
const UNIT_SCALE := 1.3
const FORMATION := [Vector2(-6.5, -1.6), Vector2(-6.5, 1.6), Vector2(-8.6, -2.4), Vector2(-8.6, 2.4), Vector2(-10.8, 0.0)]
const ENEMY_TEMPLATES := {
	"raider": {"hp": 210.0, "attack": 31.0, "defense": 8.0, "speed": 2.3, "cadence": 0.95, "threat": 1, "range": 1.1, "tint": Color("#c0453a"), "name": "Predone"},
	"hound": {"hp": 150.0, "attack": 26.0, "defense": 5.0, "speed": 3.6, "cadence": 0.75, "threat": 1, "range": 1.0, "tint": Color("#7b4fb8"), "name": "Segugio"},
	"archer": {"hp": 140.0, "attack": 29.0, "defense": 4.0, "speed": 2.0, "cadence": 1.3, "threat": 2, "range": 6.5, "tint": Color("#c4467e"), "name": "Arciere"},
	"brute": {"hp": 540.0, "attack": 48.0, "defense": 16.0, "speed": 1.5, "cadence": 1.55, "threat": 3, "range": 1.5, "tint": Color("#a8653a"), "name": "Bruto"},
	"boss": {"hp": 2100.0, "attack": 46.0, "defense": 22.0, "speed": 1.3, "cadence": 1.35, "threat": 8, "range": 2.0, "tint": Color("#4f8a3a"), "name": "Guardiano"},
}

## Aspetto dei biomi: colori del terreno, alberi, oggetti di scena e luce.
const BIOMES := {
	"Bosco cinereo": {"grass": [Color("#3b4733"), Color("#5f6a48"), Color("#7e7a62")], "dirt": Color("#4b4139"), "trees": {"conifer": 0.45, "dead": 0.35, "broadleaf": 0.2}, "props": "rocks", "look": "dusk", "fog": Color("#8d8a96"), "fog_density": 0.009},
	"Borgo evacuato": {"grass": [Color("#3b4a2b"), Color("#5c6c3c"), Color("#86804c")], "dirt": Color("#5a4a3a"), "trees": {"broadleaf": 0.7, "conifer": 0.3}, "props": "ruins_village", "look": "dusk", "fog": Color("#7d8ca3"), "fog_density": 0.012},
	"Rovine allagate": {"grass": [Color("#2f4a3c"), Color("#4b6a4b"), Color("#6b7a5a")], "dirt": Color("#3c4a48"), "trees": {"broadleaf": 0.5, "dead": 0.2, "conifer": 0.3}, "props": "ruins_water", "look": "dusk", "fog": Color("#6f8ca0"), "fog_density": 0.01, "zenith": Color("#1d2c4a"), "horizon": Color("#b7a49a")},
	"Santuario in rovina": {"grass": [Color("#4c5a2b"), Color("#7a7a3b"), Color("#a08c4a")], "dirt": Color("#7a6a4a"), "trees": {"broadleaf": 0.6, "conifer": 0.4}, "props": "ruins_temple", "look": "dusk", "fog": Color("#c8a070"), "fog_density": 0.006},
	"Pianure ventose": {"grass": [Color("#4f6a2a"), Color("#7a9a3a"), Color("#a4a052")], "dirt": Color("#6a5a3a"), "trees": {"broadleaf": 0.6, "conifer": 0.4}, "props": "rocks", "look": "day", "fog": Color("#b9c6d4"), "fog_density": 0.004},
	"Canyon ramato": {"grass": [Color("#7a5236"), Color("#a06c3e"), Color("#b8865a")], "dirt": Color("#8a4f30"), "trees": {"dead": 0.8, "conifer": 0.2}, "props": "canyon", "look": "dusk", "fog": Color("#c48a62"), "fog_density": 0.006, "horizon": Color("#f0905a"), "no_grass": true},
	"Ghiacciaio sospeso": {"grass": [Color("#b9c6d4"), Color("#e2e8ef"), Color("#cfd8e2")], "dirt": Color("#8a9aac"), "trees": {"conifer": 0.85, "dead": 0.15}, "props": "ice", "look": "day", "fog": Color("#c9d6e6"), "fog_density": 0.009, "zenith": Color("#3c5a88"), "horizon": Color("#d6e2ee"), "no_grass": true},
	"Giardini di cristallo": {"grass": [Color("#3a3a58"), Color("#55557a"), Color("#6c6a8a")], "dirt": Color("#3a3448"), "trees": {"broadleaf": 0.5, "conifer": 0.5}, "props": "crystals", "look": "night", "fog": Color("#4a3c6c"), "fog_density": 0.009},
}

var stage: Dictionary
var party_source: Array
var attempt := 1
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var accumulator := 0.0
var decision_timer := 0.0
var running := false
var completed := false
var result_victory := false
var result_reason := ""
var speed_scale := 1.0
var units: Array = []
var effects: Array = []
var floaters: Array = []
var spawned_waves: Array = []
var next_id := 1
var command_state := {"posture": "ADVANCE", "focus": false, "protect": false, "all_out_until": 0.0, "extracting": false, "extract_at": 0.0}
var command_ready := {"posture": 0.0, "focus": 0.0, "protect": 0.0, "all_out": 0.0, "extract": 0.0}
var objective := {"poi": 0, "poi_progress": 0.0, "beacon": 100.0, "boss_dead": false}
var poi_points: Array[Vector2] = [Vector2(-1.0, -3.8), Vector2(4.5, 3.6), Vector2(10.0, -2.5)]
var beacon_pos := Vector2(-10.0, 3.2)

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var overlay: Control
var title_label: Label
var objective_label: Label
var progress_label: Label
var clock_label: Label
var party_box: VBoxContainer
var party_cards: Dictionary = {}
var log_box: VBoxContainer
var command_buttons: Dictionary = {}
var speed_button: Button
var boss_panel: PanelContainer
var boss_bar: ProgressBar
var boss_label: Label
var poi_nodes: Array[Node3D] = []
var beacon_node: Node3D

func setup(stage_data: Dictionary, source_party: Array, mission_attempt: int) -> void:
	stage = stage_data
	party_source = source_party
	attempt = mission_attempt
	rng.seed = abs((str(stage.seed) + ":" + str(attempt)).hash())

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_hud()
	_create_heroes()
	running = true
	_log("La squadra attraversa il Portale. Da qui in avanti decidono loro.", "good")

# =============================================================================
# Scena 3D
# =============================================================================

func _biome() -> Dictionary:
	return BIOMES.get(str(stage.get("biome", "")), BIOMES["Bosco cinereo"])

func _build_world() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var biome := _biome()
	var overrides := {"fog": biome.fog, "fog_density": biome.fog_density, "fog_height": -6.0, "fog_height_density": 0.0, "sun_rot": Vector3(-42, 150, 0)}
	if biome.has("zenith"): overrides["zenith"] = biome.zenith
	if biome.has("horizon"): overrides["horizon"] = biome.horizon
	WorldLook.setup(world, str(biome.look), overrides, 70.0)
	camera = Camera3D.new()
	camera.fov = 34.0
	camera.position = Vector3(-5.0, 9.8, 10.2)
	world.add_child(camera)
	camera.look_at(Vector3(-2.2, 0.0, 0.6), Vector3.UP)
	camera.current = true
	var r := RandomNumberGenerator.new()
	r.seed = abs(str(stage.seed).hash())
	_build_ground(biome, r)
	_build_surroundings(biome, r)
	match str(stage.type):
		"Exploration": _build_pois()
		"Defense": _build_beacon()

func _ground_mask(p: Vector2) -> Color:
	# un sentiero di terra attraversa l'arena da sinistra a destra
	var lane := absf(p.y - sin(p.x * 0.18) * 1.6) - 1.4
	var dirt := smoothstep(1.2, -0.4, lane)
	var patch := smoothstep(0.62, 0.8, (sin(p.x * 0.7 + 1.3) * cos(p.y * 0.9) * 0.5 + 0.5))
	dirt = maxf(dirt, patch * 0.7)
	var edge := smoothstep(ARENA_X + 3.0, ARENA_X + 9.0, absf(p.x)) + smoothstep(ARENA_Z + 2.0, ARENA_Z + 8.0, absf(p.y))
	return Color(clampf(dirt, 0, 1), 0, 0, lerpf(1.0, 0.85, clampf(edge, 0, 1)))

func _build_ground(biome: Dictionary, r: RandomNumberGenerator) -> void:
	var grass: Array = biome.grass
	var mat := WorldMaterials.terrain_biome(grass[0], grass[1], grass[2], biome.dirt)
	var b := MeshBuilder.new()
	b.material("ground", mat)
	var size_x := 76.0
	var size_z := 52.0
	var step := 0.8
	var nx := int(size_x / step)
	var nz := int(size_z / step)
	var heights := {}
	var noise := FastNoiseLite.new()
	noise.seed = r.randi()
	noise.frequency = 0.05
	for zi in nz + 1:
		for xi in nx + 1:
			var x := -size_x * 0.5 + xi * step
			var z := -size_z * 0.5 + zi * step - 6.0
			var outside := clampf(maxf((absf(x) - ARENA_X - 1.0) / 6.0, (absf(z) - ARENA_Z - 1.0) / 5.0), 0.0, 1.0)
			heights[Vector2i(xi, zi)] = (noise.get_noise_2d(x, z) * 0.5 + 0.5) * 1.6 * outside * (0.4 if z > 0 else 1.0)
	for zi in nz:
		for xi in nx:
			var pts: Array[Vector3] = []
			var cols: Array[Color] = []
			for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var x: float = -size_x * 0.5 + (xi + k.x) * step
				var z: float = -size_z * 0.5 + (zi + k.y) * step - 6.0
				pts.append(Vector3(x, heights[Vector2i(xi + k.x, zi + k.y)], z))
				cols.append(_ground_mask(Vector2(x, z)))
			var n1 := (pts[2] - pts[0]).cross(pts[1] - pts[0]).normalized()
			if n1.y < 0: n1 = -n1
			var n2 := (pts[3] - pts[0]).cross(pts[2] - pts[0]).normalized()
			if n2.y < 0: n2 = -n2
			b.tri("ground", pts[0], pts[1], pts[2], n1, n1, n1, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cols[0], cols[1], cols[2])
			b.tri("ground", pts[0], pts[2], pts[3], n2, n2, n2, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cols[0], cols[2], cols[3])
	var ground := b.instance(world, false)
	ground.name = "Ground"

func _build_surroundings(biome: Dictionary, r: RandomNumberGenerator) -> void:
	var weights: Dictionary = biome.trees
	var groups := {}
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < 90 and attempts < 3000:
		attempts += 1
		var p := Vector2(r.randf_range(-ARENA_X - 16.0, ARENA_X + 16.0), r.randf_range(-ARENA_Z - 16.0, ARENA_Z + 6.0))
		var inside := absf(p.x) < ARENA_X + 1.5 and absf(p.y) < ARENA_Z + 1.2
		if inside: continue
		if p.y > ARENA_Z + 1.0 and absf(p.x) < ARENA_X + 3.0: continue
		var close := false
		for q in placed:
			if q.distance_to(p) < 2.0:
				close = true
				break
		if close: continue
		placed.append(p)
		var roll := r.randf()
		var kind := "broadleaf"
		var acc := 0.0
		for k in weights:
			acc += float(weights[k])
			if roll <= acc:
				kind = k
				break
		var variant := r.randi_range(0, 3 if kind == "conifer" else 4 if kind == "broadleaf" else 1)
		var key := "%s_%d" % [kind, variant]
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(Vector3(p.x, 0.0, p.y), r.randf_range(0.9, 1.35), r.randf() * TAU))
	for i in 34:
		var p := Vector2(r.randf_range(-ARENA_X - 10.0, ARENA_X + 10.0), r.randf_range(-ARENA_Z - 9.0, ARENA_Z + 4.0))
		if absf(p.x) < ARENA_X - 1.0 and absf(p.y) < ARENA_Z - 0.5 and r.randf() < 0.75: continue
		var key := "rock_%d" % (i % 3)
		if not groups.has(key): groups[key] = []
		groups[key].append(NatureKit.placement(Vector3(p.x, -0.1, p.y), r.randf_range(0.5, 1.6), r.randf() * TAU))
	for key in groups:
		var parts := str(key).split("_")
		NatureKit.scatter(world, parts[0], int(parts[1]), groups[key], true)
	if not biome.get("no_grass", false):
		var tufts := [[], []]
		for i in 1200:
			var p := Vector2(r.randf_range(-ARENA_X - 12.0, ARENA_X + 12.0), r.randf_range(-ARENA_Z - 9.0, ARENA_Z + 5.0))
			if _ground_mask(p).r > 0.5: continue
			tufts[i % 2].append(NatureKit.placement(Vector3(p.x, 0.0, p.y), r.randf_range(0.8, 1.4), r.randf() * TAU))
		for v in 2: NatureKit.scatter(world, "tuft", v, tufts[v], false)
	_build_props(str(biome.props), r)

## Oggetti di scena del bioma: rovine, colonne, cristalli, guglie di ghiaccio.
func _build_props(kind: String, r: RandomNumberGenerator) -> void:
	var b := MeshBuilder.new()
	b.material("stone", WorldMaterials.stone("wall"))
	b.material("pale", WorldMaterials.stone("pale"))
	b.material("rubble", WorldMaterials.stone("rubble"))
	b.material("timber", WorldMaterials.wood("weathered"))
	b.material("plaster", WorldMaterials.plaster("grey"))
	b.material("roof", WorldMaterials.roof("shingle"))
	b.material("rock", WorldMaterials.terrain())
	b.material("ice", WorldMaterials.metal(Color("#cfe6f5"), 0.15, 0.1))
	b.material("crystal_a", WorldMaterials.glow(Color("#9a7cff"), 2.2))
	b.material("crystal_b", WorldMaterials.glow(Color("#6fd0ff"), 2.0))
	var spots: Array[Vector2] = []
	for i in 12:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector2(r.randf_range(-ARENA_X - 4.0, ARENA_X + 4.0), -ARENA_Z - r.randf_range(2.0, 7.0)) if i < 8 else Vector2(side * (ARENA_X + r.randf_range(2.5, 6.0)), r.randf_range(-ARENA_Z, ARENA_Z))
		spots.append(p)
	for i in spots.size():
		var p := spots[i]
		var pos := Vector3(p.x, 0, p.y)
		var yaw := r.randf() * TAU
		match kind:
			"ruins_village":
				if i % 3 == 0:
					b.push_at(pos, yaw)
					b.box("stone", Vector3(3.2, 0.5, 2.4), Vector3(0, 0.25, 0))
					b.box("plaster", Vector3(3.0, 1.6, 0.2), Vector3(0, 1.3, -1.1))
					b.box("plaster", Vector3(0.2, 1.1, 2.2), Vector3(-1.4, 1.05, 0))
					for k in 4: b.box("timber", Vector3(0.12, 0.12, 2.6), Vector3(-1.0 + k * 0.6, 1.9 + (k % 2) * 0.2, 0), Color.WHITE, Vector3(0.3, 0, 0.1 * k), MeshBuilder.UV.LONG)
					b.pop()
				else:
					b.push_at(pos, yaw)
					for k in 5: b.box("timber", Vector3(0.08, 0.7, 0.08), Vector3(-1.0 + k * 0.5, 0.35, 0), Color.WHITE, Vector3(0, 0, r.randf_range(-0.2, 0.2)), MeshBuilder.UV.LONG)
					b.box("timber", Vector3(2.2, 0.07, 0.05), Vector3(0, 0.5, 0), Color.WHITE, Vector3(0, 0, 0.1), MeshBuilder.UV.LONG)
					b.pop()
			"ruins_water", "ruins_temple":
				var col_key := "pale" if kind == "ruins_temple" else "stone"
				var h := r.randf_range(1.2, 3.6)
				b.cylinder(col_key, 0.32, 0.36, h, pos + Vector3(0, h * 0.5, 0), Color.WHITE, 12)
				b.box(col_key, Vector3(0.9, 0.3, 0.9), pos + Vector3(0, 0.15, 0))
				if h > 3.0: b.box(col_key, Vector3(0.95, 0.3, 0.95), pos + Vector3(0, h + 0.15, 0))
				else: b.rock("rubble", 0.32, pos + Vector3(0.8, 0.12, 0.3), Color.WHITE, Vector3(1.2, 0.6, 1.0), i, 0.2)
				if kind == "ruins_water" and i % 2 == 0: _puddle(pos + Vector3(1.6, 0.03, 0.8), r.randf_range(1.0, 1.8))
			"canyon":
				b.rock("rock", r.randf_range(1.4, 2.8), pos, Color(0, 0, 1, 1), Vector3(1.0, r.randf_range(1.2, 2.4), 0.9), i + 100, 0.25, false)
			"ice":
				for k in 3:
					var off := Vector3(r.randf_range(-0.8, 0.8), 0, r.randf_range(-0.8, 0.8))
					b.cone("ice", r.randf_range(0.25, 0.5), r.randf_range(1.2, 2.6), pos + off + Vector3(0, 0.6, 0), Color.WHITE, 5, Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2)))
			"crystals":
				for k in 4:
					var off := Vector3(r.randf_range(-0.7, 0.7), 0, r.randf_range(-0.7, 0.7))
					var h := r.randf_range(0.8, 2.2)
					b.sphere("crystal_a" if k % 2 == 0 else "crystal_b", 0.22, pos + off + Vector3(0, h * 0.4, 0), Color.WHITE, Vector3(0.7, h * 2.0, 0.7), 5, 2, false, Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3)))
				if i % 3 == 0: _light_pool(pos, Color("#8f7cff"), 2.5, 0.35)
			_:
				b.rock("rock", r.randf_range(0.6, 1.3), pos, Color(0, 0, 1, 1), Vector3(1.2, 0.8, 1.0), i + 40, 0.25)
	if b.has_geometry(): b.instance(world)

func _puddle(pos: Vector3, radius: float) -> void:
	var m := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 20
	m.mesh = disc
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/hub3d/water.gdshader")
	mat.set_shader_parameter("speed", 0.2)
	mat.set_shader_parameter("alpha", 0.85)
	m.material_override = mat
	m.position = pos
	world.add_child(m)

func _light_pool(pos: Vector3, color: Color, radius: float, strength: float) -> MeshInstance3D:
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
	mi.position = pos + Vector3(0, 0.05, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi

## Punti d'interesse: cippi di pietra con stendardo che si accende quando presi.
func _build_pois() -> void:
	for p in poi_points:
		var node := Node3D.new()
		node.position = Vector3(p.x, 0, p.y)
		world.add_child(node)
		var b := MeshBuilder.new()
		b.material("stone", WorldMaterials.stone("wall"))
		b.material("timber", WorldMaterials.wood("timber"))
		b.material("cloth", WorldMaterials.lit())
		b.material("rune", WorldMaterials.glow(Color("#e8c47e"), 1.6))
		b.cylinder("stone", 0.95, 1.05, 0.18, Vector3(0, 0.09, 0), Color.WHITE, 16)
		b.box("stone", Vector3(0.5, 0.9, 0.4), Vector3(0, 0.6, 0))
		b.box("rune", Vector3(0.18, 0.4, 0.02), Vector3(0, 0.65, 0.21))
		b.rod("timber", Vector3(0.45, 0.1, 0), Vector3(0.45, 2.3, 0), 0.04, 0.035, Color.WHITE, 6)
		b.box("cloth", Vector3(0.62, 0.42, 0.03), Vector3(0.78, 2.0, 0), Color("#6e2a2a"))
		b.instance(node)
		poi_nodes.append(node)

## Faro del Rift da difendere.
func _build_beacon() -> void:
	beacon_node = Node3D.new()
	beacon_node.position = Vector3(beacon_pos.x, 0, beacon_pos.y)
	world.add_child(beacon_node)
	var b := MeshBuilder.new()
	b.material("stone", WorldMaterials.stone("pale"))
	b.material("dark", WorldMaterials.stone("dark"))
	b.material("fire", WorldMaterials.glow(Color("#ffc46a"), 3.2))
	b.material("metal", WorldMaterials.metal(Color.WHITE, 0.5, 0.7))
	b.cylinder("dark", 1.0, 1.15, 0.45, Vector3(0, 0.22, 0), Color.WHITE, 12)
	b.cylinder("stone", 0.42, 0.55, 2.6, Vector3(0, 1.75, 0), Color.WHITE, 10)
	b.cylinder("metal", 0.6, 0.4, 0.3, Vector3(0, 3.2, 0), Color("#2d2b29"), 12)
	b.sphere("fire", 0.38, Vector3(0, 3.55, 0), Color.WHITE, Vector3(1.0, 1.3, 1.0), 10, 6)
	b.instance(beacon_node)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 3.6, 0)
	light.light_color = Color("#ffbf6a")
	light.light_energy = 2.0
	light.omni_range = 8.0
	beacon_node.add_child(light)
	_light_pool(Vector3(beacon_pos.x, 0, beacon_pos.y), Color("#ffb35c"), 4.0, 0.35)

# =============================================================================
# HUD
# =============================================================================

func _hud_style(padding: float = 10.0) -> OrnateStyle:
	var s := UIKit.ornate("hud", padding)
	return s

func _build_hud() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.02, 0.04, 0.65))
	gradient.set_color(1, Color(0.03, 0.02, 0.04, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_to = Vector2(0, 1)
	shade.texture = tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shade.offset_bottom = 150
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# obiettivo
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -330
	top.offset_right = 330
	top.offset_top = 12
	top.add_theme_stylebox_override("panel", UIKit.ornate("plate", 0.0).set_padding(26.0, 8.0))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	title_label = UIKit.title("Piano %d · %s" % [int(stage.floor), stage.name], 22, UIKit.INK)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label = UIKit.label(str(stage.objective).to_upper(), 14, UIKit.GOLD, UIKit.head_medium())
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label = UIKit.label("", 15, UIKit.INK_SOFT, UIKit.body_bold())
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(title_label)
	tv.add_child(objective_label)
	tv.add_child(progress_label)
	top.add_child(tv)
	add_child(top)
	# barra del guardiano
	boss_panel = PanelContainer.new()
	boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_panel.offset_left = -380
	boss_panel.offset_right = 380
	boss_panel.offset_top = 112
	boss_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 3)
	boss_label = UIKit.label("", 16, Color("#f0c9b0"), UIKit.head_font())
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	boss_label.add_theme_constant_override("outline_size", 6)
	bv.add_child(boss_label)
	boss_bar = ProgressBar.new()
	boss_bar.show_percentage = false
	boss_bar.custom_minimum_size = Vector2(760, 16)
	boss_bar.add_theme_stylebox_override("background", UIKit.box(Color(0.05, 0.03, 0.04, 0.9), Color("#2fb4cf"), 2, 2, 0))
	boss_bar.add_theme_stylebox_override("fill", UIKit.box(Color("#b8323e"), Color.TRANSPARENT, 0, 1, 0))
	bv.add_child(boss_bar)
	boss_panel.add_child(bv)
	boss_panel.visible = false
	add_child(boss_panel)
	# orologio e velocità
	var clock := PanelContainer.new()
	clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock.offset_left = -236
	clock.offset_right = -18
	clock.offset_top = 14
	clock.add_theme_stylebox_override("panel", _hud_style(8.0).set_padding(14.0, 6.0))
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	clock_label = UIKit.title("00:00", 24, UIKit.INK)
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(clock_label)
	speed_button = UIKit.button("×1", _toggle_speed, "ghost", 60)
	ch.add_child(speed_button)
	clock.add_child(ch)
	add_child(clock)
	# squadra a sinistra
	party_box = VBoxContainer.new()
	party_box.position = Vector2(16, 16)
	party_box.custom_minimum_size.x = 300
	party_box.add_theme_constant_override("separation", 8)
	add_child(party_box)
	# registro
	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	log_panel.offset_left = -450
	log_panel.offset_right = -18
	log_panel.offset_top = -290
	log_panel.offset_bottom = -124
	var ls := UIKit.ornate("hud", 12.0)
	ls.fill_top = Color(0.07, 0.05, 0.09, 0.72)
	ls.fill_bottom = Color(0.04, 0.03, 0.05, 0.72)
	log_panel.add_theme_stylebox_override("panel", ls)
	log_box = VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 2)
	log_panel.add_child(log_box)
	add_child(log_panel)
	# ordini
	var commands := HBoxContainer.new()
	commands.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	commands.offset_left = -580
	commands.offset_right = 580
	commands.offset_top = -104
	commands.offset_bottom = -18
	commands.add_theme_constant_override("separation", 10)
	add_child(commands)
	var caption := PanelContainer.new()
	caption.add_theme_stylebox_override("panel", _hud_style(10.0))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -2)
	cv.add_child(UIKit.label("ORDINI DEL MASTER", 14, UIKit.GOLD, UIKit.head_font()))
	cv.add_child(UIKit.label("Solo ordini generali:", 13, UIKit.INK_SOFT, UIKit.body_font()))
	cv.add_child(UIKit.label("gli eroi decidono come.", 13, UIKit.INK_SOFT, UIKit.body_font()))
	caption.add_child(cv)
	commands.add_child(caption)
	_add_command(commands, "posture", "[1] Avanza", "primary")
	_add_command(commands, "focus", "[2] Alta minaccia", "sky")
	_add_command(commands, "protect", "[3] Proteggi retro", "sky")
	_add_command(commands, "all_out", "[4] Tutto per tutto", "gold")
	_add_command(commands, "extract", "[X] Ritirata", "danger")

func _add_command(parent: HBoxContainer, key: String, text: String, kind: String) -> void:
	var b := UIKit.button(text, _use_command.bind(key), kind, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 62
	b.add_theme_font_size_override("font_size", 16)
	parent.add_child(b)
	command_buttons[key] = b

func _toggle_speed() -> void:
	speed_scale = 2.0 if speed_scale < 1.5 else 1.0
	speed_button.text = "×%d" % roundi(speed_scale)

# =============================================================================
# Unità
# =============================================================================

func _create_heroes() -> void:
	var party_ids := []
	for hero_source in party_source:
		if not hero_source.is_empty(): party_ids.append(str(hero_source.id))
	var bonded := []
	for i in party_source.size():
		var source: Dictionary = party_source[i]
		if source.is_empty(): continue
		var d := GameState.derived_stats(source)
		var role := str(source.role)
		var ranged := role in ["Ranger", "Mage", "Support"]
		var unit := {
			"entity_id": next_id, "hero": true, "id": source.id, "name": str(source.name), "role": role, "source": source,
			"pos": FORMATION[i], "anchor": FORMATION[i], "hp": float(d.max_hp), "max_hp": float(d.max_hp),
			"attack": float(max(d.attack * 0.75, d.magic) if role in ["Mage", "Support"] else d.attack), "defense": float(d.defense),
			"accuracy": float(d.accuracy), "evasion": float(d.evasion), "crit": float(d.crit), "block": float(d.block),
			"range": 7.0 if role in ["Ranger", "Mage"] else 6.0 if role == "Support" else 2.0 if role == "Lancer" else 1.25,
			"speed": 3.0 if role == "Ranger" else 2.6, "cooldown": rng.randf_range(0.2, 0.8), "skill_cd": rng.randf_range(2.0, 4.0),
			"cadence": 1.35 if role in ["Mage", "Support"] else 1.0, "target": -1, "action": "hold", "alive": true,
			"kills": 0, "damage": 0, "healing": 0, "ammo": int(d.ammo), "max_ammo": int(d.ammo), "status": "", "fear": 0.0,
			"courage": int(source.personality.courage), "ranged": ranged, "threat": 0,
		}
		# legami: i compagni fidati danno forza e coraggio, i rivali tolgono coraggio
		var bonus: Dictionary = GameState.party_bond_bonus(str(source.id), party_ids)
		unit.attack = float(unit.attack) * float(bonus.attack)
		unit.courage = int(unit.courage) + int(bonus.courage)
		if int(bonus.close) > 0: bonded.append(str(source.name))
		var model := CharacterModel.new()
		world.add_child(model)
		model.build_hero(source, GameState.hero_appearance(source))
		model.scale = Vector3.ONE * UNIT_SCALE
		model.position = Vector3(unit.pos.x, 0, unit.pos.y)
		model.rotation.y = PI / 2
		model.phase = rng.randf() * 5.0
		unit.model = model
		units.append(unit)
		next_id += 1
		_make_party_card(unit)
	if bonded.size() >= 2: _log("Legami forti in squadra: %s combattono fianco a fianco." % ", ".join(bonded), "good")

func _make_party_card(unit: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _hud_style(8.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var p: HeroPortrait = HeroPortraitScript.new()
	p.setup(unit.source, 56)
	row.add_child(p)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	var name_row := HBoxContainer.new()
	var name_label := UIKit.label(str(unit.name).to_upper(), 15, UIKit.INK, UIKit.head_font())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_row.add_child(name_label)
	var hp_text := UIKit.label("", 13, UIKit.INK_SOFT, UIKit.body_bold())
	name_row.add_child(hp_text)
	v.add_child(name_row)
	var hp := ProgressBar.new()
	hp.show_percentage = false
	hp.custom_minimum_size.y = 10
	hp.max_value = float(unit.max_hp)
	hp.value = float(unit.hp)
	hp.add_theme_stylebox_override("background", UIKit.box(Color(0.05, 0.03, 0.04, 0.9), Color("#26344b"), 1, 2, 0))
	hp.add_theme_stylebox_override("fill", UIKit.box(Color("#4fae7c"), Color.TRANSPARENT, 0, 1, 0))
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hp)
	var status := UIKit.label(GameState.role_label(unit.role), 13, UIKit.MUTED, UIKit.body_bold())
	v.add_child(status)
	row.add_child(v)
	card.add_child(row)
	party_box.add_child(card)
	party_cards[unit.entity_id] = {"card": card, "hp": hp, "hp_text": hp_text, "status": status, "portrait": p}

func _spawn_enemy(kind: String, wave: int, index: int) -> void:
	var t: Dictionary = ENEMY_TEMPLATES[kind]
	var floor_index := int(stage.floor)
	var boss := kind == "boss"
	# crescita più dolce dopo i primi piani; il guardiano scala meno dei gregari
	var hp_scale := (0.8 + floor_index * 0.12) if boss else (0.8 + floor_index * 0.18)
	var atk_scale := (0.85 + floor_index * 0.08) if boss else (0.85 + floor_index * 0.13)
	var def_scale := (0.8 + floor_index * 0.12) if boss else (0.8 + floor_index * 0.18)
	var pos := Vector2(ARENA_X - 0.5 + rng.randf_range(0.0, 1.5), clampf(-ARENA_Z + 1.0 + fmod(float(wave * 3 + index * 2), 6.0) * 2.1 + rng.randf_range(-0.5, 0.5), -ARENA_Z + 0.8, ARENA_Z - 0.8))
	var unit := {
		"entity_id": next_id, "hero": false, "kind": kind, "name": str(t.name), "pos": pos, "hp": float(t.hp) * hp_scale, "max_hp": float(t.hp) * hp_scale,
		"attack": float(t.attack) * atk_scale, "defense": float(t.defense) * def_scale, "speed": float(t.speed), "cooldown": rng.randf_range(0.2, 0.9),
		"cadence": float(t.cadence), "threat": int(t.threat), "range": float(t.range), "target": -1, "alive": true, "slam_cd": 6.0,
		"accuracy": 82.0, "evasion": 4.0, "crit": 4.0, "block": 0.0, "ranged": kind == "archer",
	}
	var model := CharacterModel.new()
	world.add_child(model)
	model.build_monster(kind, t.tint)
	model.scale = Vector3.ONE * UNIT_SCALE
	model.position = Vector3(pos.x, 0, pos.y)
	model.rotation.y = -PI / 2
	model.phase = rng.randf() * 5.0
	unit.model = model
	units.append(unit)
	next_id += 1
	if boss:
		boss_label.text = ("%s · Guardiano del Piano %d" % [str(stage.get("name", "")), floor_index]).to_upper()
		boss_panel.visible = true
		boss_panel.set_meta("boss_id", unit.entity_id)

func _heroes() -> Array:
	return units.filter(func(u): return u.hero and u.alive)

func _enemies() -> Array:
	return units.filter(func(u): return not u.hero and u.alive)

func _find(entity_id: int) -> Dictionary:
	for u in units:
		if int(u.entity_id) == entity_id: return u
	return {}

# =============================================================================
# Simulazione
# =============================================================================

func _process(delta: float) -> void:
	if running and not completed:
		accumulator += minf(delta, 0.1) * speed_scale
		while accumulator >= TICK and not completed:
			_tick(TICK)
			accumulator -= TICK
		_update_hud()
	for u in units:
		var model: CharacterModel = u.model
		if not is_instance_valid(model): continue
		var target := Vector3(u.pos.x, model.position.y, u.pos.y)
		var moving := Vector2(model.position.x, model.position.z).distance_to(u.pos) > 0.02
		model.position = model.position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))
		if u.alive:
			if moving and u.get("action", "") != "attack": model.play("walk")
			elif model.anim == "walk": model.play("idle")
		model.update_animation(delta, speed_scale)
		var flash := float(u.get("flash", 0.0))
		if flash > 0.0:
			u.flash = maxf(0.0, flash - delta * 5.0)
			model.flash(u.flash * 0.9)
	_update_effects(delta)
	_follow_action(delta)
	overlay.queue_redraw()

## La camera segue dolcemente il baricentro dello scontro.
func _follow_action(delta: float) -> void:
	var sum := Vector2.ZERO
	var count := 0
	for u in units:
		if not u.alive: continue
		var weight := 2 if u.hero else 1
		sum += u.pos * weight
		count += weight
	if count == 0: return
	var center := sum / count
	var focus := Vector3(clampf(center.x, -9.0, 9.0), 0.0, clampf(center.y, -3.0, 3.0) - 0.6)
	var offset := Vector3(-0.3, 9.8, 11.2)
	var desired := focus + offset
	camera.position = camera.position.lerp(desired, clampf(delta * 1.5, 0.0, 1.0))
	camera.look_at(camera.position - offset, Vector3.UP)

func _tick(delta: float) -> void:
	elapsed += delta
	decision_timer -= delta
	_spawn_waves()
	if command_state.extracting and elapsed >= float(command_state.extract_at):
		_finish(false, "extracted")
		return
	if decision_timer <= 0.0:
		decision_timer = DECISION
		_decide()
	for u in units:
		if u.alive: _update_unit(u, delta)
	_update_objective(delta)
	_check_end()

func _spawn_waves() -> void:
	for index in stage.waves.size():
		if spawned_waves.has(index): continue
		var wave: Array = stage.waves[index]
		if elapsed < float(wave[0]): continue
		spawned_waves.append(index)
		for i in int(wave[2]): _spawn_enemy(str(wave[1]), index, i)
		_log("%s: %d × %s in arrivo." % ["Contatto" if index == 0 else "Rinforzi", int(wave[2]), ENEMY_TEMPLATES[str(wave[1])].name], "warn" if index > 0 else "")

func _score_target(hero: Dictionary, enemy: Dictionary) -> float:
	var distance: float = hero.pos.distance_to(enemy.pos)
	var score := -distance
	if command_state.focus: score += float(enemy.threat) * 2.2
	score += (1.0 - float(enemy.hp) / float(enemy.max_hp)) * 2.0
	if command_state.protect and str(GameState.ROLES[hero.role].line) == "Front":
		var rear_threat := 99.0
		for ally in _heroes():
			if str(GameState.ROLES[ally.role].line) != "Front": rear_threat = minf(rear_threat, ally.pos.distance_to(enemy.pos))
		score += maxf(0.0, 6.0 - rear_threat) * 1.4
	if int(enemy.get("target", -1)) == int(hero.entity_id): score += 1.5
	var aggression := float(hero.source.personality.aggression) / 100.0
	score += aggression * float(enemy.threat) * 0.4
	return score

func _decide() -> void:
	var enemies := _enemies()
	var heroes := _heroes()
	for hero in heroes:
		if float(hero.fear) > 0.0:
			hero.action = "retreat"
			continue
		if hero.role == "Support":
			var wounded := heroes.filter(func(a): return float(a.hp) / float(a.max_hp) < 0.65)
			wounded.sort_custom(func(a, b): return float(a.hp) / float(a.max_hp) < float(b.hp) / float(b.max_hp))
			if not wounded.is_empty() and float(hero.skill_cd) <= 0.0:
				hero.target = int(wounded[0].entity_id)
				hero.action = "heal"
				continue
		if enemies.is_empty():
			hero.target = -1
			hero.action = "regroup"
			continue
		var best: Dictionary = {}
		var best_score := -INF
		for enemy in enemies:
			var s := _score_target(hero, enemy)
			if s > best_score:
				best_score = s
				best = enemy
		hero.target = int(best.entity_id)
		hero.action = "engage"
	# esplorazione: se il punto è libero, l'eroe più vicino va a prenderlo
	if str(stage.type) == "Exploration" and int(objective.poi) < 3:
		var p: Vector2 = poi_points[int(objective.poi)]
		var contested := enemies.any(func(e): return e.pos.distance_to(p) < 5.0)
		if not contested:
			var runner: Dictionary = {}
			var best_d := INF
			for hero in heroes:
				if str(hero.action) in ["retreat", "heal"]: continue
				var d: float = hero.pos.distance_to(p)
				if d < best_d:
					best_d = d
					runner = hero
			if not runner.is_empty():
				runner.action = "capture"
				runner.target = -1
	for enemy in enemies:
		var best: Dictionary = {}
		var best_distance := INF
		for hero in heroes:
			var d: float = enemy.pos.distance_to(hero.pos)
			if str(GameState.ROLES[hero.role].line) == "Front": d -= 1.2
			if d < best_distance:
				best_distance = d
				best = hero
		if str(stage.type) == "Defense" and enemy.pos.distance_to(beacon_pos) < best_distance + 1.0:
			enemy.target = -2
		else:
			enemy.target = int(best.get("entity_id", -1))

func _update_unit(u: Dictionary, delta: float) -> void:
	u.cooldown = float(u.cooldown) - delta
	if u.has("skill_cd"): u.skill_cd = float(u.skill_cd) - delta
	if u.hero: _update_hero(u, delta)
	else: _update_enemy(u, delta)
	u.pos = Vector2(clampf(u.pos.x, -ARENA_X, ARENA_X + 2.0), clampf(u.pos.y, -ARENA_Z, ARENA_Z))

func _move_towards(u: Dictionary, target: Vector2, delta: float, speed_mult: float = 1.0) -> void:
	var to: Vector2 = target - u.pos
	if to.length() < 0.05: return
	var step := float(u.speed) * delta * speed_mult
	u.pos = u.pos + to.normalized() * minf(step, to.length())
	# separazione dagli alleati
	var spacing := 0.85 if u.get("kind", "") != "boss" else 1.6
	for other in units:
		if other == u or not other.alive or other.hero != u.hero: continue
		var gap: Vector2 = u.pos - other.pos
		var need := maxf(spacing, 1.6 if other.get("kind", "") == "boss" else 0.0)
		if gap.length() < need and gap.length() > 0.001: u.pos = u.pos + gap.normalized() * (need - gap.length()) * 0.5
	_face(u, target)

func _face(u: Dictionary, target: Vector2) -> void:
	var dir: Vector2 = target - u.pos
	if dir.length() > 0.01 and is_instance_valid(u.model):
		(u.model as Node3D).rotation.y = atan2(dir.x, dir.y)

func _update_hero(hero: Dictionary, delta: float) -> void:
	if float(hero.fear) > 0.0: hero.fear = float(hero.fear) - delta
	var posture: String = command_state.posture
	var speed_mult := 1.0 if posture == "ADVANCE" else 0.6
	match str(hero.action):
		"retreat":
			_move_towards(hero, hero.anchor + Vector2(-2.0, 0.0), delta, 1.1)
			hero.status = "Spaventato"
			return
		"regroup":
			var anchor: Vector2 = hero.anchor
			if str(stage.type) == "Exploration" and int(objective.poi) < 3: anchor = poi_points[int(objective.poi)] + (hero.anchor - FORMATION[0]) * 0.5 + Vector2(-1.0, 0.0)
			_move_towards(hero, anchor, delta)
			hero.status = ""
			return
		"capture":
			var p: Vector2 = poi_points[mini(int(objective.poi), poi_points.size() - 1)]
			if hero.pos.distance_to(p) > 0.8: _move_towards(hero, p, delta, speed_mult)
			hero.status = "Esplora"
			return
		"heal":
			var ally := _find(int(hero.target))
			if ally.is_empty() or not ally.alive or not ally.hero or float(hero.skill_cd) > 0.0:
				# niente da curare: si torna a cercare un nemico alla prossima decisione
				hero.target = -1
				hero.action = "regroup"
				return
			if hero.pos.distance_to(ally.pos) > float(hero.range):
				_move_towards(hero, ally.pos, delta, speed_mult)
				return
			_face(hero, ally.pos)
			var amount: float = 35.0 + float(hero.source.stats.int) * 1.7
			ally.hp = minf(float(ally.max_hp), float(ally.hp) + amount)
			hero.healing = int(hero.healing) + roundi(amount)
			hero.skill_cd = 8.5
			hero.model.play("attack")
			_ring(ally.pos, Color("#59e29a"), 1.4)
			_float_text(ally.pos, "+%d" % roundi(amount), Color("#7fe8a8"))
			_log("%s cura %s (+%d)." % [hero.name, ally.name, roundi(amount)], "good")
			return
	var target := _find(int(hero.target))
	if target.is_empty() or not target.alive or target.hero: return
	var distance: float = hero.pos.distance_to(target.pos)
	var reach := float(hero.range) + (0.9 if target.get("kind", "") == "boss" else 0.0)
	if posture == "RETREAT":
		_move_towards(hero, Vector2(-ARENA_X + 1.0, hero.pos.y), delta, 1.0)
		if distance > reach: return
	elif bool(hero.ranged) and distance < 3.0 and posture != "HOLD":
		# I combattenti a distanza arretrano per mantenere lo spazio
		var away: Vector2 = hero.pos + (hero.pos - target.pos).normalized() * 1.5
		_move_towards(hero, away, delta, 0.9)
	elif distance > reach:
		if posture == "HOLD" and hero.pos.distance_to(hero.anchor) > 2.5: return
		_move_towards(hero, target.pos, delta, speed_mult)
		hero.status = ""
		return
	_face(hero, target.pos)
	if float(hero.cooldown) > 0.0: return
	if hero.role == "Ranger":
		if int(hero.ammo) <= 0:
			hero.status = "Senza frecce"
			hero.cooldown = 1.5
			hero.range = 1.2
			hero.ranged = false
			return
		hero.ammo = int(hero.ammo) - 1
		if int(hero.ammo) == 4: _log(hero.name + ": restano 4 frecce.", "warn")
	var coefficient := 1.0
	if float(hero.skill_cd) <= 0.0 and (int(target.threat) >= 3 or rng.randf() < 0.2):
		coefficient = 1.6
		hero.skill_cd = 9.0
		_ring(target.pos, UIKit.GOLD, 1.0)
		_float_text(hero.pos, RiftwardState.skill_label(str(hero.source.skills[0].name)), Color("#e8c47e"))
	var all_out := elapsed < float(command_state.all_out_until)
	hero.model.play("attack")
	if bool(hero.ranged): _projectile(hero, target)
	_deal_damage(hero, target, coefficient)
	hero.cooldown = float(hero.cadence) * (0.7 if all_out else 1.0)

func _update_enemy(enemy: Dictionary, delta: float) -> void:
	if enemy.kind == "boss":
		enemy.slam_cd = float(enemy.slam_cd) - delta
		if float(enemy.slam_cd) <= 0.0:
			enemy.slam_cd = 7.5
			enemy.model.play("attack")
			_ring(enemy.pos, UIKit.ROSE, 2.6)
			_log("Il Guardiano colpisce il terreno!", "danger")
			for hero in _heroes():
				if hero.pos.distance_to(enemy.pos) < 2.6: _deal_damage(enemy, hero, 0.75)
	var target_pos: Vector2
	var target: Dictionary = {}
	if int(enemy.target) == -2:
		target_pos = beacon_pos
	else:
		target = _find(int(enemy.target))
		if target.is_empty() or not target.alive: return
		target_pos = target.pos
	var distance: float = enemy.pos.distance_to(target_pos)
	if distance > float(enemy.range):
		_move_towards(enemy, target_pos, delta)
		return
	_face(enemy, target_pos)
	if float(enemy.cooldown) > 0.0: return
	enemy.cooldown = float(enemy.cadence)
	enemy.model.play("attack")
	if int(enemy.target) == -2:
		objective.beacon = maxf(0.0, float(objective.beacon) - float(enemy.attack) * 0.12)
		_float_text(beacon_pos, "-%d" % roundi(float(enemy.attack) * 0.12), Color("#ff8a7a"))
		return
	if bool(enemy.ranged): _projectile(enemy, target)
	_deal_damage(enemy, target, 1.0)

func _deal_damage(attacker: Dictionary, target: Dictionary, coefficient: float) -> void:
	# mai colpire la propria parte
	if bool(attacker.get("hero", false)) == bool(target.get("hero", false)): return
	var hit_chance := clampf(float(attacker.get("accuracy", 85.0)) - float(target.get("evasion", 0.0)), 35.0, 98.0)
	if rng.randf_range(0.0, 100.0) > hit_chance:
		_float_text(target.pos, "mancato", Color("#cfc6d6"))
		return
	var raw: float = float(attacker.attack) * coefficient * rng.randf_range(0.92, 1.08)
	var crit := rng.randf_range(0.0, 100.0) < float(attacker.get("crit", 3.0))
	if crit: raw *= 1.6
	if float(target.get("block", 0.0)) > 0.0 and rng.randf_range(0.0, 100.0) < float(target.block):
		raw *= 0.45
	var damage := maxi(1, roundi(raw * 100.0 / (100.0 + float(target.defense))))
	target.hp = maxf(0.0, float(target.hp) - damage)
	target.flash = 1.0
	attacker.damage = int(attacker.get("damage", 0)) + damage
	_float_text(target.pos, ("%d!" % damage) if crit else str(damage), Color("#ff6a78") if target.hero else (Color("#ffd27a") if crit else Color("#f4ece0")))
	if target.hero and float(target.hp) > 0.0:
		var ratio := float(target.hp) / float(target.max_hp)
		if ratio < 0.25 and int(target.courage) < 45 and float(target.fear) <= 0.0 and command_state.posture != "ADVANCE":
			target.fear = 2.5
			_log("%s esita e arretra." % target.name, "warn")
	if float(target.hp) <= 0.0: _kill(target, attacker)

func _kill(target: Dictionary, attacker: Dictionary) -> void:
	if not target.alive: return
	target.alive = false
	(target.model as CharacterModel).play("dead")
	if not target.hero:
		var tween := create_tween()
		tween.tween_interval(1.8)
		tween.tween_property(target.model, "position:y", -1.2 * UNIT_SCALE, 1.4)
	if attacker.get("hero", false): attacker.kills = int(attacker.kills) + 1
	if target.hero:
		_log("%s è caduto. Non tornerà." % target.name, "danger")
		# chi gli era legato reagisce: dolore o furia
		for ally in _heroes():
			var value: int = GameState.bond(str(ally.id), str(target.id))
			if value >= RiftwardState.BOND_CLOSE:
				ally.attack = float(ally.attack) * 1.12
				ally.courage = int(ally.courage) + 10
				_log("%s è furioso per la caduta di %s." % [ally.name, target.name], "warn")
			elif value >= RiftwardState.BOND_FRIEND:
				ally.courage = int(ally.courage) - 12
				_log("%s è scosso per la caduta di %s." % [ally.name, target.name], "warn")
		var card: Dictionary = party_cards.get(target.entity_id, {})
		if not card.is_empty(): card.card.modulate = Color(0.75, 0.55, 0.55, 0.75)
		hero_died.emit(str(target.id), "Ucciso da " + str(attacker.name))
	else:
		if target.kind == "boss":
			objective.boss_dead = true
			_log("Il Guardiano è stato abbattuto!", "good")

func _update_objective(delta: float) -> void:
	match str(stage.type):
		"Exploration":
			if int(objective.poi) >= 3: return
			var p: Vector2 = poi_points[int(objective.poi)]
			var near := false
			for hero in _heroes():
				if hero.pos.distance_to(p) < 2.5: near = true
			if near and _enemies().filter(func(e): return e.pos.distance_to(p) < 4.0).is_empty():
				objective.poi_progress = float(objective.poi_progress) + delta
				if float(objective.poi_progress) >= 3.0:
					objective.poi_progress = 0.0
					objective.poi = int(objective.poi) + 1
					_ring(p, UIKit.GOLD, 2.0)
					_log("Punto d'interesse %d/3 in sicurezza." % int(objective.poi), "good")
					var done_index := int(objective.poi) - 1
					if done_index < poi_nodes.size(): _mark_poi(poi_nodes[done_index])

func _mark_poi(node: Node3D) -> void:
	var b := MeshBuilder.new()
	b.material("cloth", WorldMaterials.lit())
	b.material("glow", WorldMaterials.glow(Color("#e8c47e"), 2.4))
	b.box("cloth", Vector3(0.64, 0.44, 0.035), Vector3(0.78, 2.0, 0.0), Color("#c9a85a"))
	b.sphere("glow", 0.08, Vector3(0.45, 2.38, 0), Color.WHITE, Vector3.ONE, 8, 5)
	b.instance(node)
	_light_pool(node.position, Color("#e8c47e"), 1.8, 0.4)

func _check_end() -> void:
	var living_heroes := _heroes()
	var living_enemies := _enemies()
	if living_heroes.is_empty():
		_finish(false, "party_wipe")
		return
	var all_spawned: bool = spawned_waves.size() == stage.waves.size()
	match str(stage.type):
		"Survival":
			if elapsed >= float(stage.duration): _finish(true, "survived")
			return
		"Exploration":
			if int(objective.poi) >= 3 and all_spawned and living_enemies.is_empty(): _finish(true, "intel")
		"Boss":
			if bool(objective.boss_dead) and all_spawned and living_enemies.is_empty(): _finish(true, "boss")
		"Defense":
			if float(objective.beacon) <= 0.0:
				_finish(false, "beacon_lost")
				return
			if all_spawned and living_enemies.is_empty(): _finish(true, "clear")
			# il faro ha resistito fino alla fine: missione riuscita
			elif elapsed >= float(stage.duration):
				_finish(true, "defended")
				return
		_:
			if all_spawned and living_enemies.is_empty(): _finish(true, "clear")
	if not completed and elapsed >= float(stage.duration) and str(stage.type) != "Survival": _finish(false, "timeout")

func _finish(victory: bool, reason: String) -> void:
	if completed: return
	completed = true
	running = false
	result_victory = victory
	result_reason = reason
	var hero_results := []
	for u in units:
		if not u.hero: continue
		hero_results.append({"id": u.id, "alive": u.alive, "hp_ratio": float(u.hp) / float(u.max_hp), "kills": int(u.kills), "fatigue": roundi(10 + elapsed * 0.28 + (7 if float(u.hp) / float(u.max_hp) < 0.3 else 0))})
	for u in _heroes(): (u.model as CharacterModel).play("cheer" if victory else "idle")
	var banner := PanelContainer.new()
	var style := UIKit.ornate("plate", 0.0).set_padding(56.0, 18.0)
	style.border = UIKit.GOLD if victory else UIKit.ROSE
	style.ornament_color = (UIKit.GOLD if victory else UIKit.ROSE).lightened(0.2)
	banner.add_theme_stylebox_override("panel", style)
	var text := UIKit.title("VITTORIA" if victory else "RITIRATA" if reason == "extracted" else "SCONFITTA", 52, UIKit.GOLD.lightened(0.2) if victory else Color("#e88a8a"))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(text)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -240
	banner.offset_right = 240
	banner.offset_top = -60
	banner.offset_bottom = 60
	banner.modulate.a = 0.0
	add_child(banner)
	create_tween().tween_property(banner, "modulate:a", 1.0, 0.35)
	if is_inside_tree():
		await get_tree().create_timer(1.8).timeout
	battle_finished.emit({"victory": victory, "reason": reason, "duration": elapsed, "floor": int(stage.floor), "hero_results": hero_results})

# =============================================================================
# Ordini del Master
# =============================================================================

func _use_command(key: String) -> void:
	if completed or elapsed < float(command_ready[key]): return
	match key:
		"posture":
			var options := ["ADVANCE", "HOLD", "RETREAT"]
			command_state.posture = options[(options.find(command_state.posture) + 1) % options.size()]
			command_ready[key] = elapsed + 8.0
			_log("Ordine: " + {"ADVANCE": "avanzare", "HOLD": "mantenere la posizione", "RETREAT": "arretrare"}[command_state.posture] + ".", "warn")
		"focus":
			command_state.focus = not command_state.focus
			command_ready[key] = elapsed + 12.0
			_log("Priorità ai bersagli pericolosi: %s." % ("sì" if command_state.focus else "no"), "warn")
		"protect":
			command_state.protect = not command_state.protect
			command_ready[key] = elapsed + 12.0
			_log("Proteggere la retroguardia: %s." % ("sì" if command_state.protect else "no"), "warn")
		"all_out":
			command_state.all_out_until = elapsed + 10.0
			command_ready[key] = elapsed + 40.0
			_log("Tutto per tutto: 10 secondi di assalto.", "warn")
		"extract":
			command_state.extracting = true
			command_state.extract_at = elapsed + 6.0
			command_ready[key] = INF
			command_state.posture = "RETREAT"
			_log("Ritirata: estrazione tra 6 secondi.", "danger")
	_update_hud()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("macro_posture"): _use_command("posture")
	elif event.is_action_pressed("macro_focus"): _use_command("focus")
	elif event.is_action_pressed("macro_protect"): _use_command("protect")
	elif event.is_action_pressed("macro_all_out"): _use_command("all_out")
	elif event.is_action_pressed("macro_extract"): _use_command("extract")

func _update_hud() -> void:
	clock_label.text = "%02d:%02d" % [floori(elapsed / 60.0), floori(elapsed) % 60]
	var living := _enemies().size()
	match str(stage.type):
		"Survival": progress_label.text = "%d secondi alla fine" % maxi(0, ceili(float(stage.duration) - elapsed))
		"Exploration": progress_label.text = "Punti %d/3 · %d nemici" % [int(objective.poi), living]
		"Defense": progress_label.text = "Faro %d%% · %d nemici · %ds" % [roundi(float(objective.beacon)), living, maxi(0, ceili(float(stage.duration) - elapsed))]
		_: progress_label.text = "%d nemici in campo · ondate %d/%d" % [living, spawned_waves.size(), stage.waves.size()]
	for u in units:
		if not u.hero: continue
		var card: Dictionary = party_cards.get(u.entity_id, {})
		if card.is_empty(): continue
		card.hp.max_value = float(u.max_hp)
		card.hp.value = float(u.hp)
		card.hp_text.text = "%d/%d" % [roundi(float(u.hp)), roundi(float(u.max_hp))]
		var ratio := float(u.hp) / float(u.max_hp)
		var fill: StyleBoxFlat = card.hp.get_theme_stylebox("fill")
		fill.bg_color = Color("#4fae7c") if ratio > 0.5 else Color("#d9a441") if ratio > 0.25 else Color("#cf4d60")
		var text := GameState.role_label(u.role)
		if not u.alive: text = "Caduto"
		elif int(u.max_ammo) > 0: text += " · frecce %d/%d" % [int(u.ammo), int(u.max_ammo)]
		if u.alive and not str(u.status).is_empty(): text += " · " + str(u.status)
		card.status.text = text
		card.status.add_theme_color_override("font_color", UIKit.ROSE if not u.alive else UIKit.MUTED)
	if boss_panel.visible:
		var boss := _find(int(boss_panel.get_meta("boss_id", -1)))
		if boss.is_empty() or not boss.alive:
			boss_panel.visible = false
		else:
			boss_bar.max_value = float(boss.max_hp)
			boss_bar.value = float(boss.hp)
	var labels := {"posture": "[1] " + {"ADVANCE": "Avanza", "HOLD": "Mantieni", "RETREAT": "Arretra"}[command_state.posture], "focus": "[2] Alta minaccia" + (" ✓" if command_state.focus else ""), "protect": "[3] Proteggi retro" + (" ✓" if command_state.protect else ""), "all_out": "[4] Tutto per tutto", "extract": "[X] Ritirata"}
	for key in command_buttons:
		var b: Button = command_buttons[key]
		var remaining := float(command_ready[key]) - elapsed
		b.disabled = remaining > 0.0 or completed
		b.text = labels[key] + (("  %ds" % ceili(remaining)) if remaining > 0.0 and remaining < 999.0 else "")

# =============================================================================
# Effetti
# =============================================================================

func _ring(pos: Vector2, color: Color, radius: float) -> void:
	var b := MeshBuilder.new()
	b.material("ring", WorldMaterials.transparent(Color(color.r, color.g, color.b, 0.85), true, 1.5))
	b.torus("ring", radius * 0.3, 0.06, Vector3.ZERO, Color.WHITE, Vector3.ZERO, 32, 4)
	var ring := b.instance(world, false)
	ring.position = Vector3(pos.x, 0.1, pos.y)
	effects.append({"node": ring, "life": 0.6, "max": 0.6, "grow": radius})

func _projectile(from: Dictionary, to: Dictionary) -> void:
	var role := str(from.get("role", ""))
	var arrow: bool = role == "Ranger" or str(from.get("kind", "")) == "archer"
	var b := MeshBuilder.new()
	var node: MeshInstance3D
	if arrow:
		b.material("wood", WorldMaterials.lit())
		b.material("tip", WorldMaterials.metal(Color.WHITE, 0.4, 0.8))
		b.rod("wood", Vector3(0, 0, -0.35), Vector3(0, 0, 0.3), 0.012, 0.012, Color("#d9cfb4"), 4)
		b.cone("tip", 0.025, 0.08, Vector3(0, 0, 0.34), Color("#b8bec6"), 4, Vector3(PI / 2, 0, 0))
		b.box("wood", Vector3(0.06, 0.005, 0.1), Vector3(0, 0, -0.3), Color("#8a2f2f"))
		node = b.instance(world, false)
	else:
		var color := Color("#ff8a3d") if role == "Mage" else Color("#59e29a") if role == "Support" else Color("#e8dcc0") if from.hero else Color("#ff5a6e")
		b.material("orb", WorldMaterials.glow(color, 3.0))
		b.sphere("orb", 0.14, Vector3.ZERO, Color.WHITE, Vector3.ONE, 8, 5)
		node = b.instance(world, false)
	var start := Vector3(from.pos.x, 1.0 * UNIT_SCALE * 0.8, from.pos.y)
	var finish := Vector3(to.pos.x, 0.8 * UNIT_SCALE * 0.8, to.pos.y)
	node.position = start
	node.look_at_from_position(start, finish, Vector3.UP)
	node.rotate_object_local(Vector3.UP, PI)
	effects.append({"node": node, "life": 0.28, "max": 0.28, "from": start, "to": finish})

func _float_text(pos: Vector2, text: String, color: Color) -> void:
	floaters.append({"pos": Vector3(pos.x + rng.randf_range(-0.3, 0.3), 1.9, pos.y), "text": text, "color": color, "life": 0.95})

func _update_effects(delta: float) -> void:
	for e in effects:
		e.life = float(e.life) - delta * speed_scale
		var node: Node3D = e.node
		if not is_instance_valid(node): continue
		var k := 1.0 - float(e.life) / float(e.max)
		if e.has("grow"):
			node.scale = Vector3.ONE * (1.0 + k * 2.5)
			(node as GeometryInstance3D).transparency = k
		elif e.has("from"):
			node.position = (e.from as Vector3).lerp(e.to, k) + Vector3(0, sin(k * PI) * 0.5, 0)
	for e in effects.filter(func(x): return float(x.life) <= 0.0):
		if is_instance_valid(e.node): e.node.queue_free()
	effects = effects.filter(func(x): return float(x.life) > 0.0)
	for f in floaters:
		f.life = float(f.life) - delta
		f.pos = (f.pos as Vector3) + Vector3(0, delta * 1.1, 0)
	floaters = floaters.filter(func(x): return float(x.life) > 0.0)

func _draw_overlay() -> void:
	if camera == null: return
	var font := UIKit.title_font()
	var body := UIKit.head_font()
	for u in units:
		if not u.alive: continue
		var head_y := 1.75 if u.get("kind", "") != "boss" else 4.4
		if u.get("kind", "") == "brute": head_y = 2.55
		if u.get("kind", "") == "hound": head_y = 1.0
		var world_pos := Vector3(u.pos.x, head_y, u.pos.y)
		if camera.is_position_behind(world_pos): continue
		var p := camera.unproject_position(world_pos)
		var w := 56.0 if u.get("kind", "") != "boss" else 0.0
		if w > 0.0:
			var ratio := clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)
			overlay.draw_rect(Rect2(p + Vector2(-w * 0.5 - 2, -2), Vector2(w + 4, 9)), Color(0.04, 0.03, 0.05, 0.85))
			overlay.draw_rect(Rect2(p + Vector2(-w * 0.5, 0), Vector2(w * ratio, 5)), Color("#4fae7c") if u.hero else Color("#c23b48"))
			overlay.draw_rect(Rect2(p + Vector2(-w * 0.5 - 2, -2), Vector2(w + 4, 9)), Color(0.62, 0.45, 0.28, 0.6), false, 1.0)
		if u.hero:
			var name_text := str(u.name).split(" ")[0].to_upper()
			var size := body.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			overlay.draw_string_outline(body, p + Vector2(-size.x * 0.5, -6), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(0.04, 0.03, 0.05, 0.9))
			overlay.draw_string(body, p + Vector2(-size.x * 0.5, -6), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.INK)
	for f in floaters:
		if camera.is_position_behind(f.pos): continue
		var p := camera.unproject_position(f.pos)
		var alpha := clampf(float(f.life) / 0.4, 0.0, 1.0)
		var col: Color = f.color
		col.a = alpha
		var fs := 22 if str(f.text).length() < 6 else 17
		var size := font.get_string_size(str(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		overlay.draw_string_outline(font, p - Vector2(size.x * 0.5, 0), str(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.04, 0.03, 0.05, alpha * 0.9))
		overlay.draw_string(font, p - Vector2(size.x * 0.5, 0), str(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if str(stage.type) == "Exploration" and int(objective.poi) < 3:
		var target := poi_points[int(objective.poi)]
		var p := camera.unproject_position(Vector3(target.x, 3.0, target.y))
		var label := "OBIETTIVO"
		if float(objective.poi_progress) > 0.0: label += " · %d%%" % roundi(float(objective.poi_progress) / 3.0 * 100.0)
		var size := body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		overlay.draw_string_outline(body, p - Vector2(size.x * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(0.04, 0.03, 0.05, 0.9))
		overlay.draw_string(body, p - Vector2(size.x * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIKit.GOLD)

func _log(message: String, tone: String = "") -> void:
	var color := UIKit.GOLD if tone == "warn" else Color("#e88a8a") if tone == "danger" else Color("#8fd8b0") if tone == "good" else UIKit.INK_SOFT
	var line := UIKit.label("%02d:%02d  %s" % [floori(elapsed / 60.0), floori(elapsed) % 60, message], 14, color, UIKit.body_bold())
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_box.add_child(line)
	log_box.move_child(line, 0)
	while log_box.get_child_count() > 6:
		var last := log_box.get_child(log_box.get_child_count() - 1)
		log_box.remove_child(last)
		last.queue_free()
