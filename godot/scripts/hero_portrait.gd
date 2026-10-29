extends Control
class_name HeroPortrait

## Ritratto a mezzo busto in stile manhwa, disegnato interamente in codice.
## Proporzioni adulte, lineart scura, ombre a due toni (cel shading).
## Capelli, pelle, occhi, abiti e dettagli (barba, cicatrici, età) derivano
## dall'id dell'eroe, quindi lo stesso eroe ha sempre lo stesso volto.
##
## framed = true  → ritratto quadrato con cornice neon del colore di rarità (liste, HUD)
## framed = false → solo figura su fondo trasparente (dentro le carte)

const LINE := Color(0.08, 0.05, 0.06, 0.92)

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
	var left := quad(root_l, (root_l + tip) * 0.5 + bend, tip, 7)
	var right := quad(tip, (root_r + tip) * 0.5 + bend * 0.75, root_r, 7)
	left.remove_at(left.size() - 1)
	left.append_array(right)
	return left

func fill(points: PackedVector2Array, color: Color, outline: bool = true, width_scale: float = 1.0) -> void:
	if points.size() < 3: return
	draw_colored_polygon(points, color)
	if outline:
		var closed_pts := points.duplicate()
		closed_pts.append(points[0])
		draw_polyline(closed_pts, LINE, _line_w * width_scale, true)

func ufill(points, color: Color, outline: bool = true, width_scale: float = 1.0) -> void:
	fill(TA(points), color, outline, width_scale)

func uline(points, color: Color, width_scale: float = 1.0) -> void:
	var pts := TA(points)
	if pts.size() >= 2: draw_polyline(pts, color, _line_w * width_scale, true)

# =============================================================================
# Disegno
# =============================================================================

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0: return
	if framing == "bust":
		_unit = minf(h * 0.38, w * 0.47)
		_origin = Vector2(w * 0.5, h * 0.39)
	else:
		_unit = minf(w, h) * 0.64
		_origin = Vector2(w * 0.5, h * 0.48)
	_line_w = maxf(0.8, _unit * 0.0125)
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
	var fem: bool = look.get("fem", false)
	var style := int(look.get("hair_style", 0))
	_draw_back_hair(style, hair, fem)
	_draw_back_gear(outfit, accent)
	_draw_neck(skin, fem)
	_draw_torso(outfit, accent, skin, fem)
	if style != 4: _draw_ears(skin)
	if style == 4: _draw_hood_back(outfit)
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

# --- Capelli dietro --------------------------------------------------------

func _draw_back_hair(style: int, hair: Color, fem: bool) -> void:
	var dark := hair.darkened(0.3)
	match style:
		1:
			ufill(smooth([Vector2(-0.40, -0.40), Vector2(-0.50, 0.05), Vector2(-0.56, 0.55), Vector2(-0.58, 1.05), Vector2(-0.46, 1.42), Vector2(-0.2, 1.30), Vector2(0.2, 1.30), Vector2(0.46, 1.42), Vector2(0.58, 1.05), Vector2(0.56, 0.55), Vector2(0.50, 0.05), Vector2(0.40, -0.40), Vector2(0, -0.62)], true, 4), dark)
		5:
			ufill(smooth([Vector2(-0.42, -0.38), Vector2(-0.52, 0.1), Vector2(-0.55, 0.55), Vector2(-0.47, 0.86), Vector2(-0.30, 0.78), Vector2(0.30, 0.78), Vector2(0.47, 0.86), Vector2(0.55, 0.55), Vector2(0.52, 0.1), Vector2(0.42, -0.38), Vector2(0, -0.62)], true, 4), dark)
		3:
			# coda che scende dietro una spalla
			ufill(smooth([Vector2(0.30, -0.35), Vector2(0.52, -0.05), Vector2(0.60, 0.45), Vector2(0.55, 0.95), Vector2(0.45, 1.10), Vector2(0.42, 0.7), Vector2(0.36, 0.25), Vector2(0.24, -0.05)], true, 4), dark)
			ufill(smooth([Vector2(-0.41, -0.3), Vector2(-0.42, 0.18), Vector2(-0.3, 0.34), Vector2(0.3, 0.34), Vector2(0.42, 0.18), Vector2(0.41, -0.3), Vector2(0, -0.6)], true, 3), dark)
		_:
			ufill(smooth([Vector2(-0.41, -0.3), Vector2(-0.42, 0.2), Vector2(-0.32, 0.36), Vector2(0.32, 0.36), Vector2(0.42, 0.2), Vector2(0.41, -0.3), Vector2(0, -0.6)], true, 3), dark)

# --- Equipaggiamento dietro le spalle -----------------------------------------

func _draw_back_gear(outfit: Color, accent: Color) -> void:
	match role:
		"Guardian":
			ufill([Vector2(-1.25, 1.0), Vector2(-0.95, 0.80), Vector2(0.95, 0.80), Vector2(1.25, 1.0), Vector2(1.45, 1.8), Vector2(-1.45, 1.8)], accent.darkened(0.35))
		"Vanguard":
			# elsa della spada dietro la spalla destra
			ufill([Vector2(0.62, 0.30), Vector2(0.70, 0.27), Vector2(0.86, 0.86), Vector2(0.78, 0.89)], Color("#3b2a22"))
			ufill([Vector2(0.52, 0.62), Vector2(0.98, 0.50), Vector2(1.0, 0.56), Vector2(0.55, 0.68)], Color("#8a8f99"))
			ufill(ellipse(Vector2(0.65, 0.27), 0.045, 0.045, 10), Color("#b08250"))
		"Ranger":
			for k in 4:
				var x := -0.70 + k * 0.07
				ufill([Vector2(x, 0.45), Vector2(x + 0.05, 0.22 - k * 0.02), Vector2(x + 0.09, 0.47)], Color("#d8cfc0") if k % 2 == 0 else accent.lightened(0.15))
			ufill([Vector2(-0.80, 0.50), Vector2(-0.48, 0.44), Vector2(-0.42, 0.95), Vector2(-0.78, 1.0)], Color("#4a3123"))

# --- Collo --------------------------------------------------------------------

func _draw_neck(skin: Color, fem: bool) -> void:
	var w := 0.15 if fem else 0.18
	ufill([Vector2(-w, 0.25), Vector2(w, 0.25), Vector2(w * 1.12, 0.92), Vector2(-w * 1.12, 0.92)], skin)
	var shade := skin.darkened(0.22)
	ufill([Vector2(-w, 0.30), Vector2(w, 0.30), Vector2(w * 1.05, 0.62), Vector2(0.0, 0.70), Vector2(-w * 1.05, 0.62)], shade, false)
	if not fem:
		uline([Vector2(-0.02, 0.62), Vector2(0.0, 0.70), Vector2(0.03, 0.62)], skin.darkened(0.32), 0.8)

# --- Busto e abiti ------------------------------------------------------------

func _shoulders(drop: float = 0.0) -> Array:
	return [Vector2(-0.20, 0.80), Vector2(-0.62, 0.90 + drop), Vector2(-1.00, 1.08 + drop), Vector2(-1.18, 1.35), Vector2(-1.26, 1.9), Vector2(1.26, 1.9), Vector2(1.18, 1.35), Vector2(1.00, 1.08 + drop), Vector2(0.62, 0.90 + drop), Vector2(0.20, 0.80)]

func _draw_torso(outfit: Color, accent: Color, skin: Color, fem: bool) -> void:
	var lit := outfit.lightened(0.10)
	var shade := outfit.darkened(0.35)
	var body := _shoulders(0.04 if fem else 0.0)
	if fem:
		for i in body.size(): body[i] = Vector2(body[i].x * 0.88, body[i].y)
	match role:
		"Guardian":
			ufill(body, Color("#3d4048"))
			ufill([Vector2(0.15, 0.85), Vector2(0.95, 1.1), Vector2(1.1, 1.9), Vector2(0.2, 1.9)], Color("#2b2e35"), false)
			# corazza e gorgiera
			ufill([Vector2(-0.42, 0.98), Vector2(0.42, 0.98), Vector2(0.50, 1.9), Vector2(-0.50, 1.9)], Color("#7b828e"))
			ufill([Vector2(0.0, 0.98), Vector2(0.42, 0.98), Vector2(0.50, 1.9), Vector2(0.0, 1.9)], Color("#5a606b"), false)
			uline([Vector2(0, 1.0), Vector2(0, 1.9)], Color("#c9ced6"), 1.2)
			ufill([Vector2(-0.30, 0.74), Vector2(0.30, 0.74), Vector2(0.42, 1.0), Vector2(0, 1.08), Vector2(-0.42, 1.0)], Color("#8e95a1"))
			# spallacci
			for side in [-1.0, 1.0]:
				var sp := smooth([Vector2(0.40 * side, 0.92), Vector2(0.75 * side, 0.80), Vector2(1.12 * side, 0.92), Vector2(1.24 * side, 1.25), Vector2(0.95 * side, 1.22), Vector2(0.55 * side, 1.08)], true, 3)
				ufill(sp, Color("#848b97") if side < 0.0 else Color("#5f6570"))
				uline([Vector2(0.55 * side, 0.96), Vector2(0.85 * side, 0.88), Vector2(1.12 * side, 1.02)], Color("#c9ced6") if side < 0.0 else Color("#8d939e"), 1.1)
			if rarity >= 4:
				uline([Vector2(-0.42, 0.98), Vector2(0, 1.08), Vector2(0.42, 0.98)], Color("#d9ae62"), 1.6)
		"Vanguard":
			ufill(body, Color("#3a2a22"))
			ufill([Vector2(0.10, 0.82), Vector2(0.95, 1.08), Vector2(1.1, 1.9), Vector2(0.15, 1.9)], Color("#291d17"), false)
			# camicia aperta sul collo
			ufill([Vector2(-0.22, 0.80), Vector2(0.22, 0.80), Vector2(0.0, 1.25)], skin.darkened(0.08))
			ufill([Vector2(-0.22, 0.78), Vector2(-0.05, 1.22), Vector2(-0.34, 1.06), Vector2(-0.36, 0.84)], Color("#cfc6b4"))
			ufill([Vector2(0.22, 0.78), Vector2(0.05, 1.22), Vector2(0.34, 1.06), Vector2(0.36, 0.84)], Color("#a59c8b"))
			# sciarpa
			var scarf := accent.lerp(Color("#3a3030"), 0.35)
			ufill(smooth([Vector2(-0.34, 0.72), Vector2(0.0, 0.82), Vector2(0.34, 0.72), Vector2(0.40, 0.86), Vector2(0.0, 0.97), Vector2(-0.40, 0.86)], true, 3), scarf)
			uline([Vector2(-0.30, 0.80), Vector2(0.0, 0.89), Vector2(0.30, 0.80)], scarf.darkened(0.4), 0.8)
			ufill([Vector2(-0.30, 0.90), Vector2(-0.18, 0.92), Vector2(-0.24, 1.40), Vector2(-0.36, 1.36)], scarf.darkened(0.2))
			# bandoliera
			ufill([Vector2(-0.95, 1.05), Vector2(-0.82, 0.98), Vector2(0.95, 1.85), Vector2(0.78, 1.92)], Color("#1f1611"))
			ufill(ellipse(Vector2(0.05, 1.42), 0.06, 0.05, 10), Color("#b08250"))
		"Lancer":
			ufill(body, outfit)
			ufill([Vector2(0.10, 0.82), Vector2(0.95, 1.08), Vector2(1.1, 1.9), Vector2(0.15, 1.9)], shade, false)
			for k in 4: uline([Vector2(-1.0, 1.2 + k * 0.17), Vector2(1.0, 1.2 + k * 0.17)], outfit.darkened(0.45), 0.7)
			ufill([Vector2(-0.16, 0.95), Vector2(0.16, 0.95), Vector2(0.20, 1.9), Vector2(-0.20, 1.9)], accent)
			ufill([Vector2(-0.30, 0.66), Vector2(0.30, 0.66), Vector2(0.34, 0.90), Vector2(0, 0.96), Vector2(-0.34, 0.90)], outfit.lightened(0.05))
			for side in [-1.0, 1.0]:
				ufill(smooth([Vector2(0.55 * side, 0.92), Vector2(0.85 * side, 0.86), Vector2(1.12 * side, 1.0), Vector2(1.15 * side, 1.18), Vector2(0.7 * side, 1.08)], true, 3), Color("#7d838d") if side < 0 else Color("#5a6069"))
		"Ranger":
			ufill(body, Color("#3b3326"))
			ufill([Vector2(0.10, 0.82), Vector2(0.95, 1.08), Vector2(1.1, 1.9), Vector2(0.15, 1.9)], Color("#2a241b"), false)
			# cappuccio abbassato attorno al collo
			var hood := accent.lerp(Color("#3b3326"), 0.55).darkened(0.25)
			ufill(smooth([Vector2(-0.58, 0.80), Vector2(-0.28, 0.70), Vector2(0.28, 0.70), Vector2(0.58, 0.80), Vector2(0.70, 0.98), Vector2(0.28, 1.02), Vector2(0, 1.08), Vector2(-0.28, 1.02), Vector2(-0.70, 0.98)], true, 3), hood)
			uline([Vector2(-0.45, 0.90), Vector2(0, 0.97), Vector2(0.45, 0.90)], hood.darkened(0.45), 0.9)
			uline([Vector2(-0.30, 0.76), Vector2(-0.05, 0.82)], hood.lightened(0.2), 0.8)
			ufill([Vector2(0.80, 1.0), Vector2(0.95, 1.08), Vector2(-0.55, 1.9), Vector2(-0.72, 1.85)], Color("#2a1b12"))
		"Mage":
			ufill(body, accent.darkened(0.45))
			ufill([Vector2(0.10, 0.82), Vector2(0.95, 1.08), Vector2(1.1, 1.9), Vector2(0.15, 1.9)], accent.darkened(0.62), false)
			# colletto alto
			ufill([Vector2(-0.36, 0.55), Vector2(-0.20, 0.78), Vector2(0.0, 0.95), Vector2(0.20, 0.78), Vector2(0.36, 0.55), Vector2(0.46, 0.92), Vector2(0, 1.12), Vector2(-0.46, 0.92)], accent.darkened(0.3))
			uline([Vector2(-0.46, 0.92), Vector2(0, 1.12), Vector2(0.46, 0.92)], Color("#d9ae62"), 1.4)
			uline([Vector2(0, 1.12), Vector2(0, 1.9)], Color("#d9ae62"), 1.4)
			ufill(ellipse(Vector2(0, 1.28), 0.07, 0.09, 12), Color("#7fe0ff") if not dead else Color("#777777"))
			draw_circle(T(Vector2(-0.02, 1.25)), _unit * 0.025, Color(1, 1, 1, 0.8))
		"Support":
			ufill(body, Color("#cfc6b6") if not dead else Color("#8b8884"))
			ufill([Vector2(0.10, 0.82), Vector2(0.95, 1.08), Vector2(1.1, 1.9), Vector2(0.15, 1.9)], Color("#a69d8d") if not dead else Color("#6f6c69"), false)
			ufill([Vector2(-0.24, 0.76), Vector2(0.24, 0.76), Vector2(0.0, 0.98)], skin.darkened(0.1))
			for side in [-1.0, 1.0]:
				ufill([Vector2(0.18 * side, 0.78), Vector2(0.32 * side, 0.78), Vector2(0.30 * side, 1.9), Vector2(0.14 * side, 1.9)], accent)
			ufill(ellipse(Vector2(0, 1.26), 0.075, 0.075, 14), Color("#d9ae62"))
			ufill(ellipse(Vector2(0, 1.26), 0.035, 0.035, 10), Color("#fff0c2"), false)
		_:
			ufill(body, outfit)
	# luce di contorno sulla spalla illuminata
	uline([Vector2(-0.22, 0.80), Vector2(-0.62, 0.90), Vector2(-1.0, 1.08)], Color(1, 0.95, 0.85, 0.35), 1.2)

func _draw_ears(skin: Color) -> void:
	for side in [-1.0, 1.0]:
		ufill(ellipse(Vector2(0.355 * side, 0.03), 0.055, 0.11, 12), skin.darkened(0.06 if side < 0 else 0.2))

# --- Volto -----------------------------------------------------------------

func _face_outline(fem: bool) -> Array:
	var right := [Vector2(0.22, -0.48), Vector2(0.31, -0.38), Vector2(0.345, -0.18), Vector2(0.34, 0.04), Vector2(0.31, 0.17)]
	if fem: right.append_array([Vector2(0.255, 0.27), Vector2(0.17, 0.38), Vector2(0.075, 0.455)])
	else: right.append_array([Vector2(0.295, 0.27), Vector2(0.21, 0.385), Vector2(0.095, 0.465)])
	var outline := [Vector2(0, -0.53)]
	outline.append_array(right)
	outline.append(Vector2(0, 0.49 if fem else 0.50))
	outline.append_array(mirror(right))
	return outline

func _draw_face(skin: Color, eyes: Color, hair: Color, fem: bool) -> void:
	var outline := smooth(_face_outline(fem), true, 4)
	ufill(outline, skin)
	# ombra a due toni sul lato destro del viso
	var shade := Color(skin.r * 0.86, skin.g * 0.76, skin.b * 0.76)
	var jaw_x := 0.255 if fem else 0.295
	ufill(smooth([Vector2(0.16, -0.46), Vector2(0.31, -0.38), Vector2(0.345, -0.18), Vector2(0.34, 0.04), Vector2(0.31, 0.17), Vector2(jaw_x, 0.27), Vector2(0.17, 0.39), Vector2(0.09, 0.46), Vector2(0.12, 0.36), Vector2(0.21, 0.22), Vector2(0.25, 0.06), Vector2(0.24, -0.15), Vector2(0.20, -0.33)], true, 3), shade, false)
	# ombra sotto la frangia
	ufill(smooth([Vector2(-0.33, -0.22), Vector2(0, -0.30), Vector2(0.33, -0.22), Vector2(0.32, -0.14), Vector2(0, -0.20), Vector2(-0.32, -0.14)], true, 3), Color(shade.r, shade.g, shade.b, 0.75), false)
	# luce morbida su fronte e naso, guance rosate
	ufill(ellipse(Vector2(-0.06, -0.12), 0.13, 0.08, 16), Color(1, 0.96, 0.9, 0.10), false)
	ufill(ellipse(Vector2(0.0, 0.12), 0.035, 0.09, 12), Color(1, 0.96, 0.9, 0.08), false)
	for side in [-1.0, 1.0]:
		var blush := Color("#e0707a")
		for i in 3:
			ufill(ellipse(Vector2(0.19 * side, 0.19), 0.07 - i * 0.018, 0.035 - i * 0.008, 14), Color(blush.r, blush.g, blush.b, 0.07 + (0.04 if fem else 0.0)), false)
	if look.get("veteran", false):
		uline([Vector2(-0.16, -0.24), Vector2(0, -0.255), Vector2(0.16, -0.24)], skin.darkened(0.28), 0.7)
		for side in [-1.0, 1.0]: uline([Vector2(0.075 * side, 0.235), Vector2(0.115 * side, 0.30), Vector2(0.12 * side, 0.355)], skin.darkened(0.25), 0.8)
	_draw_eyes(eyes, hair, skin, fem)
	# naso
	uline([Vector2(0.015, 0.08), Vector2(0.03, 0.20), Vector2(0.045, 0.235)], Color(skin.darkened(0.35), 0.7), 0.8)
	ufill([Vector2(-0.035, 0.245), Vector2(0.045, 0.235), Vector2(0.02, 0.255), Vector2(-0.02, 0.258)], skin.darkened(0.25), false)
	# bocca
	var mouth_y := 0.335
	if fem:
		ufill(smooth([Vector2(-0.065, mouth_y), Vector2(0, mouth_y - 0.012), Vector2(0.065, mouth_y), Vector2(0, mouth_y + 0.035)], true, 3), skin.lerp(Color("#b3545c"), 0.45), false)
		uline([Vector2(-0.07, mouth_y), Vector2(0, mouth_y + 0.004), Vector2(0.07, mouth_y)], Color("#5e2c2c"), 1.0)
		ufill(ellipse(Vector2(0.012, mouth_y + 0.02), 0.022, 0.007, 8), Color(1, 0.9, 0.9, 0.35), false)
	else:
		uline([Vector2(-0.075, mouth_y), Vector2(-0.02, mouth_y + 0.006), Vector2(0.03, mouth_y + 0.004), Vector2(0.075, mouth_y - 0.006)], Color("#5a302b"), 1.0)
		uline([Vector2(-0.025, mouth_y + 0.05), Vector2(0.03, mouth_y + 0.05)], skin.darkened(0.2), 0.8)
	_draw_beard(hair, skin)
	if look.get("scar", false):
		uline([Vector2(0.11, -0.13), Vector2(0.16, 0.0), Vector2(0.21, 0.16)], Color("#c98b86"), 1.6)
		uline([Vector2(0.115, -0.12), Vector2(0.165, 0.0), Vector2(0.215, 0.15)], Color(0.35, 0.15, 0.15, 0.5), 0.6)

func _eye_points(side: float, fem: bool) -> Dictionary:
	# occhi un po' più grandi e aperti, come nei manhwa
	var c := Vector2(0.137 * side, 0.012)
	var k := 1.14 if fem else 1.08
	var pts := {
		"inner": Vector2(0.05 * side, 0.035),
		"outer": Vector2((0.228 if fem else 0.222) * side, 0.0 if fem else 0.006),
		"top": Vector2(0.135 * side, -0.066 if fem else -0.05),
		"bottom": Vector2(0.14 * side, 0.074 if fem else 0.062),
	}
	for key in pts: pts[key] = c + (pts[key] - c) * k
	return pts

func _eye_shape(side: float, fem: bool) -> Array:
	var e := _eye_points(side, fem)
	var upper := quad(e.inner, e.top, e.outer, 8)
	var lower := quad(e.outer, e.bottom, e.inner, 8)
	var shape: Array = []
	for p in upper: shape.append(p)
	for i in range(1, lower.size() - 1): shape.append(lower[i])
	return shape

func _draw_eyes(eyes: Color, hair: Color, skin: Color, fem: bool) -> void:
	for side in [-1.0, 1.0]:
		var e := _eye_points(side, fem)
		# ombra della palpebra sotto il sopracciglio
		ufill(smooth([Vector2(0.04 * side, 0.0), Vector2(0.13 * side, -0.085), Vector2(0.24 * side, -0.03), Vector2(0.13 * side, -0.04)], true, 3), Color(skin.r * 0.8, skin.g * 0.68, skin.b * 0.7, 0.45), false)
		if dead:
			uline([Vector2(0.055 * side, 0.025), Vector2(0.135 * side, 0.032), Vector2(0.215 * side, 0.01)], LINE, 1.8)
			_draw_brow(side, hair, fem)
			continue
		var shape_px := TA(_eye_shape(side, fem))
		draw_colored_polygon(shape_px, Color("#ece4dc"))
		var iris_c := Vector2(0.137 * side, 0.014)
		var iris_r := 0.058 if fem else 0.051
		for poly in Geometry2D.intersect_polygons(TA(ellipse(iris_c, iris_r, iris_r * 1.1, 20)), shape_px): draw_colored_polygon(poly, eyes.darkened(0.25))
		for poly in Geometry2D.intersect_polygons(TA(ellipse(iris_c + Vector2(0, 0.016), iris_r * 0.78, iris_r * 0.62, 16)), shape_px): draw_colored_polygon(poly, eyes.lightened(0.22))
		for poly in Geometry2D.intersect_polygons(TA(ellipse(iris_c + Vector2(0, 0.024), iris_r * 0.55, iris_r * 0.32, 14)), shape_px): draw_colored_polygon(poly, eyes.lightened(0.45))
		for poly in Geometry2D.intersect_polygons(TA(ellipse(iris_c, iris_r * 0.42, iris_r * 0.55, 12)), shape_px): draw_colored_polygon(poly, Color("#120a0c"))
		draw_arc(T(iris_c), _unit * iris_r * 1.02, 0, TAU, 24, eyes.darkened(0.55), _line_w * 0.7, true)
		# ombra della palpebra superiore sull'occhio
		for poly in Geometry2D.intersect_polygons(TA(smooth([e.inner, e.top + Vector2(0, -0.02), e.outer, e.top + Vector2(0, 0.03)], true, 3)), shape_px): draw_colored_polygon(poly, Color(0.1, 0.05, 0.06, 0.35))
		draw_circle(T(iris_c + Vector2(-0.018 * side + 0.004, -0.014)), _unit * 0.013, Color(1, 1, 1, 0.95))
		draw_circle(T(iris_c + Vector2(0.012 * side, 0.02)), _unit * 0.006, Color(1, 1, 1, 0.6))
		# linea superiore spessa con coda verso l'esterno
		var upper := quad(e.inner, e.top, e.outer, 10)
		var lash := PackedVector2Array()
		for p in upper: lash.append(T(p))
		lash.append(T(Vector2((0.252 if fem else 0.24) * side, -0.018 if fem else -0.006)))
		for i in range(upper.size() - 1, -1, -1):
			var t := float(i) / (upper.size() - 1)
			lash.append(T(upper[i] + Vector2(0.004 * side * t, -(0.007 + 0.022 * t))))
		draw_colored_polygon(lash, Color("#140b0e"))
		uline([Vector2(0.16 * side, 0.066 if fem else 0.056), Vector2(0.215 * side, 0.026)], Color("#3a2522"), 0.9)
		uline([Vector2(0.085 * side, -0.058), Vector2(0.15 * side, -0.082), Vector2(0.215 * side, -0.06)], skin.darkened(0.3), 0.8)
		_draw_brow(side, hair, fem)

func _draw_brow(side: float, hair: Color, fem: bool) -> void:
	var brow_color := hair.darkened(0.4)
	if fem:
		ufill([Vector2(0.045 * side, -0.112), Vector2(0.15 * side, -0.15), Vector2(0.25 * side, -0.118), Vector2(0.15 * side, -0.132), Vector2(0.05 * side, -0.098)], brow_color, false)
	else:
		ufill([Vector2(0.035 * side, -0.092), Vector2(0.16 * side, -0.138), Vector2(0.262 * side, -0.115), Vector2(0.16 * side, -0.108), Vector2(0.045 * side, -0.062)], brow_color, false)

func _draw_beard(hair: Color, skin: Color) -> void:
	var beard := int(look.get("beard", 0))
	if beard == 0: return
	var outer := [Vector2(-0.31, 0.12), Vector2(-0.30, 0.27), Vector2(-0.21, 0.40), Vector2(-0.10, 0.50), Vector2(0, 0.53), Vector2(0.10, 0.50), Vector2(0.21, 0.40), Vector2(0.30, 0.27), Vector2(0.31, 0.12)]
	var inner := [Vector2(0.26, 0.16), Vector2(0.18, 0.33), Vector2(0.07, 0.385), Vector2(0, 0.39), Vector2(-0.07, 0.385), Vector2(-0.18, 0.33), Vector2(-0.26, 0.16)]
	var shape := outer.duplicate()
	shape.append_array(inner)
	if beard == 1:
		ufill(smooth(shape, true, 2), Color(hair.r, hair.g, hair.b, 0.28).lerp(Color(skin.r * 0.6, skin.g * 0.55, skin.b * 0.55, 0.3), 0.4), false)
	else:
		if look.get("veteran", false):
			outer[4] = Vector2(0, 0.60)
			shape = outer.duplicate()
			shape.append_array(inner)
		ufill(smooth(shape, true, 2), hair.darkened(0.1))
		ufill(smooth([Vector2(-0.10, 0.315), Vector2(0, 0.29), Vector2(0.10, 0.315), Vector2(0.06, 0.325), Vector2(0, 0.31), Vector2(-0.06, 0.325)], true, 2), hair.darkened(0.1))

# --- Capelli davanti -------------------------------------------------------

func _cap(spiky: bool, seed: int) -> Array:
	var pts := [Vector2(-0.40, -0.04)]
	var n := 14
	for i in n + 1:
		var a := PI + PI * float(i) / n
		var r := 1.0
		if spiky and i > 1 and i < n - 1 and i % 2 == 1: r = 1.05 + float((seed >> i) & 3) * 0.018
		pts.append(Vector2(cos(a) * 0.41 * r, -0.08 + sin(a) * 0.54 * r))
	pts.append(Vector2(0.40, -0.04))
	pts.append_array([Vector2(0.33, -0.30), Vector2(0.0, -0.40), Vector2(-0.33, -0.30)])
	return pts

func _draw_front_hair(style: int, hair: Color, fem: bool) -> void:
	var seed: int = int(look.get("seed", 0))
	var light := hair.lightened(0.16)
	var dark := hair.darkened(0.22)
	match style:
		0:
			ufill(_cap(true, seed), hair)
			var roots := [-0.36, -0.26, -0.16, -0.05, 0.06, 0.17, 0.27, 0.36]
			for i in roots.size():
				var x: float = roots[i]
				var tip_y := -0.04 + float((seed >> (i * 2)) & 3) * 0.03
				var lean := 0.06 if i % 2 == 0 else -0.05
				ufill(strand(Vector2(x - 0.07, -0.42), Vector2(x + 0.07, -0.42), Vector2(x + lean, tip_y), Vector2(lean * 0.4, 0.02)), hair if i % 3 else dark)
			for side in [-1.0, 1.0]:
				ufill(strand(Vector2(0.33 * side, -0.30), Vector2(0.42 * side, -0.22), Vector2(0.38 * side, 0.20), Vector2(0.03 * side, 0.0)), dark)
			uline([Vector2(-0.30, -0.47), Vector2(-0.18, -0.51), Vector2(-0.08, -0.49), Vector2(0.02, -0.53), Vector2(0.12, -0.5)], light, 1.6)
		1:
			ufill(_cap(false, seed), hair)
			for side in [-1.0, 1.0]:
				ufill(strand(Vector2(0.0, -0.56), Vector2(0.06 * side, -0.56), Vector2(0.34 * side, 0.02), Vector2(0.10 * side, -0.02)), hair)
				ufill(strand(Vector2(0.30 * side, -0.32), Vector2(0.42 * side, -0.2), Vector2(0.46 * side, 1.15), Vector2(0.08 * side, 0.1)), hair)
				ufill(strand(Vector2(0.22 * side, -0.40), Vector2(0.33 * side, -0.34), Vector2(0.36 * side, 0.55), Vector2(0.04 * side, 0.05)), dark)
			uline([Vector2(-0.25, -0.45), Vector2(-0.12, -0.52), Vector2(-0.02, -0.55)], light, 1.6)
			uline([Vector2(0.06, -0.54), Vector2(0.16, -0.50)], light, 1.4)
		2:
			var cap := _cap(false, seed)
			cap[cap.size() - 2] = Vector2(0.0, -0.46)
			cap[cap.size() - 1] = Vector2(-0.32, -0.36)
			cap[cap.size() - 3] = Vector2(0.32, -0.36)
			ufill(cap, hair)
			for k in 4:
				uline([Vector2(-0.24 + k * 0.14, -0.44), Vector2(-0.22 + k * 0.15, -0.56), Vector2(-0.16 + k * 0.15, -0.6)], dark, 0.9)
			ufill(strand(Vector2(0.02, -0.46), Vector2(0.10, -0.46), Vector2(0.10, -0.12), Vector2(0.04, 0.02)), hair)
			ufill(strand(Vector2(-0.08, -0.46), Vector2(0.0, -0.46), Vector2(-0.06, -0.20), Vector2(-0.03, 0.0)), dark)
			uline([Vector2(-0.28, -0.46), Vector2(-0.12, -0.55), Vector2(0.05, -0.57)], light, 1.5)
		3:
			ufill(_cap(false, seed), hair)
			var sweep := [-0.34, -0.22, -0.10, 0.02, 0.14]
			for i in sweep.size():
				var x: float = sweep[i]
				ufill(strand(Vector2(x - 0.04, -0.46), Vector2(x + 0.10, -0.46), Vector2(x + 0.18, -0.06 + i * 0.02), Vector2(0.06, 0.02)), hair if i % 2 == 0 else dark)
			for side in [-1.0, 1.0]:
				ufill(strand(Vector2(0.32 * side, -0.30), Vector2(0.41 * side, -0.22), Vector2(0.37 * side, 0.26 if fem else 0.14), Vector2(0.03 * side, 0.0)), dark)
			uline([Vector2(-0.30, -0.46), Vector2(-0.10, -0.53), Vector2(0.08, -0.52)], light, 1.5)
		4:
			for i in 4:
				var x := -0.20 + i * 0.13
				ufill(strand(Vector2(x - 0.06, -0.36), Vector2(x + 0.06, -0.36), Vector2(x + 0.02, -0.06), Vector2(0.02, 0.02)), hair if i % 2 == 0 else dark)
			for side in [-1.0, 1.0]:
				ufill(strand(Vector2(0.24 * side, -0.30), Vector2(0.34 * side, -0.24), Vector2(0.33 * side, 0.22), Vector2(0.03 * side, 0.0)), dark)
		5:
			ufill(_cap(false, seed), hair)
			var roots := [-0.34, -0.22, -0.08, 0.06, 0.20]
			for i in roots.size():
				var x: float = roots[i]
				ufill(strand(Vector2(x - 0.05, -0.47), Vector2(x + 0.10, -0.47), Vector2(x + 0.16, -0.10 + i * 0.015), Vector2(0.07, 0.03)), hair if i % 2 == 0 else dark)
			for side in [-1.0, 1.0]:
				ufill(strand(Vector2(0.31 * side, -0.32), Vector2(0.43 * side, -0.22), Vector2(0.44 * side, 0.62), Vector2(0.09 * side, 0.12)), hair)
			uline([Vector2(-0.28, -0.47), Vector2(-0.12, -0.53), Vector2(0.02, -0.54)], light, 1.6)

## Luce di contorno sul lato illuminato della testa (colore della rarità).
func _draw_rim_light(style: int) -> void:
	var tint := UIKit.rarity_color(rarity).lerp(Color(1, 0.96, 0.9), 0.45)
	tint.a = 0.55 if not dead else 0.0
	var pts: Array = []
	var rx := 0.43 if style != 4 else 0.60
	var ry := 0.56 if style != 4 else 0.70
	for i in 9:
		var a := PI * 0.98 + PI * 0.45 * float(i) / 8.0
		pts.append(Vector2(cos(a) * rx, -0.08 + sin(a) * ry))
	uline(pts, tint, 1.8)

func _draw_hood_back(outfit: Color) -> void:
	var hood := role_color(outfit).darkened(0.25)
	ufill(smooth([Vector2(-0.56, 0.75), Vector2(-0.58, 0.1), Vector2(-0.46, -0.45), Vector2(0, -0.75), Vector2(0.46, -0.45), Vector2(0.58, 0.1), Vector2(0.56, 0.75), Vector2(0.3, 0.55), Vector2(-0.3, 0.55)], true, 4), hood)
	ufill(smooth([Vector2(-0.44, 0.45), Vector2(-0.46, -0.1), Vector2(-0.34, -0.48), Vector2(0, -0.62), Vector2(0.34, -0.48), Vector2(0.46, -0.1), Vector2(0.44, 0.45), Vector2(0.2, 0.35), Vector2(-0.2, 0.35)], true, 4), Color("#0e0a0d"), false)

func _draw_hood_front(outfit: Color) -> void:
	var hood := role_color(outfit).darkened(0.1)
	ufill(smooth([Vector2(-0.52, -0.05), Vector2(-0.46, -0.42), Vector2(0, -0.66), Vector2(0.46, -0.42), Vector2(0.52, -0.05), Vector2(0.38, -0.28), Vector2(0, -0.44), Vector2(-0.38, -0.28)], true, 4), hood)
	uline([Vector2(-0.38, -0.28), Vector2(0, -0.44), Vector2(0.38, -0.28)], hood.lightened(0.25), 1.0)

func role_color(outfit: Color) -> Color:
	if role == "Mage": return look.get("accent", outfit).darkened(0.35)
	if role == "Ranger": return look.get("accent", outfit).darkened(0.4)
	return outfit
