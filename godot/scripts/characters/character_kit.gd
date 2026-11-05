extends RefCounted

## Kit dei personaggi modellato in Blender (tools/character_kit/build_kit.py), come
## il foglio di riferimento: per ogni vestito un corpo unico legato allo scheletro di
## CharacterModel, con le corporature come chiavi di forma; poi la testa base (tre
## volti, viso femminile, guance piene), le capigliature e gli accessori.
##
## I colori non stanno nei modelli: ogni faccia dice solo il suo "posto" (pelle,
## stoffa principale, metallo...) e la tavolozza dell'eroe li riempie. La logica:
## il vestito decide i colori di base come nel foglio, l'eroe li varia di poco e la
## rarità decide quanto brillano le finiture (ottone per i popolani, oro dal 4★).

const DIR := "res://assets/characters/kit/"

enum { SKIN, MAIN, SECOND, LIGHT, LEATHER, METAL, GOLD, DARK, BOOT, ACCENT, WOOD, LIGHT2, METAL_DARK, MOUTH, LINE }

## Lucentezza dei posti (alfa della tavolozza): metalli e cuoio hanno un riflesso.
const SHINE := {METAL: 0.75, METAL_DARK: 0.55, GOLD: 0.65, LEATHER: 0.12, BOOT: 0.18}

## Colori di base per vestito, dal foglio. Le liste sono varianti tra cui l'eroe sceglie.
const OUTFIT_COLORS := {
	"villager": {
		LIGHT: ["#e6dcc6", "#ddd5c4", "#d8ccb0", "#d3d6d0"], SECOND: ["#6b5340", "#5c5146", "#55504a", "#6d5c45"],
		LEATHER: ["#6e4b2f", "#7a5535", "#5f432b"], BOOT: ["#43301f"], DARK: ["#2a1e17"], MAIN: ["#7b6a52"],
	},
	"guard": {
		MAIN: ["#3b3d46"], SECOND: ["#2f2c2e", "#33302c"], LIGHT: ["#e7dfcd"], LEATHER: ["#5a3c27", "#4e3626"],
		METAL: ["#7d8590"], METAL_DARK: ["#4a4f58"], BOOT: ["#33251b"], DARK: ["#1f1a17"], ACCENT: ["#532428"],
	},
	"merchant": {
		LIGHT: ["#e2d8c3", "#ddd3bf"], MAIN: ["#2f3446", "#3a3040", "#2e3a3a"], SECOND: ["#6d6052", "#5f5a55", "#6a5847"],
		LEATHER: ["#6b4429", "#76502f"], BOOT: ["#3d2a1d"], DARK: ["#262021"], ACCENT: ["#7a2c2c", "#6b4a1f", "#2f4a3a"],
		LIGHT2: ["#cdbf9f"],
	},
	"scholar": {
		MAIN: ["#2b3352", "#2d2f4a", "#30364f"], LIGHT: ["#ece5d6"], LIGHT2: ["#f2eee6"], SECOND: ["#3a3f52"],
		LEATHER: ["#5e4129"], BOOT: ["#2b2420"], DARK: ["#1f1d24"], ACCENT: ["#6b2433"],
	},
	"hunter": {
		MAIN: ["#3f5136", "#45503a", "#3b4a3f"], SECOND: ["#4e4034", "#4a4339"], LIGHT: ["#ddd4bf"],
		LEATHER: ["#6a4a30", "#5d4128"], BOOT: ["#3a2a1e"], DARK: ["#231c17"], WOOD: ["#7a5a3a"],
	},
}

## Colore principale per classe quando la classe è scelta: stessa logica del foglio
## (guardie col mantello rosso scuro, maghi in viola, chierici in blu e bianco...).
const CLASS_TINT := {
	"Guardian": {ACCENT: "#532428"}, "Vanguard": {ACCENT: "#4f1c22", MAIN: "#2e2a2c"}, "Lancer": {ACCENT: "#26324f"},
	"Ranger": {}, "Mage": {MAIN: "#3a2d5a"}, "Support": {MAIN: "#2b3352"},
}

static var _bodies: Dictionary = {}
static var _parts: Dictionary = {}
static var _parts_loaded := false

static func available() -> bool:
	return ResourceLoader.exists(DIR + "parts.glb") or FileAccess.file_exists(DIR + "parts.glb")

static func _load_scene(path: String) -> Node:
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null: return scene.instantiate()
	# glb non ancora importato da Godot: lo si legge direttamente
	if not FileAccess.file_exists(path): return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK: return null
	return doc.generate_scene(state)

## Copia nuova del corpo vestito (Skeleton3D con la sua mesh), o null se manca.
static func body_instance(outfit: String) -> Node:
	if not _bodies.has(outfit):
		var path := DIR + "body_%s.glb" % outfit
		_bodies[outfit] = _load_scene(path) if (ResourceLoader.exists(path) or FileAccess.file_exists(path)) else null
	var template: Node = _bodies[outfit]
	return template.duplicate() if template != null else null

## Mesh di un pezzo della testa: "head", "hair_<taglio>", "glasses", "headband", "beard_short"...
static func part(name: String) -> Mesh:
	if not _parts_loaded:
		_parts_loaded = true
		var root := _load_scene(DIR + "parts.glb")
		if root != null:
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				_parts[str(mi.name)] = (mi as MeshInstance3D).mesh
			root.free()
	return _parts.get(name)

# -----------------------------------------------------------------------------
# Modelli fatti dall'utente (tools/character_kit/import_user_model.py)
# -----------------------------------------------------------------------------

## Corpi completi fatti a parte, con le texture dipinte: se c'è quello di un vestito,
## lo usano gli eroi con quel vestito al posto del corpo del kit. Stesso scheletro del
## kit, ma con le braccia tese come nel file (CharacterModel corregge il riposo).
const USER_DIR := "res://assets/characters/user/"
static var _user: Dictionary = {}

static func has_user_body(outfit: String) -> bool:
	var path := USER_DIR + "%s.glb" % outfit
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

static func user_body(outfit: String) -> Node:
	if not _user.has(outfit):
		_user[outfit] = _load_scene(USER_DIR + "%s.glb" % outfit) if has_user_body(outfit) else null
	var template: Node = _user[outfit]
	return template.duplicate() if template != null else null

static func has_outfit(outfit: String) -> bool:
	var path := DIR + "body_%s.glb" % outfit
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

# -----------------------------------------------------------------------------
# Tavolozza dell'eroe
# -----------------------------------------------------------------------------

## Porta un colore qualsiasi del generatore dentro toni sobri, da stoffa tinta.
static func earthy(c: Color, max_sat: float = 0.45, v_lo: float = 0.3, v_hi: float = 0.55) -> Color:
	return Color.from_hsv(c.h, minf(c.s, max_sat), clampf(c.v, v_lo, v_hi))

static func _pick(options: Array, seed_text: String) -> Color:
	return Color(str(options[abs(seed_text.hash()) % options.size()]))

static func trim_color(rarity: int) -> Color:
	if rarity <= 2: return Color("#9c8650")
	if rarity == 3: return Color("#b8954f")
	if rarity == 4: return Color("#cfa94f")
	return Color("#e2bb4f")

static func palette(look: Dictionary, outfit: String, rarity: int) -> Array:
	var seed_text := str(look.get("seed", look.get("id", "x")))
	var cols: Array = []
	cols.resize(16)
	for i in 16: cols[i] = Color("#808080")
	var base: Dictionary = OUTFIT_COLORS.get(outfit, OUTFIT_COLORS.villager)
	for slot in base:
		cols[slot] = _pick(base[slot], seed_text + ":%d" % slot)
	cols[SKIN] = look.get("skin", Color("#f1d2b6"))
	cols[GOLD] = trim_color(rarity)
	cols[WOOD] = cols[WOOD] if base.has(WOOD) else Color("#7a5a3a")
	cols[MOUTH] = Color("#8a4a48")
	var accent: Color = look.get("outfit", Color("#7a4a3a"))
	match outfit:
		"villager":
			# fazzoletto e toppe col colore dell'eroe, smorzato
			cols[ACCENT] = earthy(accent, 0.5, 0.42, 0.62)
			cols[MAIN] = earthy(accent, 0.3, 0.38, 0.5)
		"merchant":
			if not look.get("veteran", false): cols[ACCENT] = earthy(accent, 0.5, 0.35, 0.5)
		"hunter":
			cols[ACCENT] = earthy(accent, 0.45, 0.35, 0.5)
	var role := str(look.get("role", ""))
	if look.get("class_chosen", true) and CLASS_TINT.has(role):
		var tint: Dictionary = CLASS_TINT[role]
		for slot in tint: cols[slot] = Color(str(tint[slot]))
	var out: Array = []
	for i in 16:
		var c: Color = cols[i]
		out.append(Color(c.r, c.g, c.b, float(SHINE.get(i, 0.0))))
	return out
