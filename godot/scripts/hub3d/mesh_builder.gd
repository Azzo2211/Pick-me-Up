extends RefCounted
class_name MeshBuilder

## Costruisce un'unica ArrayMesh unendo molte primitive (box, cilindri, tetti,
## archi, rocce...). Ogni materiale diventa una superficie, così un edificio
## dettagliato costa pochi draw call. Le UV sono in unità di mondo: gli shader
## procedurali (pietra, legno, tegole) mantengono la stessa scala su ogni faccia.
## Il colore dei vertici è una tinta (sRGB) e l'alfa un'occlusione ambientale.

enum UV { FACE, LONG }

var _tools: Dictionary = {}
var _materials: Dictionary = {}
var _order: Array[String] = []
var xform := Transform3D.IDENTITY
var _normal_basis := Basis.IDENTITY
var _stack: Array[Transform3D] = []

func material(key: String, mat: Material) -> MeshBuilder:
	_materials[key] = mat
	return self

func has_geometry() -> bool:
	return not _tools.is_empty()

func push(t: Transform3D) -> void:
	_stack.append(xform)
	xform = xform * t
	_normal_basis = xform.basis.inverse().transposed()

func push_at(pos: Vector3, yaw: float = 0.0) -> void:
	push(Transform3D(Basis(Vector3.UP, yaw), pos))

func pop() -> void:
	xform = _stack.pop_back()
	_normal_basis = xform.basis.inverse().transposed()

func _st(key: String) -> SurfaceTool:
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
		_order.append(key)
	return _tools[key]

func _vertex(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	st.set_color(col)
	st.set_uv(uv)
	st.set_normal(n)
	st.add_vertex(p)

## Triangolo in coordinate locali. L'ordine dei vertici viene sistemato in base
## alle normali: Godot considera frontali i triangoli in senso orario.
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color, cb: Color = Color(-1, 0, 0), cc: Color = Color(-1, 0, 0)) -> void:
	var st := _st(key)
	var A := xform * a
	var B := xform * b
	var C := xform * c
	var NA := (_normal_basis * na).normalized()
	var NB := (_normal_basis * nb).normalized()
	var NC := (_normal_basis * nc).normalized()
	var col_b := col if cb.r < 0.0 else cb
	var col_c := col if cc.r < 0.0 else cc
	if (B - A).cross(C - A).dot(NA + NB + NC) < 0.0:
		var tp := B; B = C; C = tp
		var tn := NB; NB = NC; NC = tn
		var tu := ub; ub = uc; uc = tu
		var tc := col_b; col_b = col_c; col_c = tc
	_vertex(st, A, NA, ua, col)
	_vertex(st, C, NC, uc, col_c)
	_vertex(st, B, NB, ub, col_b)

## Triangolo piatto: la normale è quella della faccia, orientata verso "outward".
func flat_tri(key: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color, uv_a := Vector2.ZERO, uv_b := Vector2.ZERO, uv_c := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(outward) < 0.0: n = -n
	tri(key, a, b, c, n, n, n, uv_a, uv_b, uv_c, col)

## Quadrilatero piatto (a, b, c, d in ordine lungo il perimetro).
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.000001: n = (c - a).cross(d - a)
	n = n.normalized()
	if n.dot(outward) < 0.0: n = -n
	tri(key, a, b, c, n, n, n, ua, ub, uc, col)
	tri(key, a, c, d, n, n, n, ua, uc, ud, col)

# =============================================================================
# Primitive
# =============================================================================

## Parallelepipedo. "rot" in radianti (euler YXZ). Con uv_mode LONG la U segue
## il lato più lungo di ogni faccia (venature del legno lungo travi e pali).
func box(key: String, size: Vector3, center: Vector3, col: Color = Color.WHITE, rot: Vector3 = Vector3.ZERO, uv_mode: int = UV.FACE, skip_bottom: bool = true) -> void:
	var basis := Basis.from_euler(rot)
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
	]
	for face in faces:
		var n: Vector3 = face[0]
		if skip_bottom and n == Vector3.DOWN: continue
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var su := absf(u.dot(size))
		var sv := absf(v.dot(size))
		var origin := n * absf(n.dot(h))
		var corners := []
		for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			corners.append(origin + u * (k[0] * su * 0.5) + v * (k[1] * sv * 0.5))
		var uvs := []
		for k in [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]:
			var uu: float = k[0] * su
			var vv: float = k[1] * sv
			if n == Vector3.UP or n == Vector3.DOWN:
				uu += center.x - su * 0.5
				vv += center.z - sv * 0.5
			else:
				uu += absf(u.x) * (center.x - su * 0.5) + absf(u.z) * (center.z - su * 0.5)
				vv += center.y - sv * 0.5
			if uv_mode == UV.LONG and sv > su: uvs.append(Vector2(vv, uu))
			else: uvs.append(Vector2(uu, vv))
		var wn := basis * n
		var p: Array[Vector3] = []
		for corner in corners: p.append(center + basis * (corner as Vector3))
		tri(key, p[0], p[1], p[2], wn, wn, wn, uvs[0], uvs[1], uvs[2], col)
		tri(key, p[0], p[2], p[3], wn, wn, wn, uvs[0], uvs[2], uvs[3], col)

## Tronco di cono / cilindro lungo Y. "arc" < TAU produce un settore aperto.
func cylinder(key: String, r_top: float, r_bottom: float, height: float, center: Vector3, col: Color = Color.WHITE, segments: int = 12, rot: Vector3 = Vector3.ZERO, caps: bool = true, uv_mode: int = UV.FACE, arc: float = TAU, smooth: bool = true, start_angle: float = 0.0) -> void:
	var basis := Basis.from_euler(rot)
	var y0 := -height * 0.5
	var y1 := height * 0.5
	var slope := (r_bottom - r_top) / maxf(height, 0.0001)
	var avg_r := (r_top + r_bottom) * 0.5
	var full := is_equal_approx(arc, TAU)
	for i in segments:
		var a0 := start_angle + arc * i / segments
		var a1 := start_angle + arc * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := d0 * r_bottom + Vector3(0, y0, 0)
		var b1 := d1 * r_bottom + Vector3(0, y0, 0)
		var t0 := d0 * r_top + Vector3(0, y1, 0)
		var t1 := d1 * r_top + Vector3(0, y1, 0)
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		if not smooth:
			var nm := (n0 + n1).normalized()
			n0 = nm
			n1 = nm
		var u0 := a0 * avg_r
		var u1 := a1 * avg_r
		var uv_b0 := Vector2(u0, center.y + y0)
		var uv_b1 := Vector2(u1, center.y + y0)
		var uv_t0 := Vector2(u0, center.y + y1)
		var uv_t1 := Vector2(u1, center.y + y1)
		if uv_mode == UV.LONG and height > avg_r * 2.0:
			uv_b0 = Vector2(uv_b0.y, uv_b0.x); uv_b1 = Vector2(uv_b1.y, uv_b1.x)
			uv_t0 = Vector2(uv_t0.y, uv_t0.x); uv_t1 = Vector2(uv_t1.y, uv_t1.x)
		var P := [center + basis * b0, center + basis * b1, center + basis * t1, center + basis * t0]
		var N := [basis * n0, basis * n1, basis * n1, basis * n0]
		if r_top <= 0.0001:
			var apex_n: Vector3 = (N[0] + N[1]).normalized()
			tri(key, P[0], P[1], P[3], N[0], N[1], apex_n, uv_b0, uv_b1, (uv_t0 + uv_t1) * 0.5, col)
		elif r_bottom <= 0.0001:
			var apex_b: Vector3 = (N[2] + N[3]).normalized()
			tri(key, P[0], P[2], P[3], apex_b, N[2], N[3], (uv_b0 + uv_b1) * 0.5, uv_t1, uv_t0, col)
		else:
			tri(key, P[0], P[1], P[2], N[0], N[1], N[2], uv_b0, uv_b1, uv_t1, col)
			tri(key, P[0], P[2], P[3], N[0], N[2], N[3], uv_b0, uv_t1, uv_t0, col)
		if caps:
			var up := basis * Vector3.UP
			if r_top > 0.0001:
				var ct := center + basis * Vector3(0, y1, 0)
				tri(key, ct, P[3], P[2], up, up, up, Vector2(center.x, center.z), Vector2(center.x, center.z) + Vector2(d0.x, d0.z) * r_top, Vector2(center.x, center.z) + Vector2(d1.x, d1.z) * r_top, col)
			if r_bottom > 0.0001:
				var cb := center + basis * Vector3(0, y0, 0)
				tri(key, cb, P[1], P[0], -up, -up, -up, Vector2(center.x, center.z), Vector2(center.x, center.z) + Vector2(d1.x, d1.z) * r_bottom, Vector2(center.x, center.z) + Vector2(d0.x, d0.z) * r_bottom, col)
	if not full and caps:
		# chiude i lati del settore
		for a in [start_angle, start_angle + arc]:
			var d := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-d.z, 0, d.x) * (1.0 if a == start_angle else -1.0)
			var pts := [Vector3(0, y0, 0), d * r_bottom + Vector3(0, y0, 0), d * r_top + Vector3(0, y1, 0), Vector3(0, y1, 0)]
			var wp: Array[Vector3] = []
			for q in pts: wp.append(center + basis * (q as Vector3))
			quad(key, wp[0], wp[1], wp[2], wp[3], basis * -side, col, Vector2(0, y0), Vector2(r_bottom, y0), Vector2(r_top, y1), Vector2(0, y1))

## Cilindro tra due punti (aste, rami, lance, segmenti di arco).
func rod(key: String, a: Vector3, b: Vector3, r_a: float, r_b: float, col: Color = Color.WHITE, segments: int = 6, caps: bool = true) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001: return
	var unit := dir / length
	var basis: Basis
	if unit.dot(Vector3.UP) < -0.9999: basis = Basis(Vector3.RIGHT, PI)
	elif unit.dot(Vector3.UP) > 0.9999: basis = Basis.IDENTITY
	else: basis = Basis(Quaternion(Vector3.UP, unit))
	cylinder(key, r_b, r_a, length, (a + b) * 0.5, col, segments, basis.get_euler(), caps, UV.LONG)

func cone(key: String, radius: float, height: float, center: Vector3, col: Color = Color.WHITE, segments: int = 10, rot: Vector3 = Vector3.ZERO) -> void:
	cylinder(key, 0.0, radius, height, center, col, segments, rot)

## Sfera (o ellissoide con "scale"). "top_only" crea una cupola.
func sphere(key: String, radius: float, center: Vector3, col: Color = Color.WHITE, scale: Vector3 = Vector3.ONE, segments: int = 12, rings: int = 8, top_only: bool = false, rot: Vector3 = Vector3.ZERO, col_bottom: Color = Color(-1, 0, 0)) -> void:
	var basis := Basis.from_euler(rot)
	var r0 := 0 if not top_only else rings / 2
	var cb := col if col_bottom.r < 0.0 else col_bottom
	for j in range(r0, rings):
		var p0 := PI * j / rings - PI * 0.5
		var p1 := PI * (j + 1) / rings - PI * 0.5
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var pts := [
				Vector3(cos(p0) * cos(a0), sin(p0), cos(p0) * sin(a0)),
				Vector3(cos(p0) * cos(a1), sin(p0), cos(p0) * sin(a1)),
				Vector3(cos(p1) * cos(a1), sin(p1), cos(p1) * sin(a1)),
				Vector3(cos(p1) * cos(a0), sin(p1), cos(p1) * sin(a0)),
			]
			var P: Array[Vector3] = []
			var N: Array[Vector3] = []
			var C: Array[Color] = []
			var U: Array[Vector2] = []
			for q in pts:
				var unit: Vector3 = q
				P.append(center + basis * (unit * radius * scale))
				N.append((basis * Vector3(unit.x / scale.x, unit.y / scale.y, unit.z / scale.z)).normalized())
				C.append(cb.lerp(col, clampf(unit.y * 0.5 + 0.5, 0.0, 1.0)))
				U.append(Vector2(atan2(unit.z, unit.x) * radius, asin(clampf(unit.y, -1.0, 1.0)) * radius))
			var bottom_pole := j == 0 and not top_only
			var top_pole := j == rings - 1
			if not bottom_pole: tri(key, P[0], P[1], P[2], N[0], N[1], N[2], U[0], U[1], U[2], C[0], C[1], C[2])
			if not top_pole: tri(key, P[0], P[2], P[3], N[0], N[2], N[3], U[0], U[2], U[3], C[0], C[2], C[3])

func dome(key: String, radius: float, center: Vector3, col: Color = Color.WHITE, height_scale: float = 1.0, segments: int = 18, rings: int = 10) -> void:
	sphere(key, radius, center, col, Vector3(1, height_scale, 1), segments, rings * 2, true)

func torus(key: String, ring_radius: float, tube_radius: float, center: Vector3, col: Color = Color.WHITE, rot: Vector3 = Vector3.ZERO, segments: int = 24, sides: int = 8, arc: float = TAU) -> void:
	var basis := Basis.from_euler(rot)
	for i in segments:
		var a0 := arc * i / segments
		var a1 := arc * (i + 1) / segments
		for j in sides:
			var b0 := TAU * j / sides
			var b1 := TAU * (j + 1) / sides
			var P: Array[Vector3] = []
			var N: Array[Vector3] = []
			for k in [[a0, b0], [a1, b0], [a1, b1], [a0, b1]]:
				var dir := Vector3(cos(k[0]), 0, sin(k[0]))
				var n := dir * cos(k[1]) + Vector3.UP * sin(k[1])
				P.append(center + basis * (dir * ring_radius + n * tube_radius))
				N.append(basis * n)
			var u0 := a0 * ring_radius
			var u1 := a1 * ring_radius
			tri(key, P[0], P[1], P[2], N[0], N[1], N[2], Vector2(u0, b0 * tube_radius), Vector2(u1, b0 * tube_radius), Vector2(u1, b1 * tube_radius), col)
			tri(key, P[0], P[2], P[3], N[0], N[2], N[3], Vector2(u0, b0 * tube_radius), Vector2(u1, b1 * tube_radius), Vector2(u0, b1 * tube_radius), col)

## Poligono (XZ) estruso tra y0 e y1. I punti vanno in un verso qualsiasi.
func extrude(key: String, points: PackedVector2Array, y0: float, y1: float, col: Color = Color.WHITE, cap_top: bool = true, cap_bottom: bool = false, offset: Vector3 = Vector3.ZERO) -> void:
	var n_pts := points.size()
	if n_pts < 3: return
	var area := 0.0
	for i in n_pts:
		var p := points[i]
		var q := points[(i + 1) % n_pts]
		area += p.x * q.y - q.x * p.y
	var ccw := area > 0.0
	var length := 0.0
	for i in n_pts:
		var p := points[i]
		var q := points[(i + 1) % n_pts]
		var edge := q - p
		var out := Vector3(edge.y, 0, -edge.x).normalized() * (1.0 if ccw else -1.0)
		var seg := edge.length()
		quad(key, offset + Vector3(p.x, y0, p.y), offset + Vector3(q.x, y0, q.y), offset + Vector3(q.x, y1, q.y), offset + Vector3(p.x, y1, p.y), out, col,
			Vector2(length, y0), Vector2(length + seg, y0), Vector2(length + seg, y1), Vector2(length, y1))
		length += seg
	var indices := Geometry2D.triangulate_polygon(points)
	for k in range(0, indices.size(), 3):
		var a := points[indices[k]]
		var b := points[indices[k + 1]]
		var c := points[indices[k + 2]]
		if cap_top:
			flat_tri(key, offset + Vector3(a.x, y1, a.y), offset + Vector3(b.x, y1, b.y), offset + Vector3(c.x, y1, c.y), Vector3.UP, col, a + Vector2(offset.x, offset.z), b + Vector2(offset.x, offset.z), c + Vector2(offset.x, offset.z))
		if cap_bottom:
			flat_tri(key, offset + Vector3(a.x, y0, a.y), offset + Vector3(b.x, y0, b.y), offset + Vector3(c.x, y0, c.y), Vector3.DOWN, col, a, b, c)

## Tetto a due falde con colmo lungo X: due lastre spesse più la trave di colmo.
func gable_roof(key: String, width: float, depth: float, rise: float, base_y: float, col: Color = Color.WHITE, overhang: float = 0.3, thickness: float = 0.08, center: Vector3 = Vector3.ZERO) -> void:
	var half := depth * 0.5 + overhang
	var angle := atan2(rise, depth * 0.5)
	var slope_len := half / cos(angle)
	for side in [-1.0, 1.0]:
		var mid := Vector3(0, base_y + rise - tan(angle) * half * 0.5, side * half * 0.5)
		var nrm := Vector3(0, cos(angle), side * sin(angle))
		box(key, Vector3(width + overhang * 2.0, thickness, slope_len), center + mid + nrm * thickness * 0.5, col, Vector3(side * angle, 0, 0))

## Timpano triangolare (pareti alle estremità di un tetto a due falde, piano YZ).
func gable_wall(key: String, depth: float, rise: float, base_y: float, x: float, col: Color = Color.WHITE, outward: float = 1.0) -> void:
	var a := Vector3(x, base_y, -depth * 0.5)
	var b := Vector3(x, base_y, depth * 0.5)
	var c := Vector3(x, base_y + rise, 0)
	flat_tri(key, a, b, c, Vector3(outward, 0, 0), col, Vector2(-depth * 0.5, base_y), Vector2(depth * 0.5, base_y), Vector2(0, base_y + rise))

## Tetto a padiglione (quattro falde) su pianta rettangolare.
func hip_roof(key: String, width: float, depth: float, rise: float, base_y: float, col: Color = Color.WHITE, overhang: float = 0.3) -> void:
	var w := width * 0.5 + overhang
	var d := depth * 0.5 + overhang
	var ridge := maxf(0.0, w - d)
	var top_a := Vector3(-ridge, base_y + rise, 0)
	var top_b := Vector3(ridge, base_y + rise, 0)
	var c := [Vector3(-w, base_y, -d), Vector3(w, base_y, -d), Vector3(w, base_y, d), Vector3(-w, base_y, d)]
	var slope_len := sqrt(d * d + rise * rise)
	quad(key, c[3], c[2], top_b, top_a, Vector3(0, 1, 1), col, Vector2(-w, 0), Vector2(w, 0), Vector2(ridge, slope_len), Vector2(-ridge, slope_len))
	quad(key, c[1], c[0], top_a, top_b, Vector3(0, 1, -1), col, Vector2(w, 0), Vector2(-w, 0), Vector2(-ridge, slope_len), Vector2(ridge, slope_len))
	var side_len := sqrt((w - ridge) * (w - ridge) + rise * rise)
	flat_tri(key, c[2], c[1], top_b, Vector3(1, 1, 0), col, Vector2(d, 0), Vector2(-d, 0), Vector2(0, side_len))
	flat_tri(key, c[0], c[3], top_a, Vector3(-1, 1, 0), col, Vector2(-d, 0), Vector2(d, 0), Vector2(0, side_len))

## Tetto conico (torri) con gronda.
func cone_roof(key: String, radius: float, rise: float, base_y: float, col: Color = Color.WHITE, segments: int = 14, center: Vector3 = Vector3.ZERO) -> void:
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := center + Vector3(cos(a0) * radius, base_y, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, base_y, sin(a1) * radius)
		var top := center + Vector3(0, base_y + rise, 0)
		var slope := sqrt(radius * radius + rise * rise)
		var am := (a0 + a1) * 0.5
		var n := Vector3(cos(am) * rise, radius, sin(am) * rise).normalized()
		var u0 := a0 * radius
		var u1 := a1 * radius
		tri(key, p0, p1, top, n, n, n, Vector2(u0, 0), Vector2(u1, 0), Vector2((u0 + u1) * 0.5, slope), col)

## Arco a tutto sesto (piano XY, spessore lungo Z) per porte e finestre.
func arch(key: String, inner: float, outer: float, depth: float, center: Vector3, col: Color = Color.WHITE, rot: Vector3 = Vector3.ZERO, segments: int = 10) -> void:
	var basis := Basis.from_euler(rot)
	for i in segments:
		var a0 := PI * i / segments
		var a1 := PI * (i + 1) / segments
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		for side in [-1.0, 1.0]:
			var z := Vector3(0, 0, depth * 0.5 * side)
			var pts := [d0 * inner + z, d1 * inner + z, d1 * outer + z, d0 * outer + z]
			var wp: Array[Vector3] = []
			for q in pts: wp.append(center + basis * (q as Vector3))
			quad(key, wp[0], wp[1], wp[2], wp[3], basis * Vector3(0, 0, side), col, Vector2(d0.x * inner, d0.y * inner), Vector2(d1.x * inner, d1.y * inner), Vector2(d1.x * outer, d1.y * outer), Vector2(d0.x * outer, d0.y * outer))
		var o0 := center + basis * (d0 * outer + Vector3(0, 0, -depth * 0.5))
		var o1 := center + basis * (d1 * outer + Vector3(0, 0, -depth * 0.5))
		var o2 := center + basis * (d1 * outer + Vector3(0, 0, depth * 0.5))
		var o3 := center + basis * (d0 * outer + Vector3(0, 0, depth * 0.5))
		quad(key, o0, o1, o2, o3, basis * ((d0 + d1) * 0.5), col, Vector2(a0 * outer, 0), Vector2(a1 * outer, 0), Vector2(a1 * outer, depth), Vector2(a0 * outer, depth))
		var i0 := center + basis * (d0 * inner + Vector3(0, 0, -depth * 0.5))
		var i1 := center + basis * (d1 * inner + Vector3(0, 0, -depth * 0.5))
		var i2 := center + basis * (d1 * inner + Vector3(0, 0, depth * 0.5))
		var i3 := center + basis * (d0 * inner + Vector3(0, 0, depth * 0.5))
		quad(key, i0, i1, i2, i3, basis * -((d0 + d1) * 0.5), col, Vector2(a0 * inner, 0), Vector2(a1 * inner, 0), Vector2(a1 * inner, depth), Vector2(a0 * inner, depth))

## Roccia: icosaedro suddiviso e deformato dal rumore, a facce piatte.
func rock(key: String, radius: float, center: Vector3, col: Color = Color.WHITE, scale: Vector3 = Vector3.ONE, seed_value: int = 1, roughness: float = 0.28, flat_bottom: bool = true) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.6
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var sub: Array = []
	var cache := {}
	for f in faces:
		var mids := []
		for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
			var key2 := "%d_%d" % [mini(e[0], e[1]), maxi(e[0], e[1])]
			if not cache.has(key2):
				cache[key2] = verts.size()
				verts.append((verts[e[0]] + verts[e[1]]) * 0.5)
			mids.append(cache[key2])
		sub.append([f[0], mids[0], mids[2]])
		sub.append([f[1], mids[1], mids[0]])
		sub.append([f[2], mids[2], mids[1]])
		sub.append([mids[0], mids[1], mids[2]])
	var pts: Array[Vector3] = []
	for v in verts:
		var dir := v.normalized()
		var r := 1.0 + noise.get_noise_3dv(dir * 1.3) * roughness * 2.0
		var p := dir * r * radius * scale
		if flat_bottom and p.y < -radius * scale.y * 0.35: p.y = -radius * scale.y * 0.35 + (p.y + radius * scale.y * 0.35) * 0.2
		pts.append(p)
	for f in sub:
		var a := pts[f[0]]
		var b := pts[f[1]]
		var c := pts[f[2]]
		var outward := (a + b + c) / 3.0
		var shade := col
		var up := outward.normalized().y
		shade = Color(col.r, col.g, col.b, clampf(0.65 + up * 0.35, 0.3, 1.0))
		flat_tri(key, center + a, center + b, center + c, outward, shade, Vector2(a.x + a.z, a.y), Vector2(b.x + b.z, b.y), Vector2(c.x + c.z, c.y))

# =============================================================================
# Risultato
# =============================================================================

func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in _order:
		var st: SurfaceTool = _tools[key]
		mesh = st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials.get(key, WorldMaterials.fallback()))
	return mesh

func instance(parent: Node, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent != null: parent.add_child(mi)
	return mi

func clear() -> void:
	_tools.clear()
	_order.clear()
	xform = Transform3D.IDENTITY
	_normal_basis = Basis.IDENTITY
	_stack.clear()
