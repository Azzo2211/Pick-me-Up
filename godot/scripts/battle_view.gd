extends Control
class_name BattleView

signal battle_finished(result: Dictionary)
signal hero_died(hero_id: String, cause: String)

const BG := Color("#0b0f1a")
const PANEL := Color("#151b2af0")
const TEXT := Color("#f5f7fb")
const MUTED := Color("#9da7b8")
const AMBER := Color("#f0c75e")
const BLUE := Color("#4e7cff")
const GREEN := Color("#39c5bb")
const RED := Color("#ff4d5a")
const CYAN := Color("#66d9ff")
const VIOLET := Color("#9a6bff")

var stage: Dictionary
var party_source: Array
var attempt := 1
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var accumulator := 0.0
var decision_timer := 0.0
var running := false
var completed := false
var heroes: Array = []
var enemies: Array = []
var effects: Array = []
var spawned_waves: Array = []
var next_id := 1
var command_state := {"posture": "ADVANCE", "focus": false, "protect": false, "all_out_until": 0.0, "extracting": false, "extract_at": 0.0}
var command_ready := {"posture": 0.0, "focus": 0.0, "protect": 0.0, "all_out": 0.0, "extract": 0.0}
var objective := {"poi": 0, "beacon": 100.0, "boss_dead": false}

var title_label: Label
var objective_label: Label
var progress_label: Label
var clock_label: Label
var party_box: VBoxContainer
var log_label: RichTextLabel
var command_buttons: Dictionary = {}
var combat_log: Array[String] = []

func setup(stage_data: Dictionary, source_party: Array, mission_attempt: int) -> void:
	stage = stage_data
	party_source = source_party
	attempt = mission_attempt
	rng.seed = abs((str(stage.seed) + ":" + str(attempt)).hash())

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_hud()
	_create_heroes()
	running = true
	_log("Descriptor %s bloccato. L'IA assume la formazione." % stage.seed, "good")
	queue_redraw()

func _build_hud() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 18
	top.offset_bottom = 92
	top.add_theme_constant_override("separation", 24)
	add_child(top)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label = Label.new()
	title_label.text = "CENERE SULLA FRONTIERA\nPIANO %02d // %s" % [stage.floor, str(stage.type).to_upper()]
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", TEXT)
	title_box.add_child(title_label)
	top.add_child(title_box)

	var objective_box := VBoxContainer.new()
	objective_box.custom_minimum_size.x = 380
	objective_label = Label.new()
	objective_label.text = "OBIETTIVO // " + str(stage.objective).to_upper()
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.add_theme_color_override("font_color", AMBER)
	objective_label.add_theme_font_size_override("font_size", 12)
	progress_label = Label.new()
	progress_label.text = "Stabilizzazione del Rift..."
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.add_theme_color_override("font_color", MUTED)
	objective_box.add_child(objective_label)
	objective_box.add_child(progress_label)
	top.add_child(objective_box)

	clock_label = Label.new()
	clock_label.custom_minimum_size.x = 150
	clock_label.text = "TEMPO SIM.\n00:00"
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.add_theme_font_size_override("font_size", 18)
	top.add_child(clock_label)

	party_box = VBoxContainer.new()
	party_box.position = Vector2(18, 112)
	party_box.size = Vector2(220, 285)
	party_box.add_theme_constant_override("separation", 5)
	add_child(party_box)

	var console_panel := PanelContainer.new()
	console_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	console_panel.offset_left = -382
	console_panel.offset_top = -268
	console_panel.offset_right = -18
	console_panel.offset_bottom = -122
	console_panel.add_theme_stylebox_override("panel", _box(PANEL, Color("#3a4255"), 1, 4))
	add_child(console_panel)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = false
	log_label.scroll_active = false
	log_label.add_theme_font_size_override("normal_font_size", 11)
	console_panel.add_child(log_label)

	var command_panel := PanelContainer.new()
	command_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	command_panel.offset_left = 18
	command_panel.offset_right = -18
	command_panel.offset_top = -104
	command_panel.offset_bottom = -16
	command_panel.add_theme_stylebox_override("panel", _box(Color("#0d1220f2"), BLUE.darkened(0.38), 1, 4))
	add_child(command_panel)
	var commands := HBoxContainer.new()
	commands.add_theme_constant_override("separation", 7)
	command_panel.add_child(commands)
	var caption := Label.new()
	caption.custom_minimum_size.x = 190
	caption.text = "MASTER UPLINK\nSolo ordini macro.\nGli eroi decidono come eseguirli."
	caption.add_theme_color_override("font_color", CYAN)
	caption.add_theme_font_size_override("font_size", 10)
	commands.add_child(caption)
	_add_command(commands, "posture", "[1] AVANZA\nPostura squadra")
	_add_command(commands, "focus", "[2] ALTA MINACCIA\nPriorità bersagli")
	_add_command(commands, "protect", "[3] PROTEGGI REAR\nCopertura alleati")
	_add_command(commands, "all_out", "[4] TUTTO PER TUTTO\n10 secondi")
	_add_command(commands, "extract", "[X] ESTRAZIONE\n6 secondi")

func _box(color: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _add_command(parent: HBoxContainer, key: String, label_text: String) -> void:
	var button := Button.new()
	button.text = label_text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(150, 66)
	button.add_theme_font_size_override("font_size", 10)
	button.pressed.connect(_use_command.bind(key))
	parent.add_child(button)
	command_buttons[key] = button

func _create_heroes() -> void:
	var positions := [Vector2(0.27, 0.38), Vector2(0.26, 0.62), Vector2(0.20, 0.33), Vector2(0.18, 0.68), Vector2(0.12, 0.50)]
	for i in party_source.size():
		var source: Dictionary = party_source[i]
		var derived := GameState.derived_stats(source)
		heroes.append({"entity_id": next_id, "id": source.id, "name": source.name, "role": source.role, "hue": source.hue, "source": source, "x_ratio": positions[i].x, "y_ratio": positions[i].y, "hp": float(derived.max_hp), "max_hp": float(derived.max_hp), "attack": float(max(derived.attack * 0.75, derived.magic) if source.role in ["Mage", "Support"] else derived.attack), "defense": float(derived.defense), "range": 230.0 if source.role in ["Ranger", "Mage", "Support"] else 76.0 if source.role == "Lancer" else 48.0, "speed": 0.060 if source.role == "Ranger" else 0.050, "cooldown": rng.randf_range(0.2, 0.8), "skill_cd": rng.randf_range(2.0, 4.0), "target": -1, "action": "Valuta minacce", "alive": true, "kills": 0, "damage": 0, "healing": 0, "ammo": int(derived.ammo), "max_ammo": int(derived.ammo), "status": "Stable", "flash": 0.0})
		next_id += 1
	_refresh_party_hud()

func _process(delta: float) -> void:
	if not running or completed: return
	accumulator += min(delta, 0.1)
	while accumulator >= 0.05:
		_tick(0.05)
		accumulator -= 0.05
	queue_redraw()

func _tick(delta: float) -> void:
	elapsed += delta
	decision_timer -= delta
	_spawn_waves()
	if command_state.extracting and elapsed >= command_state.extract_at:
		_finish(false, "extracted")
		return
	if decision_timer <= 0:
		decision_timer = 0.2
		_decide()
	for hero in heroes: _update_hero(hero, delta)
	for enemy in enemies: _update_enemy(enemy, delta)
	_update_effects(delta)
	_update_objective()
	_check_end()
	_update_hud()

func _spawn_waves() -> void:
	for index in stage.waves.size():
		if spawned_waves.has(index): continue
		var wave: Array = stage.waves[index]
		if elapsed < float(wave[0]): continue
		spawned_waves.append(index)
		for i in int(wave[2]): _spawn_enemy(str(wave[1]), index, i)
		_log("%s: %d ostili rilevati." % ["Contatto" if index == 0 else "Rinforzi", int(wave[2])], "warn" if index > 0 else "")

func _spawn_enemy(kind: String, wave: int, index: int) -> void:
	var templates := {"raider": [145.0, 17.0, 7.0, 0.039, 0.82, 1], "hound": [108.0, 15.0, 4.0, 0.058, 0.70, 1], "archer": [102.0, 16.0, 3.0, 0.034, 1.18, 2], "brute": [285.0, 27.0, 14.0, 0.027, 1.45, 3], "boss": [1750.0, 34.0, 21.0, 0.022, 1.35, 8]}
	var t: Array = templates[kind]
	var scale := 0.82 + int(stage.floor) * 0.10
	enemies.append({"entity_id": next_id, "kind": kind, "name": "Custode" if kind == "boss" else kind.capitalize(), "x_ratio": 1.02 + rng.randf_range(0.0, 0.08), "y_ratio": 0.22 + fmod(float(wave * 3 + index * 2), 7.0) * 0.09, "hp": t[0] * scale, "max_hp": t[0] * scale, "attack": t[1] * scale, "defense": t[2] * scale, "speed": t[3], "cooldown": rng.randf_range(0.1, 0.8), "cadence": t[4], "threat": t[5], "range": 0.21 if kind == "archer" else 0.055, "target": -1, "alive": true, "flash": 0.0})
	next_id += 1

func _decide() -> void:
	var living_enemies := enemies.filter(func(unit): return unit.alive)
	for hero in heroes:
		if not hero.alive: continue
		if hero.role == "Support":
			var wounded := heroes.filter(func(unit): return unit.alive and unit.hp / unit.max_hp < 0.65)
			wounded.sort_custom(func(a, b): return a.hp / a.max_hp < b.hp / b.max_hp)
			if not wounded.is_empty() and hero.skill_cd <= 0:
				hero.target = wounded[0].entity_id
				hero.action = "heal"
				continue
		if living_enemies.is_empty():
			hero.action = "regroup"
			continue
		living_enemies.sort_custom(func(a, b):
			var score_a: float = abs(a.x_ratio - hero.x_ratio) - (a.threat * 0.08 if command_state.focus else 0.0)
			var score_b: float = abs(b.x_ratio - hero.x_ratio) - (b.threat * 0.08 if command_state.focus else 0.0)
			return score_a < score_b)
		var target: Dictionary = living_enemies[0]
		hero.target = target.entity_id
		var distance: float = abs(target.x_ratio - hero.x_ratio)
		if distance <= hero.range / 1000.0:
			hero.action = "attack"
		else: hero.action = "advance"
	for enemy in living_enemies:
		var living_heroes := heroes.filter(func(unit): return unit.alive)
		if living_heroes.is_empty(): continue
		living_heroes.sort_custom(func(a, b): return abs(a.x_ratio - enemy.x_ratio) < abs(b.x_ratio - enemy.x_ratio))
		enemy.target = living_heroes[0].entity_id

func _find_unit(collection: Array, entity_id: int) -> Dictionary:
	for unit in collection:
		if int(unit.entity_id) == entity_id: return unit
	return {}

func _update_hero(hero: Dictionary, delta: float) -> void:
	if not hero.alive: return
	hero.cooldown -= delta
	hero.skill_cd -= delta
	hero.flash = max(0.0, hero.flash - delta * 4.0)
	if hero.action == "heal":
		var ally := _find_unit(heroes, hero.target)
		if not ally.is_empty() and ally.alive and hero.skill_cd <= 0:
			var amount: float = 35.0 + hero.source.stats.int * 1.7
			ally.hp = min(ally.max_hp, ally.hp + amount)
			hero.healing += roundi(amount)
			hero.skill_cd = 9.0
			effects.append({"type": "ring", "x": ally.x_ratio, "y": ally.y_ratio, "life": 0.8, "color": GREEN})
			_log("%s stabilizza %s (+%d HP)." % [hero.name, ally.name, roundi(amount)], "good")
		return
	var target := _find_unit(enemies, hero.target)
	if target.is_empty() or not target.alive: return
	var distance: float = abs(target.x_ratio - hero.x_ratio)
	if hero.action == "advance" and distance > hero.range / 1000.0:
		var move: float = hero.speed * delta
		if command_state.posture == "HOLD": move *= 0.45
		elif command_state.posture == "RETREAT": move *= -0.4
		hero.x_ratio = clampf(hero.x_ratio + move, 0.08, 0.82)
	elif hero.action == "attack" and hero.cooldown <= 0:
		if hero.role == "Ranger":
			if hero.ammo <= 0:
				hero.status = "No ammo"
				hero.cooldown = 1.4
				return
			hero.ammo -= 1
			if hero.ammo == 4: _log(hero.name + ": 4 frecce rimaste.", "warn")
		var coefficient := 1.0
		if hero.skill_cd <= 0 and (target.threat >= 3 or rng.randf() < 0.18):
			coefficient = 1.55
			hero.skill_cd = 10.0
			effects.append({"type": "ring", "x": target.x_ratio, "y": target.y_ratio, "life": 0.6, "color": AMBER})
		var all_out: bool = elapsed < float(command_state.all_out_until)
		_deal_damage(hero, target, coefficient)
		hero.cooldown = (0.72 if all_out else 1.0) * (1.35 if hero.role in ["Mage", "Support"] else 1.02)

func _update_enemy(enemy: Dictionary, delta: float) -> void:
	if not enemy.alive: return
	enemy.cooldown -= delta
	enemy.flash = max(0.0, enemy.flash - delta * 4.0)
	var target := _find_unit(heroes, enemy.target)
	if target.is_empty() or not target.alive: return
	var distance: float = abs(target.x_ratio - enemy.x_ratio)
	if distance > enemy.range:
		enemy.x_ratio = max(0.08, enemy.x_ratio - enemy.speed * delta)
	elif enemy.cooldown <= 0:
		_deal_damage(enemy, target, 1.0)
		enemy.cooldown = enemy.cadence

func _deal_damage(attacker: Dictionary, target: Dictionary, coefficient: float) -> void:
	var raw: float = attacker.attack * coefficient * rng.randf_range(0.95, 1.05)
	var damage := maxi(1, roundi(raw * 100.0 / (100.0 + target.defense)))
	target.hp = max(0.0, target.hp - damage)
	target.flash = 1.0
	attacker.damage = int(attacker.get("damage", 0)) + damage
	effects.append({"type": "hit", "x": target.x_ratio, "y": target.y_ratio, "life": 0.28, "color": RED if target.has("source") else AMBER})
	if target.hp <= 0: _kill(target, attacker)

func _kill(target: Dictionary, attacker: Dictionary) -> void:
	if not target.alive: return
	target.alive = false
	if attacker.has("source"): attacker.kills += 1
	effects.append({"type": "death", "x": target.x_ratio, "y": target.y_ratio, "life": 1.1, "color": RED})
	if target.has("source"):
		_log(target.name + " è caduto. Evento irreversibile registrato.", "danger")
		hero_died.emit(target.id, "Ucciso da " + attacker.name)
	else:
		if target.kind == "boss": objective.boss_dead = true

func _update_objective() -> void:
	if stage.type == "Exploration":
		if elapsed >= 14 and objective.poi < 1: objective.poi = 1; _log("Punto d'interesse 1/3 acquisito.", "good")
		if elapsed >= 28 and objective.poi < 2: objective.poi = 2; _log("Punto d'interesse 2/3 acquisito.", "good")
		if elapsed >= 42 and objective.poi < 3: objective.poi = 3; _log("Punto d'interesse 3/3 acquisito.", "good")

func _update_effects(delta: float) -> void:
	for effect in effects: effect.life -= delta
	effects = effects.filter(func(effect): return effect.life > 0)

func _check_end() -> void:
	var living_heroes := heroes.filter(func(unit): return unit.alive)
	var living_enemies := enemies.filter(func(unit): return unit.alive)
	if living_heroes.is_empty(): _finish(false, "party_wipe"); return
	var all_spawned: bool = spawned_waves.size() == stage.waves.size()
	if stage.type == "Survival" and elapsed >= stage.duration: _finish(true, "survived"); return
	if stage.type == "Exploration" and objective.poi >= 3 and all_spawned and living_enemies.is_empty(): _finish(true, "intel"); return
	if stage.type == "Boss" and objective.boss_dead and all_spawned and living_enemies.is_empty(): _finish(true, "boss"); return
	if stage.type in ["Subjugation", "Defense"] and all_spawned and living_enemies.is_empty(): _finish(true, "clear"); return
	if elapsed >= stage.duration and stage.type != "Survival": _finish(false, "timeout")

func _finish(victory: bool, reason: String) -> void:
	if completed: return
	completed = true
	running = false
	var hero_results := []
	for hero in heroes:
		hero_results.append({"id": hero.id, "alive": hero.alive, "hp_ratio": hero.hp / hero.max_hp, "kills": hero.kills, "fatigue": roundi(10 + elapsed * 0.28 + (7 if hero.hp / hero.max_hp < 0.3 else 0))})
	await get_tree().create_timer(0.45).timeout
	battle_finished.emit({"victory": victory, "reason": reason, "duration": elapsed, "hero_results": hero_results})

func _use_command(key: String) -> void:
	if elapsed < float(command_ready[key]): return
	if key == "posture":
		var options := ["ADVANCE", "HOLD", "RETREAT"]
		command_state.posture = options[(options.find(command_state.posture) + 1) % options.size()]
		command_ready[key] = elapsed + 20.0
		_log("Ordine Master: postura " + command_state.posture + ".", "warn")
	elif key == "focus": command_state.focus = not command_state.focus; command_ready[key] = elapsed + 30.0; _log("Priorità alta minaccia aggiornata.", "warn")
	elif key == "protect": command_state.protect = not command_state.protect; command_ready[key] = elapsed + 30.0; _log("Protezione retroguardia aggiornata.", "warn")
	elif key == "all_out": command_state.all_out_until = elapsed + 10.0; command_ready[key] = elapsed + 45.0; _log("Tutto per tutto autorizzato.", "warn")
	elif key == "extract": command_state.extracting = true; command_state.extract_at = elapsed + 6.0; command_ready[key] = INF; command_state.posture = "RETREAT"; _log("Estrazione in 6 secondi.", "danger")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("macro_posture"): _use_command("posture")
	elif event.is_action_pressed("macro_focus"): _use_command("focus")
	elif event.is_action_pressed("macro_protect"): _use_command("protect")
	elif event.is_action_pressed("macro_all_out"): _use_command("all_out")
	elif event.is_action_pressed("macro_extract"): _use_command("extract")

func _update_hud() -> void:
	clock_label.text = "TEMPO SIM.\n%02d:%02d" % [floori(elapsed / 60), floori(elapsed) % 60]
	var living := enemies.filter(func(unit): return unit.alive).size()
	if stage.type == "Survival": progress_label.text = "%d secondi rimanenti" % maxi(0, ceili(stage.duration - elapsed))
	elif stage.type == "Exploration": progress_label.text = "%d/3 punti // %d ostili" % [objective.poi, living]
	else: progress_label.text = "%d ostili rimanenti" % living
	_refresh_party_hud()
	for key in command_buttons:
		var button: Button = command_buttons[key]
		var remaining := maxi(0, ceili(float(command_ready[key]) - elapsed))
		button.disabled = remaining > 0
		button.modulate = Color(1, 1, 1, 0.55) if button.disabled else Color.WHITE

func _refresh_party_hud() -> void:
	for child in party_box.get_children(): child.queue_free()
	for hero in heroes:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(215, 49)
		panel.add_theme_stylebox_override("panel", _box(Color("#091016d8"), Color.from_hsv(float(hero.hue) / 360.0, 0.45, 0.65), 1, 2))
		var row := HBoxContainer.new()
		var initial := Label.new(); initial.text = str(hero.name).left(2).to_upper(); initial.custom_minimum_size.x = 32
		var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new(); name_label.text = hero.name; name_label.add_theme_font_size_override("font_size", 10)
		var hp := ProgressBar.new(); hp.max_value = hero.max_hp; hp.value = hero.hp; hp.show_percentage = false; hp.custom_minimum_size.y = 5
		info.add_child(name_label); info.add_child(hp)
		var status := Label.new(); status.text = "DEAD" if not hero.alive else ("%d/%d" % [hero.ammo, hero.max_ammo] if hero.max_ammo > 0 else hero.status); status.add_theme_font_size_override("font_size", 8); status.add_theme_color_override("font_color", RED if not hero.alive else CYAN)
		row.add_child(initial); row.add_child(info); row.add_child(status); panel.add_child(row); party_box.add_child(panel)

func _log(message: String, tone: String = "") -> void:
	var color := "#e2b75f" if tone == "warn" else "#e56a64" if tone == "danger" else "#72c493" if tone == "good" else "#aeb9c0"
	combat_log.push_front("[color=#667783]%02d:%02d[/color] · [color=%s]%s[/color]" % [floori(elapsed / 60), floori(elapsed) % 60, color, message])
	if combat_log.size() > 6: combat_log.resize(6)
	log_label.text = "[font_size=10][color=#7c8b95]EVENT LOG[/color]\n" + "\n".join(combat_log) + "[/font_size]"

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var field := Rect2(0, 96, size.x, size.y - 210)
	var stage_color := Color(stage.get("color", "#4e7cff"))
	draw_rect(field, stage_color.darkened(0.78))
	for x in range(0, int(size.x), 64): draw_line(Vector2(x, field.position.y), Vector2(x + 180, field.end.y), Color(0.40, 0.85, 1.0, 0.045), 1)
	for y in range(int(field.position.y), int(field.end.y), 55): draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.40, 0.85, 1.0, 0.045), 1)
	for hero in heroes: _draw_unit(hero, true, field)
	for enemy in enemies: _draw_unit(enemy, false, field)
	for effect in effects:
		var pos := Vector2(effect.x * size.x, field.position.y + effect.y * field.size.y)
		var radius := 15.0 + (1.0 - float(effect.life)) * 30.0
		draw_arc(pos, radius, 0, TAU, 18, effect.color, 2.0)

func _draw_unit(unit: Dictionary, is_hero: bool, field: Rect2) -> void:
	if not unit.alive: return
	var pos := Vector2(unit.x_ratio * size.x, field.position.y + unit.y_ratio * field.size.y)
	var radius := 27.0 if unit.get("kind", "") == "boss" else 14.0
	var color := Color.from_hsv(float(unit.get("hue", 8 if not is_hero else 45)) / 360.0, 0.45, 0.70 if is_hero else 0.55)
	if not is_hero:
		var enemy_hues := {"raider": 8.0, "hound": 278.0, "archer": 330.0, "brute": 22.0, "boss": 112.0}
		color = Color.from_hsv(enemy_hues[unit.kind] / 360.0, 0.55, 0.64)
	if unit.flash > 0: color = Color.WHITE
	draw_circle(pos + Vector2(0, radius * 0.8), radius * 1.25, Color(0, 0, 0, 0.32))
	var polygon := PackedVector2Array([pos + Vector2(-radius, radius * 0.7), pos + Vector2(-radius * 0.7, -radius * 0.7), pos + Vector2(0, -radius), pos + Vector2(radius * 0.8, -radius * 0.4), pos + Vector2(radius, radius * 0.7)])
	draw_colored_polygon(polygon, color)
	draw_polyline(polygon, TEXT if is_hero else RED, 1.0)
	var hp_width := 84.0 if unit.get("kind", "") == "boss" else 34.0
	draw_rect(Rect2(pos + Vector2(-hp_width / 2, -radius - 11), Vector2(hp_width, 4)), Color("#101318"))
	draw_rect(Rect2(pos + Vector2(-hp_width / 2, -radius - 11), Vector2(hp_width * unit.hp / unit.max_hp, 4)), GREEN if is_hero else RED)
