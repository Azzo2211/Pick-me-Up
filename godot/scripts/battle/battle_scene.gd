extends Control
class_name BattleScene

## Missione in tempo reale. Gli eroi agiscono da soli con una Utility AI
## (bersagli, distanza, ruolo, coraggio); il Master dà solo ordini generali.
## Simulazione deterministica a 20 tick/s, decisioni a 5 Hz.

signal battle_finished(result: Dictionary)
signal hero_died(hero_id: String, cause: String)

const ChibiScript := preload("res://scripts/hub3d/chibi_model.gd")
const HeroPortraitScript := preload("res://scripts/hero_portrait.gd")

const TICK := 0.05
const DECISION := 0.2
const ARENA_X := 15.0
const ARENA_Z := 7.0
const FORMATION := [Vector2(-6.5, -1.6), Vector2(-6.5, 1.6), Vector2(-8.6, -2.4), Vector2(-8.6, 2.4), Vector2(-10.8, 0.0)]
const ENEMY_TEMPLATES := {
	"raider": {"hp": 150.0, "attack": 17.0, "defense": 7.0, "speed": 2.3, "cadence": 0.9, "threat": 1, "range": 1.1, "tint": Color("#c0453a"), "name": "Predone"},
	"hound": {"hp": 110.0, "attack": 15.0, "defense": 4.0, "speed": 3.6, "cadence": 0.75, "threat": 1, "range": 1.0, "tint": Color("#7b4fb8"), "name": "Segugio"},
	"archer": {"hp": 105.0, "attack": 16.0, "defense": 3.0, "speed": 2.0, "cadence": 1.25, "threat": 2, "range": 6.5, "tint": Color("#c4467e"), "name": "Arciere"},
	"brute": {"hp": 300.0, "attack": 27.0, "defense": 14.0, "speed": 1.5, "cadence": 1.5, "threat": 3, "range": 1.4, "tint": Color("#a8653a"), "name": "Bruto"},
	"boss": {"hp": 1800.0, "attack": 34.0, "defense": 21.0, "speed": 1.3, "cadence": 1.35, "threat": 8, "range": 1.9, "tint": Color("#4f8a3a"), "name": "Guardiano"},
}

var stage: Dictionary
var party_source: Array
var attempt := 1
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var accumulator := 0.0
var decision_timer := 0.0
var running := false
var completed := false
var speed_scale := 1.0
var units: Array = []
var effects: Array = []
var floaters: Array = []
var spawned_waves: Array = []
var next_id := 1
var command_state := {"posture": "ADVANCE", "focus": false, "protect": false, "all_out_until": 0.0, "extracting": false, "extract_at": 0.0}
var command_ready := {"posture": 0.0, "focus": 0.0, "protect": 0.0, "all_out": 0.0, "extract": 0.0}
var objective := {"poi": 0, "poi_progress": 0.0, "beacon": 100.0, "boss_dead": false}
var poi_points: Array[Vector2] = [Vector2(-1.0, -3.8), Vector2(4.5, 3.6), Vector2(10.0, -2.5)]
var beacon_pos := Vector2(-12.6, 0.0)

var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var overlay: Control
var title_label: Label
var objective_label: Label
var progress_label: Label
var clock_label: Label
var party_box: VBoxContainer
var party_cards: Dictionary = {}
var log_box: VBoxContainer
var command_buttons: Dictionary = {}
var speed_button: Button
var poi_nodes: Array[Node3D] = []
var beacon_node: Node3D

func setup(stage_data: Dictionary, source_party: Array, mission_attempt: int) -> void:
	stage = stage_data
	party_source = source_party
	attempt = mission_attempt
	rng.seed = abs((str(stage.seed) + ":" + str(attempt)).hash())

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_hud()
	_create_heroes()
	running = true
	_log("La squadra attraversa il Portale. Da qui in avanti decidono loro.", "good")

# =============================================================================
# Scena 3D
# =============================================================================

func _build_world() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var biome_color := Color(str(stage.get("color", "#3c7968")))
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = biome_color.lerp(Color("#4c9be8"), 0.6)
	sky_mat.sky_horizon_color = biome_color.lerp(Color("#e8f2ff"), 0.75)
	sky_mat.ground_bottom_color = biome_color.darkened(0.3)
	sky_mat.ground_horizon_color = biome_color.lerp(Color("#e8f2ff"), 0.6)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.6
	env.fog_enabled = true
	env.fog_light_color = biome_color.lerp(Color("#e8f2ff"), 0.7)
	env.fog_density = 0.0035
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.75
	sun.light_color = Color("#fff3df")
	world.add_child(sun)
	camera = Camera3D.new()
	camera.fov = 34.0
	camera.position = Vector3(-1.0, 13.5, 15.5)
	world.add_child(camera)
	camera.look_at(Vector3(-0.5, 0.0, 0.6), Vector3.UP)
	camera.current = true
	var kit := MeshKit.new(world)
	kit.cast_shadows = false
	var ground_color := biome_color.lerp(Color("#8fcf5e"), 0.55).darkened(0.05)
	kit.box(Vector3(ARENA_X * 2.0 + 30.0, 0.4, ARENA_Z * 2.0 + 24.0), ground_color.darkened(0.08), Vector3(0, -0.2, 0))
	kit.box(Vector3(ARENA_X * 2.0 + 2.0, 0.06, ARENA_Z * 2.0 + 1.0), ground_color, Vector3(0, 0.01, 0))
	var r := RandomNumberGenerator.new()
	r.seed = abs(str(stage.seed).hash())
	for i in 40:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(r.randf_range(-ARENA_X - 8.0, ARENA_X + 8.0), 0, side * r.randf_range(ARENA_Z + 1.2, ARENA_Z + 9.0))
		if r.randf() < 0.65:
			var s := r.randf_range(0.8, 1.4)
			kit.cyl(0.13 * s, 0.2 * s, 1.3 * s, Color("#7a4d2d"), pos + Vector3(0, 0.65 * s, 0), 7)
			kit.sphere(0.95 * s, biome_color.lerp(Color("#5fae4a"), 0.55).lerp(Color.WHITE, r.randf() * 0.15), pos + Vector3(0, 1.75 * s, 0), Vector3(1, 0.9, 1), 10)
		else:
			kit.rock(r.randf_range(0.4, 0.9), Color("#b5aa98").lerp(biome_color, 0.2), pos + Vector3(0, 0.2, 0), i)
	for i in 10:
		var pos := Vector3(r.randf_range(-ARENA_X, ARENA_X), 0.08, r.randf_range(-ARENA_Z, ARENA_Z))
		kit.sphere(0.35, ground_color.darkened(0.12), pos, Vector3(1.4, 0.3, 1.0), 8)
	match str(stage.type):
		"Exploration":
			for p in poi_points:
				var node := Node3D.new()
				node.position = Vector3(p.x, 0, p.y)
				world.add_child(node)
				var pk := MeshKit.new(node)
				pk.cyl(0.9, 1.0, 0.15, Color("#e8dcc0"), Vector3(0, 0.08, 0), 14)
				pk.cyl(0.05, 0.05, 1.8, Color("#6e4a2c"), Vector3(0, 0.9, 0), 6)
				pk.box(Vector3(0.7, 0.45, 0.04), Color("#ffd166"), Vector3(0.35, 1.55, 0), Vector3.ZERO, 0.6)
				poi_nodes.append(node)
		"Defense":
			beacon_node = Node3D.new()
			beacon_node.position = Vector3(beacon_pos.x, 0, beacon_pos.y)
			world.add_child(beacon_node)
			var bk := MeshKit.new(beacon_node)
			bk.cyl(0.9, 1.1, 0.5, Color("#d8cfbd"), Vector3(0, 0.25, 0), 12)
			bk.cyl(0.35, 0.5, 2.6, Color("#e8e0cf"), Vector3(0, 1.8, 0), 10)
			bk.sphere(0.45, Color("#ffd27a"), Vector3(0, 3.4, 0), Vector3.ONE, 12, 2.5)
			var light := OmniLight3D.new()
			light.position = Vector3(0, 3.4, 0)
			light.light_color = Color("#ffd27a")
			light.omni_range = 7.0
			beacon_node.add_child(light)

# =============================================================================
# HUD
# =============================================================================

func _build_hud() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -330
	top.offset_right = 330
	top.offset_top = 14
	top.add_theme_stylebox_override("panel", UIKit.box(Color(0.1, 0.13, 0.26, 0.86), UIKit.GOLD, 2, 20, 12))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	title_label = UIKit.heading("Piano %d · %s" % [int(stage.floor), stage.name], 24, Color.WHITE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label = UIKit.label(str(stage.objective), 15, Color("#ffe39a"), UIKit.body_bold())
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label = UIKit.label("", 14, Color("#cfe3ff"), UIKit.body_bold())
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(title_label)
	tv.add_child(objective_label)
	tv.add_child(progress_label)
	top.add_child(tv)
	add_child(top)
	var clock := PanelContainer.new()
	clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock.offset_left = -250
	clock.offset_right = -18
	clock.offset_top = 14
	clock.add_theme_stylebox_override("panel", UIKit.box(Color(0.1, 0.13, 0.26, 0.86), UIKit.GOLD, 2, 20, 10))
	var ch := HBoxContainer.new()
	clock_label = UIKit.heading("00:00", 24, Color.WHITE)
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(clock_label)
	speed_button = UIKit.button("×1", _toggle_speed, "ghost", 64)
	ch.add_child(speed_button)
	clock.add_child(ch)
	add_child(clock)
	party_box = VBoxContainer.new()
	party_box.position = Vector2(16, 16)
	party_box.custom_minimum_size.x = 270
	party_box.add_theme_constant_override("separation", 6)
	add_child(party_box)
	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	log_panel.offset_left = -440
	log_panel.offset_right = -18
	log_panel.offset_top = -270
	log_panel.offset_bottom = -126
	log_panel.add_theme_stylebox_override("panel", UIKit.box(Color(0.1, 0.13, 0.26, 0.55), Color.TRANSPARENT, 0, 16, 12))
	log_box = VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 2)
	log_panel.add_child(log_box)
	add_child(log_panel)
	var commands := HBoxContainer.new()
	commands.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	commands.offset_left = -560
	commands.offset_right = 560
	commands.offset_top = -108
	commands.offset_bottom = -18
	commands.add_theme_constant_override("separation", 10)
	add_child(commands)
	var caption := PanelContainer.new()
	caption.add_theme_stylebox_override("panel", UIKit.box(Color(0.1, 0.13, 0.26, 0.86), UIKit.GOLD, 2, 16, 10))
	var cl := UIKit.label("ORDINI DEL MASTER\nSolo ordini generali:\ngli eroi decidono come.", 13, Color("#ffe39a"), UIKit.body_bold())
	caption.add_child(cl)
	commands.add_child(caption)
	_add_command(commands, "posture", "[1] Avanza", "primary")
	_add_command(commands, "focus", "[2] Alta minaccia", "sky")
	_add_command(commands, "protect", "[3] Proteggi retro", "sky")
	_add_command(commands, "all_out", "[4] Tutto per tutto", "gold")
	_add_command(commands, "extract", "[X] Ritirata", "danger")

func _add_command(parent: HBoxContainer, key: String, text: String, kind: String) -> void:
	var b := UIKit.button(text, _use_command.bind(key), kind, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 64
	b.add_theme_font_size_override("font_size", 16)
	parent.add_child(b)
	command_buttons[key] = b

func _toggle_speed() -> void:
	speed_scale = 2.0 if speed_scale < 1.5 else 1.0
	speed_button.text = "×%d" % roundi(speed_scale)

# =============================================================================
# Unità
# =============================================================================

func _create_heroes() -> void:
	for i in party_source.size():
		var source: Dictionary = party_source[i]
		if source.is_empty(): continue
		var d := GameState.derived_stats(source)
		var role := str(source.role)
		var ranged := role in ["Ranger", "Mage", "Support"]
		var unit := {
			"entity_id": next_id, "hero": true, "id": source.id, "name": str(source.name), "role": role, "source": source,
			"pos": FORMATION[i], "anchor": FORMATION[i], "hp": float(d.max_hp), "max_hp": float(d.max_hp),
			"attack": float(max(d.attack * 0.75, d.magic) if role in ["Mage", "Support"] else d.attack), "defense": float(d.defense),
			"accuracy": float(d.accuracy), "evasion": float(d.evasion), "crit": float(d.crit), "block": float(d.block),
			"range": 7.0 if role in ["Ranger", "Mage"] else 6.0 if role == "Support" else 2.0 if role == "Lancer" else 1.25,
			"speed": 3.0 if role == "Ranger" else 2.6, "cooldown": rng.randf_range(0.2, 0.8), "skill_cd": rng.randf_range(2.0, 4.0),
			"cadence": 1.35 if role in ["Mage", "Support"] else 1.0, "target": -1, "action": "hold", "alive": true,
			"kills": 0, "damage": 0, "healing": 0, "ammo": int(d.ammo), "max_ammo": int(d.ammo), "status": "", "fear": 0.0,
			"courage": int(source.personality.courage), "ranged": ranged, "threat": 0,
		}
		var model: ChibiModel = ChibiScript.new()
		world.add_child(model)
		model.build_hero(source, GameState.hero_appearance(source))
		model.scale = Vector3.ONE * 1.35
		MeshKit.new(model).blob_shadow(0.4, Vector3(0, 0.04, 0), 0.5)
		model.position = Vector3(unit.pos.x, 0, unit.pos.y)
		model.rotation.y = PI / 2
		unit.model = model
		units.append(unit)
		next_id += 1
		_make_party_card(unit)

func _make_party_card(unit: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.box(Color(1, 0.99, 0.95, 0.94), UIKit.GOLD, 2, 14, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var p: HeroPortrait = HeroPortraitScript.new()
	p.setup(unit.source, 52)
	row.add_child(p)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	v.add_child(UIKit.label(unit.name, 15, UIKit.INK, UIKit.head_font()))
	var hp := UIKit.bar(unit.hp, unit.max_hp, UIKit.TEAL, 10)
	v.add_child(hp)
	var status := UIKit.label(GameState.role_label(unit.role), 12, UIKit.INK_SOFT, UIKit.body_bold())
	v.add_child(status)
	row.add_child(v)
	card.add_child(row)
	party_box.add_child(card)
	party_cards[unit.entity_id] = {"card": card, "hp": hp, "status": status, "portrait": p}

func _spawn_enemy(kind: String, wave: int, index: int) -> void:
	var t: Dictionary = ENEMY_TEMPLATES[kind]
	var scale := 0.82 + int(stage.floor) * 0.10
	var pos := Vector2(ARENA_X - 0.5 + rng.randf_range(0.0, 1.5), clampf(-ARENA_Z + 1.0 + fmod(float(wave * 3 + index * 2), 6.0) * 2.1 + rng.randf_range(-0.5, 0.5), -ARENA_Z + 0.8, ARENA_Z - 0.8))
	var unit := {
		"entity_id": next_id, "hero": false, "kind": kind, "name": str(t.name), "pos": pos, "hp": float(t.hp) * scale, "max_hp": float(t.hp) * scale,
		"attack": float(t.attack) * scale, "defense": float(t.defense) * scale, "speed": float(t.speed), "cooldown": rng.randf_range(0.2, 0.9),
		"cadence": float(t.cadence), "threat": int(t.threat), "range": float(t.range), "target": -1, "alive": true, "slam_cd": 5.0,
		"accuracy": 82.0, "evasion": 4.0, "crit": 4.0, "block": 0.0, "ranged": kind == "archer",
	}
	var model: ChibiModel = ChibiScript.new()
	world.add_child(model)
	model.build_monster(kind, t.tint)
	model.scale = Vector3.ONE * (1.35 if kind != "boss" else 1.6)
	MeshKit.new(model).blob_shadow(0.5 if kind != "boss" else 1.2, Vector3(0, 0.04, 0), 0.5)
	model.position = Vector3(pos.x, 0, pos.y)
	model.rotation.y = -PI / 2
	unit.model = model
	units.append(unit)
	next_id += 1

func _heroes() -> Array:
	return units.filter(func(u): return u.hero and u.alive)

func _enemies() -> Array:
	return units.filter(func(u): return not u.hero and u.alive)

func _find(entity_id: int) -> Dictionary:
	for u in units:
		if int(u.entity_id) == entity_id: return u
	return {}

# =============================================================================
# Simulazione
# =============================================================================

func _process(delta: float) -> void:
	if running and not completed:
		accumulator += minf(delta, 0.1) * speed_scale
		while accumulator >= TICK and not completed:
			_tick(TICK)
			accumulator -= TICK
		_update_hud()
	for u in units:
		var model: ChibiModel = u.model
		if not is_instance_valid(model): continue
		var target := Vector3(u.pos.x, 0, u.pos.y)
		var moving := model.position.distance_to(target) > 0.02
		model.position = model.position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))
		if u.alive:
			if moving and u.get("action", "") != "attack": model.play("walk")
			elif model.anim == "walk": model.play("idle")
		model.update_animation(delta * speed_scale)
		var flash := float(u.get("flash", 0.0))
		if flash > 0.0:
			u.flash = maxf(0.0, flash - delta * 5.0)
			model.flash(u.flash * 0.9)
	_update_effects(delta)
	overlay.queue_redraw()

func _tick(delta: float) -> void:
	elapsed += delta
	decision_timer -= delta
	_spawn_waves()
	if command_state.extracting and elapsed >= float(command_state.extract_at):
		_finish(false, "extracted")
		return
	if decision_timer <= 0.0:
		decision_timer = DECISION
		_decide()
	for u in units:
		if u.alive: _update_unit(u, delta)
	_update_objective(delta)
	_check_end()

func _spawn_waves() -> void:
	for index in stage.waves.size():
		if spawned_waves.has(index): continue
		var wave: Array = stage.waves[index]
		if elapsed < float(wave[0]): continue
		spawned_waves.append(index)
		for i in int(wave[2]): _spawn_enemy(str(wave[1]), index, i)
		_log("%s: %d × %s in arrivo." % ["Contatto" if index == 0 else "Rinforzi", int(wave[2]), ENEMY_TEMPLATES[str(wave[1])].name], "warn" if index > 0 else "")

func _score_target(hero: Dictionary, enemy: Dictionary) -> float:
	var distance: float = hero.pos.distance_to(enemy.pos)
	var score := -distance
	if command_state.focus: score += float(enemy.threat) * 2.2
	score += (1.0 - float(enemy.hp) / float(enemy.max_hp)) * 2.0
	if command_state.protect and str(GameState.ROLES[hero.role].line) == "Front":
		var rear_threat := 99.0
		for ally in _heroes():
			if str(GameState.ROLES[ally.role].line) != "Front": rear_threat = minf(rear_threat, ally.pos.distance_to(enemy.pos))
		score += maxf(0.0, 6.0 - rear_threat) * 1.4
	if int(enemy.get("target", -1)) == int(hero.entity_id): score += 1.5
	var aggression := float(hero.source.personality.aggression) / 100.0
	score += aggression * float(enemy.threat) * 0.4
	return score

func _decide() -> void:
	var enemies := _enemies()
	var heroes := _heroes()
	for hero in heroes:
		if float(hero.fear) > 0.0:
			hero.action = "retreat"
			continue
		if hero.role == "Support":
			var wounded := heroes.filter(func(a): return float(a.hp) / float(a.max_hp) < 0.65)
			wounded.sort_custom(func(a, b): return float(a.hp) / float(a.max_hp) < float(b.hp) / float(b.max_hp))
			if not wounded.is_empty() and float(hero.skill_cd) <= 0.0:
				hero.target = int(wounded[0].entity_id)
				hero.action = "heal"
				continue
		if enemies.is_empty():
			hero.action = "regroup"
			continue
		var best: Dictionary = {}
		var best_score := -INF
		for enemy in enemies:
			var s := _score_target(hero, enemy)
			if s > best_score:
				best_score = s
				best = enemy
		hero.target = int(best.entity_id)
		hero.action = "engage"
	for enemy in enemies:
		var best: Dictionary = {}
		var best_distance := INF
		for hero in heroes:
			var d: float = enemy.pos.distance_to(hero.pos)
			if str(GameState.ROLES[hero.role].line) == "Front": d -= 1.2
			if d < best_distance:
				best_distance = d
				best = hero
		if str(stage.type) == "Defense" and enemy.pos.distance_to(beacon_pos) < best_distance + 1.0:
			enemy.target = -2
		else:
			enemy.target = int(best.get("entity_id", -1))

func _update_unit(u: Dictionary, delta: float) -> void:
	u.cooldown = float(u.cooldown) - delta
	if u.has("skill_cd"): u.skill_cd = float(u.skill_cd) - delta
	if u.hero: _update_hero(u, delta)
	else: _update_enemy(u, delta)
	u.pos = Vector2(clampf(u.pos.x, -ARENA_X, ARENA_X + 2.0), clampf(u.pos.y, -ARENA_Z, ARENA_Z))

func _move_towards(u: Dictionary, target: Vector2, delta: float, speed_mult: float = 1.0) -> void:
	var to: Vector2 = target - u.pos
	if to.length() < 0.05: return
	var step := float(u.speed) * delta * speed_mult
	u.pos = u.pos + to.normalized() * minf(step, to.length())
	# separazione dagli alleati
	for other in units:
		if other == u or not other.alive or other.hero != u.hero: continue
		var gap: Vector2 = u.pos - other.pos
		if gap.length() < 0.85 and gap.length() > 0.001: u.pos = u.pos + gap.normalized() * (0.85 - gap.length()) * 0.5
	_face(u, target)

func _face(u: Dictionary, target: Vector2) -> void:
	var dir: Vector2 = target - u.pos
	if dir.length() > 0.01 and is_instance_valid(u.model):
		(u.model as Node3D).rotation.y = atan2(dir.x, dir.y)

func _update_hero(hero: Dictionary, delta: float) -> void:
	if float(hero.fear) > 0.0: hero.fear = float(hero.fear) - delta
	var posture: String = command_state.posture
	var speed_mult := 1.0 if posture == "ADVANCE" else 0.6
	match str(hero.action):
		"retreat":
			_move_towards(hero, hero.anchor + Vector2(-2.0, 0.0), delta, 1.1)
			hero.status = "Spaventato"
			return
		"regroup":
			var anchor: Vector2 = hero.anchor
			if str(stage.type) == "Exploration" and int(objective.poi) < 3: anchor = poi_points[int(objective.poi)] + (hero.anchor - FORMATION[0]) * 0.5 + Vector2(-1.0, 0.0)
			_move_towards(hero, anchor, delta)
			hero.status = ""
			return
		"heal":
			var ally := _find(int(hero.target))
			if ally.is_empty() or not ally.alive: return
			if hero.pos.distance_to(ally.pos) > float(hero.range):
				_move_towards(hero, ally.pos, delta, speed_mult)
				return
			_face(hero, ally.pos)
			var amount: float = 35.0 + float(hero.source.stats.int) * 1.7
			ally.hp = minf(float(ally.max_hp), float(ally.hp) + amount)
			hero.healing = int(hero.healing) + roundi(amount)
			hero.skill_cd = 8.5
			hero.model.play("attack")
			_ring(ally.pos, Color("#59e29a"), 1.4)
			_float_text(ally.pos, "+%d" % roundi(amount), Color("#3fdc8a"))
			_log("%s cura %s (+%d)." % [hero.name, ally.name, roundi(amount)], "good")
			return
	var target := _find(int(hero.target))
	if target.is_empty() or not target.alive: return
	var distance: float = hero.pos.distance_to(target.pos)
	var reach := float(hero.range)
	if posture == "RETREAT":
		_move_towards(hero, Vector2(-ARENA_X + 1.0, hero.pos.y), delta, 1.0)
		if distance > reach: return
	elif bool(hero.ranged) and distance < 3.0 and posture != "HOLD":
		# I combattenti a distanza arretrano per mantenere lo spazio
		var away: Vector2 = hero.pos + (hero.pos - target.pos).normalized() * 1.5
		_move_towards(hero, away, delta, 0.9)
	elif distance > reach:
		if posture == "HOLD" and hero.pos.distance_to(hero.anchor) > 2.5: return
		_move_towards(hero, target.pos, delta, speed_mult)
		hero.status = ""
		return
	_face(hero, target.pos)
	if float(hero.cooldown) > 0.0: return
	if hero.role == "Ranger":
		if int(hero.ammo) <= 0:
			hero.status = "Senza frecce"
			hero.cooldown = 1.5
			hero.range = 1.2
			hero.ranged = false
			return
		hero.ammo = int(hero.ammo) - 1
		if int(hero.ammo) == 4: _log(hero.name + ": restano 4 frecce.", "warn")
	var coefficient := 1.0
	if float(hero.skill_cd) <= 0.0 and (int(target.threat) >= 3 or rng.randf() < 0.2):
		coefficient = 1.6
		hero.skill_cd = 9.0
		_ring(target.pos, UIKit.GOLD, 1.0)
		_float_text(hero.pos, str(hero.source.skills[0].name), Color("#ffe39a"))
	var all_out := elapsed < float(command_state.all_out_until)
	hero.model.play("attack")
	if bool(hero.ranged): _projectile(hero, target)
	_deal_damage(hero, target, coefficient)
	hero.cooldown = float(hero.cadence) * (0.7 if all_out else 1.0)

func _update_enemy(enemy: Dictionary, delta: float) -> void:
	if enemy.kind == "boss":
		enemy.slam_cd = float(enemy.slam_cd) - delta
		if float(enemy.slam_cd) <= 0.0:
			enemy.slam_cd = 6.5
			_ring(enemy.pos, UIKit.ROSE, 3.0)
			_log("Il Guardiano colpisce il terreno!", "danger")
			for hero in _heroes():
				if hero.pos.distance_to(enemy.pos) < 2.8: _deal_damage(enemy, hero, 0.9)
	var target_pos: Vector2
	var target: Dictionary = {}
	if int(enemy.target) == -2:
		target_pos = beacon_pos
	else:
		target = _find(int(enemy.target))
		if target.is_empty() or not target.alive: return
		target_pos = target.pos
	var distance: float = enemy.pos.distance_to(target_pos)
	if distance > float(enemy.range):
		_move_towards(enemy, target_pos, delta)
		return
	_face(enemy, target_pos)
	if float(enemy.cooldown) > 0.0: return
	enemy.cooldown = float(enemy.cadence)
	enemy.model.play("attack")
	if int(enemy.target) == -2:
		objective.beacon = maxf(0.0, float(objective.beacon) - float(enemy.attack) * 0.12)
		_float_text(beacon_pos, "-%d" % roundi(float(enemy.attack) * 0.12), UIKit.ROSE)
		return
	if bool(enemy.ranged): _projectile(enemy, target)
	_deal_damage(enemy, target, 1.0)

func _deal_damage(attacker: Dictionary, target: Dictionary, coefficient: float) -> void:
	var hit_chance := clampf(float(attacker.get("accuracy", 85.0)) - float(target.get("evasion", 0.0)), 35.0, 98.0)
	if rng.randf_range(0.0, 100.0) > hit_chance:
		_float_text(target.pos, "mancato", Color("#d8d8e0"))
		return
	var raw: float = float(attacker.attack) * coefficient * rng.randf_range(0.92, 1.08)
	var crit := rng.randf_range(0.0, 100.0) < float(attacker.get("crit", 3.0))
	if crit: raw *= 1.6
	if float(target.get("block", 0.0)) > 0.0 and rng.randf_range(0.0, 100.0) < float(target.block):
		raw *= 0.45
	var damage := maxi(1, roundi(raw * 100.0 / (100.0 + float(target.defense))))
	target.hp = maxf(0.0, float(target.hp) - damage)
	target.flash = 1.0
	attacker.damage = int(attacker.get("damage", 0)) + damage
	_float_text(target.pos, ("%d!" % damage) if crit else str(damage), Color("#ff5a6e") if target.hero else (Color("#ffd166") if crit else Color.WHITE))
	if target.hero and float(target.hp) > 0.0:
		var ratio := float(target.hp) / float(target.max_hp)
		if ratio < 0.25 and int(target.courage) < 45 and float(target.fear) <= 0.0 and command_state.posture != "ADVANCE":
			target.fear = 2.5
			_log("%s esita e arretra." % target.name, "warn")
	if float(target.hp) <= 0.0: _kill(target, attacker)

func _kill(target: Dictionary, attacker: Dictionary) -> void:
	if not target.alive: return
	target.alive = false
	(target.model as ChibiModel).play("dead")
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(target.model, "scale", Vector3.ONE * 0.01, 0.5)
	if attacker.get("hero", false): attacker.kills = int(attacker.kills) + 1
	if target.hero:
		_log("%s è caduto. Non tornerà." % target.name, "danger")
		var card: Dictionary = party_cards.get(target.entity_id, {})
		if not card.is_empty(): card.card.modulate = Color(1, 0.6, 0.6, 0.65)
		hero_died.emit(str(target.id), "Ucciso da " + str(attacker.name))
	else:
		if target.kind == "boss":
			objective.boss_dead = true
			_log("Il Guardiano è stato abbattuto!", "good")

func _update_objective(delta: float) -> void:
	match str(stage.type):
		"Exploration":
			if int(objective.poi) >= 3: return
			var p: Vector2 = poi_points[int(objective.poi)]
			var near := false
			for hero in _heroes():
				if hero.pos.distance_to(p) < 2.0: near = true
			if near and _enemies().filter(func(e): return e.pos.distance_to(p) < 4.0).is_empty():
				objective.poi_progress = float(objective.poi_progress) + delta
				if float(objective.poi_progress) >= 3.0:
					objective.poi_progress = 0.0
					objective.poi = int(objective.poi) + 1
					_ring(p, UIKit.GOLD, 2.0)
					_log("Punto d'interesse %d/3 in sicurezza." % int(objective.poi), "good")
					var done_index := int(objective.poi) - 1
					if done_index < poi_nodes.size(): create_tween().tween_property(poi_nodes[done_index], "scale", Vector3(1.0, 0.25, 1.0), 0.4)

func _check_end() -> void:
	var living_heroes := _heroes()
	var living_enemies := _enemies()
	if living_heroes.is_empty():
		_finish(false, "party_wipe")
		return
	var all_spawned: bool = spawned_waves.size() == stage.waves.size()
	match str(stage.type):
		"Survival":
			if elapsed >= float(stage.duration): _finish(true, "survived")
			return
		"Exploration":
			if int(objective.poi) >= 3 and all_spawned and living_enemies.is_empty(): _finish(true, "intel")
		"Boss":
			if bool(objective.boss_dead) and all_spawned and living_enemies.is_empty(): _finish(true, "boss")
		"Defense":
			if float(objective.beacon) <= 0.0:
				_finish(false, "beacon_lost")
				return
			if all_spawned and living_enemies.is_empty(): _finish(true, "clear")
		_:
			if all_spawned and living_enemies.is_empty(): _finish(true, "clear")
	if not completed and elapsed >= float(stage.duration) and str(stage.type) != "Survival": _finish(false, "timeout")

func _finish(victory: bool, reason: String) -> void:
	if completed: return
	completed = true
	running = false
	var hero_results := []
	for u in units:
		if not u.hero: continue
		hero_results.append({"id": u.id, "alive": u.alive, "hp_ratio": float(u.hp) / float(u.max_hp), "kills": int(u.kills), "fatigue": roundi(10 + elapsed * 0.28 + (7 if float(u.hp) / float(u.max_hp) < 0.3 else 0))})
	for u in _heroes(): (u.model as ChibiModel).play("cheer" if victory else "idle")
	var banner := UIKit.pill("VITTORIA!" if victory else "RITIRATA" if reason == "extracted" else "SCONFITTA", UIKit.GOLD if victory else UIKit.ROSE, Color.WHITE, 46)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -200
	banner.offset_right = 200
	banner.offset_top = -50
	banner.offset_bottom = 50
	add_child(banner)
	await get_tree().create_timer(1.6).timeout
	battle_finished.emit({"victory": victory, "reason": reason, "duration": elapsed, "floor": int(stage.floor), "hero_results": hero_results})

# =============================================================================
# Ordini del Master
# =============================================================================

func _use_command(key: String) -> void:
	if completed or elapsed < float(command_ready[key]): return
	match key:
		"posture":
			var options := ["ADVANCE", "HOLD", "RETREAT"]
			command_state.posture = options[(options.find(command_state.posture) + 1) % options.size()]
			command_ready[key] = elapsed + 8.0
			_log("Ordine: " + {"ADVANCE": "avanzare", "HOLD": "mantenere la posizione", "RETREAT": "arretrare"}[command_state.posture] + ".", "warn")
		"focus":
			command_state.focus = not command_state.focus
			command_ready[key] = elapsed + 12.0
			_log("Priorità ai bersagli pericolosi: %s." % ("sì" if command_state.focus else "no"), "warn")
		"protect":
			command_state.protect = not command_state.protect
			command_ready[key] = elapsed + 12.0
			_log("Proteggere la retroguardia: %s." % ("sì" if command_state.protect else "no"), "warn")
		"all_out":
			command_state.all_out_until = elapsed + 10.0
			command_ready[key] = elapsed + 40.0
			_log("Tutto per tutto: 10 secondi di assalto.", "warn")
		"extract":
			command_state.extracting = true
			command_state.extract_at = elapsed + 6.0
			command_ready[key] = INF
			command_state.posture = "RETREAT"
			_log("Ritirata: estrazione tra 6 secondi.", "danger")
	_update_hud()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("macro_posture"): _use_command("posture")
	elif event.is_action_pressed("macro_focus"): _use_command("focus")
	elif event.is_action_pressed("macro_protect"): _use_command("protect")
	elif event.is_action_pressed("macro_all_out"): _use_command("all_out")
	elif event.is_action_pressed("macro_extract"): _use_command("extract")

func _update_hud() -> void:
	clock_label.text = "%02d:%02d" % [floori(elapsed / 60.0), floori(elapsed) % 60]
	var living := _enemies().size()
	match str(stage.type):
		"Survival": progress_label.text = "%d secondi alla fine" % maxi(0, ceili(float(stage.duration) - elapsed))
		"Exploration": progress_label.text = "Punti %d/3 · %d nemici" % [int(objective.poi), living]
		"Defense": progress_label.text = "Faro %d%% · %d nemici" % [roundi(float(objective.beacon)), living]
		_: progress_label.text = "%d nemici in campo · ondate %d/%d" % [living, spawned_waves.size(), stage.waves.size()]
	for u in units:
		if not u.hero: continue
		var card: Dictionary = party_cards.get(u.entity_id, {})
		if card.is_empty(): continue
		card.hp.max_value = float(u.max_hp)
		card.hp.value = float(u.hp)
		var text := GameState.role_label(u.role)
		if not u.alive: text = "Caduto"
		elif int(u.max_ammo) > 0: text += " · frecce %d/%d" % [int(u.ammo), int(u.max_ammo)]
		if u.alive and not str(u.status).is_empty(): text += " · " + str(u.status)
		card.status.text = text
	var labels := {"posture": "[1] " + {"ADVANCE": "Avanza", "HOLD": "Mantieni", "RETREAT": "Arretra"}[command_state.posture], "focus": "[2] Alta minaccia" + (" ✓" if command_state.focus else ""), "protect": "[3] Proteggi retro" + (" ✓" if command_state.protect else ""), "all_out": "[4] Tutto per tutto", "extract": "[X] Ritirata"}
	for key in command_buttons:
		var b: Button = command_buttons[key]
		var remaining := float(command_ready[key]) - elapsed
		b.disabled = remaining > 0.0 or completed
		b.text = labels[key] + (("  %ds" % ceili(remaining)) if remaining > 0.0 and remaining < 999.0 else "")

# =============================================================================
# Effetti
# =============================================================================

func _ring(pos: Vector2, color: Color, radius: float) -> void:
	var kit := MeshKit.new(world)
	kit.cast_shadows = false
	var ring := kit.torus(radius * 0.3, radius * 0.3 + 0.12, color, Vector3(pos.x, 0.12, pos.y), Vector3.ZERO, 2.0, 28)
	effects.append({"node": ring, "life": 0.6, "max": 0.6, "grow": radius})

func _projectile(from: Dictionary, to: Dictionary) -> void:
	var kit := MeshKit.new(world)
	kit.cast_shadows = false
	var color := Color("#ff8a3d") if from.get("role", "") == "Mage" else Color("#59e29a") if from.get("role", "") == "Support" else Color("#f4e6c8") if from.hero else Color("#ff5a6e")
	var orb := kit.sphere(0.13, color, Vector3(from.pos.x, 0.9, from.pos.y), Vector3(1.6, 1, 1) if from.get("role", "") == "Ranger" else Vector3.ONE, 8, 2.5)
	effects.append({"node": orb, "life": 0.25, "max": 0.25, "from": Vector3(from.pos.x, 0.9, from.pos.y), "to": Vector3(to.pos.x, 0.8, to.pos.y)})

func _float_text(pos: Vector2, text: String, color: Color) -> void:
	floaters.append({"pos": Vector3(pos.x + rng.randf_range(-0.3, 0.3), 1.6, pos.y), "text": text, "color": color, "life": 0.9})

func _update_effects(delta: float) -> void:
	for e in effects:
		e.life = float(e.life) - delta * speed_scale
		var node: Node3D = e.node
		if not is_instance_valid(node): continue
		var k := 1.0 - float(e.life) / float(e.max)
		if e.has("grow"):
			node.scale = Vector3.ONE * (1.0 + k * 2.5)
			node.transparency = k
		elif e.has("from"):
			node.position = (e.from as Vector3).lerp(e.to, k) + Vector3(0, sin(k * PI) * 0.6, 0)
	for e in effects.filter(func(x): return float(x.life) <= 0.0):
		if is_instance_valid(e.node): e.node.queue_free()
	effects = effects.filter(func(x): return float(x.life) > 0.0)
	for f in floaters:
		f.life = float(f.life) - delta
		f.pos = (f.pos as Vector3) + Vector3(0, delta * 1.2, 0)
	floaters = floaters.filter(func(x): return float(x.life) > 0.0)

func _draw_overlay() -> void:
	if camera == null: return
	var font := UIKit.head_font()
	var body := UIKit.body_bold()
	for u in units:
		if not u.alive: continue
		var world_pos := Vector3(u.pos.x, 2.2 if u.get("kind", "") != "boss" else 3.6, u.pos.y)
		if camera.is_position_behind(world_pos): continue
		var p := camera.unproject_position(world_pos)
		var w := 58.0 if u.get("kind", "") != "boss" else 150.0
		var ratio := clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)
		overlay.draw_rect(Rect2(p + Vector2(-w * 0.5 - 2, -2), Vector2(w + 4, 11)), Color(0.08, 0.08, 0.16, 0.85))
		overlay.draw_rect(Rect2(p + Vector2(-w * 0.5, 0), Vector2(w * ratio, 7)), Color("#3fdc8a") if u.hero else Color("#ff5a6e"))
		if u.hero:
			var name_text := str(u.name).split(" ")[0]
			var size := body.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			overlay.draw_string_outline(body, p + Vector2(-size.x * 0.5, -6), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0.08, 0.08, 0.16))
			overlay.draw_string(body, p + Vector2(-size.x * 0.5, -6), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	for f in floaters:
		if camera.is_position_behind(f.pos): continue
		var p := camera.unproject_position(f.pos)
		var alpha := clampf(float(f.life) / 0.4, 0.0, 1.0)
		var col: Color = f.color
		col.a = alpha
		var size := font.get_string_size(str(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		overlay.draw_string_outline(font, p - Vector2(size.x * 0.5, 0), str(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0.08, 0.08, 0.16, alpha))
		overlay.draw_string(font, p - Vector2(size.x * 0.5, 0), str(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
	if str(stage.type) == "Exploration" and int(objective.poi) < 3:
		var target := poi_points[int(objective.poi)]
		var p := camera.unproject_position(Vector3(target.x, 2.4, target.y))
		overlay.draw_string_outline(font, p + Vector2(-40, 0), "Obiettivo", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0.08, 0.08, 0.16))
		overlay.draw_string(font, p + Vector2(-40, 0), "Obiettivo", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ffe39a"))

func _log(message: String, tone: String = "") -> void:
	var color := Color("#ffe39a") if tone == "warn" else Color("#ff8a9a") if tone == "danger" else Color("#8ff0c0") if tone == "good" else Color("#dfe7ff")
	var line := UIKit.label("%02d:%02d  %s" % [floori(elapsed / 60.0), floori(elapsed) % 60, message], 14, color, UIKit.body_bold())
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_box.add_child(line)
	log_box.move_child(line, 0)
	while log_box.get_child_count() > 6:
		var last := log_box.get_child(log_box.get_child_count() - 1)
		log_box.remove_child(last)
		last.queue_free()
