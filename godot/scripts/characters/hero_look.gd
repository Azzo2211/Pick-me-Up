extends RefCounted

## Aspetto a pezzi degli eroi, come nel foglio di riferimento dei personaggi:
## archetipo (Guardia, Mercante, Studioso, Popolano), testa base, 3 volti per
## archetipo, 4 capigliature per archetipo, corporatura ed età. I colori di
## capelli e occhi vengono dal generatore personaggi (occhi rossi 1 su 100.000).
##
## La logica: i popolani (1★-2★) hanno l'aspetto del loro mestiere; dal 3★ in su
## l'aspetto segue la classe. La rarità rende più probabile il volto più bello.
## Tutto dipende dall'id dell'eroe: stesso eroe, stesso aspetto.

## Se cambia, gli eroi salvati ricevono di nuovo i loro pezzi.
const VERSION := 1

const ARCHETYPES := {
	"guard": {
		"label": "Guardia", "bodies": ["athletic", "muscular"], "age": [18, 44],
		"hair_m": ["wavy", "medium", "tied_back", "short"], "hair_f": ["tied_back", "long_wavy", "braid", "short"],
		"faces": ["bello", "comune", "rude"],
	},
	"merchant": {
		"label": "Mercante", "bodies": ["slim", "average", "chubby"], "age": [20, 56],
		"hair_m": ["slicked", "layered", "wavy", "messy"], "hair_f": ["layered", "long_wavy", "bun", "bob"],
		"faces": ["affascinante", "cordiale", "semplice"],
	},
	"scholar": {
		"label": "Studioso", "bodies": ["slim", "average"], "age": [16, 58],
		"hair_m": ["long_straight", "layered", "braid", "short"], "hair_f": ["long_straight", "layered", "braid", "bob"],
		"faces": ["gentile", "calmo", "anziano"],
	},
	"villager": {
		"label": "Popolano", "bodies": ["slim", "average", "muscular"], "age": [16, 60],
		"hair_m": ["messy", "crop", "wavy", "bun"], "hair_f": ["messy", "bob", "long_wavy", "bun"],
		"faces": ["vivace", "comune", "segnato"],
	},
}
## Aspetto (e vestiti) di chi ha una classe. Il Ranger veste da cacciatore.
const CLASS_ARCHETYPE := {"Guardian": "guard", "Vanguard": "guard", "Lancer": "guard", "Ranger": "villager", "Mage": "scholar", "Support": "scholar"}
const CLASS_OUTFIT := {"Guardian": "guard", "Vanguard": "guard", "Lancer": "guard", "Ranger": "hunter", "Mage": "scholar", "Support": "scholar"}
## Categorie del generatore personaggi per classe: decidono i colori più probabili.
const CLASS_CATEGORIES := {
	"Guardian": ["Tank", "Swordsman"], "Vanguard": ["Swordsman", "Barbarian"], "Lancer": ["Lancer"],
	"Ranger": ["Ranger", "Archer"], "Mage": ["Mage", "Alchemist"], "Support": ["Cleric"],
}
const HAIR_LABELS := {
	"wavy": "mossi", "medium": "a media lunghezza", "tied_back": "legati dietro", "short": "corti",
	"slicked": "tirati indietro", "layered": "scalati", "messy": "spettinati", "long_straight": "lunghi e lisci",
	"braid": "con treccia", "crop": "rasati corti", "bun": "raccolti a crocchia", "long_wavy": "lunghi e mossi", "bob": "a caschetto",
}
const BODY_LABELS := {"slim": "snello", "average": "nella media", "athletic": "atletico", "muscular": "muscoloso", "chubby": "robusto"}
## Probabilità dei tre volti (bello, comune, rude) per rarità.
const FACE_WEIGHTS := {1: [15, 50, 35], 2: [25, 50, 25], 3: [35, 45, 20], 4: [50, 40, 10], 5: [60, 35, 5], 6: [72, 28, 0], 7: [82, 18, 0]}
## Età per fascia del generatore, poi stretta dentro quella dell'archetipo.
const AGE_GROUPS := {"young_adult": [16, 25], "adult": [24, 38], "mature": [36, 50], "senior": [48, 62]}
## Corporatura del generatore → corporature del foglio, in ordine di preferenza.
const BODY_MAP := {
	"slim": ["slim", "average"], "average": ["average", "athletic", "slim"], "athletic": ["athletic", "muscular", "average"],
	"stocky": ["muscular", "chubby", "average"], "curvy": ["average", "chubby"], "heavy": ["chubby", "muscular", "average"],
	"very_heavy": ["chubby", "muscular", "average"],
}

static func category_for_role(role: String, id: String) -> String:
	var options: Array = CLASS_CATEGORIES.get(role, ["Villager"])
	return str(options[abs((id + ":category").hash()) % options.size()])

## Pezzi dell'eroe: {v, archetype, face, hair, body, age}. `gen` è il risultato del generatore personaggi.
static func generate(id: String, archetype: String, fem: bool, rarity: int, gen: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs((id + ":look").hash())
	var arch: Dictionary = ARCHETYPES.get(archetype, ARCHETYPES.villager)
	# volto: più è rara, più è probabile il volto bello
	var weights: Array = FACE_WEIGHTS.get(clampi(rarity, 1, 7), FACE_WEIGHTS[1])
	var roll := rng.randi_range(1, int(weights[0]) + int(weights[1]) + int(weights[2]))
	var face := 0 if roll <= int(weights[0]) else 1 if roll <= int(weights[0]) + int(weights[1]) else 2
	var hairs: Array = arch.hair_f if fem else arch.hair_m
	var hair := str(hairs[rng.randi_range(0, hairs.size() - 1)])
	# corporatura: quella del generatore, se l'archetipo la prevede
	var body := ""
	for option in BODY_MAP.get(str(gen.get("body_type", "average")), ["average"]):
		if (arch.bodies as Array).has(option):
			body = str(option)
			break
	if body.is_empty(): body = str(arch.bodies[rng.randi_range(0, arch.bodies.size() - 1)])
	# età: fascia del generatore dentro i limiti dell'archetipo; il volto "anziano" è più vecchio
	var span: Array = AGE_GROUPS.get(str(gen.get("age_group", "adult")), [24, 38])
	var lo := maxi(int(span[0]), int(arch.age[0]))
	var hi := mini(int(span[1]), int(arch.age[1]))
	if lo > hi: lo = hi
	var age := rng.randi_range(lo, hi)
	if archetype == "scholar" and face == 2: age = maxi(age, 46)
	if face == 0: age = mini(age, 34)
	return {"v": VERSION, "archetype": archetype, "face": face, "hair": hair, "body": body, "age": age}

static func label(archetype: String) -> String:
	return str(ARCHETYPES.get(archetype, {}).get("label", archetype))

static func face_label(archetype: String, face: int) -> String:
	var faces: Array = ARCHETYPES.get(archetype, ARCHETYPES.villager).faces
	return str(faces[clampi(face, 0, faces.size() - 1)])
