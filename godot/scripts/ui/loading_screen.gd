extends Control
class_name LoadingScreen

## Schermata di caricamento del Sistema: anelli HUD che girano, barra di
## avanzamento e una riga di stato. Si usa all'avvio ("connessione al Nexus")
## e prima di una missione ("apertura del varco"). Pochissimo testo.

signal finished

var title_text := "RIFTWARD"
var status_text := "CONNESSIONE AL NEXUS…"
var detail_text := ""
var accent := UIKit.MAGENTA
var progress := 0.0
var _shown := 0.0
var _t := 0.0
var _closing := false

func setup(title: String, status: String, detail: String = "", color: Color = UIKit.MAGENTA) -> Control:
	title_text = title
	status_text = status
	detail_text = detail
	accent = color
	return self

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	_t += delta
	_shown = move_toward(_shown, progress, delta * 1.6)
	queue_redraw()

## Porta la barra a `value` (0–1) e aspetta che ci arrivi.
func advance(value: float, seconds: float = 0.5) -> void:
	progress = clampf(value, 0.0, 1.0)
	var waited := 0.0
	while _shown < progress - 0.001 and waited < seconds + 1.0 and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()

## Riempie la barra, sfuma e si toglie di mezzo.
func close(fade: float = 0.35) -> void:
	if _closing: return
	_closing = true
	await advance(1.0)
	if not is_inside_tree(): return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade)
	await tween.finished
	finished.emit()
	queue_free()

func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color("#06090f"))
	# righe di scansione leggere
	for y in range(0, int(s.y), 4):
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(1, 1, 1, 0.012), 1.0)
	var c := s * 0.5 - Vector2(0, s.y * 0.06)
	var r := minf(s.x, s.y) * 0.17
	for i in 8:
		draw_circle(c, r * (2.2 - i * 0.2), Color(accent, 0.012 + i * 0.006))
	# anelli: magenta esterno, ciano medio, ambra interno
	var rings := [[r * 1.25, accent, 0.5], [r * 0.95, UIKit.CYAN, -0.8], [r * 0.66, UIKit.GOLD, 1.3]]
	for k in rings.size():
		var rr: float = rings[k][0]
		var col: Color = rings[k][1]
		var a: float = _t * float(rings[k][2]) + k
		draw_arc(c, rr, 0, TAU, 96, Color(col, 0.22), 1.2, true)
		draw_arc(c, rr, a, a + PI * 0.9, 48, Color(col, 0.9), 2.2, true)
		draw_arc(c, rr, a + PI * 1.2, a + PI * 1.45, 16, Color(col, 0.7), 2.2, true)
	for k in 60:
		var a := TAU * k / 60.0 + _t * 0.12
		var inner := r * 1.36
		var tick := r * (0.07 if k % 5 == 0 else 0.035)
		draw_line(c + Vector2(cos(a), sin(a)) * inner, c + Vector2(cos(a), sin(a)) * (inner + tick), Color(accent, 0.45), 1.0, true)
	# nucleo: un rombo che pulsa
	var p := 0.5 + 0.5 * sin(_t * 3.0)
	var d := r * (0.2 + 0.03 * p)
	var diamond := PackedVector2Array([c + Vector2(0, -d * 1.3), c + Vector2(d, 0), c + Vector2(0, d * 1.3), c + Vector2(-d, 0)])
	draw_colored_polygon(diamond, Color(accent.lightened(0.3), 0.25 + 0.2 * p))
	draw_polyline(OrnateStyle.closed(diamond), accent.lightened(0.4), 2.0, true)
	# testo
	var title_font := UIKit.title_font()
	var head := UIKit.head_medium()
	var y := c.y + r * 1.75
	_center_text(title_font, title_text, y, 46, UIKit.INK)
	# barra
	var bw := minf(460.0, s.x * 0.6)
	var bar := Rect2(Vector2(s.x * 0.5 - bw * 0.5, y + 26.0), Vector2(bw, 8.0))
	draw_rect(bar, Color("#1a2232"))
	draw_rect(Rect2(bar.position, Vector2(bw * _shown, bar.size.y)), accent)
	draw_rect(Rect2(bar.position + Vector2(bw * _shown - 2.0, -3.0), Vector2(4.0, 14.0)), Color(accent.lightened(0.5), 0.9 if _shown > 0.01 else 0.0))
	var dots := ".".repeat(1 + int(_t * 2.5) % 3)
	_center_text(head, status_text.trim_suffix("…").trim_suffix("...") + dots, bar.position.y + 40.0, 15, UIKit.INK_SOFT)
	if not detail_text.is_empty():
		_center_text(head, detail_text, bar.position.y + 66.0, 13, Color(accent, 0.9))
	# cornice del Sistema
	var m := 26.0
	var frame := Rect2(Vector2(m, m), s - Vector2(m, m) * 2.0)
	var arm := 34.0
	var fc := Color(UIKit.CYAN, 0.55)
	for corner in [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]:
		var sx := 1.0 if corner.x < s.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < s.y * 0.5 else -1.0
		draw_line(corner, corner + Vector2(arm * sx, 0), fc, 2.0)
		draw_line(corner, corner + Vector2(0, arm * sy), fc, 2.0)
	draw_line(Vector2(s.x * 0.5 - 40.0, m), Vector2(s.x * 0.5 + 40.0, m), accent, 3.0)
	draw_string(head, Vector2(m + 14.0, s.y - m - 12.0), "NEXUS · SERVER 13", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UIKit.INK_SOFT, 0.6))
	var pct := "%d%%" % roundi(_shown * 100.0)
	var pw := head.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(head, Vector2(s.x - m - 14.0 - pw, s.y - m - 12.0), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UIKit.INK_SOFT, 0.6))

func _center_text(font: Font, text: String, y: float, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
