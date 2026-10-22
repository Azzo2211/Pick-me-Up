extends Node3D
class_name ChibiModel

## Personaggio chibi procedurale (eroi e mostri). Usato nella base e in battaglia.
## Il modello guarda verso +Z; l'animazione è procedurale (camminata, attacco, riposo…).

var kit: MeshKit
var body: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var weapon_pivot: Node3D
var anim := "idle"
var phase := 0.0
var attack_timer := 0.0
var base_height := 0.0
var is_monster := false
var monster_kind := ""

func build_hero(hero: Dictionary, appearance: Dictionary) -> void:
	kit = MeshKit.new(self)
	var outfit: Color = appearance.outfit
	var skin: Color = appearance.skin
	var hair: Color = appearance.hair
	var role := str(hero.get("role", "Guardian"))
	var rarity := int(hero.get("current_rarity", 1))
	body = Node3D.new(); add_child(body)
	# Gambe
	leg_l = _limb(Vector3(-0.075, 0.27, 0)); leg_r = _limb(Vector3(0.075, 0.27, 0))
	for leg in [leg_l, leg_r]:
		kit.capsule(0.068, 0.28, outfit.darkened(0.45), Vector3(0, -0.12, 0), Vector3.ZERO, leg)
		kit.sphere(0.075, Color("#5a3d2b"), Vector3(0, -0.24, 0.025), Vector3(1, 0.7, 1.3), 8, 0.0, leg)
	# Busto e tunica
	kit.cyl(0.13, 0.22, 0.24, outfit.darkened(0.1), Vector3(0, 0.33, 0), 12, Vector3.ZERO, 0.0, body)
	kit.capsule(0.155, 0.36, outfit, Vector3(0, 0.47, 0), Vector3.ZERO, body)
	kit.cyl(0.158, 0.158, 0.05, Color("#6b4a2f"), Vector3(0, 0.38, 0), 12, Vector3.ZERO, 0.0, body)
	if rarity >= 4:
		kit.torus(0.13, 0.17, UIKit.rarity_color(rarity), Vector3(0, 0.6, 0), Vector3.ZERO, 0.4, 16, body)
	# Braccia
	arm_l = _limb(Vector3(-0.19, 0.58, 0), body); arm_r = _limb(Vector3(0.19, 0.58, 0), body)
	for arm in [arm_l, arm_r]:
		kit.capsule(0.055, 0.25, outfit.lightened(0.08), Vector3(0, -0.1, 0), Vector3.ZERO, arm)
		kit.sphere(0.058, skin, Vector3(0, -0.23, 0), Vector3.ONE, 8, 0.0, arm)
	weapon_pivot = Node3D.new(); weapon_pivot.position = Vector3(0, -0.23, 0.02); arm_r.add_child(weapon_pivot)
	_build_weapon(role)
	# Testa grande stile chibi
	head = Node3D.new(); head.position = Vector3(0, 0.66, 0); body.add_child(head)
	kit.sphere(0.215, skin, Vector3(0, 0.2, 0), Vector3(1.0, 0.96, 0.98), 16, 0.0, head)
	kit.sphere(0.232, hair, Vector3(0, 0.25, -0.025), Vector3(1.02, 0.9, 1.0), 14, 0.0, head)
	kit.box(Vector3(0.36, 0.1, 0.12), hair, Vector3(0, 0.33, 0.15), Vector3(0.35, 0, 0), 0.0, head)
	for side in [-1.0, 1.0]:
		kit.box(Vector3(0.09, 0.2, 0.1), hair, Vector3(0.17 * side, 0.18, 0.1), Vector3(0, 0, 0.12 * side), 0.0, head)
	match int(appearance.hair_style):
		0: kit.sphere(0.11, hair, Vector3(0, 0.27, -0.24), Vector3(0.9, 1.2, 1.0), 10, 0.0, head)
		1:
			for i in 4: kit.cone(0.07, 0.2, hair, Vector3(-0.12 + i * 0.08, 0.45, -0.02 - (i % 2) * 0.05), 6, 0.0, head)
		2: kit.box(Vector3(0.36, 0.42, 0.12), hair, Vector3(0, 0.05, -0.17), Vector3.ZERO, 0.0, head)
		3:
			for side in [-1.0, 1.0]: kit.sphere(0.085, hair, Vector3(0.2 * side, 0.4, -0.05), Vector3.ONE, 10, 0.0, head)
	# Occhi grandi
	for side in [-1.0, 1.0]:
		kit.sphere(0.048, Color("#1d1a2a"), Vector3(0.078 * side, 0.18, 0.185), Vector3(0.85, 1.25, 0.5), 10, 0.0, head)
		kit.sphere(0.03, appearance.eyes, Vector3(0.078 * side, 0.165, 0.2), Vector3(0.85, 1.1, 0.5), 8, 0.2, head)
		kit.sphere(0.013, Color.WHITE, Vector3(0.068 * side + 0.012, 0.2, 0.215), Vector3.ONE, 6, 0.6, head)
		kit.sphere(0.03, Color("#ff9fae"), Vector3(0.13 * side, 0.12, 0.17), Vector3(1.2, 0.6, 0.4), 8, 0.0, head)
	base_height = 0.0

func build_monster(kind: String, tint: Color) -> void:
	kit = MeshKit.new(self)
	is_monster = true
	monster_kind = kind
	body = Node3D.new(); add_child(body)
	var dark := tint.darkened(0.45)
	match kind:
		"hound":
			kit.capsule(0.2, 0.75, tint, Vector3(0, 0.36, 0), Vector3(PI / 2, 0, 0), body)
			head = Node3D.new(); head.position = Vector3(0, 0.48, 0.36); body.add_child(head)
			kit.sphere(0.17, tint, Vector3.ZERO, Vector3(1, 0.9, 1.2), 10, 0.0, head)
			kit.cone(0.06, 0.16, dark, Vector3(-0.09, 0.17, -0.03), 5, 0.0, head)
			kit.cone(0.06, 0.16, dark, Vector3(0.09, 0.17, -0.03), 5, 0.0, head)
			for side in [-1.0, 1.0]: kit.sphere(0.03, Color("#ffde4a"), Vector3(0.07 * side, 0.04, 0.17), Vector3.ONE, 6, 1.5, head)
			leg_l = _limb(Vector3(-0.12, 0.25, 0.22)); leg_r = _limb(Vector3(0.12, 0.25, 0.22))
			arm_l = _limb(Vector3(-0.12, 0.25, -0.22)); arm_r = _limb(Vector3(0.12, 0.25, -0.22))
			for limb in [leg_l, leg_r, arm_l, arm_r]: kit.capsule(0.055, 0.28, dark, Vector3(0, -0.12, 0), Vector3.ZERO, limb)
		"brute", "boss":
			var s := 1.0 if kind == "brute" else 1.7
			kit.capsule(0.32 * s, 0.75 * s, tint, Vector3(0, 0.55 * s, 0), Vector3.ZERO, body)
			head = Node3D.new(); head.position = Vector3(0, 1.0 * s, 0.05); body.add_child(head)
			kit.sphere(0.22 * s, tint.lightened(0.1), Vector3.ZERO, Vector3.ONE, 12, 0.0, head)
			for side in [-1.0, 1.0]:
				kit.cone(0.07 * s, 0.28 * s, Color("#f2e6c8"), Vector3(0.16 * s * side, 0.2 * s, 0), 6, 0.0, head)
				kit.sphere(0.04 * s, Color("#ff4a3a"), Vector3(0.08 * s * side, 0.03 * s, 0.19 * s), Vector3.ONE, 6, 2.0, head)
			if kind == "boss":
				for i in 5: kit.cone(0.06, 0.3, Color("#ffd04a"), Vector3(-0.24 + i * 0.12, 0.42 * s, -0.04), 5, 0.6, head)
			leg_l = _limb(Vector3(-0.16 * s, 0.32 * s, 0)); leg_r = _limb(Vector3(0.16 * s, 0.32 * s, 0))
			for leg in [leg_l, leg_r]: kit.capsule(0.1 * s, 0.36 * s, dark, Vector3(0, -0.15 * s, 0), Vector3.ZERO, leg)
			arm_l = _limb(Vector3(-0.38 * s, 0.82 * s, 0), body); arm_r = _limb(Vector3(0.38 * s, 0.82 * s, 0), body)
			for arm in [arm_l, arm_r]:
				kit.capsule(0.1 * s, 0.48 * s, tint.darkened(0.15), Vector3(0, -0.22 * s, 0), Vector3.ZERO, arm)
				kit.sphere(0.12 * s, dark, Vector3(0, -0.45 * s, 0), Vector3.ONE, 8, 0.0, arm)
			weapon_pivot = Node3D.new(); weapon_pivot.position = Vector3(0, -0.45 * s, 0.05); arm_r.add_child(weapon_pivot)
			kit.cyl(0.05 * s, 0.07 * s, 0.7 * s, Color("#6b4a2f"), Vector3(0, 0, 0.3 * s), 6, Vector3(PI / 2, 0, 0), 0.0, weapon_pivot)
			kit.sphere(0.13 * s, Color("#5b5560"), Vector3(0, 0, 0.62 * s), Vector3.ONE, 8, 0.0, weapon_pivot)
		_:
			# raider / archer: figura incappucciata
			leg_l = _limb(Vector3(-0.08, 0.27, 0)); leg_r = _limb(Vector3(0.08, 0.27, 0))
			for leg in [leg_l, leg_r]: kit.capsule(0.07, 0.28, dark, Vector3(0, -0.12, 0), Vector3.ZERO, leg)
			kit.cyl(0.12, 0.26, 0.5, tint, Vector3(0, 0.45, 0), 10, Vector3.ZERO, 0.0, body)
			head = Node3D.new(); head.position = Vector3(0, 0.72, 0); body.add_child(head)
			kit.sphere(0.2, dark.darkened(0.3), Vector3(0, 0.1, 0.02), Vector3.ONE, 10, 0.0, head)
			kit.cone(0.22, 0.36, tint, Vector3(0, 0.2, -0.04), 10, 0.0, head)
			for side in [-1.0, 1.0]: kit.sphere(0.035, Color("#ff5a3d"), Vector3(0.07 * side, 0.1, 0.18), Vector3(1, 0.6, 0.5), 6, 2.5, head)
			arm_l = _limb(Vector3(-0.2, 0.6, 0), body); arm_r = _limb(Vector3(0.2, 0.6, 0), body)
			for arm in [arm_l, arm_r]: kit.capsule(0.055, 0.26, tint.darkened(0.15), Vector3(0, -0.1, 0), Vector3.ZERO, arm)
			weapon_pivot = Node3D.new(); weapon_pivot.position = Vector3(0, -0.23, 0.02); arm_r.add_child(weapon_pivot)
			if kind == "archer":
				var bow := kit.torus(0.3, 0.34, Color("#5a3d2b"), Vector3(0, 0, 0.05), Vector3(0, 0, PI / 2), 0.0, 16, arm_l)
				bow.position = Vector3(0, -0.24, 0.08)
				bow.scale = Vector3(1, 1, 0.3)
			else:
				kit.box(Vector3(0.05, 0.05, 0.42), Color("#c9ccd6"), Vector3(0, 0, 0.22), Vector3.ZERO, 0.0, weapon_pivot)

func _limb(pos: Vector3, target: Node3D = null) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	(target if target != null else body).add_child(pivot)
	return pivot

func _build_weapon(role: String) -> void:
	var steel := Color("#dfe4ee")
	var wood := Color("#8a5a35")
	var gold := Color("#e8b23a")
	match role:
		"Guardian":
			kit.box(Vector3(0.05, 0.05, 0.4), steel, Vector3(0, 0, 0.2), Vector3.ZERO, 0.0, weapon_pivot)
			kit.box(Vector3(0.16, 0.03, 0.03), gold, Vector3(0, 0, 0.02), Vector3.ZERO, 0.0, weapon_pivot)
			var shield := kit.cyl(0.17, 0.17, 0.04, Color("#3f7fd6"), Vector3(-0.04, -0.2, 0.06), 12, Vector3(0, 0, PI / 2), 0.0, arm_l)
			kit.cyl(0.07, 0.07, 0.05, gold, Vector3(-0.065, -0.2, 0.06), 10, Vector3(0, 0, PI / 2), 0.0, arm_l)
			shield.position.x = -0.05
		"Vanguard":
			kit.box(Vector3(0.09, 0.04, 0.6), steel, Vector3(0, 0, 0.3), Vector3.ZERO, 0.0, weapon_pivot)
			kit.box(Vector3(0.2, 0.04, 0.04), gold, Vector3(0, 0, 0.01), Vector3.ZERO, 0.0, weapon_pivot)
		"Lancer":
			kit.cyl(0.022, 0.022, 0.95, wood, Vector3(0, 0, 0.25), 6, Vector3(PI / 2, 0, 0), 0.0, weapon_pivot)
			kit.cone(0.05, 0.16, steel, Vector3(0, 0, 0.78), 6, 0.0, weapon_pivot).rotation = Vector3(PI / 2, 0, 0)
		"Ranger":
			var bow := kit.torus(0.26, 0.29, wood, Vector3(0, -0.24, 0.08), Vector3(0, 0, PI / 2), 0.0, 16, arm_l)
			bow.scale = Vector3(1, 1, 0.35)
			kit.box(Vector3(0.12, 0.3, 0.1), Color("#7a4b2a"), Vector3(0.0, 0.5, -0.17), Vector3(0.2, 0, 0.3), 0.0, body)
		"Mage":
			kit.cyl(0.02, 0.025, 0.85, Color("#6b4a8f"), Vector3(0, 0, 0.18), 6, Vector3(PI / 2, 0, 0), 0.0, weapon_pivot)
			kit.sphere(0.07, Color("#ff7b3d"), Vector3(0, 0, 0.62), Vector3.ONE, 10, 2.2, weapon_pivot)
		"Support":
			kit.cyl(0.02, 0.025, 0.7, Color("#f1e7cf"), Vector3(0, 0, 0.14), 6, Vector3(PI / 2, 0, 0), 0.0, weapon_pivot)
			kit.sphere(0.065, Color("#59e29a"), Vector3(0, 0, 0.5), Vector3.ONE, 10, 2.0, weapon_pivot)
			kit.torus(0.07, 0.09, gold, Vector3(0, 0, 0.5), Vector3(PI / 2, 0, 0), 0.3, 12, weapon_pivot)

func play(name: String) -> void:
	if name == "attack":
		attack_timer = 0.35
		return
	anim = name

func update_animation(delta: float, speed_scale: float = 1.0) -> void:
	phase += delta * speed_scale
	attack_timer = maxf(0.0, attack_timer - delta)
	var walk_phase := phase * 9.0
	var leg_swing := 0.0
	var arm_swing := 0.0
	var bob := 0.0
	var arm_r_extra := 0.0
	var arm_l_extra := 0.0
	var body_y := 0.0
	var body_tilt := 0.0
	match anim:
		"walk":
			leg_swing = sin(walk_phase) * 0.65
			arm_swing = -sin(walk_phase) * 0.55
			bob = absf(sin(walk_phase)) * 0.04
		"train":
			var t := fmod(phase, 1.2)
			arm_r_extra = -2.4 + clampf(t * 6.0, 0.0, 2.6) if t < 0.5 else -2.4 + 2.6 - (t - 0.5) * 3.7
			arm_r_extra = clampf(arm_r_extra, -2.4, 0.3)
			bob = 0.02 * sin(phase * 5.0)
		"cheer":
			arm_r_extra = -2.8 + sin(phase * 8.0) * 0.25
			arm_l_extra = -2.8 - sin(phase * 8.0) * 0.25
			bob = absf(sin(phase * 8.0)) * 0.06
		"sit":
			body_y = -0.13
			leg_swing = 0.0
		"rest":
			body_y = -0.13
			body_tilt = 0.12
		"dead":
			body_tilt = 1.45
			body_y = -0.15
		"talk":
			arm_r_extra = -0.5 + sin(phase * 4.0) * 0.35
			bob = 0.012 * sin(phase * 3.0)
		_:
			bob = 0.012 * sin(phase * 2.2)
			arm_swing = sin(phase * 2.2) * 0.04
	if attack_timer > 0.0:
		var k := attack_timer / 0.35
		arm_r_extra = -2.6 * sin(k * PI)
		body_tilt = 0.15 * sin(k * PI)
	if leg_l != null:
		var sit_leg := -1.4 if anim in ["sit", "rest"] else 0.0
		leg_l.rotation.x = leg_swing + sit_leg
		leg_r.rotation.x = -leg_swing + sit_leg
	if arm_l != null and not is_monster or monster_kind in ["raider", "archer", "brute", "boss"]:
		if arm_l != null: arm_l.rotation.x = arm_swing + arm_l_extra
		if arm_r != null: arm_r.rotation.x = -arm_swing + arm_r_extra
	elif arm_l != null:
		arm_l.rotation.x = -leg_swing
		arm_r.rotation.x = leg_swing
	if body != null:
		body.position.y = base_height + bob + body_y
		body.rotation.x = body_tilt
	if head != null and anim == "idle":
		head.rotation.y = sin(phase * 0.6) * 0.25

func flash(amount: float) -> void:
	if kit != null: kit.set_highlight(amount)
