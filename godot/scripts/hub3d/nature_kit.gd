extends RefCounted
class_name NatureKit

## Alberi, cespugli, ciuffi d'erba e rocce per la base e le missioni.
## Ogni variante è una ArrayMesh costruita una volta e disegnata con MultiMesh.

const CONIFER_GREENS := [Color("#3e6436"), Color("#355f42"), Color("#4b6634"), Color("#3a5a48")]
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
# Elementi comuni
# -----------------------------------------------------------------------------

static func _bark(b: MeshBuilder) -> void:
	b.material("bark", WorldMaterials.wood("bark"))

## Carta di fogliame: rettangolo centrato in "center" con assi "right" e "up"
## (lunghezze piene), UV dentro "cell" dell'atlante. La base della texture
## (rametto) è in basso, la punta in alto. Le normali puntano fuori da "crown".
static func _card(b: MeshBuilder, key: String, center: Vector3, right: Vector3, up: Vector3, cell: Rect2, crown: Vector3, out_bias: Vector3, col_low: Color, col_high: Color) -> void:
	var c0 := center - right * 0.5 - up * 0.5
	var c1 := center + right * 0.5 - up * 0.5
	var c2 := center + right * 0.5 + up * 0.5
	var c3 := center - right * 0.5 + up * 0.5
	var n0 := ((c0 - crown).normalized() + out_bias).normalized()
	var n1 := ((c1 - crown).normalized() + out_bias).normalized()
	var n2 := ((c2 - crown).normalized() + out_bias).normalized()
	var n3 := ((c3 - crown).normalized() + out_bias).normalized()
	var u0 := cell.position.x
	var u1 := cell.position.x + cell.size.x
	var v_top := cell.position.y
	var v_bottom := cell.position.y + cell.size.y
	b.tri(key, c0, c1, c2, n0, n1, n2, Vector2(u0, v_bottom), Vector2(u1, v_bottom), Vector2(u1, v_top), col_low, col_low, col_high)
	b.tri(key, c0, c2, c3, n0, n2, n3, Vector2(u0, v_bottom), Vector2(u1, v_top), Vector2(u0, v_top), col_low, col_high, col_high)

## Volume pieno dentro una chioma: sfera con normali che puntano fuori dal
## centro della chioma (si illumina insieme alle carte) e colore che scurisce in basso.
static func _blob(b: MeshBuilder, key: String, center: Vector3, radius: Vector3, crown: Vector3, col_top: Color, col_bottom: Color, segments: int = 9, rings: int = 6) -> void:
	var pts: Array = []
	for ring in rings + 1:
		var row: Array = []
		var phi := PI * ring / rings
		for seg in segments + 1:
			var th := TAU * seg / segments
			row.append(center + Vector3(sin(phi) * cos(th) * radius.x, cos(phi) * radius.y, sin(phi) * sin(th) * radius.z))
		pts.append(row)
	for ring in rings:
		for seg in segments:
			var quad := [pts[ring][seg], pts[ring][seg + 1], pts[ring + 1][seg + 1], pts[ring + 1][seg]]
			var ns: Array = []
			var cs: Array = []
			for q in quad:
				var p: Vector3 = q
				ns.append(((p - crown).normalized() * 0.7 + (p - center).normalized() * 0.3).normalized())
				var t := clampf((p.y - (center.y - radius.y)) / (radius.y * 2.0), 0.0, 1.0)
				var c := col_bottom.lerp(col_top, t)
				c.a = lerpf(0.35, 0.75, t)
				cs.append(c)
			b.tri(key, quad[0], quad[1], quad[2], ns[0], ns[1], ns[2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cs[0], cs[1], cs[2])
			b.tri(key, quad[0], quad[2], quad[3], ns[0], ns[2], ns[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cs[0], cs[2], cs[3])

static func _rand_dir(r: RandomNumberGenerator) -> Vector3:
	var z := r.randf_range(-1.0, 1.0)
	var a := r.randf() * TAU
	var s := sqrt(1.0 - z * z)
	return Vector3(s * cos(a), z, s * sin(a))

## Colore per vertice con l'occlusione nel canale alfa.
static func _shade(c: Color, ao: float) -> Color:
	var out := c
	out.a = clampf(ao, 0.0, 1.0)
	return out

# -----------------------------------------------------------------------------
# Conifera: tronco, cuore scuro e palchi di rametti ritagliati che scendono
# -----------------------------------------------------------------------------

static func _conifer(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	_bark(b)
	b.material("needles", WorldMaterials.foliage_cards("needles", 0.022))
	b.material("core", WorldMaterials.foliage_solid())
	var r := RandomNumberGenerator.new()
	r.seed = 7100 + variant
	var height := 4.4 + variant * 0.45
	var base_green: Color = CONIFER_GREENS[variant % CONIFER_GREENS.size()]
	b.cylinder("bark", 0.04, 0.16, height * 0.86, Vector3(0, height * 0.43, 0), Color.WHITE, 9, Vector3.ZERO, false, MeshBuilder.UV.LONG)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		b.rod("bark", Vector3(cos(a) * 0.26, 0.0, sin(a) * 0.26), Vector3(cos(a) * 0.05, 0.3, sin(a) * 0.05), 0.025, 0.08, Color.WHITE, 5)
	# cuore pieno a cono: impedisce di vedere attraverso i rami
	var core_low := base_green.darkened(0.45)
	var core_high := base_green.darkened(0.15)
	var rings := 8
	var segs := 9
	var prev: Array = []
	for ri in rings + 1:
		var k := float(ri) / rings
		var y := 0.5 + k * (height - 0.9)
		var rad := lerpf(0.95, 0.06, pow(k, 0.9))
		var row: Array = []
		for si in segs + 1:
			var a := TAU * si / segs
			row.append(Vector3(cos(a) * rad, y, sin(a) * rad))
		if ri > 0:
			for si in segs:
				var q := [prev[si], prev[si + 1], row[si + 1], row[si]]
				var ns: Array = []
				var cs: Array = []
				for v in q:
					var pv: Vector3 = v
					ns.append((Vector3(pv.x, 0, pv.z).normalized() + Vector3(0, 0.7, 0)).normalized())
					var t := clampf(pv.y / height, 0.0, 1.0)
					cs.append(_shade(core_low.lerp(core_high, t), lerpf(0.45, 0.8, t)))
				b.tri("core", q[0], q[1], q[2], ns[0], ns[1], ns[2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cs[0], cs[1], cs[2])
				b.tri("core", q[0], q[2], q[3], ns[0], ns[2], ns[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cs[0], cs[2], cs[3])
		prev = row
	var tiers := 9 + variant % 2
	var phase := r.randf() * TAU
	for t in tiers:
		var k := float(t) / (tiers - 1)
		var y := 0.55 + k * (height - 0.95)
		var reach := lerpf(1.6, 0.26, pow(k, 0.85)) * (0.92 + r.randf() * 0.14)
		var count := int(round(lerpf(12.0, 5.0, k)))
		var tier_col := base_green.lightened(0.05 * k)
		for i in count:
			var a := phase + TAU * (i + r.randf_range(-0.25, 0.25)) / count + t * 0.37
			var dir := Vector3(cos(a), 0.0, sin(a))
			var side := Vector3(-dir.z, 0.0, dir.x)
			var root := Vector3(0, y, 0) + dir * 0.05
			var tip := Vector3(0, y, 0) + dir * reach + Vector3(0, -reach * r.randf_range(0.28, 0.42), 0)
			var axis := tip - root
			var length := axis.length()
			# la carta è un po' ruotata attorno al ramo: si vede bene dall'alto
			var tilt := r.randf_range(-0.6, 0.6)
			var right := (side * cos(tilt) + Vector3.UP * sin(tilt)).normalized() * length * 0.9
			var center := root + axis * 0.5
			var cell := Rect2(0.5 * (i % 2), 0.0, 0.5, 1.0)
			var low := _shade(tier_col.darkened(0.2), lerpf(0.6, 0.8, k))
			var high := _shade(tier_col.lightened(0.15), 1.0)
			_card(b, "needles", center, right, axis, cell, Vector3(0, y + 0.4, 0), Vector3(0, 0.5, 0), low, high)
	# cima
	var top := Vector3(0, height - 0.55, 0)
	for i in 3:
		var a := TAU * i / 3.0 + phase
		var right := Vector3(cos(a), 0, sin(a)) * 0.42
		_card(b, "needles", top + Vector3(0, 0.25, 0), right, Vector3(0, 0.75, 0), Rect2(0.5 * (i % 2), 0.0, 0.5, 1.0), top - Vector3(0, 0.6, 0), Vector3(0, 0.4, 0), _shade(base_green.darkened(0.2), 0.8), _shade(base_green.lightened(0.18), 1.0))
	return b.commit()

# -----------------------------------------------------------------------------
# Latifoglia: tronco con radici, rami e chioma a lobi di carte di foglie
# -----------------------------------------------------------------------------

static func _broadleaf(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	_bark(b)
	b.material("leaves", WorldMaterials.foliage_cards("leaves", 0.03))
	b.material("crown", WorldMaterials.foliage_solid())
	var r := RandomNumberGenerator.new()
	r.seed = 8200 + variant
	var trunk_h := 1.45 + variant * 0.12
	var lean := Vector3(r.randf_range(-0.16, 0.16), 0, r.randf_range(-0.16, 0.16))
	var trunk_top := Vector3(0, trunk_h, 0) + lean
	b.rod("bark", Vector3.ZERO, trunk_top, 0.21, 0.12, Color.WHITE, 10, false)
	for i in 5:
		var a := TAU * i / 5.0 + r.randf() * 0.5
		b.rod("bark", Vector3(cos(a) * 0.36, 0.0, sin(a) * 0.36), Vector3(cos(a) * 0.08, 0.42, sin(a) * 0.08), 0.03, 0.11, Color.WHITE, 6)
	var green: Color = LEAF_GREENS[variant % LEAF_GREENS.size()]
	var crown := trunk_top + Vector3(0, 1.2, 0)
	var radius := Vector3(1.5, 1.15, 1.5) * (1.0 + variant * 0.04)
	var lobes := 6 + variant % 3
	var lobe_centers: Array[Vector3] = []
	for i in lobes:
		var a := TAU * i / lobes + r.randf_range(-0.3, 0.3)
		var elev := r.randf_range(-0.25, 0.75)
		var dir := Vector3(cos(a) * cos(elev), sin(elev), sin(a) * cos(elev))
		lobe_centers.append(crown + dir * radius * r.randf_range(0.45, 0.6))
	lobe_centers.append(crown + Vector3(0, radius.y * 0.45, 0))
	# rami verso i lobi
	for lc in lobe_centers:
		var to := trunk_top.lerp(lc, 0.75)
		b.rod("bark", trunk_top - Vector3(0, 0.25, 0), to, 0.08, 0.035, Color.WHITE, 5, false)
	var top_col := green.lightened(0.16)
	var low_col := green.darkened(0.42)
	for li in lobe_centers.size():
		var lc: Vector3 = lobe_centers[li]
		var lr := r.randf_range(0.66, 0.86) * (1.0 + variant * 0.03)
		var hue: Color = green.lerp(LEAF_GREENS[(variant + li + 1) % LEAF_GREENS.size()], 0.3)
		_blob(b, "crown", lc, Vector3(lr, lr * 0.85, lr) * 0.8, crown, hue.darkened(0.25), hue.darkened(0.6), 8, 5)
		for k in 15:
			var d := (_rand_dir(r) + (lc - crown).normalized() * 0.9).normalized()
			var p := lc + d * lr * r.randf_range(0.5, 0.95)
			var out := (p - crown).normalized()
			var up := (Vector3.UP - out * out.dot(Vector3.UP))
			if up.length() < 0.2: up = Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1))
			up = up.normalized().rotated(out, r.randf_range(-0.7, 0.7))
			var normal := (out + _rand_dir(r) * 0.35).normalized()
			var right := up.cross(normal).normalized()
			up = normal.cross(right).normalized()
			var size := r.randf_range(0.9, 1.2)
			var t := clampf((p.y - (crown.y - radius.y)) / (radius.y * 2.0), 0.0, 1.0)
			var shade := hue.lerp(top_col, t * 0.8).lerp(low_col, (1.0 - t) * 0.45)
			var cell := Rect2(0.5 * (k % 2), 0.0, 0.5, 0.5)
			_card(b, "leaves", p, right * size, up * size, cell, crown, Vector3(0, 0.25, 0), _shade(shade.darkened(0.12), lerpf(0.55, 0.85, t)), _shade(shade, lerpf(0.7, 1.0, t)))
	return b.commit()

static func _bush(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.material("leaves", WorldMaterials.foliage_cards("leaves", 0.02))
	b.material("crown", WorldMaterials.foliage_solid())
	var r := RandomNumberGenerator.new()
	r.seed = 9300 + variant
	var green: Color = LEAF_GREENS[(variant + 1) % LEAF_GREENS.size()].darkened(0.08)
	var crown := Vector3(0, 0.2, 0)
	for li in 3:
		var a := TAU * li / 3.0 + r.randf()
		var lc := Vector3(cos(a) * 0.28, 0.36 + r.randf_range(0.0, 0.12), sin(a) * 0.28)
		var lr := r.randf_range(0.36, 0.46)
		_blob(b, "crown", lc, Vector3(lr, lr * 0.8, lr) * 0.85, crown, green.darkened(0.25), green.darkened(0.6), 7, 4)
		for k in 9:
			var d := (_rand_dir(r) + Vector3(0, 0.6, 0)).normalized()
			var p := lc + d * lr * r.randf_range(0.55, 0.95)
			var out := (p - crown).normalized()
			var up := (Vector3.UP - out * out.dot(Vector3.UP))
			if up.length() < 0.2: up = Vector3(1, 0, 0)
			up = up.normalized().rotated(out, r.randf_range(-0.8, 0.8))
			var normal := (out + _rand_dir(r) * 0.3).normalized()
			var right := up.cross(normal).normalized()
			up = normal.cross(right).normalized()
			var size := r.randf_range(0.55, 0.75)
			var t := clampf(p.y / 0.8, 0.0, 1.0)
			var shade := green.lightened(0.12 * t)
			_card(b, "leaves", p, right * size, up * size, Rect2(0.5 * (k % 2), 0.5, 0.5, 0.5), crown, Vector3(0, 0.3, 0), _shade(shade.darkened(0.15), lerpf(0.5, 0.8, t)), _shade(shade, lerpf(0.7, 1.0, t)))
	return b.commit()

static func _dead_tree(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.material("bark", WorldMaterials.wood("weathered"))
	var r := RandomNumberGenerator.new()
	r.seed = 9900 + variant
	var h := 2.6 + variant * 0.3
	var top := Vector3(r.randf_range(-0.15, 0.15), h, r.randf_range(-0.15, 0.15))
	b.rod("bark", Vector3.ZERO, top, 0.2, 0.05, Color.WHITE, 9, false)
	for i in 4:
		var a := TAU * i / 4.0 + r.randf()
		b.rod("bark", Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32), Vector3(cos(a) * 0.06, 0.32, sin(a) * 0.06), 0.025, 0.09, Color.WHITE, 5)
	for i in 6:
		var a := TAU * i / 6.0 + r.randf()
		var dir := Vector3(cos(a), r.randf_range(0.4, 1.1), sin(a)).normalized()
		var start := Vector3(0, h * r.randf_range(0.45, 0.85), 0)
		var length := r.randf_range(0.6, 1.2)
		var end := start + dir * length
		b.rod("bark", start, end, 0.05, 0.012, Color.WHITE, 5, false)
		var twig_dir := (dir + Vector3(r.randf_range(-0.6, 0.6), 0.3, r.randf_range(-0.6, 0.6))).normalized()
		b.rod("bark", start.lerp(end, 0.6), start.lerp(end, 0.6) + twig_dir * length * 0.4, 0.02, 0.006, Color.WHITE, 4, false)
	return b.commit()

## Ciuffo d'erba: tre carte incrociate con la texture dei fili d'erba.
static func _tuft(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.material("grass", WorldMaterials.foliage_cards("grass", 0.06))
	var r := RandomNumberGenerator.new()
	r.seed = 5100 + variant
	var base_col := _shade(Color("#3f5a22") if variant % 2 == 0 else Color("#4d5a24"), 0.55)
	var tip_col := _shade(Color("#a9b85e") if variant % 2 == 0 else Color("#bdb365"), 1.0)
	var h := 0.42 if variant % 2 == 0 else 0.34
	for i in 3:
		var a := TAU * i / 6.0 + r.randf() * 0.4
		var right := Vector3(cos(a), 0, sin(a)) * 0.5
		_card(b, "grass", Vector3(0, h * 0.5, 0), right, Vector3(0, h, 0), Rect2(0.5 * ((i + variant) % 2), 0.0, 0.5, 1.0), Vector3(0, -2.0, 0), Vector3.ZERO, base_col, tip_col)
	return b.commit()

## Masso: icosfera suddivisa e deformata con il rumore, normali morbide.
static func _rock(variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.material("rock", WorldMaterials.rock())
	var noise := FastNoiseLite.new()
	noise.seed = 4400 + variant
	noise.frequency = 1.6
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in verts.size(): verts[i] = verts[i].normalized()
	for level in 2:
		var mids := {}
		var next_faces := []
		for f in faces:
			var m := []
			for e in 3:
				var a: int = f[e]
				var c: int = f[(e + 1) % 3]
				var key := "%d_%d" % [mini(a, c), maxi(a, c)]
				if not mids.has(key):
					mids[key] = verts.size()
					verts.append(((verts[a] + verts[c]) * 0.5).normalized())
				m.append(mids[key])
			next_faces.append([f[0], m[0], m[2]])
			next_faces.append([f[1], m[1], m[0]])
			next_faces.append([f[2], m[2], m[1]])
			next_faces.append([m[0], m[1], m[2]])
		faces = next_faces
	var r := RandomNumberGenerator.new()
	r.seed = 4400 + variant
	var scale := Vector3(r.randf_range(0.55, 0.75), r.randf_range(0.32, 0.45), r.randf_range(0.45, 0.62))
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + noise.get_noise_3dv(v) * 0.32 + noise.get_noise_3dv(v * 3.1) * 0.08
		var p := v * d * scale
		# base piatta, appoggiata al terreno
		if p.y < -0.05: p.y = -0.05 + (p.y + 0.05) * 0.2
		verts[i] = p + Vector3(0, 0.08, 0)
	var normals: Array[Vector3] = []
	normals.resize(verts.size())
	for i in normals.size(): normals[i] = Vector3.ZERO
	for f in faces:
		var n := (verts[f[1]] - verts[f[0]]).cross(verts[f[2]] - verts[f[0]])
		for k in 3: normals[f[k]] += n
	for f in faces:
		var cs: Array = []
		for k in 3:
			var p: Vector3 = verts[f[k]]
			cs.append(Color(1, 1, 1, clampf(0.45 + (p.y + 0.05) * 1.6, 0.4, 1.0)))
		b.tri("rock", verts[f[0]], verts[f[1]], verts[f[2]], normals[f[0]].normalized(), normals[f[1]].normalized(), normals[f[2]].normalized(), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cs[0], cs[1], cs[2])
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
