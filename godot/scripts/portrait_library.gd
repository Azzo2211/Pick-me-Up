extends RefCounted

## Ritratti dipinti degli eroi: 300 volti ritagliati dalle griglie mandate dal
## giocatore (assets/portraits/pNNN.jpg, ingranditi 2×).
## Ogni eroe riceve un ritratto fisso, salvato in hero.portrait. Il catalogo
## (portraits.json) dice sesso, capelli, pelle e dettagli di ogni volto: così
## la scelta rispetta il nome dell'eroe e il modello 3D gli somiglia.
## Niente class_name: si usa con preload (la cache delle classi di Godot può essere vecchia).

const DIR := "res://assets/portraits/"
const MANIFEST := DIR + "portraits.json"

## Sigle del catalogo: B barba, S baffi o barba corta, G occhiali, X cicatrice,
## O anziano, E elfo, D nano, C testa coperta (cappuccio, cappello, fazzoletto),
## F robusto, L capelli lunghi, Q pelleverde (goblin, orco), K uomo-bestia, R occhi rossi.
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

## Sceglie il ritratto di un eroe: stesso sesso del nome (o volto neutro), uomini-bestia e
## pelleverde solo per gli uomini-bestia (e i pelleverde anche per i barbari),
## occhi rossi solo a chi li ha davvero. Tra i volti adatti preferisce quelli
## non ancora usati; a parità decide l'hash dell'id, quindi è stabile.
static func pick(seed_text: String, fem: bool, category: String, red_eyes: bool, used: Dictionary) -> String:
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
			if relax < 1 and flags.contains("R") != red_eyes: continue
			if relax >= 1 and flags.contains("R") and not red_eyes: continue
			var sex := str(e.get("sex", "a"))
			if relax < 2 and sex != "a" and (sex == "f") != fem: continue
			# md5: mescola bene anche id quasi uguali (String.hash darebbe sempre lo stesso volto)
			var score: int = ("%s|%s" % [seed_text, id]).md5_text().substr(0, 6).hex_to_int()
			if used.has(id): score += 0x1000000 * int(used[id])
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
