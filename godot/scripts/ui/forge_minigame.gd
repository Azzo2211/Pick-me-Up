extends Control

## Forgia a mano dell'Armeria: un minigioco di precisione in tre fasi.
## 1. Scalda: il cursore corre sulla barra del calore, fermalo nella zona incandescente.
## 2. Martella: sulla lama compaiono dei punti; un anello si stringe su ognuno,
##    colpisci il punto quando l'anello combacia con il suo bordo.
## 3. Tempra: come la prima fase, ma la zona è più stretta e il cursore più veloce.
## La precisione totale (calore 20%, martello 60%, tempra 20%) decide il grado da F a S,
## limitato dalla difficoltà scelta (vedi FORGE_DIFFICULTIES in game_state.gd).
## Si gioca con il mouse (clic sui punti) o con Spazio / Invio.

signal closed

const GRADE_COLORS := ["#7d8796", "#b08a63", "#7fd16a", "#4fb9ff", "#b57cff", "#f052c8", "#ffbb4d"]
const POINT_RADIUS := 20.0
const RING_START := 86.0
const PHASE_TITLES := {"heat": "1 · SCALDA IL METALLO", "hammer": "2 · MARTELLA I PUNTI", "quench": "3 · TEMPRA"}
const PHASE_HINTS := {
	"heat": "Ferma il cursore nella zona incandescente: clic o Spazio.",
	"hammer": "Colpisci ogni punto quando l'anello tocca il suo bordo.",
	"quench": "Immergi la lama al momento giusto: la zona è più stretta.",
}

var recipe_id := "weapon"
var difficulty := "normal"
var speed := 1.0
var window := 1.0
var hits := 5

var phase := "intro"      # intro → heat → hammer → quench → result
var phase_t := 0.0        # tempo dall'inizio della fase
var active := false       # la fase accetta input (dopo il breve titolo)
var _t := 0.0
var rng := RandomNumberGenerator.new()

# Barra di calore / tempra
var bar_pos := 0.0
var bar_dir := 1.0
var bar_center := 0.5
var bar_half := 0.07
var bar_speed := 0.55
var heat_score := 0.0
var quench_score := 0.0
var _bar_mark := -1.0     # dove il giocatore ha fermato il cursore

# Martello
var points: Array = []    # {pos: Vector2 (0..1 sulla lama), born: float, score: float, done: bool}
var _spawned := 0
var _next_spawn := 0.0
var ring_time := 1.4

# Effetti
var sparks: Array = []
var popups: Array = []
var shake := 0.0

var precision := 0.0
var result_item: Dictionary = {}
var _result_shown := 0.0
var _close_button: Button

func setup(recipe: String, diff: String, window_bonus: float = 1.0) -> Control:
	recipe_id = recipe
	difficulty = diff
	var info: Dictionary = GameState.FORGE_DIFFICULTIES.get(diff, GameState.FORGE_DIFFICULTIES.normal)
	speed = float(info.speed)
	window = float(info.window) * window_bonus
	hits = int(info.hits)
	return self

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	rng.randomize()
	ring_time = 1.45 / speed
	_close_button = UIKit.button("Ritira l'oggetto", _close, "gold", 220)
	_close_button.visible = false
	add_child(_close_button)
	_start_phase("heat")

func _close() -> void:
	closed.emit()
	queue_free()

# =============================================================================
# Fasi
# =============================================================================

func _start_phase(next: String) -> void:
	phase = next
	phase_t = 0.0
	active = false
	_bar_mark = -1.0
	match next:
		"heat":
			bar_half = 0.075 * window
			bar_speed = 0.6 * speed
			_reset_bar()
		"quench":
			bar_half = 0.055 * window
			bar_speed = 0.8 * speed
			_reset_bar()
		"hammer":
			points.clear()
			_spawned = 0
			_next_spawn = 0.0
		"result":
			_finish()

func _reset_bar() -> void:
	bar_center = rng.randf_range(0.2 + bar_half, 0.8 - bar_half)
	bar_pos = rng.randf_range(0.0, 0.15)
	bar_dir = 1.0

func _finish() -> void:
	var hammer_total := 0.0
	for p in points: hammer_total += float(p.score)
	var hammer_avg := hammer_total / maxf(1.0, float(hits))
	precision = clampf(heat_score * 0.2 + hammer_avg * 0.6 + quench_score * 0.2, 0.0, 1.0)
	var result := GameState.finish_forge(precision)
	result_item = result.get("item", {})
	_result_shown = 0.0
	_close_button.visible = true
	shake = 0.5 if int(_grade_index()) >= 5 else 0.0

func _grade_index() -> int:
	return maxi(0, GameState.GRADES.find(str(result_item.get("grade", "F"))))

func _process(delta: float) -> void:
	_t += delta
	phase_t += delta
	shake = maxf(0.0, shake - delta)
	if phase in ["heat", "quench", "hammer"] and not active and phase_t >= 1.1:
		active = true
		phase_t = 0.0
	if active:
		match phase:
			"heat", "quench": _update_bar(delta)
			"hammer": _update_hammer()
	if phase == "result": _result_shown += delta
	for s in sparks:
		var v: Vector2 = s.vel
		v.y += 900.0 * delta
		s.vel = v
		s.pos = s.pos + v * delta
		s.life -= delta
	sparks = sparks.filter(func(s): return s.life > 0.0)
	for p in popups:
		p.life -= delta
		p.pos = p.pos + Vector2(0.0, -40.0 * delta)
	popups = popups.filter(func(p): return p.life > 0.0)
	_place_button()
	queue_redraw()

func _update_bar(delta: float) -> void:
	if _bar_mark >= 0.0:
		if phase_t > 0.9: _start_phase("hammer" if phase == "heat" else "result")
		return
	bar_pos += bar_dir * bar_speed * delta
	if bar_pos >= 1.0:
		bar_pos = 1.0
		bar_dir = -1.0
	elif bar_pos <= 0.0:
		bar_pos = 0.0
		bar_dir = 1.0

func _update_hammer() -> void:
	var interval := ring_time * (0.8 if difficulty in ["easy", "normal"] else 0.6)
	if _spawned < hits and phase_t >= _next_spawn:
		var x := 0.14 + 0.72 * (float(_spawned) + rng.randf_range(0.2, 0.8)) / float(hits)
		points.append({"pos": Vector2(x, rng.randf_range(0.28, 0.72)), "born": phase_t, "score": 0.0, "done": false})
		_spawned += 1
		_next_spawn = phase_t + interval
	var all_done := _spawned >= hits
	for p in points:
		if p.done: continue
		if _ring_radius(p) <= 0.0:
			p.done = true
			_popup("Mancato", _point_screen(p), UIKit.ROSE)
		else: all_done = false
	if all_done and phase_t >= _next_spawn + 0.2:
		_start_phase("quench")

func _ring_radius(p: Dictionary) -> float:
	return RING_START * (1.0 - (phase_t - float(p.born)) / ring_time)

# =============================================================================
# Input
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_strike(event.position, true)
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_strike(Vector2.ZERO, false)
		get_viewport().set_input_as_handled()

func _strike(at: Vector2, from_mouse: bool) -> void:
	if not active: return
	match phase:
		"heat", "quench":
			if _bar_mark >= 0.0: return
			_bar_mark = bar_pos
			phase_t = 0.0
			var d := absf(bar_pos - bar_center) / bar_half
			var score := clampf(1.0 - 0.5 * d, 0.0, 1.0)
			if phase == "heat": heat_score = score
			else: quench_score = score
			var r := _bar_rect()
			var where := Vector2(r.position.x + r.size.x * bar_pos, r.position.y)
			_popup(_rating(score), where, _rating_color(score))
			_burst(where, int(8 + score * 18), Color("#ffb347") if phase == "heat" else Color("#bfe9ff"))
		"hammer":
			var target := {}
			var best := INF
			for p in points:
				if p.done: continue
				var dist := at.distance_to(_point_screen(p)) if from_mouse else float(p.born)  # da tastiera: il punto più vecchio
				if from_mouse and dist > POINT_RADIUS * 2.0: continue
				if dist < best:
					best = dist
					target = p
			if target.is_empty(): return
			var tol := 22.0 * window
			var timing := clampf(1.0 - absf(_ring_radius(target) - POINT_RADIUS) / tol, 0.0, 1.0)
			var aim := 1.0
			if from_mouse: aim = 1.0 - 0.25 * clampf(best / (POINT_RADIUS * 2.0), 0.0, 1.0)
			target.score = timing * aim
			target.done = true
			var where := _point_screen(target)
			_popup(_rating(target.score), where, _rating_color(target.score))
			_burst(where, int(6 + target.score * 26), Color("#ffd27a"))
			shake = maxf(shake, 0.12 * target.score)

func _rating(score: float) -> String:
	if score >= 0.9: return "Perfetto!"
	if score >= 0.75: return "Ottimo"
	if score >= 0.5: return "Buono"
	if score > 0.0: return "Scarso"
	return "Mancato"

func _rating_color(score: float) -> Color:
	if score >= 0.9: return UIKit.GOLD
	if score >= 0.75: return UIKit.TEAL
	if score >= 0.5: return UIKit.SKY
	if score > 0.0: return UIKit.INK_SOFT
	return UIKit.ROSE

func _popup(text: String, pos: Vector2, color: Color) -> void:
	popups.append({"text": text, "pos": pos + Vector2(0, -28), "life": 0.9, "color": color})

func _burst(pos: Vector2, count: int, color: Color) -> void:
	for i in count:
		var angle := rng.randf_range(-PI, 0.0)
		var v := Vector2(cos(angle), sin(angle)) * rng.randf_range(120.0, 420.0)
		sparks.append({"pos": pos, "vel": v, "life": rng.randf_range(0.3, 0.7), "color": color})

# =============================================================================
# Geometria
# =============================================================================

func _panel_rect() -> Rect2:
	var w := minf(size.x - 60.0, 920.0)
	var h := minf(size.y - 60.0, 600.0)
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))

func _anvil_rect() -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position + Vector2(50, 120), Vector2(p.size.x - 100, p.size.y - 260))

func _bar_rect() -> Rect2:
	var p := _panel_rect()
	return Rect2(p.position + Vector2(70, p.size.y - 120), Vector2(p.size.x - 140, 30))

func _point_screen(p: Dictionary) -> Vector2:
	var a := _anvil_rect()
	return a.position + a.size * Vector2(p.pos)

func _place_button() -> void:
	if not is_instance_valid(_close_button): return
	var p := _panel_rect()
	_close_button.size = _close_button.get_combined_minimum_size()
	_close_button.position = Vector2(p.get_center().x - _close_button.size.x * 0.5, p.end.y - 70)

# =============================================================================
# Disegno
# =============================================================================

func _draw() -> void:
	var offset := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake * 40.0 if shake > 0.0 else Vector2.ZERO
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.82))
	draw_set_transform(offset)
	var p := _panel_rect()
	draw_style_box(UIKit.ornate("card", 12.0), p)
	var head := UIKit.head_font()
	var body := UIKit.body_bold()
	var recipe: Dictionary = GameState.FORGE_RECIPES.get(recipe_id, {})
	var diff_name := str(GameState.FORGE_DIFFICULTIES.get(difficulty, {}).get("name", ""))
	draw_string(head, p.position + Vector2(30, 46), "FORGIA · %s" % str(recipe.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UIKit.GOLD)
	draw_string(body, p.position + Vector2(p.size.x - 30, 44), "Difficoltà %s" % diff_name, HORIZONTAL_ALIGNMENT_RIGHT, -1, 16, UIKit.INK_SOFT)
	_draw_steps(p)
	if phase == "result":
		_draw_result(p)
	else:
		_draw_anvil()
		if phase == "hammer": _draw_points()
		if phase in ["heat", "quench"]: _draw_bar()
		draw_string(head, Vector2(p.position.x, p.position.y + 108), PHASE_TITLES.get(phase, ""), HORIZONTAL_ALIGNMENT_CENTER, p.size.x, 22, UIKit.CYAN)
		draw_string(body, Vector2(p.position.x, p.end.y - 34), PHASE_HINTS.get(phase, ""), HORIZONTAL_ALIGNMENT_CENTER, p.size.x, 16, UIKit.INK_SOFT)
		if not active:
			var a := clampf(phase_t / 0.3, 0.0, 1.0) * clampf((1.1 - phase_t) / 0.3, 0.0, 1.0)
			draw_string(head, Vector2(p.position.x, p.get_center().y + 14), "PRONTO…", HORIZONTAL_ALIGNMENT_CENTER, p.size.x, 40, Color(UIKit.WHITE, a))
	for s in sparks:
		var c: Color = s.color
		draw_line(s.pos, s.pos - s.vel * 0.02, Color(c, clampf(s.life * 2.0, 0.0, 1.0)), 2.0)
	for pop in popups:
		var col: Color = pop.color
		draw_string(head, pop.pos - Vector2(80, 0), pop.text, HORIZONTAL_ALIGNMENT_CENTER, 160, 22, Color(col, clampf(pop.life * 2.0, 0.0, 1.0)))
	draw_set_transform(Vector2.ZERO)

func _draw_steps(p: Rect2) -> void:
	var labels := ["Scalda", "Martella", "Tempra", "Grado"]
	var order := ["heat", "hammer", "quench", "result"]
	var current := order.find(phase)
	var w := 120.0
	var x0 := p.get_center().x - w * 2.0
	for i in labels.size():
		var color := UIKit.GOLD if i == current else (UIKit.TEAL if i < current else UIKit.MUTED)
		var c := Vector2(x0 + w * (float(i) + 0.5), p.position.y + 70)
		draw_circle(c, 5.0, color)
		draw_string(UIKit.body_bold(), c + Vector2(-50, 22), labels[i], HORIZONTAL_ALIGNMENT_CENTER, 100, 13, color)

## Il pezzo sull'incudine: lama, corazza o amuleto, che si scalda durante la forgia.
func _draw_anvil() -> void:
	var a := _anvil_rect()
	var glow := heat_score if phase != "heat" else (1.0 - absf(bar_pos - bar_center))
	if phase == "quench" and _bar_mark >= 0.0: glow = 0.2
	var metal := Color("#3a4150").lerp(Color("#ff7a2e"), clampf(glow, 0.0, 1.0) * 0.85)
	var edge := metal.lightened(0.35)
	var c := a.get_center()
	# Incudine
	draw_rect(Rect2(c.x - a.size.x * 0.42, a.end.y - 34, a.size.x * 0.84, 22), Color("#1d2433"))
	draw_rect(Rect2(c.x - a.size.x * 0.12, a.end.y - 12, a.size.x * 0.24, 12), Color("#151b27"))
	match str(GameState.FORGE_RECIPES.get(recipe_id, {}).get("slot", "main")):
		"main":
			var blade := PackedVector2Array([
				Vector2(a.position.x + a.size.x * 0.1, c.y - a.size.y * 0.16),
				Vector2(a.position.x + a.size.x * 0.82, c.y - a.size.y * 0.13),
				Vector2(a.position.x + a.size.x * 0.94, c.y),
				Vector2(a.position.x + a.size.x * 0.82, c.y + a.size.y * 0.13),
				Vector2(a.position.x + a.size.x * 0.1, c.y + a.size.y * 0.16)])
			draw_colored_polygon(blade, metal)
			draw_polyline(blade + PackedVector2Array([blade[0]]), edge, 2.0)
			draw_rect(Rect2(a.position.x + a.size.x * 0.06, c.y - a.size.y * 0.3, a.size.x * 0.04, a.size.y * 0.6), Color("#5b4632"))
			draw_rect(Rect2(a.position.x, c.y - a.size.y * 0.06, a.size.x * 0.06, a.size.y * 0.12), Color("#6e5238"))
		"armor":
			var plate := PackedVector2Array([
				Vector2(c.x - a.size.x * 0.3, a.position.y + a.size.y * 0.12),
				Vector2(c.x + a.size.x * 0.3, a.position.y + a.size.y * 0.12),
				Vector2(c.x + a.size.x * 0.36, a.position.y + a.size.y * 0.3),
				Vector2(c.x + a.size.x * 0.24, a.end.y - 44),
				Vector2(c.x - a.size.x * 0.24, a.end.y - 44),
				Vector2(c.x - a.size.x * 0.36, a.position.y + a.size.y * 0.3)])
			draw_colored_polygon(plate, metal)
			draw_polyline(plate + PackedVector2Array([plate[0]]), edge, 2.0)
		_:
			draw_circle(c, a.size.y * 0.36, metal)
			draw_arc(c, a.size.y * 0.36, 0.0, TAU, 48, edge, 2.0)
			draw_arc(c, a.size.y * 0.2, 0.0, TAU, 32, edge, 1.5)

func _draw_points() -> void:
	for p in points:
		var pos := _point_screen(p)
		if p.done:
			var col := _rating_color(float(p.score))
			draw_circle(pos, 7.0, Color(col, 0.9))
			continue
		var r := _ring_radius(p)
		var tol := 22.0 * window
		var close := clampf(1.0 - absf(r - POINT_RADIUS) / tol, 0.0, 1.0)
		draw_circle(pos, POINT_RADIUS, Color(UIKit.CYAN, 0.18 + 0.25 * close))
		draw_arc(pos, POINT_RADIUS, 0.0, TAU, 40, UIKit.CYAN, 2.5)
		draw_arc(pos, maxf(1.0, r), 0.0, TAU, 48, UIKit.GOLD.lerp(UIKit.WHITE, close), 3.0)

func _draw_bar() -> void:
	var r := _bar_rect()
	draw_rect(r, Color("#0b111b"))
	var zone_x := r.position.x + r.size.x * (bar_center - bar_half)
	var zone := Rect2(zone_x, r.position.y, r.size.x * bar_half * 2.0, r.size.y)
	var hot := Color("#ff8a3d") if phase == "heat" else Color("#6fd8ff")
	draw_rect(Rect2(r.position.x + r.size.x * (bar_center - bar_half * 2.0), r.position.y, r.size.x * bar_half * 4.0, r.size.y), Color(hot, 0.2))
	draw_rect(zone, Color(hot, 0.55))
	draw_rect(Rect2(r.position.x + r.size.x * bar_center - 2, r.position.y, 4, r.size.y), Color(UIKit.WHITE, 0.8))
	draw_rect(r, UIKit.PAPER_LINE, false, 2.0)
	var x := r.position.x + r.size.x * (_bar_mark if _bar_mark >= 0.0 else bar_pos)
	draw_rect(Rect2(x - 3, r.position.y - 10, 6, r.size.y + 20), UIKit.GOLD)
	draw_string(UIKit.body_bold(), r.position + Vector2(0, -16), "Calore" if phase == "heat" else "Tempra", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.INK_SOFT)

func _draw_result(p: Rect2) -> void:
	var head := UIKit.head_font()
	var body := UIKit.body_bold()
	var index := _grade_index()
	var color := Color(GRADE_COLORS[index])
	var grow := clampf(_result_shown / 0.35, 0.0, 1.0)
	var c := p.get_center() + Vector2(0, -40)
	draw_circle(c, 90.0 * grow, Color(color, 0.15))
	draw_arc(c, 90.0 * grow, 0.0, TAU, 64, color, 4.0)
	if index >= 5:
		for i in 12:
			var ang := _t * 0.6 + TAU * float(i) / 12.0
			draw_line(c + Vector2(cos(ang), sin(ang)) * 100.0, c + Vector2(cos(ang), sin(ang)) * (130.0 + 10.0 * sin(_t * 4.0 + i)), Color(color, 0.7), 3.0)
	draw_string(head, c + Vector2(-100, 34), str(result_item.get("grade", "?")), HORIZONTAL_ALIGNMENT_CENTER, 200, int(96 * grow) + 1, color)
	draw_string(head, Vector2(p.position.x, c.y + 132), str(result_item.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, p.size.x, 24, UIKit.INK)
	var stat := ""
	if result_item.has("power"): stat = "Attacco +%d" % int(result_item.power)
	elif result_item.has("defense"): stat = "Difesa +%d" % int(result_item.defense)
	elif result_item.has("hp"): stat = "Vita +%d" % int(result_item.hp)
	draw_string(body, Vector2(p.position.x, c.y + 162), "Precisione %d%% · %s" % [roundi(precision * 100.0), stat], HORIZONTAL_ALIGNMENT_CENTER, p.size.x, 17, UIKit.INK_SOFT)
	var cap := int(GameState.FORGE_DIFFICULTIES.get(difficulty, {}).get("max_grade", 6))
	if cap < GameState.GRADES.size() - 1 and GameState.forge_grade_index(precision, "master") > cap:
		draw_string(body, Vector2(p.position.x, c.y + 188), "Con una difficoltà più alta avresti ottenuto di più.", HORIZONTAL_ALIGNMENT_CENTER, p.size.x, 15, UIKit.GOLD)
