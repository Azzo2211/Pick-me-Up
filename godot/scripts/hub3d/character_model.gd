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
const PaintedShader := preload("res://scripts/hub3d/shaders/painted_model.gdshader")
const PaintedOutlineShader := preload("res://scripts/hub3d/shaders/painted_outline.gdshader")
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
var _hit_t := 0.0
var _hit_side := 1.0
var _flash_prev := 0.0
var _last_pos := Vector3.INF
var _speed := 0.0
## ≥ 0: velocità imposta (m/s del modello) al posto di quella misurata. Serve alle anteprime.
var gait_speed := -1.0
## Vero: non corre mai, al più cammina svelto (gli abitanti della base).
var calm := false
var _weapon_r := false
## Perni in più dei mostri (mascella, garretti, punta della coda): nome del pezzo → nodo.
var _extra: Dictionary = {}
var _gait_t := 0.0
var _walk_w := 0.0
var thigh_len := 0.45
var shin_len := 0.45
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
const KIT_HEAD_SCALE := 1.0
## Corpo del kit (tools/character_kit): scheletro mosso dalle articolazioni del rig.
var _skel: Skeleton3D
var _bone_ids := PackedInt32Array()
## Corpo 3D dell'utente (posa a T): per ogni articolazione [inversa del padre, propria],
## la rotazione che porta l'osso dalla posa a T a quella del rig (braccia lungo i fianchi).
var _bone_fix: Array = []
## Apertura delle braccia del corpo dell'utente: un po' fuori dal mantello largo.
const USER_ARM_OPEN := 0.3
static var _painted_cache: Dictionary = {}
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
			_build_brute(accent)
		"boss":
			_build_golem(tint)
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
	_bone_fix = []
	rig = Node3D.new()
	rig.scale = Vector3.ONE * METER * float(p.get("scale", 1.0))
	add_child(rig)
	var shoulder := float(p.get("shoulder", 0.205))
	var hip := float(p.get("hip", 0.1))
	# i mostri grossi hanno proporzioni loro: gambe corte, braccia lunghe, spalle alte
	thigh_len = float(p.get("thigh", 0.45))
	shin_len = float(p.get("shin", 0.45))
	var upper := float(p.get("upper_arm", 0.29))
	var fore := float(p.get("fore_arm", 0.26))
	var chest := float(p.get("chest", 0.42))
	hip_height = 0.05 + thigh_len + shin_len
	hips = _pivot(rig, Vector3(0, hip_height, 0))
	spine = _pivot(hips, Vector3(0, 0.06, 0))
	head = _pivot(spine, p.get("head_at", Vector3(0, 0.5, 0)))
	arm_l = _pivot(spine, Vector3(-shoulder, chest, 0))
	arm_r = _pivot(spine, Vector3(shoulder, chest, 0))
	fore_l = _pivot(arm_l, Vector3(0, -upper, 0))
	fore_r = _pivot(arm_r, Vector3(0, -upper, 0))
	hand_l = _pivot(fore_l, Vector3(0, -fore, 0))
	hand_r = _pivot(fore_r, Vector3(0, -fore, 0))
	leg_l = _pivot(hips, Vector3(-hip, -0.03, 0))
	leg_r = _pivot(hips, Vector3(hip, -0.03, 0))
	shin_l = _pivot(leg_l, Vector3(0, -thigh_len, 0))
	shin_r = _pivot(leg_r, Vector3(0, -thigh_len, 0))
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
	map.merge(_extra)
	_flash()
	_weapon_r = _parts.has("hand_r") and (_parts["hand_r"] as MeshBuilder).has_geometry() and not upright_r and _skel != null
	for part in _parts:
		var b: MeshBuilder = _parts[part]
		if not b.has_geometry(): continue
		# sul corpo dell'utente armi e attrezzi seguono le ossa vere, non i perni del rig
		var pivot: Node3D = _bone_holder(part) if not _bone_fix.is_empty() and part in JOINT_NAMES else map.get(part)
		if pivot == null: continue
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

static func _spike(b: MeshBuilder, key: String, at: Vector3, dir: Vector3, length: float, radius: float, col: Color, segments: int = 5) -> void:
	b.rod(key, at, at + dir.normalized() * length, radius, 0.0, col, segments)

## Bruto del Varco: un orco curvo e massiccio, spalle enormi, braccia fino alle ginocchia,
## zanne dal basso e una mazza ferrata. Si muove con le sue pose (_animate_heavy).
func _build_brute(tint: Color) -> void:
	_build_rig({"scale": 1.62, "shoulder": 0.36, "hip": 0.17, "thigh": 0.36, "shin": 0.34, "upper_arm": 0.36, "fore_arm": 0.34, "chest": 0.5,
		"head_at": Vector3(0, 0.55, 0.1)})
	body_type = "heavy"
	attack_style = "smash"
	var skin := Color("#75825a")
	var shade := skin.darkened(0.2)
	var pale := skin.lightened(0.14)
	var hide := Color("#4a3a2a")
	var iron := Color("#6d6a66")
	var bone := Color("#e3d9c0")
	var eye := _glow("head", Color("#ffb24a"), 3.0)
	# gambe corte e grosse, piedi larghi
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var lb := _b("leg_" + side)
		lb.sphere("cloth", 0.14, Vector3(0, -0.02, 0), hide, Vector3(1.0, 1.1, 1.05), 10, 7)
		lb.rod("cloth", Vector3(0, -0.02, 0), Vector3(0, -0.36, 0), 0.135, 0.1, hide, 10)
		var sb := _b("shin_" + side)
		sb.sphere("cloth", 0.1, Vector3(0, 0, 0.01), hide.lightened(0.08), Vector3.ONE, 9, 6)
		sb.rod("cloth", Vector3(0, 0, 0), Vector3(0, -0.3, 0), 0.098, 0.085, skin, 10)
		sb.sphere("cloth", 0.1, Vector3(0, -0.33, 0.05), shade, Vector3(1.05, 0.62, 1.7), 10, 6)
		for toe in 3: sb.sphere("cloth", 0.035, Vector3((toe - 1) * 0.055, -0.36, 0.2), pale, Vector3(1, 0.8, 1.3), 6, 4)
		# strisce di pelle legate sotto il ginocchio
		sb.cylinder("cloth", 0.1, 0.1, 0.05, Vector3(0, -0.08, 0), tint.darkened(0.2), 10)
		# braccia: spalla tonda, bicipite, avambraccio più grosso del braccio, pugno
		var ab := _b("arm_" + side)
		ab.sphere("cloth", 0.165, Vector3(sx * 0.01, 0.0, 0), skin, Vector3(1.05, 1.0, 1.05), 12, 8, false, Vector3.ZERO, shade)
		ab.rod("cloth", Vector3(0, -0.02, 0), Vector3(0, -0.36, 0), 0.118, 0.092, skin, 10)
		ab.sphere("cloth", 0.1, Vector3(0, -0.17, 0.03), skin, Vector3(0.9, 1.5, 0.9), 9, 6)
		var fb := _b("fore_" + side)
		fb.sphere("cloth", 0.092, Vector3.ZERO, shade, Vector3.ONE, 9, 6)
		fb.rod("cloth", Vector3(0, 0, 0), Vector3(0, -0.34, 0), 0.09, 0.112, skin, 10)
		fb.cylinder("dull", 0.118, 0.122, 0.13, Vector3(0, -0.24, 0), hide, 10)
		fb.cylinder("dull", 0.124, 0.124, 0.025, Vector3(0, -0.19, 0), iron, 10)
		fb.cylinder("dull", 0.126, 0.126, 0.025, Vector3(0, -0.29, 0), iron, 10)
		var hb2 := _b("hand_" + side)
		hb2.sphere("cloth", 0.105, Vector3(0, -0.07, 0.01), shade, Vector3(1.0, 1.05, 1.15), 10, 7)
		for f in 4: hb2.sphere("cloth", 0.034, Vector3((f - 1.5) * 0.05, -0.15, 0.05), skin, Vector3(1, 1.1, 1), 6, 4)
	# bacino, gonnellino di pelli e cintura con la fibbia d'osso
	var hb := _b("hips")
	hb.sphere("cloth", 0.2, Vector3(0, 0.0, 0), hide, Vector3(1.3, 0.85, 1.05), 12, 7)
	hb.cylinder("dull", 0.25, 0.25, 0.07, Vector3(0, 0.1, 0), Color("#2e2118"), 12, Vector3.ZERO, false)
	_cloth_panel(hb, 0.3, 0.24, 0.42, Vector3(0, 0.08, 0.2), tint.darkened(0.15), -0.1)
	_cloth_panel(hb, 0.34, 0.3, 0.38, Vector3(0, 0.08, -0.2), hide.darkened(0.15), 0.1)
	hb.sphere("dull", 0.05, Vector3(0, 0.1, 0.25), bone, Vector3(1, 1.1, 0.5), 8, 5)
	# busto a botte: pancia, torace largo, gobba tra le spalle
	var tb := _b("spine")
	tb.sphere("cloth", 0.27, Vector3(0, 0.14, 0.04), skin, Vector3(1.12, 0.95, 1.0), 14, 9, false, Vector3.ZERO, pale)
	tb.sphere("cloth", 0.3, Vector3(0, 0.36, 0.0), skin, Vector3(1.32, 0.9, 0.98), 14, 9, false, Vector3.ZERO, shade)
	tb.sphere("cloth", 0.2, Vector3(0, 0.53, -0.07), shade, Vector3(1.6, 0.75, 1.0), 12, 7)
	for sx in [-1.0, 1.0]: tb.sphere("cloth", 0.13, Vector3(sx * 0.15, 0.4, 0.2), pale, Vector3(1.15, 0.85, 0.6), 10, 6)
	# tracolla nel colore della banda e spallaccio di ferro con le punte
	tb.rod("cloth", Vector3(-0.33, 0.58, 0.06), Vector3(0.3, 0.1, 0.24), 0.04, 0.04, tint, 6)
	tb.rod("cloth", Vector3(-0.33, 0.58, -0.06), Vector3(0.3, 0.1, -0.24), 0.04, 0.04, tint.darkened(0.15), 6)
	tb.sphere("dull", 0.2, Vector3(-0.4, 0.56, 0), iron, Vector3(1.0, 0.7, 1.0), 10, 6, true)
	for k in 3: _spike(tb, "dull", Vector3(-0.4 + (k - 1) * 0.1, 0.66, (k - 1) * 0.03), Vector3(-0.3 + (k - 1) * 0.3, 1, 0), 0.14, 0.035, bone)
	# segni di guerra sul braccio libero
	for k in 2: _b("arm_r").cylinder("fine", 0.115 - k * 0.006, 0.112 - k * 0.006, 0.025, Vector3(0, -0.2 - k * 0.06, 0), tint.lightened(0.1), 10, Vector3.ZERO, false)
	# testa bassa tra le spalle: fronte sfuggente, mascella larga, zanne, occhi accesi
	var hd := _b("head")
	hd.sphere("cloth", 0.135, Vector3(0, 0.1, 0.0), skin, Vector3(1.0, 0.95, 1.08), 12, 8)
	hd.sphere("cloth", 0.125, Vector3(0, 0.02, 0.05), shade, Vector3(1.2, 0.62, 1.05), 12, 7)
	hd.box("cloth", Vector3(0.21, 0.04, 0.06), Vector3(0, 0.13, 0.12), shade, Vector3(0.2, 0, 0))
	hd.sphere("cloth", 0.04, Vector3(0, 0.075, 0.15), pale, Vector3(1.2, 0.8, 0.9), 7, 5)
	for sx in [-1.0, 1.0]:
		hd.sphere(eye, 0.018, Vector3(sx * 0.055, 0.105, 0.13), Color.WHITE, Vector3(1.3, 0.7, 0.6), 7, 4)
		_spike(hd, "dull", Vector3(sx * 0.075, 0.03, 0.14), Vector3(sx * 0.12, 1, 0.12), 0.11, 0.024, bone)
		_spike(hd, "cloth", Vector3(sx * 0.12, 0.1, 0.0), Vector3(sx, 0.35, -0.3), 0.13, 0.04, skin)
	for k in 4: _spike(hd, "cloth", Vector3(0, 0.2, 0.06 - k * 0.055), Vector3(0, 1, -0.5), 0.1 - k * 0.012, 0.03, Color("#1f1c18"))
	# mazza: un tronco cerchiato di ferro con le punte, impugnata bassa
	var club := _b("hand_r")
	club.push(Transform3D(Basis(Vector3.RIGHT, 1.9), Vector3(0, -0.08, 0.03)))
	club.rod("cloth", Vector3(0, -0.14, 0), Vector3(0, 0.5, 0), 0.036, 0.05, Color("#4a3624"), 8)
	club.rod("cloth", Vector3(0, 0.48, 0), Vector3(0, 1.0, 0), 0.07, 0.125, Color("#3c2b1c"), 9)
	club.sphere("cloth", 0.125, Vector3(0, 1.0, 0), Color("#3c2b1c"), Vector3(1, 0.5, 1), 9, 5)
	for ring in 2: club.cylinder("dull", 0.1 + ring * 0.026, 0.094 + ring * 0.026, 0.045, Vector3(0, 0.62 + ring * 0.24, 0), iron, 9, Vector3.ZERO, false)
	for k in 7:
		var ang := k * 2.4
		_spike(club, "dull", Vector3(sin(ang) * 0.09, 0.6 + k * 0.058, cos(ang) * 0.09), Vector3(sin(ang), 0.15, cos(ang)), 0.1, 0.028, Color("#8d8a84"))
	club.pop()

## Guardiano di pietra: un colosso di massi con spalle larghe, avambracci enormi e il
## nucleo del Varco acceso nel petto. Crepe e cristalli nel colore del piano.
func _build_golem(tint: Color) -> void:
	_build_rig({"scale": 2.45, "shoulder": 0.5, "hip": 0.2, "thigh": 0.3, "shin": 0.3, "upper_arm": 0.36, "fore_arm": 0.4, "chest": 0.6,
		"head_at": Vector3(0, 0.66, 0.1)})
	body_type = "heavy"
	attack_style = "smash"
	var stone := Color("#6c6964")
	var dark := Color("#4b4844")
	var light := Color("#858178")
	var moss := Color("#55683a").lerp(tint, 0.25)
	var lit := tint.lightened(0.4)
	for part in ["spine", "head", "hips", "arm_l", "arm_r", "fore_l", "fore_r", "hand_l", "hand_r", "shin_l", "shin_r"]: _glow(part, lit, 1.15)
	var glow := "glow_" + lit.to_html()
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var n := 0 if side == "l" else 7
		_b("leg_" + side).rock("cloth", 0.17, Vector3(0, -0.15, 0), dark, Vector3(0.95, 1.25, 0.95), 11 + n, 0.16, false)
		var sb := _b("shin_" + side)
		sb.rock("cloth", 0.2, Vector3(0, -0.12, 0.01), stone, Vector3(1.0, 1.05, 1.05), 13 + n, 0.18, false)
		sb.rock("cloth", 0.2, Vector3(0, -0.29, 0.07), light, Vector3(1.05, 0.45, 1.5), 15 + n, 0.14, false)
		sb.box(glow, Vector3(0.02, 0.16, 0.02), Vector3(sx * 0.06, -0.1, 0.2), Color.WHITE, Vector3(0, 0, sx * 0.3))
		var ab := _b("arm_" + side)
		ab.rock("cloth", 0.27, Vector3(sx * 0.03, 0.04, 0), light, Vector3(1.1, 0.95, 1.1), 16 + n, 0.2, false)
		ab.rock("cloth", 0.15, Vector3(0, -0.22, 0), dark, Vector3(0.95, 1.3, 0.95), 17 + n, 0.16, false)
		ab.sphere("cloth", 0.12, Vector3(sx * 0.08, 0.2, -0.05), moss, Vector3(1.4, 0.45, 1.2), 8, 5)
		var fb := _b("fore_" + side)
		fb.rock("cloth", 0.22, Vector3(0, -0.2, 0), stone, Vector3(1.0, 1.35, 1.05), 18 + n, 0.18, false)
		fb.torus(glow, 0.17, 0.016, Vector3(0, -0.03, 0), Color.WHITE, Vector3.ZERO, 12, 5)
		var hb2 := _b("hand_" + side)
		hb2.rock("cloth", 0.22, Vector3(0, -0.1, 0.02), light, Vector3(1.05, 1.0, 1.15), 20 + n, 0.2, false)
		for f in 3: hb2.rock("cloth", 0.08, Vector3((f - 1) * 0.12, -0.27, 0.08), dark, Vector3(1, 1.1, 1), 30 + f + n, 0.15, false)
		# cristalli del Varco che spuntano dalle spalle
		for k in 3: _spike(ab, glow, Vector3(sx * (0.05 + k * 0.07), 0.2, -0.08 + k * 0.05), Vector3(sx * (0.2 + k * 0.25), 1, -0.25 + k * 0.1), 0.3 - k * 0.07, 0.055 - k * 0.008, Color.WHITE, 5)
	_b("hips").rock("cloth", 0.27, Vector3(0, 0.0, 0), dark, Vector3(1.25, 0.7, 0.95), 22, 0.18, false)
	var tb := _b("spine")
	tb.rock("cloth", 0.24, Vector3(0, 0.14, 0), stone, Vector3(1.1, 0.8, 0.9), 40, 0.16, false)
	tb.rock("cloth", 0.44, Vector3(0, 0.46, -0.02), stone, Vector3(1.3, 0.85, 0.82), 23, 0.2, false)
	tb.rock("cloth", 0.26, Vector3(0, 0.7, -0.14), dark, Vector3(1.6, 0.6, 0.9), 24, 0.2, false)
	for sx in [-1.0, 1.0]: tb.rock("cloth", 0.2, Vector3(sx * 0.2, 0.52, 0.2), light, Vector3(1.0, 0.85, 0.6), 41 if sx < 0.0 else 42, 0.14, false)
	# nucleo: una cavità scura col cuore acceso e le crepe che ne escono
	tb.sphere("fine", 0.11, Vector3(0, 0.4, 0.33), Color("#1c1a18"), Vector3(1, 1.15, 0.45), 10, 6)
	tb.sphere(glow, 0.075, Vector3(0, 0.4, 0.36), Color.WHITE, Vector3(1, 1.2, 0.6), 10, 6)
	for k in 6:
		var ang := k * 1.05 + 0.3
		var from := Vector3(cos(ang) * 0.1, 0.4 + sin(ang) * 0.11, 0.36)
		var to := Vector3(cos(ang) * (0.26 + 0.06 * (k % 2)), 0.4 + sin(ang) * (0.24 + 0.05 * ((k + 1) % 2)), 0.33 - 0.03 * absf(cos(ang)))
		tb.rod(glow, from, to, 0.014, 0.004, Color.WHITE, 4)
	tb.sphere("cloth", 0.16, Vector3(0.12, 0.84, -0.1), moss, Vector3(1.6, 0.4, 1.2), 8, 5)
	for k in 4: _spike(tb, glow, Vector3(-0.2 + k * 0.13, 0.8, -0.28), Vector3(-0.15 + k * 0.1, 1, -0.7), 0.22 + 0.1 * (k % 2), 0.05, Color.WHITE, 5)
	# testa piccola incassata: una fessura di luce al posto degli occhi
	var hd := _b("head")
	hd.rock("cloth", 0.16, Vector3(0, 0.1, 0), light, Vector3(1.1, 0.95, 1.0), 25, 0.16, false)
	hd.rock("cloth", 0.13, Vector3(0, 0.02, 0.05), dark, Vector3(1.15, 0.5, 0.95), 26, 0.12, false)
	hd.box("fine", Vector3(0.2, 0.05, 0.03), Vector3(0, 0.11, 0.145), Color("#1c1a18"))
	for sx in [-1.0, 1.0]: hd.box(glow, Vector3(0.065, 0.026, 0.02), Vector3(sx * 0.05, 0.11, 0.158), Color.WHITE, Vector3(0, 0, -sx * 0.18))
	hd.rock("cloth", 0.09, Vector3(0, 0.23, -0.02), stone, Vector3(1.3, 0.6, 1.1), 27, 0.2, false)

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
	# il modello dell'utente è un uomo: le donne con lo stesso vestito restano dal kit
	var model := _user_model(outfit, role)
	if not fem and not model.is_empty() and _build_user_body(look, role, rarity, outfit, model, prop): return
	# i nani dei ritratti sono bassi davvero; gli altri restano entro pochi centimetri
	var height := 0.84 if look.get("dwarf", false) else clampf(float(look.get("height", 1.0)), 0.93, 1.07)
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

## Corpo 3D fatto dall'utente (assets/characters/user/<vestito>.glb, preparato da
## tools/character_kit/import_user_model.py): colori dipinti nella texture e scheletro
## con gli stessi nomi del kit, ma in posa a T. Le animazioni restano quelle di tutti:
## ogni osso riceve la rotazione del suo perno corretta da _bone_fix.
func _build_user_body(look: Dictionary, role: String, rarity: int, outfit: String, model: String, prop: String) -> bool:
	var inst := CharacterKitScript.user_body(model)
	if inst == null: return false
	var found := inst.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		inst.free()
		return false
	var height := clampf(float(look.get("height", 1.0)), 0.95, 1.05)
	_build_rig({"scale": height, "shoulder": 0.22, "hip": 0.11})
	var skel := found[0] as Skeleton3D
	skel.get_parent().remove_child(skel)
	inst.free()
	skel.name = "UserSkeleton"
	skel.transform = Transform3D.IDENTITY
	rig.add_child(skel)
	_skel = skel
	_bone_ids = PackedInt32Array()
	for j in JOINT_NAMES: _bone_ids.append(skel.find_bone(j))
	_user_rest_fix()
	var fit: Dictionary = user_hair_fit.get(model, {})
	for node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := _painted_material(mi.mesh.surface_get_material(s))
			if fit.get("recolor", false) and mat is ShaderMaterial:
				# capelli dipinti col colore dell'eroe: materiale suo (la texture resta condivisa)
				mat = mat.duplicate()
				mat.set_shader_parameter("hair_recolor", 1.0)
				mat.set_shader_parameter("hair_color", look.get("hair", Color("#3a2a20")))
			mi.set_surface_override_material(s, mat)
		mi.material_overlay = _flash()
		_meshes.append(mi)
	_user_hair(look, model, CharacterKitScript.palette(look, outfit, rarity))
	# copricapo e tratti del ritratto anche sul modello dell'utente, adattati alla sua testa
	var head_b := _b("head")
	head_b.push(Transform3D(Basis.from_scale(fit.get("scale", Vector3(0.84, 0.9, 0.74))), fit.get("pos", Vector3(0.0, 0.001, 0.01))))
	_portrait_details(head_b, look)
	head_b.pop()
	if role == "Villager":
		attack_style = "melee"
	elif not prop.is_empty():
		_prop(prop, look)
	else:
		_class_weapon(role, look)
	_finish()
	return true

## Modelli dell'utente per vestito e classe: la Guardia col tabarro bianco va al
## Guardiano (scudo) e alle guardie cittadine, il Guerriero (foglio "turntable") ad
## Avanguardia e Lanciere. Se un modello manca si usa quello del vestito, poi il kit.
const USER_MODELS := {"guard": {"Vanguard": "warrior", "Lancer": "warrior"}}

static func _user_model(outfit: String, role: String) -> String:
	var name: String = USER_MODELS.get(outfit, {}).get(role, outfit)
	if CharacterKitScript.has_user_body(name): return name
	return outfit if CharacterKitScript.has_user_body(outfit) else ""

## Capelli dei modelli dell'utente. La Guardia è calva: si mettono i capelli del kit
## (taglio e colore dell'eroe) nello spazio dell'osso della testa, adattati alla sua
## testa più piccola e schiacciata davanti-dietro. Il Guerriero ha i capelli dipinti
## come nel foglio: si tingono col colore dell'eroe ("recolor"), il taglio resta il suo.
static var user_hair_fit := {
	"guard": {"pos": Vector3(0.0, 0.001, 0.01), "scale": Vector3(0.84, 0.9, 0.68)},
	"warrior": {"recolor": true},
}

## Capelli dell'eroe (stesso taglio e colore di sempre) sul modello dell'utente.
func _user_hair(look: Dictionary, model: String, pal: Array) -> void:
	var kind := _hair_under(look)
	var fit: Dictionary = user_hair_fit.get(model, {})
	if kind == "none" or not fit.has("scale"): return
	var mesh := CharacterKitScript.part("hair_" + kind)
	var holder := _bone_holder("head")
	if mesh == null or holder == null: return
	var place := Node3D.new()
	place.name = "UserHair"
	place.position = fit.pos
	place.scale = fit.scale
	holder.add_child(place)
	var hair_col: Color = look.get("hair", Color("#3a2a20"))
	var hm := ShaderMaterial.new()
	hm.shader = HairShader
	hm.set_shader_parameter("hair_color", hair_col)
	hm.set_shader_parameter("tie_color", pal[CharacterKitScript.ACCENT] as Color)
	hm.next_pass = _kit_line(hair_col)
	var mi := MeshInstance3D.new()
	mi.name = "Hair"
	mi.mesh = mesh
	mi.material_override = hm
	mi.material_overlay = _flash()
	place.add_child(mi)
	_meshes.append(mi)

## Dalla posa a T alla posa del rig: braccia giù (aperte di USER_ARM_OPEN), la mano
## segue l'avambraccio (non ha figli). Le gambe restano come nel modello (un po'
## aperte, come nel foglio): raddrizzarle stirava il tabarro tra le gambe.
func _user_rest_fix() -> void:
	var rest := {}
	for i in JOINT_NAMES.size():
		rest[JOINT_NAMES[i]] = _skel.get_bone_rest(_bone_ids[i]).origin if _bone_ids[i] >= 0 else Vector3.ZERO
	var own := {}
	for side in ["l", "r"]:
		var down := _user_down(side)
		own["arm_" + side] = _arc(rest["fore_" + side], down)
		own["fore_" + side] = _arc(rest["hand_" + side], down)
		own["hand_" + side] = own["fore_" + side]
	var parent := {"arm_l": "spine", "arm_r": "spine", "fore_l": "arm_l", "fore_r": "arm_r", "hand_l": "fore_l",
		"hand_r": "fore_r", "leg_l": "hips", "leg_r": "hips", "shin_l": "leg_l", "shin_r": "leg_r", "spine": "hips", "head": "spine"}
	_bone_fix = []
	for j in JOINT_NAMES:
		var up: Quaternion = own.get(parent.get(j, ""), Quaternion.IDENTITY)
		_bone_fix.append([up.inverse(), own.get(j, Quaternion.IDENTITY)])
	# il bacino del modello è la sua altezza da fermo: passo e seduta restano giusti
	hip_height = (rest["hips"] as Vector3).y
	hips.position = Vector3(0, hip_height, 0)

func _user_down(side: String) -> Vector3:
	var sx := -1.0 if side == "l" else 1.0
	return Vector3(sx * sin(USER_ARM_OPEN), -cos(USER_ARM_OPEN), 0.0)

static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.length() < 0.001: return Quaternion.IDENTITY
	return Quaternion(from.normalized(), to.normalized())

## Punto d'attacco sull'osso vero del corpo dell'utente: segue la mano (o l'avambraccio,
## la testa...) del modello, con gli assi del perno del rig come se l'arto pendesse
## lungo il braccio aperto. Così spada e scudo restano in mano.
func _bone_holder(part: String) -> Node3D:
	var i := JOINT_NAMES.find(part)
	if _skel == null or i < 0 or _bone_ids[i] < 0: return null
	var att := BoneAttachment3D.new()
	att.name = "Bone_" + part
	_skel.add_child(att)
	att.bone_name = part
	var holder := Node3D.new()
	holder.name = "Hold_" + part
	var tilt := Quaternion.IDENTITY
	if part.begins_with("arm_") or part.begins_with("fore_") or part.begins_with("hand_"):
		tilt = Quaternion(Vector3.DOWN, _user_down(part.right(1)))
	holder.quaternion = (_bone_fix[i][1] as Quaternion).inverse() * tilt
	if part.begins_with("fore_"):
		# il braccio del modello è più largo di quello del kit (spallacci): lo scudo più in fuori
		holder.position = holder.quaternion * Vector3(-0.05 if part.ends_with("l") else 0.05, 0.0, 0.0)
	att.add_child(holder)
	return holder

## Materiale dipinto: la texture del modello con una luce morbida (painted_model.gdshader).
func _painted_material(src: Material) -> Material:
	var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
	if tex == null: return src
	if not _painted_cache.has(tex):
		var m := ShaderMaterial.new()
		m.shader = PaintedShader
		m.set_shader_parameter("albedo_tex", tex)
		# contorno scuro come gli altri personaggi, altrimenti da lontano sembra sbiadito
		var line := ShaderMaterial.new()
		line.shader = PaintedOutlineShader
		m.next_pass = line
		_painted_cache[tex] = m
	return _painted_cache[tex]

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
		_head_kit.position = Vector3(0.0, -0.01, 0.004)
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
	var hair_kind := _hair_under(look)
	if hair_kind != "none":
		var hair_mi := _kit_piece("hair_" + hair_kind, hm)
		# sotto fazzoletti e cappelli i capelli si schiacciano un po', così non bucano la stoffa
		if hair_mi != null and _covers_hair(look): hair_mi.scale = HAIR_PRESSED
	var beard := int(look.get("beard", 0))
	if beard >= 2:
		_kit_piece("beard_short" if beard >= 3 or int(look.get("face", 1)) != 0 else "beard_goatee", _kit_material(_kit_pal(pal, CharacterKitScript.DARK, hair_col.darkened(0.08))))
	_portrait_details(_b("head"), look)
	if look.get("glasses", false):
		# niente contorno: ingrosserebbe la montatura sottile
		var gm := _kit_material(_kit_pal(pal, CharacterKitScript.DARK, Color("#3a2c24")))
		gm.next_pass = null
		_kit_piece("glasses", gm)
	if outfit == "villager" and str(look.get("portrait", "")).is_empty() and int(look.get("seed", 0)) % 3 == 0 and str(look.get("hair_kind", "")) in ["crop", "short", "bun", "tied_back"]:
		_kit_piece("headband", _kit_material(_kit_pal(pal, CharacterKitScript.LIGHT, Color("#e9e2d2"))))

const HAIR_PRESSED := Vector3(0.97, 0.92, 0.97)

func _covers_hair(look: Dictionary) -> bool:
	return str(look.get("headwear", "")) in ["kerchief", "bandana", "hat", "hood", "veil"]

## Taglio dei capelli sotto il copricapo: sotto cappelli, fazzoletti e cappucci i tagli
## gonfi bucherebbero la stoffa, quindi si usa il loro parente più aderente; i capelli
## lunghi e le trecce restano e spuntano da sotto, come nei ritratti.
func _hair_under(look: Dictionary) -> String:
	var kind := str(look.get("hair_kind", "short"))
	if kind == "none" or CharacterKitScript.part("hair_" + kind) == null: return "none" if kind == "none" else "short"
	var wear := str(look.get("headwear", ""))
	if not wear in ["kerchief", "bandana", "hat", "hood", "veil"]: return kind
	if wear == "hood" or wear == "veil": return {"messy": "short", "wavy": "short", "layered": "medium", "bun": "tied_back"}.get(kind, kind)
	return {"messy": "crop", "wavy": "crop", "short": "crop", "slicked": "crop", "layered": "bob", "medium": "bob", "bun": "tied_back"}.get(kind, kind)

## Tutto ciò che nel ritratto dipinto si porta in testa o sul viso, più orecchie da elfo,
## tratti da uomo-bestia e barba lunga: il personaggio 3D si riconosce dall'immagine
## (richiesta del proprietario, 2026-11-12). Misure nello spazio della testa del kit:
## cranio da y 0,01 a 0,27, largo ±0,108, viso verso +z (0,09).
func _portrait_details(b: MeshBuilder, look: Dictionary) -> void:
	var skin: Color = look.get("skin", Color("#f1d2b6"))
	var hair: Color = look.get("hair", Color("#3a2a20"))
	# ingombro dei capelli che stanno sotto: fazzoletti e cappelli gli stanno attorno, senza buchi
	var hair_mesh := CharacterKitScript.part("hair_" + _hair_under(look))
	var box := hair_mesh.get_aabb() if hair_mesh != null else AABB(Vector3(-0.108, 0.008, -0.121), Vector3(0.216, 0.264, 0.212))
	if hair_mesh != null and _covers_hair(look):
		box = AABB(box.position * HAIR_PRESSED, box.size * HAIR_PRESSED)
	var half := maxf(0.118, maxf(-box.position.x, box.position.x + box.size.x))
	var top := maxf(0.272, box.position.y + box.size.y)
	var front := maxf(0.095, box.position.z + box.size.z)
	var back := minf(-0.125, box.position.z)
	var mid_z := (front + back) * 0.5
	var deep := (front - back) * 0.5
	if look.get("elf", false):
		for sx in [-1.0, 1.0]:
			b.rod("cloth", Vector3(sx * 0.1, 0.135, -0.012), Vector3(sx * 0.19, 0.218, -0.05), 0.026, 0.003, skin.darkened(0.04), 6)
	match str(look.get("beast", "")):
		"feline":
			for sx in [-1.0, 1.0]:
				b.rod("cloth", Vector3(sx * 0.062, 0.235, -0.02), Vector3(sx * 0.098, 0.335, -0.04), 0.042, 0.004, skin.darkened(0.12), 6)
			b.sphere("cloth", 0.05, Vector3(0, 0.098, 0.082), skin.lightened(0.12), Vector3(1.15, 0.78, 0.95), 8, 5)
			b.sphere("cloth", 0.014, Vector3(0, 0.112, 0.128), Color("#3a2a2a"), Vector3(1.2, 0.8, 0.8), 6, 4)
			b.sphere("cloth", 0.13, Vector3(0, 0.13, -0.05), skin.darkened(0.08), Vector3(1.12, 1.15, 0.9), 10, 7)
		"lizard":
			b.sphere("cloth", 0.066, Vector3(0, 0.1, 0.092), skin, Vector3(0.95, 0.7, 1.35), 8, 5)
			for i in 4:
				b.rod("cloth", Vector3(0, 0.262 - i * 0.012, 0.02 - i * 0.05), Vector3(0, 0.325 - i * 0.022, -0.012 - i * 0.055), 0.018, 0.002, skin.darkened(0.25), 5)
			for sx in [-1.0, 1.0]: b.rod("cloth", Vector3(sx * 0.07, 0.24, -0.04), Vector3(sx * 0.12, 0.31, -0.11), 0.016, 0.003, Color("#d9cdb0"), 5)
		"bull":
			for sx in [-1.0, 1.0]:
				b.rod("cloth", Vector3(sx * 0.08, 0.235, 0.0), Vector3(sx * 0.2, 0.275, 0.02), 0.03, 0.02, Color("#d9cdb0"), 6)
				b.rod("cloth", Vector3(sx * 0.2, 0.275, 0.02), Vector3(sx * 0.235, 0.345, 0.045), 0.02, 0.004, Color("#d9cdb0"), 6)
			b.sphere("cloth", 0.06, Vector3(0, 0.088, 0.088), skin.lightened(0.1), Vector3(1.15, 0.82, 0.95), 8, 5)
	if int(look.get("beard", 0)) >= 3:
		# barba lunga da nano o da vecchio mago: scende sul petto, con i baffi
		var bc := hair.darkened(0.06)
		b.sphere("cloth", 0.078, Vector3(0, 0.03, 0.058), bc, Vector3(1.12, 1.05, 0.7), 10, 7)
		b.sphere("cloth", 0.056, Vector3(0, -0.06, 0.066), bc.darkened(0.07), Vector3(0.95, 1.6, 0.6), 8, 6)
		b.sphere("cloth", 0.03, Vector3(0, -0.15, 0.07), bc.darkened(0.12), Vector3(0.9, 1.4, 0.7), 6, 5)
		for sx in [-1.0, 1.0]: b.rod("cloth", Vector3(sx * 0.008, 0.094, 0.103), Vector3(sx * 0.07, 0.07, 0.085), 0.018, 0.008, bc.lightened(0.06), 5)
	var col: Color = look.get("head_color", Color("#6b4a2e"))
	var gold := Color("#d9b65a")
	match str(look.get("headwear", "")):
		"kerchief":
			# fazzoletto annodato dietro la nuca: copre la testa dalla fronte in su
			var kr := half + 0.012
			b.sphere("cloth", kr, Vector3(0, 0.186, mid_z), col, Vector3(1.0, (top + 0.03 - 0.186) / kr, (deep + 0.014) / kr), 14, 8, true)
			b.sphere("cloth", kr, Vector3(0, 0.186, mid_z), col.darkened(0.07), Vector3(1.03, 0.16, (deep + 0.016) / kr), 14, 6)
			b.sphere("cloth", 0.034, Vector3(0, 0.15, back - 0.02), col.darkened(0.05), Vector3(1.4, 0.9, 0.9), 6, 4)
			for sx in [-1.0, 1.0]: b.rod("cloth", Vector3(sx * 0.012, 0.14, back - 0.02), Vector3(sx * 0.06, 0.04, back - 0.035), 0.024, 0.006, col, 5)
		"bandana":
			# bandana stretta sulla fronte, nodo di lato
			var br := half + 0.008
			b.sphere("cloth", br, Vector3(0, 0.198, mid_z), col, Vector3(1.0, (top + 0.026 - 0.198) / br, (deep + 0.01) / br), 14, 8, true)
			b.sphere("cloth", br, Vector3(0, 0.2, mid_z), col.darkened(0.12), Vector3(1.03, 0.15, (deep + 0.012) / br), 14, 6)
			b.sphere("cloth", 0.028, Vector3(half * 0.8, 0.185, back + 0.03), col.darkened(0.05), Vector3.ONE, 6, 4)
			b.rod("cloth", Vector3(half * 0.8, 0.18, back + 0.025), Vector3(half * 0.8 + 0.04, 0.07, back - 0.01), 0.02, 0.005, col, 5)
		"hood":
			_cloth_shell(b, col, half + 0.016, top, mid_z, deep)
		"veil":
			# velo: calotta chiara con il bordo d'oro, scende dietro e ai lati fino alle spalle
			_cloth_shell(b, col, half + 0.01, top, mid_z, deep)
			b.sphere("metal", half + 0.012, Vector3(0, 0.196, mid_z), gold, Vector3(1.0, 0.07, (deep + 0.014) / (half + 0.012)), 14, 6)
		"goggles":
			var leather := Color("#5a3d28")
			b.torus("cloth", 0.134, 0.013, Vector3(0, 0.215, -0.022), leather, Vector3(0.14, 0, 0), 16, 5)
			for sx in [-1.0, 1.0]:
				b.cylinder("metal", 0.034, 0.034, 0.03, Vector3(sx * 0.046, 0.236, 0.108), Color("#b08d4a"), 10, Vector3(PI * 0.5 - 0.25, 0, 0))
				b.cylinder("dull", 0.026, 0.026, 0.034, Vector3(sx * 0.046, 0.237, 0.11), Color("#5d7d86"), 10, Vector3(PI * 0.5 - 0.25, 0, 0))
		"hat":
			# il cappello si alza quanto serve per stare sopra i capelli
			b.push(Transform3D(Basis.from_scale(Vector3.ONE * clampf((half + 0.012) / 0.15, 1.0, 1.25)), Vector3(0, maxf(0.0, top - 0.288) * 0.6, 0)))
			_hat(b, str(look.get("hat", "beret")), col)
			b.pop()
		"circlet":
			b.torus("metal", 0.136, 0.007, Vector3(0, 0.218, -0.02), col, Vector3(0.16, 0, 0), 18, 5)
			b.sphere("metal", 0.014, Vector3(0, 0.2, 0.113), col.lightened(0.15), Vector3(1, 1.2, 0.7), 6, 4)
			for sx in [-1.0, 1.0]: b.sphere("metal", 0.011, Vector3(sx * 0.12, 0.2, 0.03), col.lightened(0.1), Vector3.ONE, 6, 4)
		"patch":
			if col.get_luminance() > 0.6:
				# benda chiara sugli occhi
				b.cylinder("cloth", 0.116, 0.116, 0.04, Vector3(0, 0.148, -0.012), col, 16, Vector3.ZERO, false)
			else:
				b.sphere("cloth", 0.03, Vector3(0.043, 0.146, 0.092), col, Vector3(1.0, 0.85, 0.45), 8, 5)
				b.torus("cloth", 0.118, 0.005, Vector3(0, 0.165, -0.014), col, Vector3(0.0, 0, -0.3), 18, 4)
		"flowers":
			for k in 3:
				var at := Vector3(-0.118 + k * 0.012, 0.215 - k * 0.04, 0.045 - k * 0.03)
				b.sphere("cloth", 0.024, at, col, Vector3(1.0, 0.55, 1.0), 6, 4)
				b.sphere("cloth", 0.009, at + Vector3(-0.012, 0.004, 0.006), Color("#e2b84f"), Vector3.ONE, 5, 3)

## Cappuccio o velo: calotta attorno ai capelli, drappo dietro la nuca e due lembi ai lati del viso.
func _cloth_shell(b: MeshBuilder, col: Color, radius: float, top: float, mid_z: float, deep: float) -> void:
	b.sphere("cloth", radius, Vector3(0, 0.172, mid_z), col, Vector3(1.0, (top + 0.032 - 0.172) / radius, (deep + 0.016) / radius), 14, 8, true)
	b.sphere("cloth", radius, Vector3(0, 0.06, mid_z - 0.05), col.darkened(0.06), Vector3(1.04, 1.5, (deep - 0.02) / radius), 12, 7)
	for sx in [-1.0, 1.0]:
		b.sphere("cloth", 0.062, Vector3(sx * (radius - 0.03), 0.085, 0.0), col.darkened(0.03), Vector3(0.5, 1.8, 1.05), 8, 6)

## Cappelli dei ritratti: basco, paglia, falda larga, tricorno, punta, pelliccia, cuoco, visiera.
func _hat(b: MeshBuilder, kind: String, col: Color) -> void:
	var band := col.darkened(0.25)
	match kind:
		"straw":
			b.cylinder("cloth", 0.3, 0.31, 0.014, Vector3(0, 0.236, -0.02), col, 18, Vector3(0.1, 0, 0))
			b.cylinder("cloth", 0.115, 0.135, 0.1, Vector3(0, 0.285, -0.025), col.lightened(0.05), 12, Vector3(0.1, 0, 0))
			b.cylinder("cloth", 0.137, 0.137, 0.022, Vector3(0, 0.25, -0.022), Color("#6b3a2a"), 12, Vector3(0.1, 0, 0))
		"brim":
			b.cylinder("cloth", 0.27, 0.28, 0.016, Vector3(0, 0.238, -0.02), col, 18, Vector3(0.14, 0, 0.06))
			b.cylinder("cloth", 0.11, 0.138, 0.12, Vector3(0, 0.295, -0.03), col.lightened(0.04), 12, Vector3(0.14, 0, 0.06))
			b.cylinder("cloth", 0.14, 0.14, 0.022, Vector3(0, 0.252, -0.025), band, 12, Vector3(0.14, 0, 0.06))
			b.rod("cloth", Vector3(0.11, 0.26, -0.06), Vector3(0.2, 0.4, -0.2), 0.022, 0.004, Color("#a33b3b"), 5)
		"tricorn":
			b.extrude("cloth", PackedVector2Array([Vector2(0, 0.3), Vector2(0.27, -0.17), Vector2(-0.27, -0.17)]), 0.228, 0.262, col, true, true, Vector3(0, 0, -0.02))
			b.cylinder("cloth", 0.125, 0.142, 0.085, Vector3(0, 0.295, -0.03), col.lightened(0.04), 12)
			b.extrude("cloth", PackedVector2Array([Vector2(0, 0.31), Vector2(0.28, -0.18), Vector2(-0.28, -0.18)]), 0.262, 0.272, Color("#d9b65a"), true, false, Vector3(0, 0, -0.02))
		"witch":
			b.cylinder("cloth", 0.27, 0.28, 0.016, Vector3(0, 0.238, -0.02), col, 18, Vector3(0.12, 0, 0))
			b.cylinder("cloth", 0.045, 0.14, 0.2, Vector3(0, 0.34, -0.035), col.lightened(0.04), 12, Vector3(-0.1, 0, 0))
			b.cylinder("cloth", 0.0, 0.047, 0.13, Vector3(0, 0.485, -0.075), col.lightened(0.08), 10, Vector3(-0.55, 0, 0))
			b.cylinder("cloth", 0.142, 0.142, 0.022, Vector3(0, 0.252, -0.024), band, 12, Vector3(0.12, 0, 0))
		"fur":
			b.rock("cloth", 0.17, Vector3(0, 0.25, -0.025), col.lightened(0.06), Vector3(1.04, 0.62, 1.06), 31, 0.1, false)
			b.torus("cloth", 0.15, 0.03, Vector3(0, 0.215, -0.022), col.lightened(0.16), Vector3(0.08, 0, 0), 16, 6)
		"chef":
			b.cylinder("cloth", 0.14, 0.14, 0.055, Vector3(0, 0.235, -0.022), col.darkened(0.04), 12, Vector3(0.08, 0, 0))
			b.sphere("cloth", 0.165, Vector3(0, 0.305, -0.03), col, Vector3(1.05, 0.62, 1.05), 12, 7)
		"cap":
			b.cylinder("cloth", 0.16, 0.14, 0.07, Vector3(0, 0.262, -0.025), col, 14, Vector3(0.1, 0, 0))
			b.cylinder("cloth", 0.141, 0.141, 0.024, Vector3(0, 0.225, -0.022), Color("#d9b65a"), 14, Vector3(0.1, 0, 0))
			b.cylinder("cloth", 0.11, 0.11, 0.01, Vector3(0, 0.205, 0.07), band, 12, Vector3(0.3, 0, 0), true, 0, PI, true, 0.0)
		_:
			# basco o berretto morbido, calato da una parte
			b.sphere("cloth", 0.168, Vector3(0.018, 0.25, -0.03), col, Vector3(1.08, 0.5, 1.1), 12, 7, false, Vector3(0, 0, -0.16))
			b.torus("cloth", 0.14, 0.014, Vector3(0, 0.212, -0.022), band, Vector3(0.1, 0, 0), 16, 5)

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
	attack_style = "bite"
	rig = Node3D.new()
	rig.scale = Vector3.ONE * METER * 1.15
	add_child(rig)
	var fur := Color("#3d3a40").lerp(tint.darkened(0.45), 0.22)
	var belly := fur.lightened(0.22)
	var dark := fur.darkened(0.35)
	var lit := tint.lightened(0.3)
	for part in ["spine", "head", "hips"]: _glow(part, lit, 1.15)
	var glow := "glow_" + lit.to_html()
	# groppa e torace sono due perni: correndo la schiena si flette davvero
	hips = _pivot(rig, Vector3(0, 0.6, -0.26))
	spine = _pivot(rig, Vector3(0, 0.63, 0.2))
	head = _pivot(spine, Vector3(0, 0.14, 0.27))
	var jaw := _pivot(head, Vector3(0, -0.03, 0.06))
	leg_l = _pivot(spine, Vector3(-0.105, -0.06, 0.04))
	leg_r = _pivot(spine, Vector3(0.105, -0.06, 0.04))
	shin_l = _pivot(leg_l, Vector3(0, -0.27, 0))
	shin_r = _pivot(leg_r, Vector3(0, -0.27, 0))
	legs_back = [_pivot(hips, Vector3(-0.1, -0.03, -0.02)), _pivot(hips, Vector3(0.1, -0.03, -0.02))]
	tail = _pivot(hips, Vector3(0, 0.06, -0.19))
	_extra = {"jaw": jaw, "tail2": _pivot(tail, Vector3(0, -0.1, -0.14))}
	for i in 2:
		var hock := _pivot(legs_back[i], Vector3(0, -0.22, 0.07))
		_extra["bshin_%d" % i] = hock
		_extra["bfoot_%d" % i] = _pivot(hock, Vector3(0, -0.19, -0.13))
	# groppa e vita stretta che raggiunge il torace
	var hb := _b("hips")
	hb.sphere("cloth", 0.15, Vector3(0, 0.0, 0.0), fur, Vector3(0.95, 1.0, 1.35), 14, 9, false, Vector3.ZERO, belly)
	hb.rod("cloth", Vector3(0, 0.0, 0.04), Vector3(0, 0.02, 0.36), 0.125, 0.14, fur, 12)
	# torace profondo, garrese, collo forte
	var sb := _b("spine")
	sb.sphere("cloth", 0.175, Vector3(0, -0.03, 0.0), fur, Vector3(0.95, 1.2, 1.5), 16, 10, false, Vector3.ZERO, belly)
	sb.sphere("cloth", 0.13, Vector3(0, 0.08, 0.03), fur.lightened(0.04), Vector3(1.1, 0.9, 1.35), 12, 8)
	sb.rod("cloth", Vector3(0, 0.02, 0.1), Vector3(0, 0.14, 0.28), 0.125, 0.085, fur, 12)
	sb.sphere("cloth", 0.1, Vector3(0, -0.04, 0.2), belly, Vector3(1.0, 1.2, 0.9), 10, 7)
	# criniera: ciocche che puntano indietro dal collo al garrese
	for k in 8:
		var along := k / 7.0
		var at := Vector3((k % 2 - 0.5) * 0.07, lerpf(0.21, 0.15, along), lerpf(0.24, -0.12, along))
		_spike(sb, "cloth", at, Vector3((k % 2 - 0.5) * 0.4, 0.75, -0.8), 0.14 - along * 0.04, 0.042, dark)
	# cristalli del Varco che spaccano la schiena
	_spike(sb, glow, Vector3(0.0, 0.14, -0.04), Vector3(0, 1, -0.45), 0.2, 0.034, Color.WHITE)
	_spike(sb, glow, Vector3(0.05, 0.14, 0.08), Vector3(0.3, 1, -0.3), 0.13, 0.026, Color.WHITE)
	_spike(sb, glow, Vector3(-0.045, 0.13, -0.14), Vector3(-0.3, 1, -0.5), 0.15, 0.028, Color.WHITE)
	_spike(hb, glow, Vector3(0.0, 0.12, 0.12), Vector3(0, 1, -0.6), 0.12, 0.026, Color.WHITE)
	# testa: cranio, muso lungo, orecchie, occhi accesi sotto la fronte aggrottata
	var hd := _b("head")
	hd.sphere("cloth", 0.088, Vector3(0, 0.012, 0.02), fur, Vector3(1.05, 0.95, 1.15), 14, 9, false, Vector3.ZERO, belly)
	hd.rod("cloth", Vector3(0, 0.0, 0.06), Vector3(0, -0.012, 0.245), 0.056, 0.032, fur.lightened(0.05), 10)
	hd.sphere("cloth", 0.022, Vector3(0, -0.004, 0.25), Color("#121010"), Vector3(1.2, 0.9, 1.0), 8, 6)
	for sx in [-1.0, 1.0]:
		_spike(hd, "cloth", Vector3(sx * 0.072, -0.01, 0.0), Vector3(sx * 0.8, -0.2, -0.6), 0.1, 0.04, fur)
		_spike(hd, "cloth", Vector3(sx * 0.052, 0.07, -0.015), Vector3(sx * 0.28, 1, -0.2), 0.125, 0.038, dark)
		_spike(hd, "cloth", Vector3(sx * 0.052, 0.072, -0.005), Vector3(sx * 0.28, 1, -0.2), 0.085, 0.022, Color("#6a4650"))
		hd.sphere(glow, 0.015, Vector3(sx * 0.047, 0.036, 0.088), Color.WHITE, Vector3(1.35, 0.7, 0.7), 8, 5)
		hd.rod("cloth", Vector3(sx * 0.018, 0.05, 0.105), Vector3(sx * 0.075, 0.07, 0.07), 0.014, 0.012, dark, 5)
		_spike(hd, "dull", Vector3(sx * 0.024, -0.03, 0.2), Vector3(0, -1, 0.1), 0.04, 0.009, Color("#eee6d2"))
		_spike(hd, "dull", Vector3(sx * 0.033, -0.035, 0.14), Vector3(0, -1, 0), 0.022, 0.008, Color("#eee6d2"))
	# mascella a parte: si spalanca nel morso
	var jb := _b("jaw")
	jb.rod("cloth", Vector3(0, 0, -0.02), Vector3(0, -0.012, 0.165), 0.04, 0.022, belly.darkened(0.12), 8)
	jb.box("fine", Vector3(0.035, 0.008, 0.11), Vector3(0, 0.022, 0.08), Color("#a3353a"))
	for sx in [-1.0, 1.0]: _spike(jb, "dull", Vector3(sx * 0.018, 0.005, 0.15), Vector3(0, 1, 0.1), 0.032, 0.008, Color("#eee6d2"))
	# zampe davanti: spalla, avambraccio, zampa
	for i in 2:
		var side: String = ["l", "r"][i]
		var ub := _b("leg_" + side)
		ub.sphere("cloth", 0.078, Vector3(0, -0.02, 0), fur, Vector3(0.8, 1.6, 1.2), 10, 7)
		ub.rod("cloth", Vector3(0, 0, 0), Vector3(0, -0.27, 0), 0.052, 0.038, fur, 9)
		var lb := _b("shin_" + side)
		lb.sphere("cloth", 0.04, Vector3.ZERO, fur, Vector3.ONE, 8, 5)
		lb.rod("cloth", Vector3(0, 0, 0), Vector3(0, -0.25, 0), 0.037, 0.029, dark, 8)
		lb.sphere("cloth", 0.042, Vector3(0, -0.262, 0.022), dark, Vector3(1.0, 0.6, 1.45), 9, 5)
		# zampe dietro: coscia in avanti, garretto all'indietro, metatarso a terra
		var tb := _b("back_%d" % i)
		tb.sphere("cloth", 0.1, Vector3(0, -0.05, 0.01), fur, Vector3(0.75, 1.45, 1.25), 11, 7)
		tb.rod("cloth", Vector3(0, 0, 0), Vector3(0, -0.22, 0.07), 0.078, 0.05, fur, 9)
		var kb := _b("bshin_%d" % i)
		kb.sphere("cloth", 0.05, Vector3.ZERO, fur, Vector3.ONE, 8, 5)
		kb.rod("cloth", Vector3(0, 0, 0), Vector3(0, -0.19, -0.13), 0.046, 0.03, fur, 8)
		var fb := _b("bfoot_%d" % i)
		fb.sphere("cloth", 0.032, Vector3.ZERO, dark, Vector3.ONE, 7, 5)
		fb.rod("cloth", Vector3(0, 0, 0), Vector3(0, -0.125, 0.025), 0.03, 0.027, dark, 8)
		fb.sphere("cloth", 0.042, Vector3(0, -0.135, 0.05), dark, Vector3(1.0, 0.6, 1.45), 9, 5)
	# coda folta attaccata alla groppa, in due pezzi: pende da ferma, si stende in corsa
	var t1 := _b("tail")
	t1.sphere("cloth", 0.05, Vector3(0, 0, 0.02), fur, Vector3.ONE, 8, 5)
	t1.rod("cloth", Vector3(0, 0, 0.02), Vector3(0, -0.1, -0.14), 0.044, 0.066, fur, 9)
	var t2 := _b("tail2")
	t2.sphere("cloth", 0.066, Vector3.ZERO, fur, Vector3.ONE, 9, 6)
	t2.rod("cloth", Vector3.ZERO, Vector3(0, -0.11, -0.13), 0.066, 0.07, fur, 9)
	t2.sphere("cloth", 0.07, Vector3(0, -0.11, -0.13), fur, Vector3.ONE, 9, 6)
	t2.rod("cloth", Vector3(0, -0.11, -0.13), Vector3(0, -0.2, -0.27), 0.068, 0.0, dark, 9)

# =============================================================================
# Animazione
# =============================================================================

const ATTACK_LENGTHS := {"melee": 0.55, "heavy": 0.74, "thrust": 0.52, "bow": 0.6, "cast": 0.6, "bite": 0.55, "smash": 0.95}
const GAITS := ["Walk_F", "Jog_F", "Sprint_F"]
## Velocità naturale dei clip di passo (m/s nel metro del modello): il passo segue la strada fatta, i piedi non pattinano.
const GAIT_SPEED := {"Walk_F": 1.53, "Jog_F": 2.59, "Sprint_F": 4.09}
const HIT_TIME := 0.34

func play(name_text: String) -> void:
	if name_text == "attack":
		attack_length = ATTACK_LENGTHS.get(attack_style, 0.5)
		attack_timer = attack_length
		return
	anim = name_text

func update_animation(delta: float, speed_scale: float = 1.0) -> void:
	var dt := delta * speed_scale
	phase += dt
	attack_timer = maxf(0.0, attack_timer - dt)
	_dead_t = move_toward(_dead_t, 1.0 if anim == "dead" else 0.0, dt * (2.5 if body_type == "human" else 1.25))
	_sit_t = move_toward(_sit_t, 1.0 if anim in ["sit", "rest"] else 0.0, dt * 3.0)
	_hit_t = maxf(0.0, _hit_t - dt / HIT_TIME)
	_measure_speed(delta, dt)
	if body_type == "beast": _animate_beast(dt)
	elif body_type == "heavy": _animate_heavy(dt)
	else:
		if use_clips and _sit_t <= 0.0 and Motion.ensure(): _animate_clips(dt)
		else:
			if not _clip.is_empty():
				# dai clip alle pose procedurali: si riparte da articolazioni dritte
				for joint in _joints(): joint.quaternion = Quaternion.IDENTITY
				_clip = ""
				_pose = {}
			_animate_human()
		_apply_hit()
	_sync_skeleton()

## Quanto si sta spostando il modello, in m/s del proprio metro e nel tempo di gioco.
## Chi lo muove (battaglia, base) non deve dire niente: si misura la strada fatta.
func _measure_speed(delta: float, dt: float) -> void:
	if rig == null or not is_inside_tree(): return
	var pos := global_position
	if _last_pos != Vector3.INF and dt > 0.0001:
		var unit := maxf(rig.global_transform.basis.get_scale().y, 0.001)
		var v := minf(Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / (dt * unit), 9.0)
		_speed = lerpf(_speed, v, clampf(delta * 10.0, 0.0, 1.0))
	_last_pos = pos

func move_speed() -> float:
	return gait_speed if gait_speed >= 0.0 else _speed

## Passo adatto alla velocità: [clip, ritmo]. Chi è già di corsa continua finché non rallenta davvero.
func _gait() -> Array:
	var v := move_speed()
	if v < 0.3: return ["Walk_F", 1.0]
	var running := _clip in ["Jog_F", "Sprint_F"]
	if calm or v < (2.0 if running else 2.3): return ["Walk_F", clampf(v / GAIT_SPEED.Walk_F, 0.7, 1.4)]
	if v > (3.5 if _clip == "Sprint_F" else 3.8): return ["Sprint_F", clampf(v / GAIT_SPEED.Sprint_F, 0.9, 1.3)]
	return ["Jog_F", clampf(v / GAIT_SPEED.Jog_F, 0.8, 1.45)]

## Il corpo del kit segue le articolazioni: stesse rotazioni, bacino compreso lo spostamento.
func _sync_skeleton() -> void:
	if _skel == null or _bone_ids.is_empty(): return
	var nodes := _joints()
	var fix := not _bone_fix.is_empty()
	for i in nodes.size():
		var b := _bone_ids[i]
		if b < 0: continue
		var q := (nodes[i] as Node3D).quaternion
		# corpo dell'utente: dalla posa a T dell'osso a quella del perno
		if fix: q = (_bone_fix[i][0] as Quaternion) * q * (_bone_fix[i][1] as Quaternion)
		_skel.set_bone_pose_rotation(b, q)
	if _bone_ids[0] >= 0: _skel.set_bone_pose_position(_bone_ids[0], hips.position)

## Pose dai clip: animazione base su tutto il corpo (fermo, passo, corsa, caduta).
## I colpi si sovrappongono: arco e magia dai clip, spada e lancia dalle pose
## procedurali a tutto corpo. In movimento il colpo prende solo la parte alta.
func _animate_clips(dt: float) -> void:
	if rig == null: return
	var base: String = BASE_CLIPS.get(anim, "")
	var moving := anim == "walk"
	var rate := 1.0
	if moving:
		var gait := _gait()
		base = gait[0]
		rate = gait[1]
	var procedural := base.is_empty()
	var key := ("proc:" + anim) if procedural else base
	if key != _clip:
		if _clip.is_empty() and _pose.is_empty():
			# primo clip: fase casuale, così una folla non si muove all'unisono
			_clip_t = fmod(float(get_instance_id() % 997) * 0.37, Motion.length(base)) if not base.is_empty() else 0.0
		elif moving and _clip in GAITS:
			# dal passo alla corsa senza perdere l'appoggio: stesso punto del ciclo
			_clip_t = _clip_t / Motion.length(_clip) * Motion.length(base)
		else:
			_clip_t = 0.0
		_fade_from = _pose
		_fade_t = 0.0 if not _pose.is_empty() else 1.0
		_clip = key
	_clip_t += dt * rate
	_fade_t = minf(1.0, _fade_t + dt / BLEND_TIME)
	var pose: Dictionary
	if procedural:
		for joint in _joints(): joint.quaternion = Quaternion.IDENTITY
		_animate_human()
		pose = _read_pose()
	else:
		pose = Motion.sample(base, _clip_t, base != "Death")
		if attack_timer > 0.0 and base != "Death":
			var k := 1.0 - attack_timer / attack_length
			var action: String = ATTACK_CLIPS.get(attack_style, "")
			var strike: Dictionary
			if action.is_empty():
				for joint in _joints(): joint.quaternion = Quaternion.IDENTITY
				_animate_human()
				strike = _read_pose()
			else:
				strike = Motion.sample(action, k * Motion.length(action), false)
			# il colpo entra e esce sfumando sulla posa di base: niente scatti
			var weight := smoothstep(0.0, 0.1, k) * (1.0 - smoothstep(0.8, 1.0, k))
			for joint in (Motion.UPPER if moving else Motion.UPPER + Motion.LOWER):
				pose[joint] = (pose[joint] as Quaternion).slerp(strike[joint], weight)
			if not moving: pose["@hips"] = (pose["@hips"] as Vector3).lerp(strike["@hips"], weight)
		if base in ["Jog_F", "Sprint_F"] and _weapon_r and attack_timer <= 0.0:
			# di corsa l'arma non sventola: il braccio che la porta resta raccolto lungo il fianco
			pose["arm_r"] = (pose["arm_r"] as Quaternion).slerp(Quaternion.from_euler(Vector3(0.2, 0, 0.12)), 0.7)
			pose["fore_r"] = (pose["fore_r"] as Quaternion).slerp(Quaternion.from_euler(Vector3(-0.75, 0, 0)), 0.7)
			pose["hand_r"] = Quaternion.from_euler(Vector3(0.35 if attack_style == "thrust" else 0.0, 0, 0))
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

## Piede piantato a terra: la gamba si piega quanto serve per arrivare a `forward`
## metri davanti all'anca, col bacino abbassato di `drop` (cinematica inversa a due ossa).
func _plant(leg: Node3D, shin: Node3D, forward: float, drop: float, side: float = 0.0) -> void:
	var down := maxf(0.2, thigh_len + shin_len - drop)
	var reach := clampf(sqrt(forward * forward + down * down), 0.25, (thigh_len + shin_len) * 0.999)
	var knee := acos(clampf((thigh_len * thigh_len + shin_len * shin_len - reach * reach) / (2.0 * thigh_len * shin_len), -1.0, 1.0))
	var hip := acos(clampf((thigh_len * thigh_len + reach * reach - shin_len * shin_len) / (2.0 * thigh_len * reach), -1.0, 1.0))
	leg.rotation = Vector3(-(atan2(forward, down) + hip), 0, side)
	shin.rotation = Vector3(PI - knee, 0, 0)

static func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)

static func _mix(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var out := a.duplicate()
	for key in b: out[key] = lerpf(float(a.get(key, 0.0)), float(b[key]), weight)
	return out

## Colpi a tutto corpo: carica breve, colpo col peso che avanza, chiusura e ritorno.
## Il danno arriva subito, quindi l'impatto cade presto (circa al 30%).
func _strike_pose(base: Dictionary, k: float) -> Dictionary:
	var wind: Dictionary
	var hit: Dictionary
	var t_wind := 0.17
	var t_hit := 0.31
	match attack_style:
		"heavy":
			# spadone a due mani: dall'alto dietro la testa fino a terra davanti
			t_wind = 0.2
			t_hit = 0.34
			wind = {"arm_r_x": -2.75, "elbow_r": -1.25, "arm_r_z": -0.2, "arm_l_x": -2.6, "elbow_l": -1.45, "arm_l_z": 0.5, "spine_x": -0.24, "spine_y": 0.22,
				"hips_y": 0.1, "dz": -0.07, "dy": -0.02, "foot_l": 0.12, "foot_r": -0.08, "wrist": -0.25}
			hit = {"arm_r_x": -0.8, "elbow_r": -0.3, "arm_r_z": -0.35, "arm_l_x": -0.85, "elbow_l": -0.75, "arm_l_z": 0.6, "spine_x": 0.52, "spine_y": -0.3,
				"hips_y": -0.12, "dz": 0.2, "dy": -0.17, "foot_l": 0.46, "foot_r": -0.12, "wrist": 0.5}
		"thrust":
			# affondo di lancia: braccio caricato indietro, poi passo lungo e punta in avanti
			wind = {"arm_r_x": 0.75, "elbow_r": -1.55, "arm_r_z": 0.25, "arm_l_x": -1.0, "elbow_l": -0.5, "spine_x": 0.06, "spine_y": 0.6,
				"hips_y": 0.25, "dz": -0.1, "dy": -0.06, "foot_l": 0.14, "foot_r": -0.1}
			hit = {"arm_r_x": -1.42, "elbow_r": -0.05, "arm_r_z": 0.0, "arm_l_x": 0.75, "elbow_l": -0.35, "arm_l_z": -0.3, "spine_x": 0.3, "spine_y": -0.45,
				"hips_y": -0.2, "dz": 0.36, "dy": -0.19, "foot_r": 0.62, "foot_l": -0.12}
		_:
			# fendente a una mano: spalla indietro, poi il taglio attraversa il corpo con un passo
			wind = {"arm_r_x": -2.35, "elbow_r": -1.45, "arm_r_z": 0.55, "arm_l_x": -0.75, "elbow_l": -1.0, "arm_l_z": 0.15, "spine_x": -0.1, "spine_y": 0.58,
				"hips_y": 0.2, "dz": -0.06, "dy": -0.03, "foot_r": -0.08}
			hit = {"arm_r_x": -0.95, "elbow_r": -0.18, "arm_r_z": -0.6, "arm_l_x": 0.35, "elbow_l": -0.9, "arm_l_z": -0.2, "spine_x": 0.3, "spine_y": -0.62,
				"hips_y": -0.22, "dz": 0.2, "dy": -0.11, "foot_l": 0.4, "foot_r": -0.08, "wrist": 0.45}
	wind = _mix(base, wind, 1.0)
	hit = _mix(base, hit, 1.0)
	var pose: Dictionary
	if k < t_wind: pose = _mix(base, wind, _ease_out(k / t_wind))
	elif k < t_hit:
		var s := (k - t_wind) / (t_hit - t_wind)
		pose = _mix(wind, hit, s * s)
	elif k < 0.6: pose = _mix(hit, base, 0.1 * (k - t_hit) / (0.6 - t_hit))
	else: pose = _mix(hit, base, 0.1 + 0.9 * smoothstep(0.6, 1.0, k))
	# lo sguardo resta sul bersaglio mentre il busto gira
	pose.head_y = -(float(pose.spine_y) + float(pose.hips_y)) * 0.75
	pose.head_x = -float(pose.spine_x) * 0.6
	pose.arm_a = 0.0
	# la lancia resta puntata in avanti qualunque cosa faccia il braccio
	if attack_style == "thrust":
		var level := smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.75, 1.0, k))
		pose.wrist = (-(float(pose.arm_r_x) + float(pose.elbow_r)) - 0.16) * level
		pose.arm_r_y = -(float(pose.spine_y) + float(pose.hips_y)) * level
	return pose

func _animate_human() -> void:
	if rig == null: return
	var t := phase
	var walk := anim == "walk"
	var w := t * 7.2
	var p := {"leg_a": 0.0, "knee_l": 0.04, "knee_r": 0.04, "arm_a": 0.0, "arm_l_x": 0.0, "arm_r_x": -0.12, "arm_l_z": -0.07, "arm_r_z": 0.07, "arm_r_y": 0.0,
		"elbow_l": -0.18, "elbow_r": -0.32, "bob": 0.0, "spine_x": sin(t * 1.7) * 0.015, "spine_y": 0.0, "head_x": 0.0, "head_y": 0.0,
		"wrist": 0.0, "hips_y": 0.0, "dz": 0.0, "dy": 0.0, "foot_l": 0.0, "foot_r": 0.0}
	if walk:
		p.leg_a = sin(w) * 0.55
		p.knee_l = maxf(0.0, sin(w + 1.3)) * 0.85 + 0.05
		p.knee_r = maxf(0.0, sin(w + 1.3 + PI)) * 0.85 + 0.05
		p.arm_a = sin(w) * 0.38
		p.bob = absf(sin(w)) * 0.035
		p.spine_y = sin(w) * 0.07
		p.elbow_l = -0.25 - maxf(0.0, -sin(w)) * 0.35
		p.elbow_r = -0.32 - maxf(0.0, sin(w)) * 0.3
	match anim:
		"idle":
			p.head_y = sin(t * 0.5) * 0.3 * sin(t * 0.17)
		"talk":
			p.arm_r_x = -0.5 + sin(t * 3.5) * 0.25
			p.elbow_r = -0.9 + sin(t * 4.3) * 0.25
			p.head_y = sin(t * 1.3) * 0.15
		"cheer":
			p.arm_r_x = -2.85 + sin(t * 7.0) * 0.18
			p.arm_l_x = -2.6 - sin(t * 7.0) * 0.18
			p.elbow_r = -0.25
			p.elbow_l = -0.3
			p.bob = absf(sin(t * 7.0)) * 0.05
		"train":
			var c := fmod(t, 1.3) / 1.3
			if c < 0.45:
				p.arm_r_x = lerpf(-0.4, -2.5, c / 0.45)
				p.elbow_r = lerpf(-0.4, -1.3, c / 0.45)
			elif c < 0.6:
				var k := (c - 0.45) / 0.15
				p.arm_r_x = lerpf(-2.5, -0.5, k)
				p.elbow_r = lerpf(-1.3, -0.15, k)
				p.spine_y = -0.25 * k
			else:
				p.arm_r_x = -0.5
				p.elbow_r = -0.25
			p.arm_l_x = -0.6
			p.elbow_l = -1.0
			p.leg_a = 0.0
			p.knee_l = 0.2
			p.knee_r = 0.12
		"rest":
			p.head_x = 0.35
			p.arm_l_x = -0.5
			p.arm_r_x = -0.5
			p.elbow_l = -1.0
			p.elbow_r = -1.0
	var attacking := attack_timer > 0.0
	if attacking:
		var k := 1.0 - attack_timer / attack_length
		match attack_style:
			"bow":
				p.arm_l_x = -1.5
				p.arm_l_z = -0.05
				p.elbow_l = -0.05
				p.arm_r_x = -1.45
				p.elbow_r = lerpf(-0.6, -1.9, minf(1.0, k * 2.0))
				p.arm_r_z = -0.25
				p.spine_y = 0.35
				p.head_y = -0.3
			"cast":
				var s := sin(k * PI)
				p.arm_r_x = lerpf(-0.4, -2.1, s)
				p.elbow_r = lerpf(-0.4, -0.2, s)
				p.arm_l_x = lerpf(0.0, -1.2, s)
				p.elbow_l = -0.4
				p.spine_x = -0.08 * s
			_:
				p = _strike_pose(p, k)
	# seduto
	var sit := _sit_t
	if attacking and not walk and sit <= 0.0 and attack_style not in ["bow", "cast"]:
		# colpo da fermi: il bacino avanza e si abbassa, i piedi restano piantati
		hips.position = Vector3(0, hip_height + float(p.dy), float(p.dz))
		hips.rotation = Vector3(0, float(p.hips_y), 0)
		_plant(leg_l, shin_l, float(p.foot_l) - float(p.dz), -float(p.dy))
		_plant(leg_r, shin_r, float(p.foot_r) - float(p.dz), -float(p.dy))
	else:
		hips.position = Vector3(0, lerpf(hip_height + float(p.bob), 0.52, sit), 0)
		hips.rotation = Vector3.ZERO
		leg_l.rotation = Vector3(lerpf(-float(p.leg_a), -1.5, sit), 0, 0)
		leg_r.rotation = Vector3(lerpf(float(p.leg_a), -1.45, sit), 0, 0)
		shin_l.rotation.x = lerpf(float(p.knee_l), 1.5, sit)
		shin_r.rotation.x = lerpf(float(p.knee_r), 1.45, sit)
	arm_l.rotation = Vector3(float(p.arm_l_x) + float(p.arm_a), 0, float(p.arm_l_z))
	arm_r.rotation = Vector3(float(p.arm_r_x) - float(p.arm_a), float(p.arm_r_y), float(p.arm_r_z))
	fore_l.rotation.x = float(p.elbow_l)
	fore_r.rotation.x = float(p.elbow_r)
	# chi impugna bastoni o archi li tiene dritti compensando braccio e gomito
	hand_r.rotation.x = (-(arm_r.rotation.x + float(p.elbow_r)) - (0.25 if attacking and attack_style == "cast" else 0.0)) if upright_r else float(p.wrist)
	hand_l.rotation.x = -(arm_l.rotation.x + float(p.elbow_l)) if upright_l else 0.0
	spine.rotation = Vector3(float(p.spine_x) + sit * 0.05, float(p.spine_y), 0)
	head.rotation = Vector3(float(p.head_x), float(p.head_y), 0)
	# caduto: si accascia all'indietro
	var d := _dead_t
	rig.rotation.x = -1.42 * d * d
	rig.position.y = 0.06 * d

## Colpo subito: il busto incassa all'indietro, la testa segue, poi si torna in guardia.
func _hit_amount() -> float:
	if _hit_t <= 0.0: return 0.0
	var x := 1.0 - _hit_t
	return (x / 0.18) if x < 0.18 else pow(1.0 - (x - 0.18) / 0.82, 2.0)

func _apply_hit() -> void:
	var h := _hit_amount() * (0.0 if anim == "dead" else 1.0)
	if h <= 0.0: return
	hips.position += Vector3(0, -0.03, -0.09) * h
	spine.quaternion = spine.quaternion * Quaternion(Vector3.RIGHT, -0.36 * h) * Quaternion(Vector3.UP, 0.25 * h * _hit_side)
	head.quaternion = head.quaternion * Quaternion(Vector3.RIGHT, 0.32 * h)
	arm_l.quaternion = arm_l.quaternion * Quaternion(Vector3.FORWARD, 0.25 * h)
	arm_r.quaternion = arm_r.quaternion * Quaternion(Vector3.FORWARD, -0.25 * h)

## Segugio: trotto o galoppo secondo la velocità, schiena che si flette, morso con
## balzo e mascella che scatta, sussulto ai colpi, caduta sul fianco con le zampe molli.
func _animate_beast(dt: float) -> void:
	if rig == null: return
	var t := phase
	var jaw: Node3D = _extra.get("jaw")
	var tail2: Node3D = _extra.get("tail2")
	var moving := anim == "walk" and _dead_t <= 0.0
	var v := move_speed()
	if moving and v < 0.3: v = 2.2
	_walk_w = move_toward(_walk_w, 1.0 if moving else 0.0, dt * 6.0)
	# quanto è galoppo (1) e quanto trotto (0)
	var run := smoothstep(2.8, 3.8, v) * _walk_w
	if moving: _gait_t += dt * TAU * v / lerpf(1.15, 2.1, run)
	var w := _gait_t
	var ww := _walk_w
	var amp := lerpf(0.5, 0.78, run) * ww
	# fasi delle quattro zampe: in diagonale al trotto, davanti e dietro a coppie al galoppo
	var ph := [w, w + lerpf(PI, 0.55, run), w + lerpf(PI, PI - 0.3, run), w + lerpf(0.0, PI + 0.25, run)]
	var front := [[leg_l, shin_l], [leg_r, shin_r]]
	for i in 2:
		var a: float = ph[i]
		(front[i][0] as Node3D).rotation = Vector3(-sin(a) * amp, 0, 0)
		(front[i][1] as Node3D).rotation.x = maxf(0.0, cos(a)) * lerpf(0.9, 1.3, run) * ww
		var b: float = ph[2 + i]
		legs_back[i].rotation = Vector3(-sin(b) * amp * 0.9, 0, 0)
		(_extra["bshin_%d" % i] as Node3D).rotation.x = maxf(0.0, cos(b)) * 0.8 * ww
		(_extra["bfoot_%d" % i] as Node3D).rotation.x = -maxf(0.0, cos(b)) * 0.9 * ww
	var flex := sin(w) * 0.2 * run
	var bob := (absf(sin(w)) * 0.025 * (1.0 - run) + sin(w - 0.6) * 0.05 * run) * ww
	var breath := sin(t * 2.2) * 0.006 * (1.0 - ww)
	var body := Vector3(0, bob + breath, 0)
	var chest_x := -flex
	var hips_x := flex * 1.1
	var head_rot := Vector3(0.12 - chest_x * 0.7, sin(t * 0.6) * 0.25 * sin(t * 0.23) * (1.0 - ww), 0)
	var jaw_open := 0.1 + sin(t * 1.3) * 0.04
	var tail_x := lerpf(0.1, 0.75, run) + sin(t * 2.0) * 0.06
	var tail_y := sin(t * (7.0 if moving else 2.0)) * lerpf(0.3, 0.12, run)
	if attack_timer > 0.0 and _dead_t <= 0.0:
		var k := 1.0 - attack_timer / attack_length
		# si raccoglie, scatta in avanti a fauci aperte, morde e torna
		var crouch := smoothstep(0.0, 0.16, k) * (1.0 - smoothstep(0.16, 0.3, k))
		var leap := smoothstep(0.16, 0.32, k) * (1.0 - smoothstep(0.5, 0.95, k))
		var air := sin(clampf((k - 0.16) / 0.42, 0.0, 1.0) * PI)
		body += Vector3(0, -0.07 * crouch + 0.1 * air, -0.1 * crouch + 0.42 * leap)
		chest_x += 0.12 * crouch - 0.3 * air
		hips_x += -0.1 * crouch + 0.12 * air
		head_rot.x = 0.3 * crouch - 0.05 * air + 0.25 * smoothstep(0.3, 0.38, k) * (1.0 - smoothstep(0.5, 0.8, k))
		head_rot.z = sin(k * 34.0) * 0.22 * smoothstep(0.34, 0.4, k) * (1.0 - smoothstep(0.55, 0.75, k))
		jaw_open = 0.15 + 0.75 * smoothstep(0.05, 0.28, k) * (1.0 - smoothstep(0.31, 0.37, k))
		for i in 2:
			(front[i][0] as Node3D).rotation.x += 0.35 * crouch - 0.95 * air
			(front[i][1] as Node3D).rotation.x += 0.5 * crouch + 0.25 * air
			legs_back[i].rotation.x += -0.3 * crouch + 0.75 * air
			(_extra["bshin_%d" % i] as Node3D).rotation.x += 0.35 * crouch - 0.25 * air
			(_extra["bfoot_%d" % i] as Node3D).rotation.x += -0.35 * crouch + 0.5 * air
		tail_x = 0.6
	# colpo subito: sussulta di lato e abbassa la testa
	var h := _hit_amount() * (0.0 if anim == "dead" else 1.0)
	body += Vector3(0.03 * _hit_side, -0.03, -0.09) * h
	chest_x += 0.1 * h
	head_rot += Vector3(0.35, 0.45 * _hit_side, 0.2 * _hit_side) * h
	jaw_open += 0.3 * h
	# caduta: le zampe cedono, poi si rovescia sul fianco
	var d := _dead_t
	var buckle := smoothstep(0.0, 0.45, d)
	var roll := smoothstep(0.25, 1.0, d)
	if d > 0.0:
		for i in 2:
			(front[i][0] as Node3D).rotation.x = lerpf((front[i][0] as Node3D).rotation.x, -0.5 + i * 0.25, buckle)
			(front[i][1] as Node3D).rotation.x = lerpf((front[i][1] as Node3D).rotation.x, 1.1 - i * 0.3, buckle)
			legs_back[i].rotation.x = lerpf(legs_back[i].rotation.x, 0.5 - i * 0.3, buckle)
			(_extra["bshin_%d" % i] as Node3D).rotation.x = lerpf((_extra["bshin_%d" % i] as Node3D).rotation.x, 0.5, buckle)
		body.y -= 0.22 * buckle * (1.0 - roll)
		head_rot = head_rot.lerp(Vector3(0.55, 0.0, -0.35), buckle)
		jaw_open = lerpf(jaw_open, 0.35, buckle)
		tail_x = lerpf(tail_x, -0.2, buckle)
		tail_y *= 1.0 - buckle
	spine.position = Vector3(0, 0.63, 0.2) + body + Vector3(0, -0.04 * buckle * (1.0 - roll), 0)
	hips.position = Vector3(0, 0.6, -0.26) + body
	spine.rotation = Vector3(chest_x, 0, 0.12 * h * _hit_side)
	hips.rotation = Vector3(hips_x, 0, 0)
	head.rotation = head_rot
	if jaw != null: jaw.rotation.x = jaw_open
	tail.rotation = Vector3(tail_x, tail_y, 0)
	if tail2 != null: tail2.rotation = Vector3(tail_x * 0.35 - 0.1, tail_y * 0.8, 0)
	rig.rotation = Vector3(0, 0, 1.42 * roll * roll)
	rig.position = Vector3(0, 0.06 * roll, 0)

## Bruto e Guardiano: postura curva, passo pesante che dondola, colpo dall'alto con
## tutto il corpo, barcollo ai colpi, crollo in ginocchio e poi a terra.
func _animate_heavy(dt: float) -> void:
	if rig == null: return
	var t := phase
	var boss := monster_kind == "boss"
	var moving := anim == "walk" and _dead_t <= 0.0
	var v := move_speed()
	if moving and v < 0.2: v = 0.6 if boss else 1.1
	var stride := 0.2 if boss else 0.24
	if moving: _gait_t += dt * v / stride
	_walk_w = move_toward(_walk_w, 1.0 if moving else 0.0, dt * 3.5)
	var w := _gait_t
	var ww := _walk_w
	var hunch := 0.16 if boss else 0.3
	var breath := sin(t * (1.1 if boss else 1.5))
	var sway := sin(t * 0.8) * (1.0 - ww)
	var p := {"spine_x": hunch + breath * 0.03, "spine_y": 0.0, "spine_z": 0.0, "head_x": -hunch * 0.75 + breath * 0.02, "head_y": sin(t * 0.45) * 0.22 * sin(t * 0.19) * (1.0 - ww),
		"arm_l_x": -0.22, "arm_r_x": -0.22, "arm_l_z": -0.32 - breath * 0.03, "arm_r_z": 0.32 + breath * 0.03, "elbow_l": -0.5, "elbow_r": -0.5, "wrist": 0.35,
		"dx": sway * 0.02, "dy": -0.06 + breath * 0.008, "dz": 0.0, "roll": sway * 0.015, "yaw": 0.0,
		"foot_l": 0.02, "foot_r": -0.02, "lift_l": 0.0, "lift_r": 0.0}
	if ww > 0.0:
		var sw := sin(w)
		var cw := cos(w)
		p.foot_l = lerpf(0.02, stride * sw, ww)
		p.foot_r = lerpf(-0.02, -stride * sw, ww)
		p.lift_l = maxf(0.0, cw) * 0.09 * ww
		p.lift_r = maxf(0.0, -cw) * 0.09 * ww
		# il peso passa sul piede d'appoggio: il corpo dondola e ricade a ogni passo
		p.roll += cw * 0.075 * ww
		p.dx += cw * 0.045 * ww
		p.dy -= absf(sw) * 0.04 * ww
		p.yaw = -sw * 0.14 * ww
		p.spine_y = sw * 0.22 * ww
		p.spine_z = -cw * 0.05 * ww
		p.spine_x += 0.06 * ww
		p.arm_l_x += sw * 0.4 * ww
		p.arm_r_x -= sw * 0.3 * ww
		p.elbow_l -= maxf(0.0, -sw) * 0.25 * ww
	if anim == "cheer":
		p.arm_l_x = -2.7 + sin(t * 6.0) * 0.15
		p.arm_r_x = -2.7 - sin(t * 6.0) * 0.15
	if attack_timer > 0.0 and _dead_t <= 0.0:
		var k := 1.0 - attack_timer / attack_length
		var wind := _mix(p, {"arm_l_x": -2.85, "arm_r_x": -2.95, "arm_l_z": 0.28, "arm_r_z": -0.28, "elbow_l": -0.75, "elbow_r": -0.6, "wrist": -0.35,
			"spine_x": -0.28, "spine_y": 0.12, "head_x": 0.1, "dy": 0.0, "dz": -0.06, "foot_l": 0.06, "foot_r": -0.08, "roll": 0.0, "dx": 0.0, "yaw": 0.0, "lift_l": 0.0, "lift_r": 0.0}, 1.0)
		var hit := _mix(wind, {"arm_l_x": -0.7, "arm_r_x": -0.8, "arm_l_z": 0.2, "arm_r_z": -0.2, "elbow_l": -0.3, "elbow_r": -0.2, "wrist": 0.55,
			"spine_x": 0.62 if boss else 0.72, "spine_y": -0.1, "head_x": -0.4, "dy": -0.1 if boss else -0.13, "dz": 0.16, "foot_l": 0.3, "foot_r": -0.12}, 1.0)
		if k < 0.26: p = _mix(p, wind, _ease_out(k / 0.26))
		elif k < 0.38:
			var s := (k - 0.26) / 0.12
			p = _mix(wind, hit, s * s)
		elif k < 0.62:
			# il colpo a terra fa tremare tutto
			var shake := sin(k * 90.0) * 0.012 * (1.0 - (k - 0.38) / 0.24)
			hit.dy = float(hit.dy) + shake
			p = _mix(hit, p, 0.08 * (k - 0.38) / 0.24)
		else: p = _mix(hit, p, 0.08 + 0.92 * smoothstep(0.62, 1.0, k))
	# colpo subito: barcolla all'indietro
	var h := _hit_amount() * (0.0 if anim == "dead" else 1.0) * (0.6 if boss else 1.0)
	p.spine_x = float(p.spine_x) - 0.24 * h
	p.spine_y = float(p.spine_y) + 0.2 * h * _hit_side
	p.head_x = float(p.head_x) + 0.25 * h
	p.dz = float(p.dz) - 0.07 * h
	p.arm_l_z = float(p.arm_l_z) - 0.2 * h
	p.arm_r_z = float(p.arm_r_z) + 0.2 * h
	# caduta: le ginocchia cedono, il busto si piega, poi giù in avanti
	var d := _dead_t
	var knees := smoothstep(0.0, 0.5, d)
	var fall := smoothstep(0.35, 1.0, d)
	if d > 0.0:
		p.dy = lerpf(float(p.dy), -0.3, knees)
		p.spine_x = lerpf(float(p.spine_x), 0.55, knees)
		p.head_x = lerpf(float(p.head_x), 0.4, knees)
		p.arm_l_x = lerpf(float(p.arm_l_x), -0.9 * fall, knees)
		p.arm_r_x = lerpf(float(p.arm_r_x), -0.7 * fall, knees)
		p.elbow_l = lerpf(float(p.elbow_l), -0.3, knees)
		p.elbow_r = lerpf(float(p.elbow_r), -0.3, knees)
		p.foot_l = lerpf(float(p.foot_l), -0.2, knees)
		p.foot_r = lerpf(float(p.foot_r), -0.28, knees)
		p.roll = float(p.roll) * (1.0 - knees)
		p.dx = float(p.dx) * (1.0 - knees)
	var dy := float(p.dy)
	var dz := float(p.dz)
	var roll_z := float(p.roll)
	hips.position = Vector3(float(p.dx), hip_height + dy, dz)
	hips.rotation = Vector3(0, float(p.yaw), roll_z)
	_plant(leg_l, shin_l, float(p.foot_l) - dz, float(p.lift_l) - dy, -0.1 - roll_z)
	_plant(leg_r, shin_r, float(p.foot_r) - dz, float(p.lift_r) - dy, 0.1 - roll_z)
	spine.rotation = Vector3(float(p.spine_x), float(p.spine_y), float(p.spine_z) - roll_z * 0.6)
	head.rotation = Vector3(float(p.head_x), float(p.head_y), 0)
	arm_l.rotation = Vector3(float(p.arm_l_x), 0, float(p.arm_l_z))
	arm_r.rotation = Vector3(float(p.arm_r_x), 0, float(p.arm_r_z))
	fore_l.rotation.x = float(p.elbow_l)
	fore_r.rotation.x = float(p.elbow_r)
	hand_r.rotation.x = float(p.wrist)
	rig.rotation = Vector3(1.38 * fall * fall, 0, 0)
	rig.position = Vector3(0, 0.1 * fall, 0)

func flash(amount: float) -> void:
	if _flash_mat != null: _flash_mat.set_shader_parameter("intensity", amount * 1.6)
	# un lampo che parte è un colpo appena subito: il corpo lo incassa
	if amount > _flash_prev + 0.25 and anim != "dead":
		_hit_t = 1.0
		_hit_side = -_hit_side
	_flash_prev = amount
