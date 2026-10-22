extends StyleBox
class_name OrnateStyle

## Riquadro decorato disegnato in codice: fondo sfumato, angoli smussati,
## doppio bordo, ornamenti agli angoli e alone opzionale.
## Usato per pannelli, pulsanti, finestre di sistema e targhette.

enum Ornament { NONE, BRONZE, SYSTEM, PLATE }

var fill_top := Color("#1d1724")
var fill_bottom := Color("#0f0b13")
var border := Color("#9c7448")
var border_width := 1.6
var inner := Color(0.69, 0.51, 0.31, 0.35)
var inner_inset := 4.0
var chamfer := 6.0
var ornament := Ornament.NONE
var ornament_color := Color("#e2c08a")
var glow := Color(0, 0, 0, 0)
var glow_size := 0.0
var shadow := 0.0

static func make(top: Color, bottom: Color, edge: Color, cut: float = 6.0, padding: float = 12.0) -> OrnateStyle:
	var s := OrnateStyle.new()
	s.fill_top = top
	s.fill_bottom = bottom
	s.border = edge
	s.inner = Color(edge.r, edge.g, edge.b, 0.32)
	s.chamfer = cut
	s.set_padding(padding)
	return s

func set_padding(padding: float, vertical: float = -1.0) -> OrnateStyle:
	content_margin_left = padding
	content_margin_right = padding
	content_margin_top = padding if vertical < 0.0 else vertical
	content_margin_bottom = padding if vertical < 0.0 else vertical
	return self

func duplicate_style() -> OrnateStyle:
	var s := OrnateStyle.new()
	for key in ["fill_top", "fill_bottom", "border", "border_width", "inner", "inner_inset", "chamfer", "ornament", "ornament_color", "glow", "glow_size", "shadow", "content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		s.set(key, get(key))
	return s

static func octagon(r: Rect2, c: float) -> PackedVector2Array:
	c = minf(c, minf(r.size.x, r.size.y) * 0.5)
	var p := r.position
	var e := r.end
	return PackedVector2Array([
		Vector2(p.x + c, p.y), Vector2(e.x - c, p.y), Vector2(e.x, p.y + c), Vector2(e.x, e.y - c),
		Vector2(e.x - c, e.y), Vector2(p.x + c, e.y), Vector2(p.x, e.y - c), Vector2(p.x, p.y + c),
	])

static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out

func _draw(item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if rect.size.x < 2.0 or rect.size.y < 2.0: return
	if shadow > 0.0:
		for i in 4:
			var grown := Rect2(rect.position + Vector2(0, shadow * 0.35), rect.size).grow(shadow * (i + 1) / 4.0)
			rs.canvas_item_add_polygon(item, octagon(grown, chamfer + shadow * 0.5), PackedColorArray([Color(0, 0, 0, 0.10)]))
	if glow.a > 0.0 and glow_size > 0.0:
		for i in 3:
			var g := glow
			g.a = glow.a * (1.0 - i / 3.0) * 0.6
			rs.canvas_item_add_polyline(item, closed(octagon(rect.grow(1.5 + i * glow_size / 3.0), chamfer + i)), PackedColorArray([g]), 2.0 + i, true)
	var pts := octagon(rect, chamfer)
	var colors := PackedColorArray()
	for p in pts: colors.append(fill_top.lerp(fill_bottom, clampf((p.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
	rs.canvas_item_add_polygon(item, pts, colors)
	if inner.a > 0.0 and inner_inset > 0.0 and rect.size.x > inner_inset * 4.0 and rect.size.y > inner_inset * 4.0:
		rs.canvas_item_add_polyline(item, closed(octagon(rect.grow(-inner_inset), maxf(0.0, chamfer - inner_inset * 0.4))), PackedColorArray([inner]), 1.0, true)
	if border.a > 0.0 and border_width > 0.0:
		rs.canvas_item_add_polyline(item, closed(octagon(rect.grow(-border_width * 0.5), chamfer)), PackedColorArray([border]), border_width, true)
	match ornament:
		Ornament.BRONZE: _bronze_corners(item, rect)
		Ornament.SYSTEM: _system_corners(item, rect)
		Ornament.PLATE: _plate_marks(item, rect)

func _diamond(item: RID, center: Vector2, size: float, color: Color) -> void:
	RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([center + Vector2(0, -size), center + Vector2(size, 0), center + Vector2(0, size), center + Vector2(-size, 0)]), PackedColorArray([color]))

func _bronze_corners(item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var c := minf(chamfer, minf(rect.size.x, rect.size.y) * 0.5)
	var corners := [[rect.position, Vector2(1, 1)], [Vector2(rect.end.x, rect.position.y), Vector2(-1, 1)], [rect.end, Vector2(-1, -1)], [Vector2(rect.position.x, rect.end.y), Vector2(1, -1)]]
	var length := minf(26.0, minf(rect.size.x, rect.size.y) * 0.22)
	for corner in corners:
		var o: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		var mid := o + d * c * 0.5
		_diamond(item, mid + d * 1.5, 3.2, ornament_color)
		rs.canvas_item_add_line(item, o + Vector2(d.x * (c + 3.0), d.y * 0.8), o + Vector2(d.x * (c + length), d.y * 0.8), ornament_color, 1.6, true)
		rs.canvas_item_add_line(item, o + Vector2(d.x * 0.8, d.y * (c + 3.0)), o + Vector2(d.x * 0.8, d.y * (c + length)), ornament_color, 1.6, true)
		rs.canvas_item_add_circle(item, o + Vector2(d.x * (c + length + 3.0), d.y * 0.8), 1.4, ornament_color)
		rs.canvas_item_add_circle(item, o + Vector2(d.x * 0.8, d.y * (c + length + 3.0)), 1.4, ornament_color)
	if rect.size.x > 120.0:
		_diamond(item, Vector2(rect.get_center().x, rect.position.y + 0.8), 3.0, ornament_color)
		_diamond(item, Vector2(rect.get_center().x, rect.end.y - 0.8), 3.0, ornament_color)

func _system_corners(item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	var corners := [[rect.position, Vector2(1, 1)], [Vector2(rect.end.x, rect.position.y), Vector2(-1, 1)], [rect.end, Vector2(-1, -1)], [Vector2(rect.position.x, rect.end.y), Vector2(1, -1)]]
	var length := minf(30.0, minf(rect.size.x, rect.size.y) * 0.25)
	for corner in corners:
		var o: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		var bracket := PackedVector2Array([o + Vector2(d.x * length, d.y * 3.0), o + Vector2(d.x * 3.0, d.y * 3.0), o + Vector2(d.x * 3.0, d.y * length)])
		rs.canvas_item_add_polyline(item, bracket, PackedColorArray([ornament_color]), 2.4, true)
		# piccolo ventaglio di schegge verso l'esterno
		for k in 3:
			var angle := atan2(-d.y, -d.x) + (k - 1) * 0.42
			var dir := Vector2(cos(angle), sin(angle))
			var side := Vector2(-dir.y, dir.x)
			var base := o + d * 2.0
			var tip := base + dir * (9.0 if k == 1 else 6.0)
			rs.canvas_item_add_polygon(item, PackedVector2Array([base + side * 1.6, tip, base - side * 1.6]), PackedColorArray([ornament_color]))
		_diamond(item, o + d * 9.0, 2.6, ornament_color)

func _plate_marks(item: RID, rect: Rect2) -> void:
	var y := rect.get_center().y
	_diamond(item, Vector2(rect.position.x + chamfer * 0.5 + 4.0, y), 3.0, ornament_color)
	_diamond(item, Vector2(rect.end.x - chamfer * 0.5 - 4.0, y), 3.0, ornament_color)
