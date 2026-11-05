extends Control
class_name SummonEvent

## Evocazione come evento a schermo intero.
## 1. Carica: il Sistema apre il varco, anelli sempre più veloci e particelle
##    risucchiate verso il centro. Il colore vira verso la rarità migliore uscita
##    (6★ e 7★ hanno anche un avviso del Sistema).
## 2. Esplosione: lampo, onda d'urto, scossa; le carte escono dal varco e volano
##    al loro posto, coperte.
## 3. Rivelazione carta per carta, diversa per rarità: più la carta è rara, più
##    attesa (la carta trema e si carica di luce), più luce e particelle quando si
##    gira (fascio di luce da 4★, raggi da 5★, lampo e scossa da 6★). Le carte da
##    4★ in su restano circondate da un'aura.
## "Salta" mostra subito tutto; "Continua" chiude. Toccare una carta apre l'eroe.

signal hero_pressed(hero_id: String)

const HeroCardScript := preload("res://scripts/ui/hero_card.gd")
const CHARGE_TIME := 1.9
## Per rarità (indice = stelle): attesa prima di girare, pausa dopo, particelle.
const ANTICIPATION := [0.0, 0.0, 0.0, 0.1, 0.4, 0.65, 0.9, 1.1]
const AFTER := [0.0, 0.1, 0.12, 0.18, 0.4, 0.6, 0.85, 1.0]
const BURST := [0, 10, 14, 22, 34, 46, 64, 84]

var heroes: Array = []
var pool_name := ""
var count := 1
var best := 1
var phase := "charge"   # charge → deal → reveal → done
var _t := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _shake := 0.0
var _cards: Array = []
var _slots: Array = []
## Stato visivo di ogni carta: volo (0→1), carica prima di girarsi, fascio, raggi, aura.
var _fx: Array = []
var _particles: Array = []
var _waves: Array = []
var _rng := RandomNumberGenerator.new()
var _layout: VBoxContainer
var _front: Control
var _grid: GridContainer
var _title: Label
var _subtitle: Label
var _notice: Label
var _skip: Button
var _continue: Button

func setup(summoned: Array, pool_label: String) -> Control:
	heroes = summoned
	pool_name = pool_label
	count = summoned.size()
	for hero in summoned: best = maxi(best, int(hero.get("current_rarity", hero.get("rarity", 1))))
	return self

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.seed = hash(str(count) + pool_name + str(best))
	_layout = VBoxContainer.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.add_theme_constant_override("separation", 0)
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layout)
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_top", 34)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_child(top)
	_layout.add_child(top_margin)
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
	_layout.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = mini(5, count)
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_grid)
	var card_w := 150.0 if count > 1 else 240.0
	for hero in heroes:
		# il posto nella griglia è fisso; la carta dentro si muove liberamente (volo dal varco)
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(card_w, card_w * 1.55)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(slot)
		var card: HeroCard = HeroCardScript.new()
		card.setup(hero, card_w)
		card.set_face_down(true)
		card.size = card.custom_minimum_size
		card.pivot_offset = card.size * 0.5
		card.modulate.a = 0.0
		card.pressed.connect(func(id: String): hero_pressed.emit(id))
		slot.add_child(card)
		_slots.append(slot)
		_cards.append(card)
		_fx.append({"fly": 0.0, "charge": 0.0, "beam": 0.0, "rays": 0.0, "aura": 0.0, "shake": 0.0})
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 14)
	var bottom_margin := MarginContainer.new()
	bottom_margin.add_theme_constant_override("margin_bottom", 34)
	bottom_margin.add_child(bottom)
	_layout.add_child(bottom_margin)
	_skip = UIKit.button("Salta", skip, "ghost", 160)
	bottom.add_child(_skip)
	_continue = UIKit.button("Continua", close, "violet", 220)
	_continue.visible = false
	bottom.add_child(_continue)
	# effetti davanti alle carte: particelle, onde d'urto, lampo
	_front = Control.new()
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.draw.connect(_draw_front)
	add_child(_front)
	_run()

func _gate_center() -> Vector2:
	return size * 0.5 + Vector2(0, 10)

func _card_center(i: int) -> Vector2:
	var card: HeroCard = _cards[i]
	return card.get_global_rect().get_center() - global_position

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	_shake = maxf(0.0, _shake - delta * 28.0)
	_layout.position = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake
	if phase == "charge": _charge_particles(delta)
	for i in _fx.size():
		var fx: Dictionary = _fx[i]
		fx.beam = maxf(0.0, float(fx.beam) - delta * 0.9)
		fx.rays = move_toward(float(fx.rays), 0.3 if float(fx.aura) > 0.0 and _cards[i].rarity >= 5 else 0.0, delta * 0.8)
		var card: HeroCard = _cards[i]
		# la carta che si carica trema sempre di più
		if float(fx.charge) > 0.0 and card.face_down:
			var k := float(fx.charge)
			card.position = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * (1.0 + k * k * 4.0)
			card.scale = Vector2.ONE * (1.0 + 0.08 * k)
			if _rng.randf() < 0.3 + k * 0.6:
				_spawn_inward(_card_center(i), card.size.y * (0.55 + 0.25 * k), _rarity_color(card.rarity, float(i)), 1)
	_update_particles(delta)
	queue_redraw()
	_front.queue_redraw()

## Colore della scena: parte azzurro e vira verso la rarità migliore.
func scene_color() -> Color:
	var target := _rarity_color(best)
	if best <= 3: target = UIKit.CYAN.lerp(target, 0.5)
	if phase == "charge":
		var k := clampf((_t - CHARGE_TIME * 0.35) / (CHARGE_TIME * 0.55), 0.0, 1.0)
		return UIKit.CYAN.lerp(target, k)
	return target

func _rarity_color(rarity: int, offset: float = 0.0) -> Color:
	return UIKit.rarity_color(rarity) if rarity < 7 else UIKit.prism_color(_t, offset * 0.07)

func _run() -> void:
	await get_tree().create_timer(CHARGE_TIME * 0.6).timeout
	if not is_inside_tree() or phase != "charge": return
	if best >= 7: _set_notice("SEGNALE TRASCENDENTE RILEVATO", UIKit.prism_color(_t).lightened(0.2))
	elif best == 6: _set_notice("RISONANZA LEGGENDARIA", UIKit.rarity_color(6).lightened(0.2))
	elif best == 5: _set_notice("Segnale raro in arrivo", UIKit.GOLD)
	await get_tree().create_timer(CHARGE_TIME * 0.4).timeout
	if not is_inside_tree() or phase != "charge": return
	_open_gate()
	await get_tree().create_timer(0.35 + 0.06 * count).timeout
	for i in _cards.size():
		if not is_inside_tree() or phase == "done": return
		var card: HeroCard = _cards[i]
		if not card.face_down: continue
		var wait: float = ANTICIPATION[card.rarity]
		if wait > 0.0:
			var fx: Dictionary = _fx[i]
			var tween := create_tween()
			tween.tween_method(func(v: float): fx.charge = v, 0.0, 1.0, wait).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			await get_tree().create_timer(wait).timeout
			if not is_inside_tree() or phase == "done": return
		_flip(i)
		await get_tree().create_timer(0.22 + float(AFTER[card.rarity])).timeout
	_finish()

func _set_notice(text: String, color: Color) -> void:
	_notice.text = text
	_notice.add_theme_color_override("font_color", color)
	_notice.add_theme_font_override("font", UIKit.head_font())
	_notice.add_theme_font_size_override("font_size", 20)

## Il varco esplode: lampo, onda d'urto, schegge; poi le carte volano al loro posto.
func _open_gate() -> void:
	phase = "deal"
	var color := scene_color()
	_flash = 1.0
	_flash_color = color.lightened(0.6)
	_shake = 6.0 + best * 1.6
	if best >= 6: _title.text = "LEGGENDA" if best == 6 else "TRASCENDENZA"
	_title.add_theme_color_override("font_color", color.lightened(0.25))
	_title.pivot_offset = _title.size * 0.5
	var pop := create_tween()
	pop.tween_property(_title, "scale", Vector2(1.18, 1.18), 0.08)
	pop.tween_property(_title, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var c := _gate_center()
	var r := minf(size.x, size.y) * 0.3
	_wave(c, r * 0.1, r * 2.6, 0.7, color.lightened(0.3), 5.0)
	_wave(c, r * 0.05, r * 1.6, 0.5, Color.WHITE, 3.0)
	_burst(c, 90 + best * 10, color, r * 2.4, "shard")
	for i in _cards.size():
		var card: HeroCard = _cards[i]
		var slot: Control = _slots[i]
		var start := c - (slot.global_position - global_position) - card.size * 0.5
		card.position = start
		card.scale = Vector2.ONE * 0.2
		card.rotation = _rng.randf_range(-0.7, 0.7)
		var tween := create_tween()
		tween.tween_interval(0.05 + i * 0.06)
		tween.tween_property(card, "modulate:a", 1.0, 0.08)
		tween.parallel().tween_property(card, "position", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card, "rotation", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var fx: Dictionary = _fx[i]
		tween.parallel().tween_method(func(v: float): fx.fly = v, 0.0, 1.0, 0.5)
	phase = "reveal"

## Gira una carta: più è rara, più luce, particelle, lampo e scossa.
func _flip(i: int) -> void:
	var card: HeroCard = _cards[i]
	var fx: Dictionary = _fx[i]
	var r := card.rarity
	card.position = Vector2.ZERO
	var tween := card.create_tween()
	tween.tween_property(card, "scale", Vector2(0.0, 1.0 + 0.05 * r * fx.charge), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		card.set_face_down(false)
		fx.charge = 0.0
		_reveal_fx(i))
	tween.tween_property(card, "scale", Vector2(1.0 + 0.04 * r, 1.0 + 0.04 * r), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _reveal_fx(i: int) -> void:
	var card: HeroCard = _cards[i]
	var fx: Dictionary = _fx[i]
	var r := card.rarity
	var color := _rarity_color(r, float(i))
	var c := _card_center(i)
	var h := card.size.y
	_burst(c, BURST[r], color, h * (0.5 + 0.12 * r), "star" if r >= 5 else "spark")
	_wave(c, h * 0.3, h * (0.6 + 0.16 * r), 0.45 + 0.05 * r, color.lightened(0.3), 2.0 + r * 0.5)
	if r >= 4:
		fx.beam = 1.0
		fx.aura = 1.0
	if r >= 5:
		fx.rays = 1.0
		_flash = maxf(_flash, 0.18 + (r - 5) * 0.2)
		_flash_color = color.lightened(0.5)
		_shake = maxf(_shake, 3.0 + (r - 5) * 6.0)
		_wave(c, h * 0.2, h * 2.2, 0.8, Color.WHITE, 1.5)
	if r >= 6: _set_notice("%s · %s" % [UIKit.rarity_tag(r), str(card.hero.get("name", "")).to_upper()], color.lightened(0.2))

## Mostra subito tutte le carte.
func skip() -> void:
	if phase == "charge": _open_gate()
	for i in _cards.size():
		var card: HeroCard = _cards[i]
		card.modulate.a = 1.0
		card.position = Vector2.ZERO
		card.rotation = 0.0
		card.scale = Vector2.ONE
		_fx[i].fly = 1.0
		_fx[i].charge = 0.0
		if card.face_down:
			card.set_face_down(false)
			if card.rarity >= 4: _fx[i].aura = 1.0
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

# --- Particelle ----------------------------------------------------------------

## Esplosione dal centro c: schegge, scintille o stelline che rallentano e svaniscono.
func _burst(c: Vector2, amount: int, color: Color, reach: float, kind: String) -> void:
	for k in amount:
		var a := _rng.randf() * TAU
		var speed := reach * _rng.randf_range(0.9, 2.4)
		var tint := color.lerp(Color.WHITE, _rng.randf() * 0.5)
		if best >= 7 and kind != "spark": tint = UIKit.prism_color(_t, _rng.randf())
		var life := _rng.randf_range(0.5, 1.1)
		_particles.append({"p": c + Vector2(cos(a), sin(a)) * _rng.randf_range(0.0, reach * 0.15), "v": Vector2(cos(a), sin(a)) * speed, "life": life, "max": life, "color": tint, "size": _rng.randf_range(1.5, 4.0), "kind": kind, "drag": 3.2, "gravity": 0.0})

## Particelle risucchiate verso un punto (carica del varco o di una carta).
func _spawn_inward(c: Vector2, radius: float, color: Color, amount: int) -> void:
	for k in amount:
		var a := _rng.randf() * TAU
		var start := c + Vector2(cos(a), sin(a)) * radius * _rng.randf_range(0.8, 1.3)
		var to_c := (c - start)
		var tangent := Vector2(-to_c.y, to_c.x).normalized()
		var life := _rng.randf_range(0.45, 0.8)
		_particles.append({"p": start, "v": to_c / life * 1.1 + tangent * radius * 0.9, "life": life, "max": life, "color": color.lightened(_rng.randf() * 0.4), "size": _rng.randf_range(1.2, 2.6), "kind": "mote", "drag": 1.2, "gravity": 0.0, "target": c})

func _charge_particles(delta: float) -> void:
	var charge := clampf(_t / CHARGE_TIME, 0.0, 1.0)
	var r := minf(size.x, size.y) * 0.3
	var amount := int(delta * (40.0 + charge * 200.0) + _rng.randf())
	_spawn_inward(_gate_center(), r * (1.9 - charge * 0.6), scene_color(), amount)

func _wave(c: Vector2, r0: float, r1: float, life: float, color: Color, width: float) -> void:
	_waves.append({"c": c, "r0": r0, "r1": r1, "life": life, "max": life, "color": color, "width": width})

func _update_particles(delta: float) -> void:
	for p in _particles:
		p.life = float(p.life) - delta
		var v: Vector2 = p.v
		if p.has("target"):
			# attratte dal centro: accelerano e spariscono quando ci arrivano
			var to_t: Vector2 = (p.target as Vector2) - (p.p as Vector2)
			v += to_t * delta * 9.0
			if to_t.length() < 6.0: p.life = 0.0
		v *= maxf(0.0, 1.0 - float(p.drag) * delta)
		v.y += float(p.gravity) * delta
		p.v = v
		p.p = (p.p as Vector2) + v * delta
	_particles = _particles.filter(func(p): return float(p.life) > 0.0)
	for w in _waves: w.life = float(w.life) - delta
	_waves = _waves.filter(func(w): return float(w.life) > 0.0)

# --- Disegno -----------------------------------------------------------------------

## Dietro le carte: fondo, varco, scie di volo, aure, fasci e raggi.
func _draw() -> void:
	var s := size
	var color := scene_color()
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.015, 0.02, 0.035, 0.9))
	var c := _gate_center()
	var r := minf(s.x, s.y) * 0.3
	var charge := clampf(_t / CHARGE_TIME, 0.0, 1.0) if phase == "charge" else 1.0
	var fade := 1.0 if phase == "charge" else 0.4
	for i in 9:
		var g := color
		g.a = (0.012 + i * 0.008) * (0.6 + charge * 0.8)
		draw_circle(c, r * (2.0 - i * 0.2), g)
	# anelli del varco: ruotano sempre più veloci durante la carica
	var spin := _t * (0.6 + charge * charge * 6.0)
	for k in 4:
		var rr := r * (0.55 + k * 0.17) * (1.0 - 0.18 * charge * charge if phase == "charge" else 1.0)
		var a := spin * (1.0 if k % 2 == 0 else -0.7) + k
		var lc := color
		lc.a = (0.75 - k * 0.12) * fade
		draw_arc(c, rr, a, a + PI * (1.2 - k * 0.15), 64, lc, 2.0 if k == 0 else 1.4, true)
		draw_arc(c, rr, a + PI * 1.35, a + PI * 1.75, 24, lc, 1.4, true)
	for k in 48:
		var a := TAU * k / 48.0 - spin * 0.25
		var inner_r := r * 1.12
		var tick_len := r * (0.06 if k % 4 == 0 else 0.03)
		var tc := color
		tc.a = 0.5 * fade
		draw_line(c + Vector2(cos(a), sin(a)) * inner_r, c + Vector2(cos(a), sin(a)) * (inner_r + tick_len), tc, 1.2, true)
	# nucleo che si stringe e pulsa sempre più forte, poi esplode
	if phase == "charge":
		var core := color.lightened(0.4)
		core.a = 0.35 + charge * 0.6
		var pulse := 0.12 + 0.08 * sin(_t * (9.0 + charge * 14.0)) * charge + 0.05 * charge
		for g in 4:
			draw_circle(c, r * pulse * (1.0 + g * 0.6), Color(core, core.a * (0.5 - g * 0.11)))
		draw_circle(c, r * pulse, core)
		for k in 8:
			var a := TAU * k / 8.0 + spin * 1.5
			draw_line(c + Vector2(cos(a), sin(a)) * r * 0.2, c + Vector2(cos(a), sin(a)) * r * (0.2 + charge * 0.35), Color(core, core.a * 0.6), 1.5, true)
	if phase == "charge" or _cards.is_empty(): return
	for i in _cards.size():
		var card: HeroCard = _cards[i]
		var fx: Dictionary = _fx[i]
		var cc := _card_center(i)
		var rc := _rarity_color(card.rarity, float(i))
		var h := card.size.y * card.scale.y
		# scia del volo dal varco
		var fly := float(fx.fly)
		if fly > 0.0 and fly < 1.0:
			var tail := c.lerp(cc, maxf(0.0, fly - 0.35))
			draw_line(tail, cc, Color(rc.lightened(0.3), 0.5 * (1.0 - fly)), 3.0 * (1.0 - fly) + 1.0, true)
		# carica: alone che cresce attorno alla carta coperta
		var k := float(fx.charge)
		if k > 0.0:
			for g in 5:
				draw_circle(cc, h * (0.5 + g * 0.12) * (0.8 + 0.3 * k), Color(rc, 0.05 * k * (5 - g)))
		# aura delle carte alte, pulsante
		var aura := float(fx.aura)
		if aura > 0.0:
			var pulse := 0.75 + 0.25 * sin(_t * 2.6 + i)
			for g in 4:
				draw_circle(cc, h * (0.46 + g * 0.1), Color(rc, 0.035 * pulse * (4 - g) * (1.0 + (card.rarity - 4) * 0.35)))
		# raggi che girano dietro le carte da 5★
		var rays := float(fx.rays)
		if rays > 0.01:
			# raggi sottili e sfumati: un ventaglio largo e tenue, uno stretto e più luminoso
			var n := 12 + card.rarity * 2
			for q in n:
				var a := TAU * q / n + _t * (0.35 if q % 2 == 0 else -0.22)
				var len := h * (0.85 + 0.3 * sin(_t * 2.6 + q * 1.7)) * (1.0 + 0.8 * rays)
				var tip := cc + Vector2(cos(a), sin(a)) * len
				for layer in 2:
					var wdt := (0.05 if layer == 0 else 0.018) * (1.0 + 0.4 * (q % 3))
					var pts := PackedVector2Array([cc, cc + Vector2(cos(a - wdt), sin(a - wdt)) * len * 0.92, tip, cc + Vector2(cos(a + wdt), sin(a + wdt)) * len * 0.92])
					draw_colored_polygon(pts, Color(rc.lightened(0.35), (0.035 if layer == 0 else 0.07) * rays))
		# fascio di luce verticale dalle carte da 4★
		var beam := float(fx.beam)
		if beam > 0.0:
			var bw := card.size.x * (0.5 + 0.5 * beam)
			var top := Vector2(cc.x, 0.0)
			var pts := PackedVector2Array([top + Vector2(-bw * 0.3, 0), top + Vector2(bw * 0.3, 0), Vector2(cc.x + bw * 0.5, size.y), Vector2(cc.x - bw * 0.5, size.y)])
			var core_pts := PackedVector2Array([Vector2(cc.x - bw * 0.12, 0), Vector2(cc.x + bw * 0.12, 0), Vector2(cc.x + bw * 0.22, size.y), Vector2(cc.x - bw * 0.22, size.y)])
			draw_colored_polygon(core_pts, Color(rc.lightened(0.5), 0.22 * beam))
			draw_colored_polygon(pts, Color(rc, 0.1 * beam))

## Davanti alle carte: onde d'urto, particelle e lampo.
func _draw_front() -> void:
	for w in _waves:
		var k := 1.0 - float(w.life) / float(w.max)
		var rr := lerpf(float(w.r0), float(w.r1), 1.0 - pow(1.0 - k, 3.0))
		var col: Color = w.color
		col.a = (1.0 - k) * 0.85
		_front.draw_arc(w.c, rr, 0, TAU, 72, col, float(w.width) * (1.0 - k * 0.6) + 0.5, true)
	for p in _particles:
		var k := clampf(float(p.life) / float(p.max), 0.0, 1.0)
		var col: Color = p.color
		col.a = k if p.kind != "mote" else minf(1.0, k * 2.0)
		var pos: Vector2 = p.p
		var sz := float(p.size)
		match str(p.kind):
			"spark", "shard":
				var v: Vector2 = p.v
				var tail := v * (0.035 if p.kind == "spark" else 0.05)
				_front.draw_line(pos - tail, pos, col, sz * (0.8 if p.kind == "spark" else 1.2), true)
			"star":
				var rr := sz * (1.0 + 1.5 * k)
				_front.draw_line(pos - Vector2(rr, 0), pos + Vector2(rr, 0), col, 1.3, true)
				_front.draw_line(pos - Vector2(0, rr), pos + Vector2(0, rr), col, 1.3, true)
				_front.draw_circle(pos, sz * 0.45, Color(1, 1, 1, col.a))
			_:
				_front.draw_circle(pos, sz, col)
	if _flash > 0.0:
		_front.draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_color, _flash * 0.6))
