extends Control
class_name SummonEvent

## Evocazione come evento a schermo intero.
## 1. Carica: nel buio si apre uno squarcio verticale del Rift che si allunga,
##    crepita di fulmini e risucchia particelle. Il colore vira verso la rarità
##    migliore uscita (6★ e 7★ hanno anche un avviso del Sistema). Niente cerchi:
##    il proprietario non li vuole (2026-11-05).
## 2. Lo squarcio si spalanca: lama di luce che si allarga, lampo, schegge, scossa;
##    le carte escono dallo squarcio e volano al loro posto, coperte.
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
## Squarcio del Rift: scarti orizzontali dei punti lungo la fenditura (fissi) e fulmini.
var _tear: Array = []
var _arcs: Array = []
var _open_t := -1.0
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
	# fenditura frastagliata: scarti casuali, poi ammorbiditi
	var raw := []
	for k in 31: raw.append(_rng.randf_range(-1.0, 1.0))
	for k in 31: _tear.append((raw[maxi(0, k - 1)] + raw[k] * 2.0 + raw[mini(30, k + 1)]) * 0.25)
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

## Lunghezza attuale dello squarcio (cresce durante la carica).
func _tear_length() -> float:
	var charge := clampf(_t / CHARGE_TIME, 0.0, 1.0) if phase == "charge" else 1.0
	return size.y * (0.08 + 0.6 * (1.0 - pow(1.0 - charge, 2.2)))

## Punto dello squarcio a quota v (0 = cima, 1 = fondo), con un tremolio vivo.
func _tear_point(v: float) -> Vector2:
	var c := _gate_center()
	var length := _tear_length()
	var f := v * (_tear.size() - 1)
	var i0 := clampi(int(f), 0, _tear.size() - 1)
	var i1 := mini(i0 + 1, _tear.size() - 1)
	var jag := lerpf(float(_tear[i0]), float(_tear[i1]), f - i0)
	var wobble := sin(_t * 23.0 + v * 17.0) * 0.12
	return Vector2(c.x + (jag + wobble) * length * 0.07, c.y - length * 0.5 + v * length)

func _card_center(i: int) -> Vector2:
	var card: HeroCard = _cards[i]
	return card.get_global_rect().get_center() - global_position

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	_shake = maxf(0.0, _shake - delta * 28.0)
	if phase == "charge": _shake = maxf(_shake, 2.5 * pow(clampf(_t / CHARGE_TIME, 0.0, 1.0), 3.0))
	_layout.position = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake
	if _open_t >= 0.0: _open_t += delta
	if phase == "charge":
		_charge_particles(delta)
		_spawn_arcs(delta)
	for a in _arcs: a.life = float(a.life) - delta
	_arcs = _arcs.filter(func(a): return float(a.life) > 0.0)
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
	_open_t = 0.0
	var length := _tear_length()
	# schegge che schizzano di lato da tutta la fenditura
	for k in 110 + best * 12:
		var v := _rng.randf()
		var p := _tear_point(v)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var dir := Vector2(side, _rng.randf_range(-0.45, 0.45)).normalized()
		var tint := color.lerp(Color.WHITE, _rng.randf() * 0.5)
		if best >= 7: tint = UIKit.prism_color(_t, _rng.randf())
		var life := _rng.randf_range(0.5, 1.1)
		_particles.append({"p": p, "v": dir * length * _rng.randf_range(0.6, 2.2), "life": life, "max": life, "color": tint, "size": _rng.randf_range(1.5, 4.0), "kind": "shard", "drag": 3.0, "gravity": 0.0})
	for i in _cards.size():
		var card: HeroCard = _cards[i]
		var slot: Control = _slots[i]
		# ogni carta esce da un punto diverso dello squarcio
		var out := _tear_point(0.2 + 0.6 * (float(i) + 0.5) / maxf(1.0, _cards.size()))
		var start := out - (slot.global_position - global_position) - card.size * 0.5
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
	_wave(c, card.size, 0.0, h * (0.25 + 0.1 * r), 0.45 + 0.05 * r, color.lightened(0.3), 2.0 + r * 0.5)
	if r >= 4:
		fx.beam = 1.0
		fx.aura = 1.0
	if r >= 5:
		fx.rays = 1.0
		_flash = maxf(_flash, 0.18 + (r - 5) * 0.2)
		_flash_color = color.lightened(0.5)
		_shake = maxf(_shake, 3.0 + (r - 5) * 6.0)
		_wave(c, card.size, 0.0, h * 1.2, 0.8, Color.WHITE, 1.5)
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

## Durante la carica le particelle arrivano dai lati e finiscono dentro la fenditura.
func _charge_particles(delta: float) -> void:
	var charge := clampf(_t / CHARGE_TIME, 0.0, 1.0)
	var amount := int(delta * (50.0 + charge * 230.0) + _rng.randf())
	var color := scene_color()
	for k in amount:
		var target := _tear_point(_rng.randf_range(0.1, 0.9))
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var start := target + Vector2(side * _rng.randf_range(0.12, 0.45) * size.x, _rng.randf_range(-0.25, 0.25) * size.y)
		var life := _rng.randf_range(0.5, 0.9)
		_particles.append({"p": start, "v": (target - start) / life * 0.6 + Vector2(0, _rng.randf_range(-60.0, 60.0)), "life": life, "max": life, "color": color.lightened(_rng.randf() * 0.45), "size": _rng.randf_range(1.2, 2.6), "kind": "mote", "drag": 1.2, "gravity": 0.0, "target": target})

## Fulmini che si staccano dalla fenditura, sempre più spessi verso la fine della carica.
func _spawn_arcs(delta: float) -> void:
	var charge := clampf(_t / CHARGE_TIME, 0.0, 1.0)
	if _rng.randf() > delta * (6.0 + 26.0 * charge): return
	var v := _rng.randf_range(0.08, 0.92)
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var reach := size.x * _rng.randf_range(0.02, 0.035 + 0.04 * charge)
	var width := 0.8 + 1.0 * charge
	_arcs.append({"pts": _bolt(_tear_point(v), Vector2(side, _rng.randf_range(-0.6, 0.6)).normalized(), reach), "life": 0.1, "max": 0.1, "width": width})
	# a volte un ramo secondario più corto
	if _rng.randf() < 0.45:
		var main: PackedVector2Array = _arcs[-1].pts
		var from := main[int(main.size() * 0.5)]
		_arcs.append({"pts": _bolt(from, Vector2(side, _rng.randf_range(-1.0, 1.0)).normalized(), reach * 0.5), "life": 0.1, "max": 0.1, "width": width * 0.6})

## Saetta: tanti piccoli tratti spezzati lungo una direzione.
func _bolt(from: Vector2, dir: Vector2, reach: float) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var normal := Vector2(-dir.y, dir.x)
	var steps := 12
	var p := from
	for k in steps:
		p += dir * (reach / steps) + normal * _rng.randf_range(-1.0, 1.0) * reach * 0.12
		pts.append(p)
	return pts

## Onda a forma di carta: un contorno che parte dalla carta e si allarga svanendo.
func _wave(c: Vector2, card_size: Vector2, grow0: float, grow1: float, life: float, color: Color, width: float) -> void:
	_waves.append({"c": c, "size": card_size, "g0": grow0, "g1": grow1, "life": life, "max": life, "color": color, "width": width})

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

## Dietro le carte: fondo, squarcio del Rift, scie di volo, aure, fasci e raggi.
func _draw() -> void:
	var s := size
	var color := scene_color()
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.015, 0.02, 0.035, 0.92))
	var c := _gate_center()
	var charge := clampf(_t / CHARGE_TIME, 0.0, 1.0) if phase == "charge" else 1.0
	# bagliore verticale attorno allo squarcio (sfumato ai lati, mai circolare)
	var glow_w := s.x * (0.08 + 0.22 * charge) * (1.0 if phase == "charge" else 0.7)
	var glow_a := (0.05 + 0.2 * charge) * (1.0 if phase == "charge" else 0.45)
	_soft_band(c.x, glow_w, Color(color, glow_a))
	_soft_band(c.x, glow_w * 0.35, Color(color.lightened(0.3), glow_a * 1.2))
	# lo squarcio: lama frastagliata, nucleo bianco, bordo colorato
	if phase == "charge" or _open_t < 0.9:
		var open := 0.0 if _open_t < 0.0 else clampf(_open_t / 0.9, 0.0, 1.0)
		var width := (2.0 + 7.0 * charge * charge) * (1.0 - open)
		var alpha := 1.0 - open
		if alpha > 0.0:
			_draw_tear(width * 3.2, Color(color, 0.25 * alpha))
			_draw_tear(width * 1.6, Color(color.lightened(0.35), 0.6 * alpha))
			_draw_tear(width * 0.55, Color(1, 1, 1, 0.95 * alpha))
	for a in _arcs:
		var k := float(a.life) / float(a.max)
		draw_polyline(a.pts, Color(color.lightened(0.5), k * 0.9), float(a.width) * 2.4, true)
		draw_polyline(a.pts, Color(1, 1, 1, k), float(a.width), true)
	if phase == "charge" or _cards.is_empty(): return
	for i in _cards.size():
		var card: HeroCard = _cards[i]
		var fx: Dictionary = _fx[i]
		var cc := _card_center(i)
		var rc := _rarity_color(card.rarity, float(i))
		var h := card.size.y * card.scale.y
		var rect := Rect2(cc - card.size * card.scale * 0.5, card.size * card.scale)
		# scia del volo dallo squarcio
		var fly := float(fx.fly)
		if fly > 0.0 and fly < 1.0:
			var tail := Vector2(c.x, cc.y).lerp(cc, maxf(0.0, fly - 0.35))
			draw_line(tail, cc, Color(rc.lightened(0.3), 0.5 * (1.0 - fly)), 3.0 * (1.0 - fly) + 1.0, true)
		# carica: alone a forma di carta che cresce attorno alla carta coperta
		var k := float(fx.charge)
		if k > 0.0: _glow_rect(rect, h * (0.12 + 0.3 * k), Color(rc, 0.55 * k))
		# aura delle carte alte, pulsante, sempre a forma di carta
		var aura := float(fx.aura)
		if aura > 0.0:
			var pulse := 0.75 + 0.25 * sin(_t * 2.6 + i)
			_glow_rect(rect, h * (0.16 + 0.04 * card.rarity), Color(rc, 0.26 * pulse * (1.0 + (card.rarity - 4) * 0.35)))
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

## Fascia verticale di luce sfumata ai lati (centro x, mezza larghezza w).
func _soft_band(x: float, w: float, col: Color) -> void:
	var h := size.y
	draw_polygon(PackedVector2Array([Vector2(x - w, 0), Vector2(x, 0), Vector2(x, h), Vector2(x - w, h)]), PackedColorArray([Color(col, 0.0), col, col, Color(col, 0.0)]))
	draw_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w, h), Vector2(x, h)]), PackedColorArray([col, Color(col, 0.0), Color(col, 0.0), col]))

## La fenditura come striscia frastagliata, più larga al centro e appuntita in cima e in fondo.
func _draw_tear(width: float, col: Color) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := 40
	for k in n + 1:
		var v := float(k) / n
		var p := _tear_point(v)
		var w := width * pow(sin(v * PI), 0.7)
		left.append(p - Vector2(w, 0))
		right.append(p + Vector2(w, 0))
	right.reverse()
	var poly := left + right
	if Geometry2D.triangulate_polygon(poly).is_empty(): return
	draw_colored_polygon(poly, col)

## Alone sfumato a forma di carta: quattro trapezi dal bordo verso l'esterno.
func _glow_rect(rect: Rect2, spread: float, col: Color) -> void:
	var o := rect.grow(spread)
	var inner := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var outer := [o.position, Vector2(o.end.x, o.position.y), o.end, Vector2(o.position.x, o.end.y)]
	var clear := Color(col, 0.0)
	for k in 4:
		var k2 := (k + 1) % 4
		draw_polygon(PackedVector2Array([inner[k], inner[k2], outer[k2], outer[k]]), PackedColorArray([col, col, clear, clear]))

## Davanti alle carte: onde d'urto, particelle e lampo.
func _draw_front() -> void:
	for w in _waves:
		var k := 1.0 - float(w.life) / float(w.max)
		var g := lerpf(float(w.g0), float(w.g1), 1.0 - pow(1.0 - k, 3.0))
		var col: Color = w.color
		col.a = (1.0 - k) * 0.85
		var half: Vector2 = (w.size as Vector2) * 0.5 + Vector2(g, g)
		var cut := minf(half.x, half.y) * 0.12
		var c: Vector2 = w.c
		var pts := PackedVector2Array([c + Vector2(-half.x + cut, -half.y), c + Vector2(half.x - cut, -half.y), c + Vector2(half.x, -half.y + cut), c + Vector2(half.x, half.y - cut), c + Vector2(half.x - cut, half.y), c + Vector2(-half.x + cut, half.y), c + Vector2(-half.x, half.y - cut), c + Vector2(-half.x, -half.y + cut), c + Vector2(-half.x + cut, -half.y)])
		_front.draw_polyline(pts, col, float(w.width) * (1.0 - k * 0.6) + 0.5, true)
	# lo squarcio si spalanca: la luce dilaga di lato in una fascia verticale e svanisce
	if _open_t >= 0.0 and _open_t < 0.7:
		var k := _open_t / 0.7
		var wide := size.x * 0.55 * (1.0 - pow(1.0 - k, 3.0)) + 6.0
		var col := scene_color().lightened(0.55)
		var cx := _gate_center().x
		_front_band(cx, wide, Color(col, 0.5 * (1.0 - k)))
		_front_band(cx, wide * 0.25, Color(1, 1, 1, 0.75 * (1.0 - k) * (1.0 - k)))
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
		_front.draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_color, _flash * 0.38))

func _front_band(x: float, w: float, col: Color) -> void:
	var h := size.y
	_front.draw_polygon(PackedVector2Array([Vector2(x - w, 0), Vector2(x, 0), Vector2(x, h), Vector2(x - w, h)]), PackedColorArray([Color(col, 0.0), col, col, Color(col, 0.0)]))
	_front.draw_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w, h), Vector2(x, h)]), PackedColorArray([col, Color(col, 0.0), Color(col, 0.0), col]))
