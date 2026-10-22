extends Node3D
class_name HubAgent

## Una persona che vive nella base: gli eroi camminano per le strade, si allenano
## nel cortile rialzato, entrano nel Dormitorio per riposare, chiacchierano in
## piazza. Gli abitanti (non cliccabili) passeggiano e animano il borgo.

var world: HubWorld
var hero_id := ""
var hero_name := ""
var model: CharacterModel
var activity := ""
var slot := -1
var route: PackedVector3Array = PackedVector3Array()
var route_index := 0
var goal_node := -1
var goal_anim := "idle"
var goal_offset := Vector3.ZERO
var arrived := false
var wait := 0.0
var speed := 1.3
var forced := false
var inside := false
var villager := false
var emote: Label3D
var name_tag: Label3D
var rng := RandomNumberGenerator.new()
var emote_timer := 0.0
var body: StaticBody3D

func setup(hub: HubWorld, hero: Dictionary, appearance: Dictionary) -> void:
	world = hub
	hero_id = str(hero.id)
	hero_name = str(hero.name)
	rng.seed = abs(hero_id.hash())
	speed = 1.2 + rng.randf_range(0.0, 0.35)
	model = CharacterModel.new()
	add_child(model)
	model.build_hero(hero, appearance)
	model.phase = rng.randf_range(0, 10)
	body = StaticBody3D.new()
	body.collision_layer = 4
	body.set_meta("hero_id", hero_id)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.1
	shape.shape = capsule
	shape.position = Vector3(0, 0.5, 0)
	body.add_child(shape)
	add_child(body)
	emote = _tag(UIKit.head_font(), 28, Vector3(0, 1.2, 0))
	emote.visible = false
	name_tag = _tag(UIKit.body_bold(), 19, Vector3(0, 1.05, 0))
	name_tag.text = hero_name
	name_tag.visible = false

func setup_villager(hub: HubWorld, seed_value: int) -> void:
	world = hub
	villager = true
	rng.seed = seed_value
	speed = 0.9 + rng.randf_range(0.0, 0.3)
	model = CharacterModel.new()
	add_child(model)
	model.build_villager(seed_value)
	model.phase = rng.randf_range(0, 10)
	activity = "idle"

func _tag(font: Font, size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.font_size = size
	l.outline_size = 8
	l.outline_modulate = Color(0.06, 0.04, 0.07, 0.92)
	l.modulate = Color("#f1e6cf")
	l.pixel_size = 0.0009
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	add_child(l)
	return l

func set_collision_enabled(value: bool) -> void:
	if body != null: body.collision_layer = 4 if value else 0

func set_activity(new_activity: String, new_slot: int, hero: Dictionary) -> void:
	hero_name = str(hero.name)
	name_tag.text = "%s · Lv.%d" % [hero_name, int(hero.level)]
	if new_activity == activity and new_slot == slot: return
	activity = new_activity
	slot = new_slot
	if inside and activity != "resting": _leave_building()
	if not forced: _choose_goal()
	_update_emote()

func _leave_building() -> void:
	inside = false
	visible = true
	set_collision_enabled(true)

func reset_route() -> void:
	if not forced: _choose_goal()

func force_goal(node: int, anim_name: String) -> void:
	forced = true
	if inside: _leave_building()
	_go(node, anim_name, Vector3.ZERO)

func release_goal() -> void:
	forced = false
	speed = 1.2 + rng.randf_range(0.0, 0.35)
	if activity != "resting" or not inside:
		visible = true
		set_collision_enabled(true)
	_choose_goal()

func show_hover(value: bool) -> void:
	if name_tag != null: name_tag.visible = value

func pop_emote(text: String, seconds: float = 2.5) -> void:
	if emote == null: return
	emote.text = text
	emote.modulate = Color("#e8c47e")
	emote.visible = true
	emote_timer = seconds

func _update_emote() -> void:
	if emote == null or emote_timer > 0.0: return
	if activity == "injured":
		emote.text = "✚"
		emote.modulate = Color("#e05a6a")
		emote.visible = true
	else:
		emote.visible = false

func _choose_goal() -> void:
	if world == null or world.nav.get_point_count() == 0: return
	var sites: Dictionary = world.site_nodes
	match activity:
		"training":
			var spots: Array = sites.get("training", {}).get("spots", [])
			if not spots.is_empty():
				_go(spots[maxi(0, slot) % spots.size()], "train", Vector3.ZERO)
				return
		"resting":
			if sites.has("dormitory"):
				_go(sites.dormitory.door, "enter", Vector3.ZERO)
				return
		"injured":
			var bench: Array = sites.get("dormitory", {}).get("spots", [])
			if not bench.is_empty():
				_go(bench[rng.randi_range(0, bench.size() - 1)], "rest", Vector3(rng.randf_range(-0.1, 0.1), 0, 0))
				return
		"party":
			var near_gate: Array[int] = []
			var gdir := Vector3(cos(HubWorld.GATE_ANGLE), 0, sin(HubWorld.GATE_ANGLE))
			for n in world.plaza_nodes + world.ring_nodes:
				if world.node_position(n).normalized().dot(gdir) > 0.75: near_gate.append(n)
			if not near_gate.is_empty():
				_go(near_gate[rng.randi_range(0, near_gate.size() - 1)], ["idle", "talk", "idle"][rng.randi_range(0, 2)], _jitter(0.4))
				return
	if not world.wander_nodes.is_empty():
		var node: int = world.wander_nodes[rng.randi_range(0, world.wander_nodes.size() - 1)]
		_go(node, ["idle", "talk", "idle", "idle"][rng.randi_range(0, 3)], _jitter(0.45))

func _jitter(amount: float) -> Vector3:
	return Vector3(rng.randf_range(-amount, amount), 0, rng.randf_range(-amount, amount))

func _go(node: int, anim_name: String, offset: Vector3) -> void:
	goal_node = node
	goal_anim = anim_name
	goal_offset = offset
	arrived = false
	route = world.route(position, node) if node >= 0 else PackedVector3Array()
	route_index = 0
	wait = rng.randf_range(6.0, 14.0)
	if route.is_empty(): arrived = true

func tick(delta: float) -> void:
	if model == null: return
	if emote_timer > 0.0:
		emote_timer -= delta
		if emote_timer <= 0.0: _update_emote()
	if inside: return
	if not arrived and route_index < route.size():
		var target := route[route_index]
		if route_index == route.size() - 1: target += goal_offset
		var to_target := target - position
		var step := speed * delta
		if to_target.length() <= step:
			position = target
			route_index += 1
			if route_index >= route.size(): _arrive()
		else:
			position += to_target.normalized() * step
			var flat := Vector3(to_target.x, 0, to_target.z)
			if flat.length() > 0.01: _face(flat, delta)
			model.play("walk")
	elif not arrived:
		_arrive()
	else:
		if goal_anim == "train":
			var focus := world.facing_target_for("training", slot)
			var flat := Vector3(focus.x - position.x, 0, focus.z - position.z)
			if flat.length() > 0.05: _face(flat, delta)
		elif goal_anim == "rest":
			var away := Vector3(position.x, 0, position.z) - Vector3(world.buildings.dormitory.position.x, 0, world.buildings.dormitory.position.z) if world.buildings.has("dormitory") else Vector3.FORWARD
			if away.length() > 0.05: _face(away, delta)
		elif not forced and activity in ["idle", "party", ""]:
			wait -= delta
			if wait <= 0.0: _choose_goal()
	model.update_animation(delta)

func _face(direction: Vector3, delta: float) -> void:
	var yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))

func _arrive() -> void:
	arrived = true
	if goal_anim == "enter":
		inside = true
		visible = false
		set_collision_enabled(false)
		return
	model.play(goal_anim if goal_anim in ["idle", "talk", "train", "cheer", "rest", "sit"] else "idle")
	if goal_anim == "talk": rotation.y += rng.randf_range(-1.5, 1.5)
