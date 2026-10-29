extends Control
class_name MissionResultScreen

## Fine missione a schermo intero.
## 1. Per ogni eroe caduto: "Eroe perduto", tono silenzioso e rosso controllato,
##    nome, rarità e causa. Nessun effetto celebrativo. Si chiude con "Ho capito".
## 2. Poi il resoconto: "Stage Clear" con grado a stelle, ricompense e superstiti,
##    oppure "Missione fallita" / "Ritirata" senza ricompense.

signal closed
signal hero_pressed(hero_id: String)

const HeroPortraitScript := preload("res://scripts/hero_portrait.gd")

var result: Dictionary = {}
var resolved: Dictionary = {}
var phase := "lost"   # lost → summary
var _lost_index := 0
var _t := 0.0
var _accent := UIKit.GOLD
var _holder: CenterContainer
var _stars_shown := 0.0
var _stars: Control

func setup(mission_result: Dictionary, mission_resolved: Dictionary) -> Control:
	result = mission_result
	resolved = mission_resolved
	return self

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_holder = CenterContainer.new()
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_holder)
	if deaths().is_empty(): _show_summary()
	else: _show_lost(0)

func _process(delta: float) -> void:
	_t += delta
	if phase == "summary": _stars_shown = minf(3.0, _stars_shown + delta * 2.2)
	if is_instance_valid(_stars): _stars.queue_redraw()
	queue_redraw()

static func reason_text(reason: String) -> String:
	return {"clear": "zona ripulita", "survived": "resistito fino alla fine", "intel": "punti messi in sicurezza", "boss": "guardiano abbattuto", "party_wipe": "squadra annientata", "extracted": "ritirata", "timeout": "tempo scaduto", "beacon_lost": "faro perduto", "abandoned": "missione abbandonata", "defended": "faro difeso"}.get(reason, reason)

func deaths() -> Array:
	return resolved.get("deaths", [])

func survivors() -> Array:
	var alive := []
	for hero_result in result.get("hero_results", []):
		if bool(hero_result.get("alive", true)): alive.append(hero_result)
	return alive

## Grado: una stella per la vittoria, una se nessuno è caduto, una se nessun
## superstite è uscito sotto il 30% di vita.
func grade() -> Array:
	var victory := bool(result.get("victory", false))
	var no_deaths := deaths().is_empty()
	var healthy := true
	for hero_result in survivors():
		if float(hero_result.get("hp_ratio", 1.0)) < 0.3: healthy = false
	return [victory, victory and no_deaths, victory and no_deaths and healthy]

# --- Eroe perduto --------------------------------------------------------------

func _show_lost(index: int) -> void:
	phase = "lost"
	_lost_index = index
	_accent = UIKit.ROSE
	UIKit.clear(_holder)
	var record: Dictionary = deaths()[index]
	var panel := PanelContainer.new()
	var style := UIKit.ornate("system", 0.0).set_padding(56.0, 34.0)
	style.border = Color(UIKit.ROSE, 0.7)
	style.fill_top = Color("#140b10")
	style.fill_bottom = Color("#0d080b")
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = 620
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	if deaths().size() > 1:
		v.add_child(_centered(UIKit.label("%d / %d" % [index + 1, deaths().size()], 13, UIKit.MUTED, UIKit.head_medium())))
	var sigil := Control.new()
	sigil.custom_minimum_size = Vector2(180, 180)
	var face := CenterContainer.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hero := GameState.hero_by_id(str(record.id))
	var portrait: HeroPortrait = HeroPortraitScript.new()
	portrait.setup(hero if not hero.is_empty() else {"name": record.name, "role": record.role, "rarity": record.rarity, "state": "DEAD"}, 128)
	portrait.modulate = Color(0.75, 0.68, 0.7, 0.9)
	face.add_child(portrait)
	sigil.add_child(face)
	var cross := Control.new()
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross.bind(cross))
	sigil.add_child(cross)
	v.add_child(_centered(sigil))
	v.add_child(_centered(UIKit.title("EROE PERDUTO", 38, UIKit.ROSE)))
	v.add_child(_centered(UIKit.label("%s  %s" % [str(record.name), "★".repeat(int(record.get("rarity", 1)))], 22, UIKit.INK, UIKit.head_font())))
	v.add_child(_centered(UIKit.label("%s · Lv.%d · Piano %d" % [GameState.role_label(str(record.get("role", ""))), int(record.get("level", 1)), int(record.get("floor", 0))], 15, UIKit.INK_SOFT, UIKit.head_medium())))
	v.add_child(_centered(UIKit.para(str(record.get("cause", "")), 16, UIKit.INK_SOFT)))
	v.add_child(UIKit.hsep(4))
	v.add_child(_centered(UIKit.para("Questo eroe non può tornare nel roster. Non esistono resurrezioni.", 15, UIKit.MUTED)))
	v.add_child(_centered(UIKit.label("IL SUO NOME RESTA NEL MEMORIALE", 13, Color(UIKit.ROSE, 0.85), UIKit.head_medium())))
	v.add_child(UIKit.hsep(6))
	var ok := UIKit.button("Ho capito", _next_lost, "danger", 240)
	v.add_child(_centered(ok))
	panel.add_child(v)
	panel.modulate.a = 0.0
	_holder.add_child(panel)
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.6)

func _draw_cross(c: Control) -> void:
	var center := c.size * 0.5
	var r := minf(c.size.x, c.size.y) * 0.5 - 4.0
	c.draw_arc(center, r, 0, TAU, 72, Color(UIKit.ROSE, 0.85), 2.5, true)
	var d := r * 0.62
	c.draw_line(center + Vector2(-d, -d), center + Vector2(d, d), Color(UIKit.ROSE, 0.8), 3.0, true)
	c.draw_line(center + Vector2(d, -d), center + Vector2(-d, d), Color(UIKit.ROSE, 0.8), 3.0, true)

## Salta le schede dei caduti e mostra subito il resoconto.
func skip_to_summary() -> void:
	if phase != "summary": _show_summary()

func _next_lost() -> void:
	if _lost_index + 1 < deaths().size(): _show_lost(_lost_index + 1)
	else: _show_summary()

# --- Resoconto -----------------------------------------------------------------

func _show_summary() -> void:
	phase = "summary"
	_stars_shown = 0.0
	UIKit.clear(_holder)
	var victory := bool(result.get("victory", false))
	var extracted := str(result.get("reason", "")) == "extracted"
	_accent = UIKit.GOLD if victory else Color("#e88a8a")
	var panel := PanelContainer.new()
	var style := UIKit.ornate("system", 0.0).set_padding(48.0, 30.0)
	style.border = Color(_accent, 0.75)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = 760
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var floor_index := int(result.get("floor", 0))
	v.add_child(_centered(UIKit.label(("Piano %d · %s" % [floor_index, reason_text(str(result.get("reason", "")))]).to_upper(), 14, UIKit.CYAN, UIKit.head_medium())))
	var heading := "STAGE CLEAR" if victory else "RITIRATA" if extracted else "MISSIONE FALLITA"
	v.add_child(_centered(UIKit.title(heading, 48, _accent.lightened(0.15))))
	if victory:
		var stars := Control.new()
		stars.custom_minimum_size = Vector2(240, 54)
		stars.draw.connect(_draw_stars.bind(stars))
		_stars = stars
		v.add_child(_centered(stars))
		var g := grade()
		var notes := ["Vittoria", "Nessun caduto" if g[1] else "Ci sono caduti", "Squadra in forze" if g[2] else "Feriti gravi"]
		v.add_child(_centered(UIKit.label(" · ".join(notes).to_upper(), 12, UIKit.MUTED, UIKit.head_medium())))
	else:
		v.add_child(_centered(UIKit.para("Il piano resta identico: ritenta con una squadra più forte o più riposata.", 16, UIKit.INK_SOFT)))
	v.add_child(UIKit.hsep(4))
	if victory:
		var rewards: Dictionary = resolved.get("rewards", {})
		var drops: Dictionary = resolved.get("drops", {})
		var material_total := 0
		for key in drops: material_total += int(drops[key])
		var tiles := HBoxContainer.new()
		tiles.alignment = BoxContainer.ALIGNMENT_CENTER
		tiles.add_theme_constant_override("separation", 26)
		tiles.add_child(_reward("gold", "Oro", "+" + GameState.format_number(rewards.get("gold", 0)), UIKit.GOLD))
		tiles.add_child(_reward("ore", "Materiali", "+%d" % material_total, UIKit.CYAN))
		if rewards.has("gems"): tiles.add_child(_reward("gems", "Gemme", "+%d" % int(rewards.gems), UIKit.SKY))
		if rewards.has("stones"): tiles.add_child(_reward("stones", "Pietre", "+%d" % int(rewards.stones), UIKit.MAGENTA))
		tiles.add_child(_reward("star", "Esperienza", "+%d" % int(rewards.get("xp", 0)), UIKit.TEAL))
		v.add_child(tiles)
		if not drops.is_empty():
			var parts := []
			for key in drops: parts.append("%s +%d" % [GameState.MATERIALS[key].name, int(drops[key])])
			v.add_child(_centered(UIKit.label("Bottino: " + " · ".join(parts), 14, UIKit.INK_SOFT, UIKit.body_font())))
		for up in resolved.get("level_ups", []):
			v.add_child(_centered(UIKit.label("▲ %s sale dal Lv.%d al Lv.%d" % [up.name, int(up.from), int(up.to)], 15, UIKit.TEAL, UIKit.body_bold())))
	v.add_child(UIKit.divider())
	var foot := HBoxContainer.new()
	var total := maxi(1, result.get("hero_results", []).size())
	var alive := survivors().size()
	foot.add_child(UIKit.label("SUPERSTITI %d/%d" % [alive, total], 15, UIKit.TEAL if alive == total else UIKit.ROSE, UIKit.head_font()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	if victory and bool(resolved.get("first_clear", false)) and floor_index < RiftwardState.MAX_FLOOR:
		foot.add_child(UIKit.label("PIANO %d SBLOCCATO" % (floor_index + 1), 15, UIKit.CYAN, UIKit.head_font()))
	elif not deaths().is_empty():
		foot.add_child(UIKit.label("CADUTI %d" % deaths().size(), 15, UIKit.ROSE, UIKit.head_font()))
	v.add_child(foot)
	var injured := []
	for hero in GameState.get_party():
		if not hero.is_empty() and not hero.injuries.is_empty(): injured.append(hero.name)
	if not injured.is_empty():
		v.add_child(UIKit.para("Feriti: %s. Mandali al Dormitorio prima della prossima missione." % ", ".join(injured), 14, UIKit.GOLD))
	var back := UIKit.button("Torna alla base", close, "gold" if victory else "ghost", 260)
	back.custom_minimum_size.y = 50
	v.add_child(_centered(back))
	panel.add_child(v)
	panel.pivot_offset = Vector2(380, 200)
	panel.scale = Vector2(0.94, 0.94)
	panel.modulate.a = 0.0
	_holder.add_child(panel)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.3)
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)

func _reward(icon: String, title: String, value: String, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = 104
	var ring := Control.new()
	ring.custom_minimum_size = Vector2(72, 72)
	var paint := func():
		var c := ring.size * 0.5
		ring.draw_circle(c, 34.0, Color(color, 0.14))
		ring.draw_arc(c, 34.0, 0, TAU, 48, color, 2.0, true)
	ring.draw.connect(paint)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(UIKit.icon(icon, 34))
	ring.add_child(center)
	box.add_child(_centered(ring))
	box.add_child(_centered(UIKit.label(title.to_upper(), 12, UIKit.MUTED, UIKit.head_medium())))
	box.add_child(_centered(UIKit.label(value, 22, color, UIKit.head_font())))
	return box

func _draw_stars(c: Control) -> void:
	var g := grade()
	for i in 3:
		var p := Vector2(c.size.x * 0.5 + (i - 1) * 64.0, c.size.y * 0.5)
		var k := clampf(_stars_shown - i, 0.0, 1.0)
		var r := 20.0 * (0.6 + 0.4 * k) if g[i] else 18.0
		UIKit.draw_star(c, p, r, Color(UIKit.GOLD, k) if g[i] else Color("#2b3546"))
		if g[i] and k > 0.0: c.draw_circle(p, r * 1.5, Color(UIKit.GOLD, 0.08 * k))

func _centered(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(control)
	if control is Label:
		var label := control as Label
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# un testo che va a capo dentro un CenterContainer ha bisogno di una larghezza
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF: label.custom_minimum_size.x = 520
	return center

func close() -> void:
	closed.emit()
	queue_free()

func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.012, 0.016, 0.028, 0.93 if phase == "summary" else 0.97))
	var c := s * 0.5
	var r := minf(s.x, s.y) * 0.45
	for i in 8:
		draw_circle(c, r * (1.6 - i * 0.16), Color(_accent, (0.008 + i * 0.004) * (1.0 if phase == "summary" else 0.6)))
	if phase == "summary" and bool(result.get("victory", false)):
		# raggi lenti dietro al pannello
		for k in 18:
			var a := TAU * k / 18.0 + _t * 0.05
			draw_line(c + Vector2(cos(a), sin(a)) * r * 0.5, c + Vector2(cos(a), sin(a)) * r * 1.5, Color(_accent, 0.035), 10.0)
