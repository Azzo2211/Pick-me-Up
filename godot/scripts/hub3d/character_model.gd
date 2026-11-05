extends Node3D
class_name CharacterModel

## Personaggi con proporzioni reali: eroi, abitanti, predoni, lupi, bruti e
## guardiani di pietra. Costruiti in metri e scalati a unità di mondo
## (1 unità = 2 m). Il modello guarda verso +Z; animazioni procedurali.

const METER := 0.5
const Motion := preload("res://scripts/hub3d/motion_library.gd")
const ToonShader := preload("res://scripts/hub3d/shaders/toon.gdshader")
const OutlineShader := preload("res://scripts/hub3d/shaders/outline.gdshader")
const FaceShader := preload("res://scripts/hub3d/shaders/face.gdshader")
const CharacterGeneratorScript := preload("res://scripts/characters/character_generator.gd")
const HeroLookScript := preload("res://scripts/characters/hero_look.gd")
const CharacterKitScript := preload("res://scripts/characters/character_kit.gd")
const KitToonShader := preload("res://scripts/hub3d/shaders/kit_toon.gdshader")
const KitOutlineShader := preload("res://scripts/hub3d/shaders/kit_outline.gdshader")
const HairShader := preload("res://scripts/hub3d/shaders/hair.gdshader")
## Animazione base → clip del pacchetto di animazioni. Quello che manca qui resta
## procedurale: "sit" e "rest" (pose tarate su panche e letti), "train" e i colpi di
## spada e lancia, che nei clip si leggono meno bene da lontano.
const BASE_CLIPS := {"idle": "Idle", "walk": "Walk_F", "talk": "Interact", "cheer": "Cheer", "dead": "Death"}
const ATTACK_CLIPS := {"bow": "Bow_Shot", "cast": "Cast_Spell"}
const JOINT_NAMES := ["hips", "spine", "head", "arm_l", "arm_r", "fore_l", "fore_r", "hand_l", "hand_r", "leg_l", "leg_r", "shin_l", "shin_r"]
const BLEND_TIME := 0.18

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
## Clip di animazione (falso: solo pose procedurali, per esempio se manca il GLB).
var use_clips := true
var _clip := ""
var _clip_t := 0.0
var _action := ""
var _pose: Dictionary = {}
var _fade_from: Dictionary = {}
var _fade_t := 1.0
## Spessore del contorno anime in pixel (i ritratti delle carte lo alzano).
var outline_px := 1.3
var _face_mat: ShaderMaterial
var _head_kit: Node3D
const KIT_HEAD_SCALE := 0.9
## Corpo del kit (tools/character_kit): scheletro mosso dalle articolazioni del rig.
var _skel: Skeleton3D
var _bone_ids := PackedInt32Array()
static var _toon_cache: Dictionary = {}

# =============================================================================
# Costruzione: eroi
# =============================================================================

func build_hero(hero: Dictionary, appearance: Dictionary) -> void:
	var role := str(hero.get("role", "Guardian"))
	var rarity := int(hero.get("current_rarity", 1))
	var outfit := str(appearance.get("outfit_kind", HeroLookScript.CLASS_OUTFIT.get(role, "villager")))
	var look := appearance.duplicate()
	look["class_chosen"] = not RiftwardState.needs_class(hero)
	_build_anime(look, role, rarity, outfit, str(appearance.get("prop", "")))

## Abitante della base (non combattente): un popolano con il suo mestiere, senza attrezzo.
func build_villager(seed_value: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var jobs := ["Contadino", "Fabbro", "Carpentiere", "Cuoco", "Minatore", "Mercante", "Bottegaio", "Locandiere", "Erborista", "Archivista"]
	var job: String = jobs[r.randi() % jobs.size()]
	var names: Array = RiftwardState.FIRST_NAMES
	var fake := {"id": "V-%d" % seed_value, "name": "%s Villa" % names[r.randi() % names.size()], "commoner": true, "class_chosen": false,
		"job": job, "native_rarity": 1, "role": "Villager", "hue": r.randi_range(0, 359)}
	fake["appearance"] = CharacterGeneratorScript.generate(str(fake.id) + ":appearance", str(RiftwardState.COMMONER_JOBS[job].category))
	var look := RiftwardState.appearance_for(fake)
	look["class_chosen"] = false
	_build_anime(look, "Villager", 1, str(look.outfit_kind), "")

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
			if _build_raider(tint, true): return
			_build_rig({"scale": 0.98, "shoulder": 0.195, "hip": 0.1})
			_dress_bandit(accent, true)
			attack_style = "bow"
		_:
			if _build_raider(tint, false): return
			_build_rig({"scale": 1.0, "shoulder": 0.205, "hip": 0.1})
			_dress_bandit(accent, false)
			attack_style = "melee"
	_finish()

static var _raider_count := 0

## Predoni del Varco col kit dei personaggi: corpo da cacciatore in cuoio scuro,
## cappuccio e fazzoletto sul viso nel colore della banda, falcione o arco.
## Stessa qualità degli eroi; false se il kit non c'è (si usa il modello semplice).
func _build_raider(tint: Color, archer: bool) -> bool:
	if not CharacterKitScript.has_outfit("hunter") or CharacterKitScript.part("hood") == null: return false
	_raider_count += 1
	var seed_text := "raider:%d:%s" % [_raider_count, tint.to_html(false)]
	var gen: Dictionary = CharacterGeneratorScript.generate(seed_text)
	var fake := {"id": seed_text, "name": "Predone", "commoner": true, "native_rarity": 1, "role": "Ranger" if archer else "Vanguard",
		"hue": abs(seed_text.hash()) % 360, "appearance": gen, "gender": "m"}
	var look := RiftwardState.appearance_for(fake)
	look["fem"] = false
	look["glasses"] = false
	look["class_chosen"] = false
	look["role"] = "Raider"
	look["anime"] = true
	look["face"] = 2 if _raider_count % 2 == 0 else 1
	look["body"] = ["athletic", "muscular", "average"][_raider_count % 3]
	look["hair_kind"] = "none" # sotto il cappuccio
	look["beard"] = 0
	_build_rig({"scale": 0.98 if archer else 1.0, "shoulder": 0.2, "hip": 0.1})
	var inst := CharacterKitScript.body_instance("hunter")
	var skel := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	skel.get_parent().remove_child(skel)
	inst.free()
	skel.name = "KitSkeleton"
	skel.transform = Transform3D.IDENTITY
	rig.add_child(skel)
	_skel = skel
	_bone_ids = PackedInt32Array()
	for j in JOINT_NAMES: _bone_ids.append(skel.find_bone(j))
	var band := Color.from_hsv(tint.h, clampf(tint.s, 0.35, 0.7), clampf(tint.v, 0.32, 0.5))
	var pal := CharacterKitScript.palette(look, "hunter", 1)
	var dark := {CharacterKitScript.MAIN: Color("#2d2622"), CharacterKitScript.SECOND: Color("#241e1b"),
		CharacterKitScript.LIGHT: Color("#5a4c40"), CharacterKitScript.LEATHER: Color("#3b2a1f"),
		CharacterKitScript.BOOT: Color("#1f1814"), CharacterKitScript.DARK: Color("#17120f"),
		CharacterKitScript.ACCENT: band, CharacterKitScript.GOLD: Color("#6d6250")}
	for slot in dark: pal = _kit_pal(pal, slot, dark[slot])
	var shapes := {look.body: 1.0} if str(look.body) != "average" else {}
	for node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.material_override = _kit_material(pal)
		for key in shapes:
			var idx := mi.find_blend_shape_by_name(key)
			if idx >= 0: mi.set_blend_shape_value(idx, shapes[key])
		mi.material_overlay = _flash()
		_meshes.append(mi)
	_kit_head(look, pal, "hunter")
	_kit_piece("hood", _kit_material(_kit_pal(pal, CharacterKitScript.MAIN, band.darkened(0.08))))
	# fazzoletto di stoffa grezza, tinto appena col colore della banda: si legge come stoffa, non come una macchia nera
	_kit_piece("mask", _kit_material(_kit_pal(pal, CharacterKitScript.DARK, Color("#6a5e52").lerp(band, 0.25))))
	if archer:
		_bow(_b("hand_l"), Color("#3d2a1c"))
		upright_l = true
		attack_style = "bow"
	else:
		_falchion(_b("hand_r"), Color("#8d9097"))
		attack_style = "melee"
	_finish()
	return true

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
	_head_kit = null
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
	b.material("cloth", toon_material("cloth", outline_px))
	b.material("metal", toon_material("metal", outline_px))
	b.material("dull", toon_material("dull", outline_px))
	b.material("fine", toon_material("fine", 0.0))
	b.material("rock", WorldMaterials.terrain())
	_parts[part] = b
	return b

## Materiali anime condivisi: due toni di ombra e contorno scuro.
static func toon_material(kind: String, px: float) -> ShaderMaterial:
	var key := "%s|%.2f" % [kind, px]
	if _toon_cache.has(key): return _toon_cache[key]
	var m := ShaderMaterial.new()
	m.shader = ToonShader
	match kind:
		"metal":
			m.set_shader_parameter("toon_spec", 0.55)
			m.set_shader_parameter("toon_shade", 0.3)
			m.set_shader_parameter("toon_rim", 0.28)
		"dull", "fine":
			m.set_shader_parameter("toon_spec", 0.45)
			m.set_shader_parameter("toon_rim", 0.22)
	# "fine": dettagli sottili (occhiali) senza contorno, che li ingrosserebbe
	if px > 0.0: m.next_pass = outline_material(px)
	_toon_cache[key] = m
	return m

static func outline_material(px: float) -> ShaderMaterial:
	var key := "outline|%.2f" % px
	if _toon_cache.has(key): return _toon_cache[key]
	var m := ShaderMaterial.new()
	m.shader = OutlineShader
	m.set_shader_parameter("width_px", px)
	_toon_cache[key] = m
	return m

func _glow(part: String, color: Color, energy: float = 2.2) -> String:
	var key := "glow_" + color.to_html()
	_b(part).material(key, WorldMaterials.glow(color, energy))
	return key

func _finish() -> void:
	var map := {"hips": hips, "spine": spine, "head": head, "arm_l": arm_l, "arm_r": arm_r, "fore_l": fore_l, "fore_r": fore_r,
		"hand_l": hand_l, "hand_r": hand_r, "leg_l": leg_l, "leg_r": leg_r, "shin_l": shin_l, "shin_r": shin_r, "tail": tail, "root": rig}
	for i in legs_back.size(): map["back_%d" % i] = legs_back[i]
	_flash()
	for part in _parts:
		var b: MeshBuilder = _parts[part]
		var pivot: Node3D = map.get(part)
		if pivot == null or not b.has_geometry(): continue
		var mi := b.instance(pivot)
		mi.material_overlay = _flash_mat
		_meshes.append(mi)
	_parts.clear()
	update_animation(0.0)

func _flash() -> ShaderMaterial:
	if _flash_mat == null:
		_flash_mat = WorldMaterials.highlight()
		_flash_mat.set_shader_parameter("glow_color", Color(1.0, 0.92, 0.85))
	return _flash_mat

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
	_head_details(b, look)
	b.pop()

## Orecchie da elfo, occhiali e tratti da uomo-bestia, come nel ritratto dipinto.
func _head_details(b: MeshBuilder, look: Dictionary) -> void:
	var skin: Color = look.skin
	var hair: Color = look.hair
	if look.get("elf", false):
		for sx in [-1.0, 1.0]:
			b.rod("cloth", Vector3(sx * 0.098, 0.13, -0.004), Vector3(sx * 0.168, 0.205, -0.034), 0.022, 0.003, skin.darkened(0.04), 6)
	if look.get("glasses", false):
		var frame := Color("#2b2421")
		for sx in [-1.0, 1.0]:
			b.torus("dull", 0.021, 0.0035, Vector3(sx * 0.037, 0.143, 0.106), frame, Vector3(PI * 0.5, 0, 0), 14, 4)
		b.box("dull", Vector3(0.03, 0.005, 0.005), Vector3(0, 0.147, 0.11), frame)
	match str(look.get("beast", "")):
		"feline":
			for sx in [-1.0, 1.0]:
				b.rod("cloth", Vector3(sx * 0.058, 0.215, -0.012), Vector3(sx * 0.088, 0.3, -0.03), 0.036, 0.004, hair.darkened(0.1), 6)
			b.sphere("cloth", 0.045, Vector3(0, 0.1, 0.085), skin.lightened(0.08), Vector3(1.1, 0.75, 0.9), 8, 5)
		"lizard":
			b.sphere("cloth", 0.06, Vector3(0, 0.1, 0.09), skin, Vector3(0.95, 0.7, 1.3), 8, 5)
			for i in 4:
				b.rod("cloth", Vector3(0, 0.235 - i * 0.012, 0.02 - i * 0.045), Vector3(0, 0.29 - i * 0.02, -0.01 - i * 0.05), 0.016, 0.002, skin.darkened(0.25), 5)
		"bull":
			for sx in [-1.0, 1.0]:
				b.rod("cloth", Vector3(sx * 0.075, 0.215, 0.0), Vector3(sx * 0.2, 0.27, 0.03), 0.026, 0.004, Color("#d9cdb0"), 6)
			b.sphere("cloth", 0.055, Vector3(0, 0.09, 0.09), skin.lightened(0.1), Vector3(1.1, 0.8, 0.9), 8, 5)

func _hair(b: MeshBuilder, look: Dictionary) -> void:
	var hair: Color = look.hair
	var style := int(look.get("style", 0))
	var fem: bool = look.get("fem", false)
	if look.get("hood", false) or look.get("bald", false):
		_beard(b, look)
		return
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
			var long_hair: bool = fem or look.get("long", false)
			b.box("cloth", Vector3(0.21, 0.3 if long_hair else 0.18, 0.05), Vector3(0, 0.0 if long_hair else 0.05, -0.085), hair, Vector3(0.12, 0, 0))
			for sx in [-1.0, 1.0]: b.box("cloth", Vector3(0.04, 0.2 if long_hair else 0.1, 0.06), Vector3(sx * 0.098, 0.07 if long_hair else 0.12, 0.02), hair)
		3:
			b.sphere("cloth", 0.04, Vector3(0, 0.17, -0.12), hair, Vector3.ONE, 6, 4)
			b.rod("cloth", Vector3(0, 0.15, -0.13), Vector3(0, -0.06, -0.17), 0.034, 0.018, hair, 6)
		4:
			b.sphere("cloth", 0.055, Vector3(0, 0.24, -0.07), hair, Vector3(1, 0.85, 1), 8, 5)
		5:
			b.box("cloth", Vector3(0.2, 0.1, 0.16), Vector3(0, 0.2, -0.04), hair, Vector3(-0.3, 0, 0))
			b.box("cloth", Vector3(0.18, 0.12, 0.05), Vector3(0, 0.1, -0.11), hair, Vector3(0.25, 0, 0))
	_beard(b, look)

func _beard(b: MeshBuilder, look: Dictionary) -> void:
	var beard := int(look.get("beard", 0))
	if beard > 0:
		b.sphere("cloth", 0.07, Vector3(0, 0.055, 0.06), (look.hair as Color).darkened(0.1), Vector3(1.05, 0.8 if beard == 1 else 1.1, 0.75), 8, 5)

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
	# testa coperta nel ritratto (cappuccio, cappello, fazzoletto): cappuccio anche in 3D
	var covered: bool = look.get("covered", false) and role != "Ranger" and str(look.get("beast", "")).is_empty()
	if covered: look["hood"] = true
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
	if covered:
		_hood(_b("head"), o.darkened(0.22))
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
# Eroi a pezzi (foglio dei personaggi): corpo, testa base, volto, capelli, vestiti
# =============================================================================

func _build_anime(look_in: Dictionary, role: String, rarity: int, outfit: String, prop: String) -> void:
	var look := look_in.duplicate()
	look["anime"] = true
	look["role"] = role
	look["rarity"] = rarity
	_build_kit(look, role, rarity, outfit if CharacterKitScript.has_outfit(outfit) else "villager", prop)

# --- Kit modellato in Blender ---------------------------------------------------------

## Personaggio dal kit: corpo vestito unico (si piega con lo scheletro), testa base
## con il volto disegnato, capelli e accessori; arma o attrezzo come prima.
func _build_kit(look: Dictionary, role: String, rarity: int, outfit: String, prop: String) -> void:
	var fem: bool = look.get("fem", false)
	var height := clampf(float(look.get("height", 1.0)), 0.93, 1.07)
	if int(look.get("age", 28)) < 18: height *= 0.97
	# le articolazioni restano quelle del kit: le corporature sono chiavi di forma
	_build_rig({"scale": (0.95 if fem else 1.0) * height, "shoulder": 0.2, "hip": 0.1})
	var inst := CharacterKitScript.body_instance(outfit)
	var found := inst.find_children("*", "Skeleton3D", true, false)
	var skel := found[0] as Skeleton3D
	skel.get_parent().remove_child(skel)
	inst.free()
	skel.name = "KitSkeleton"
	skel.transform = Transform3D.IDENTITY
	rig.add_child(skel)
	_skel = skel
	_bone_ids = PackedInt32Array()
	for j in JOINT_NAMES: _bone_ids.append(skel.find_bone(j))
	var pal := CharacterKitScript.palette(look, outfit, rarity)
	var shapes := {}
	if fem: shapes["fem"] = 1.0
	var body := str(look.get("body", "average"))
	if body != "average": shapes[body] = 1.0
	for node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.material_override = _kit_material(pal)
		for key in shapes:
			var idx := mi.find_blend_shape_by_name(key)
			if idx >= 0: mi.set_blend_shape_value(idx, shapes[key])
		mi.material_overlay = _flash()
		_meshes.append(mi)
	_kit_head(look, pal, outfit)
	if role == "Villager":
		attack_style = "melee"
	elif not prop.is_empty():
		_prop(prop, look)
	else:
		_class_weapon(role, look)
	_finish()

func _kit_material(pal: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = KitToonShader
	m.set_shader_parameter("palette", pal)
	var line := ShaderMaterial.new()
	line.shader = KitOutlineShader
	line.set_shader_parameter("palette", pal)
	line.set_shader_parameter("width_px", outline_px)
	m.next_pass = line
	return m

func _kit_line(color: Color) -> ShaderMaterial:
	var line := ShaderMaterial.new()
	line.shader = KitOutlineShader
	line.set_shader_parameter("use_palette", false)
	line.set_shader_parameter("base_color", color)
	line.set_shader_parameter("width_px", outline_px)
	return line

func _kit_piece(name: String, material: Material) -> MeshInstance3D:
	var mesh := CharacterKitScript.part(name)
	if mesh == null: return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.material_overlay = _flash()
	if _head_kit == null:
		# la testa del kit è un po' più piccola del perno: corpo adulto di circa otto
		# teste come nel foglio (il mento resta sul collo)
		_head_kit = Node3D.new()
		_head_kit.name = "KitHead"
		_head_kit.scale = Vector3.ONE * KIT_HEAD_SCALE
		# testa un filo più bassa: il collo del kit sembrava lungo e sottile
		_head_kit.position = Vector3(0.0, -0.022, 0.004)
		head.add_child(_head_kit)
	_head_kit.add_child(mi)
	_meshes.append(mi)
	return mi

func _kit_head(look: Dictionary, pal: Array, outfit: String) -> void:
	var skin: Color = look.skin
	_face_mat = _make_face_material(look)
	_face_mat.set_shader_parameter("skin_color", skin)
	_face_mat.next_pass = _kit_line(skin)
	var head_mi := _kit_piece("head", _face_mat)
	if head_mi != null:
		var face := int(look.get("face", 1))
		var keys := {"fem": 1.0 if look.get("fem", false) else 0.0, "sharp": 1.0 if face == 0 else 0.0,
			"square": 1.0 if face == 2 else 0.0,
			"full": 1.0 if str(look.get("body", "")) == "chubby" else (0.5 if int(look.get("age", 28)) >= 50 else 0.0)}
		for key in keys:
			var idx := head_mi.find_blend_shape_by_name(key)
			if idx >= 0: head_mi.set_blend_shape_value(idx, keys[key])
	var hair_col: Color = look.get("hair", Color("#3a2a20"))
	var hm := ShaderMaterial.new()
	hm.shader = HairShader
	hm.set_shader_parameter("hair_color", hair_col)
	hm.set_shader_parameter("tie_color", (pal[CharacterKitScript.ACCENT] as Color))
	hm.next_pass = _kit_line(hair_col)
	_kit_piece("hair_" + str(look.get("hair_kind", "short")), hm)
	var beard := int(look.get("beard", 0))
	if beard >= 2:
		_kit_piece("beard_goatee" if int(look.get("face", 1)) == 0 else "beard_short", _kit_material(_kit_pal(pal, CharacterKitScript.DARK, hair_col.darkened(0.08))))
	if look.get("glasses", false):
		# niente contorno: ingrosserebbe la montatura sottile
		var gm := _kit_material(_kit_pal(pal, CharacterKitScript.DARK, Color("#3a2c24")))
		gm.next_pass = null
		_kit_piece("glasses", gm)
	if outfit == "villager" and int(look.get("seed", 0)) % 3 == 0 and str(look.get("hair_kind", "")) in ["crop", "short", "bun", "tied_back"]:
		_kit_piece("headband", _kit_material(_kit_pal(pal, CharacterKitScript.LIGHT, Color("#e9e2d2"))))

func _kit_pal(pal: Array, slot: int, color: Color) -> Array:
	var out := pal.duplicate()
	out[slot] = Color(color.r, color.g, color.b, (pal[slot] as Color).a)
	return out

# --- Volto ----------------------------------------------------------------------------

## I tre volti del foglio come parametri del disegno del volto.
func _make_face_material(look: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FaceShader
	var fem: bool = look.get("fem", false)
	var face := int(look.get("face", 1))
	var archetype := str(look.get("archetype", "villager"))
	var age := int(look.get("age", 28))
	var hair: Color = look.get("hair", Color("#3a2a20"))
	var size := lerpf(1.0, float(look.get("eye_size", 1.0)), 0.5) * (1.06 if age < 20 else 1.0)
	# volto adulto come nel foglio: occhi stretti e taglienti con l'iride tagliata dalla
	# palpebra, sopracciglia dritte e vicine agli occhi, naso e bocca a tratto
	var p := {
		"eye_x": 0.38, "eye_y": 0.0, "mouth_y": -0.6,
		"eye_w": 0.19, "eye_h": 0.1, "iris_r": 0.1, "eye_tilt": 0.15, "lid_th": 0.034,
		"lash": 1.0, "lash_flick": 0.0, "lower_lash": 0.6, "crease": 0.45, "brow_thick": 0.032,
		"brow_gap": 0.05, "brow_tilt": 0.5, "brow_arch": 0.012, "mouth_w": 0.14, "mouth_curve": 0.0, "blush": 0.0, "lips": 0.0,
	}
	match face:
		0:
			# bello: occhi un po' più aperti e allungati, sguardo morbido
			p.merge({"eye_h": 0.11, "iris_r": 0.108, "eye_tilt": 0.2, "lash": 1.1, "brow_thick": 0.027, "brow_tilt": 0.6,
				"brow_arch": 0.018, "mouth_w": 0.12, "blush": 0.1}, true)
		2:
			# rude: occhi piccoli e incassati, sopracciglia pesanti e basse, bocca larga
			p.merge({"eye_w": 0.18, "eye_h": 0.08, "iris_r": 0.085, "eye_tilt": 0.05, "lid_th": 0.036, "crease": 0.8,
				"brow_thick": 0.042, "brow_gap": 0.032, "brow_tilt": -0.2, "brow_arch": 0.005, "mouth_w": 0.16,
				"mouth_curve": -0.01}, true)
	# sfumature per archetipo, come nel foglio
	if archetype == "merchant" and face != 2: p.mouth_curve = 0.026
	if archetype == "villager" and face == 0: p.mouth_curve = 0.03
	if archetype == "scholar" and face == 1:
		p.eye_h = 0.085
		p.crease = 0.6
	if fem:
		p.eye_h = float(p.eye_h) * 1.6
		p.iris_r = float(p.iris_r) * 1.36
		p.eye_tilt = float(p.eye_tilt) * 0.6
		p.lash = float(p.lash) * 1.3
		p.lash_flick = 1.0 if face == 0 else 0.6
		p.brow_thick = float(p.brow_thick) * 0.7
		p.brow_gap = float(p.brow_gap) + 0.035
		p.brow_tilt = float(p.brow_tilt) * 0.3
		p.brow_arch = float(p.brow_arch) + 0.018
		p.blush = float(p.blush) + 0.45
		p.lips = 0.6
		p.mouth_w = float(p.mouth_w) * 0.85
	p.eye_w = float(p.eye_w) * size
	p.eye_h = float(p.eye_h) * size
	p.iris_r = float(p.iris_r) * size
	for key in p: m.set_shader_parameter(key, p[key])
	# sul viso l'ombra è più morbida: occhi e bocca restano leggibili
	m.set_shader_parameter("toon_shade", 0.8)
	m.set_shader_parameter("toon_shadow_tint", Color(1.0, 0.86, 0.86))
	m.set_shader_parameter("iris_color", look.get("eyes", Color("#3b5a7a")))
	m.set_shader_parameter("brow_color", hair.darkened(0.42).lerp(Color("#2a1d16"), 0.3))
	m.set_shader_parameter("age_lines", clampf((age - 38) / 18.0, 0.0, 1.0) + (0.25 if face == 2 else 0.0))
	m.set_shader_parameter("stubble", 0.35 if int(look.get("beard", 0)) >= 1 else 0.0)
	m.set_shader_parameter("stubble_color", hair.darkened(0.2))
	m.set_shader_parameter("scar", 1.0 if look.get("scar", false) else 0.0)
	m.set_shader_parameter("freckles", 1.0 if look.get("freckles", false) else 0.0)
	m.next_pass = outline_material(outline_px)
	return m

## Occhi chiusi (caduti).
func set_eyes_closed(value: bool) -> void:
	if _face_mat != null: _face_mat.set_shader_parameter("closed", 1.0 if value else 0.0)

# --- Armi di classe e attrezzi dei mestieri ------------------------------------

func _class_weapon(role: String, look: Dictionary) -> void:
	var steel := Color("#b4bac4")
	var gold := Color("#c9a85c")
	match role:
		"Guardian":
			_sword(_b("hand_r"), 0.78, 0.045, steel, gold)
			_shield(_b("fore_l"), Color("#8f2a2f").lerp(look.outfit, 0.2), gold, steel)
			attack_style = "melee"
		"Vanguard":
			_sword(_b("hand_r"), 1.15, 0.065, steel, gold)
			attack_style = "heavy"
		"Lancer":
			_spear(_b("hand_r"), steel, gold)
			attack_style = "thrust"
		"Ranger":
			_bow(_b("hand_l"), Color("#5a3d26"))
			upright_l = true
			attack_style = "bow"
		"Mage":
			_staff(_b("hand_r"), Color("#3b2a1e"), (look.accent as Color).lightened(0.25))
			upright_r = true
			attack_style = "cast"
		"Support":
			_healer_staff(_b("hand_r"), Color("#d9cfb8"), Color("#7ef0b2"))
			upright_r = true
			attack_style = "cast"
		_:
			attack_style = "melee"

## Attrezzo del mestiere, in mano ai popolani che non hanno ancora una classe.
func _prop(prop: String, look: Dictionary) -> void:
	var wood := Color("#7a5634")
	var iron := Color("#8d939b")
	var b := _b("hand_r")
	match prop:
		"bow":
			_bow(_b("hand_l"), Color("#6a4a2c"))
			upright_l = true
			attack_style = "bow"
			return
		"staff":
			b.push(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, -0.04, 0.02)))
			b.rod("cloth", Vector3(0, -0.9, 0), Vector3(0, 0.75, 0), 0.02, 0.026, wood, 7)
			b.sphere("cloth", 0.035, Vector3(0, 0.78, 0), wood.darkened(0.2), Vector3.ONE, 8, 5)
			b.pop()
			upright_r = true
			attack_style = "cast"
			return
		"book", "map", "pouch":
			var col := Color("#6b2f2a") if prop == "book" else Color("#e0d3b0") if prop == "map" else Color("#7c5a36")
			if prop == "book": b.box("cloth", Vector3(0.12, 0.16, 0.035), Vector3(0, -0.09, 0.03), col)
			elif prop == "map": b.cylinder("cloth", 0.022, 0.022, 0.2, Vector3(0, -0.07, 0.03), col, 8, Vector3(0, 0, PI * 0.5))
			else: b.sphere("cloth", 0.05, Vector3(0, -0.1, 0.03), col, Vector3(1, 1.2, 0.9), 8, 5)
			attack_style = "cast"
			return
	b.push(Transform3D(Basis(Vector3.RIGHT, 1.75), Vector3(0, -0.04, 0.01)))
	match prop:
		"pitchfork":
			b.rod("cloth", Vector3(0, -0.6, 0), Vector3(0, 0.9, 0), 0.016, 0.016, wood, 6)
			b.box("dull", Vector3(0.14, 0.02, 0.02), Vector3(0, 0.9, 0), iron)
			for i in 3: b.cone("dull", 0.01, 0.2, Vector3(-0.06 + i * 0.06, 1.0, 0), iron, 5)
			attack_style = "thrust"
		"hammer":
			b.rod("cloth", Vector3(0, -0.08, 0), Vector3(0, 0.42, 0), 0.016, 0.018, wood, 6)
			b.box("dull", Vector3(0.16, 0.08, 0.08), Vector3(0, 0.45, 0), iron.darkened(0.2))
			attack_style = "heavy"
		"axe":
			b.rod("cloth", Vector3(0, -0.08, 0), Vector3(0, 0.55, 0), 0.016, 0.018, wood, 6)
			b.extrude("metal", PackedVector2Array([Vector2(0.0, 0.5), Vector2(0.14, 0.44), Vector2(0.16, 0.6), Vector2(0.0, 0.58)]), -0.008, 0.008, iron, true, true)
			attack_style = "heavy"
		"pickaxe":
			b.rod("cloth", Vector3(0, -0.08, 0), Vector3(0, 0.55, 0), 0.016, 0.018, wood, 6)
			b.rod("dull", Vector3(-0.2, 0.5, 0), Vector3(0.2, 0.5, 0), 0.012, 0.024, iron, 6)
			attack_style = "heavy"
		"club":
			b.rod("cloth", Vector3(0, -0.08, 0), Vector3(0, 0.55, 0), 0.02, 0.045, wood.darkened(0.15), 8)
			attack_style = "melee"
		"ladle":
			b.rod("dull", Vector3(0, -0.06, 0), Vector3(0, 0.38, 0), 0.008, 0.008, iron, 5)
			b.sphere("dull", 0.05, Vector3(0, 0.42, 0.02), iron, Vector3(1, 0.5, 1), 10, 6, true, Vector3(PI, 0, 0))
			attack_style = "melee"
		_:
			# coltello, falcetto
			b.cylinder("cloth", 0.014, 0.015, 0.11, Vector3(0, 0.0, 0), wood, 6)
			b.box("metal", Vector3(0.03, 0.2 if prop == "knife" else 0.14, 0.008), Vector3(0, 0.15, 0), iron, Vector3(0, 0, 0.0 if prop == "knife" else 0.5))
			attack_style = "melee"
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
	var fur := Color("#4b433b").lerp(tint.darkened(0.55), 0.15)
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
	# corpo morbido e muscoloso: groppa, torace profondo, collo con la gorgiera di pelo
	var hb := _b("hips")
	hb.sphere("cloth", 0.13, Vector3(0, 0.02, 0.06), fur, Vector3(0.98, 1.15, 1.6), 16, 10, false, Vector3.ZERO, belly)
	for sx in [-1.0, 1.0]: hb.sphere("cloth", 0.075, Vector3(sx * 0.075, -0.02, -0.02), fur, Vector3(0.8, 1.25, 1.2), 12, 8)
	var sb := _b("spine")
	sb.sphere("cloth", 0.155, Vector3(0, -0.03, -0.12), fur, Vector3(0.92, 1.4, 1.7), 16, 10, false, Vector3.ZERO, belly)
	sb.sphere("cloth", 0.13, Vector3(0, -0.02, 0.12), fur.lightened(0.05), Vector3(1.0, 1.7, 1.1), 16, 10, false, Vector3.ZERO, belly)
	for sx in [-1.0, 1.0]: sb.sphere("cloth", 0.07, Vector3(sx * 0.08, -0.03, 0.1), fur, Vector3(0.8, 1.3, 1.1), 12, 8)
	sb.rod("cloth", Vector3(0, 0.06, 0.14), Vector3(0, 0.14, 0.3), 0.085, 0.065, fur, 12)
	# gorgiera: ciocche di pelo a cono intorno al collo e sul dorso
	for k in 9:
		var a := -2.2 + 4.4 * k / 8.0
		sb.cone("cloth", 0.035, 0.11, Vector3(sin(a) * 0.1, 0.1 + cos(a) * 0.06, 0.15), fur.darkened(0.06), 6, Vector3(-1.1 + cos(a) * 0.5, 0, -sin(a) * 0.9))
	for k in 5:
		sb.cone("cloth", 0.03, 0.08, Vector3(0, 0.15 - k * 0.012, 0.02 - k * 0.07), fur.darkened(0.12), 5, Vector3(-1.9, 0, 0))
	var hd := _b("head")
	hd.sphere("cloth", 0.098, Vector3(0, 0.02, 0.0), fur, Vector3(1.05, 0.92, 1.1), 16, 10, false, Vector3.ZERO, belly)
	for sx in [-1.0, 1.0]: hd.sphere("cloth", 0.05, Vector3(sx * 0.065, -0.02, 0.02), fur.lightened(0.04), Vector3(0.9, 1.0, 1.2), 10, 6)
	hd.push(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, -0.012, 0.13)))
	hd.cylinder("cloth", 0.03, 0.062, 0.19, Vector3.ZERO, fur.darkened(0.04), 12, Vector3(PI / 2, 0, 0))
	hd.box("cloth", Vector3(0.07, 0.025, 0.15), Vector3(0, -0.035, 0.0), belly.darkened(0.1))
	hd.pop()
	hd.sphere("cloth", 0.022, Vector3(0, 0.0, 0.235), Color("#121010"), Vector3(1.2, 0.9, 1.0), 8, 6)
	# zanne
	for sx in [-1.0, 1.0]: hd.cone("cloth", 0.007, 0.03, Vector3(sx * 0.022, -0.05, 0.19), Color("#e8e0cc"), 5, Vector3(PI, 0, 0))
	for sx in [-1.0, 1.0]:
		hd.cone("cloth", 0.04, 0.1, Vector3(sx * 0.06, 0.12, -0.03), fur.darkened(0.15), 6, Vector3(-0.25, 0, sx * 0.32))
		hd.cone("cloth", 0.022, 0.06, Vector3(sx * 0.058, 0.115, -0.02), Color("#5a3e38"), 5, Vector3(-0.25, 0, sx * 0.32))
	var eye := _glow("head", Color("#ffb347"), 2.8)
	for sx in [-1.0, 1.0]: hd.sphere(eye, 0.015, Vector3(sx * 0.047, 0.045, 0.085), Color.WHITE, Vector3(1.4, 0.7, 0.6), 8, 5)
	for i in 4:
		var ub := _b(["leg_l", "leg_r", "back_0", "back_1"][i])
		var front := i < 2
		# coscia piena in alto, zampa asciutta in basso
		ub.sphere("cloth", 0.07 if front else 0.085, Vector3(0, -0.07, 0.0 if front else -0.02), fur, Vector3(0.8, 1.7, 1.2), 12, 8)
		ub.cylinder("cloth", 0.056, 0.036, 0.32, Vector3(0, -0.16, 0), fur, 12)
		if front:
			var lb := _b(["shin_l", "shin_r"][i])
			lb.cylinder("cloth", 0.036, 0.028, 0.3, Vector3(0, -0.15, 0), fur.darkened(0.1), 10)
			lb.sphere("cloth", 0.036, Vector3(0, -0.3, 0.025), fur.darkened(0.22), Vector3(1.0, 0.6, 1.5), 10, 6)
		else:
			ub.cylinder("cloth", 0.036, 0.028, 0.32, Vector3(0, -0.42, -0.04), fur.darkened(0.1), 10, Vector3(-0.25, 0, 0))
			ub.sphere("cloth", 0.036, Vector3(0, -0.6, 0.02), fur.darkened(0.22), Vector3(1.0, 0.6, 1.5), 10, 6)
	# coda folta
	_b("tail").sphere("cloth", 0.06, Vector3(0, -0.08, -0.16), fur.darkened(0.04), Vector3(0.8, 0.8, 1.9), 12, 8, false, Vector3(0.5, 0, 0))
	_b("tail").sphere("cloth", 0.05, Vector3(0, -0.2, -0.32), fur.darkened(0.14), Vector3(0.8, 0.8, 1.8), 12, 8, false, Vector3(0.7, 0, 0))
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
	elif use_clips and _sit_t <= 0.0 and Motion.ensure(): _animate_clips(delta * speed_scale)
	else:
		if not _clip.is_empty():
			# dai clip alle pose procedurali: si riparte da articolazioni dritte
			for joint in _joints(): joint.quaternion = Quaternion.IDENTITY
			_clip = ""
			_pose = {}
		_animate_human()
	_sync_skeleton()

## Il corpo del kit segue le articolazioni: stesse rotazioni, bacino compreso lo spostamento.
func _sync_skeleton() -> void:
	if _skel == null or _bone_ids.is_empty(): return
	var nodes := _joints()
	for i in nodes.size():
		var b := _bone_ids[i]
		if b >= 0: _skel.set_bone_pose_rotation(b, (nodes[i] as Node3D).quaternion)
	if _bone_ids[0] >= 0: _skel.set_bone_pose_position(_bone_ids[0], hips.position)

## Pose dai clip: animazione base su tutto il corpo, arco e magia sulla parte alta
## (sulle gambe solo da fermi). Le animazioni senza clip usano le pose procedurali,
## lette come quaternioni così che anche quei passaggi siano morbidi.
func _animate_clips(dt: float) -> void:
	if rig == null: return
	var heavy := monster_kind in ["brute", "boss"]
	var base: String = BASE_CLIPS.get(anim, "")
	var action: String = ATTACK_CLIPS.get(attack_style, "") if attack_timer > 0.0 else ""
	var procedural := base.is_empty() or (attack_timer > 0.0 and action.is_empty())
	var key := ("proc:" + anim + (":atk" if attack_timer > 0.0 else "")) if procedural else base
	if key != _clip or action != _action:
		if _clip.is_empty() and _pose.is_empty():
			# primo clip: fase casuale, così una folla non si muove all'unisono
			_clip_t = fmod(float(get_instance_id() % 997) * 0.37, Motion.length(base)) if not base.is_empty() else 0.0
		elif key != _clip:
			_clip_t = 0.0
		_fade_from = _pose
		_fade_t = 0.0 if not _pose.is_empty() else 1.0
		_clip = key
		_action = action
	_clip_t += dt * (0.75 if heavy and base == "Walk_F" else 1.0)
	_fade_t = minf(1.0, _fade_t + dt / BLEND_TIME)
	var pose: Dictionary
	if procedural:
		for joint in _joints(): joint.quaternion = Quaternion.IDENTITY
		_animate_human()
		pose = _read_pose()
	else:
		pose = Motion.sample(base, _clip_t, base != "Death")
		if not action.is_empty():
			var k := 1.0 - attack_timer / attack_length
			var strike := Motion.sample(action, k * Motion.length(action), false)
			for joint in (Motion.UPPER if base == "Walk_F" else Motion.UPPER + Motion.LOWER): pose[joint] = strike[joint]
			if base != "Walk_F": pose["@hips"] = strike["@hips"]
	pose = Motion.blend(_fade_from, pose, _fade_t)
	_pose = pose
	_apply_pose(pose)
	if not procedural:
		# chi impugna bastoni o archi li tiene dritti rispetto al busto
		if upright_r: hand_r.quaternion = (arm_r.quaternion * fore_r.quaternion).inverse()
		if upright_l: hand_l.quaternion = (arm_l.quaternion * fore_l.quaternion).inverse()
		rig.rotation.x = 0.0
		rig.position.y = 0.0

func _joints() -> Array:
	return [hips, spine, head, arm_l, arm_r, fore_l, fore_r, hand_l, hand_r, leg_l, leg_r, shin_l, shin_r]

func _read_pose() -> Dictionary:
	var pose := {}
	var nodes := _joints()
	for i in JOINT_NAMES.size(): pose[JOINT_NAMES[i]] = (nodes[i] as Node3D).quaternion
	pose["@hips"] = (hips.position - Vector3(0, hip_height, 0)) / (hip_height / Motion.SOURCE_HIP_HEIGHT)
	return pose

func _apply_pose(pose: Dictionary) -> void:
	var nodes := _joints()
	for i in JOINT_NAMES.size(): (nodes[i] as Node3D).quaternion = pose[JOINT_NAMES[i]]
	hips.position = Vector3(0, hip_height, 0) + (pose["@hips"] as Vector3) * (hip_height / Motion.SOURCE_HIP_HEIGHT)

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
