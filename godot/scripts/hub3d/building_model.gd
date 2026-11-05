extends Node3D
class_name BuildingModel

## Edificio della base. I livelli 1–3 aggiungono piani; dal Lv.4 al Lv.10
## l'edificio cresce in altri modi (vedi "Crescita oltre il terzo piano"):
## Lv.4 pianterreno di pietra, Lv.5 torretta, Lv.6 seconda torretta, abbaini e
## cresta sul tetto, Lv.7 rune luminose, Lv.8 cristalli sospesi, Lv.9 aureola di
## luce, Lv.10 guglia dorata con un grande cristallo.
## La geometria statica è un'unica mesh con una superficie per materiale; luci,
## fumo e parti animate sono nodi a parte. Il modello guarda verso +Z (ingresso).
## 1 unità = 2 metri.

const FLOOR_H := 1.5
const MAX_STOREYS := 3
const MAX_LEVEL := 10
const GOLD := Color("#d9b45a")
const IRON := Color("#2b2a28")
const RUNE := Color("#7fd2ff")
const PortalShader := preload("res://scripts/hub3d/portal.gdshader")

var facility_id := ""
var level := 1
var floors := 1
var base_level := 1
var top_height := 2.0
var footprint := Vector3(4, 3, 4)
var door_local := Vector3(0, 0, 2.5)
var spots_local: Array[Vector3] = []
var animated: Array[Node3D] = []
var portal_material: ShaderMaterial
var time := 0.0
var b: MeshBuilder
var _mesh: MeshInstance3D
var _highlight: ShaderMaterial
var _extra_meshes: Array[MeshInstance3D] = []
var _seed := 1

func build(id: String, building_level: int, base_lv: int = 1) -> void:
	facility_id = id
	level = clampi(building_level, 0, MAX_LEVEL)
	floors = clampi(level, 1, MAX_STOREYS)
	base_level = base_lv
	_seed = abs(id.hash()) % 1000 + level * 17
	b = _new_builder()
	match id:
		"dormitory": _build_dormitory()
		"training": _build_training()
		"merging": _build_merging()
		"gate": _build_gate()
		"armory": _build_armory()
		"warehouse": _build_warehouse()
		"workshop": _build_workshop()
		"alchemy": _build_alchemy()
		"plot": _build_plot()
		"house": _build_house()
	_mesh = b.instance(self)
	_highlight = WorldMaterials.highlight()
	_mesh.material_overlay = _highlight
	for m in _extra_meshes: m.material_overlay = _highlight
	# le case delle isole sono scenografia: non si cliccano
	if id != "house": _add_pick_body()

func set_highlight(amount: float) -> void:
	if _highlight != null: _highlight.set_shader_parameter("intensity", amount * 3.5)

func _roof_variant() -> String:
	if facility_id in ["armory"]: return "slate"
	if base_level <= 1: return "thatch"
	if base_level == 2: return "shingle"
	return "slate"

func _new_builder() -> MeshBuilder:
	var mb := MeshBuilder.new()
	mb.material("stone", WorldMaterials.stone("wall"))
	mb.material("stone_dark", WorldMaterials.stone("dark"))
	mb.material("pale", WorldMaterials.stone("pale"))
	mb.material("basalt", WorldMaterials.stone("basalt"))
	mb.material("rubble", WorldMaterials.stone("rubble"))
	mb.material("paving", WorldMaterials.stone("paving"))
	mb.material("plaster", WorldMaterials.plaster("warm"))
	mb.material("plaster_white", WorldMaterials.plaster("white"))
	mb.material("plaster_ochre", WorldMaterials.plaster("ochre"))
	mb.material("plaster_grey", WorldMaterials.plaster("grey"))
	mb.material("timber", WorldMaterials.wood("timber"))
	mb.material("planks", WorldMaterials.wood("planks"))
	mb.material("light_wood", WorldMaterials.wood("light"))
	mb.material("weathered", WorldMaterials.wood("weathered"))
	mb.material("roof", WorldMaterials.roof(_roof_variant()))
	mb.material("slate", WorldMaterials.roof("slate"))
	mb.material("copper", WorldMaterials.roof("copper"))
	mb.material("violet_roof", WorldMaterials.roof("violet"))
	mb.material("window", WorldMaterials.window())
	mb.material("glass", WorldMaterials.lit(Color("#1b2230"), 0.25))
	mb.material("metal", WorldMaterials.metal(Color.WHITE, 0.45, 0.7))
	mb.material("cloth", WorldMaterials.lit())
	mb.material("ground", WorldMaterials.terrain())
	return mb

func _glow(color: Color, energy: float = 2.0) -> String:
	var key := "glow_" + color.to_html()
	b.material(key, WorldMaterials.glow(color, energy))
	return key

func _hash(i: int) -> float:
	return fposmod(sin(float(i * 12.9898 + _seed * 78.233)) * 43758.5453, 1.0)

func _process(delta: float) -> void:
	time += delta
	for node in animated:
		if not is_instance_valid(node): continue
		match str(node.get_meta("anim", "")):
			"orbit":
				var r: float = node.get_meta("radius")
				var a: float = float(node.get_meta("offset")) + time * float(node.get_meta("speed", 0.6))
				node.position = Vector3(cos(a) * r, float(node.get_meta("height")) + sin(time * 1.7 + a) * 0.12, sin(a) * r)
				node.rotation.y = time * 1.5
			"spin":
				node.rotation.y = time * float(node.get_meta("speed", 1.0))
			"roll":
				node.rotate_object_local(Vector3.FORWARD, delta * float(node.get_meta("speed", 1.0)))
			"bob":
				node.position.y = float(node.get_meta("height")) + sin(time * 1.4 + float(node.get_meta("offset", 0.0))) * 0.14
				node.rotation.y += delta * 0.4
			"flicker":
				var light: OmniLight3D = node
				light.light_energy = float(node.get_meta("energy")) * (0.85 + 0.15 * sin(time * 9.0) * sin(time * 5.3 + 1.0))
			"pulse":
				var light2: OmniLight3D = node
				light2.light_energy = float(node.get_meta("energy")) * (0.8 + 0.2 * sin(time * 1.6))

func _add_pick_body() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("facility_id", facility_id)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(footprint.x, top_height, footprint.z)
	shape.shape = box
	shape.position = Vector3(0, top_height * 0.5, 0)
	body.add_child(shape)
	add_child(body)

# =============================================================================
# Elementi comuni
# =============================================================================

func _light(pos: Vector3, color: Color, energy: float, radius: float, anim: String = "") -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.light_specular = 0.2
	add_child(light)
	if not anim.is_empty():
		light.set_meta("anim", anim)
		light.set_meta("energy", energy)
		animated.append(light)
	return light

func _smoke(pos: Vector3, amount: int = 10) -> void:
	var smoke := CPUParticles3D.new()
	smoke.position = pos
	smoke.amount = amount
	smoke.lifetime = 4.0
	smoke.direction = Vector3(0.15, 1, 0)
	smoke.spread = 10.0
	smoke.initial_velocity_min = 0.3
	smoke.initial_velocity_max = 0.45
	smoke.gravity = Vector3(0.1, 0.04, 0)
	smoke.scale_amount_min = 0.7
	smoke.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 2.0))
	smoke.scale_amount_curve = curve
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.45, 0.45)
	var m := StandardMaterial3D.new()
	m.albedo_texture = WorldMaterials.soft_texture(48, Color(0.75, 0.72, 0.72, 1.0))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.material = m
	smoke.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.15, Color(1, 1, 1, 0.38))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	smoke.color_ramp = ramp
	add_child(smoke)

## Finestra con cornice, croce, davanzale e (se spenta) scuri chiusi a metà.
func _window(center: Vector3, yaw: float, size: Vector2 = Vector2(0.36, 0.5), lit: bool = true, frame_key: String = "timber", arched: bool = false) -> void:
	b.push_at(center, yaw)
	b.box(frame_key, Vector3(size.x + 0.1, size.y + 0.1, 0.05), Vector3(0, 0, 0.0))
	b.box("window" if lit else "glass", Vector3(size.x, size.y, 0.05), Vector3(0, 0, 0.012))
	b.box(frame_key, Vector3(0.03, size.y, 0.06), Vector3(0, 0, 0.022))
	b.box(frame_key, Vector3(size.x, 0.03, 0.06), Vector3(0, size.y * 0.1, 0.022))
	b.box(frame_key, Vector3(size.x + 0.16, 0.05, 0.12), Vector3(0, -size.y * 0.5 - 0.06, 0.04))
	if arched:
		b.cylinder(frame_key, size.x * 0.5 + 0.05, size.x * 0.5 + 0.05, 0.05, Vector3(0, size.y * 0.5, 0.0), Color.WHITE, 10, Vector3(-PI / 2, 0, 0), true, MeshBuilder.UV.FACE, PI, true, 0.0)
		b.cylinder("window" if lit else "glass", size.x * 0.5, size.x * 0.5, 0.05, Vector3(0, size.y * 0.5, 0.012), Color.WHITE, 10, Vector3(-PI / 2, 0, 0), true, MeshBuilder.UV.FACE, PI, true, 0.0)
	elif not lit:
		for sx in [-1.0, 1.0]:
			b.box("planks", Vector3(size.x * 0.5, size.y + 0.04, 0.03), Vector3(sx * (size.x * 0.75 + 0.06), 0, 0.03), Color(0.85, 0.9, 1.0))
	b.pop()

## Porta di assi con cornice, architrave e gradino.
func _door(center: Vector3, width: float = 0.55, height: float = 1.05, frame_key: String = "timber", arched: bool = false, yaw: float = 0.0) -> void:
	b.push_at(center, yaw)
	b.box(frame_key, Vector3(width + 0.16, height + 0.1, 0.08), Vector3(0, height * 0.5, -0.01))
	b.box("planks", Vector3(width, height, 0.06), Vector3(0, height * 0.5, 0.025), Color(0.9, 0.85, 0.8))
	b.box("metal", Vector3(width * 0.9, 0.035, 0.07), Vector3(0, height * 0.25, 0.035), Color("#3d3a36"))
	b.box("metal", Vector3(width * 0.9, 0.035, 0.07), Vector3(0, height * 0.72, 0.035), Color("#3d3a36"))
	b.sphere("metal", 0.025, Vector3(width * 0.32, height * 0.5, 0.07), Color("#b39a62"), Vector3.ONE, 6, 4)
	if arched:
		b.arch(frame_key, width * 0.5, width * 0.5 + 0.1, 0.1, Vector3(0, height, 0.0), Color.WHITE, Vector3.ZERO, 8)
		b.cylinder("planks", width * 0.5, width * 0.5, 0.06, Vector3(0, height, 0.025), Color(0.9, 0.85, 0.8), 8, Vector3(-PI / 2, 0, 0), true, MeshBuilder.UV.FACE, PI, true, 0.0)
	else:
		b.box(frame_key, Vector3(width + 0.3, 0.1, 0.14), Vector3(0, height + 0.06, 0.02))
	b.box("stone", Vector3(width + 0.4, 0.08, 0.32), Vector3(0, 0.04, 0.16))
	b.pop()

## Lanterna a muro con staffa e piccola luce.
func _wall_lantern(pos: Vector3, yaw: float = 0.0, with_light: bool = true) -> void:
	b.push_at(pos, yaw)
	b.box("metal", Vector3(0.03, 0.03, 0.22), Vector3(0, 0.12, 0.1), Color("#2b2a28"))
	b.box("metal", Vector3(0.12, 0.03, 0.12), Vector3(0, 0.1, 0.2), Color("#2b2a28"))
	b.box(_glow(Color("#ffb35c"), 3.0), Vector3(0.08, 0.12, 0.08), Vector3(0, 0.02, 0.2))
	b.cone("metal", 0.08, 0.08, Vector3(0, 0.15, 0.2), Color("#2b2a28"), 4)
	b.pop()
	if with_light: _light(pos + Vector3(sin(yaw), 0, cos(yaw)) * 0.4, Color("#ffab55"), 1.2, 3.6, "flicker")

## Comignolo in pietra con cappello e fumo.
func _chimney(pos: Vector3, height: float, with_smoke: bool = true) -> void:
	b.box("stone", Vector3(0.38, height, 0.38), pos + Vector3(0, height * 0.5, 0))
	b.box("stone_dark", Vector3(0.46, 0.08, 0.46), pos + Vector3(0, height + 0.04, 0))
	b.box("stone_dark", Vector3(0.2, 0.12, 0.2), pos + Vector3(0, height + 0.14, 0))
	if with_smoke: _smoke(pos + Vector3(0, height + 0.3, 0))

## Telaio a graticcio su una parete (montanti, traversi e diagonali).
func _timber_face(width: float, height: float, y0: float, z: float, yaw: float, braces: bool = true) -> void:
	b.push_at(Vector3.ZERO, yaw)
	var posts := maxi(2, int(width / 1.1) + 1)
	for i in posts:
		var x := -width * 0.5 + width * i / (posts - 1)
		b.box("timber", Vector3(0.1, height, 0.06), Vector3(x, y0 + height * 0.5, z), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("timber", Vector3(width + 0.1, 0.1, 0.07), Vector3(0, y0 + 0.05, z), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("timber", Vector3(width + 0.1, 0.1, 0.07), Vector3(0, y0 + height - 0.05, z), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	if braces:
		for i in posts - 1:
			if i % 2 == 1: continue
			var x0 := -width * 0.5 + width * i / (posts - 1)
			var x1 := -width * 0.5 + width * (i + 1) / (posts - 1)
			var len_d := Vector2(x1 - x0, height * 0.45).length()
			var ang := atan2(height * 0.45, x1 - x0)
			b.box("timber", Vector3(len_d, 0.07, 0.05), Vector3((x0 + x1) * 0.5, y0 + height * 0.28, z), Color.WHITE, Vector3(0, 0, ang if (i / 2) % 2 == 0 else -ang), MeshBuilder.UV.LONG)
	b.pop()

## Piano a graticcio: muri d'intonaco più il telaio di legno sulle quattro facce.
func _timber_storey(w: float, d: float, y0: float, plaster_key: String = "plaster", jetty: float = 0.0) -> void:
	var ww := w + jetty * 2.0
	var dd := d + jetty * 2.0
	b.box(plaster_key, Vector3(ww, FLOOR_H, dd), Vector3(0, y0 + FLOOR_H * 0.5, 0))
	_timber_face(ww, FLOOR_H, y0, dd * 0.5 + 0.03, 0.0)
	_timber_face(ww, FLOOR_H, y0, dd * 0.5 + 0.03, PI)
	_timber_face(dd, FLOOR_H, y0, ww * 0.5 + 0.03, PI / 2, false)
	_timber_face(dd, FLOOR_H, y0, ww * 0.5 + 0.03, -PI / 2, false)
	if jetty > 0.0:
		for i in int(ww / 0.5):
			b.box("timber", Vector3(0.08, 0.08, 0.3), Vector3(-ww * 0.5 + 0.25 + i * 0.5, y0 - 0.02, dd * 0.5 - 0.12), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)

## Tetto a due falde con timpani, trave di colmo e coppi di colmo.
func _roof(w: float, d: float, rise: float, y: float, key: String = "roof", gable_key: String = "plaster", overhang: float = 0.32) -> void:
	b.gable_roof(key, w, d, rise, y, Color.WHITE, overhang, 0.09)
	b.gable_wall(gable_key, d, rise, y, w * 0.5, Color.WHITE, 1.0)
	b.gable_wall(gable_key, d, rise, y, -w * 0.5, Color.WHITE, -1.0)
	b.box("timber", Vector3(w + overhang * 2.0 + 0.06, 0.12, 0.12), Vector3(0, y + rise + 0.06, 0), Color.WHITE, Vector3(PI / 4, 0, 0), MeshBuilder.UV.LONG)
	for sx in [-1.0, 1.0]:
		b.box("timber", Vector3(0.08, 0.1, d + overhang * 2.0), Vector3(sx * (w * 0.5 + overhang), y - 0.02, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)

func _barrel(pos: Vector3, scale: float = 1.0) -> void:
	b.cylinder("planks", 0.16 * scale, 0.16 * scale, 0.42 * scale, pos + Vector3(0, 0.21 * scale, 0), Color(0.9, 0.85, 0.8), 10, Vector3.ZERO, true, MeshBuilder.UV.LONG)
	b.cylinder("planks", 0.185 * scale, 0.185 * scale, 0.2 * scale, pos + Vector3(0, 0.21 * scale, 0), Color(1, 0.95, 0.9), 10, Vector3.ZERO, true, MeshBuilder.UV.LONG)
	for y in [0.07, 0.35]: b.cylinder("metal", 0.17 * scale, 0.17 * scale, 0.03, pos + Vector3(0, y * scale, 0), Color("#3a3632"), 10)

func _crate(pos: Vector3, size: float = 0.36, yaw: float = 0.0) -> void:
	b.push_at(pos, yaw)
	b.box("planks", Vector3(size, size, size), Vector3(0, size * 0.5, 0), Color(1.0, 0.95, 0.85))
	for sx in [-1.0, 1.0]:
		b.box("timber", Vector3(0.04, size, size + 0.01), Vector3(sx * size * 0.48, size * 0.5, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.pop()

func _bench(pos: Vector3, yaw: float = 0.0) -> void:
	b.push_at(pos, yaw)
	b.box("planks", Vector3(0.9, 0.05, 0.24), Vector3(0, 0.23, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	for sx in [-0.36, 0.36]: b.box("timber", Vector3(0.06, 0.22, 0.2), Vector3(sx, 0.11, 0))
	b.pop()

func _woodpile(pos: Vector3, yaw: float = 0.0) -> void:
	b.push_at(pos, yaw)
	for row in 3:
		for i in 4 - row:
			b.cylinder("light_wood", 0.06, 0.06, 0.55, Vector3(-0.19 + i * 0.13 + row * 0.065, 0.06 + row * 0.11, 0), Color(1, 0.95, 0.85), 7, Vector3(PI / 2, 0, 0))
	b.pop()

func _banner(pos: Vector3, color: Color, height: float = 2.2) -> void:
	b.rod("timber", pos, pos + Vector3(0, height, 0), 0.035, 0.03, Color.WHITE, 6)
	b.box("cloth", Vector3(0.4, 0.7, 0.02), pos + Vector3(0.22, height - 0.45, 0), color)
	b.box("metal", Vector3(0.46, 0.03, 0.03), pos + Vector3(0.22, height - 0.08, 0), Color("#b39a62"))
	b.sphere("metal", 0.04, pos + Vector3(0, height + 0.04, 0), Color("#b39a62"), Vector3.ONE, 6, 4)

# =============================================================================
# Crescita oltre il terzo piano (Lv.4–10)
# =============================================================================

## Scudo appeso alla facciata (armeria).
func _shield(pos: Vector3, color: Color) -> void:
	b.push_at(pos)
	b.box("cloth", Vector3(0.36, 0.34, 0.04), Vector3(0, 0.06, 0), color)
	b.box("cloth", Vector3(0.25, 0.25, 0.04), Vector3(0, -0.1, 0), color, Vector3(0, 0, PI / 4))
	b.box("metal", Vector3(0.06, 0.5, 0.05), Vector3(0, 0.0, 0.01), GOLD)
	b.box("metal", Vector3(0.36, 0.05, 0.05), Vector3(0, 0.08, 0.01), GOLD)
	b.sphere("metal", 0.05, Vector3(0, 0.08, 0.03), GOLD, Vector3.ONE, 6, 4)
	b.pop()

## Quadrante d'orologio rivolto verso l'ingresso (torre del Laboratorio).
func _clock(center: Vector3, radius: float) -> void:
	b.cylinder(_glow(Color("#efdcae"), 0.7), radius, radius, 0.06, center, Color.WHITE, 24, Vector3(PI / 2, 0, 0))
	b.torus("metal", radius, 0.035, center + Vector3(0, 0, 0.03), GOLD, Vector3(PI / 2, 0, 0), 24, 4)
	for i in 12:
		var a := TAU * i / 12.0
		b.box("metal", Vector3(0.025, 0.07 if i % 3 == 0 else 0.04, 0.02), center + Vector3(sin(a), cos(a), 0) * (radius - 0.07) + Vector3(0, 0, 0.04), IRON, Vector3(0, 0, -a))
	b.box("metal", Vector3(0.03, radius * 0.6, 0.02), center + Vector3(0.0, radius * 0.27, 0.05), IRON)
	b.box("metal", Vector3(0.03, radius * 0.45, 0.02), center + Vector3(radius * 0.18, -radius * 0.08, 0.055), IRON, Vector3(0, 0, -2.1))

## Piano di pietra con cantonali chiari e marcapiano: dal Lv.4 il pianterreno
## degli edifici a graticcio viene rifatto in muratura.
func _stone_storey(w: float, d: float, y0: float, h: float = FLOOR_H) -> void:
	b.box("stone", Vector3(w, h, d), Vector3(0, y0 + h * 0.5, 0))
	var rows := int(round(h / 0.25))
	var step := h / rows
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for i in rows:
				var long: bool = (i % 2 == 0) == (float(sx) * float(sz) > 0.0)
				var size := Vector3(0.44 if long else 0.26, step - 0.025, 0.26 if long else 0.44)
				b.box("pale", size, Vector3(sx * (w * 0.5 - size.x * 0.5 + 0.03), y0 + step * (i + 0.5), sz * (d * 0.5 - size.z * 0.5 + 0.03)), Color(1.0, 0.98, 0.94))
	b.box("stone_dark", Vector3(w + 0.14, 0.12, d + 0.14), Vector3(0, y0 + h - 0.06, 0))

## Torretta rotonda addossata a un angolo: muro di pietra, cornici, beccatelli,
## finestre ad arco e tetto conico (guglia con anelli d'oro se "spire").
## Le finestre guardano verso "side"; quelle sopra il colmo anche verso l'ingresso.
func _turret(base: Vector3, r: float, top: float, roof_key: String, side: Vector3, ridge_y: float, wall_key: String = "stone", rise: float = 2.2, spire: bool = false) -> Dictionary:
	var flat := Vector3(base.x, 0, base.z)
	var y0 := base.y
	var h := top - y0
	b.cylinder(wall_key, r, r + 0.05, h, flat + Vector3(0, y0 + h * 0.5, 0), Color.WHITE, 16)
	b.cylinder("stone_dark", r + 0.1, r + 0.14, 0.3, flat + Vector3(0, y0 + 0.15, 0), Color.WHITE, 16)
	var rune := _glow(RUNE, 2.2)
	var k := 1
	while y0 + k * FLOOR_H < top - 0.6:
		b.cylinder("stone_dark", r + 0.06, r + 0.06, 0.1, flat + Vector3(0, y0 + k * FLOOR_H, 0), Color.WHITE, 16)
		if level >= 7: b.torus(rune, r + 0.07, 0.026, flat + Vector3(0, y0 + k * FLOOR_H - 0.11, 0), Color.WHITE, Vector3.ZERO, 28, 4)
		k += 1
	# beccatelli sotto la gronda
	b.cylinder("stone_dark", r + 0.18, r + 0.05, 0.3, flat + Vector3(0, top - 0.15, 0), Color.WHITE, 16)
	for i in 14:
		var a := TAU * i / 14.0
		b.box("stone_dark", Vector3(0.1, 0.2, 0.12), flat + Vector3(sin(a), 0, cos(a)) * (r + 0.09) + Vector3(0, top - 0.38, 0), Color.WHITE, Vector3(0, a, 0))
	# finestre ad arco
	var side_yaw := atan2(side.x, side.z)
	var band := 0
	while y0 + (band + 0.55) * FLOOR_H + 0.32 < top - 0.4:
		var hy := y0 + (band + 0.55) * FLOOR_H
		var yaws := [side_yaw]
		if hy > ridge_y - 0.3: yaws.append(0.0)
		for yaw in yaws:
			var dir := Vector3(sin(yaw), 0, cos(yaw))
			_window(flat + dir * (r + 0.03) + Vector3(0, hy, 0), yaw, Vector2(0.24, 0.4), _hash(band * 7 + int(yaw * 10.0) + 3) < 0.8, "stone_dark", true)
		band += 1
	# tetto
	var roof_rise := rise * (1.6 if spire else 1.0)
	b.cone_roof(roof_key, r + 0.3, roof_rise, top, Color.WHITE, 16, flat)
	b.torus("stone_dark", r + 0.27, 0.05, flat + Vector3(0, top + 0.02, 0), Color.WHITE, Vector3.ZERO, 20, 4)
	if spire:
		for i in 3:
			var t := 0.24 + i * 0.22
			b.torus("metal", (r + 0.3) * (1.0 - t) + 0.015, 0.035, flat + Vector3(0, top + roof_rise * t, 0), GOLD, Vector3.ZERO, 20, 4)
	var tip := flat + Vector3(0, top + roof_rise, 0)
	var finial := GOLD if level >= 6 else IRON
	b.rod("metal", tip - Vector3(0, 0.15, 0), tip + Vector3(0, 0.5, 0), 0.035, 0.02, finial, 5)
	b.sphere("metal", 0.075, tip + Vector3(0, 0.53, 0), finial, Vector3.ONE, 8, 5)
	top_height = maxf(top_height, tip.y + 0.62)
	return {"center": flat, "r": r, "top": top, "tip": tip + Vector3(0, 0.62, 0), "side": side}

## Torretta quadrata (armeria, addestramento): stesso ruolo della rotonda, tetto a piramide.
func _square_tower(base: Vector3, half: float, top: float, roof_key: String, side: Vector3, ridge_y: float, wall_key: String = "stone", rise: float = 2.0, spire: bool = false) -> Dictionary:
	var flat := Vector3(base.x, 0, base.z)
	var y0 := base.y
	var h := top - y0
	b.box(wall_key, Vector3(half * 2.0, h, half * 2.0), flat + Vector3(0, y0 + h * 0.5, 0))
	b.box("stone_dark", Vector3(half * 2.0 + 0.2, 0.3, half * 2.0 + 0.2), flat + Vector3(0, y0 + 0.15, 0))
	var rune := _glow(RUNE, 2.2)
	var k := 1
	while y0 + k * FLOOR_H < top - 0.6:
		b.box("stone_dark", Vector3(half * 2.0 + 0.1, 0.1, half * 2.0 + 0.1), flat + Vector3(0, y0 + k * FLOOR_H, 0))
		if level >= 7:
			for yaw in [0.0, PI / 2, PI, -PI / 2]:
				var dir := Vector3(sin(yaw), 0, cos(yaw))
				b.box(rune, Vector3(half * 2.0 + 0.12, 0.035, 0.02), flat + dir * (half + 0.065) + Vector3(0, y0 + k * FLOOR_H - 0.1, 0), Color.WHITE, Vector3(0, yaw, 0))
		k += 1
	# cantonali
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box("pale", Vector3(0.16, h - 0.3, 0.16), flat + Vector3(sx * (half - 0.05), y0 + 0.3 + (h - 0.3) * 0.5, sz * (half - 0.05)), Color(1.0, 0.98, 0.94))
	# beccatelli e gronda
	b.box("stone_dark", Vector3(half * 2.0 + 0.32, 0.26, half * 2.0 + 0.32), flat + Vector3(0, top - 0.13, 0))
	var side_yaw := atan2(side.x, side.z)
	var band := 0
	while y0 + (band + 0.55) * FLOOR_H + 0.32 < top - 0.4:
		var hy := y0 + (band + 0.55) * FLOOR_H
		var yaws := [side_yaw]
		if hy > ridge_y - 0.3: yaws.append(0.0)
		for yaw in yaws:
			var dir := Vector3(sin(yaw), 0, cos(yaw))
			_window(flat + dir * (half + 0.03) + Vector3(0, hy, 0), yaw, Vector2(0.24, 0.4), _hash(band * 5 + int(yaw * 10.0) + 1) < 0.8, "stone_dark", true)
		band += 1
	var roof_rise := rise * (1.6 if spire else 1.0)
	b.push_at(flat, PI / 4)
	b.cone_roof(roof_key, (half + 0.25) * sqrt(2.0), roof_rise, top, Color.WHITE, 4)
	if spire:
		for i in 3:
			var t := 0.24 + i * 0.22
			b.torus("metal", (half + 0.25) * sqrt(2.0) * (1.0 - t) + 0.02, 0.035, Vector3(0, top + roof_rise * t, 0), GOLD, Vector3.ZERO, 4, 4)
	b.pop()
	var tip := flat + Vector3(0, top + roof_rise, 0)
	var finial := GOLD if level >= 6 else IRON
	b.rod("metal", tip - Vector3(0, 0.15, 0), tip + Vector3(0, 0.5, 0), 0.035, 0.02, finial, 5)
	b.sphere("metal", 0.075, tip + Vector3(0, 0.53, 0), finial, Vector3.ONE, 8, 5)
	top_height = maxf(top_height, tip.y + 0.62)
	return {"center": flat, "r": half * 1.15, "half": half, "top": top, "tip": tip + Vector3(0, 0.62, 0), "side": side}

## Cresta di ferro sul colmo, con pinnacoli dorati alle estremità (Lv.6+).
func _cresting(length: float, ridge_y: float, center: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> void:
	b.push_at(center, yaw)
	var y := ridge_y + 0.14
	b.box("metal", Vector3(length, 0.035, 0.035), Vector3(0, y + 0.2, 0), IRON)
	var n := maxi(2, int(length / 0.3))
	for i in n + 1:
		var x := -length * 0.5 + length * i / n
		b.box("metal", Vector3(0.022, 0.22, 0.022), Vector3(x, y + 0.1, 0), IRON)
		if i % 2 == 0: b.cone("metal", 0.04, 0.12, Vector3(x, y + 0.27, 0), IRON, 4)
		else: b.sphere("metal", 0.03, Vector3(x, y + 0.24, 0), IRON, Vector3.ONE, 5, 3)
	for sx in [-1.0, 1.0]:
		b.rod("metal", Vector3(sx * length * 0.5, y - 0.1, 0), Vector3(sx * length * 0.5, y + 0.5, 0), 0.03, 0.02, IRON, 5)
		b.sphere("metal", 0.07, Vector3(sx * length * 0.5, y + 0.55, 0), GOLD, Vector3.ONE, 6, 4)
	b.pop()

## Abbaino sulla falda davanti di un tetto a due falde (Lv.6+).
## roof_y = quota della gronda, rise = altezza del tetto, half_d = metà profondità del tetto.
func _dormer(x: float, roof_y: float, rise: float, half_d: float, wall_key: String = "plaster") -> void:
	var zf := half_d * 0.66
	var yb := roof_y + rise * (1.0 - zf / half_d) - 0.04
	var h := 0.74
	var depth := 1.0
	b.box(wall_key, Vector3(0.82, h, depth), Vector3(x, yb + h * 0.5, zf - depth * 0.5))
	for sx in [-1.0, 1.0]: b.box("timber", Vector3(0.07, h, 0.07), Vector3(x + sx * 0.39, yb + h * 0.5, zf + 0.0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	_window(Vector3(x, yb + h * 0.52, zf + 0.03), 0.0, Vector2(0.32, 0.4), _hash(int(x * 10.0) + 60) < 0.8)
	b.push_at(Vector3(x, 0, zf - depth * 0.5 + 0.06), PI / 2)
	b.gable_roof("roof", depth + 0.12, 0.82, 0.4, yb + h, Color.WHITE, 0.1, 0.06)
	b.gable_wall(wall_key, 0.82, 0.4, yb + h, -(depth + 0.12) * 0.5, Color.WHITE, -1.0)
	b.pop()

## Rune luminose che corrono attorno all'edificio (Lv.7+).
func _rune_band(w: float, d: float, y: float, out: float = 0.05) -> void:
	var key := _glow(RUNE, 2.4)
	for sz in [-1.0, 1.0]: b.box(key, Vector3(w + out * 2.0, 0.05, 0.02), Vector3(0, y, sz * (d * 0.5 + out)))
	for sx in [-1.0, 1.0]: b.box(key, Vector3(0.02, 0.05, d + out * 2.0), Vector3(sx * (w * 0.5 + out), y, 0))

## Pilastrini di rune ai lati della porta e un bagliore che pulsa (Lv.7+).
func _door_runes(center: Vector3, half_width: float, yaw: float = 0.0) -> void:
	var key := _glow(RUNE, 2.6)
	b.push_at(center, yaw)
	for sx in [-1.0, 1.0]:
		b.box("stone_dark", Vector3(0.16, 1.3, 0.1), Vector3(sx * half_width, 0.65, 0.0))
		b.box(key, Vector3(0.04, 0.72, 0.02), Vector3(sx * half_width, 0.62, 0.055))
		b.box(key, Vector3(0.1, 0.1, 0.02), Vector3(sx * half_width, 1.12, 0.055), Color.WHITE, Vector3(0, 0, PI / 4))
	b.pop()
	_light(center + Vector3(sin(yaw), 0, cos(yaw)) * 0.7 + Vector3(0, 0.9, 0), RUNE, 0.8, 3.2, "pulse")

func _crystal_mesh(size: float, color: Color = Color("#7fc0ff")) -> ArrayMesh:
	var sb := MeshBuilder.new()
	sb.material("core", WorldMaterials.glow(color.darkened(0.35), 1.6))
	sb.material("edge", WorldMaterials.glow(color.lightened(0.35), 2.8))
	sb.sphere("core", size, Vector3.ZERO, Color.WHITE, Vector3(0.6, 1.6, 0.6), 6, 2)
	sb.sphere("edge", size * 0.62, Vector3(0, size * 0.25, 0), Color.WHITE, Vector3(0.45, 1.5, 0.45), 6, 2, false, Vector3(0, PI / 6, 0))
	return sb.commit()

## Cristallo del Nexus che fluttua e ruota piano.
func _float_crystal(pos: Vector3, size: float, offset: float, color: Color = Color("#7fc0ff")) -> void:
	var shard := MeshInstance3D.new()
	shard.mesh = _crystal_mesh(size, color)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shard.position = pos
	shard.set_meta("anim", "bob")
	shard.set_meta("height", pos.y)
	shard.set_meta("offset", offset)
	add_child(shard)
	animated.append(shard)
	top_height = maxf(top_height, pos.y + size * 1.7)

## Tre cristalli attorno alla torre principale (Lv.8+), dal lato esterno dell'edificio.
func _crystals(tower: Dictionary, color: Color = Color("#7fc0ff")) -> void:
	var c: Vector3 = tower.center
	var side: Vector3 = tower.side
	var base_yaw := atan2(side.x, side.z)
	for i in 3:
		var yaw := base_yaw + (i - 1) * 1.05
		var pos := c + Vector3(sin(yaw), 0, cos(yaw)) * (float(tower.r) + 1.05) + Vector3(0, float(tower.top) - 0.8 + (0.5 if i == 1 else 0.0), 0)
		_float_crystal(pos, 0.34 if i == 1 else 0.27, i * 2.1, color)

## Aureola: un anello di luce che gira lento attorno al tetto della torre, con
## lucciole in orbita (Lv.9+).
func _halo(tower: Dictionary) -> void:
	var pivot := Node3D.new()
	pivot.position = tower.center + Vector3(0, float(tower.top) + 0.75, 0)
	add_child(pivot)
	var radius := float(tower.r) + 0.62
	var ring := MeshInstance3D.new()
	var rb := MeshBuilder.new()
	rb.material("g", WorldMaterials.glow(Color("#ffe2a0"), 2.8))
	rb.material("r", WorldMaterials.glow(RUNE, 2.4))
	rb.torus("g", radius, 0.03, Vector3.ZERO, Color.WHITE, Vector3.ZERO, 40, 4)
	rb.torus("g", radius - 0.1, 0.012, Vector3.ZERO, Color.WHITE, Vector3.ZERO, 40, 3)
	for i in 10:
		var a := TAU * i / 10.0
		rb.box("r", Vector3(0.05, 0.05, 0.16), Vector3(cos(a), 0, sin(a)) * (radius - 0.05), Color.WHITE, Vector3(0, -a, 0))
	ring.mesh = rb.commit()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_meta("anim", "spin")
	ring.set_meta("speed", 0.3)
	pivot.add_child(ring)
	animated.append(ring)
	for i in 4:
		var mote := MeshInstance3D.new()
		var mb := MeshBuilder.new()
		mb.material("g", WorldMaterials.glow(Color("#fff0c8"), 3.2))
		mb.sphere("g", 0.06, Vector3.ZERO, Color.WHITE, Vector3.ONE, 6, 4)
		mote.mesh = mb.commit()
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mote.set_meta("anim", "orbit")
		mote.set_meta("radius", radius + 0.3)
		mote.set_meta("offset", TAU * i / 4.0)
		mote.set_meta("height", -0.3 + (i % 2) * 0.6)
		mote.set_meta("speed", 0.8)
		pivot.add_child(mote)
		animated.append(mote)

## Corona del Lv.10: un grande cristallo sospeso sopra la guglia, con la sua luce.
func _crown_crystal(tower: Dictionary) -> void:
	var pos: Vector3 = tower.tip + Vector3(0, 0.75, 0)
	var crystal := MeshInstance3D.new()
	crystal.mesh = _crystal_mesh(0.42, Color("#9fd8ff"))
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crystal.position = pos
	crystal.set_meta("anim", "bob")
	crystal.set_meta("height", pos.y)
	add_child(crystal)
	animated.append(crystal)
	_light(pos, Color("#7cc4ff"), 1.6, 6.0, "pulse")
	top_height = maxf(top_height, pos.y + 0.8)

## Torri, cristalli, aureola e corona dal Lv.5 al Lv.10. "bases": piedi delle
## torri (la prima è la principale), "sides": verso dove guardano le finestre.
func _grow_towers(bases: Array, sides: Array, r: float, ridge_y: float, roof_key: String, square: bool = false, wall_key: String = "stone", extra: float = 0.0) -> Dictionary:
	if level < 5: return {}
	var main: Dictionary
	if square: main = _square_tower(bases[0], r, ridge_y + 0.6 + extra, roof_key, sides[0], ridge_y, wall_key, 2.0, level >= 10)
	else: main = _turret(bases[0], r, ridge_y + 0.6 + extra, roof_key, sides[0], ridge_y, wall_key, 2.3, level >= 10)
	if level >= 6 and bases.size() > 1:
		if square: _square_tower(bases[1], r * 0.84, ridge_y - 0.1, roof_key, sides[1], ridge_y, wall_key, 1.7)
		else: _turret(bases[1], r * 0.82, ridge_y - 0.1, roof_key, sides[1], ridge_y, wall_key, 1.9)
	if level >= 8: _crystals(main)
	if level >= 9: _halo(main)
	if level >= 10: _crown_crystal(main)
	return main

# =============================================================================
# Dormitorio: casa lunga a graticcio (circa 5 eroi al Lv.1)
# =============================================================================

func _build_dormitory() -> void:
	var w := 5.8
	var d := 3.6
	var plinth := 0.35
	footprint = Vector3(w + 1.2, 0, d + 2.0)
	b.box("stone", Vector3(w + 0.3, plinth, d + 0.3), Vector3(0, plinth * 0.5, 0))
	var y := plinth
	for f in floors:
		var jetty := 0.12 if f > 0 else 0.0
		var stone := f == 0 and level >= 4
		if stone: _stone_storey(w, d, y)
		else: _timber_storey(w, d, y, "plaster", jetty)
		var frame := "stone_dark" if stone else "timber"
		var count := 3
		for i in count:
			var x := -w * 0.5 + w * (i + 0.5) / count
			if f == 0 and i == 1: continue
			_window(Vector3(x, y + FLOOR_H * 0.55, d * 0.5 + jetty + 0.05), 0.0, Vector2(0.38, 0.52), _hash(f * 10 + i) < 0.7, frame, stone)
			_window(Vector3(x, y + FLOOR_H * 0.55, -d * 0.5 - jetty - 0.05), PI, Vector2(0.38, 0.52), _hash(f * 10 + i + 5) < 0.5, frame, stone)
		_window(Vector3(w * 0.5 + jetty + 0.05, y + FLOOR_H * 0.55, 0), PI / 2, Vector2(0.36, 0.5), _hash(f + 40) < 0.6, frame, stone)
		_window(Vector3(-w * 0.5 - jetty - 0.05, y + FLOOR_H * 0.55, 0), -PI / 2, Vector2(0.36, 0.5), _hash(f + 41) < 0.6, frame, stone)
		y += FLOOR_H
	_door(Vector3(0, plinth, d * 0.5 + 0.04), 0.58, 1.08)
	# tettoia sopra l'ingresso
	b.push_at(Vector3(0, plinth + 1.28, d * 0.5 + 0.35))
	b.gable_roof("roof", 1.0, 0.7, 0.35, 0.0, Color.WHITE, 0.12, 0.06)
	b.pop()
	for sx in [-0.55, 0.55]: b.box("timber", Vector3(0.08, 1.28, 0.08), Vector3(sx, plinth + 0.64, d * 0.5 + 0.62), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	var rise := 1.7
	_roof(w + 0.24, d + 0.24, rise, y, "roof", "plaster")
	_chimney(Vector3(w * 0.28, y + rise * 0.45, -d * 0.18), 1.4)
	if floors >= 3: _chimney(Vector3(-w * 0.3, y + rise * 0.45, -d * 0.18), 1.4, false)
	_wall_lantern(Vector3(0.75, plinth + 1.15, d * 0.5 + 0.05))
	_bench(Vector3(-1.55, 0, d * 0.5 + 0.75))
	_bench(Vector3(1.8, 0, d * 0.5 + 0.75))
	_woodpile(Vector3(w * 0.5 + 0.35, 0, -0.6), PI / 2)
	_barrel(Vector3(w * 0.5 + 0.3, 0, 0.7))
	if base_level >= 3:
		for sx in [-1.95, 1.95]:
			b.box("planks", Vector3(0.5, 0.12, 0.16), Vector3(sx, plinth + 0.55, d * 0.5 + 0.13))
			for k in 4: b.sphere("cloth", 0.05, Vector3(sx - 0.18 + k * 0.12, plinth + 0.64, d * 0.5 + 0.13), [Color("#b8475a"), Color("#d9b04a"), Color("#e8e0d0"), Color("#8b5fbf")][k], Vector3.ONE, 5, 3)
	top_height = y + rise + 0.3
	if level >= 4: _wall_lantern(Vector3(-0.75, plinth + 1.15, d * 0.5 + 0.05), 0.0, false)
	if level >= 6:
		for x in [-w / 3.0, w / 3.0]: _dormer(x, y, rise, (d + 0.24) * 0.5)
		_cresting(w + 0.24, y + rise)
	if level >= 7:
		_rune_band(w, d, plinth + FLOOR_H - 0.2)
		_door_runes(Vector3(0, plinth, d * 0.5 + 0.08), 0.55)
	_grow_towers([Vector3(-w * 0.5 - 0.1, 0.0, -d * 0.5 - 0.1), Vector3(w * 0.5 + 0.1, 0.0, -d * 0.5 - 0.1)], [Vector3(-1, 0, -0.25), Vector3(1, 0, -0.25)], 0.95, y + rise, "roof")
	if level >= 10:
		for sx in [-1.0, 1.0]: _banner(Vector3(sx * (w * 0.5 + 0.45), 0, d * 0.5 + 0.2), Color("#a8822a"), 2.6)
	door_local = Vector3(0, 0, d * 0.5 + 1.0)
	spots_local = [Vector3(-1.75, 0, d * 0.5 + 0.92), Vector3(-1.35, 0, d * 0.5 + 0.92), Vector3(1.6, 0, d * 0.5 + 0.92), Vector3(2.0, 0, d * 0.5 + 0.92)]

# =============================================================================
# Centro di Addestramento: cortile rialzato con manichini
# =============================================================================

func _build_training() -> void:
	var w := 6.8
	var d := 5.4
	var h := 1.0
	footprint = Vector3(w + 0.6, 0, d + 2.4)
	b.box("stone", Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	b.box("stone_dark", Vector3(w + 0.12, 0.1, d + 0.12), Vector3(0, h + 0.05, 0))
	# pavimento di terra battuta
	b.box("ground", Vector3(w - 0.3, 0.02, d - 0.3), Vector3(0, h + 0.1, 0.1), Color(1, 0, 0, 0.9))
	# parapetto basso con pali
	for side in [[Vector3(-w * 0.5 + 0.08, 0, 0), Vector3(0.16, 0.38, d)], [Vector3(w * 0.5 - 0.08, 0, 0), Vector3(0.16, 0.38, d)]]:
		b.box("stone", side[1], side[0] + Vector3(0, h + 0.29, 0))
	b.box("stone", Vector3(w, 0.38, 0.16), Vector3(0, h + 0.29, -d * 0.5 + 0.08))
	for sx in [-1.0, 1.0]:
		b.box("stone", Vector3(w * 0.5 - 1.1, 0.38, 0.16), Vector3(sx * (w * 0.25 + 0.55), h + 0.29, d * 0.5 - 0.08))
	# scalinata frontale
	for i in 5:
		var step_h := h - i * (h / 5.0)
		b.box("stone_dark" if i % 2 == 0 else "stone", Vector3(1.9, step_h, 0.34), Vector3(0, step_h * 0.5, d * 0.5 + 0.17 + i * 0.34))
	# manichini
	var dummies := [Vector3(-1.9, h + 0.1, -0.5), Vector3(0.0, h + 0.1, -1.1), Vector3(1.9, h + 0.1, -0.5)]
	for p in dummies:
		b.rod("timber", p, p + Vector3(0, 1.0, 0), 0.04, 0.035, Color.WHITE, 6)
		b.cylinder("cloth", 0.13, 0.15, 0.42, p + Vector3(0, 0.62, 0), Color("#a88a58"), 8)
		b.sphere("cloth", 0.1, p + Vector3(0, 0.95, 0), Color("#b29462"), Vector3.ONE, 8, 5)
		b.box("timber", Vector3(0.62, 0.05, 0.05), p + Vector3(0, 0.78, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
		b.box("timber", Vector3(0.3, 0.05, 0.3), p + Vector3(0, 0.02, 0))
	# rastrelliere e bersaglio
	for side in [-1.0, 1.0]:
		b.push_at(Vector3(side * (w * 0.5 - 0.45), h + 0.1, 1.2), side * -PI / 2)
		b.box("timber", Vector3(1.1, 0.06, 0.08), Vector3(0, 0.85, 0))
		b.box("timber", Vector3(1.1, 0.06, 0.08), Vector3(0, 0.3, 0))
		for sx in [-0.5, 0.5]: b.box("timber", Vector3(0.07, 0.95, 0.07), Vector3(sx, 0.47, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
		for i in 4:
			b.box("metal", Vector3(0.04, 0.85, 0.012), Vector3(-0.33 + i * 0.22, 0.55, 0.06), Color("#a8adb5"), Vector3(0.1, 0, 0))
			b.box("metal", Vector3(0.12, 0.02, 0.03), Vector3(-0.33 + i * 0.22, 0.15, 0.08), Color("#b39a62"))
		b.pop()
	b.push_at(Vector3(-w * 0.5 + 0.9, h + 0.1, d * 0.5 - 0.9), 0.6)
	for i in 3: b.cylinder("cloth" if i != 1 else "cloth", 0.36 - i * 0.11, 0.36 - i * 0.11, 0.06 + i * 0.012, Vector3(0, 0.75, 0.0), [Color("#d8cdb4"), Color("#9b3b32"), Color("#d8cdb4")][i], 14, Vector3(PI / 2, 0, 0))
	b.rod("timber", Vector3(-0.2, 0, -0.1), Vector3(0, 0.75, -0.06), 0.03, 0.03, Color.WHITE, 5)
	b.rod("timber", Vector3(0.2, 0, -0.1), Vector3(0, 0.75, -0.06), 0.03, 0.03, Color.WHITE, 5)
	b.pop()
	# casermetta sul retro: un piano per livello fino al terzo
	var pw := 4.2
	var pd := 1.7
	var y := h + 0.1
	var hall_z := -d * 0.5 + pd * 0.5 + 0.2
	b.push_at(Vector3(0, 0, hall_z))
	for f in floors:
		var stone := f == 0 and level >= 4
		if stone: _stone_storey(pw, pd, y)
		else: _timber_storey(pw, pd, y, "plaster", 0.0)
		for i in 3:
			if f == 0 and i == 1:
				_door(Vector3(0, y, pd * 0.5 + 0.04), 0.5, 1.0)
				continue
			_window(Vector3(-pw * 0.5 + pw * (i + 0.5) / 3.0, y + FLOOR_H * 0.55, pd * 0.5 + 0.05), 0.0, Vector2(0.34, 0.46), _hash(f * 5 + i) < 0.6, "stone_dark" if stone else "timber", stone)
		y += FLOOR_H
	_roof(pw + 0.2, pd + 0.2, 0.9, y, "roof", "plaster", 0.28)
	if level >= 6: _cresting(pw + 0.2, y + 0.9)
	if level >= 7: _rune_band(pw, pd, h + 0.1 + FLOOR_H - 0.2)
	b.pop()
	var banner_color := Color("#7a2f2f") if base_level < 4 else Color("#8a6a2a")
	for sx in [-1.0, 1.0]: _banner(Vector3(sx * (w * 0.5 - 0.25), h + 0.48, d * 0.5 - 0.3), banner_color, 2.3)
	if base_level >= 2:
		for sx in [-1.0, 1.0]: _wall_lantern(Vector3(sx * 1.1, h + 0.45, d * 0.5 - 0.02), 0.0, sx > 0)
	top_height = maxf(h + 2.9, y + 1.0)
	if level >= 4:
		# parapetto merlato: il cortile diventa una piazza d'armi
		for sx in [-1.0, 1.0]:
			for i in 6:
				b.box("stone", Vector3(0.2, 0.22, 0.32), Vector3(sx * (w * 0.5 - 0.08), h + 0.59, -d * 0.5 + 1.25 + i * 0.72))
			for i in 3:
				b.box("stone", Vector3(0.32, 0.22, 0.2), Vector3(sx * (w * 0.5 - 0.3 - i * 0.62), h + 0.59, d * 0.5 - 0.08))
	if level >= 7:
		# cerchio di rune per i duelli
		var ring := _glow(RUNE, 2.2)
		b.torus(ring, 1.75, 0.035, Vector3(0, h + 0.13, 0.35), Color.WHITE, Vector3.ZERO, 44, 4)
		b.torus(ring, 1.5, 0.018, Vector3(0, h + 0.13, 0.35), Color.WHITE, Vector3.ZERO, 44, 3)
		for i in 8:
			var a := TAU * i / 8.0
			b.box(ring, Vector3(0.05, 0.02, 0.22), Vector3(sin(a), 0, cos(a)) * 1.625 + Vector3(0, h + 0.13, 0.35), Color.WHITE, Vector3(0, a, 0))
	_grow_towers([Vector3(-w * 0.5 + 0.6, 0.0, -d * 0.5 + 0.6), Vector3(w * 0.5 - 0.6, 0.0, -d * 0.5 + 0.6)], [Vector3(-1, 0, -0.2), Vector3(1, 0, -0.2)], 0.72, y + 0.9, "roof", true)
	door_local = Vector3(0, 0, d * 0.5 + 2.1)
	spots_local = []
	for p in dummies: spots_local.append(p + Vector3(0, 0, 0.62))
	spots_local.append(Vector3(-0.85, h + 0.1, 1.1))
	spots_local.append(Vector3(0.85, h + 0.1, 1.1))
	spots_local.append(Vector3(-2.2, h + 0.1, 1.5))
	spots_local.append(Vector3(2.2, h + 0.1, 1.5))
	set_meta("dummies", dummies)

# =============================================================================
# Centro di Fusione: rotonda di pietra chiusa, cupola e luce blu
# =============================================================================

func _build_merging() -> void:
	var r := 2.05
	var plinth := 0.45
	footprint = Vector3(r * 2.0 + 1.6, 0, r * 2.0 + 1.6)
	b.cylinder("pale", r + 0.75, r + 0.85, 0.15, Vector3(0, 0.075, 0), Color.WHITE, 28)
	b.cylinder("pale", r + 0.45, r + 0.55, 0.15, Vector3(0, 0.225, 0), Color.WHITE, 28)
	b.cylinder("pale", r + 0.2, r + 0.25, 0.15, Vector3(0, 0.375, 0), Color.WHITE, 28)
	var blue := Color("#6fb6ff")
	var glow_key := _glow(blue, 2.4)
	var y := plinth
	for f in floors:
		b.cylinder("pale", r, r, FLOOR_H, Vector3(0, y + FLOOR_H * 0.5, 0), Color.WHITE, 24)
		b.cylinder("pale", r + 0.08, r + 0.08, 0.14, Vector3(0, y + FLOOR_H - 0.07, 0), Color(0.9, 0.9, 0.92), 24)
		if level >= 7: b.torus(_glow(RUNE, 2.4), r + 0.1, 0.026, Vector3(0, y + FLOOR_H - 0.2, 0), Color.WHITE, Vector3.ZERO, 40, 4)
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			var dir := Vector3(sin(a), 0, cos(a))
			# colonne addossate
			b.cylinder("pale", 0.1, 0.12, FLOOR_H - 0.14, dir * (r + 0.08) + Vector3(0, y + (FLOOR_H - 0.14) * 0.5, 0), Color(1.02, 1.0, 0.98), 8)
		for i in 8:
			var a := TAU * i / 8.0
			if f == 0 and i == 0: continue
			var dir := Vector3(sin(a), 0, cos(a))
			b.push(Transform3D(Basis(Vector3.UP, a), dir * (r + 0.01) + Vector3(0, y + FLOOR_H * 0.45, 0)))
			b.box(glow_key, Vector3(0.3, 0.62, 0.05), Vector3(0, 0, 0.0))
			b.cylinder(glow_key, 0.15, 0.15, 0.05, Vector3(0, 0.31, 0.0), Color.WHITE, 8, Vector3(-PI / 2, 0, 0), true, MeshBuilder.UV.FACE, PI, true, 0.0)
			b.box("pale", Vector3(0.42, 0.06, 0.12), Vector3(0, -0.34, 0.04))
			b.pop()
		y += FLOOR_H
	# ingresso ad arco con portale luminoso
	b.push_at(Vector3(0, plinth, r - 0.02))
	b.box("pale", Vector3(1.25, 1.55, 0.36), Vector3(0, 0.78, 0.12), Color(1.02, 1.0, 0.97))
	b.box(glow_key, Vector3(0.78, 1.0, 0.06), Vector3(0, 0.5, 0.31))
	b.cylinder(glow_key, 0.39, 0.39, 0.06, Vector3(0, 1.0, 0.31), Color.WHITE, 10, Vector3(-PI / 2, 0, 0), true, MeshBuilder.UV.FACE, PI, true, 0.0)
	b.arch("pale", 0.39, 0.5, 0.4, Vector3(0, 1.0, 0.14), Color(0.96, 0.95, 0.93), Vector3.ZERO, 10)
	b.box("pale", Vector3(1.4, 0.12, 0.42), Vector3(0, 1.62, 0.12))
	b.pop()
	# cupola di rame con lanterna di vetro azzurro (costoloni dorati dal Lv.6)
	b.cylinder("pale", r + 0.12, r + 0.12, 0.22, Vector3(0, y + 0.11, 0), Color(0.95, 0.95, 0.95), 24)
	b.dome("copper", r + 0.02, Vector3(0, y + 0.22, 0), Color.WHITE, 0.92, 24, 8)
	for i in 8:
		var a := TAU * i / 8.0
		b.push(Transform3D(Basis(Vector3.UP, a), Vector3(0, y + 0.22, 0)))
		if level >= 6: b.torus("metal", r + 0.03, 0.045, Vector3.ZERO, GOLD, Vector3(PI / 2, 0, 0), 12, 4, PI * 0.5)
		else: b.torus("pale", r + 0.03, 0.04, Vector3.ZERO, Color(0.95, 0.94, 0.9), Vector3(PI / 2, 0, 0), 12, 4, PI * 0.5)
		b.pop()
	var lantern_y := y + 0.22 + (r + 0.02) * 0.92
	b.cylinder(glow_key, 0.3, 0.3, 0.55, Vector3(0, lantern_y + 0.2, 0), Color.WHITE, 10)
	for i in 6:
		var a := TAU * i / 6.0
		b.box("pale", Vector3(0.06, 0.58, 0.06), Vector3(cos(a) * 0.31, lantern_y + 0.2, sin(a) * 0.31))
	# Lv.10: il cappello della lanterna diventa una guglia d'oro
	var cap := 1.6 if level >= 10 else 0.45
	b.cone("copper", 0.4, cap, Vector3(0, lantern_y + 0.475 + cap * 0.5, 0), Color.WHITE, 10)
	if level >= 10:
		for i in 3:
			var t := 0.22 + i * 0.24
			b.torus("metal", 0.4 * (1.0 - t) + 0.015, 0.03, Vector3(0, lantern_y + 0.475 + cap * t, 0), GOLD, Vector3.ZERO, 16, 4)
	var lantern_tip := lantern_y + 0.475 + cap
	b.sphere("metal", 0.06, Vector3(0, lantern_tip + 0.05, 0), Color("#d4b56a"), Vector3.ONE, 6, 4)
	# Lv.4: peristilio di colonne libere attorno al tamburo di base
	if level >= 4:
		var cr := r + 0.55
		for i in 12:
			var a := TAU * (i + 0.5) / 12.0
			if absf(wrapf(a, -PI, PI)) < 0.4: continue
			var p := Vector3(sin(a), 0, cos(a)) * cr
			b.box("pale", Vector3(0.3, 0.12, 0.3), p + Vector3(0, 0.36, 0), Color(0.96, 0.95, 0.93))
			b.cylinder("pale", 0.11, 0.13, 1.45, p + Vector3(0, 0.3 + 0.12 + 0.725, 0), Color(1.03, 1.01, 0.98), 10)
			b.box("pale", Vector3(0.3, 0.1, 0.3), p + Vector3(0, 1.92, 0), Color(0.96, 0.95, 0.93))
		b.cylinder("pale", cr + 0.2, cr + 0.2, 0.2, Vector3(0, 2.07, 0), Color(0.98, 0.97, 0.95), 28)
		b.cylinder("pale", cr + 0.3, cr + 0.3, 0.08, Vector3(0, 2.21, 0), Color(0.92, 0.91, 0.9), 28)
		if level >= 7: b.torus(_glow(RUNE, 2.4), cr + 0.21, 0.025, Vector3(0, 2.07, 0), Color.WHITE, Vector3.ZERO, 44, 4)
	# Lv.5: pinnacoli con la punta luminosa attorno alla cupola
	if level >= 5:
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			var p := Vector3(sin(a), 0, cos(a)) * (r + 0.1)
			b.box("pale", Vector3(0.3, 0.3, 0.3), p + Vector3(0, y + 0.37, 0))
			b.cylinder("pale", 0.1, 0.15, 1.1, p + Vector3(0, y + 1.07, 0), Color.WHITE, 4, Vector3(0, PI / 4, 0))
			b.cone("pale", 0.13, 0.32, p + Vector3(0, y + 1.78, 0), Color.WHITE, 4, Vector3(0, PI / 4, 0))
			b.sphere(_glow(Color("#9fdcff"), 3.0), 0.07, p + Vector3(0, y + 2.0, 0), Color.WHITE, Vector3.ONE, 6, 4)
	# runa luminosa sul basamento
	var rune_key := _glow(Color("#7cc8ff"), 1.8)
	b.torus(rune_key, r + 0.62, 0.025, Vector3(0, 0.31, 0), Color.WHITE, Vector3.ZERO, 40, 4)
	_light(Vector3(0, 1.2, r + 1.2), Color("#69b4ff"), 2.2, 6.5, "pulse")
	_light(Vector3(0, lantern_y + 0.2, 0), Color("#7cc4ff"), 1.4, 5.0)
	if base_level >= 3:
		for i in 3:
			var shard := MeshInstance3D.new()
			var sb := MeshBuilder.new()
			sb.material("g", WorldMaterials.glow(Color("#a8e4ff"), 3.0))
			sb.sphere("g", 0.11, Vector3.ZERO, Color.WHITE, Vector3(0.7, 1.6, 0.7), 4, 2)
			shard.mesh = sb.commit()
			shard.set_meta("anim", "orbit")
			shard.set_meta("radius", r + 1.0)
			shard.set_meta("offset", TAU * i / 3.0)
			shard.set_meta("height", 1.8 + i * 0.35)
			shard.set_meta("speed", 0.5)
			add_child(shard)
			animated.append(shard)
	top_height = lantern_tip + 0.1
	var dome_tower := {"center": Vector3.ZERO, "r": 0.35, "top": lantern_tip - 0.55, "tip": Vector3(0, lantern_tip + 0.1, 0), "side": Vector3(0, 0, 1)}
	if level >= 8:
		for i in 3:
			var a := TAU * i / 3.0 + 0.5
			_float_crystal(Vector3(sin(a), 0, cos(a)) * (r + 1.0) + Vector3(0, y + 1.3 + (i % 2) * 0.4, 0), 0.3, i * 1.7)
	if level >= 9: _halo(dome_tower)
	if level >= 10: _crown_crystal(dome_tower)
	door_local = Vector3(0, 0, r + 1.35)
	spots_local = [Vector3(-1.1, 0, r + 1.25), Vector3(1.1, 0, r + 1.25), Vector3(-1.9, 0, r + 0.6), Vector3(1.9, 0, r + 0.6)]

# =============================================================================
# Portale delle Missioni: arco monumentale con varco sul Rift
# =============================================================================

func _build_gate() -> void:
	footprint = Vector3(9.0, 0, 5.0)
	var inner := 2.65
	var pillar_x := inner + 0.55
	var spring := 3.4
	b.cylinder("basalt", 3.6, 3.8, 0.3, Vector3(0, 0.15, 0.3), Color.WHITE, 32)
	b.cylinder("paving", 3.2, 3.25, 0.06, Vector3(0, 0.32, 0.3), Color.WHITE, 32)
	var rune := _glow(Color("#9f86ff"), 2.4)
	for sx in [-1.0, 1.0]:
		var px: float = sx * pillar_x
		b.box("basalt", Vector3(1.25, 0.6, 1.4), Vector3(px, 0.6, 0))
		b.box("basalt", Vector3(1.0, spring, 1.15), Vector3(px, 0.9 + spring * 0.5, 0))
		for k in 3:
			b.box("stone_dark", Vector3(1.08, 0.12, 1.22), Vector3(px, 1.5 + k * 1.05, 0))
			b.box(rune, Vector3(0.08, 0.5, 0.02), Vector3(px, 2.0 + k * 1.05, 0.585))
		b.box("basalt", Vector3(1.2, 0.3, 1.3), Vector3(px, 0.9 + spring + 0.15, 0))
	# arco a tutto sesto in conci
	var arch_center := Vector3(0, 0.9 + spring + 0.3, 0)
	var segments := 13
	for i in segments:
		var a0 := PI * i / segments
		var a1 := PI * (i + 1) / segments
		var am := (a0 + a1) * 0.5
		var mid := arch_center + Vector3(cos(am), sin(am), 0) * (pillar_x)
		var length := pillar_x * (a1 - a0) + 0.02
		b.box("basalt", Vector3(1.0, length, 1.1), mid, Color(1, 1, 1) if i % 2 == 0 else Color(0.92, 0.92, 0.95), Vector3(0, 0, am))
	var key_top := arch_center + Vector3(0, pillar_x + 0.55, 0)
	b.box("stone_dark", Vector3(0.7, 0.9, 1.25), key_top)
	b.box(rune, Vector3(0.18, 0.4, 0.02), key_top + Vector3(0, 0, 0.63))
	# varco
	portal_material = ShaderMaterial.new()
	portal_material.shader = PortalShader
	var disc := MeshInstance3D.new()
	disc.mesh = _portal_mesh(inner + 0.12, arch_center.y - 0.36)
	disc.material_override = portal_material
	disc.position = Vector3(0, 0.36, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_light(Vector3(0, 3.6, 1.6), Color("#8a7dff"), 2.6, 10.0, "pulse")
	_light(Vector3(0, 1.2, 2.8), Color("#a9c7ff"), 1.0, 6.0)
	# catene verso gli ancoraggi
	for sx in [-1.0, 1.0]:
		var top := Vector3(sx * (pillar_x + 0.5), 3.9, -0.2)
		var anchor := Vector3(sx * 4.2, 0.35, -1.8)
		var links := 9
		for i in links:
			var t0 := float(i) / links
			var t1 := float(i + 1) / links
			var p0 := top.lerp(anchor, t0) + Vector3(0, -sin(t0 * PI) * 0.35, 0)
			var p1 := top.lerp(anchor, t1) + Vector3(0, -sin(t1 * PI) * 0.35, 0)
			b.rod("metal", p0, p1, 0.045, 0.045, Color("#3a3836"), 5)
		b.box("basalt", Vector3(0.6, 0.5, 0.6), anchor + Vector3(0, 0.0, 0))
	# bracieri
	for sx in [-1.0, 1.0]:
		var base := Vector3(sx * 2.0, 0.33, 2.6)
		b.cylinder("basalt", 0.16, 0.22, 0.75, base + Vector3(0, 0.375, 0), Color.WHITE, 8)
		b.cylinder("metal", 0.3, 0.18, 0.2, base + Vector3(0, 0.85, 0), Color("#2d2b29"), 10)
		b.sphere(_glow(Color("#8fb4ff"), 3.5), 0.15, base + Vector3(0, 0.98, 0), Color.WHITE, Vector3(1.2, 0.8, 1.2), 8, 4)
		_light(base + Vector3(0, 1.3, 0), Color("#8fb4ff"), 1.2, 4.0, "flicker")
	if level >= 2:
		var ring := MeshInstance3D.new()
		var rb := MeshBuilder.new()
		rb.material("g", WorldMaterials.glow(Color("#a99bff"), 2.2))
		rb.material("m", WorldMaterials.metal(Color.WHITE, 0.4, 0.8))
		rb.torus("m", pillar_x + 1.1, 0.07, Vector3.ZERO, Color("#3b3550"), Vector3(PI / 2, 0, 0), 48, 6)
		for i in 12:
			var a := TAU * i / 12.0
			rb.box("g", Vector3(0.14, 0.3, 0.05), Vector3(cos(a), sin(a), 0) * (pillar_x + 1.1), Color.WHITE, Vector3(0, 0, a))
		ring.mesh = rb.commit()
		ring.position = arch_center + Vector3(0, -0.6, -0.65)
		ring.set_meta("anim", "roll")
		ring.set_meta("speed", 0.25)
		add_child(ring)
		animated.append(ring)
		_extra_meshes.append(ring)
	if level >= 3:
		for i in 5:
			var stone := MeshInstance3D.new()
			var sb := MeshBuilder.new()
			sb.material("s", WorldMaterials.stone("basalt"))
			sb.material("g", WorldMaterials.glow(Color("#b9a8ff"), 2.4))
			sb.rock("s", 0.28, Vector3.ZERO, Color.WHITE, Vector3(0.8, 1.4, 0.7), 50 + i, 0.2, false)
			sb.box("g", Vector3(0.05, 0.25, 0.02), Vector3(0, 0, 0.2))
			stone.mesh = sb.commit()
			stone.position = Vector3((i - 2) * 1.5, 0, 2.2 + (i % 2) * 0.6)
			stone.set_meta("anim", "bob")
			stone.set_meta("height", 2.2 + (i % 3) * 0.5)
			stone.set_meta("offset", i * 1.3)
			add_child(stone)
			animated.append(stone)
	top_height = key_top.y + 0.6
	var violet := _glow(Color("#b9a8ff"), 2.6)
	# Lv.4: obelischi con rune ai lati della piattaforma
	if level >= 4:
		for sx in [-1.0, 1.0]:
			var o := Vector3(sx * 3.05, 0.3, 2.15)
			b.box("basalt", Vector3(0.62, 0.3, 0.62), o + Vector3(0, 0.15, 0))
			b.cylinder("basalt", 0.15, 0.25, 2.5, o + Vector3(0, 1.55, 0), Color.WHITE, 4, Vector3(0, PI / 4, 0))
			b.cone("basalt", 0.16, 0.35, o + Vector3(0, 2.97, 0), Color.WHITE, 4, Vector3(0, PI / 4, 0))
			b.box(violet, Vector3(0.06, 1.5, 0.02), o + Vector3(0, 1.45, 0.205))
			b.sphere(violet, 0.08, o + Vector3(0, 3.2, 0), Color.WHITE, Vector3.ONE, 6, 4)
	# Lv.5: secondo anello, più grande, che gira al contrario
	if level >= 5:
		var ring2 := MeshInstance3D.new()
		var rb2 := MeshBuilder.new()
		rb2.material("g", WorldMaterials.glow(Color("#ffd27a"), 2.2))
		rb2.material("m", WorldMaterials.metal(Color.WHITE, 0.4, 0.8))
		rb2.torus("m", pillar_x + 1.75, 0.055, Vector3.ZERO, Color("#5a4a2a"), Vector3(PI / 2, 0, 0), 56, 6)
		for i in 16:
			var a := TAU * i / 16.0
			rb2.box("g", Vector3(0.1, 0.24, 0.05), Vector3(cos(a), sin(a), 0) * (pillar_x + 1.75), Color.WHITE, Vector3(0, 0, a))
		ring2.mesh = rb2.commit()
		ring2.position = arch_center + Vector3(0, -0.6, -0.95)
		ring2.set_meta("anim", "roll")
		ring2.set_meta("speed", -0.15)
		add_child(ring2)
		animated.append(ring2)
		_extra_meshes.append(ring2)
	# Lv.6: due guardiani di pietra incappucciati con il bastone acceso
	if level >= 6:
		for sx in [-1.0, 1.0]:
			var g := Vector3(sx * 1.3, 0.33, 3.15)
			b.box("pale", Vector3(0.6, 0.4, 0.6), g + Vector3(0, 0.2, 0))
			b.cylinder("pale", 0.2, 0.32, 1.2, g + Vector3(0, 1.0, 0), Color(0.97, 0.96, 0.94), 10)
			b.cylinder("pale", 0.17, 0.2, 0.4, g + Vector3(0, 1.75, 0), Color(0.97, 0.96, 0.94), 10)
			b.sphere("pale", 0.17, g + Vector3(0, 2.05, 0.0), Color(0.95, 0.94, 0.92), Vector3(1.0, 1.15, 1.0), 8, 5)
			b.cone("pale", 0.19, 0.32, g + Vector3(0, 2.25, -0.03), Color(0.95, 0.94, 0.92), 8)
			b.sphere("stone_dark", 0.11, g + Vector3(0, 2.03, 0.08), Color(0.6, 0.6, 0.65), Vector3(1.0, 1.1, 0.6), 6, 4)
			b.rod("metal", g + Vector3(-sx * 0.3, 0.4, 0.15), g + Vector3(-sx * 0.3, 2.5, 0.15), 0.03, 0.03, Color("#3a3640"), 5)
			b.sphere(violet, 0.09, g + Vector3(-sx * 0.3, 2.6, 0.15), Color.WHITE, Vector3.ONE, 6, 4)
	# Lv.7: cerchio di rune sulla piattaforma
	if level >= 7:
		var ring_key := _glow(Color("#9f86ff"), 2.2)
		b.torus(ring_key, 3.0, 0.035, Vector3(0, 0.37, 0.3), Color.WHITE, Vector3.ZERO, 56, 4)
		b.torus(ring_key, 2.7, 0.018, Vector3(0, 0.37, 0.3), Color.WHITE, Vector3.ZERO, 56, 3)
		for i in 12:
			var a := TAU * i / 12.0
			b.box(ring_key, Vector3(0.05, 0.02, 0.24), Vector3(sin(a), 0, cos(a)) * 2.85 + Vector3(0, 0.37, 0.3), Color.WHITE, Vector3(0, a, 0))
	# Lv.8: cristalli sospesi ai lati dell'arco
	if level >= 8:
		for i in 4:
			var sx := -1.0 if i < 2 else 1.0
			_float_crystal(Vector3(sx * (pillar_x + 1.0 + (i % 2) * 0.5), 2.6 + (i % 2) * 1.5, 0.6), 0.3 if i % 2 == 0 else 0.24, i * 1.3, Color("#b39cff"))
	var crown := {"center": Vector3(0, 0, 0.0), "r": 0.5, "top": key_top.y + 0.25, "tip": key_top + Vector3(0, 1.35, 0), "side": Vector3(0, 0, 1)}
	if level >= 9: _halo(crown)
	# Lv.10: grande cristallo sopra la chiave di volta e stendardi d'oro sui pilastri
	if level >= 10:
		_crown_crystal(crown)
		for sx in [-1.0, 1.0]:
			b.box("cloth", Vector3(0.62, 2.0, 0.03), Vector3(sx * pillar_x, 2.6, 0.6), Color("#a8822a"))
			b.box("metal", Vector3(0.7, 0.05, 0.05), Vector3(sx * pillar_x, 3.62, 0.6), GOLD)
			b.box(violet, Vector3(0.12, 0.12, 0.02), Vector3(sx * pillar_x, 2.9, 0.62), Color.WHITE, Vector3(0, 0, PI / 4))
	door_local = Vector3(0, 0.33, 2.2)
	spots_local = [Vector3(-1.1, 0.33, 1.4), Vector3(1.1, 0.33, 1.4), Vector3(-0.55, 0.33, 2.1), Vector3(0.55, 0.33, 2.1), Vector3(0.0, 0.33, 0.9)]

## Varco: rettangolo con la parte alta ad arco, UV quadrate per lo shader.
func _portal_mesh(radius: float, straight: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total_h := straight + radius
	var pts: Array[Vector2] = []
	pts.append(Vector2(-radius, 0))
	pts.append(Vector2(radius, 0))
	for i in 17:
		var a := PI * i / 16.0
		pts.append(Vector2(cos(a) * radius, straight + sin(a) * radius))
	var center := Vector2(0, total_h * 0.5)
	var scale := maxf(radius * 2.0, total_h)
	for i in range(0, pts.size() - 1):
		for p in [center, pts[i], pts[i + 1]]:
			var v: Vector2 = p
			st.set_normal(Vector3.BACK)
			st.set_uv(Vector2(0.5 + (v.x - center.x) / scale, 0.5 - (v.y - center.y) / scale))
			st.add_vertex(Vector3(v.x, v.y, 0))
	for p in [center, pts[pts.size() - 1], pts[0]]:
		var v: Vector2 = p
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0.5 + (v.x - center.x) / scale, 0.5 - (v.y - center.y) / scale))
		st.add_vertex(Vector3(v.x, v.y, 0))
	return st.commit()

# =============================================================================
# Strutture sbloccate più avanti
# =============================================================================

func _build_armory() -> void:
	var w := 4.4
	var d := 3.3
	var plinth := 0.3
	footprint = Vector3(w + 2.4, 0, d + 1.8)
	b.box("stone_dark", Vector3(w + 0.3, plinth, d + 0.3), Vector3(0, plinth * 0.5, 0))
	var y := plinth
	for f in floors:
		b.box("stone", Vector3(w, FLOOR_H, d), Vector3(0, y + FLOOR_H * 0.5, 0))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.box("stone_dark", Vector3(0.28, FLOOR_H, 0.28), Vector3(sx * (w * 0.5 - 0.1), y + FLOOR_H * 0.5, sz * (d * 0.5 - 0.1)))
		b.box("stone_dark", Vector3(w + 0.1, 0.12, d + 0.1), Vector3(0, y + FLOOR_H - 0.06, 0))
		for i in 2:
			var x := -1.2 + i * 2.4
			if f == 0 and i == 1: continue
			_window(Vector3(x, y + FLOOR_H * 0.55, d * 0.5 + 0.05), 0.0, Vector2(0.32, 0.5), _hash(f * 3 + i) < 0.75, "stone_dark", true)
		_window(Vector3(w * 0.5 + 0.05, y + FLOOR_H * 0.55, 0), PI / 2, Vector2(0.3, 0.46), _hash(f + 20) < 0.5, "stone_dark", true)
		y += FLOOR_H
	_door(Vector3(1.15, plinth, d * 0.5 + 0.04), 0.72, 1.1, "stone_dark", true)
	_roof(w + 0.1, d + 0.1, 1.4, y, "slate", "stone", 0.25)
	_chimney(Vector3(-w * 0.32, y + 0.2, -d * 0.2), 1.8)
	# Lv.4: scudi con i colori della base sulla facciata, lanterne alla porta
	if level >= 4:
		for f in range(1, floors):
			_shield(Vector3(0.0, plinth + f * FLOOR_H + FLOOR_H * 0.55, d * 0.5 + 0.06), Color("#7a2f2f") if f % 2 == 1 else Color("#2f4a7a"))
		_shield(Vector3(-0.1, plinth + FLOOR_H * 0.6, d * 0.5 + 0.06), Color("#7a2f2f"))
		_wall_lantern(Vector3(0.55, plinth + 1.2, d * 0.5 + 0.05), 0.0, false)
	if level >= 6: _cresting(w + 0.1, y + 1.4)
	if level >= 7:
		_rune_band(w, d, plinth + FLOOR_H - 0.2)
		_door_runes(Vector3(1.15, plinth, d * 0.5 + 0.1), 0.62)
	# forgia sotto una tettoia
	var fx := w * 0.5 + 0.85
	b.push_at(Vector3(fx, 0, 0.5))
	b.box("stone_dark", Vector3(1.0, 0.75, 1.0), Vector3(0, 0.375, 0))
	b.box(_glow(Color("#ff7a2a"), 4.0), Vector3(0.6, 0.08, 0.6), Vector3(0, 0.76, 0))
	b.box("metal", Vector3(0.5, 0.22, 0.24), Vector3(0.0, 0.62, 1.1), Color("#46484d"))
	b.box("metal", Vector3(0.22, 0.4, 0.2), Vector3(0.0, 0.2, 1.1), Color("#36383c"))
	for sx in [-0.65, 0.65]: b.box("timber", Vector3(0.1, 1.9, 0.1), Vector3(sx, 0.95, 1.6), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("timber", Vector3(1.5, 0.1, 0.1), Vector3(0, 1.9, 1.6), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.push(Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0, 2.05, 0.7)))
	b.box("slate", Vector3(1.6, 0.06, 2.2), Vector3.ZERO)
	b.pop()
	b.pop()
	_light(Vector3(fx, 1.2, 0.8), Color("#ff8a3a"), 1.8, 4.5, "flicker")
	_smoke(Vector3(fx, 1.0, 0.5), 6)
	for i in 3: _barrel(Vector3(-w * 0.5 - 0.35, 0, 0.9 - i * 0.42), 0.9)
	b.push_at(Vector3(-0.9, 0, d * 0.5 + 0.35))
	for i in 3: b.box("metal", Vector3(0.04, 0.9, 0.012), Vector3(-0.2 + i * 0.2, 0.5, 0.0), Color("#a8adb5"), Vector3(0.12, 0, 0))
	b.box("timber", Vector3(0.75, 0.06, 0.08), Vector3(0, 0.82, -0.05))
	b.pop()
	top_height = y + 1.6
	_grow_towers([Vector3(-w * 0.5 - 0.05, 0.0, -d * 0.5 - 0.05), Vector3(w * 0.5 + 0.05, 0.0, -d * 0.5 - 0.05)], [Vector3(-1, 0, -0.2), Vector3(1, 0, -0.2)], 0.7, y + 1.4, "slate", true)
	if level >= 10:
		for sx in [-1.0, 1.0]: _banner(Vector3(sx * (w * 0.5 + 0.3), 0, d * 0.5 + 0.35), Color("#a8822a"), 2.6)
	door_local = Vector3(1.15, 0, d * 0.5 + 1.0)
	spots_local = [Vector3(fx, 0, 2.3), Vector3(fx - 0.6, 0, 2.2)]

func _build_warehouse() -> void:
	var w := 5.0
	var d := 3.4
	footprint = Vector3(w + 1.6, 0, d + 1.6)
	b.box("stone", Vector3(w + 0.2, 0.3, d + 0.2), Vector3(0, 0.15, 0))
	var y := 0.3
	for f in floors:
		if f == 0 and level >= 4: _stone_storey(w, d, y)
		else:
			b.box("planks", Vector3(w, FLOOR_H, d), Vector3(0, y + FLOOR_H * 0.5, 0), Color(0.95, 0.9, 0.85))
			_timber_face(w, FLOOR_H, y, d * 0.5 + 0.03, 0.0, false)
			_timber_face(w, FLOOR_H, y, d * 0.5 + 0.03, PI, false)
		if f > 0:
			_window(Vector3(-1.5, y + FLOOR_H * 0.55, d * 0.5 + 0.05), 0.0, Vector2(0.4, 0.45), _hash(f) < 0.5)
			_window(Vector3(1.5, y + FLOOR_H * 0.55, d * 0.5 + 0.05), 0.0, Vector2(0.4, 0.45), _hash(f + 9) < 0.5)
		y += FLOOR_H
	# portone a due ante
	b.box("timber", Vector3(1.7, 1.35, 0.1), Vector3(0, 0.3 + 0.67, d * 0.5 + 0.03))
	for sx in [-1.0, 1.0]:
		b.box("planks", Vector3(0.75, 1.25, 0.06), Vector3(sx * 0.4, 0.3 + 0.63, d * 0.5 + 0.08), Color(0.85, 0.78, 0.7))
		b.box("timber", Vector3(0.95, 0.07, 0.04), Vector3(sx * 0.4, 0.3 + 0.63, d * 0.5 + 0.12), Color.WHITE, Vector3(0, 0, sx * 0.9), MeshBuilder.UV.LONG)
	_roof(w + 0.1, d + 0.1, 1.5, y, "roof", "planks", 0.3)
	b.box("timber", Vector3(0.12, 0.12, 0.9), Vector3(0, y + 0.9, d * 0.5 + 0.55), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("metal", Vector3(0.05, 0.45, 0.05), Vector3(0, y + 0.62, d * 0.5 + 0.95), Color("#3a3836"))
	for i in 5: _crate(Vector3(w * 0.5 + 0.45, (i / 3) * 0.36, -0.9 + (i % 3) * 0.42), 0.36, _hash(i) * 0.4)
	for i in 3: _barrel(Vector3(-w * 0.5 - 0.35, 0, -0.6 + i * 0.42))
	for i in 3: b.sphere("cloth", 0.18, Vector3(-1.4 + i * 0.32, 0.15, d * 0.5 + 0.55), Color("#b9a27a"), Vector3(1.0, 0.8, 0.85), 8, 5)
	top_height = y + 1.7
	if level >= 4:
		for sx in [-1.0, 1.0]: _wall_lantern(Vector3(sx * 1.15, 1.35, d * 0.5 + 0.05), 0.0, sx > 0)
	if level >= 6:
		for x in [-1.6, 1.6]: _dormer(x, y, 1.5, (d + 0.1) * 0.5, "planks")
		_cresting(w + 0.1, y + 1.5)
	if level >= 7:
		_rune_band(w, d, 0.3 + FLOOR_H - 0.2)
		_door_runes(Vector3(0, 0.3, d * 0.5 + 0.1), 1.0)
	# torri del Magazzino: silos rotondi per il grano
	_grow_towers([Vector3(-w * 0.5 - 0.1, 0.0, -d * 0.5 - 0.1), Vector3(w * 0.5 + 0.1, 0.0, -d * 0.5 - 0.1)], [Vector3(-1, 0, -0.2), Vector3(1, 0, -0.2)], 0.9, y + 1.5, "roof")
	if level >= 10:
		for sx in [-1.0, 1.0]: _banner(Vector3(sx * (w * 0.5 + 0.5), 0, d * 0.5 + 0.3), Color("#a8822a"), 2.6)
	door_local = Vector3(0, 0, d * 0.5 + 1.0)

func _build_workshop() -> void:
	var w := 4.2
	var d := 3.1
	footprint = Vector3(w + 2.0, 0, d + 1.6)
	b.box("stone", Vector3(w + 0.3, 0.3, d + 0.3), Vector3(0, 0.15, 0))
	var y := 0.3
	for f in floors:
		var stone := f == 0 and level >= 4
		if stone: _stone_storey(w, d, y)
		else: _timber_storey(w, d, y, "plaster_white", 0.1 if f > 0 else 0.0)
		_window(Vector3(-1.2, y + FLOOR_H * 0.55, d * 0.5 + 0.1), 0.0, Vector2(0.4, 0.5), _hash(f * 2) < 0.7, "stone_dark" if stone else "timber", stone)
		if f > 0: _window(Vector3(1.2, y + FLOOR_H * 0.55, d * 0.5 + 0.1), 0.0, Vector2(0.4, 0.5), _hash(f * 2 + 1) < 0.7)
		y += FLOOR_H
	_door(Vector3(0.9, 0.3, d * 0.5 + 0.04), 0.6, 1.05)
	_roof(w + 0.2, d + 0.2, 1.4, y, "roof", "plaster_white")
	_chimney(Vector3(-w * 0.3, y + 0.5, -d * 0.15), 1.1)
	# grande ruota dentata sul fianco
	var gear := MeshInstance3D.new()
	var gb := MeshBuilder.new()
	gb.material("m", WorldMaterials.metal(Color.WHITE, 0.5, 0.7))
	gb.material("w", WorldMaterials.wood("timber"))
	gb.torus("m", 0.48, 0.06, Vector3.ZERO, Color("#8a6a3a"), Vector3(0, 0, PI / 2), 24, 6)
	for i in 10:
		var a := TAU * i / 10.0
		gb.box("m", Vector3(0.06, 0.14, 0.12), Vector3(0, cos(a), sin(a)) * 0.58, Color("#8a6a3a"), Vector3(a, 0, 0))
	for i in 4:
		var a := TAU * i / 4.0
		gb.box("w", Vector3(0.05, 0.9, 0.06), Vector3.ZERO, Color.WHITE, Vector3(a, 0, 0))
	gear.mesh = gb.commit()
	gear.position = Vector3(w * 0.5 + 0.12, 0.3 + FLOOR_H * 0.75, 0.2)
	gear.set_meta("anim", "roll")
	gear.set_meta("speed", 0.5)
	add_child(gear)
	animated.append(gear)
	_extra_meshes.append(gear)
	# banco da lavoro e cavalletti
	b.push_at(Vector3(-w * 0.5 - 0.6, 0, 0.6), PI / 2)
	b.box("planks", Vector3(1.3, 0.07, 0.5), Vector3(0, 0.5, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	for sx in [-0.55, 0.55]: b.box("timber", Vector3(0.07, 0.5, 0.42), Vector3(sx, 0.25, 0))
	b.box("metal", Vector3(0.25, 0.04, 0.04), Vector3(0.2, 0.56, 0.1), Color("#5a5c60"))
	b.pop()
	for i in 4:
		b.cylinder("light_wood", 0.08, 0.08, 1.4, Vector3(0.2, 0.08 + (i % 2) * 0.15, d * 0.5 + 0.6 + (i / 2) * 0.16), Color(1, 0.95, 0.85), 7, Vector3(0, 0, PI / 2), true, MeshBuilder.UV.LONG)
	top_height = y + 1.6
	if level >= 4: _wall_lantern(Vector3(0.35, 1.45, d * 0.5 + 0.05), 0.0, false)
	if level >= 6: _cresting(w + 0.2, y + 1.4)
	if level >= 7:
		_rune_band(w, d, 0.3 + FLOOR_H - 0.2)
		_door_runes(Vector3(0.9, 0.3, d * 0.5 + 0.1), 0.5)
	# torre dell'orologio (Lv.5) e torretta degli ingranaggi (Lv.6)
	var clock_tower := _grow_towers([Vector3(-w * 0.5 - 0.05, 0.0, -d * 0.5 - 0.05), Vector3(w * 0.5 + 0.05, 0.0, -d * 0.5 - 0.05)], [Vector3(-1, 0, -0.2), Vector3(1, 0, -0.2)], 0.66, y + 1.4, "roof", true, "stone", 0.8)
	if not clock_tower.is_empty(): _clock(clock_tower.center + Vector3(0, float(clock_tower.top) - 0.66, float(clock_tower.half) + 0.05), 0.34)
	if level >= 10:
		for sx in [-1.0, 1.0]: _banner(Vector3(sx * (w * 0.5 + 0.5), 0, d * 0.5 + 0.35), Color("#a8822a"), 2.6)
	door_local = Vector3(0.9, 0, d * 0.5 + 1.0)

func _build_alchemy() -> void:
	var r := 1.45
	footprint = Vector3(r * 2.0 + 1.6, 0, r * 2.0 + 1.6)
	b.cylinder("stone_dark", r + 0.25, r + 0.35, 0.35, Vector3(0, 0.175, 0), Color.WHITE, 18)
	var violet := _glow(Color("#b58cff"), 2.2)
	var y := 0.35
	for f in floors:
		b.cylinder("stone", r, r + 0.03, FLOOR_H, Vector3(0, y + FLOOR_H * 0.5, 0), Color.WHITE, 18)
		b.cylinder("stone_dark", r + 0.08, r + 0.08, 0.12, Vector3(0, y + FLOOR_H - 0.06, 0), Color.WHITE, 18)
		if level >= 7: b.torus(_glow(Color("#c9a8ff"), 2.4), r + 0.06, 0.026, Vector3(0, y + FLOOR_H - 0.2, 0), Color.WHITE, Vector3.ZERO, 36, 4)
		for i in 3:
			var a := TAU * i / 3.0 + f * 0.6
			if f == 0 and i == 0: continue
			var dir := Vector3(sin(a), 0, cos(a))
			b.push(Transform3D(Basis(Vector3.UP, a), dir * (r + 0.02) + Vector3(0, y + FLOOR_H * 0.5, 0)))
			b.box(violet if _hash(f * 3 + i) < 0.7 else "glass", Vector3(0.26, 0.5, 0.05), Vector3.ZERO)
			b.cylinder(violet if _hash(f * 3 + i) < 0.7 else "glass", 0.13, 0.13, 0.05, Vector3(0, 0.25, 0), Color.WHITE, 8, Vector3(-PI / 2, 0, 0), true, MeshBuilder.UV.FACE, PI, true, 0.0)
			b.box("stone_dark", Vector3(0.36, 0.05, 0.12), Vector3(0, -0.28, 0.04))
			b.pop()
		y += FLOOR_H
	_door(Vector3(0, 0.35, r - 0.02), 0.55, 1.0, "stone_dark", true)
	# tetto conico; al Lv.10 diventa una guglia con anelli d'oro
	var rise := 3.5 if level >= 10 else 2.2
	b.cone_roof("violet_roof", r + 0.35, rise, y, Color.WHITE, 18)
	if level >= 10:
		for i in 3:
			var t := 0.22 + i * 0.22
			b.torus("metal", (r + 0.35) * (1.0 - t) + 0.015, 0.035, Vector3(0, y + rise * t, 0), GOLD, Vector3.ZERO, 22, 4)
	b.sphere(_glow(Color("#d8b8ff"), 3.0), 0.12, Vector3(0, y + rise + 0.1, 0), Color.WHITE, Vector3(1, 1.4, 1), 6, 4)
	# Lv.4: contrafforti alla base e un ballatoio di legno sotto l'ultimo piano
	if level >= 4:
		for i in 3:
			var a := TAU * i / 3.0 + PI / 3.0
			b.push_at(Vector3(sin(a), 0, cos(a)) * (r + 0.12), a)
			b.box("stone_dark", Vector3(0.34, 1.3, 0.5), Vector3(0, 0.65, 0.1))
			b.box("stone_dark", Vector3(0.26, 0.9, 0.32), Vector3(0, 1.75, 0.02))
			b.box("stone_dark", Vector3(0.26, 0.42, 0.3), Vector3(0, 2.25, -0.05), Color.WHITE, Vector3(0.5, 0, 0))
			b.pop()
		var by := 0.35 + FLOOR_H * (floors - 1)
		b.cylinder("planks", r + 0.5, r + 0.5, 0.08, Vector3(0, by, 0), Color(0.95, 0.9, 0.85), 22)
		for i in 16:
			var a := TAU * i / 16.0
			b.box("timber", Vector3(0.05, 0.45, 0.05), Vector3(sin(a), 0, cos(a)) * (r + 0.46) + Vector3(0, by + 0.26, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
			b.box("timber", Vector3(0.06, 0.06, 0.4), Vector3(sin(a), 0, cos(a)) * (r + 0.25) + Vector3(0, by - 0.1, 0), Color.WHITE, Vector3(0, a, 0), MeshBuilder.UV.LONG)
		b.torus("timber", r + 0.46, 0.03, Vector3(0, by + 0.48, 0), Color.WHITE, Vector3.ZERO, 22, 4)
	# calderone fumante
	var cx := Vector3(r + 0.7, 0, 0.9)
	b.sphere("metal", 0.36, cx + Vector3(0, 0.34, 0), Color("#2f2e33"), Vector3(1, 0.78, 1), 12, 6)
	b.cylinder(_glow(Color("#59e29a"), 2.6), 0.3, 0.3, 0.03, cx + Vector3(0, 0.6, 0), Color.WHITE, 12)
	for i in 3:
		var a := TAU * i / 3.0
		b.rod("metal", cx + Vector3(cos(a) * 0.3, 0, sin(a) * 0.3), cx + Vector3(cos(a) * 0.24, 0.3, sin(a) * 0.24), 0.025, 0.025, Color("#2f2e33"), 4)
	_light(cx + Vector3(0, 1.0, 0), Color("#59e29a"), 1.4, 3.6, "flicker")
	_smoke(cx + Vector3(0, 0.7, 0), 6)
	_light(Vector3(0, 1.4, r + 0.8), Color("#b58cff"), 1.0, 4.0)
	top_height = y + rise + 0.3
	# Lv.5–6: torrette addossate con il loro tetto viola
	if level >= 5:
		var sides := [-1.0, 1.0] if level >= 6 else [-1.0]
		for sx in sides:
			var a: float = sx * 1.95
			var dir := Vector3(sin(a), 0, cos(a))
			_turret(dir * (r + 0.42), 0.6, y - 0.4, "violet_roof", dir, y + 9.0, "stone", 1.7)
	if level >= 7: _door_runes(Vector3(0, 0.35, r + 0.12), 0.48)
	var tower := {"center": Vector3.ZERO, "r": r, "top": y + 0.5, "tip": Vector3(0, y + rise + 0.25, 0), "side": Vector3(0, 0, 1)}
	if level >= 8: _crystals(tower, Color("#c9a8ff"))
	if level >= 9: _halo(tower)
	if level >= 10: _crown_crystal(tower)
	door_local = Vector3(0, 0, r + 1.0)

## Casa del villaggio sulle isole: uno o due piani, intonaco e misure che
## cambiano con "level" usato come variante (0-9). Porta verso +Z.
func _build_house() -> void:
	var v := level
	var w := 2.7 + float(v % 3) * 0.3
	var d := 2.2 + float((v / 3) % 2) * 0.3
	var storeys := 1 + (v % 2)
	var plinth := 0.25
	var plaster: String = ["plaster", "plaster_white", "plaster_ochre", "plaster_grey"][v % 4]
	footprint = Vector3(w + 0.8, 0, d + 1.2)
	b.box("stone", Vector3(w + 0.2, plinth, d + 0.2), Vector3(0, plinth * 0.5, 0))
	var y := plinth
	for f in storeys:
		var stone := f == 0 and v % 3 == 2
		if stone: _stone_storey(w, d, y)
		else: _timber_storey(w, d, y, plaster, 0.1 if f > 0 else 0.0)
		var jetty := 0.1 if f > 0 else 0.0
		var frame := "stone_dark" if stone else "timber"
		_window(Vector3(w * 0.22, y + FLOOR_H * 0.55, d * 0.5 + jetty + 0.05), 0.0, Vector2(0.34, 0.46), _hash(f * 3 + 1) < 0.75, frame, stone)
		if f > 0: _window(Vector3(-w * 0.22, y + FLOOR_H * 0.55, d * 0.5 + jetty + 0.05), 0.0, Vector2(0.34, 0.46), _hash(f * 3 + 2) < 0.75, frame, stone)
		_window(Vector3(w * 0.5 + jetty + 0.05, y + FLOOR_H * 0.55, 0), PI / 2, Vector2(0.32, 0.44), _hash(f * 3 + 3) < 0.5, frame, stone)
		_window(Vector3(-w * 0.5 - jetty - 0.05, y + FLOOR_H * 0.55, 0), -PI / 2, Vector2(0.32, 0.44), _hash(f * 3 + 4) < 0.5, frame, stone)
		y += FLOOR_H
	_door(Vector3(-w * 0.22, plinth, d * 0.5 + 0.04), 0.5, 1.0)
	var rise := 1.15 + 0.1 * float(v % 2)
	_roof(w + 0.2, d + 0.2, rise, y, "roof", plaster, 0.28)
	_chimney(Vector3(w * 0.3, y + rise * 0.4, -d * 0.15), 0.9, v % 2 == 0)
	# fioriera sotto la finestra e un barile o una panca accanto alla porta
	b.box("planks", Vector3(0.5, 0.12, 0.16), Vector3(w * 0.22, plinth + FLOOR_H * 0.55 - 0.36, d * 0.5 + 0.13))
	for k in 4: b.sphere("cloth", 0.05, Vector3(w * 0.22 - 0.18 + k * 0.12, plinth + FLOOR_H * 0.55 - 0.27, d * 0.5 + 0.13), [Color("#b8475a"), Color("#d9b04a"), Color("#e8e0d0"), Color("#8b5fbf")][(k + v) % 4], Vector3.ONE, 5, 3)
	if v % 2 == 0: _barrel(Vector3(-w * 0.5 - 0.1, 0, d * 0.5 + 0.25), 0.85)
	else: _bench(Vector3(w * 0.22, 0, d * 0.5 + 0.45))
	if base_level >= 2: _wall_lantern(Vector3(-w * 0.22 + 0.45, plinth + 1.1, d * 0.5 + 0.05), 0.0, false)
	top_height = y + rise + 0.2
	door_local = Vector3(-w * 0.22, 0, d * 0.5 + 0.7)

## Cantiere: fondamenta tracciate, ponteggio, pile di legname e pietre.
func _build_plot() -> void:
	footprint = Vector3(4.4, 0, 3.8)
	b.box("ground", Vector3(4.2, 0.02, 3.6), Vector3(0, 0.01, 0), Color(1, 0, 0, 1))
	for side in [[Vector3(0, 0, 1.7), Vector3(4.0, 0.25, 0.25)], [Vector3(0, 0, -1.7), Vector3(4.0, 0.25, 0.25)], [Vector3(1.9, 0, 0), Vector3(0.25, 0.25, 3.2)], [Vector3(-1.9, 0, 0), Vector3(0.25, 0.25, 3.2)]]:
		b.box("rubble", side[1], side[0] + Vector3(0, 0.125, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box("weathered", Vector3(0.1, 2.2, 0.1), Vector3(sx * 1.9, 1.1, sz * 1.7), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("weathered", Vector3(3.9, 0.08, 0.1), Vector3(0, 1.4, 1.7), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("weathered", Vector3(3.9, 0.08, 0.1), Vector3(0, 1.4, -1.7), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("planks", Vector3(3.8, 0.05, 0.4), Vector3(0, 1.45, -1.55), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("weathered", Vector3(0.08, 2.4, 0.08), Vector3(0, 1.0, 1.7), Color.WHITE, Vector3(0, 0, 1.0), MeshBuilder.UV.LONG)
	for i in 5: b.box("light_wood", Vector3(1.6, 0.08, 0.16), Vector3(-0.6, 0.06 + i * 0.085, -0.4 + (i % 2) * 0.05), Color(1, 0.95, 0.85), Vector3(0, 0.05 * i, 0), MeshBuilder.UV.LONG)
	for i in 4: b.box("stone", Vector3(0.4, 0.25, 0.3), Vector3(1.0 + (i % 2) * 0.42, 0.125 + (i / 2) * 0.25, 0.5), Color.WHITE, Vector3(0, 0.1 * i, 0))
	b.push_at(Vector3(1.3, 0, 2.2))
	b.box("weathered", Vector3(0.08, 0.95, 0.08), Vector3(0, 0.47, 0), Color.WHITE, Vector3.ZERO, MeshBuilder.UV.LONG)
	b.box("planks", Vector3(0.75, 0.42, 0.05), Vector3(0, 0.85, 0.05), Color(1.05, 1.0, 0.95))
	b.box(_glow(Color("#e8b94a"), 1.2), Vector3(0.18, 0.18, 0.02), Vector3(0, 0.85, 0.09), Color.WHITE, Vector3(0, 0, PI / 4))
	b.pop()
	top_height = 2.4
	door_local = Vector3(0, 0, 2.3)
