extends Control
class_name HeroCard

## Carta eroe in stile "sistema": cornice neon del colore di rarità, etichetta
## della rarità in alto, ritratto a mezzo busto, stelle e targhetta col nome.
## La cornice cresce con la rarità: 1★–2★ una linea, 3★ doppia, 4★–5★ con
## staffe agli angoli e alone, 6★ alone pulsante e braci che salgono,
## 7★ cornice iridescente che scorre e scintille. 6★ e 7★ si riconoscono
## in mezzo secondo anche senza leggere le stelle.
## Per i caduti la carta si spegne e riporta la causa della morte.

signal pressed(hero_id: String)

const PortraitScript := preload("res://scripts/hero_portrait.gd")
const BG := Color("#080c13")
const BG_INNER := Color("#0e1520")

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
var _time := 0.0

func setup(data: Dictionary, card_width: float = 180.0, death_caption: String = "") -> HeroCard:
	hero = data
	hero_id = str(data.get("id", ""))
	rarity = clampi(int(data.get("current_rarity", data.get("rarity", 1))), 1, 7)
	dead = str(data.get("state", "ALIVE")) != "ALIVE" or not death_caption.is_empty()
	caption = death_caption
	custom_minimum_size = Vector2(card_width, card_width * 1.55)
	_time = float(hash(hero_id) % 997) * 0.01
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
	set_process(_animated())
	_layout()

func _animated() -> bool:
	return rarity >= 6 and not dead

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if overlay != null: overlay.queue_redraw()

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
	# al rilascio: così una carta si può anche trascinare (formazione) senza aprirla
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and get_global_rect().has_point(event.global_position):
		pressed.emit(hero_id)

## Colore della cornice: grigio per i caduti, iridescente per il 7★.
func _frame_color(offset: float = 0.0) -> Color:
	if dead: return Color("#4a5260")
	if rarity >= 7: return UIKit.prism_color(_time, offset)
	return UIKit.rarity_color(rarity)

func _draw() -> void:
	var w := size.x
	var h := size.y
	var color := _frame_color()
	var rect := Rect2(Vector2.ZERO, Vector2(w, h))
	var cut := w * 0.06
	var inner := rect.grow(-w * 0.045)
	# alone esterno: sempre acceso da 4★, pulsante da 6★, più forte al passaggio del mouse
	var halo := 0.0
	if not dead:
		if rarity >= 6: halo = 0.55 + 0.25 * sin(_time * 3.2)
		elif rarity >= 4: halo = 0.35
		if hovered: halo = maxf(halo, 0.6) + 0.2
	if halo > 0.0 and not face_down:
		var rings := 5 if rarity >= 6 else 3
		for i in rings:
			var c := _frame_color(i * 0.04)
			c.a = halo * (0.30 - i * 0.05)
			draw_polyline(OrnateStyle.closed(OrnateStyle.octagon(rect.grow(1.5 + i * 2.5), cut + i)), c, 2.0, true)
	draw_colored_polygon(OrnateStyle.octagon(rect, cut), BG)
	draw_colored_polygon(OrnateStyle.octagon(inner, cut * 0.8), BG_INNER)
	if face_down:
		_draw_back(inner)
	else:
		var glow_center := Vector2(w * 0.5, h * 0.36)
		for i in 7:
			var c := color.darkened(0.55)
			c.a = (0.05 + i * 0.022) * (0.35 if dead else 1.0)
			draw_circle(glow_center, w * (0.62 - i * 0.075), c)
		for i in 3:
			draw_arc(glow_center, w * (0.24 + i * 0.09), 0, TAU, 48, Color(color.r, color.g, color.b, 0.14 - i * 0.03), 1.0, true)
		# griglia tecnica leggera sul fondo
		var grid_c := Color(color.r, color.g, color.b, 0.05)
		var step := w * 0.1
		var x := inner.position.x + step
		while x < inner.end.x:
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), grid_c, 1.0)
			x += step
	_draw_frame(rect, inner, cut)

## Cornice per livello di rarità.
func _draw_frame(rect: Rect2, inner: Rect2, cut: float) -> void:
	var w := rect.size.x
	var color := _frame_color()
	var outer_pts := OrnateStyle.octagon(rect.grow(-1.5), cut)
	if rarity >= 7 and not dead:
		# cornice iridescente: ogni lato ha la sua tinta, che scorre col tempo
		var closed_pts := OrnateStyle.closed(outer_pts)
		for i in outer_pts.size():
			draw_line(closed_pts[i], closed_pts[i + 1], _frame_color(i / 8.0), 3.0, true)
	else:
		var width := 1.2 if rarity <= 2 else 1.8 if rarity <= 5 else 3.0
		draw_polyline(OrnateStyle.closed(outer_pts), Color(color.r, color.g, color.b, 0.9 if not dead else 0.5), width, true)
	if rarity >= 3 or dead:
		draw_polyline(OrnateStyle.closed(OrnateStyle.octagon(inner, cut * 0.8)), Color(color.r, color.g, color.b, 0.45 if not dead else 0.2), 1.0, true)
	if rarity >= 4 and not dead:
		var l := w * 0.2
		for corner in [[rect.position, Vector2(1, 1)], [Vector2(rect.end.x, rect.position.y), Vector2(-1, 1)], [rect.end, Vector2(-1, -1)], [Vector2(rect.position.x, rect.end.y), Vector2(1, -1)]]:
			var o: Vector2 = corner[0]
			var d: Vector2 = corner[1]
			var c := _frame_color(d.x * 0.1 + d.y * 0.2).lightened(0.25)
			draw_polyline(PackedVector2Array([o + Vector2(d.x * (cut + l), d.y * 4.0), o + Vector2(d.x * (cut + 2.0), d.y * 4.0), o + Vector2(d.x * 4.0, d.y * (cut + 2.0)), o + Vector2(d.x * 4.0, d.y * (cut + l))]), c, 2.2, true)

func _draw_overlay() -> void:
	if face_down: return
	var w := size.x
	var h := size.y
	var color := _frame_color()
	var rect := Rect2(Vector2.ZERO, Vector2(w, h))
	var cut := w * 0.06
	var inner := rect.grow(-w * 0.045)
	var o := overlay
	# sfumatura scura in basso dietro stelle e nome
	var fade := PackedVector2Array([Vector2(inner.position.x, h * 0.6), Vector2(inner.end.x, h * 0.6), Vector2(inner.end.x, inner.end.y), Vector2(inner.position.x, inner.end.y)])
	o.draw_polygon(fade, PackedColorArray([Color(BG, 0), Color(BG, 0), Color(BG, 0.96), Color(BG, 0.96)]))
	if _animated(): _draw_particles(o, inner)
	o.draw_polyline(OrnateStyle.closed(OrnateStyle.octagon(inner, cut * 0.8)), Color(color.r, color.g, color.b, 0.45 if not dead else 0.2), 1.0, true)
	var font := UIKit.head_font()
	# etichetta di rarità in alto
	var tag := UIKit.rarity_tag(rarity)
	var tfs := int(clampf(w * 0.058, 8.0, 15.0))
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	var tag_rect := Rect2(Vector2(w * 0.5 - tw * 0.5 - tfs * 0.8, 0.0), Vector2(tw + tfs * 1.6, tfs * 1.7))
	var tn := tag_rect.size.y * 0.45
	var tag_pts := PackedVector2Array([tag_rect.position, Vector2(tag_rect.end.x, tag_rect.position.y), Vector2(tag_rect.end.x - tn, tag_rect.end.y), Vector2(tag_rect.position.x + tn, tag_rect.end.y)])
	o.draw_colored_polygon(tag_pts, BG)
	o.draw_polyline(PackedVector2Array([tag_pts[1], tag_pts[2], tag_pts[3], tag_pts[0]]), Color(color.r, color.g, color.b, 0.9), 1.2, true)
	if rarity >= 6 and not dead: o.draw_colored_polygon(tag_pts, Color(color.r, color.g, color.b, 0.22))
	o.draw_string(font, Vector2(w * 0.5 - tw * 0.5, tag_rect.position.y + tag_rect.size.y * 0.5 + tfs * 0.36), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, color.lightened(0.3) if not dead else Color("#7d8696"))
	# targhetta del nome
	var plate := Rect2(Vector2(w * 0.08, h * 0.83), Vector2(w * 0.84, h * 0.115))
	var notch := plate.size.y * 0.42
	var plate_pts := PackedVector2Array([plate.position + Vector2(notch, 0), Vector2(plate.end.x, plate.position.y), Vector2(plate.end.x, plate.end.y - notch), Vector2(plate.end.x - notch, plate.end.y), Vector2(plate.position.x, plate.end.y), Vector2(plate.position.x, plate.position.y + notch)])
	o.draw_colored_polygon(plate_pts, Color("#060a10"))
	o.draw_polyline(OrnateStyle.closed(plate_pts), Color(color.r, color.g, color.b, 0.85 if not dead else 0.35), 1.2, true)
	o.draw_line(Vector2(plate.position.x + notch + 4.0, plate.end.y - 2.5), Vector2(plate.position.x + plate.size.x * 0.4, plate.end.y - 2.5), Color(color.r, color.g, color.b, 0.6), 2.0, true)
	var name_text := str(hero.get("name", "")).to_upper()
	var fs := int(clampf(w * 0.08, 10.0, 21.0))
	var text_w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while text_w > plate.size.x - notch * 2.2 and fs > 8:
		fs -= 1
		text_w = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	o.draw_string(font, Vector2(plate.get_center().x - text_w * 0.5, plate.get_center().y + fs * 0.36), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.INK if not dead else Color("#8a93a3"))
	# stelle: ambra fino a 5★, poi del colore della rarità
	var star_r := w * 0.045
	var total := rarity * star_r * 2.1
	for i in rarity:
		var c := Vector2(w * 0.5 - total * 0.5 + star_r * 1.05 + i * star_r * 2.1, plate.position.y - star_r * 1.2)
		var star_color := UIKit.GOLD
		if dead: star_color = Color("#6b7380")
		elif rarity >= 7: star_color = UIKit.prism_color(_time, i * 0.08, 1.0)
		elif rarity == 6: star_color = UIKit.rarity_color(6).lightened(0.15)
		UIKit.draw_star(o, c, star_r, star_color)
	if dead:
		o.draw_colored_polygon(OrnateStyle.octagon(inner, cut * 0.8), Color(0.02, 0.03, 0.05, 0.5))
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
			o.draw_string(font, Vector2(w * 0.5 - lw * 0.5, y0 + i * big * 1.1), line, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(1.0, 0.45, 0.5, 0.9))

## 6★: braci che salgono. 7★: scintille a stella che brillano e scorrono.
func _draw_particles(o: Control, inner: Rect2) -> void:
	var count := 14 if rarity == 6 else 18
	for i in count:
		var spark := float(i) * 0.6180339
		var speed := 0.18 + fmod(spark * 7.3, 1.0) * 0.22
		var phase := fmod(_time * speed + spark, 1.0)
		var x := inner.position.x + fmod(spark * 13.7, 1.0) * inner.size.x
		x += sin(_time * 1.3 + i) * inner.size.x * 0.03
		var y := inner.end.y - phase * inner.size.y
		var alpha := sin(phase * PI)
		if rarity == 6:
			var c := Color("#ff6a5a").lerp(UIKit.GOLD, fmod(spark * 3.1, 1.0))
			c.a = alpha * 0.85
			o.draw_circle(Vector2(x, y), 1.2 + fmod(spark * 5.0, 1.0) * 1.6, c)
		else:
			var c := UIKit.prism_color(_time, spark, 1.0)
			c.a = alpha
			var r := 1.5 + fmod(spark * 5.0, 1.0) * 2.5
			o.draw_line(Vector2(x - r, y), Vector2(x + r, y), c, 1.2, true)
			o.draw_line(Vector2(x, y - r), Vector2(x, y + r), c, 1.2, true)
			o.draw_circle(Vector2(x, y), 1.0, Color(1, 1, 1, alpha))

## Emblema originale del Nexus: un varco a losanga attraversato da un taglio.
func _draw_emblem(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.62, 0), c + Vector2(0, r), c + Vector2(-r * 0.62, 0)])
	canvas.draw_colored_polygon(diamond, color.darkened(0.35))
	canvas.draw_polyline(OrnateStyle.closed(diamond), color.lightened(0.2), 1.2, true)
	canvas.draw_line(c + Vector2(-r * 0.25, r * 0.55), c + Vector2(r * 0.25, -r * 0.55), Color(1, 0.97, 0.9, 0.9), maxf(1.0, r * 0.14), true)
	canvas.draw_circle(c, r * 0.16, Color(1, 0.97, 0.9))

## Dorso della carta: anelli del Sistema e l'emblema tinto della rarità che sta per uscire.
func _draw_back(inner: Rect2) -> void:
	var c := inner.get_center()
	var w := inner.size.x
	var hint := UIKit.rarity_color(rarity) if rarity < 7 else UIKit.prism_color(_time)
	for i in 4:
		draw_arc(c, w * (0.12 + i * 0.09), 0, TAU, 48, Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.45 - i * 0.08), 1.2, true)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		draw_line(c + Vector2(cos(a), sin(a)) * w * 0.12, c + Vector2(cos(a), sin(a)) * w * 0.42, Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.25), 1.0, true)
	_draw_emblem(self, c, w * 0.12, hint)
