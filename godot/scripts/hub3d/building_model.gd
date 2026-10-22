extends Node3D
class_name BuildingModel

## Edificio procedurale della base. Il livello N corrisponde a N piani (o a una
## crescita architettonica equivalente). Il modello guarda verso +Z (ingresso).

const FLOOR_H := 1.35
const PortalShader := preload("res://scripts/hub3d/portal.gdshader")

const STONE := Color("#c8bfae")
const STONE_DARK := Color("#a39886")
const PLASTER := Color("#fbf1dc")
const TIMBER := Color("#8a5a35")
const WINDOW_WARM := Color("#ffd27a")
const GOLD := Color("#e8b445")

var facility_id := ""
var level := 1
var kit: MeshKit
var top_height := 2.0
var footprint := Vector3(4, 3, 4)
var door_local := Vector3(0, 0, 2.5)
var spots_local: Array[Vector3] = []
var animated: Array[Node3D] = []
var portal_material: ShaderMaterial
var time := 0.0

func build(id: String, building_level: int, base_level: int = 1) -> void:
	facility_id = id
	level = clampi(building_level, 0, 5)
	kit = MeshKit.new(self)
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
	if base_level >= 3 and id in ["dormitory", "armory", "workshop", "warehouse"]:
		_flower_box(Vector3(footprint.x * 0.5 - 0.6, 0.15, footprint.z * 0.5 + 0.35))
	_add_pick_body()

func _process(delta: float) -> void:
	time += delta
	for node in animated:
		var kind := str(node.get_meta("anim", ""))
		match kind:
			"orbit":
				var r: float = node.get_meta("radius")
				var a: float = float(node.get_meta("offset")) + time * 0.8
				node.position = Vector3(cos(a) * r, float(node.get_meta("height")) + sin(time * 2.0 + a) * 0.15, sin(a) * r)
				node.rotation.y = time * 2.0
			"spin":
				node.rotation.y = time * float(node.get_meta("speed", 1.0))
			"roll":
				node.rotate_object_local(Vector3.UP, delta * float(node.get_meta("speed", 1.0)))
			"bob":
				node.position.y = float(node.get_meta("height")) + sin(time * 1.6 + float(node.get_meta("offset", 0.0))) * 0.12
			"flicker":
				var light: OmniLight3D = node
				light.light_energy = float(node.get_meta("energy")) * (0.85 + 0.15 * sin(time * 9.0) * sin(time * 5.3))

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

# -----------------------------------------------------------------------------
# Elementi comuni
# -----------------------------------------------------------------------------

func _gable_roof(width: float, depth: float, height: float, y: float, color: Color, overhang: float = 0.35) -> void:
	# PrismMesh: triangolo nel piano XY estruso lungo Z. Ruotato per avere il colmo lungo X.
	kit.prism(Vector3(depth + overhang * 2.0, height, width + overhang * 2.0), color, Vector3(0, y + height * 0.5, 0), Vector3(0, PI / 2, 0))
	kit.box(Vector3(width + overhang * 2.0 + 0.1, 0.12, 0.16), color.darkened(0.25), Vector3(0, y + height - 0.02, 0))

func _window(pos: Vector3, rot_y: float = 0.0, size := Vector2(0.42, 0.5), color: Color = WINDOW_WARM, glow: float = 0.6) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot_y
	add_child(holder)
	kit.box(Vector3(size.x + 0.12, size.y + 0.12, 0.06), TIMBER, Vector3(0, 0, 0.0), Vector3.ZERO, 0.0, holder)
	kit.box(Vector3(size.x, size.y, 0.07), color, Vector3(0, 0, 0.012), Vector3.ZERO, glow, holder)
	kit.box(Vector3(0.04, size.y, 0.08), TIMBER, Vector3(0, 0, 0.02), Vector3.ZERO, 0.0, holder)
	kit.box(Vector3(size.x + 0.2, 0.06, 0.16), TIMBER.lightened(0.1), Vector3(0, -size.y * 0.5 - 0.06, 0.05), Vector3.ZERO, 0.0, holder)

func _door(pos: Vector3, color: Color = Color("#7a4a2c"), width: float = 0.7, height: float = 1.05) -> void:
	kit.box(Vector3(width + 0.16, height + 0.1, 0.08), TIMBER.darkened(0.2), pos + Vector3(0, 0, -0.01))
	kit.box(Vector3(width, height, 0.1), color, pos)
	kit.sphere(0.04, GOLD, pos + Vector3(width * 0.3, 0, 0.06), Vector3.ONE, 6, 0.3)

func _lantern(pos: Vector3, color: Color = Color("#ffcf6b")) -> void:
	kit.cyl(0.03, 0.03, 0.9, Color("#4e3a2c"), pos + Vector3(0, 0.45, 0), 6)
	kit.box(Vector3(0.2, 0.24, 0.2), Color("#4e3a2c"), pos + Vector3(0, 0.98, 0))
	kit.sphere(0.08, color, pos + Vector3(0, 0.98, 0), Vector3.ONE, 8, 2.5)

func _flower_box(pos: Vector3) -> void:
	kit.box(Vector3(0.9, 0.22, 0.3), TIMBER, pos)
	var colors := [Color("#ff6f91"), Color("#ffd166"), Color("#ffffff"), Color("#c77dff")]
	for i in 4: kit.sphere(0.09, colors[i], pos + Vector3(-0.3 + i * 0.2, 0.16, 0), Vector3.ONE, 6)

func _chimney_smoke(pos: Vector3) -> void:
	var smoke := CPUParticles3D.new()
	smoke.position = pos
	smoke.amount = 10
	smoke.lifetime = 3.0
	smoke.direction = Vector3(0.2, 1, 0)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.35
	smoke.initial_velocity_max = 0.55
	smoke.gravity = Vector3(0.12, 0.05, 0)
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4)); curve.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = curve
	var mesh := SphereMesh.new(); mesh.radius = 0.16; mesh.height = 0.32; mesh.radial_segments = 6; mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	smoke.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.55)); ramp.set_color(1, Color(1, 1, 1, 0.0))
	smoke.color_ramp = ramp
	m.vertex_color_use_as_albedo = true
	add_child(smoke)

func _glow_light(pos: Vector3, color: Color, energy: float, radius: float, flicker: bool = false) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	add_child(light)
	if flicker:
		light.set_meta("anim", "flicker")
		light.set_meta("energy", energy)
		animated.append(light)

func _timber_frame(width: float, depth: float, y0: float, height: float) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box(Vector3(0.14, height, 0.14), TIMBER, Vector3(sx * width * 0.5, y0 + height * 0.5, sz * depth * 0.5))
	kit.box(Vector3(width + 0.06, 0.12, depth + 0.06), TIMBER, Vector3(0, y0 + height - 0.06, 0))

# -----------------------------------------------------------------------------
# Dormitorio: semplice casetta accogliente (circa 5 eroi al Lv.1)
# -----------------------------------------------------------------------------

func _build_dormitory() -> void:
	var w := 5.0
	var d := 3.4
	footprint = Vector3(w + 0.8, 0, d + 1.4)
	kit.box(Vector3(w + 0.3, 0.3, d + 0.3), STONE, Vector3(0, 0.15, 0))
	var y := 0.3
	for f in level:
		kit.box(Vector3(w, FLOOR_H, d), PLASTER, Vector3(0, y + FLOOR_H * 0.5, 0))
		_timber_frame(w, d, y, FLOOR_H)
		var windows := 2 if f == 0 else 3
		for i in windows:
			var x := -1.6 + i * 3.2 if f == 0 else -1.6 + i * 1.6
			_window(Vector3(x, y + FLOOR_H * 0.55, d * 0.5 + 0.02))
			_window(Vector3(x, y + FLOOR_H * 0.55, -d * 0.5 - 0.02), PI)
		_window(Vector3(w * 0.5 + 0.02, y + FLOOR_H * 0.55, 0), PI / 2)
		_window(Vector3(-w * 0.5 - 0.02, y + FLOOR_H * 0.55, 0), -PI / 2)
		y += FLOOR_H
	_door(Vector3(0, 0.3 + 0.53, d * 0.5 + 0.05))
	kit.box(Vector3(1.3, 0.1, 0.8), STONE_DARK, Vector3(0, 0.05, d * 0.5 + 0.45))
	# Tettoia sopra la porta
	kit.prism(Vector3(1.4, 0.4, 0.7), Color("#e0694a"), Vector3(0, 1.55, d * 0.5 + 0.3), Vector3(-PI / 2 + 0.35, 0, 0))
	_gable_roof(w, d, 1.5, y, Color("#e0694a"))
	kit.box(Vector3(0.45, 1.4, 0.45), Color("#b5654a"), Vector3(1.5, y + 1.0, -0.6))
	_chimney_smoke(Vector3(1.5, y + 1.8, -0.6))
	_lantern(Vector3(0.8, 0.0, d * 0.5 + 0.7))
	_flower_box(Vector3(-1.6, 0.3 + 0.18, d * 0.5 + 0.2))
	_flower_box(Vector3(1.6, 0.3 + 0.18, d * 0.5 + 0.2))
	# Panchina davanti all'ingresso
	kit.box(Vector3(1.2, 0.08, 0.35), TIMBER, Vector3(-1.9, 0.42, d * 0.5 + 0.9))
	for sx in [-0.5, 0.5]: kit.box(Vector3(0.08, 0.4, 0.3), TIMBER.darkened(0.2), Vector3(-1.9 + sx, 0.2, d * 0.5 + 0.9))
	top_height = y + 1.6
	door_local = Vector3(0, 0, d * 0.5 + 0.9)
	spots_local = [Vector3(-1.9, 0, d * 0.5 + 1.25), Vector3(-1.5, 0, d * 0.5 + 1.3)]

# -----------------------------------------------------------------------------
# Centro di Addestramento: piattaforma rialzata con manichini
# -----------------------------------------------------------------------------

func _build_training() -> void:
	var r := 3.4 + (0.4 if level >= 4 else 0.0)
	var h := 0.9
	footprint = Vector3(r * 2.0, 0, r * 2.0)
	kit.cyl(r, r + 0.25, h, STONE, Vector3(0, h * 0.5, 0), 20)
	kit.cyl(r + 0.02, r + 0.02, 0.14, STONE_DARK, Vector3(0, h + 0.02, 0), 20)
	kit.cyl(r - 0.25, r - 0.25, 0.12, Color("#e6cc9c"), Vector3(0, h + 0.05, 0), 20)
	kit.cyl(1.0, 1.0, 0.02, Color("#d9b884"), Vector3(0, h + 0.12, 0.4), 16)
	# Scalinata verso la piazza
	for i in 4:
		var step_h := h - i * (h / 4.0)
		kit.box(Vector3(1.8, step_h, 0.42), STONE_DARK if i % 2 == 0 else STONE, Vector3(0, step_h * 0.5, r + 0.05 + i * 0.42))
	# Manichini
	var dummy_positions := [Vector3(-1.4, h + 0.1, -0.6), Vector3(0.0, h + 0.1, -1.3), Vector3(1.4, h + 0.1, -0.6)]
	for p in dummy_positions:
		kit.cyl(0.05, 0.05, 1.0, TIMBER, p + Vector3(0, 0.5, 0), 6)
		kit.cyl(0.16, 0.18, 0.45, Color("#d9b35a"), p + Vector3(0, 0.75, 0), 8)
		kit.sphere(0.14, Color("#e3c070"), p + Vector3(0, 1.12, 0), Vector3.ONE, 8)
		kit.box(Vector3(0.7, 0.06, 0.06), TIMBER, p + Vector3(0, 0.88, 0))
	# Bersaglio e rastrelliera
	var target := Node3D.new(); target.position = Vector3(-2.4, h, 0.9); target.rotation.y = 0.9; add_child(target)
	kit.box(Vector3(0.08, 1.1, 0.08), TIMBER, Vector3(0, 0.55, -0.1), Vector3(0.2, 0, 0), 0.0, target)
	for i in 3:
		var col: Color = [Color("#f4efe4"), Color("#e04848"), Color("#f4efe4")][i]
		kit.cyl(0.42 - i * 0.13, 0.42 - i * 0.13, 0.06 + i * 0.01, col, Vector3(0, 0.95, 0.0), 14, Vector3(PI / 2, 0, 0), 0.0, target)
	var rack := Node3D.new(); rack.position = Vector3(2.5, h, 0.8); rack.rotation.y = -0.9; add_child(rack)
	kit.box(Vector3(1.0, 0.08, 0.1), TIMBER, Vector3(0, 0.9, 0), Vector3.ZERO, 0.0, rack)
	for sx in [-0.45, 0.45]: kit.box(Vector3(0.08, 0.9, 0.08), TIMBER, Vector3(sx, 0.45, 0), Vector3.ZERO, 0.0, rack)
	for i in 3: kit.box(Vector3(0.05, 1.1, 0.05), Color("#dfe4ee"), Vector3(-0.25 + i * 0.25, 0.6, 0.06), Vector3(0.12, 0, 0), 0.0, rack)
	# Stendardi
	for sx in [-1.0, 1.0]:
		var pole := Vector3(sx * (r - 0.4), h, -1.9)
		kit.cyl(0.04, 0.04, 2.6, TIMBER, pole + Vector3(0, 1.3, 0), 6)
		kit.box(Vector3(0.6, 0.9, 0.04), Color("#21a99b") if level < 4 else GOLD, pole + Vector3(sx * -0.32, 2.05, 0))
		kit.sphere(0.07, GOLD, pole + Vector3(0, 2.65, 0), Vector3.ONE, 6, 0.4)
	var top := h + 2.6
	# Dal Lv.2 cresce un padiglione sul retro, un piano per livello
	if level >= 2:
		var pav := Node3D.new(); pav.position = Vector3(0, h, -r + 1.0); add_child(pav)
		var y := 0.0
		for f in level - 1:
			kit.box(Vector3(2.4, FLOOR_H, 1.4), PLASTER, Vector3(0, y + FLOOR_H * 0.5, 0), Vector3.ZERO, 0.0, pav)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]: kit.box(Vector3(0.14, FLOOR_H, 0.14), TIMBER, Vector3(sx * 1.2, y + FLOOR_H * 0.5, sz * 0.7), Vector3.ZERO, 0.0, pav)
			kit.box(Vector3(0.5, 0.55, 0.07), WINDOW_WARM, Vector3(-0.6, y + FLOOR_H * 0.55, 0.71), Vector3.ZERO, 0.5, pav)
			kit.box(Vector3(0.5, 0.55, 0.07), WINDOW_WARM, Vector3(0.6, y + FLOOR_H * 0.55, 0.71), Vector3.ZERO, 0.5, pav)
			y += FLOOR_H
		kit.prism(Vector3(1.9, 1.0, 2.9), Color("#21a99b"), Vector3(0, y + 0.5, 0), Vector3(0, PI / 2, 0), pav)
		top = maxf(top, h + y + 1.0)
		if level >= 5:
			var crystal := kit.sphere(0.3, Color("#7fe7ff"), Vector3(0, y + 1.5, 0), Vector3(1, 1.6, 1), 4, 2.0, pav)
			crystal.set_meta("anim", "spin"); crystal.set_meta("speed", 1.2); animated.append(crystal)
	if level >= 3:
		for p in [Vector3(-r + 0.3, h, 1.8), Vector3(r - 0.3, h, 1.8)]: _lantern(p)
	top_height = top
	door_local = Vector3(0, 0, r + 1.8)
	spots_local = []
	for p in dummy_positions: spots_local.append(p + Vector3(0, 0, 0.75))
	spots_local.append(Vector3(-0.7, h + 0.1, 1.2))
	spots_local.append(Vector3(0.7, h + 0.1, 1.2))
	spots_local.append(Vector3(-1.8, h + 0.1, 1.6))
	spots_local.append(Vector3(1.8, h + 0.1, 1.6))

# -----------------------------------------------------------------------------
# Centro di Fusione: edificio chiuso a cupola con luce blu
# -----------------------------------------------------------------------------

func _build_merging() -> void:
	var r := 2.1
	footprint = Vector3(5.6, 0, 5.6)
	kit.cyl(r + 0.6, r + 0.8, 0.3, Color("#e7e2d6"), Vector3(0, 0.15, 0), 18)
	var rune := kit.torus(r + 0.75, r + 0.9, Color("#7fd8ff"), Vector3(0, 0.31, 0), Vector3.ZERO, 1.6, 32)
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := 0.3
	for f in level:
		kit.cyl(r, r, FLOOR_H, Color("#eef1f8"), Vector3(0, y + FLOOR_H * 0.5, 0), 18)
		for i in 6:
			var a := TAU * i / 6.0 + PI / 6.0
			var holder := Node3D.new(); holder.position = Vector3(sin(a) * (r + 0.01), y + FLOOR_H * 0.55, cos(a) * (r + 0.01)); holder.rotation.y = a; add_child(holder)
			kit.box(Vector3(0.28, 0.62, 0.06), Color("#6fc6ff"), Vector3.ZERO, Vector3.ZERO, 1.4, holder)
		kit.torus(r - 0.02, r + 0.12, GOLD, Vector3(0, y + FLOOR_H, 0), Vector3.ZERO, 0.2, 24)
		y += FLOOR_H
	var dome := kit.dome(r + 0.05, Color("#4d7cf2"), Vector3(0, y, 0), 0.5, 22)
	dome.scale = Vector3(1, 1.15, 1)
	for i in 4:
		var rib := kit.torus(r - 0.02, r + 0.05, GOLD, Vector3(0, y, 0), Vector3(PI / 2, TAU * i / 8.0, 0), 0.2, 24)
		rib.scale = Vector3(1, 1, 1.15)
	kit.cone(0.18, 0.9, GOLD, Vector3(0, y + r * 1.15 + 0.35, 0), 8, 0.3)
	var orb := kit.sphere(0.16, Color("#9be8ff"), Vector3(0, y + r * 1.15 + 0.9, 0), Vector3.ONE, 10, 3.0)
	orb.set_meta("anim", "bob"); orb.set_meta("height", orb.position.y); animated.append(orb)
	# Ingresso ad arco luminoso
	var arch := Node3D.new(); arch.position = Vector3(0, 0.3, r - 0.05); add_child(arch)
	kit.box(Vector3(1.2, 1.5, 0.3), Color("#d9dfeb"), Vector3(0, 0.75, 0.1), Vector3.ZERO, 0.0, arch)
	kit.box(Vector3(0.85, 1.2, 0.32), Color("#5fc0ff"), Vector3(0, 0.62, 0.12), Vector3.ZERO, 2.2, arch)
	kit.cyl(0.6, 0.6, 0.3, Color("#d9dfeb"), Vector3(0, 1.5, 0.1), 12, Vector3(PI / 2, 0, 0), 0.0, arch)
	_glow_light(Vector3(0, 1.4, r + 1.0), Color("#5fb4ff"), 1.6, 6.5)
	_glow_light(Vector3(0, y + 0.6, 0), Color("#7cc4ff"), 1.0, 5.0)
	for i in 3:
		var c := kit.sphere(0.13, Color("#8ff0ff"), Vector3.ZERO, Vector3(1, 1.7, 1), 4, 2.4)
		c.set_meta("anim", "orbit"); c.set_meta("radius", r + 1.2); c.set_meta("offset", TAU * i / 3.0); c.set_meta("height", 1.6 + i * 0.4)
		animated.append(c)
	top_height = y + r * 1.15 + 1.1
	door_local = Vector3(0, 0, r + 1.2)
	spots_local = [Vector3(-1.2, 0, r + 1.3), Vector3(1.2, 0, r + 1.3)]

# -----------------------------------------------------------------------------
# Portale delle Missioni: grande anello sospeso
# -----------------------------------------------------------------------------

func _build_gate() -> void:
	footprint = Vector3(7.4, 0, 4.6)
	kit.cyl(2.6, 2.9, 0.4, STONE, Vector3(0, 0.2, 0.2), 20)
	kit.cyl(2.0, 2.0, 0.08, Color("#e9dfc8"), Vector3(0, 0.42, 0.2), 20)
	var ring_y := 3.25
	for sx in [-1.0, 1.0]:
		kit.box(Vector3(0.7, 5.2, 0.7), STONE, Vector3(sx * 3.15, 2.6, 0))
		kit.box(Vector3(0.9, 0.3, 0.9), GOLD, Vector3(sx * 3.15, 5.3, 0))
		kit.cone(0.42, 0.9, Color("#21a99b"), Vector3(sx * 3.15, 5.9, 0), 4)
		kit.box(Vector3(0.62, 1.6, 0.05), Color("#21a99b"), Vector3(sx * 3.15, 3.8, 0.4))
		kit.box(Vector3(0.62, 0.12, 0.06), GOLD, Vector3(sx * 3.15, 4.6, 0.41))
	kit.torus(2.55, 3.1, Color("#efe6d2"), Vector3(0, ring_y, 0), Vector3(PI / 2, 0, 0), 0.0, 36)
	kit.torus(2.45, 2.62, GOLD, Vector3(0, ring_y, 0.02), Vector3(PI / 2, 0, 0), 0.5, 36)
	for i in 8:
		var a := TAU * i / 8.0
		kit.sphere(0.14, Color("#7fe7ff"), Vector3(cos(a) * 2.83, ring_y + sin(a) * 2.83, 0.28), Vector3.ONE, 6, 2.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(5.0, 5.0)
	portal_material = ShaderMaterial.new()
	portal_material.shader = PortalShader
	var disc := MeshInstance3D.new()
	disc.mesh = quad
	disc.material_override = portal_material
	disc.position = Vector3(0, ring_y, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_glow_light(Vector3(0, ring_y, 1.4), Color("#86b8ff"), 2.2, 9.0)
	if level >= 2:
		var outer := kit.torus(3.4, 3.55, Color("#9be8ff"), Vector3(0, ring_y, -0.2), Vector3(PI / 2, 0, 0), 1.2, 40)
		outer.set_meta("anim", "roll"); outer.set_meta("speed", 0.5); animated.append(outer)
	if level >= 3:
		for i in 4:
			var stone := kit.box(Vector3(0.35, 0.6, 0.2), Color("#c9b8ff"), Vector3((i - 1.5) * 1.6, 0, 1.6), Vector3(0, 0.3 * i, 0), 1.0)
			stone.set_meta("anim", "bob"); stone.set_meta("height", 1.3 + (i % 2) * 0.4); stone.set_meta("offset", i * 1.3); animated.append(stone)
	for sx in [-1.8, 1.8]: _lantern(Vector3(sx, 0.4, 2.2), Color("#9fd8ff"))
	top_height = 6.4
	door_local = Vector3(0, 0.4, 1.9)
	spots_local = [Vector3(-1.0, 0.4, 1.4), Vector3(1.0, 0.4, 1.4), Vector3(-0.5, 0.4, 2.2), Vector3(0.5, 0.4, 2.2), Vector3(0.0, 0.4, 1.0)]

# -----------------------------------------------------------------------------
# Strutture sbloccate più avanti
# -----------------------------------------------------------------------------

func _build_armory() -> void:
	var w := 4.2
	var d := 3.2
	footprint = Vector3(w + 1.4, 0, d + 1.6)
	kit.box(Vector3(w + 0.3, 0.3, d + 0.3), STONE_DARK, Vector3(0, 0.15, 0))
	var y := 0.3
	for f in level:
		kit.box(Vector3(w, FLOOR_H, d), STONE, Vector3(0, y + FLOOR_H * 0.5, 0))
		kit.box(Vector3(w + 0.08, 0.14, d + 0.08), STONE_DARK, Vector3(0, y + FLOOR_H - 0.07, 0))
		_window(Vector3(-1.2, y + FLOOR_H * 0.55, d * 0.5 + 0.02), 0.0, Vector2(0.4, 0.45), Color("#ff9a4a"), 0.9)
		if f > 0: _window(Vector3(1.2, y + FLOOR_H * 0.55, d * 0.5 + 0.02), 0.0, Vector2(0.4, 0.45), Color("#ff9a4a"), 0.9)
		y += FLOOR_H
	_door(Vector3(0.6, 0.85, d * 0.5 + 0.05), Color("#5b3a24"), 1.0, 1.1)
	_gable_roof(w, d, 1.3, y, Color("#5577b8"))
	kit.box(Vector3(0.6, 1.6, 0.6), STONE_DARK, Vector3(-1.4, y + 1.0, -0.5))
	_chimney_smoke(Vector3(-1.4, y + 1.9, -0.5))
	# Forgia all'aperto con incudine
	var forge := Node3D.new(); forge.position = Vector3(w * 0.5 + 0.5, 0, 0.8); add_child(forge)
	kit.box(Vector3(0.9, 0.7, 0.9), STONE_DARK, Vector3(0, 0.35, 0), Vector3.ZERO, 0.0, forge)
	kit.box(Vector3(0.6, 0.12, 0.6), Color("#ff7a2a"), Vector3(0, 0.72, 0), Vector3.ZERO, 3.0, forge)
	kit.box(Vector3(0.5, 0.25, 0.25), Color("#4a4f5c"), Vector3(0.1, 0.55, 1.0), Vector3.ZERO, 0.0, forge)
	kit.box(Vector3(0.25, 0.4, 0.2), Color("#3d414c"), Vector3(0.1, 0.2, 1.0), Vector3.ZERO, 0.0, forge)
	_glow_light(Vector3(w * 0.5 + 0.5, 1.2, 0.8), Color("#ff8a3a"), 1.4, 4.0, true)
	top_height = y + 1.5
	door_local = Vector3(0.6, 0, d * 0.5 + 1.0)
	spots_local = [Vector3(w * 0.5 + 0.6, 0, 2.2)]

func _build_warehouse() -> void:
	var w := 4.6
	var d := 3.2
	footprint = Vector3(w + 1.6, 0, d + 1.4)
	kit.box(Vector3(w + 0.2, 0.25, d + 0.2), STONE, Vector3(0, 0.12, 0))
	var y := 0.25
	for f in level:
		kit.box(Vector3(w, FLOOR_H, d), Color("#c98d55"), Vector3(0, y + FLOOR_H * 0.5, 0))
		for i in 5: kit.box(Vector3(0.06, FLOOR_H, 0.05), Color("#a86f3d"), Vector3(-w * 0.5 + 0.4 + i * (w - 0.8) / 4.0, y + FLOOR_H * 0.5, d * 0.5 + 0.02))
		y += FLOOR_H
	kit.box(Vector3(1.4, 1.2, 0.1), Color("#7a4a2c"), Vector3(0, 0.25 + 0.6, d * 0.5 + 0.05))
	kit.box(Vector3(1.5, 0.08, 0.12), Color("#5b3a24"), Vector3(0, 0.25 + 0.6, d * 0.5 + 0.1), Vector3(0, 0, 0.7))
	_gable_roof(w, d, 1.4, y, Color("#4f9a5a"))
	for i in 4: kit.box(Vector3(0.5, 0.5, 0.5), Color("#b98a52"), Vector3(w * 0.5 + 0.5, 0.25 + (i / 2) * 0.5, -0.6 + (i % 2) * 0.6))
	kit.cyl(0.25, 0.25, 0.6, Color("#9b6a3d"), Vector3(-w * 0.5 - 0.4, 0.3, 0.6), 10)
	top_height = y + 1.5
	door_local = Vector3(0, 0, d * 0.5 + 0.9)

func _build_workshop() -> void:
	var w := 4.0
	var d := 3.0
	footprint = Vector3(w + 1.2, 0, d + 1.4)
	kit.box(Vector3(w + 0.3, 0.3, d + 0.3), STONE, Vector3(0, 0.15, 0))
	var y := 0.3
	for f in level:
		kit.box(Vector3(w, FLOOR_H, d), PLASTER, Vector3(0, y + FLOOR_H * 0.5, 0))
		_timber_frame(w, d, y, FLOOR_H)
		_window(Vector3(-1.1, y + FLOOR_H * 0.55, d * 0.5 + 0.02))
		_window(Vector3(1.1, y + FLOOR_H * 0.55, d * 0.5 + 0.02))
		y += FLOOR_H
	_door(Vector3(0, 0.83, d * 0.5 + 0.05))
	_gable_roof(w, d, 1.3, y, Color("#3aa3a0"))
	var gear := kit.torus(0.35, 0.55, Color("#d9a441"), Vector3(w * 0.5 + 0.05, y - 0.6, 0), Vector3(0, 0, PI / 2), 0.2, 8)
	gear.set_meta("anim", "roll"); gear.set_meta("speed", 0.8); animated.append(gear)
	kit.box(Vector3(1.1, 0.08, 0.6), TIMBER, Vector3(-w * 0.5 - 0.4, 0.8, 0.6))
	for sx in [-0.45, 0.45]: kit.box(Vector3(0.08, 0.8, 0.5), TIMBER, Vector3(-w * 0.5 - 0.4 + sx, 0.4, 0.6))
	top_height = y + 1.4
	door_local = Vector3(0, 0, d * 0.5 + 0.9)

func _build_alchemy() -> void:
	footprint = Vector3(4.4, 0, 4.4)
	kit.cyl(1.9, 2.1, 0.3, STONE, Vector3(0, 0.15, 0), 14)
	var y := 0.3
	for f in level + 1:
		kit.cyl(1.4, 1.5, FLOOR_H, Color("#efe2f7"), Vector3(0, y + FLOOR_H * 0.5, 0), 14)
		_window(Vector3(0, y + FLOOR_H * 0.55, 1.45), 0.0, Vector2(0.36, 0.5), Color("#b48cff"), 1.0)
		y += FLOOR_H
	kit.cone(1.75, 2.0, Color("#8e5bd6"), Vector3(0, y + 1.0, 0), 14)
	kit.sphere(0.14, Color("#c9a3ff"), Vector3(0, y + 2.1, 0), Vector3.ONE, 8, 2.0)
	var cauldron := Node3D.new(); cauldron.position = Vector3(1.8, 0, 1.2); add_child(cauldron)
	kit.sphere(0.4, Color("#3b3946"), Vector3(0, 0.38, 0), Vector3(1, 0.8, 1), 10, 0.0, cauldron)
	kit.cyl(0.32, 0.32, 0.04, Color("#59e29a"), Vector3(0, 0.62, 0), 12, Vector3.ZERO, 2.2, cauldron)
	_glow_light(Vector3(1.8, 1.0, 1.2), Color("#59e29a"), 1.2, 3.5, true)
	top_height = y + 2.3
	door_local = Vector3(0, 0, 2.4)

func _build_plot() -> void:
	footprint = Vector3(4.2, 0, 3.6)
	kit.box(Vector3(4.0, 0.06, 3.4), Color("#d8bf8e"), Vector3(0, 0.03, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box(Vector3(0.14, 1.6, 0.14), TIMBER, Vector3(sx * 1.8, 0.8, sz * 1.5))
	kit.box(Vector3(3.8, 0.1, 0.12), TIMBER, Vector3(0, 1.55, 1.5))
	kit.box(Vector3(3.8, 0.1, 0.12), TIMBER, Vector3(0, 1.55, -1.5))
	kit.box(Vector3(0.1, 1.9, 0.1), TIMBER, Vector3(0, 0.8, 1.5), Vector3(0, 0, 1.0))
	for i in 4: kit.box(Vector3(1.6, 0.08, 0.3), Color("#d9a46a"), Vector3(-0.8, 0.1 + i * 0.09, -0.4 + (i % 2) * 0.05))
	for i in 3: kit.rock(0.22, STONE, Vector3(1.0 + i * 0.25, 0.1, -0.6 + i * 0.3), i + 7)
	var sign := Node3D.new(); sign.position = Vector3(1.2, 0, 1.9); add_child(sign)
	kit.box(Vector3(0.08, 0.9, 0.08), TIMBER, Vector3(0, 0.45, 0), Vector3.ZERO, 0.0, sign)
	kit.box(Vector3(0.8, 0.45, 0.06), Color("#f0d29a"), Vector3(0, 0.85, 0.04), Vector3.ZERO, 0.0, sign)
	kit.box(Vector3(0.3, 0.3, 0.07), Color("#e0a93b"), Vector3(0, 0.85, 0.08), Vector3(0, 0, PI / 4), 0.6, sign)
	top_height = 2.0
	door_local = Vector3(0, 0, 2.2)
