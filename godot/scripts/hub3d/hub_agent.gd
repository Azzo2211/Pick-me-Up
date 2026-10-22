extends Node3D
class_name HubAgent

## Un eroe che vive nella base: cammina sui sentieri, si allena sul campo
## rialzato, entra nel Dormitorio per riposare, chiacchiera in piazza.

const ChibiScript := preload("res://scripts/hub3d/chibi_model.gd")

var world: HubWorld
var hero_id := ""
var hero_name := ""
var model: ChibiModel
var activity := ""
var slot := -1
var route: PackedVector3Array = PackedVector3Array()
var route_index := 0
var goal_node := -1
var goal_anim := "idle"
var goal_offset := Vector3.ZERO
var arrived := false
var wait := 0.0
var speed := 1.8
var forced := false
var inside := false
var emote: Label3D
var name_tag: Label3D
var rng := RandomNumberGenerator.new()
var emote_timer := 0.0

func setup(hub: HubWorld, hero: Dictionary, appearance: Dictionary) -> void:
	world = hub
	hero_id = str(hero.id)
	hero_name = str(hero.name)
	rng.seed = abs(hero_id.hash())
	speed = 1.6 + rng.randf_range(0.0, 0.5)
	model = ChibiScript.new()
	add_child(model)
	model.build_hero(hero, appearance)
	model.scale = Vector3.ONE * 1.3
	model.phase = rng.randf_range(0, 10)
	MeshKit.new(self).blob_shadow(0.42, Vector3(0, 0.05, 0), 0.5)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.set_meta("hero_id", hero_id)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.3
	shape.shape = capsule
	shape.position = Vector3(0, 0.65, 0)
	body.add_child(shape)
	add_child(body)
	emote = Label3D.new()
	emote.font = UIKit.head_font()
	emote.font_size = 30
	emote.outline_size = 10
	emote.outline_modulate = Color("#1a2342")
	emote.pixel_size = 0.0009
	emote.fixed_size = true
	emote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	emote.no_depth_test = true
	emote.position = Vector3(0, 1.55, 0)
	emote.visible = false
	add_child(emote)
	name_tag = Label3D.new()
	name_tag.font = UIKit.body_bold()
	name_tag.font_size = 20
	name_tag.outline_size = 8
	name_tag.outline_modulate = Color("#1a2342")
	name_tag.pixel_size = 0.0009
	name_tag.fixed_size = true
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.no_depth_test = true
	name_tag.position = Vector3(0, 1.35, 0)
	name_tag.text = hero_name
	name_tag.visible = false
	add_child(name_tag)

func set_activity(new_activity: String, new_slot: int, hero: Dictionary) -> void:
	hero_name = str(hero.name)
	name_tag.text = "%s  ·  Lv.%d" % [hero_name, int(hero.level)]
	if new_activity == activity and new_slot == slot: return
	activity = new_activity
	slot = new_slot
	if inside and activity != "resting":
		inside = false
		visible = true
	if not forced: _choose_goal()
	_update_emote()

func reset_route() -> void:
	if not forced: _choose_goal()

func force_goal(node: int, anim_name: String) -> void:
	forced = true
	inside = false
	visible = true
	_go(node, anim_name, Vector3.ZERO)

func release_goal() -> void:
	forced = false
	_choose_goal()

func show_hover(value: bool) -> void:
	name_tag.visible = value

func pop_emote(text: String, seconds: float = 2.5) -> void:
	emote.text = text
	emote.modulate = Color("#ffe39a")
	emote.visible = true
	emote_timer = seconds

func _update_emote() -> void:
	if emote_timer > 0.0: return
	match activity:
		"injured":
			emote.text = "✚"
			emote.modulate = Color("#ff6b81")
			emote.visible = true
		_:
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
				_go(bench[rng.randi_range(0, bench.size() - 1)], "sit", Vector3(rng.randf_range(-0.2, 0.2), 0, 0))
				return
		"party":
			var near_gate: Array[int] = []
			for n in world.plaza_nodes:
				var p := world.node_position(n)
				if p.x > -0.5 and p.z < 0.5: near_gate.append(n)
			if not near_gate.is_empty():
				_go(near_gate[rng.randi_range(0, near_gate.size() - 1)], ["idle", "talk", "cheer"][rng.randi_range(0, 2)], _jitter(0.45))
				return
	if not world.wander_nodes.is_empty():
		var node: int = world.wander_nodes[rng.randi_range(0, world.wander_nodes.size() - 1)]
		_go(node, ["idle", "talk", "idle", "sit"][rng.randi_range(0, 3)], _jitter(0.5))

func _jitter(amount: float) -> Vector3:
	return Vector3(rng.randf_range(-amount, amount), 0, rng.randf_range(-amount, amount))

func _go(node: int, anim_name: String, offset: Vector3) -> void:
	goal_node = node
	goal_anim = anim_name
	goal_offset = offset
	arrived = false
	route = world.route(position, node) if node >= 0 else PackedVector3Array()
	route_index = 0
	wait = rng.randf_range(5.0, 11.0)
	if route.is_empty(): arrived = true

func tick(delta: float) -> void:
	if model == null: return
	if emote_timer > 0.0:
		emote_timer -= delta
		if emote_timer <= 0.0: _update_emote()
	if inside:
		return
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
		elif not forced and activity in ["idle", "party"]:
			wait -= delta
			if wait <= 0.0: _choose_goal()
	model.update_animation(delta)

func _face(direction: Vector3, delta: float) -> void:
	var yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 10.0, 0.0, 1.0))

func _arrive() -> void:
	arrived = true
	if goal_anim == "enter":
		inside = true
		visible = false
		return
	model.play(goal_anim if goal_anim != "enter" else "idle")
	if goal_anim == "talk": rotation.y += rng.randf_range(-1.5, 1.5)
