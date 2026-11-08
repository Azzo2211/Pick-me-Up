extends RefCounted

## Ritratti dipinti degli eroi: 300 volti ritagliati dalle griglie mandate dal
## giocatore (assets/portraits/pNNN.jpg, ingranditi 2×). Dalle foto vengono volto e
## taglio di capelli; colore dei capelli e degli occhi vengono dal generatore personaggi.
## Ogni eroe riceve un ritratto fisso, salvato in hero.portrait. Il catalogo
## (portraits.json) dice sesso, capelli, pelle e dettagli di ogni volto: così
## la scelta rispetta il nome dell'eroe e il modello 3D gli somiglia.
## Niente class_name: si usa con preload (la cache delle classi di Godot può essere vecchia).

const DIR := "res://assets/portraits/"
const MANIFEST := DIR + "portraits.json"

## Sigle del catalogo: B barba, S baffi o barba corta, G occhiali, X cicatrice,
## O anziano, E elfo, D nano, C testa coperta (cappuccio, cappello, fazzoletto),
## F robusto, L capelli lunghi, Q pelleverde (goblin, orco), K uomo-bestia, R occhi rossi dipinti.
## Ogni volto ha anche pNNN_mask.png (rosso = capelli, verde = iridi) e nel catalogo
## la luminosità dipinta di capelli e occhi (OKLab L) e la tinta media dei capelli: servono
## a ricolorarli con i colori del generatore. Le fa tools/character_kit/portrait_masks.py;
## le iridi sono controllate a occhio (has_eyes), chi non le ha tiene gli occhi dipinti.
const HAIR_HEX := {
	"black": "#25222b", "brown": "#704833", "blond": "#dec27f", "auburn": "#a85439",
	"copper": "#da793c", "silver": "#c5cedb", "white": "#f0e9e7", "blue": "#578ddc",
	"violet": "#9a71db", "pink": "#e78fbc", "green": "#70a982", "teal": "#70c3c1", "bald": "#3a2a20",
}
const SKIN_HEX := ["#f8dfc4", "#edc9a7", "#dba887", "#bc8166", "#97634f", "#704438"]
const GREEN_SKIN := "#7f8f5c"
## Uomini-bestia: colore del pelo o delle squame e forma della testa nel modello 3D.
const BEASTS := {
	"p087": {"skin": "#7d8a70", "kind": "lizard"}, "p270": {"skin": "#c9a774", "kind": "lizard"},
	"p097": {"skin": "#b4834c", "kind": "feline"}, "p174": {"skin": "#cfc8bd", "kind": "feline"},
	"p225": {"skin": "#e2ddd4", "kind": "feline"}, "p292": {"skin": "#6b4a35", "kind": "bull"},
}

static var _loaded := false
static var _entries: Dictionary = {}
static var _order: Array = []
static var _textures: Dictionary = {}

static func ensure() -> bool:
	if _loaded: return not _entries.is_empty()
	_loaded = true
	if not FileAccess.file_exists(MANIFEST): return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary: return false
	for e in parsed.get("portraits", []):
		var id := str(e.get("id", ""))
		if id.is_empty(): continue
		_entries[id] = e
		_order.append(id)
	return not _entries.is_empty()

static func count() -> int:
	ensure()
	return _order.size()

static func has(id: String) -> bool:
	ensure()
	return _entries.has(id)

static func entry(id: String) -> Dictionary:
	ensure()
	return _entries.get(id, {})

## Texture del ritratto (caricata una volta sola). null se manca.
static func texture(id: String) -> Texture2D:
	if id.is_empty() or not has(id): return null
	if _textures.has(id): return _textures[id]
	var path := DIR + id + ".jpg"
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[id] = tex
	return tex

## Centro del volto nel ritratto (0–1), per i ritagli.
static func focus(id: String) -> Vector2:
	var e := entry(id)
	return Vector2(float(e.get("cx", 0.5)), float(e.get("cy", 0.45)))

## Colori dipinti che si ricolorano bene in un altro colore (dipinto → colori di arrivo).
## Un ritratto con capelli neri diventa bene castano o blu, molto peggio biondo.
const HAIR_COMPAT := {
	"black": ["black", "brown", "blue", "violet"],
	"brown": ["brown", "black", "auburn", "copper"],
	"auburn": ["auburn", "copper", "brown", "pink"],
	"copper": ["copper", "auburn", "brown"],
	"blond": ["blond", "white", "silver", "pink", "green", "teal"],
	"silver": ["silver", "white", "blond", "blue", "teal", "violet", "pink", "green"],
	"white": ["white", "silver", "blond", "blue", "teal", "violet", "pink", "green"],
	"violet": ["violet", "blue", "pink", "black"],
	"blue": ["blue", "violet", "teal", "silver"],
	"pink": ["pink", "auburn", "violet", "blond"],
	"teal": ["teal", "green", "blue"],
	"green": ["green", "teal", "blue"],
}

## I capelli del ritratto si possono ricolorare? Serve una maschera dei capelli buona
## (hair_ok: controllata a occhio, niente chiazze né pellicce colorate) e niente barba
## piena o testa coperta (la maschera li confonderebbe con i capelli).
static func hair_recolorable(id: String) -> bool:
	var e := entry(id)
	var flags := str(e.get("flags", ""))
	return bool(e.get("hair_ok", false)) and not flags.contains("B") and not flags.contains("C")

## I capelli dipinti di `id` diventano bene del colore `family`? Solo tra colori vicini
## (HAIR_COMPAT): nero → biondo o bianco verrebbe grigio e sporco, meglio il colore dipinto.
static func hair_recolors_to(id: String, family: String) -> bool:
	var painted := str(entry(id).get("hair", ""))
	return hair_recolorable(id) and HAIR_COMPAT.get(painted, []).has(family)

## Il ritratto mostrerà i capelli nel colore `family` (già dipinti così, ricolorati o calvo)?
static func shows_hair(id: String, family: String) -> bool:
	var painted := str(entry(id).get("hair", ""))
	return painted == family or painted == "bald" or hair_recolors_to(id, family)

## Cosa ricolorare nel ritratto `id` per un eroe con capelli `family`:
## maschera (R capelli, G iridi), cosa accendere e la luminosità dipinta di capelli e occhi.
static func recolor(id: String, family: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty(): return {}
	var path := DIR + id + "_mask.png"
	var mask: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	var painted := str(e.get("hair", ""))
	return {
		"mask": mask,
		"hair_on": mask != null and not family.is_empty() and painted != family and painted != "bald" and hair_recolors_to(id, family),
		"eye_on": mask != null and bool(e.get("has_eyes", false)),
		"hair_range": _range(e, "hair"),
		"hair_ab": Vector2(float(e.get("hair_a", 0.0)), float(e.get("hair_b", 0.0))),
		"eye_range": _range(e, "eye"),
	}

## Luminosità dipinta (più scura, media, più chiara) di capelli o iridi, in OKLab L.
static func _range(e: Dictionary, part: String) -> Vector3:
	var lo := float(e.get(part + "_lo", 0.25))
	var hi := float(e.get(part + "_hi", 0.7))
	return Vector3(lo, float(e.get(part + "_mid", (lo + hi) * 0.5)), hi)

## Quanto un volto è adatto ai capelli dell'eroe (0 è il migliore): stesso colore dipinto,
## poi un colore che si ricolora bene, poi il resto (capelli col colore dipinto).
## Un punto in più se gli occhi non si possono ricolorare.
static func _tier(e: Dictionary, family: String, red_eyes: bool = false) -> int:
	var id := str(e.get("id", ""))
	var painted := str(e.get("hair", ""))
	var tier := 6
	if family.is_empty() or painted == family: tier = 0
	elif painted == "bald" or hair_recolors_to(id, family): tier = 2
	var eyes_ok := bool(e.get("has_eyes", false))
	if not eyes_ok: tier += 1
	# occhi rossi (1 su 100.000): servono occhi ricolorabili o già dipinti rossi;
	# gli occhi rossi dipinti che non si ricolorano restano a chi li ha davvero
	var painted_red := str(e.get("flags", "")).contains("R")
	if red_eyes and not eyes_ok and not painted_red: tier += 8
	if painted_red and not eyes_ok and not red_eyes: tier += 16
	return tier

## Sceglie il ritratto di un eroe: stesso sesso del nome (o volto neutro), uomini-bestia e
## pelleverde solo per gli uomini-bestia (e i pelleverde anche per i barbari).
## Volti e tagli vengono dalle foto, i colori di capelli e occhi dal generatore:
## preferisce i volti non ancora usati, poi quelli che mostrano bene il colore
## dei capelli dell'eroe; a parità decide l'hash dell'id, quindi è stabile.
static func pick(seed_text: String, fem: bool, category: String, hair_family: String, used: Dictionary, red_eyes: bool = false) -> String:
	if not ensure(): return ""
	# passaggi sempre più larghi, se i volti adatti sono finiti
	for relax in 3:
		var best := ""
		var best_score := 0
		for id in _order:
			var e: Dictionary = _entries[id]
			var flags := str(e.get("flags", ""))
			var beastly := flags.contains("K") or flags.contains("Q")
			if category == "Beastkin":
				if not beastly and relax < 2: continue
			elif beastly and not (category == "Barbarian" and flags.contains("Q")):
				continue
			var sex := str(e.get("sex", "a"))
			if relax < 2 and sex != "a" and (sex == "f") != fem: continue
			# md5: mescola bene anche id quasi uguali (String.hash darebbe sempre lo stesso volto)
			var score: int = ("%s|%s" % [seed_text, id]).md5_text().substr(0, 6).hex_to_int()
			score += 0x1000000 * _tier(e, hair_family, red_eyes)
			if used.has(id): score += 0x10000000 * int(used[id])
			if best.is_empty() or score < best_score:
				best = id
				best_score = score
		if not best.is_empty(): return best
	return ""

## Tratti del ritratto che il resto del gioco deve rispettare (colori, barba, occhiali…).
static func look(id: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty(): return {}
	var flags := str(e.get("flags", ""))
	var hair_name := str(e.get("hair", "black"))
	var skin_code := str(e.get("skin", "1"))
	var skin := Color(SKIN_HEX[clampi(int(skin_code), 0, SKIN_HEX.size() - 1)]) if skin_code.is_valid_int() else Color(GREEN_SKIN)
	var beast := ""
	if BEASTS.has(id):
		skin = Color(str(BEASTS[id].skin))
		beast = str(BEASTS[id].kind)
	return {
		"portrait": id,
		"sex": str(e.get("sex", "a")),
		"hair": Color(str(HAIR_HEX.get(hair_name, "#3a2a20"))),
		"hair_color": hair_name,
		"bald": hair_name == "bald",
		"skin": skin,
		"beard": 2 if flags.contains("B") else 1 if flags.contains("S") else 0,
		"glasses": flags.contains("G"),
		"scar": flags.contains("X"),
		"old": flags.contains("O"),
		"elf": flags.contains("E"),
		"dwarf": flags.contains("D"),
		"covered": flags.contains("C"),
		"heavy": flags.contains("F"),
		"long_hair": flags.contains("L"),
		"greenskin": flags.contains("Q"),
		"beast": beast,
	}
