extends Control
class_name TowerMap

## Mappa della Torre: dieci piani per pagina, dal basso verso l'alto, collegati
## da un sentiero a zig-zag. Colori: completato (verde), sbloccato (azzurro),
## piano più alto raggiungibile (ambra), bloccato (grigio). I guardiani
## (ogni 5 piani) hanno un nodo a rombo più grande.

signal floor_selected(floor_index: int)

const PER_PAGE := 10

var first_floor := 1
var max_floor := 1
var selected := 1
var cleared: Dictionary = {}
var _time := 0.0
var _hover := -1

func setup(state: RiftwardState, selected_floor: int) -> TowerMap:
	max_floor = int(state.data.world.max_floor)
	selected = clampi(selected_floor, 1, state.MAX_FLOOR)
	first_floor = int((selected - 1) / PER_PAGE) * PER_PAGE + 1
	for key in state.data.stages:
		if bool(state.data.stages[key].get("cleared", false)): cleared[int(key)] = true
	custom_minimum_size = Vector2(460, 620)
	return self

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func set_page(first: int) -> void:
	first_floor = clampi(first, 1, RiftwardState.MAX_FLOOR - PER_PAGE + 1)
	queue_redraw()

func node_position(floor_index: int) -> Vector2:
	var i := floor_index - first_floor
	var step := (size.y - 80.0) / float(PER_PAGE - 1)
	var x := size.x * (0.3 if i % 2 == 0 else 0.7) + sin(i * 1.7) * size.x * 0.06
	return Vector2(x, size.y - 40.0 - i * step)

func status(floor_index: int) -> String:
	if cleared.has(floor_index): return "cleared"
	if floor_index == max_floor: return "frontier"
	if floor_index < max_floor: return "open"
	return "locked"

func _color(floor_index: int) -> Color:
	match status(floor_index):
		"cleared": return UIKit.TEAL
		"frontier": return UIKit.GOLD
		"open": return UIKit.CYAN
	return Color("#3a4558")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _floor_at(event.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h > 0 and h <= max_floor else Control.CURSOR_ARROW
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var f := _floor_at(event.position)
		if f > 0:
			selected = f
			floor_selected.emit(f)

func _floor_at(p: Vector2) -> int:
	for f in range(first_floor, first_floor + PER_PAGE):
		if node_position(f).distance_to(p) < 26.0: return f
	return -1

func _draw() -> void:
	var font := UIKit.head_font()
	# sentiero
	for f in range(first_floor, first_floor + PER_PAGE - 1):
		var a := node_position(f)
		var b := node_position(f + 1)
		var c := _color(f + 1) if status(f + 1) != "locked" else Color("#243042")
		draw_line(a, b, Color(c, 0.55), 2.0, true)
		# tacche lungo il sentiero
		for k in range(1, 4):
			draw_circle(a.lerp(b, k / 4.0), 1.6, Color(c, 0.6))
	for f in range(first_floor, first_floor + PER_PAGE):
		var p := node_position(f)
		var col := _color(f)
		var boss := f % 5 == 0
		var r := 20.0 if boss else 15.0
		if f == selected:
			draw_arc(p, r + 9.0 + sin(_time * 4.0) * 1.5, 0, TAU, 40, Color(UIKit.WHITE, 0.85), 2.0, true)
		if status(f) == "frontier":
			draw_circle(p, r + 6.0 + sin(_time * 3.0) * 2.0, Color(col, 0.18))
		var shape := PackedVector2Array()
		if boss: shape = PackedVector2Array([p + Vector2(0, -r * 1.2), p + Vector2(r * 1.2, 0), p + Vector2(0, r * 1.2), p + Vector2(-r * 1.2, 0)])
		else:
			for k in 6: shape.append(p + Vector2(cos(TAU * k / 6.0 + PI / 6.0), sin(TAU * k / 6.0 + PI / 6.0)) * r)
		draw_colored_polygon(shape, Color("#0b111b"))
		draw_polyline(OrnateStyle.closed(shape), col, 2.0 if f != _hover else 3.0, true)
		var label := str(f)
		var fs := 15 if boss else 13
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, p + Vector2(-w * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.25))
		var side := -1.0 if p.x > size.x * 0.5 else 1.0
		var tag := "GUARDIANO" if boss else ""
		if status(f) == "cleared": tag = ("GUARDIANO · " if boss else "") + "COMPLETATO"
		elif status(f) == "frontier": tag = ("GUARDIANO · " if boss else "") + "PROSSIMO"
		elif status(f) == "locked": tag = "BLOCCATO"
		if not tag.is_empty():
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var tx := p.x + side * (r + 14.0) - (tw if side < 0 else 0.0)
			draw_string(font, Vector2(tx, p.y + 4.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.85))
