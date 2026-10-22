extends Control
class_name HeroCard

## Carta eroe in stile "sistema": cornice in bronzo, medaglione con l'emblema del Nexus,
## ritratto a mezzo busto, stelle di rarità e targhetta col nome.
## Per i caduti la carta si spegne e riporta la causa della morte.

signal pressed(hero_id: String)

const PortraitScript := preload("res://scripts/hero_portrait.gd")

var hero: Dictionary = {}
var hero_id := ""
var rarity := 1
var dead := false
var caption := ""
var face_down := false
var hovered := false
var portrait: HeroPortrait
var art: Control
var overlay: Control

func setup(data: Dictionary, card_width: float = 180.0, death_caption: String = "") -> HeroCard:
	hero = data
	hero_id = str(data.get("id", ""))
	rarity = clampi(int(data.get("current_rarity", data.get("rarity", 1))), 1, 7)
	dead = str(data.get("state", "ALIVE")) != "ALIVE" or not death_caption.is_empty()
	caption = death_caption
	custom_minimum_size = Vector2(card_width, card_width * 1.55)
	return self

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): hovered = true; queue_redraw())
	mouse_exited.connect(func(): hovered = false; queue_redraw())
	art = Control.new()
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	portrait = PortraitScript.new()
	var data := hero.duplicate()
	if dead: data["state"] = "DEAD"
	portrait.setup(data, 100, "bust")
	art.add_child(portrait)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var w := size.x
	var h := size.y
	var inset := w * 0.075
	art.position = Vector2(inset * 0.62, inset * 0.62)
	art.size = Vector2(w - inset * 1.24, h * 0.84 - inset)
	portrait.position = Vector2.ZERO
	portrait.size = art.size
	portrait.custom_minimum_size = Vector2.ZERO
	portrait.queue_redraw()
	art.visible = not face_down
	queue_redraw()
	if overlay != null: overlay.queue_redraw()

func set_face_down(value: bool) -> void:
	face_down = value
	if art != null: art.visible = not value
	queue_redraw()
	if overlay != null: overlay.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(hero_id)

func _draw() -> void:
	var w := size.x
	var h := size.y
	var color := UIKit.rarity_color(rarity)
	var bronze := Color("#a27a4a") if not dead else Color("#6a5d52")
	var bronze_dark := Color("#4f3a26") if not dead else Color("#3a332e")
	var rect := Rect2(Vector2.ZERO, Vector2(w, h))
	var cut := w * 0.06
	if hovered and not dead:
		for i in 3:
			draw_polyline(OrnateStyle.closed(OrnateStyle.octagon(rect.grow(2.0 + i * 2.5), cut + i)), Color(color.r, color.g, color.b, 0.22 - i * 0.06), 2.0, true)
	# fondo
	draw_colored_polygon(OrnateStyle.octagon(rect, cut), Color("#0d0a0f"))
	var inner := rect.grow(-w * 0.045)
	var bg_top := Color("#1d1622") if not face_down else Color("#1a1320")
	draw_colored_polygon(OrnateStyle.octagon(inner, cut * 0.8), bg_top)
	if face_down:
		_draw_back(inner, color)
	else:
		var glow_center := Vector2(w * 0.5, h * 0.33)
		for i in 7:
			var c := color.darkened(0.5)
			c.a = (0.05 + i * 0.022) * (0.4 if dead else 1.0)
			draw_circle(glow_center, w * (0.62 - i * 0.075), c)
		for i in 3:
			draw_arc(glow_center, w * (0.24 + i * 0.09), 0, TAU, 48, Color(0.69, 0.51, 0.31, 0.16 - i * 0.03), 1.0, true)
		for k in 16:
			var a := TAU * k / 16.0
			draw_line(glow_center + Vector2(cos(a), sin(a)) * w * 0.22, glow_center + Vector2(cos(a), sin(a)) * w * 0.52, Color(0.69, 0.51, 0.31, 0.06), 1.0, true)
	# cornice
	draw_polyline(OrnateStyle.closed(OrnateStyle.octagon(rect.grow(-1.5), cut)), bronze_dark, 3.0, true)
	draw_polyline(OrnateStyle.closed(OrnateStyle.octagon(rect.grow(-2.5), cut)), bronze, 1.6, true)
	draw_polyline(OrnateStyle.closed(OrnateStyle.octagon(inner, cut * 0.8)), Color(color.r, color.g, color.b, 0.55 if not dead else 0.2), 1.2, true)
	_draw_corner_scrolls(rect, bronze)

func _draw_overlay() -> void:
	if face_down: return
	var w := size.x
	var h := size.y
	var color := UIKit.rarity_color(rarity)
	var bronze := Color("#a27a4a") if not dead else Color("#6a5d52")
	var bronze_dark := Color("#4f3a26") if not dead else Color("#3a332e")
	var rect := Rect2(Vector2.ZERO, Vector2(w, h))
	var cut := w * 0.06
	var inner := rect.grow(-w * 0.045)
	var o := overlay
	# sfumatura scura in basso dietro stelle e nome
	var fade := PackedVector2Array([Vector2(inner.position.x, h * 0.62), Vector2(inner.end.x, h * 0.62), Vector2(inner.end.x, inner.end.y), Vector2(inner.position.x, inner.end.y)])
	o.draw_polygon(fade, PackedColorArray([Color(0.05, 0.04, 0.06, 0), Color(0.05, 0.04, 0.06, 0), Color(0.05, 0.04, 0.06, 0.95), Color(0.05, 0.04, 0.06, 0.95)]))
	o.draw_polyline(OrnateStyle.closed(OrnateStyle.octagon(inner, cut * 0.8)), Color(color.r, color.g, color.b, 0.55 if not dead else 0.2), 1.2, true)
	# medaglione in alto
	var medal := Vector2(w * 0.5, w * 0.075)
	var mr := w * 0.085
	o.draw_circle(medal, mr + 2.0, bronze_dark)
	o.draw_circle(medal, mr, Color("#16101a"))
	o.draw_arc(medal, mr, 0, TAU, 28, bronze, 1.6, true)
	_draw_emblem(o, medal, mr * 0.7, color if not dead else Color("#777"))
	# targhetta del nome
	var plate := Rect2(Vector2(w * 0.08, h * 0.83), Vector2(w * 0.84, h * 0.115))
	var notch := plate.size.y * 0.5
	var plate_pts := PackedVector2Array([plate.position + Vector2(notch, 0), Vector2(plate.end.x - notch, plate.position.y), Vector2(plate.end.x, plate.get_center().y), Vector2(plate.end.x - notch, plate.end.y), Vector2(plate.position.x + notch, plate.end.y), Vector2(plate.position.x, plate.get_center().y)])
	o.draw_colored_polygon(plate_pts, Color("#0b080d"))
	o.draw_polyline(OrnateStyle.closed(plate_pts), bronze, 1.4, true)
	for side in [-1.0, 1.0]:
		var tip := Vector2(plate.get_center().x + side * (plate.size.x * 0.5 + 6.0), plate.get_center().y)
		o.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-side * 8.0, -5.0), tip + Vector2(-side * 5.0, 0), tip + Vector2(-side * 8.0, 5.0)]), bronze)
	var font := UIKit.head_font()
	var name_text := str(hero.get("name", "")).to_upper()
	var fs := int(clampf(w * 0.085, 10.0, 22.0))
	var text_w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while text_w > plate.size.x - notch * 2.2 and fs > 8:
		fs -= 1
		text_w = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	o.draw_string(font, Vector2(plate.get_center().x - text_w * 0.5, plate.get_center().y + fs * 0.36), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.INK if not dead else Color("#9a9290"))
	# stelle
	var star_r := w * 0.045
	var total := rarity * star_r * 2.1
	for i in rarity:
		var c := Vector2(w * 0.5 - total * 0.5 + star_r * 1.05 + i * star_r * 2.1, plate.position.y - star_r * 1.2)
		UIKit.draw_star(o, c, star_r, Color("#e6b24c") if not dead else Color("#8c857c"))
	if dead:
		o.draw_colored_polygon(OrnateStyle.octagon(inner, cut * 0.8), Color(0.04, 0.03, 0.05, 0.45))
		var lines := caption.to_upper().split("\n") if not caption.is_empty() else PackedStringArray(["CADUTO"])
		var big := int(clampf(w * 0.13, 12.0, 30.0))
		var y0 := h * 0.42 - (lines.size() - 1) * big * 0.55
		for i in lines.size():
			var line: String = lines[i]
			var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
			while lw > w * 0.86 and big > 9:
				big -= 1
				lw = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
			o.draw_string_outline(font, Vector2(w * 0.5 - lw * 0.5, y0 + i * big * 1.1), line, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 5, Color(0, 0, 0, 0.7))
			o.draw_string(font, Vector2(w * 0.5 - lw * 0.5, y0 + i * big * 1.1), line, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(0.93, 0.89, 0.82, 0.85))

func _draw_corner_scrolls(rect: Rect2, bronze: Color) -> void:
	var w := rect.size.x
	var l := w * 0.16
	for corner in [[rect.position, Vector2(1, 1)], [Vector2(rect.end.x, rect.position.y), Vector2(-1, 1)], [rect.end, Vector2(-1, -1)], [Vector2(rect.position.x, rect.end.y), Vector2(1, -1)]]:
		var o: Vector2 = corner[0] + corner[1] * w * 0.045
		var d: Vector2 = corner[1]
		draw_arc(o + d * w * 0.05, w * 0.05, 0, TAU, 16, Color(bronze.r, bronze.g, bronze.b, 0.7), 1.2, true)
		draw_line(o + Vector2(d.x * w * 0.10, 0), o + Vector2(d.x * l, 0), bronze, 1.2, true)
		draw_line(o + Vector2(0, d.y * w * 0.10), o + Vector2(0, d.y * l), bronze, 1.2, true)
		draw_circle(o + d * w * 0.05, 1.8, bronze.lightened(0.2))

## Emblema originale del Nexus: un varco a losanga attraversato da un taglio.
func _draw_emblem(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.62, 0), c + Vector2(0, r), c + Vector2(-r * 0.62, 0)])
	canvas.draw_colored_polygon(diamond, color.darkened(0.35))
	canvas.draw_polyline(OrnateStyle.closed(diamond), color.lightened(0.2), 1.2, true)
	canvas.draw_line(c + Vector2(-r * 0.25, r * 0.55), c + Vector2(r * 0.25, -r * 0.55), Color(1, 0.97, 0.9, 0.9), maxf(1.0, r * 0.14), true)
	canvas.draw_circle(c, r * 0.16, Color(1, 0.97, 0.9))

func _draw_back(inner: Rect2, color: Color) -> void:
	var c := inner.get_center()
	var w := inner.size.x
	for i in 4:
		draw_arc(c, w * (0.12 + i * 0.09), 0, TAU, 48, Color(0.69, 0.51, 0.31, 0.5 - i * 0.08), 1.2, true)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		draw_line(c + Vector2(cos(a), sin(a)) * w * 0.12, c + Vector2(cos(a), sin(a)) * w * 0.42, Color(0.69, 0.51, 0.31, 0.35), 1.0, true)
	_draw_emblem(self, c, w * 0.12, color)
