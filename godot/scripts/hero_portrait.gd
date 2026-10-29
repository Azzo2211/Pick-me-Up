extends Control
class_name HeroPortrait

## Ritratto a mezzo busto in stile manhwa, disegnato interamente in codice.
## Proporzioni adulte, inchiostro a pennello (tratti affusolati con spessore
## variabile), cel shading a due toni con la luce da in alto a sinistra,
## capelli a ciocche sovrapposte con riflesso lucido, occhi a mandorla.
## Capelli, pelle, occhi, abiti e dettagli (barba, cicatrici, età) derivano
## dall'id dell'eroe, quindi lo stesso eroe ha sempre lo stesso volto.
##
## framed = true  → ritratto quadrato con cornice neon del colore di rarità (liste, HUD)
## framed = false → solo figura su fondo trasparente (dentro le carte)

const LINE := Color(0.075, 0.045, 0.055, 0.95)
## Direzione verso cui cadono le ombre (luce da in alto a sinistra).
const SHADOW_DIR := Vector2(0.55, 0.85)

var hero_name := "Hero"
var role := "Guardian"
var rarity := 1
var dead := false
var look: Dictionary = {}
var framed := true
var framing := "face"
var portrait_size := Vector2(96, 96)

var _origin := Vector2.ZERO
var _unit := 1.0
var _line_w := 1.0
var _face_px := PackedVector2Array()

# colori del volto calcolati una volta per disegno
var _skin := Color.WHITE
var _skin_shade := Color.WHITE
var _skin_deep := Color.WHITE
var _skin_line := Color.BLACK
var _hair := Color.BLACK

func setup(hero: Dictionary, size_px: float = 96.0, mode: String = "") -> void:
	hero_name = str(hero.get("name", "Hero"))
	role = str(hero.get("role", "Guardian"))
	rarity = clampi(int(hero.get("current_rarity", hero.get("rarity", 1))), 1, 7)
	dead = str(hero.get("state", "ALIVE")) != "ALIVE"
	look = RiftwardState.appearance_for(hero)
	if mode == "bust":
		framed = false
		framing = "bust"
	elif mode == "bare":
		framed = false
		framing = "face"
	portrait_size = Vector2(size_px, size_px)
	custom_minimum_size = portrait_size
	queue_redraw()

func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO: custom_minimum_size = portrait_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = framed
	if framed:
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

# =============================================================================
# Geometria di supporto
# =============================================================================

func T(p: Vector2) -> Vector2:
	return _origin + p * _unit

func TA(points) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points: out.append(T(p))
	return out

static func quad(a: Vector2, c: Vector2, b: Vector2, n: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out

## Curva morbida (Catmull-Rom) che passa per i punti chiave.
static func smooth(points, closed_shape: bool = true, steps: int = 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = points.size()
	if n < 2: return PackedVector2Array(points)
	var count: int = n if closed_shape else n - 1
	for i in count:
		var p0: Vector2 = points[(i - 1 + n) % n] if closed_shape or i > 0 else points[0]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % n]
		var p3: Vector2 = points[(i + 2) % n] if closed_shape or i + 2 < n else points[n - 1]
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	if not closed_shape: out.append(points[n - 1])
	return out

static func mirror(points: Array) -> Array:
	var out := []
	for i in range(points.size() - 1, -1, -1):
		var p: Vector2 = points[i]
		out.append(Vector2(-p.x, p.y))
	return out

static func ellipse(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n: out.append(c + Vector2(cos(TAU * i / n) * rx, sin(TAU * i / n) * ry))
	return out

## Ciocca di capelli: radice larga, punta affilata, leggermente curva.
static func strand(root_l: Vector2, root_r: Vector2, tip: Vector2, bend: Vector2) -> PackedVector2Array:
	var left := quad(root_l, (root_l + tip) * 0.5 + bend, tip, 9)
	var right := quad(tip, (root_r + tip) * 0.5 + bend * 0.75, root_r, 9)
	left.remove_at(left.size() - 1)
	left.append_array(right)
	return left

static func _offset(points, delta: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points: out.append(p + delta)
	return out

static func _seed_f(seed_value: int, k: int) -> float:
	return float(((seed_value >> (k % 24)) ^ (seed_value * (k + 7))) & 1023) / 1023.0

# =============================================================================
# Pennello: riempimenti sfumati e tratti d'inchiostro affusolati
# =============================================================================

## Riempimento piatto (coordinate in pixel).
func fill(points: PackedVector2Array, color: Color, outline: bool = true, width_scale: float = 1.0) -> void:
	if points.size() < 3: return
	draw_colored_polygon(points, color)
	if outline: _contour_px(points, _line_w * width_scale, LINE)

## Riempimento con chiaroscuro leggero e contorno a spessore variabile (unità).
func ufill(points, color: Color, outline: bool = true, width_scale: float = 1.0) -> void:
	gfill(points, color.lightened(0.09), color.darkened(0.2), outline, width_scale)

## Riempimento sfumato da c_light (in alto a sinistra) a c_dark (in basso a destra).
func gfill(points, c_light: Color, c_dark: Color, outline: bool = true, width_scale: float = 1.0, dir: Vector2 = SHADOW_DIR) -> void:
	var pts := TA(points)
	if pts.size() < 3: return
	var lo := INF
	var hi := -INF
	for p in pts:
		var d := p.dot(dir)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var span := maxf(hi - lo, 0.001)
	var cols := PackedColorArray()
	for p in pts: cols.append(c_light.lerp(c_dark, clampf((p.dot(dir) - lo) / span, 0.0, 1.0)))
	if Geometry2D.triangulate_polygon(pts).is_empty():
		draw_colored_polygon(pts, c_light.lerp(c_dark, 0.5))
	else:
		draw_polygon(pts, cols)
	if outline: _contour_px(pts, _line_w * width_scale, LINE)

## Riempimento piatto in unità, senza contorno.
func flat(points, color: Color) -> void:
	var pts := TA(points)
	if pts.size() >= 3: draw_colored_polygon(pts, color)

## Riempimento ritagliato dentro un'altra forma (in pixel).
func clip_fill(points, clip_px: PackedVector2Array, color: Color) -> void:
	if clip_px.size() < 3: return
	for poly in Geometry2D.intersect_polygons(TA(points), clip_px):
		draw_colored_polygon(poly, color)

func uline(points, color: Color, width_scale: float = 1.0) -> void:
	stroke(points, _line_w * width_scale, color, 0.0, 0.0, false)

## Nastro con bordi sfumati (antialias) e spessore per vertice, in pixel.
func _ribbon(pts: PackedVector2Array, widths: PackedFloat32Array, color: Color, closed: bool = false) -> void:
	var n := pts.size()
	if n < 2: return
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var clear := Color(color.r, color.g, color.b, 0.0)
	var feather := 0.7
	for i in n:
		var prev: Vector2 = pts[(i - 1 + n) % n] if (i > 0 or closed) else pts[i]
		var next: Vector2 = pts[(i + 1) % n] if (i < n - 1 or closed) else pts[i]
		var d := next - prev
		if d.length_squared() < 1e-8: d = Vector2(1, 0)
		var nrm := Vector2(-d.y, d.x).normalized()
		var w := maxf(widths[i] * 0.5, 0.05)
		var a := clampf(widths[i] * 1.6, 0.0, 1.0)
		var core := Color(color.r, color.g, color.b, color.a * a)
		verts.append(pts[i] + nrm * (w + feather))
		verts.append(pts[i] + nrm * w)
		verts.append(pts[i] - nrm * w)
		verts.append(pts[i] - nrm * (w + feather))
		cols.append(clear)
		cols.append(core)
		cols.append(core)
		cols.append(clear)
	var idx := PackedInt32Array()
	var segs := n if closed else n - 1
	for i in segs:
		var a := i * 4
		var b := ((i + 1) % n) * 4
		for k in 3:
			idx.append_array([a + k, a + k + 1, b + k, b + k, a + k + 1, b + k + 1])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, verts, cols)

## Tratto a pennello affusolato lungo una curva (punti in unità, larghezza in pixel).
func stroke(points, width_px: float, color: Color, taper_in: float = 0.3, taper_out: float = 0.45, smooth_it: bool = true) -> void:
	if points.size() < 2: return
	var pts := TA(smooth(points, false, 4) if smooth_it and points.size() > 2 else points)
	var total := 0.0
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		lengths.append(total)
	if total <= 0.0: return
	var widths := PackedFloat32Array()
	for i in pts.size():
		var t := lengths[i] / total
		var k := 1.0
		if taper_in > 0.0: k = minf(k, smoothstep(0.0, taper_in, t))
		if taper_out > 0.0: k = minf(k, smoothstep(0.0, taper_out, 1.0 - t))
		widths.append(width_px * maxf(k, 0.12))
	_ribbon(pts, widths, color)

## Contorno chiuso con spessore maggiore dal lato in ombra (in pixel).
func _contour_px(pts: PackedVector2Array, width_px: float, color: Color) -> void:
	var n := pts.size()
	if n < 3: return
	var area := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var widths := PackedFloat32Array()
	for i in n:
		var d := pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		var outward := Vector2(d.y, -d.x).normalized() * sgn
		var k := clampf(outward.dot(SHADOW_DIR) * 0.5 + 0.5, 0.0, 1.0)
		widths.append(width_px * (0.55 + 0.95 * k))
	_ribbon(pts, widths, color, true)

func contour(points, width_scale: float = 1.0, color: Color = LINE) -> void:
	_contour_px(TA(points), _line_w * width_scale, color)

# =============================================================================
# Disegno
# =============================================================================

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0: return
	if framing == "bust":
		_unit = minf(h * 0.44, w * 0.56)
		_origin = Vector2(w * 0.5, h * 0.36)
	else:
		_unit = minf(w, h) * 0.64
		_origin = Vector2(w * 0.5, h * 0.48)
	_line_w = maxf(0.75, _unit * 0.0115)
	if framed: _draw_backdrop()
	var skin: Color = look.get("skin", Color("#e4c0a2"))
	var hair: Color = look.get("hair", Color("#2a201b"))
	var outfit: Color = look.get("outfit", Color("#3a2e29"))
	var accent: Color = look.get("accent", Color("#8a5a4a"))
	var eyes: Color = look.get("eyes", Color("#4a2c1e"))
	if dead:
		skin = skin.lerp(Color("#9a948f"), 0.55)
		hair = hair.lerp(Color("#5e5a5c"), 0.6)
		outfit = outfit.lerp(Color("#3a3838"), 0.6)
		accent = accent.lerp(Color("#555050"), 0.7)
		eyes = eyes.lerp(Color("#5a5a5a"), 0.7)
	_skin = skin
	_skin_shade = Color(skin.r * 0.84, skin.g * 0.71, skin.b * 0.72)
	_skin_deep = Color(skin.r * 0.68, skin.g * 0.53, skin.b * 0.56)
	_skin_line = Color(skin.r * 0.36, skin.g * 0.2, skin.b * 0.19, 0.95)
	_hair = hair
	var fem: bool = look.get("fem", false)
	var style := int(look.get("hair_style", 0))
	_face_px = TA(smooth(_face_outline(fem), true, 4))
	_draw_back_hair(style, hair, fem)
	_draw_back_gear(outfit, accent)
	if style == 4: _draw_hood_back(outfit)
	_draw_neck(skin, fem)
	_draw_torso(outfit, accent, skin, fem)
	if style != 4 and style != 1: _draw_ears(skin)
	_draw_face(skin, eyes, hair, fem)
	_draw_front_hair(style, hair, fem)
	if style == 4: _draw_hood_front(outfit)
	if framed: _draw_frame()
	if dead:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.06, 0.35))

func _draw_backdrop() -> void:
	var s := size
	var frame := UIKit.rarity_color(rarity)
	draw_rect(Rect2(Vector2.ZERO, s), Color("#0c121c"))
	for i in 6:
		var r := s.x * (0.75 - i * 0.1)
		var c := frame.darkened(0.55)
		c.a = 0.10 + i * 0.03
		draw_circle(Vector2(s.x * 0.5, s.y * 0.42), r, c)
	draw_arc(Vector2(s.x * 0.5, s.y * 0.42), s.x * 0.44, 0, TAU, 40, Color(frame.r, frame.g, frame.b, 0.18), 1.0, true)

func _draw_frame() -> void:
	var s := size
	var frame := UIKit.rarity_color(rarity)
	var cut := s.x * 0.12
	var pts := OrnateStyle.octagon(Rect2(Vector2(1, 1), s - Vector2(2, 2)), cut)
	draw_polyline(OrnateStyle.closed(pts), Color("#1c2a3e"), maxf(2.0, s.x * 0.035), true)
	var inner := OrnateStyle.octagon(Rect2(Vector2(1, 1), s - Vector2(2, 2)).grow(-s.x * 0.05), cut * 0.7)
	draw_polyline(OrnateStyle.closed(inner), Color(frame.r, frame.g, frame.b, 0.75), maxf(1.0, s.x * 0.014), true)
	# angoli tagliati: copre il ritratto oltre la cornice
	for corner in [[Vector2(0, 0), Vector2(cut + 1, 0), Vector2(0, cut + 1)], [Vector2(s.x, 0), Vector2(s.x, cut + 1), Vector2(s.x - cut - 1, 0)], [Vector2(s.x, s.y), Vector2(s.x - cut - 1, s.y), Vector2(s.x, s.y - cut - 1)], [Vector2(0, s.y), Vector2(0, s.y - cut - 1), Vector2(cut + 1, s.y)]]:
		draw_colored_polygon(PackedVector2Array(corner), Color("#070b11"))
	var gem := Vector2(s.x * 0.5, s.y - s.x * 0.035)
	var g := s.x * 0.06
	draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -g), gem + Vector2(g, 0), gem + Vector2(0, g), gem + Vector2(-g, 0)]), frame)
	draw_polyline(PackedVector2Array([gem + Vector2(0, -g), gem + Vector2(g, 0), gem + Vector2(0, g), gem + Vector2(-g, 0), gem + Vector2(0, -g)]), Color("#070b11"), 1.0, true)

# =============================================================================
# Capelli: colori e tecnica comuni
# =============================================================================

func _hair_light(hair: Color) -> Color:
	# riflesso lucido: più freddo sui capelli scuri, più caldo su quelli chiari
	var lum := hair.get_luminance()
	var sheen := hair.lerp(Color(0.72, 0.8, 0.95), 0.3) if lum < 0.25 else hair.lerp(Color(1.0, 0.96, 0.86), 0.35)
	return sheen.lightened(0.22 if lum < 0.25 else 0.12)

## Disegna una massa di capelli (forma in unità): sfumatura, ciocche interne,
## riflesso lucido e contorno a pennello.
func _hair_mass(shape: PackedVector2Array, hair: Color, strands: Array = [], band_y: float = -999.0, outline: bool = true) -> void:
	gfill(shape, hair.lightened(0.07), hair.darkened(0.34), false)
	var px := TA(shape)
	var dark := hair.darkened(0.55)
	var light := _hair_light(hair)
	for s in strands:
		var line: Array = s
		stroke(line, _line_w * 0.65, Color(dark.r, dark.g, dark.b, 0.6), 0.25, 0.55)
	if band_y > -900.0:
		_hair_band(px, light, band_y)
		# riflessi a pennellate lungo il verso dei capelli (dalla nuca verso l'esterno)
		var crown := Vector2(0.0, -0.74)
		for i in 9:
			var x := -0.4 + i * 0.1 + (_seed_f(int(look.get("seed", 0)), i) - 0.5) * 0.04
			var p := Vector2(x, band_y + x * x * 0.35 + 0.012)
			if not Geometry2D.is_point_in_polygon(T(p), px): continue
			var dir := (p - crown).normalized()
			var ln := 0.05 + _seed_f(int(look.get("seed", 0)), i + 5) * 0.04
			stroke([p - dir * ln * 0.4, p + dir * ln], _line_w * 1.1, Color(light.r, light.g, light.b, 0.85), 0.3, 0.6)
	if outline: _contour_px(px, _line_w * 1.05, Color(LINE.r, LINE.g, LINE.b, 0.92).lerp(dark, 0.2))

## Fascia di luce morbida sulla testa (ritagliata dentro la forma).
func _hair_band(shape_px: PackedVector2Array, light: Color, band_y: float) -> void:
	var band: Array = []
	for i in 13:
		var x := -0.55 + i * 0.0917
		band.append(Vector2(x, band_y - 0.03 + sin(x * 9.0) * 0.006 + x * x * 0.35))
	for i in range(12, -1, -1):
		var x := -0.55 + i * 0.0917
		band.append(Vector2(x, band_y + 0.035 + sin(x * 13.0 + 1.0) * 0.01 + x * x * 0.35))
	for poly in Geometry2D.intersect_polygons(TA(band), shape_px):
		draw_colored_polygon(poly, Color(light.r, light.g, light.b, 0.2))

## Ciocca davanti: forma, fili interni, piega scura lungo un lato, riflesso, contorno.
func _hair_lock(points: PackedVector2Array, hair: Color, band_y: float, crease_side: float = 1.0) -> void:
	var px := TA(points)
	gfill(points, hair.lightened(0.06), hair.darkened(0.3), false)
	var n := points.size()
	var half := n / 2
	var dark := hair.darkened(0.6)
	var light := _hair_light(hair)
	if n >= 6:
		# fili interni: curve tra i due bordi, dalla radice verso la punta
		for f in [0.3, 0.62]:
			var line: Array = []
			for i in range(n - 1, half, -1):
				var t := float(n - 1 - i) / float(half)
				if t > 0.82: break
				line.append(points[i].lerp(points[n - 1 - i], f))
			if line.size() >= 2: stroke(line, _line_w * 0.55, Color(dark.r, dark.g, dark.b, 0.5), 0.2, 0.6)
		# piega scura lungo un lato
		var crease: Array = []
		if crease_side > 0.0:
			for i in range(n - 1, half, -1):
				if float(n - 1 - i) / float(half) >= 0.22: crease.append(points[i].lerp(points[n - 1 - i], 0.12))
		else:
			for i in range(0, half):
				if float(i) / float(half) <= 0.78: crease.append(points[i].lerp(points[n - 1 - i], 0.12))
		stroke(crease, _line_w * 0.8, Color(dark.r, dark.g, dark.b, 0.5), 0.25, 0.5)
		# riflesso: una pennellata chiara dove la ciocca attraversa la fascia di luce
		if band_y > -900.0:
			var axis: Array = []
			for i in range(n - 1, half, -1): axis.append(points[i].lerp(points[n - 1 - i], 0.45))
			var hit: Array = []
			for q in axis:
				var pq: Vector2 = q
				if absf(pq.y - (band_y + pq.x * pq.x * 0.35)) < 0.05: hit.append(pq)
			if hit.size() >= 2: stroke(hit, _line_w * 1.3, Color(light.r, light.g, light.b, 0.8), 0.3, 0.5)
	_contour_px(px, _line_w * 0.95, Color(LINE.r, LINE.g, LINE.b, 0.92).lerp(dark, 0.2))

## Ombra portata dalle ciocche sulla fronte (ritagliata sul viso).
func _fringe_shadow(locks: Array) -> void:
	var shade := Color(_skin_shade.r, _skin_shade.g, _skin_shade.b, 0.92)
	for lock in locks:
		var pts: PackedVector2Array = lock
		clip_fill(_offset(pts, Vector2(0.018, 0.045)), _face_px, shade)

func _cap_shape(top: float, spread: float, hairline: float, temple_y: float, jag: float = 0.0) -> PackedVector2Array:
	var seed_value := int(look.get("seed", 0))
	var arc := [Vector2(-spread * 0.98, temple_y)]
	var n := 12
	for i in n + 1:
		var a := PI + PI * float(i) / n
		arc.append(Vector2(cos(a) * spread, -0.08 + sin(a) * (top - 0.08)))
	arc.append(Vector2(spread * 0.98, temple_y))
	var pts := smooth(arc, false, 3)
	if jag > 0.0:
		# sagoma spettinata: ciuffi a punta lungo la calotta (non sulla base)
		var out := PackedVector2Array()
		var center := Vector2(0, -0.08)
		var m := pts.size()
		for i in m:
			var p: Vector2 = pts[i]
			var t := float(i) / float(m - 1)
			var edge := smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.88, t)
			var wave := pow(absf(sin(t * PI * 7.0 + _seed_f(seed_value, 3) * 2.0)), 4.0)
			out.append(center + (p - center) * (1.0 + jag * wave * edge * (0.7 + 0.6 * _seed_f(seed_value, i))))
		pts = out
	var base := smooth([Vector2(spread * 0.98, temple_y), Vector2(spread * 0.8, temple_y - 0.14), Vector2(0.24, hairline - 0.02), Vector2(0.0, hairline), Vector2(-0.24, hairline - 0.02), Vector2(-spread * 0.8, temple_y - 0.14), Vector2(-spread * 0.98, temple_y)], false, 3)
	for i in range(1, base.size() - 1): pts.append(base[i])
	return pts

# --- Capelli dietro --------------------------------------------------------

func _draw_back_hair(style: int, hair: Color, fem: bool) -> void:
	var back := hair.darkened(0.22)
	match style:
		1:
			var shape := smooth([Vector2(-0.42, -0.42), Vector2(-0.52, 0.05), Vector2(-0.58, 0.55), Vector2(-0.62, 1.05), Vector2(-0.56, 1.42), Vector2(-0.44, 1.30), Vector2(-0.30, 1.48), Vector2(-0.12, 1.25), Vector2(0.12, 1.25), Vector2(0.30, 1.48), Vector2(0.44, 1.30), Vector2(0.56, 1.42), Vector2(0.62, 1.05), Vector2(0.58, 0.55), Vector2(0.52, 0.05), Vector2(0.42, -0.42), Vector2(0, -0.64)], true, 4)
			_hair_mass(shape, back, [[Vector2(-0.48, 0.2), Vector2(-0.54, 0.8), Vector2(-0.5, 1.3)], [Vector2(0.48, 0.2), Vector2(0.55, 0.8), Vector2(0.52, 1.3)], [Vector2(-0.4, 0.6), Vector2(-0.42, 1.1)], [Vector2(0.4, 0.6), Vector2(0.43, 1.1)]])
		5:
			var shape := smooth([Vector2(-0.43, -0.4), Vector2(-0.53, 0.1), Vector2(-0.56, 0.5), Vector2(-0.5, 0.82), Vector2(-0.36, 0.72), Vector2(-0.2, 0.8), Vector2(0.2, 0.8), Vector2(0.36, 0.72), Vector2(0.5, 0.82), Vector2(0.56, 0.5), Vector2(0.53, 0.1), Vector2(0.43, -0.4), Vector2(0, -0.64)], true, 4)
			_hair_mass(shape, back, [[Vector2(-0.48, 0.1), Vector2(-0.5, 0.6)], [Vector2(0.48, 0.1), Vector2(0.5, 0.6)]])
		3:
			# coda che scende dietro una spalla
			var tail := smooth([Vector2(0.28, -0.4), Vector2(0.54, -0.1), Vector2(0.64, 0.4), Vector2(0.6, 0.9), Vector2(0.5, 1.18), Vector2(0.47, 0.92), Vector2(0.4, 0.5), Vector2(0.3, 0.1), Vector2(0.2, -0.1)], true, 4)
			_hair_mass(tail, back, [[Vector2(0.44, -0.1), Vector2(0.56, 0.4), Vector2(0.53, 0.95)], [Vector2(0.38, 0.1), Vector2(0.46, 0.6)]])
			_hair_mass(smooth([Vector2(-0.43, -0.3), Vector2(-0.45, -0.05), Vector2(-0.38, 0.06), Vector2(0.38, 0.06), Vector2(0.45, -0.05), Vector2(0.43, -0.3), Vector2(0, -0.64)], true, 3), back)
		4:
			pass
		_:
			_hair_mass(smooth([Vector2(-0.43, -0.3), Vector2(-0.45, -0.05), Vector2(-0.38, 0.08), Vector2(0.38, 0.08), Vector2(0.45, -0.05), Vector2(0.43, -0.3), Vector2(0, -0.64)], true, 3), back, [], -999.0, true)

# --- Equipaggiamento dietro le spalle -----------------------------------------

func _draw_back_gear(outfit: Color, accent: Color) -> void:
	match role:
		"Guardian":
			ufill([Vector2(-1.25, 1.0), Vector2(-0.95, 0.80), Vector2(0.95, 0.80), Vector2(1.25, 1.0), Vector2(1.45, 1.8), Vector2(-1.45, 1.8)], accent.darkened(0.35))
		"Vanguard":
			# elsa della spada dietro la spalla destra
			ufill([Vector2(0.62, 0.30), Vector2(0.70, 0.27), Vector2(0.86, 0.86), Vector2(0.78, 0.89)], Color("#3b2a22"))
			for k in 4: stroke([Vector2(0.64 + k * 0.04, 0.36 + k * 0.13), Vector2(0.72 + k * 0.04, 0.33 + k * 0.13)], _line_w * 0.7, Color(0.1, 0.06, 0.04, 0.8), 0.1, 0.1)
			gfill([Vector2(0.52, 0.62), Vector2(0.98, 0.50), Vector2(1.0, 0.56), Vector2(0.55, 0.68)], Color("#c9ced6"), Color("#6e737d"))
			gfill(ellipse(Vector2(0.65, 0.27), 0.045, 0.045, 12), Color("#e0b06a"), Color("#8a5e30"))
		"Ranger":
			for k in 4:
				var x := -0.70 + k * 0.07
				ufill([Vector2(x, 0.45), Vector2(x + 0.05, 0.22 - k * 0.02), Vector2(x + 0.09, 0.47)], Color("#d8cfc0") if k % 2 == 0 else accent.lightened(0.15))
			ufill([Vector2(-0.80, 0.50), Vector2(-0.48, 0.44), Vector2(-0.42, 0.95), Vector2(-0.78, 1.0)], Color("#4a3123"))
			stroke([Vector2(-0.78, 0.6), Vector2(-0.45, 0.55)], _line_w * 0.8, Color("#b08250"), 0.0, 0.0)

# --- Collo --------------------------------------------------------------------

func _draw_neck(skin: Color, fem: bool) -> void:
	var w := 0.15 if fem else 0.19
	var neck := [Vector2(-w, 0.22), Vector2(w, 0.22), Vector2(w * 1.06, 0.66), Vector2(w * 1.45, 0.95), Vector2(-w * 1.45, 0.95), Vector2(-w * 1.06, 0.66)]
	gfill(neck, skin, _skin_shade, true, 0.9)
	var neck_px := TA(neck)
	# ombra netta sotto la mandibola
	var jaw_shadow := [Vector2(-0.24, 0.26), Vector2(-0.12, 0.42), Vector2(0.0, 0.52), Vector2(0.14, 0.44), Vector2(0.27, 0.27), Vector2(0.3, 0.5), Vector2(0.12, 0.66), Vector2(-0.02, 0.69), Vector2(-0.14, 0.6)]
	clip_fill(smooth(jaw_shadow, true, 3), neck_px, _skin_deep)
	# lato destro del collo in ombra
	clip_fill([Vector2(w * 0.35, 0.3), Vector2(w * 1.2, 0.3), Vector2(w * 1.4, 0.98), Vector2(w * 0.55, 0.98)], neck_px, Color(_skin_shade.r, _skin_shade.g, _skin_shade.b, 0.85))
	if not fem:
		stroke([Vector2(-w * 0.7, 0.58), Vector2(-w * 0.25, 0.86)], _line_w * 0.6, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.45), 0.3, 0.5)
		stroke([Vector2(-0.025, 0.66), Vector2(0.0, 0.72), Vector2(0.03, 0.66)], _line_w * 0.6, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.5), 0.3, 0.3)

# --- Busto e abiti ------------------------------------------------------------

func _shoulders(drop: float = 0.0) -> Array:
	return [Vector2(-0.20, 0.80), Vector2(-0.62, 0.90 + drop), Vector2(-1.00, 1.08 + drop), Vector2(-1.18, 1.35), Vector2(-1.26, 1.9), Vector2(1.26, 1.9), Vector2(1.18, 1.35), Vector2(1.00, 1.08 + drop), Vector2(0.62, 0.90 + drop), Vector2(0.20, 0.80)]

## Pieghe della stoffa: tratti scuri affusolati e qualche luce.
func _folds(color: Color, light: bool = true) -> void:
	var dark := color.darkened(0.55)
	var d := Color(dark.r, dark.g, dark.b, 0.7)
	for f in [[Vector2(-0.95, 1.2), Vector2(-0.82, 1.45), Vector2(-0.85, 1.85)], [Vector2(-0.6, 1.05), Vector2(-0.5, 1.4), Vector2(-0.56, 1.88)], [Vector2(0.62, 1.0), Vector2(0.72, 1.35), Vector2(0.7, 1.85)], [Vector2(0.95, 1.2), Vector2(1.02, 1.5), Vector2(0.98, 1.88)]]:
		stroke(f, _line_w * 0.85, d, 0.2, 0.6)
	if light:
		var l := color.lightened(0.35)
		stroke([Vector2(-0.98, 1.12), Vector2(-0.9, 1.32), Vector2(-0.93, 1.6)], _line_w * 0.7, Color(l.r, l.g, l.b, 0.45), 0.3, 0.6)

func _draw_torso(outfit: Color, accent: Color, skin: Color, fem: bool) -> void:
	var shade := outfit.darkened(0.35)
	var body := _shoulders(0.04 if fem else 0.0)
	if fem:
		for i in body.size(): body[i] = Vector2(body[i].x * 0.88, body[i].y)
	match role:
		"Guardian":
			gfill(body, Color("#4a4e58"), Color("#22252c"))
			# corazza e gorgiera
			gfill([Vector2(-0.42, 0.98), Vector2(0.42, 0.98), Vector2(0.50, 1.9), Vector2(-0.50, 1.9)], Color("#a3abb8"), Color("#4c525d"))
			flat([Vector2(0.06, 0.98), Vector2(0.42, 0.98), Vector2(0.50, 1.9), Vector2(0.08, 1.9)], Color(0.1, 0.11, 0.14, 0.32))
			stroke([Vector2(0, 1.0), Vector2(0, 1.9)], _line_w * 1.2, Color("#e6eaf0"), 0.1, 0.3)
			stroke([Vector2(-0.3, 1.08), Vector2(-0.34, 1.5)], _line_w * 1.6, Color(1, 1, 1, 0.55), 0.3, 0.6)
			contour([Vector2(-0.42, 0.98), Vector2(0.42, 0.98), Vector2(0.50, 1.9), Vector2(-0.50, 1.9)])
			gfill([Vector2(-0.30, 0.74), Vector2(0.30, 0.74), Vector2(0.42, 1.0), Vector2(0, 1.08), Vector2(-0.42, 1.0)], Color("#b3bac6"), Color("#5f6672"))
			# spallacci
			for side in [-1.0, 1.0]:
				var sp := smooth([Vector2(0.40 * side, 0.92), Vector2(0.75 * side, 0.80), Vector2(1.12 * side, 0.92), Vector2(1.24 * side, 1.25), Vector2(0.95 * side, 1.22), Vector2(0.55 * side, 1.08)], true, 3)
				if side < 0.0: gfill(sp, Color("#b8bfcb"), Color("#646b77"))
				else: gfill(sp, Color("#7c838f"), Color("#3c414b"))
				stroke([Vector2(0.55 * side, 0.96), Vector2(0.85 * side, 0.87), Vector2(1.12 * side, 1.0)], _line_w * 1.3, Color(1, 1, 1, 0.75 if side < 0.0 else 0.3), 0.2, 0.4)
			if rarity >= 4:
				stroke([Vector2(-0.42, 0.98), Vector2(0, 1.08), Vector2(0.42, 0.98)], _line_w * 1.6, Color("#e0b46a"), 0.0, 0.0)
		"Vanguard":
			gfill(body, Color("#4a3629"), Color("#1f1611"))
			_folds(Color("#3a2a22"))
			# camicia aperta sul collo
			gfill([Vector2(-0.22, 0.80), Vector2(0.22, 0.80), Vector2(0.0, 1.25)], skin, _skin_shade, false)
			stroke([Vector2(-0.1, 0.95), Vector2(0.0, 1.05), Vector2(0.1, 0.95)], _line_w * 0.6, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.4), 0.3, 0.3)
			gfill([Vector2(-0.22, 0.78), Vector2(-0.05, 1.22), Vector2(-0.34, 1.06), Vector2(-0.36, 0.84)], Color("#e2dacb"), Color("#a59c8b"))
			gfill([Vector2(0.22, 0.78), Vector2(0.05, 1.22), Vector2(0.34, 1.06), Vector2(0.36, 0.84)], Color("#b5ac9b"), Color("#7c7466"))
			# sciarpa
			var scarf := accent.lerp(Color("#3a3030"), 0.35)
			gfill(smooth([Vector2(-0.34, 0.72), Vector2(0.0, 0.82), Vector2(0.34, 0.72), Vector2(0.40, 0.86), Vector2(0.0, 0.97), Vector2(-0.40, 0.86)], true, 3), scarf.lightened(0.12), scarf.darkened(0.3))
			stroke([Vector2(-0.30, 0.80), Vector2(0.0, 0.89), Vector2(0.30, 0.80)], _line_w * 0.8, scarf.darkened(0.55), 0.2, 0.2)
			gfill([Vector2(-0.30, 0.90), Vector2(-0.18, 0.92), Vector2(-0.24, 1.40), Vector2(-0.36, 1.36)], scarf, scarf.darkened(0.4))
			# bandoliera
			gfill([Vector2(-0.95, 1.05), Vector2(-0.82, 0.98), Vector2(0.95, 1.85), Vector2(0.78, 1.92)], Color("#3a2a1e"), Color("#120c08"))
			gfill(ellipse(Vector2(0.05, 1.42), 0.06, 0.05, 12), Color("#e0b06a"), Color("#7a5228"))
		"Lancer":
			gfill(body, outfit.lightened(0.1), outfit.darkened(0.4))
			for k in 4: stroke([Vector2(-1.0, 1.2 + k * 0.17), Vector2(0.0, 1.23 + k * 0.17), Vector2(1.0, 1.2 + k * 0.17)], _line_w * 0.7, Color(0, 0, 0, 0.35), 0.1, 0.1)
			gfill([Vector2(-0.16, 0.95), Vector2(0.16, 0.95), Vector2(0.20, 1.9), Vector2(-0.20, 1.9)], accent.lightened(0.1), accent.darkened(0.35))
			gfill([Vector2(-0.30, 0.66), Vector2(0.30, 0.66), Vector2(0.34, 0.90), Vector2(0, 0.96), Vector2(-0.34, 0.90)], outfit.lightened(0.12), outfit.darkened(0.2))
			for side in [-1.0, 1.0]:
				var sp := smooth([Vector2(0.55 * side, 0.92), Vector2(0.85 * side, 0.86), Vector2(1.12 * side, 1.0), Vector2(1.15 * side, 1.18), Vector2(0.7 * side, 1.08)], true, 3)
				if side < 0: gfill(sp, Color("#a4abb6"), Color("#5c626c"))
				else: gfill(sp, Color("#6d737d"), Color("#3a3f47"))
				stroke([Vector2(0.62 * side, 0.93), Vector2(0.9 * side, 0.9), Vector2(1.08 * side, 1.0)], _line_w * 1.1, Color(1, 1, 1, 0.6 if side < 0 else 0.25), 0.2, 0.4)
		"Ranger":
			gfill(body, Color("#4a4030"), Color("#1d1912"))
			_folds(Color("#3b3326"))
			# cappuccio abbassato attorno al collo
			var hood := accent.lerp(Color("#3b3326"), 0.55).darkened(0.25)
			gfill(smooth([Vector2(-0.58, 0.80), Vector2(-0.28, 0.70), Vector2(0.28, 0.70), Vector2(0.58, 0.80), Vector2(0.70, 0.98), Vector2(0.28, 1.02), Vector2(0, 1.08), Vector2(-0.28, 1.02), Vector2(-0.70, 0.98)], true, 3), hood.lightened(0.15), hood.darkened(0.35))
			stroke([Vector2(-0.45, 0.90), Vector2(0, 0.97), Vector2(0.45, 0.90)], _line_w * 0.9, hood.darkened(0.55), 0.2, 0.2)
			stroke([Vector2(-0.30, 0.76), Vector2(-0.05, 0.82)], _line_w * 0.8, Color(hood.lightened(0.35), 0.6), 0.3, 0.5)
			gfill([Vector2(0.80, 1.0), Vector2(0.95, 1.08), Vector2(-0.55, 1.9), Vector2(-0.72, 1.85)], Color("#43301f"), Color("#160e08"))
		"Mage":
			var robe := accent.darkened(0.45)
			gfill(body, robe.lightened(0.12), robe.darkened(0.45))
			_folds(robe)
			# colletto alto
			gfill([Vector2(-0.36, 0.55), Vector2(-0.20, 0.78), Vector2(0.0, 0.95), Vector2(0.20, 0.78), Vector2(0.36, 0.55), Vector2(0.46, 0.92), Vector2(0, 1.12), Vector2(-0.46, 0.92)], accent.darkened(0.15), accent.darkened(0.5))
			stroke([Vector2(-0.46, 0.92), Vector2(0, 1.12), Vector2(0.46, 0.92)], _line_w * 1.4, Color("#e0b46a"), 0.0, 0.0)
			stroke([Vector2(0, 1.12), Vector2(0, 1.9)], _line_w * 1.4, Color("#e0b46a"), 0.0, 0.0)
			var gem_c := Color("#7fe0ff") if not dead else Color("#777777")
			gfill(ellipse(Vector2(0, 1.28), 0.07, 0.09, 14), gem_c.lightened(0.3), gem_c.darkened(0.45))
			if not dead:
				for i in 3: draw_circle(T(Vector2(0, 1.28)), _unit * (0.16 - i * 0.04), Color(gem_c.r, gem_c.g, gem_c.b, 0.06))
			draw_circle(T(Vector2(-0.02, 1.25)), _unit * 0.022, Color(1, 1, 1, 0.85))
		"Support":
			var robe := Color("#d8d0c0") if not dead else Color("#8b8884")
			gfill(body, robe.lightened(0.08), robe.darkened(0.35))
			_folds(robe, false)
			gfill([Vector2(-0.24, 0.76), Vector2(0.24, 0.76), Vector2(0.0, 0.98)], skin, _skin_shade, false)
			for side in [-1.0, 1.0]:
				gfill([Vector2(0.18 * side, 0.78), Vector2(0.32 * side, 0.78), Vector2(0.30 * side, 1.9), Vector2(0.14 * side, 1.9)], accent.lightened(0.1), accent.darkened(0.35))
			gfill(ellipse(Vector2(0, 1.26), 0.075, 0.075, 14), Color("#f0c878"), Color("#8a6228"))
			flat(ellipse(Vector2(-0.01, 1.25), 0.03, 0.03, 10), Color("#fff4d0"))
		_:
			gfill(body, outfit.lightened(0.1), shade)
	# sagoma del busto: solo il bordo esterno, non la scollatura
	stroke(body, _line_w * 1.15, LINE, 0.0, 0.0, false)
	# luce di contorno sulla spalla illuminata (segue la sagoma del busto)
	var rim: Array = []
	for k in [0, 1, 2, 3]:
		var q: Vector2 = body[k]
		rim.append(q + Vector2(0.012, 0.018))
	if not role in ["Guardian", "Lancer"]: stroke(rim, _line_w * 1.2, Color(1, 0.95, 0.85, 0.4), 0.2, 0.5)

func _draw_ears(skin: Color) -> void:
	for side in [-1.0, 1.0]:
		var ear := smooth([Vector2(0.325 * side, -0.07), Vector2(0.385 * side, -0.1), Vector2(0.41 * side, -0.03), Vector2(0.395 * side, 0.07), Vector2(0.36 * side, 0.14), Vector2(0.325 * side, 0.12)], true, 3)
		if side < 0.0: gfill(ear, skin, _skin_shade, true, 0.8)
		else: gfill(ear, _skin_shade, _skin_deep, true, 0.8)
		stroke([Vector2(0.36 * side, -0.05), Vector2(0.385 * side, 0.0), Vector2(0.372 * side, 0.07), Vector2(0.35 * side, 0.1)], _line_w * 0.7, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.6), 0.2, 0.4)

# --- Volto -----------------------------------------------------------------

func _face_outline(fem: bool) -> Array:
	var right: Array
	if fem:
		right = [Vector2(0.2, -0.49), Vector2(0.295, -0.40), Vector2(0.33, -0.22), Vector2(0.33, -0.05), Vector2(0.315, 0.07), Vector2(0.285, 0.17), Vector2(0.235, 0.27), Vector2(0.165, 0.37), Vector2(0.085, 0.44), Vector2(0.03, 0.473)]
	else:
		right = [Vector2(0.2, -0.49), Vector2(0.3, -0.40), Vector2(0.335, -0.22), Vector2(0.338, -0.05), Vector2(0.326, 0.08), Vector2(0.302, 0.19), Vector2(0.27, 0.285), Vector2(0.19, 0.385), Vector2(0.1, 0.455), Vector2(0.035, 0.488)]
	var outline := [Vector2(0, -0.53)]
	outline.append_array(right)
	outline.append(Vector2(0, 0.48 if fem else 0.496))
	outline.append_array(mirror(right))
	return outline

func _draw_face(skin: Color, eyes: Color, hair: Color, fem: bool) -> void:
	var outline := smooth(_face_outline(fem), true, 4)
	gfill(outline, skin.lightened(0.05), skin.lerp(_skin_shade, 0.35), false, 1.0, Vector2(0.35, 1.0))
	# cel shading: lato destro del viso, sotto lo zigomo e sotto il mento
	var jaw := Vector2(0.235, 0.27) if fem else Vector2(0.27, 0.285)
	var shade_shape := [Vector2(0.15, -0.5), Vector2(0.31, -0.4), Vector2(0.35, -0.2), Vector2(0.35, 0.05), Vector2(0.32, 0.18), jaw, Vector2(0.17, 0.39), Vector2(0.08, 0.47), Vector2(-0.02, 0.5), Vector2(-0.04, 0.46), Vector2(0.06, 0.41), Vector2(0.15, 0.32), Vector2(0.205, 0.2), Vector2(0.23, 0.1), Vector2(0.255, -0.02), Vector2(0.262, -0.16), Vector2(0.235, -0.32)]
	clip_fill(smooth(shade_shape, true, 3), _face_px, _skin_shade)
	# luce morbida su fronte, zigomo sinistro e dorso del naso
	var glow := _skin.lightened(0.35)
	for k in 4:
		var f := 1.0 - k * 0.22
		clip_fill(ellipse(Vector2(-0.1, -0.2), 0.17 * f, 0.1 * f, 20), _face_px, Color(glow.r, glow.g, glow.b, 0.035))
		clip_fill(ellipse(Vector2(-0.17, 0.11), 0.08 * f, 0.045 * f, 16), _face_px, Color(glow.r, glow.g, glow.b, 0.03))
		clip_fill(ellipse(Vector2(0.0, 0.13), 0.022 * f, 0.08 * f, 12), _face_px, Color(glow.r, glow.g, glow.b, 0.04))
	# rossore a tratteggio sottile, solo accennato (niente cerchi rosa)
	if fem and not dead:
		for side in [-1.0, 1.0]:
			for k in 3:
				var c := Vector2((0.13 + k * 0.03) * side, 0.135)
				stroke([c + Vector2(-0.008, 0.012), c + Vector2(0.008, -0.012)], _line_w * 0.55, Color(0.75, 0.3, 0.32, 0.28), 0.3, 0.3)
	if look.get("veteran", false):
		stroke([Vector2(-0.16, -0.25), Vector2(0, -0.265), Vector2(0.16, -0.25)], _line_w * 0.6, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.45), 0.3, 0.3)
		for side in [-1.0, 1.0]:
			stroke([Vector2(0.08 * side, 0.215), Vector2(0.115 * side, 0.29), Vector2(0.125 * side, 0.35)], _line_w * 0.7, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.55), 0.2, 0.5)
			stroke([Vector2(0.2 * side, 0.03), Vector2(0.245 * side, 0.02)], _line_w * 0.5, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.4), 0.3, 0.3)
	_draw_eyes(eyes, hair, skin, fem)
	_draw_nose(fem)
	_draw_mouth(fem)
	_draw_beard(hair, skin)
	if look.get("scar", false):
		stroke([Vector2(0.11, -0.14), Vector2(0.16, 0.0), Vector2(0.21, 0.16)], _line_w * 1.8, Color("#c98b86"), 0.2, 0.3)
		stroke([Vector2(0.118, -0.13), Vector2(0.168, 0.0), Vector2(0.218, 0.15)], _line_w * 0.6, Color(0.35, 0.15, 0.15, 0.6), 0.2, 0.3)
		for k in 3:
			var y := -0.08 + k * 0.08
			var x := 0.13 + k * 0.026
			stroke([Vector2(x - 0.02, y + 0.01), Vector2(x + 0.02, y - 0.01)], _line_w * 0.5, Color(0.4, 0.18, 0.18, 0.5), 0.2, 0.2)
	# contorno del viso: più marcato sulla mandibola in ombra
	_contour_px(_face_px, _line_w * 1.05, LINE)

func _draw_nose(fem: bool) -> void:
	# niente contorno: ombra sul lato destro del dorso, ombra sotto, luce sulla punta
	var tip_y := 0.235 if fem else 0.245
	flat(smooth([Vector2(0.03, 0.02), Vector2(0.06, 0.12), Vector2(0.065, 0.2), Vector2(0.045, tip_y), Vector2(0.025, 0.2), Vector2(0.03, 0.1)], true, 3), Color(_skin_shade.r, _skin_shade.g, _skin_shade.b, 0.9))
	flat(smooth([Vector2(-0.045, tip_y + 0.005), Vector2(0.0, tip_y + 0.022), Vector2(0.055, tip_y + 0.008), Vector2(0.02, tip_y + 0.03), Vector2(-0.02, tip_y + 0.028)], true, 3), Color(_skin_deep.r, _skin_deep.g, _skin_deep.b, 0.85))
	stroke([Vector2(-0.032, tip_y + 0.012), Vector2(0.0, tip_y + 0.024), Vector2(0.04, tip_y + 0.01)], _line_w * 0.85, _skin_line, 0.35, 0.35)
	stroke([Vector2(0.032, 0.06), Vector2(0.05, 0.17)], _line_w * 0.55, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.45), 0.4, 0.5)
	draw_circle(T(Vector2(-0.005, tip_y - 0.022)), _unit * 0.011, Color(1, 1, 1, 0.3))

func _draw_mouth(fem: bool) -> void:
	var y := 0.335 if not fem else 0.33
	if fem:
		var lip := _skin.lerp(Color("#b65a62"), 0.38)
		flat(smooth([Vector2(-0.07, y), Vector2(-0.025, y - 0.017), Vector2(0.0, y - 0.01), Vector2(0.025, y - 0.017), Vector2(0.07, y), Vector2(0.0, y + 0.005)], true, 3), lip.darkened(0.12))
		flat(smooth([Vector2(-0.055, y + 0.004), Vector2(0.0, y + 0.012), Vector2(0.055, y + 0.004), Vector2(0.03, y + 0.036), Vector2(-0.03, y + 0.036)], true, 3), lip)
		stroke([Vector2(-0.072, y - 0.002), Vector2(-0.02, y + 0.006), Vector2(0.02, y + 0.006), Vector2(0.072, y - 0.004)], _line_w * 0.95, Color("#4a2026"), 0.3, 0.3)
		stroke([Vector2(-0.012, y + 0.024), Vector2(0.018, y + 0.022)], _line_w * 0.9, Color(1, 0.92, 0.92, 0.5), 0.3, 0.3)
	else:
		stroke([Vector2(-0.075, y + 0.002), Vector2(-0.02, y + 0.008), Vector2(0.03, y + 0.006), Vector2(0.075, y - 0.004)], _line_w * 1.0, Color("#4d2824"), 0.3, 0.35)
		stroke([Vector2(-0.03, y + 0.048), Vector2(0.0, y + 0.052), Vector2(0.035, y + 0.046)], _line_w * 0.75, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.45), 0.3, 0.3)
		flat(smooth([Vector2(-0.04, y + 0.03), Vector2(0.04, y + 0.03), Vector2(0.02, y + 0.06), Vector2(-0.02, y + 0.06)], true, 3), Color(_skin_shade.r, _skin_shade.g, _skin_shade.b, 0.5))

func _eye_points(side: float, fem: bool) -> Dictionary:
	if fem:
		return {
			"inner": Vector2(0.058 * side, 0.03), "outer": Vector2(0.228 * side, -0.012),
			"top": Vector2(0.13 * side, -0.058), "bottom": Vector2(0.15 * side, 0.052),
		}
	return {
		"inner": Vector2(0.055 * side, 0.026), "outer": Vector2(0.222 * side, -0.004),
		"top": Vector2(0.128 * side, -0.044), "bottom": Vector2(0.148 * side, 0.044),
	}

func _eye_shape(side: float, fem: bool) -> Array:
	var e := _eye_points(side, fem)
	var upper := quad(e.inner, e.top, e.outer, 10)
	var lower := quad(e.outer, e.bottom, e.inner, 10)
	var shape: Array = []
	for p in upper: shape.append(p)
	for i in range(1, lower.size() - 1): shape.append(lower[i])
	return shape

func _draw_eyes(eyes: Color, hair: Color, skin: Color, fem: bool) -> void:
	for side in [-1.0, 1.0]:
		var e := _eye_points(side, fem)
		# incavo: ombra tra sopracciglio e palpebra
		clip_fill(smooth([Vector2(0.045 * side, 0.0), Vector2(0.12 * side, -0.085), Vector2(0.245 * side, -0.04), Vector2(0.2 * side, -0.035), Vector2(0.12 * side, -0.05)], true, 3), _face_px, Color(_skin_shade.r, _skin_shade.g, _skin_shade.b, 0.6))
		if dead:
			stroke([e.inner, (e.inner + e.outer) * 0.5 + Vector2(0, 0.012), e.outer], _line_w * 1.6, LINE, 0.2, 0.3)
			stroke([e.inner + Vector2(0.02 * side, 0.04), e.outer + Vector2(-0.02 * side, 0.05)], _line_w * 0.5, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.4), 0.3, 0.3)
			_draw_brow(side, hair, fem)
			continue
		var shape_px := TA(_eye_shape(side, fem))
		# bianco dell'occhio, più scuro sotto la palpebra
		var sclera := PackedColorArray()
		for p in shape_px: sclera.append(Color("#f2ece6").lerp(Color("#b8aaa6"), clampf(1.0 - (p.y - T(e.top).y) / maxf(T(e.bottom).y - T(e.top).y, 1.0), 0.0, 1.0) * 0.8))
		draw_polygon(shape_px, sclera)
		var iris_c := Vector2(0.138 * side, 0.006)
		var iris_r := 0.05 if fem else 0.045
		# iride: anello scuro, sfumatura dall'alto scuro al basso chiaro, pupilla
		for poly in Geometry2D.intersect_polygons(TA(ellipse(iris_c, iris_r, iris_r * 1.08, 24)), shape_px):
			draw_colored_polygon(poly, eyes.darkened(0.6))
		var inner_iris := TA(ellipse(iris_c, iris_r * 0.84, iris_r * 0.92, 24))
		for poly in Geometry2D.intersect_polygons(inner_iris, shape_px):
			var cols := PackedColorArray()
			for p in poly:
				var t := clampf((p.y - T(iris_c).y) / (_unit * iris_r) * 0.5 + 0.5, 0.0, 1.0)
				cols.append(eyes.darkened(0.35).lerp(eyes.lightened(0.38), t))
			draw_polygon(poly, cols)
		for poly in Geometry2D.intersect_polygons(TA(ellipse(iris_c + Vector2(0, 0.002), iris_r * 0.38, iris_r * 0.46, 14)), shape_px):
			draw_colored_polygon(poly, Color("#0d0709"))
		# ombra della palpebra superiore sull'occhio
		for poly in Geometry2D.intersect_polygons(TA(smooth([e.inner, e.top + Vector2(0, -0.03), e.outer, e.top + Vector2(0.01 * side, 0.026)], true, 3)), shape_px):
			draw_colored_polygon(poly, Color(0.12, 0.05, 0.07, 0.42))
		# riflessi
		draw_circle(T(iris_c + Vector2(-0.016 * side + 0.004, -0.014)), _unit * 0.012, Color(1, 1, 1, 0.95))
		draw_circle(T(iris_c + Vector2(0.014 * side, 0.02)), _unit * 0.0055, Color(1, 1, 1, 0.65))
		# rima superiore: tratto spesso che si allunga oltre l'angolo esterno
		var upper: Array = []
		for p in quad(e.inner + Vector2(0.004 * side, 0.004), e.top + Vector2(0, -0.006), e.outer, 10): upper.append(p)
		upper.append(e.outer + Vector2(0.024 * side, -0.012 if fem else -0.004))
		stroke(upper, _line_w * (2.6 if fem else 2.3), Color("#120a0d"), 0.35, 0.18)
		if fem:
			# piccole ciglia sull'angolo esterno
			for k in 2:
				var base: Vector2 = e.outer + Vector2(-0.012 * side * k, -0.006 - 0.004 * k)
				stroke([base, base + Vector2(0.022 * side, -0.02 + k * 0.006)], _line_w * 0.9, Color("#120a0d"), 0.0, 0.8)
		# rima inferiore leggera sulla metà esterna
		stroke([e.outer + Vector2(-0.005 * side, 0.01), e.bottom + Vector2(0.02 * side, 0.004), e.bottom + Vector2(-0.03 * side, 0.002)], _line_w * 0.8, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.8), 0.15, 0.6)
		# piega della palpebra
		stroke([e.inner + Vector2(0.02 * side, -0.045), e.top + Vector2(0.01 * side, -0.03), e.outer + Vector2(-0.012 * side, -0.035)], _line_w * 0.75, Color(_skin_line.r, _skin_line.g, _skin_line.b, 0.6), 0.4, 0.4)
		# angolo interno rosato
		draw_circle(T(e.inner + Vector2(0.006 * side, 0.0)), _unit * 0.008, Color(0.85, 0.5, 0.5, 0.5))
		_draw_brow(side, hair, fem)

func _draw_brow(side: float, hair: Color, fem: bool) -> void:
	var brow := hair.darkened(0.45).lerp(Color("#1a1012"), 0.35)
	var pts: Array
	if fem:
		pts = [Vector2(0.05 * side, -0.098), Vector2(0.13 * side, -0.13), Vector2(0.2 * side, -0.128), Vector2(0.255 * side, -0.104)]
	else:
		pts = [Vector2(0.04 * side, -0.075), Vector2(0.12 * side, -0.108), Vector2(0.2 * side, -0.112), Vector2(0.262 * side, -0.094)]
	stroke(pts, _line_w * (2.4 if fem else 3.4), brow, 0.05, 0.75)
	# qualche pelo sulla testa del sopracciglio
	if not fem:
		stroke([pts[0] + Vector2(0.004 * side, 0.01), pts[1] + Vector2(-0.02 * side, 0.004)], _line_w * 1.2, Color(brow.r, brow.g, brow.b, 0.6), 0.1, 0.6)

func _draw_beard(hair: Color, skin: Color) -> void:
	var beard := int(look.get("beard", 0))
	if beard == 0: return
	var outer := [Vector2(-0.31, 0.1), Vector2(-0.29, 0.26), Vector2(-0.2, 0.39), Vector2(-0.1, 0.48), Vector2(0, 0.51), Vector2(0.1, 0.48), Vector2(0.2, 0.39), Vector2(0.29, 0.26), Vector2(0.31, 0.1)]
	var inner := [Vector2(0.25, 0.15), Vector2(0.17, 0.32), Vector2(0.07, 0.375), Vector2(0, 0.38), Vector2(-0.07, 0.375), Vector2(-0.17, 0.32), Vector2(-0.25, 0.15)]
	var shape := outer.duplicate()
	shape.append_array(inner)
	if beard == 1:
		# barba corta: velo scuro e piccoli tratti
		clip_fill(smooth(shape, true, 2), _face_px, Color(hair.r * 0.5, hair.g * 0.45, hair.b * 0.45, 0.32))
		var s: int = int(look.get("seed", 0))
		for k in 14:
			var a := -0.9 + k * 0.13
			var p := Vector2(sin(a) * 0.24, 0.3 + cos(a) * 0.14) + Vector2((_seed_f(s, k) - 0.5) * 0.04, (_seed_f(s, k + 9) - 0.5) * 0.04)
			stroke([p, p + Vector2(0.006, 0.02)], _line_w * 0.5, Color(hair.darkened(0.4), 0.5), 0.2, 0.5)
	else:
		if look.get("veteran", false):
			outer[4] = Vector2(0, 0.6)
			shape = outer.duplicate()
			shape.append_array(inner)
		var beard_shape := smooth(shape, true, 2)
		_hair_mass(beard_shape, hair.darkened(0.08), [[Vector2(-0.18, 0.36), Vector2(-0.12, 0.48)], [Vector2(0.0, 0.42), Vector2(0.0, 0.54)], [Vector2(0.18, 0.36), Vector2(0.12, 0.48)]])
		_hair_mass(smooth([Vector2(-0.10, 0.316), Vector2(0, 0.292), Vector2(0.10, 0.316), Vector2(0.06, 0.327), Vector2(0, 0.31), Vector2(-0.06, 0.327)], true, 2), hair.darkened(0.12), [], -999.0, false)

# --- Capelli davanti -------------------------------------------------------

## Ciocche della frangia e laterali per ogni acconciatura (forme in unità).
func _front_locks(style: int, fem: bool, seed_value: int) -> Array:
	var locks: Array = []
	match style:
		0:
			var roots := [-0.36, -0.25, -0.14, -0.03, 0.08, 0.19, 0.29]
			for i in roots.size():
				var x: float = roots[i]
				var tip_y := -0.15 + _seed_f(seed_value, i) * 0.12
				var lean := 0.07 + _seed_f(seed_value, i + 3) * 0.04
				locks.append(strand(Vector2(x - 0.075, -0.5), Vector2(x + 0.075, -0.5), Vector2(x + lean, tip_y), Vector2(lean * 0.35, 0.025)))
			for side in [-1.0, 1.0]:
				locks.append(strand(Vector2(0.31 * side, -0.36), Vector2(0.43 * side, -0.26), Vector2(0.39 * side, 0.12), Vector2(0.035 * side, 0.0)))
		1:
			# riga quasi centrale, frangia laterale e due tende di capelli fino al petto
			locks.append(strand(Vector2(-0.07, -0.62), Vector2(0.06, -0.6), Vector2(0.27, -0.06), Vector2(0.08, -0.05)))
			locks.append(strand(Vector2(0.02, -0.6), Vector2(0.16, -0.56), Vector2(0.36, 0.1), Vector2(0.08, -0.02)))
			locks.append(strand(Vector2(-0.1, -0.62), Vector2(-0.01, -0.62), Vector2(-0.17, -0.14), Vector2(-0.05, -0.03)))
			for side in [-1.0, 1.0]:
				locks.append(strand(Vector2(0.24 * side, -0.46), Vector2(0.44 * side, -0.26), Vector2(0.5 * side, 1.14), Vector2(0.12 * side, 0.1)))
				locks.append(strand(Vector2(0.3 * side, -0.32), Vector2(0.46 * side, -0.12), Vector2(0.58 * side, 0.92), Vector2(0.1 * side, 0.12)))
				locks.append(strand(Vector2(0.2 * side, -0.44), Vector2(0.31 * side, -0.36), Vector2(0.36 * side, 0.42), Vector2(0.05 * side, 0.05)))
		2:
			locks.append(strand(Vector2(0.02, -0.46), Vector2(0.09, -0.46), Vector2(0.11, -0.16), Vector2(0.04, 0.02)))
			locks.append(strand(Vector2(-0.06, -0.46), Vector2(0.0, -0.46), Vector2(-0.03, -0.24), Vector2(-0.02, 0.0)))
		3:
			var sweep := [-0.30, -0.18, -0.06, 0.06, 0.18]
			for i in sweep.size():
				var x: float = sweep[i]
				locks.append(strand(Vector2(x - 0.04, -0.5), Vector2(x + 0.11, -0.5), Vector2(x - 0.06 + _seed_f(seed_value, i) * 0.03, -0.12 + i * 0.012), Vector2(-0.05, 0.02)))
			for side in [-1.0, 1.0]:
				locks.append(strand(Vector2(0.3 * side, -0.34), Vector2(0.42 * side, -0.24), Vector2(0.36 * side, 0.3 if fem else 0.14), Vector2(0.035 * side, 0.0)))
		4:
			for i in 4:
				var x := -0.2 + i * 0.13
				locks.append(strand(Vector2(x - 0.06, -0.4), Vector2(x + 0.07, -0.4), Vector2(x + 0.03, -0.09 + _seed_f(seed_value, i) * 0.05), Vector2(0.02, 0.02)))
			for side in [-1.0, 1.0]:
				locks.append(strand(Vector2(0.24 * side, -0.32), Vector2(0.34 * side, -0.24), Vector2(0.33 * side, 0.22), Vector2(0.03 * side, 0.0)))
		5:
			var roots := [-0.33, -0.2, -0.07, 0.06, 0.19]
			for i in roots.size():
				var x: float = roots[i]
				locks.append(strand(Vector2(x - 0.06, -0.52), Vector2(x + 0.11, -0.52), Vector2(x + 0.13, -0.1 + _seed_f(seed_value, i) * 0.04), Vector2(0.07, 0.03)))
			for side in [-1.0, 1.0]:
				locks.append(strand(Vector2(0.29 * side, -0.38), Vector2(0.43 * side, -0.24), Vector2(0.45 * side, 0.6), Vector2(0.09 * side, 0.1)))
				locks.append(strand(Vector2(0.24 * side, -0.42), Vector2(0.33 * side, -0.34), Vector2(0.37 * side, 0.3), Vector2(0.05 * side, 0.05)))
	return locks

func _draw_front_hair(style: int, hair: Color, fem: bool) -> void:
	var seed_value: int = int(look.get("seed", 0))
	var locks := _front_locks(style, fem, seed_value)
	# le ciocche sopra la fronte proiettano ombra sul viso
	_fringe_shadow(locks)
	var band := -0.47
	match style:
		0:
			var cap := _cap_shape(0.7, 0.46, -0.36, -0.06, 0.09)
			_hair_mass(cap, hair, [[Vector2(-0.2, -0.64), Vector2(-0.3, -0.45)], [Vector2(-0.05, -0.68), Vector2(-0.08, -0.52)], [Vector2(0.12, -0.67), Vector2(0.16, -0.5)], [Vector2(0.28, -0.6), Vector2(0.36, -0.42)]], band)
		1:
			_hair_mass(_cap_shape(0.71, 0.46, -0.4, -0.05), hair, [[Vector2(-0.07, -0.68), Vector2(-0.22, -0.56), Vector2(-0.34, -0.36)], [Vector2(-0.06, -0.68), Vector2(-0.12, -0.5)], [Vector2(-0.04, -0.68), Vector2(0.12, -0.55), Vector2(0.3, -0.38)], [Vector2(-0.03, -0.68), Vector2(0.24, -0.58), Vector2(0.4, -0.3)]], band)
			stroke([Vector2(-0.07, -0.69), Vector2(-0.05, -0.55)], _line_w * 1.0, hair.darkened(0.6), 0.2, 0.5)
		2:
			var cap := _cap_shape(0.71, 0.46, -0.44, -0.1)
			var lines: Array = []
			for k in 11:
				var x := -0.34 + k * 0.068
				var wob := (_seed_f(seed_value, k) - 0.5) * 0.04
				lines.append([Vector2(x, -0.43 + absf(x) * 0.2), Vector2(x * 1.06 + wob, -0.54), Vector2(x * 1.0 + 0.02, -0.62 + absf(x) * 0.1)])
			_hair_mass(cap, hair, lines, band - 0.04)
			# luci sottili lungo il pettinato e due ciocche ribelli
			var light := _hair_light(hair)
			for k in 5:
				var x := -0.24 + k * 0.12
				stroke([Vector2(x, -0.47 + absf(x) * 0.2), Vector2(x * 1.08, -0.58)], _line_w * 0.8, Color(light.r, light.g, light.b, 0.55), 0.3, 0.5)
		3:
			_hair_mass(_cap_shape(0.68, 0.45, -0.4, -0.06, 0.03), hair, [[Vector2(0.2, -0.62), Vector2(0.4, -0.3)], [Vector2(0.05, -0.66), Vector2(0.34, -0.42)], [Vector2(-0.15, -0.64), Vector2(0.2, -0.5)]], band)
		5:
			_hair_mass(_cap_shape(0.7, 0.46, -0.4, -0.05, 0.035), hair, [[Vector2(-0.2, -0.64), Vector2(-0.3, -0.42)], [Vector2(0.05, -0.68), Vector2(0.0, -0.5)], [Vector2(0.24, -0.62), Vector2(0.34, -0.4)]], band)
	var side_first: Array = []
	var front: Array = []
	for i in locks.size():
		var pts: PackedVector2Array = locks[i]
		# le ciocche lunghe ai lati vanno disegnate prima, la frangia sopra
		if pts[pts.size() / 2].y > 0.2: side_first.append(pts)
		else: front.append(pts)
	for pts in side_first: _hair_lock(pts, hair, band, -1.0 if pts[0].x < 0.0 else 1.0)
	for i in front.size(): _hair_lock(front[i], hair, band, 1.0 if i % 2 == 0 else -1.0)
	# luce di contorno sulla testa, colore della rarità
	if not dead and rarity >= 3 and style != 4:
		var tint := UIKit.rarity_color(rarity).lerp(Color(1, 0.96, 0.9), 0.4)
		var arc: Array = []
		for i in 9:
			var a := PI * 1.05 + PI * 0.36 * float(i) / 8.0
			arc.append(Vector2(cos(a) * 0.475, -0.08 + sin(a) * 0.645))
		stroke(arc, _line_w * 1.1, Color(tint.r, tint.g, tint.b, 0.5), 0.35, 0.5)

func _draw_hood_back(outfit: Color) -> void:
	var hood := role_color(outfit).darkened(0.25)
	gfill(smooth([Vector2(-0.58, 0.78), Vector2(-0.6, 0.1), Vector2(-0.48, -0.45), Vector2(0, -0.77), Vector2(0.48, -0.45), Vector2(0.6, 0.1), Vector2(0.58, 0.78), Vector2(0.3, 0.56), Vector2(-0.3, 0.56)], true, 4), hood.lightened(0.12), hood.darkened(0.4))
	var inside := smooth([Vector2(-0.44, 0.45), Vector2(-0.46, -0.1), Vector2(-0.34, -0.48), Vector2(0, -0.62), Vector2(0.34, -0.48), Vector2(0.46, -0.1), Vector2(0.44, 0.45), Vector2(0.2, 0.35), Vector2(-0.2, 0.35)], true, 4)
	gfill(inside, Color("#1a1218"), Color("#07050a"), false)

func _draw_hood_front(outfit: Color) -> void:
	var hood := role_color(outfit).darkened(0.1)
	var rim := smooth([Vector2(-0.54, -0.05), Vector2(-0.48, -0.43), Vector2(0, -0.68), Vector2(0.48, -0.43), Vector2(0.54, -0.05), Vector2(0.39, -0.28), Vector2(0, -0.45), Vector2(-0.39, -0.28)], true, 4)
	gfill(rim, hood.lightened(0.18), hood.darkened(0.3))
	stroke([Vector2(-0.39, -0.29), Vector2(0, -0.455), Vector2(0.39, -0.29)], _line_w * 1.1, Color(hood.lightened(0.35), 0.8), 0.2, 0.3)
	# pieghe del cappuccio
	for f in [[Vector2(-0.46, -0.3), Vector2(-0.52, 0.2), Vector2(-0.5, 0.6)], [Vector2(0.47, -0.25), Vector2(0.54, 0.2), Vector2(0.52, 0.6)], [Vector2(-0.18, -0.6), Vector2(-0.26, -0.52)], [Vector2(0.22, -0.6), Vector2(0.3, -0.5)]]:
		stroke(f, _line_w * 0.9, Color(hood.darkened(0.6), 0.75), 0.2, 0.5)

func role_color(outfit: Color) -> Color:
	if role == "Mage": return look.get("accent", outfit).darkened(0.35)
	if role == "Ranger": return look.get("accent", outfit).darkened(0.4)
	return outfit
