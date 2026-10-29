extends Control
class_name SummonEvent

## Evocazione come evento a schermo intero.
## 1. Il Sistema apre il varco: anelli al centro che girano sempre più veloci.
## 2. Il colore della scena vira verso la rarità migliore uscita, prima ancora
##    di mostrare gli eroi (6★ e 7★ hanno anche un avviso del Sistema).
## 3. Lampo, poi le carte arrivano coperte e si girano una alla volta.
## "Salta" mostra subito tutto; "Continua" chiude. Toccare una carta apre l'eroe.

signal hero_pressed(hero_id: String)

const HeroCardScript := preload("res://scripts/ui/hero_card.gd")
const CHARGE_TIME := 1.7

var heroes: Array = []
var pool_name := ""
var count := 1
var best := 1
var phase := "charge"   # charge → flash → reveal → done
var _t := 0.0
var _flash := 0.0
var _cards: Array = []
var _grid: GridContainer
var _title: Label
var _subtitle: Label
var _notice: Label
var _skip: Button
var _continue: Button

func setup(summoned: Array, pool_label: String) -> SummonEvent:
	heroes = summoned
	pool_name = pool_label
	count = summoned.size()
	for hero in summoned: best = maxi(best, int(hero.get("current_rarity", hero.get("rarity", 1))))
	return self

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_top", 34)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_child(top)
	layout.add_child(top_margin)
	_subtitle = UIKit.label(("%d evocazion%s · %s" % [count, "e" if count == 1 else "i", pool_name]).to_upper(), 14, UIKit.CYAN, UIKit.head_medium())
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_subtitle)
	_title = UIKit.title("EVOCAZIONE", 40, UIKit.INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_title)
	_notice = UIKit.label("Il Sistema sta aprendo il varco…", 16, UIKit.INK_SOFT, UIKit.body_font())
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_notice)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = mini(5, count)
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	_grid.modulate.a = 0.0
	center.add_child(_grid)
	var card_w := 150.0 if count > 1 else 240.0
	for hero in heroes:
		var card: HeroCard = HeroCardScript.new()
		card.setup(hero, card_w)
		card.set_face_down(true)
		card.pressed.connect(func(id: String): hero_pressed.emit(id))
		_grid.add_child(card)
		_cards.append(card)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 14)
	var bottom_margin := MarginContainer.new()
	bottom_margin.add_theme_constant_override("margin_bottom", 34)
	bottom_margin.add_child(bottom)
	layout.add_child(bottom_margin)
	_skip = UIKit.button("Salta", skip, "ghost", 160)
	bottom.add_child(_skip)
	_continue = UIKit.button("Continua", close, "violet", 220)
	_continue.visible = false
	bottom.add_child(_continue)
	_run()

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.2)
	queue_redraw()

## Colore della scena: parte azzurro e vira verso la rarità migliore.
func scene_color() -> Color:
	var target := UIKit.rarity_color(best) if best < 7 else UIKit.prism_color(_t)
	if best <= 3: target = UIKit.CYAN.lerp(target, 0.5)
	if phase == "charge":
		var k := clampf((_t - CHARGE_TIME * 0.35) / (CHARGE_TIME * 0.55), 0.0, 1.0)
		return UIKit.CYAN.lerp(target, k)
	return target

func _run() -> void:
	await get_tree().create_timer(CHARGE_TIME * 0.6).timeout
	if not is_inside_tree() or phase != "charge": return
	if best >= 7: _set_notice("SEGNALE TRASCENDENTE RILEVATO", UIKit.prism_color(_t).lightened(0.2))
	elif best == 6: _set_notice("RISONANZA LEGGENDARIA", UIKit.rarity_color(6).lightened(0.2))
	elif best == 5: _set_notice("Segnale raro in arrivo", UIKit.GOLD)
	await get_tree().create_timer(CHARGE_TIME * 0.4).timeout
	if not is_inside_tree() or phase != "charge": return
	_open_gate()
	await get_tree().create_timer(0.3).timeout
	for card in _cards:
		if not is_inside_tree() or phase == "done": return
		if card.face_down: _flip(card)
		await get_tree().create_timer(0.16 if card.rarity < 4 else 0.5 if card.rarity < 6 else 0.9).timeout
	_finish()

func _set_notice(text: String, color: Color) -> void:
	_notice.text = text
	_notice.add_theme_color_override("font_color", color)
	_notice.add_theme_font_override("font", UIKit.head_font())
	_notice.add_theme_font_size_override("font_size", 20)

func _open_gate() -> void:
	phase = "reveal"
	_flash = 1.0
	if best >= 6: _title.text = "LEGGENDA" if best == 6 else "TRASCENDENZA"
	_title.add_theme_color_override("font_color", scene_color().lightened(0.25))
	var tween := create_tween()
	tween.tween_property(_grid, "modulate:a", 1.0, 0.25)

func _flip(card: HeroCard) -> void:
	card.pivot_offset = card.size * 0.5
	var tween := card.create_tween()
	tween.tween_property(card, "scale:x", 0.0, 0.12)
	tween.tween_callback(card.set_face_down.bind(false))
	tween.tween_property(card, "scale:x", 1.0, 0.14)
	if card.rarity >= 4:
		if card.rarity >= 6: _flash = 0.7
		tween.tween_property(card, "scale", Vector2(1.1, 1.1), 0.12)
		tween.tween_property(card, "scale", Vector2.ONE, 0.2)

## Mostra subito tutte le carte.
func skip() -> void:
	if phase == "charge": _open_gate()
	for card in _cards:
		if card.face_down:
			card.scale = Vector2.ONE
			card.set_face_down(false)
	_grid.modulate.a = 1.0
	_finish()

func _finish() -> void:
	if phase == "done": return
	phase = "done"
	_skip.visible = false
	_continue.visible = true
	var best_hero := {}
	for hero in heroes:
		if best_hero.is_empty() or int(hero.get("current_rarity", 1)) > int(best_hero.get("current_rarity", 1)): best_hero = hero
	_set_notice("Miglior risultato: %s %s · tocca una carta per aprire l'eroe" % [str(best_hero.get("name", "")), "★".repeat(best)], UIKit.INK_SOFT)
	_notice.add_theme_font_override("font", UIKit.body_font())
	_notice.add_theme_font_size_override("font_size", 16)

func close() -> void:
	queue_free()

func _draw() -> void:
	var s := size
	var color := scene_color()
	# fondo: quasi nero con una sfumatura del colore della scena al centro
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.015, 0.02, 0.035, 0.9))
	var c := s * 0.5 + Vector2(0, 10)
	var r := minf(s.x, s.y) * 0.3
	var charge := clampf(_t / CHARGE_TIME, 0.0, 1.0) if phase == "charge" else 1.0
	var fade := 1.0 if phase == "charge" else 0.45
	for i in 9:
		var g := color
		g.a = (0.012 + i * 0.008) * (0.6 + charge * 0.8)
		draw_circle(c, r * (2.0 - i * 0.2), g)
	# anelli del varco: ruotano sempre più veloci durante la carica
	var spin := _t * (0.6 + charge * charge * 6.0)
	for k in 4:
		var rr := r * (0.55 + k * 0.17)
		var a := spin * (1.0 if k % 2 == 0 else -0.7) + k
		var lc := color
		lc.a = (0.75 - k * 0.12) * fade
		draw_arc(c, rr, a, a + PI * (1.2 - k * 0.15), 64, lc, 2.0 if k == 0 else 1.4, true)
		draw_arc(c, rr, a + PI * 1.35, a + PI * 1.75, 24, lc, 1.4, true)
	# tacche sul cerchio esterno
	for k in 48:
		var a := TAU * k / 48.0 - spin * 0.25
		var inner_r := r * 1.12
		var tick_len := r * (0.06 if k % 4 == 0 else 0.03)
		var tc := color
		tc.a = 0.5 * fade
		draw_line(c + Vector2(cos(a), sin(a)) * inner_r, c + Vector2(cos(a), sin(a)) * (inner_r + tick_len), tc, 1.2, true)
	# nucleo che si stringe e poi esplode nel lampo
	if phase == "charge":
		var core := color.lightened(0.4)
		core.a = 0.35 + charge * 0.6
		draw_circle(c, r * (0.12 + 0.08 * sin(_t * 9.0) * charge), core)
		for k in 6:
			var a := TAU * k / 6.0 + spin * 1.5
			draw_line(c + Vector2(cos(a), sin(a)) * r * 0.2, c + Vector2(cos(a), sin(a)) * r * (0.2 + charge * 0.3), Color(core, core.a * 0.6), 1.5, true)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(color.lightened(0.6), _flash * 0.55))
