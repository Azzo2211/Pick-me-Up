extends RefCounted
class_name NatureKit

## Alberi, cespugli, ciuffi d'erba e rocce per la base e le missioni.
## Ogni variante è una ArrayMesh costruita una volta e disegnata con MultiMesh.

const CONIFER_GREENS := [Color("#2f4a2a"), Color("#29452f"), Color("#3a4d2b"), Color("#2b4035")]
const LEAF_GREENS := [Color("#5f8a36"), Color("#6c8f3a"), Color("#4f7a38"), Color("#78923f"), Color("#8f8c3c")]

static var _meshes: Dictionary = {}

static func mesh(kind: String, variant: int = 0) -> ArrayMesh:
	var key := "%s_%d" % [kind, variant]
	if _meshes.has(key): return _meshes[key]
	var m: ArrayMesh
	match kind:
		"conifer": m = _conifer(variant)
		"broadleaf": m = _broadleaf(variant)
		"bush": m = _bush(variant)
		"dead": m = _dead_tree(variant)
		"tuft": m = _tuft(variant)
		"rock": m = _rock(variant)
		_: m = _broadleaf(0)
	_meshes[key] = m
	return m

## Altezza indicativa di una variante (per ombre e collisioni).
static func height_of(kind: String) -> float:
	match kind:
		"conifer": return 5.0
		"broadleaf": return 4.2
		"bush": return 0.9
		"dead": return 3.6
	return 1.0

# -----------------------------------------------------------------------------

static func _bark(b: MeshBuilder) -> void:
	b.material("bark", WorldMaterials.wood("bark"))

static func _conifer(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	_bark(b)
	b.material("needles", WorldMaterials.foliage(false))
	var r := RandomNumberGenerator.new()
	r.seed = 7100 + variant
	var height := 4.2 + variant * 0.45
	var trunk_r := 0.13 + variant * 0.015
	b.cylinder("bark", trunk_r * 0.35, trunk_r, height * 0.75, Vector3(0, height * 0.375, 0), Color.WHITE, 7, Vector3.ZERO, false, MeshBuilder.UV.LONG)
	var base_green: Color = CONIFER_GREENS[variant % CONIFER_GREENS.size()]
	var tiers := 6 + variant % 2
	for t in tiers:
		var k := float(t) / tiers
		var y := 0.65 + k * (height - 1.1)
		var radius := lerpf(1.45, 0.32, pow(k, 0.85)) * (0.92 + r.randf() * 0.16)
		var tier_h := lerpf(1.25, 0.75, k)
		_serrated_cone(b, "needles", Vector3(0, y, 0), radius, tier_h, base_green.lightened(0.04 * t), r)
	b.cone("needles", 0.16, 0.6, Vector3(0, height + 0.05, 0), base_green.lightened(0.18), 6)
	return b.commit()

## Strato di rami di conifera: cono con bordo seghettato e punte piegate in giù.
static func _serrated_cone(b: MeshBuilder, key: String, base: Vector3, radius: float, height: float, color: Color, r: RandomNumberGenerator) -> void:
	var points := 14
	var apex := base + Vector3(0, height, 0)
	var ring: Array[Vector3] = []
	var phase := r.randf() * TAU
	for i in points:
		var a := phase + TAU * i / points
		var out := radius * (1.0 if i % 2 == 0 else 0.68) * (0.9 + r.randf() * 0.2)
		var droop := -0.22 * (out / radius) * height
		ring.append(base + Vector3(cos(a) * out, droop, sin(a) * out))
	var inner_dark := color.darkened(0.35)
	inner_dark.a = 0.55
	var tip := color.lightened(0.08)
	tip.a = 1.0
	var top := color.lightened(0.12)
	top.a = 0.95
	for i in points:
		var p0 := ring[i]
		var p1 := ring[(i + 1) % points]
		var n0 := (p0 - base).normalized() + Vector3(0, 0.8, 0)
		var n1 := (p1 - base).normalized() + Vector3(0, 0.8, 0)
		var na := Vector3.UP
		b.tri(key, p0, p1, apex, n0, n1, na, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1), tip if i % 2 == 0 else color, tip if (i + 1) % 2 == 0 else color, top)
		var under := base + Vector3(0, height * 0.18, 0)
		b.tri(key, p1, p0, under, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, inner_dark, inner_dark, inner_dark)

static func _broadleaf(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	_bark(b)
	b.material("leaves", WorldMaterials.foliage(true))
	b.material("crown", WorldMaterials.foliage(false))
	var r := RandomNumberGenerator.new()
	r.seed = 8200 + variant
	var trunk_h := 1.5 + variant * 0.15
	var lean := Vector3(r.randf_range(-0.12, 0.12), 0, r.randf_range(-0.12, 0.12))
	b.cylinder("bark", 0.13, 0.2, trunk_h, Vector3(0, trunk_h * 0.5, 0) + lean * 0.5, Color.WHITE, 8, Vector3(lean.z, 0, -lean.x), false, MeshBuilder.UV.LONG)
	b.cylinder("bark", 0.06, 0.12, 1.4, Vector3(0, trunk_h + 0.5, 0) + lean, Color.WHITE, 6, Vector3(lean.z, 0, -lean.x), false, MeshBuilder.UV.LONG)
	for i in 3:
		var a := TAU * i / 3.0 + r.randf() * 0.8
		var dir := Vector3(cos(a), 0.9, sin(a)).normalized()
		var start := Vector3(0, trunk_h * 0.8, 0) + lean * 0.8
		var length := r.randf_range(0.9, 1.3)
		var mid := start + dir * length * 0.5
		var basis := Basis(Quaternion(Vector3.UP, dir))
		b.cylinder("bark", 0.035, 0.07, length, mid, Color.WHITE, 5, basis.get_euler(), false, MeshBuilder.UV.LONG)
	var green: Color = LEAF_GREENS[variant % LEAF_GREENS.size()]
	var crown_center := Vector3(0, trunk_h + 1.25, 0) + lean
	var dark := green.darkened(0.45)
	dark.a = 0.6
	b.sphere("crown", 1.15, crown_center + Vector3(0, -0.1, 0), dark, Vector3(1.0, 0.82, 1.0), 9, 6)
	var clusters := 9 + variant % 3
	for i in clusters:
		var a := TAU * i / clusters + r.randf() * 0.6
		var elev := r.randf_range(-0.35, 0.9)
		var dist := r.randf_range(0.55, 1.05)
		var offset := Vector3(cos(a) * cos(elev), sin(elev) * 0.8, sin(a) * cos(elev)) * dist
		var size := r.randf_range(1.1, 1.55)
		var tint := green.lerp(LEAF_GREENS[(variant + i) % LEAF_GREENS.size()], 0.35).lightened(clampf(offset.y, -0.3, 0.6) * 0.2)
		_leaf_card_cluster(b, "leaves", crown_center + offset, crown_center, size, tint, r)
	return b.commit()

## Tre quadrati incrociati con texture di foglie; normali "sferiche" dalla chioma.
static func _leaf_card_cluster(b: MeshBuilder, key: String, pos: Vector3, crown: Vector3, size: float, color: Color, r: RandomNumberGenerator) -> void:
	var out := (pos - crown).normalized()
	if out.length() < 0.1: out = Vector3.UP
	var spin := r.randf() * TAU
	for k in 3:
		var basis := Basis(Vector3.UP, spin + k * PI / 3.0) * Basis(Vector3.RIGHT, r.randf_range(-0.5, 0.5))
		var right := basis * Vector3.RIGHT * size * 0.5
		var up := basis * Vector3.UP * size * 0.5
		var c0 := pos - right - up
		var c1 := pos + right - up
		var c2 := pos + right + up
		var c3 := pos - right + up
		var shade := color
		shade.a = clampf(0.75 + out.y * 0.25, 0.4, 1.0)
		var n0 := ((c0 - crown).normalized() + out).normalized()
		var n1 := ((c1 - crown).normalized() + out).normalized()
		var n2 := ((c2 - crown).normalized() + out).normalized()
		var n3 := ((c3 - crown).normalized() + out).normalized()
		b.tri(key, c0, c1, c2, n0, n1, n2, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), shade)
		b.tri(key, c0, c2, c3, n0, n2, n3, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0), shade)

static func _bush(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.material("leaves", WorldMaterials.foliage(true))
	b.material("crown", WorldMaterials.foliage(false))
	var r := RandomNumberGenerator.new()
	r.seed = 9300 + variant
	var green: Color = LEAF_GREENS[(variant + 1) % LEAF_GREENS.size()].darkened(0.1)
	var dark := green.darkened(0.45)
	dark.a = 0.6
	var center := Vector3(0, 0.38, 0)
	b.sphere("crown", 0.42, center + Vector3(0, -0.05, 0), dark, Vector3(1.25, 0.8, 1.1), 8, 5)
	for i in 6:
		var a := TAU * i / 6.0 + r.randf() * 0.5
		var offset := Vector3(cos(a) * 0.35, r.randf_range(0.0, 0.25), sin(a) * 0.35)
		_leaf_card_cluster(b, "leaves", center + offset, center + Vector3(0, -0.3, 0), r.randf_range(0.7, 0.95), green.lightened(r.randf() * 0.1), r)
	return b.commit()

static func _dead_tree(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.material("bark", WorldMaterials.wood("weathered"))
	var r := RandomNumberGenerator.new()
	r.seed = 9900 + variant
	var h := 2.6 + variant * 0.3
	b.cylinder("bark", 0.06, 0.2, h, Vector3(0, h * 0.5, 0), Color.WHITE, 7, Vector3(r.randf_range(-0.08, 0.08), 0, r.randf_range(-0.08, 0.08)), false, MeshBuilder.UV.LONG)
	for i in 5:
		var a := TAU * i / 5.0 + r.randf()
		var dir := Vector3(cos(a), r.randf_range(0.4, 1.1), sin(a)).normalized()
		var start := Vector3(0, h * r.randf_range(0.45, 0.85), 0)
		var length := r.randf_range(0.6, 1.2)
		var basis := Basis(Quaternion(Vector3.UP, dir))
		b.cylinder("bark", 0.015, 0.05, length, start + dir * length * 0.5, Color.WHITE, 5, basis.get_euler(), false, MeshBuilder.UV.LONG)
	return b.commit()

## Ciuffo d'erba: lame triangolari incrociate, scure alla base e chiare in punta.
static func _tuft(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.material("grass", WorldMaterials.foliage(false))
	var r := RandomNumberGenerator.new()
	r.seed = 5100 + variant
	var base_col := Color("#4a6227") if variant % 2 == 0 else Color("#5a6428")
	base_col.a = 0.85
	var tip_col := Color("#a7b65c") if variant % 2 == 0 else Color("#bcb062")
	for i in 7:
		var a := r.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * 0.025
		var root := dir * r.randf_range(0.0, 0.07)
		var height := r.randf_range(0.14, 0.3)
		var tip := root + dir * r.randf_range(0.05, 0.12) + Vector3(0, height, 0)
		# normali verso l'alto: i ciuffi prendono la stessa luce del prato
		b.tri("grass", root - side, root + side, tip, Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, base_col, base_col, tip_col)
	return b.commit()

static func _rock(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.material("rock", WorldMaterials.terrain())
	var r := RandomNumberGenerator.new()
	r.seed = 4400 + variant
	b.rock("rock", 0.5, Vector3(0, 0.12, 0), Color(0, 0, 1, 1), Vector3(r.randf_range(1.0, 1.5), r.randf_range(0.6, 0.9), r.randf_range(0.9, 1.3)), 31 + variant, 0.22)
	return b.commit()

# -----------------------------------------------------------------------------

## Disegna molte istanze di una variante con un'unica MultiMesh.
static func scatter(parent: Node3D, kind: String, variant: int, transforms: Array, shadows: bool = true) -> MultiMeshInstance3D:
	if transforms.is_empty(): return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh(kind, variant)
	mm.instance_count = transforms.size()
	for i in transforms.size(): mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi

static func placement(pos: Vector3, scale: float, yaw: float, tilt: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw)
	if tilt != Vector3.ZERO: basis = Basis.from_euler(tilt) * basis
	return Transform3D(basis.scaled(Vector3.ONE * scale), pos)
