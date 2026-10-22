extends Node3D
class_name CharacterModel

## Personaggi con proporzioni reali: eroi, abitanti, predoni, lupi, bruti e
## guardiani di pietra. Costruiti in metri e scalati a unità di mondo
## (1 unità = 2 m). Il modello guarda verso +Z; animazioni procedurali.

const METER := 0.5

var rig: Node3D
var hips: Node3D
var spine: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var legs_back: Array[Node3D] = []
var tail: Node3D
var anim := "idle"
var phase := 0.0
var attack_timer := 0.0
var attack_length := 0.45
var attack_style := "melee"
var body_type := "human"
var is_monster := false
var monster_kind := ""
var hip_height := 0.95
var _parts: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: ShaderMaterial
var _dead_t := 0.0
var _sit_t := 0.0
var upright_r := false
var upright_l := false

# =============================================================================
# Costruzione: eroi
# =============================================================================

func build_hero(hero: Dictionary, appearance: Dictionary) -> void:
	var role := str(hero.get("role", "Guardian"))
	var rarity := int(hero.get("current_rarity", 1))
	var fem := bool(appearance.get("fem", false))
	var look := {
		"skin": appearance.get("skin", Color("#c99d7c")), "hair": appearance.get("hair", Color("#3a2a20")),
		"eyes": appearance.get("eyes", Color("#3b5a7a")), "style": int(appearance.get("hair_style", 0)), "fem": fem,
		"beard": int(appearance.get("beard", 0)) if not fem else 0, "outfit": _muted(appearance.get("outfit", Color("#4b5a7a")), 0.25),
		"accent": _muted(appearance.get("accent", Color("#b08a4a")), 0.15), "rarity": rarity, "role": role,
	}
	_build_rig({"scale": 0.95 if fem else 1.0, "shoulder": 0.18 if fem else 0.205, "hip": 0.095 if fem else 0.1})
	_dress_hero(look)
	_finish()

## Abitante della base (non combattente).
func build_villager(seed_value: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var fem := r.randf() < 0.5
	var skins := [Color("#e3bf9f"), Color("#c99d7c"), Color("#a8775a"), Color("#7c5440"), Color("#f0d0b4")]
	var hairs := [Color("#2b1f18"), Color("#4a3322"), Color("#7a5634"), Color("#a08060"), Color("#8c8c8c"), Color("#1c1c22")]
	var cloths := [Color("#6b4f3a"), Color("#4f5b45"), Color("#5b4a5f"), Color("#7a6a4f"), Color("#4a5566"), Color("#8a5a3c")]
	var look := {
		"skin": skins[r.randi() % skins.size()], "hair": hairs[r.randi() % hairs.size()], "eyes": Color("#3a3028"),
		"style": r.randi_range(0, 4), "fem": fem, "beard": 0 if fem else r.randi_range(0, 2),
		"outfit": cloths[r.randi() % cloths.size()], "accent": Color("#c9b48a"), "rarity": 1, "role": "Villager",
	}
	_build_rig({"scale": 0.94 if fem else 0.98, "shoulder": 0.18 if fem else 0.2, "hip": 0.1})
	_dress_hero(look)
	_finish()

# =============================================================================
# Costruzione: nemici
# =============================================================================

func build_monster(kind: String, tint: Color) -> void:
	is_monster = true
	monster_kind = kind
	var accent := _muted(tint, 0.35)
	match kind:
		"hound":
			_build_wolf(tint)
		"brute":
			_build_rig({"scale": 1.45, "shoulder": 0.27, "hip": 0.13, "limb": 1.55, "torso": Vector3(1.35, 1.0, 1.25), "head": 0.82})
			_dress_brute(accent)
			attack_style = "heavy"
		"boss":
			_build_rig({"scale": 2.35, "shoulder": 0.29, "hip": 0.13, "limb": 1.7, "torso": Vector3(1.5, 1.05, 1.3), "head": 0.7})
			_dress_golem(tint)
			attack_style = "heavy"
		"archer":
			_build_rig({"scale": 0.98, "shoulder": 0.195, "hip": 0.1})
			_dress_bandit(accent, true)
			attack_style = "bow"
		_:
			_build_rig({"scale": 1.0, "shoulder": 0.205, "hip": 0.1})
			_dress_bandit(accent, false)
			attack_style = "melee"
	_finish()

# =============================================================================
# Scheletro
# =============================================================================

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _build_rig(p: Dictionary) -> void:
	body_type = "human"
	rig = Node3D.new()
	rig.scale = Vector3.ONE * METER * float(p.get("scale", 1.0))
	add_child(rig)
	var shoulder := float(p.get("shoulder", 0.205))
	var hip := float(p.get("hip", 0.1))
	hip_height = 0.95
	hips = _pivot(rig, Vector3(0, hip_height, 0))
	spine = _pivot(hips, Vector3(0, 0.06, 0))
	head = _pivot(spine, Vector3(0, 0.5, 0))
	arm_l = _pivot(spine, Vector3(-shoulder, 0.42, 0))
	arm_r = _pivot(spine, Vector3(shoulder, 0.42, 0))
	fore_l = _pivot(arm_l, Vector3(0, -0.29, 0))
	fore_r = _pivot(arm_r, Vector3(0, -0.29, 0))
	hand_l = _pivot(fore_l, Vector3(0, -0.26, 0))
	hand_r = _pivot(fore_r, Vector3(0, -0.26, 0))
	leg_l = _pivot(hips, Vector3(-hip, -0.03, 0))
	leg_r = _pivot(hips, Vector3(hip, -0.03, 0))
	shin_l = _pivot(leg_l, Vector3(0, -0.45, 0))
	shin_r = _pivot(leg_r, Vector3(0, -0.45, 0))
	set_meta("limb", float(p.get("limb", 1.0)))
	set_meta("torso", p.get("torso", Vector3.ONE))
	set_meta("head", float(p.get("head", 1.0)))

func _b(part: String) -> MeshBuilder:
	if _parts.has(part): return _parts[part]
	var b := MeshBuilder.new()
	b.material("cloth", WorldMaterials.lit(Color.WHITE, 0.9))
	b.material("metal", WorldMaterials.metal(Color.WHITE, 0.38, 0.8))
	b.material("dull", WorldMaterials.metal(Color.WHITE, 0.6, 0.45))
	b.material("rock", WorldMaterials.terrain())
	_parts[part] = b
	return b

func _glow(part: String, color: Color, energy: float = 2.2) -> String:
	var key := "glow_" + color.to_html()
	_b(part).material(key, WorldMaterials.glow(color, energy))
	return key

func _finish() -> void:
	var map := {"hips": hips, "spine": spine, "head": head, "arm_l": arm_l, "arm_r": arm_r, "fore_l": fore_l, "fore_r": fore_r,
		"hand_l": hand_l, "hand_r": hand_r, "leg_l": leg_l, "leg_r": leg_r, "shin_l": shin_l, "shin_r": shin_r, "tail": tail, "root": rig}
	for i in legs_back.size(): map["back_%d" % i] = legs_back[i]
	_flash_mat = WorldMaterials.highlight()
	_flash_mat.set_shader_parameter("glow_color", Color(1.0, 0.92, 0.85))
	for part in _parts:
		var b: MeshBuilder = _parts[part]
		var pivot: Node3D = map.get(part)
		if pivot == null or not b.has_geometry(): continue
		var mi := b.instance(pivot)
		mi.material_overlay = _flash_mat
		_meshes.append(mi)
	_parts.clear()
	update_animation(0.0)

static func _muted(c: Color, amount: float = 0.3) -> Color:
	var l := c.get_luminance()
	return c.lerp(Color(l, l, l), amount).darkened(0.1)

# =============================================================================
# Vestiti e corpi umani
# =============================================================================

func _body(look: Dictionary, colors: Dictionary) -> void:
	var limb := float(get_meta("limb", 1.0))
	var torso: Vector3 = get_meta("torso", Vector3.ONE)
	var fem: bool = look.get("fem", false)
	var skin: Color = look.skin
	var shirt: Color = colors.get("shirt", look.outfit)
	var pants: Color = colors.get("pants", Color("#3b3129"))
	var boots: Color = colors.get("boots", Color("#2a1f18"))
	var sleeve: Color = colors.get("sleeve", shirt)
	var fore: Color = colors.get("fore", sleeve)
	var hand: Color = colors.get("hand", skin)
	var shirt_key: String = colors.get("shirt_key", "cloth")
	var sleeve_key: String = colors.get("sleeve_key", "cloth")
	var fore_key: String = colors.get("fore_key", sleeve_key)
	var shin_key: String = colors.get("shin_key", "cloth")
	var thigh_key: String = colors.get("thigh_key", "cloth")
	var thigh_col: Color = colors.get("thigh", pants)
	var shin_col: Color = colors.get("shin", pants)
	# gambe
	for side in ["l", "r"]:
		var lb := _b("leg_" + side)
		lb.cylinder(thigh_key, 0.072 * limb, 0.062 * limb, 0.46, Vector3(0, -0.225, 0), thigh_col, 9)
		var sb := _b("shin_" + side)
		sb.cylinder(shin_key, 0.058 * limb, 0.047 * limb, 0.3, Vector3(0, -0.15, 0), shin_col, 8)
		sb.cylinder("cloth", 0.06 * limb, 0.056 * limb, 0.2, Vector3(0, -0.32, 0), boots, 8)
		sb.box("cloth", Vector3(0.1 * limb, 0.075, 0.24 * limb), Vector3(0, -0.435, 0.04 * limb), boots)
	# bacino e cintura
	var hb := _b("hips")
	hb.push(Transform3D(Basis.from_scale(Vector3(torso.x, 1, 0.72 * torso.z)), Vector3.ZERO))
	hb.cylinder("cloth", 0.155 * (1.06 if fem else 1.0), 0.15, 0.22, Vector3(0, -0.02, 0), colors.get("pelvis", pants), 12)
	hb.cylinder("cloth", 0.16, 0.16, 0.05, Vector3(0, 0.08, 0), colors.get("belt", Color("#2e2118")), 12)
	hb.pop()
	hb.box("dull", Vector3(0.05, 0.04, 0.02), Vector3(0, 0.08, 0.118 * torso.z), Color("#b39a62"))
	# busto
	var tb := _b("spine")
	tb.push(Transform3D(Basis.from_scale(Vector3(torso.x, torso.y, 0.62 * torso.z)), Vector3.ZERO))
	tb.cylinder(shirt_key, 0.19 if not fem else 0.175, 0.15 if not fem else 0.14, 0.36, Vector3(0, 0.17, 0), shirt, 12)
	tb.pop()
	tb.sphere(shirt_key, 0.19, Vector3(0, 0.38 * torso.y, 0), shirt, Vector3(1.12 * torso.x, 0.5, 0.68 * torso.z), 12, 6)
	if fem:
		for sx in [-1.0, 1.0]: tb.sphere(shirt_key, 0.058, Vector3(sx * 0.06, 0.26, 0.085), shirt, Vector3(1, 0.9, 0.8), 8, 5)
	tb.cylinder("cloth", 0.05, 0.055, 0.12, Vector3(0, 0.46 * torso.y, 0), skin, 8)
	# braccia
	for side in ["l", "r"]:
		var ab := _b("arm_" + side)
		ab.sphere(sleeve_key, 0.062 * limb, Vector3(0, -0.01, 0), sleeve, Vector3.ONE, 8, 5)
		ab.cylinder(sleeve_key, 0.056 * limb, 0.047 * limb, 0.29, Vector3(0, -0.145, 0), sleeve, 8)
		var fb := _b("fore_" + side)
		fb.cylinder(fore_key, 0.046 * limb, 0.038 * limb, 0.25, Vector3(0, -0.125, 0), fore, 8)
		var handb := _b("hand_" + side)
		handb.box("cloth", Vector3(0.062 * limb, 0.085 * limb, 0.034 * limb), Vector3(0, -0.035, 0.005), hand)
	_head(look)

func _head(look: Dictionary) -> void:
	var hs := float(get_meta("head", 1.0))
	var b := _b("head")
	var skin: Color = look.skin
	var hair: Color = look.hair
	var fem: bool = look.get("fem", false)
	b.push(Transform3D(Basis.from_scale(Vector3.ONE * hs), Vector3(0, 0.0, 0)))
	b.sphere("cloth", 0.112, Vector3(0, 0.135, 0.005), skin, Vector3(0.92 if not fem else 0.88, 1.1, 1.02), 12, 8)
	b.sphere("cloth", 0.085, Vector3(0, 0.075, 0.022), skin.darkened(0.04), Vector3(1.0 if not fem else 0.92, 0.75, 1.0), 10, 6)
	b.box("cloth", Vector3(0.022, 0.045, 0.03), Vector3(0, 0.118, 0.112), skin.darkened(0.08))
	for sx in [-1.0, 1.0]:
		b.sphere("cloth", 0.012, Vector3(sx * 0.036, 0.142, 0.099), Color("#16110e"), Vector3(1.2, 0.8, 0.6), 6, 4)
		b.box("cloth", Vector3(0.042, 0.009, 0.012), Vector3(sx * 0.036, 0.163, 0.104), hair.darkened(0.2), Vector3(0, 0, -sx * 0.12))
		b.sphere("cloth", 0.022, Vector3(sx * 0.103, 0.13, 0.0), skin.darkened(0.06), Vector3(0.5, 1.0, 0.8), 6, 4)
	b.box("cloth", Vector3(0.036, 0.008, 0.01), Vector3(0, 0.085, 0.108), skin.darkened(0.25))
	_hair(b, look)
	b.pop()

func _hair(b: MeshBuilder, look: Dictionary) -> void:
	var hair: Color = look.hair
	var style := int(look.get("style", 0))
	var fem: bool = look.get("fem", false)
	if look.get("hood", false): return
	# calotta: copre testa e nuca lasciando libera la fronte
	b.push(Transform3D(Basis(Vector3.RIGHT, -0.38), Vector3(0, 0.155, -0.012)))
	b.dome("cloth", 0.121, Vector3.ZERO, hair, 0.9, 12, 4)
	b.pop()
	b.sphere("cloth", 0.104, Vector3(0, 0.115, -0.04), hair, Vector3(1.02, 0.95, 0.85), 10, 6)
	# ciocche lungo l'attaccatura: spezzano la sagoma "a casco"
	var r := RandomNumberGenerator.new()
	r.seed = int(hair.to_rgba32()) + style
	for i in 7:
		var a := lerpf(-1.3, 1.3, i / 6.0)
		var length := r.randf_range(0.06, 0.1) * (1.5 if absf(a) > 0.9 else 1.0)
		var pos := Vector3(sin(a) * 0.104, 0.205 - absf(a) * 0.03, cos(a) * 0.088 - 0.012)
		b.box("cloth", Vector3(0.05, length, 0.026), pos + Vector3(0, -length * 0.42, 0), hair.darkened(r.randf() * 0.12), Vector3(-0.15 + r.randf() * 0.2, a * 0.95, -a * 0.2))
	match style:
		0:
			b.box("cloth", Vector3(0.17, 0.035, 0.05), Vector3(0, 0.215, 0.07), hair, Vector3(0.5, 0, 0))
		1:
			for i in 6:
				var a := -1.0 + i * 0.4
				b.cone("cloth", 0.035, 0.12, Vector3(a * 0.07, 0.24, -0.01 - absf(a) * 0.03), hair, 5, Vector3(-0.5, 0, -a * 0.6))
		2:
			b.box("cloth", Vector3(0.21, 0.3 if fem else 0.18, 0.05), Vector3(0, 0.0 if fem else 0.05, -0.085), hair, Vector3(0.12, 0, 0))
			for sx in [-1.0, 1.0]: b.box("cloth", Vector3(0.04, 0.2 if fem else 0.1, 0.06), Vector3(sx * 0.098, 0.07 if fem else 0.12, 0.02), hair)
		3:
			b.sphere("cloth", 0.04, Vector3(0, 0.17, -0.12), hair, Vector3.ONE, 6, 4)
			b.rod("cloth", Vector3(0, 0.15, -0.13), Vector3(0, -0.06, -0.17), 0.034, 0.018, hair, 6)
		4:
			b.sphere("cloth", 0.055, Vector3(0, 0.24, -0.07), hair, Vector3(1, 0.85, 1), 8, 5)
		5:
			b.box("cloth", Vector3(0.2, 0.1, 0.16), Vector3(0, 0.2, -0.04), hair, Vector3(-0.3, 0, 0))
			b.box("cloth", Vector3(0.18, 0.12, 0.05), Vector3(0, 0.1, -0.11), hair, Vector3(0.25, 0, 0))
	var beard := int(look.get("beard", 0))
	if beard > 0:
		b.sphere("cloth", 0.07, Vector3(0, 0.055, 0.06), hair.darkened(0.1), Vector3(1.05, 0.8 if beard == 1 else 1.1, 0.75), 8, 5)

func _hood(b: MeshBuilder, color: Color) -> void:
	b.push(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.13, -0.015)))
	b.dome("cloth", 0.142, Vector3.ZERO, color, 1.1, 12, 4)
	b.pop()
	b.sphere("cloth", 0.12, Vector3(0, 0.09, -0.06), color.darkened(0.05), Vector3(1.05, 1.0, 0.9), 10, 6)
	b.torus("cloth", 0.1, 0.035, Vector3(0, -0.01, 0.0), color.darkened(0.1), Vector3.ZERO, 12, 6)

func _dress_hero(look: Dictionary) -> void:
	var role := str(look.role)
	var o: Color = look.outfit
	var a: Color = look.accent
	var leather := Color("#4a3423")
	var steel := Color("#9aa0a8")
	var dark_steel := Color("#5d6168")
	var rarity := int(look.get("rarity", 1))
	match role:
		"Guardian":
			_body(look, {"shirt": steel, "shirt_key": "metal", "sleeve": steel, "sleeve_key": "metal", "fore": dark_steel, "fore_key": "metal",
				"hand": dark_steel, "thigh": Color("#6c7077"), "thigh_key": "dull", "shin": steel, "shin_key": "metal", "boots": Color("#3c3f45"), "pelvis": Color("#6c7077")})
			var tb := _b("spine")
			tb.box("cloth", Vector3(0.26, 0.6, 0.02), Vector3(0, 0.02, 0.125), o)
			tb.box("cloth", Vector3(0.26, 0.6, 0.02), Vector3(0, 0.02, -0.125), o.darkened(0.15))
			tb.box("dull", Vector3(0.27, 0.03, 0.025), Vector3(0, 0.31, 0.127), a)
			tb.torus("metal", 0.075, 0.03, Vector3(0, 0.44, 0), steel, Vector3.ZERO, 12, 5)
			for side in ["l", "r"]: _b("arm_" + side).sphere("metal", 0.1, Vector3(0, 0.0, 0), steel, Vector3(1.15, 0.8, 1.15), 10, 6, true)
			_sword(_b("hand_r"), 0.78, 0.045, steel, a)
			_shield(_b("fore_l"), o, a, steel)
			attack_style = "melee"
		"Vanguard":
			_body(look, {"shirt": leather, "sleeve": o, "fore": leather, "hand": Color("#3a2a1e"), "pants": Color("#3a3029"), "shin": Color("#5d6168"), "shin_key": "dull"})
			var tb := _b("spine")
			_breastplate(tb, dark_steel, "metal")
			tb.box("cloth", Vector3(0.05, 0.62, 0.02), Vector3(0.06, 0.22, 0.128), o, Vector3(0, 0, 0.62))
			_b("arm_r").sphere("metal", 0.095, Vector3.ZERO, steel, Vector3(1.2, 0.8, 1.2), 10, 6, true)
			_b("arm_l").sphere("cloth", 0.09, Vector3.ZERO, Color("#5a4632"), Vector3(1.2, 0.75, 1.2), 10, 6, true)
			_sword(_b("hand_r"), 1.15, 0.065, steel, a)
			attack_style = "heavy"
		"Lancer":
			_body(look, {"shirt": o, "sleeve": o.darkened(0.15), "fore": leather, "hand": Color("#3a2a1e"), "shin": leather})
			var tb := _b("spine")
			_breastplate(tb, o.darkened(0.3), "cloth")
			for i in 3:
				tb.push(Transform3D(Basis.from_scale(Vector3(1, 1, 0.64)), Vector3.ZERO))
				tb.cylinder("dull", 0.2 - i * 0.008, 0.2 - i * 0.008, 0.025, Vector3(0, 0.16 + i * 0.08, 0), dark_steel, 12, Vector3.ZERO, false)
				tb.pop()
			for side in ["l", "r"]: _b("arm_" + side).sphere("metal", 0.085, Vector3.ZERO, steel, Vector3(1.15, 0.7, 1.15), 10, 6, true)
			_spear(_b("hand_r"), steel, a)
			attack_style = "thrust"
		"Ranger":
			look["hood"] = true
			_body(look, {"shirt": Color("#4f3c2a"), "sleeve": o.darkened(0.1), "fore": leather, "hand": Color("#3a2a1e"), "pants": Color("#3d3a2c")})
			_hood(_b("head"), o)
			var tb := _b("spine")
			_cloth_panel(tb, 0.34, 0.5, 0.95, Vector3(0, 0.44, -0.13), o.darkened(0.08), 0.1)
			tb.rod("cloth", Vector3(0.1, 0.0, -0.16), Vector3(-0.06, 0.48, -0.17), 0.045, 0.05, leather, 8)
			for i in 4: tb.rod("cloth", Vector3(-0.05 + i * 0.012, 0.44, -0.17), Vector3(-0.08 + i * 0.015, 0.56, -0.18), 0.008, 0.012, Color("#d8d0c0"), 4)
			_bow(_b("hand_l"), Color("#5a3d26"))
			upright_l = true
			attack_style = "bow"
		"Mage":
			_body(look, {"shirt": o, "sleeve": o, "fore": o.darkened(0.08), "pants": o.darkened(0.25), "boots": Color("#241a14")})
			var hb := _b("hips")
			hb.push(Transform3D(Basis.from_scale(Vector3(1, 1, 0.85)), Vector3.ZERO))
			hb.cylinder("cloth", 0.17, 0.31, 0.86, Vector3(0, -0.45, 0), o.darkened(0.06), 14, Vector3.ZERO, false)
			hb.pop()
			_b("spine").torus("cloth", 0.1, 0.045, Vector3(0, 0.43, 0), a, Vector3.ZERO, 12, 6)
			_b("spine").box("cloth", Vector3(0.06, 0.6, 0.02), Vector3(0, 0.12, 0.118), a)
			for side in ["l", "r"]: _b("fore_" + side).cylinder("cloth", 0.068, 0.085, 0.22, Vector3(0, -0.14, 0), o, 9)
			_staff(_b("hand_r"), Color("#3b2a1e"), a.lightened(0.25))
			upright_r = true
			attack_style = "cast"
		"Support":
			var robe := Color("#cbc2ad")
			_body(look, {"shirt": robe, "sleeve": robe, "fore": robe.darkened(0.05), "pants": Color("#5d5446")})
			var hb := _b("hips")
			hb.push(Transform3D(Basis.from_scale(Vector3(1, 1, 0.85)), Vector3.ZERO))
			hb.cylinder("cloth", 0.165, 0.27, 0.7, Vector3(0, -0.37, 0), robe.darkened(0.04), 14, Vector3.ZERO, false)
			hb.pop()
			var tb := _b("spine")
			for sx in [-1.0, 1.0]: tb.box("cloth", Vector3(0.06, 0.75, 0.02), Vector3(sx * 0.07, 0.05, 0.12), o, Vector3(0, 0, sx * 0.08))
			tb.box("cloth", Vector3(0.12, 0.14, 0.06), Vector3(-0.17, -0.08, 0.02), Color("#5a4330"))
			_healer_staff(_b("hand_r"), Color("#d9cfb8"), Color("#7ef0b2"))
			upright_r = true
			attack_style = "cast"
		_:
			_body(look, {"shirt": o, "sleeve": o.darkened(0.1), "fore": look.skin, "pants": Color("#4a3e32")})
			if look.get("fem", false):
				var hb := _b("hips")
				hb.push(Transform3D(Basis.from_scale(Vector3(1, 1, 0.85)), Vector3.ZERO))
				hb.cylinder("cloth", 0.16, 0.25, 0.62, Vector3(0, -0.33, 0), o.darkened(0.12), 12, Vector3.ZERO, false)
				hb.pop()
			_b("spine").box("cloth", Vector3(0.26, 0.4, 0.02), Vector3(0, 0.05, 0.118), Color("#c9bea6"))
			attack_style = "melee"
	if rarity >= 4 and role != "Villager":
		var cape := _muted(UIKit.rarity_color(rarity), 0.35).darkened(0.35)
		var tb := _b("spine")
		_cloth_panel(tb, 0.36, 0.56, 1.02, Vector3(0, 0.45, -0.14), cape, 0.12)
		tb.box("dull", Vector3(0.42, 0.04, 0.05), Vector3(0, 0.43, -0.12), Color("#b39a62"))

func _dress_bandit(tint: Color, archer: bool) -> void:
	var leather := Color("#3b2c21")
	var look := {"skin": Color("#a07a5e"), "hair": Color("#1e1914"), "fem": false, "style": 0, "beard": 1, "outfit": tint, "hood": true}
	_body(look, {"shirt": leather, "sleeve": Color("#2e2620"), "fore": leather, "hand": Color("#241b15"), "pants": Color("#2a2420"), "boots": Color("#1d1713")})
	_hood(_b("head"), tint.darkened(0.25))
	_b("head").box("cloth", Vector3(0.17, 0.07, 0.05), Vector3(0, 0.075, 0.085), Color("#1c1816"))
	var tb := _b("spine")
	tb.box("cloth", Vector3(0.08, 0.66, 0.02), Vector3(-0.05, 0.2, 0.117), tint, Vector3(0, 0, -0.6))
	_cloth_panel(tb, 0.34, 0.46, 0.75, Vector3(0, 0.42, -0.13), tint.darkened(0.45), 0.1)
	if archer:
		_bow(_b("hand_l"), Color("#3d2a1c"))
		upright_l = true
		tb.rod("cloth", Vector3(0.1, 0.0, -0.16), Vector3(-0.06, 0.48, -0.17), 0.045, 0.05, leather, 8)
	else:
		_falchion(_b("hand_r"), Color("#8d9097"))

func _dress_brute(tint: Color) -> void:
	var skin := Color("#6b7458")
	var look := {"skin": skin, "hair": Color("#1f1c18"), "fem": false, "style": 1, "beard": 0, "outfit": tint}
	_body(look, {"shirt": skin, "sleeve": skin, "fore": skin, "hand": skin.darkened(0.1), "pants": Color("#4a3a2a"), "boots": skin.darkened(0.25), "pelvis": Color("#4a3a2a")})
	var hd := _b("head")
	for sx in [-1.0, 1.0]: hd.cone("cloth", 0.016, 0.06, Vector3(sx * 0.04, 0.07, 0.1), Color("#e6dcc4"), 5)
	var tb := _b("spine")
	tb.rod("cloth", Vector3(-0.2, 0.42, 0.1), Vector3(0.2, 0.0, 0.13), 0.035, 0.035, tint, 6)
	tb.box("dull", Vector3(0.16, 0.14, 0.03), Vector3(0.12, 0.38, 0.12), Color("#5b5550"), Vector3(0, 0, 0.3))
	_b("hips").box("cloth", Vector3(0.3, 0.32, 0.02), Vector3(0, -0.2, 0.12), Color("#5a4632"))
	var club := _b("hand_r")
	club.rod("cloth", Vector3(0, -0.06, 0), Vector3(0, 0.9, 0.0), 0.03, 0.08, Color("#4a3624"), 7)
	for i in 4: club.cone("dull", 0.022, 0.07, Vector3(sin(i * 1.7) * 0.07, 0.62 + i * 0.07, cos(i * 1.7) * 0.07), Color("#77736c"), 5, Vector3(cos(i * 1.7) * 1.2, 0, -sin(i * 1.7) * 1.2))
	_weapon_grip(club, 1.6)

func _dress_golem(tint: Color) -> void:
	# le rocce delle membra non vanno appiattite sotto
	var stone := Color(0, 0, 1, 1)
	var glow := _glow("spine", tint.lightened(0.35), 3.0)
	for part in ["leg_l", "leg_r", "shin_l", "shin_r", "hips", "arm_l", "arm_r", "fore_l", "fore_r", "hand_l", "hand_r", "head"]: _glow(part, tint.lightened(0.35), 3.0)
	for side in ["l", "r"]:
		_b("leg_" + side).rock("rock", 0.14, Vector3(0, -0.22, 0), stone, Vector3(0.75, 1.7, 0.75), 11 if side == "l" else 12, 0.2, false)
		_b("shin_" + side).rock("rock", 0.13, Vector3(0, -0.24, 0), stone, Vector3(0.75, 1.75, 0.8), 13 if side == "l" else 14, 0.2, false)
		_b("shin_" + side).rock("rock", 0.11, Vector3(0, -0.43, 0.04), stone, Vector3(1.0, 0.5, 1.3), 15, 0.2, false)
		_b("arm_" + side).rock("rock", 0.15, Vector3(0, -0.1, 0), stone, Vector3(1.1, 1.3, 1.1), 16 if side == "l" else 17, 0.2, false)
		_b("fore_" + side).rock("rock", 0.12, Vector3(0, -0.13, 0), stone, Vector3(0.9, 1.5, 0.9), 18 if side == "l" else 19, 0.2, false)
		_b("hand_" + side).rock("rock", 0.1, Vector3(0, -0.05, 0.01), stone, Vector3(1.0, 0.9, 0.9), 20 if side == "l" else 21, 0.2, false)
	_b("hips").rock("rock", 0.18, Vector3(0, 0.0, 0), stone, Vector3(1.2, 0.7, 0.9), 22, 0.2, false)
	var tb := _b("spine")
	tb.rock("rock", 0.26, Vector3(0, 0.25, 0), stone, Vector3(1.15, 1.0, 0.8), 23, 0.2, false)
	tb.rock("rock", 0.14, Vector3(0.0, 0.47, -0.05), stone, Vector3(1.6, 0.6, 0.8), 24, 0.2, false)
	tb.sphere(glow, 0.06, Vector3(0, 0.28, 0.17), Color.WHITE, Vector3(1, 1.3, 0.4), 8, 5)
	for i in 5:
		var y := 0.1 + i * 0.08
		tb.box(glow, Vector3(0.012, 0.06, 0.012), Vector3(-0.1 + i * 0.05, y, 0.19), Color.WHITE, Vector3(0, 0, 0.4 * sin(i * 2.0)))
	var hd := _b("head")
	hd.rock("rock", 0.11, Vector3(0, 0.1, 0), stone, Vector3(1.0, 0.85, 1.0), 25, 0.2, false)
	var hglow := _glow("head", tint.lightened(0.45), 4.0)
	for sx in [-1.0, 1.0]: hd.sphere(hglow, 0.016, Vector3(sx * 0.04, 0.11, 0.095), Color.WHITE, Vector3(1.4, 0.7, 0.6), 6, 4)

## Corazza: un guscio attorno al petto, poco più largo del busto.
func _breastplate(b: MeshBuilder, color: Color, key: String) -> void:
	var torso: Vector3 = get_meta("torso", Vector3.ONE)
	b.push(Transform3D(Basis.from_scale(Vector3(torso.x, torso.y, 0.66 * torso.z)), Vector3.ZERO))
	b.cylinder(key, 0.2, 0.17, 0.26, Vector3(0, 0.27, 0), color, 12)
	b.pop()
	b.sphere(key, 0.2, Vector3(0, 0.39 * torso.y, 0), color, Vector3(1.12 * torso.x, 0.45, 0.7 * torso.z), 12, 6, true)

## Mantello o cappa: pannello a trapezio che si allarga verso il basso.
func _cloth_panel(b: MeshBuilder, top_w: float, bottom_w: float, height: float, top_center: Vector3, color: Color, tilt: float) -> void:
	var shape := PackedVector2Array([Vector2(-top_w * 0.5, 0), Vector2(top_w * 0.5, 0), Vector2(bottom_w * 0.5, -height), Vector2(-bottom_w * 0.5, -height)])
	# il trapezio sta nel piano XZ: lo ruoto in verticale (Z locale = alto)
	b.push(Transform3D(Basis(Vector3.RIGHT, tilt) * Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), top_center))
	b.extrude("cloth", shape, -0.012, 0.012, color, true, true)
	b.pop()

# =============================================================================
# Armi (costruite lungo +Y dal punto di presa)
# =============================================================================

func _weapon_grip(b: MeshBuilder, angle: float) -> void:
	b.set_meta("grip", angle)

func _sword(b: MeshBuilder, length: float, width: float, steel: Color, accent: Color) -> void:
	b.push(Transform3D(Basis(Vector3.RIGHT, 1.75), Vector3(0, -0.04, 0.01)))
	b.cylinder("cloth", 0.016, 0.017, 0.16 + length * 0.05, Vector3(0, 0.02, 0), Color("#3a2a1e"), 6)
	b.sphere("dull", 0.024, Vector3(0, -0.07, 0), accent, Vector3.ONE, 6, 4)
	b.box("dull", Vector3(0.18 + width, 0.025, 0.035), Vector3(0, 0.11, 0), accent)
	b.box("metal", Vector3(width, length, 0.012), Vector3(0, 0.12 + length * 0.5, 0), steel)
	b.push(Transform3D(Basis.from_scale(Vector3(1, 1, 0.3)), Vector3(0, 0.12 + length + 0.04, 0)))
	b.cone("metal", width * 0.55, 0.09, Vector3.ZERO, steel, 4)
	b.pop()
	b.pop()

func _falchion(b: MeshBuilder, steel: Color) -> void:
	b.push(Transform3D(Basis(Vector3.RIGHT, 1.75), Vector3(0, -0.04, 0.01)))
	b.cylinder("cloth", 0.016, 0.017, 0.14, Vector3(0, 0.02, 0), Color("#2a1f18"), 6)
	b.box("dull", Vector3(0.12, 0.02, 0.03), Vector3(0, 0.1, 0), Color("#5d5750"))
	for i in 4:
		var y := 0.18 + i * 0.13
		b.box("metal", Vector3(0.05 + i * 0.008, 0.14, 0.01), Vector3(i * i * 0.006, y, 0), steel, Vector3(0, 0, -0.06 * i))
	b.pop()

func _spear(b: MeshBuilder, steel: Color, accent: Color) -> void:
	b.push(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.08), Vector3(0, -0.04, 0.02)))
	b.rod("cloth", Vector3(0, -0.85, 0), Vector3(0, 1.25, 0), 0.018, 0.016, Color("#4a3524"), 6)
	b.cone("metal", 0.035, 0.24, Vector3(0, 1.37, 0), steel, 5)
	b.box("dull", Vector3(0.12, 0.02, 0.02), Vector3(0, 1.24, 0), accent)
	b.box("cloth", Vector3(0.012, 0.2, 0.12), Vector3(0, 1.08, 0.07), accent.darkened(0.2))
	b.pop()

func _staff(b: MeshBuilder, wood: Color, crystal: Color) -> void:
	var key := "glow_" + crystal.to_html()
	b.material(key, WorldMaterials.glow(crystal, 2.6))
	b.push(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, -0.04, 0.02)))
	b.rod("cloth", Vector3(0, -0.85, 0), Vector3(0, 0.95, 0), 0.02, 0.024, wood, 6)
	for i in 3:
		var a := TAU * i / 3.0
		b.rod("cloth", Vector3(0, 0.92, 0), Vector3(cos(a) * 0.06, 1.1, sin(a) * 0.06), 0.012, 0.007, wood, 4)
	b.sphere(key, 0.05, Vector3(0, 1.06, 0), Color.WHITE, Vector3(0.8, 1.3, 0.8), 4, 2)
	b.pop()

func _healer_staff(b: MeshBuilder, wood: Color, crystal: Color) -> void:
	var key := "glow_" + crystal.to_html()
	b.material(key, WorldMaterials.glow(crystal, 2.2))
	b.push(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, -0.04, 0.02)))
	b.rod("cloth", Vector3(0, -0.8, 0), Vector3(0, 0.82, 0), 0.018, 0.02, wood, 6)
	b.torus("dull", 0.08, 0.012, Vector3(0, 0.93, 0), Color("#c9a85a"), Vector3(PI / 2, 0, 0), 14, 4)
	b.sphere(key, 0.035, Vector3(0, 0.93, 0), Color.WHITE, Vector3.ONE, 6, 4)
	b.pop()

func _bow(b: MeshBuilder, wood: Color) -> void:
	var pts: Array[Vector3] = []
	for i in 9:
		var t := -1.0 + i * 0.25
		pts.append(Vector3(0, t * 0.62, 0.13 * (1.0 - t * t)))
	b.push(Transform3D(Basis.IDENTITY, Vector3(0, -0.05, 0.02)))
	for i in pts.size() - 1:
		b.rod("cloth", pts[i], pts[i + 1], 0.016 if absf(i - 3.5) < 2.0 else 0.012, 0.016 if absf(i + 1 - 3.5) < 2.0 else 0.012, wood, 5, false)
	b.rod("cloth", pts[0], pts[pts.size() - 1], 0.003, 0.003, Color("#d9d2c0"), 3, false)
	b.pop()

func _shield(b: MeshBuilder, color: Color, accent: Color, rim: Color) -> void:
	var outline := PackedVector2Array([Vector2(-0.23, 0.3), Vector2(0.23, 0.3), Vector2(0.22, -0.02), Vector2(0.0, -0.36), Vector2(-0.22, -0.02)])
	b.push(Transform3D(Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)), Vector3(-0.08, -0.13, 0.02)))
	b.extrude("cloth", outline, 0.0, 0.035, color, true, true)
	b.extrude("dull", PackedVector2Array([Vector2(-0.03, 0.29), Vector2(0.03, 0.29), Vector2(0.03, -0.3), Vector2(-0.03, -0.3)]), 0.034, 0.045, accent, true, false)
	b.extrude("dull", PackedVector2Array([Vector2(-0.2, 0.1), Vector2(0.2, 0.1), Vector2(0.2, 0.04), Vector2(-0.2, 0.04)]), 0.034, 0.045, accent, true, false)
	b.pop()

# =============================================================================
# Lupo (Segugio del Rift)
# =============================================================================

func _build_wolf(tint: Color) -> void:
	body_type = "beast"
	rig = Node3D.new()
	rig.scale = Vector3.ONE * METER * 1.15
	add_child(rig)
	var fur := Color("#3e3934").lerp(tint.darkened(0.55), 0.2)
	var belly := fur.lightened(0.15)
	hips = _pivot(rig, Vector3(0, 0.62, -0.32))
	spine = _pivot(rig, Vector3(0, 0.66, 0.22))
	head = _pivot(spine, Vector3(0, 0.12, 0.3))
	leg_l = _pivot(spine, Vector3(-0.11, -0.04, 0.06))
	leg_r = _pivot(spine, Vector3(0.11, -0.04, 0.06))
	shin_l = _pivot(leg_l, Vector3(0, -0.3, 0))
	shin_r = _pivot(leg_r, Vector3(0, -0.3, 0))
	legs_back = [_pivot(hips, Vector3(-0.11, -0.02, -0.02)), _pivot(hips, Vector3(0.11, -0.02, -0.02))]
	tail = _pivot(hips, Vector3(0, 0.06, -0.18))
	var hb := _b("hips")
	hb.sphere("cloth", 0.125, Vector3(0, 0.03, 0.06), fur, Vector3(0.95, 1.0, 1.7), 10, 6, false, Vector3.ZERO, belly)
	var sb := _b("spine")
	sb.sphere("cloth", 0.15, Vector3(0, 0.0, -0.12), fur, Vector3(0.9, 1.15, 1.75), 12, 7, false, Vector3.ZERO, belly)
	sb.sphere("cloth", 0.12, Vector3(0, 0.07, 0.14), fur.lightened(0.06), Vector3(0.95, 1.25, 1.1), 10, 6)
	sb.rod("cloth", Vector3(0, 0.08, 0.12), Vector3(0, 0.15, 0.3), 0.07, 0.06, fur, 8)
	var hd := _b("head")
	hd.sphere("cloth", 0.095, Vector3(0, 0.02, 0.0), fur, Vector3(1.0, 0.9, 1.15), 10, 6)
	hd.push(Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(0, -0.015, 0.13)))
	hd.cylinder("cloth", 0.028, 0.055, 0.2, Vector3.ZERO, fur.darkened(0.08), 8, Vector3(PI / 2, 0, 0))
	hd.pop()
	hd.sphere("cloth", 0.02, Vector3(0, -0.01, 0.235), Color("#121010"), Vector3.ONE, 6, 4)
	for sx in [-1.0, 1.0]:
		hd.cone("cloth", 0.035, 0.09, Vector3(sx * 0.06, 0.12, -0.03), fur.darkened(0.15), 5, Vector3(-0.2, 0, sx * 0.3))
	var eye := _glow("head", Color("#ffb347"), 2.8)
	for sx in [-1.0, 1.0]: hd.sphere(eye, 0.014, Vector3(sx * 0.045, 0.04, 0.085), Color.WHITE, Vector3(1.3, 0.8, 0.6), 6, 4)
	for i in 4:
		var upper: Node3D = [leg_l, leg_r, legs_back[0], legs_back[1]][i]
		var ub := _b(["leg_l", "leg_r", "back_0", "back_1"][i])
		ub.cylinder("cloth", 0.045, 0.034, 0.32, Vector3(0, -0.15, 0), fur, 7)
		if i < 2:
			var lb := _b(["shin_l", "shin_r"][i])
			lb.cylinder("cloth", 0.034, 0.028, 0.3, Vector3(0, -0.15, 0), fur.darkened(0.1), 6)
			lb.box("cloth", Vector3(0.055, 0.03, 0.08), Vector3(0, -0.3, 0.02), fur.darkened(0.25))
		else:
			ub.cylinder("cloth", 0.032, 0.028, 0.32, Vector3(0, -0.42, -0.04), fur.darkened(0.1), 6, Vector3(-0.25, 0, 0))
			ub.box("cloth", Vector3(0.055, 0.03, 0.08), Vector3(0, -0.6, 0.0), fur.darkened(0.25))
	_b("tail").rod("cloth", Vector3.ZERO, Vector3(0, -0.1, -0.2), 0.035, 0.05, fur.darkened(0.05), 6)
	_b("tail").rod("cloth", Vector3(0, -0.1, -0.2), Vector3(0, -0.22, -0.4), 0.05, 0.02, fur.darkened(0.12), 6)
	attack_style = "bite"

# =============================================================================
# Animazione
# =============================================================================

func play(name_text: String) -> void:
	if name_text == "attack":
		attack_length = {"melee": 0.45, "heavy": 0.7, "thrust": 0.38, "bow": 0.6, "cast": 0.6, "bite": 0.4}.get(attack_style, 0.45)
		attack_timer = attack_length
		return
	anim = name_text

func update_animation(delta: float, speed_scale: float = 1.0) -> void:
	phase += delta * speed_scale
	attack_timer = maxf(0.0, attack_timer - delta * speed_scale)
	_dead_t = move_toward(_dead_t, 1.0 if anim == "dead" else 0.0, delta * speed_scale * 2.5)
	_sit_t = move_toward(_sit_t, 1.0 if anim in ["sit", "rest"] else 0.0, delta * speed_scale * 3.0)
	if body_type == "beast": _animate_beast()
	else: _animate_human()

func _animate_human() -> void:
	if rig == null: return
	var t := phase
	var walk := anim == "walk"
	var heavy := monster_kind in ["brute", "boss"]
	var stride := 7.2 if not heavy else 4.6
	var w := t * stride
	var leg_a := 0.0
	var knee_l := 0.04
	var knee_r := 0.04
	var arm_a := 0.0
	var arm_l_x := 0.0
	var arm_r_x := -0.12
	var arm_l_z := -0.07
	var arm_r_z := 0.07
	var elbow_l := -0.18
	var elbow_r := -0.32
	var bob := 0.0
	var spine_x := sin(t * 1.7) * 0.015
	var spine_y := 0.0
	var head_y := 0.0
	var head_x := 0.0
	if walk:
		leg_a = sin(w) * (0.55 if not heavy else 0.4)
		knee_l = maxf(0.0, sin(w + 1.3)) * 0.85 + 0.05
		knee_r = maxf(0.0, sin(w + 1.3 + PI)) * 0.85 + 0.05
		arm_a = sin(w) * 0.38
		bob = absf(sin(w)) * 0.035
		spine_y = sin(w) * 0.07
		elbow_l = -0.25 - maxf(0.0, -sin(w)) * 0.35
		elbow_r = -0.32 - maxf(0.0, sin(w)) * 0.3
	match anim:
		"idle":
			head_y = sin(t * 0.5) * 0.3 * sin(t * 0.17)
		"talk":
			arm_r_x = -0.5 + sin(t * 3.5) * 0.25
			elbow_r = -0.9 + sin(t * 4.3) * 0.25
			head_y = sin(t * 1.3) * 0.15
		"cheer":
			arm_r_x = -2.85 + sin(t * 7.0) * 0.18
			arm_l_x = -2.6 - sin(t * 7.0) * 0.18
			elbow_r = -0.25
			elbow_l = -0.3
			bob = absf(sin(t * 7.0)) * 0.05
		"train":
			var c := fmod(t, 1.3) / 1.3
			if c < 0.45:
				arm_r_x = lerpf(-0.4, -2.5, c / 0.45)
				elbow_r = lerpf(-0.4, -1.3, c / 0.45)
			elif c < 0.6:
				var k := (c - 0.45) / 0.15
				arm_r_x = lerpf(-2.5, -0.5, k)
				elbow_r = lerpf(-1.3, -0.15, k)
				spine_y = -0.25 * k
			else:
				arm_r_x = -0.5
				elbow_r = -0.25
			arm_l_x = -0.6
			elbow_l = -1.0
			leg_a = 0.0
			knee_l = 0.2
			knee_r = 0.12
		"rest":
			head_x = 0.35
			arm_l_x = -0.5
			arm_r_x = -0.5
			elbow_l = -1.0
			elbow_r = -1.0
	if attack_timer > 0.0:
		var k := 1.0 - attack_timer / attack_length
		match attack_style:
			"melee", "heavy":
				if k < 0.5:
					arm_r_x = lerpf(arm_r_x, -2.6, k / 0.5)
					elbow_r = lerpf(elbow_r, -1.2, k / 0.5)
					spine_y = lerpf(0.0, 0.25, k / 0.5)
					if attack_style == "heavy":
						arm_l_x = lerpf(arm_l_x, -2.4, k / 0.5)
						elbow_l = -1.0
				else:
					var s := (k - 0.5) / 0.5
					arm_r_x = lerpf(-2.6, -0.35, minf(1.0, s * 1.8))
					elbow_r = lerpf(-1.2, -0.1, minf(1.0, s * 1.8))
					spine_y = lerpf(0.25, -0.3, minf(1.0, s * 1.8))
					spine_x = 0.12 * sin(s * PI)
					if attack_style == "heavy":
						arm_l_x = lerpf(-2.4, -0.4, minf(1.0, s * 1.8))
			"thrust":
				var s := sin(k * PI)
				arm_r_x = lerpf(-0.25, -0.8, s)
				elbow_r = lerpf(-0.6, 0.0, s)
				spine_x = 0.15 * s
				arm_l_x = -0.9
				elbow_l = -0.9
			"bow":
				arm_l_x = -1.5
				arm_l_z = -0.05
				elbow_l = -0.05
				arm_r_x = -1.45
				elbow_r = lerpf(-0.6, -1.9, minf(1.0, k * 2.0))
				arm_r_z = -0.25
				spine_y = 0.35
				head_y = -0.3
			"cast":
				var s := sin(k * PI)
				arm_r_x = lerpf(-0.4, -2.1, s)
				elbow_r = lerpf(-0.4, -0.2, s)
				arm_l_x = lerpf(0.0, -1.2, s)
				elbow_l = -0.4
				spine_x = -0.08 * s
	# seduto
	var sit := _sit_t
	hips.position.y = lerpf(hip_height + bob, 0.52, sit)
	leg_l.rotation.x = lerpf(-leg_a, -1.5, sit)
	leg_r.rotation.x = lerpf(leg_a, -1.45, sit)
	shin_l.rotation.x = lerpf(knee_l, 1.5, sit)
	shin_r.rotation.x = lerpf(knee_r, 1.45, sit)
	arm_l.rotation = Vector3(arm_l_x + arm_a, 0, arm_l_z)
	arm_r.rotation = Vector3(arm_r_x - arm_a, 0, arm_r_z)
	fore_l.rotation.x = elbow_l
	fore_r.rotation.x = elbow_r
	# chi impugna bastoni o archi li tiene dritti compensando braccio e gomito
	hand_r.rotation.x = -(arm_r.rotation.x + elbow_r) - (0.25 if attack_timer > 0.0 and attack_style == "cast" else 0.0) if upright_r else 0.0
	hand_l.rotation.x = -(arm_l.rotation.x + elbow_l) if upright_l else 0.0
	spine.rotation = Vector3(spine_x + sit * 0.05, spine_y, 0)
	head.rotation = Vector3(head_x, head_y, 0)
	# caduto: si accascia all'indietro
	var d := _dead_t
	rig.rotation.x = -1.42 * d * d
	rig.position.y = 0.06 * d

func _animate_beast() -> void:
	if rig == null: return
	var t := phase
	var trot := t * 9.0
	var moving := anim == "walk"
	var a := sin(trot) * 0.55 if moving else 0.0
	leg_l.rotation.x = -a
	legs_back[1].rotation.x = -a
	leg_r.rotation.x = a
	legs_back[0].rotation.x = a
	shin_l.rotation.x = maxf(0.0, sin(trot + 1.2)) * 0.6 if moving else 0.0
	shin_r.rotation.x = maxf(0.0, sin(trot + 1.2 + PI)) * 0.6 if moving else 0.0
	spine.position.y = 0.66 + (absf(sin(trot)) * 0.03 if moving else sin(t * 2.0) * 0.008)
	tail.rotation = Vector3(0.3 + sin(t * 3.0) * 0.1, sin(t * (6.0 if moving else 2.0)) * 0.35, 0)
	head.rotation.x = 0.0
	if attack_timer > 0.0:
		var k := sin((1.0 - attack_timer / attack_length) * PI)
		spine.position.z = 0.22 + k * 0.22
		head.rotation.x = 0.35 * k
		hips.position.y = 0.62 - k * 0.04
	else:
		spine.position.z = 0.22
		hips.position.y = 0.62
	var d := _dead_t
	rig.rotation.z = 1.45 * d * d
	rig.position.y = 0.05 * d

func flash(amount: float) -> void:
	if _flash_mat != null: _flash_mat.set_shader_parameter("intensity", amount * 1.6)
