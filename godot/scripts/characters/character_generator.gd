extends RefCounted
class_name RiftwardCharacterGenerator

# Character category controls presentation; combat role, rarity, and stats remain independent.
# Red eyes: exactly 1 in 100,000 draws for every category (0.001%).
const RED_EYE_DENOMINATOR := 100000
const CATEGORIES := [
    "Swordsman", "Lancer", "Archer", "Rogue", "Mage", "Cleric", "Tank", "Barbarian",
    "Ranger", "Alchemist", "Blacksmith", "Merchant", "Villager", "Noble", "Scholar", "Beastkin"
]
const HAIR_COLORS := {
    "black": "#25222b", "brown": "#704833", "blond": "#dec27f", "auburn": "#a85439",
    "copper": "#da793c", "silver": "#c5cedb", "white": "#f0e9e7", "blue": "#578ddc",
    "violet": "#9a71db", "pink": "#e78fbc", "green": "#70a982", "teal": "#70c3c1"
}
const HAIR_BASE_WEIGHTS := {
    "black": 25.0, "brown": 28.0, "blond": 18.0, "auburn": 10.0, "copper": 7.0,
    "silver": 3.5, "white": 2.5, "blue": 1.5, "violet": 1.5, "pink": 1.0, "green": 1.0, "teal": 1.0
}
const EYE_COLORS := {
    "brown": "#815137", "amber": "#c3954a", "blue": "#639de2", "green": "#62a978",
    "gray": "#9daeb9", "hazel": "#9c8f59", "violet": "#9c75d0", "gold": "#e3bd55",
    "pink": "#e18fad", "teal": "#5cbabd", "red": "#c82c41"
}
const EYE_BASE_WEIGHTS := {
    "brown": 30.0, "amber": 9.0, "blue": 18.0, "green": 15.0, "gray": 10.0,
    "hazel": 10.0, "violet": 3.0, "gold": 2.0, "pink": 1.0, "teal": 2.0
}
const SKIN_TONES := ["#f8dfc4", "#edc9a7", "#dba887", "#bc8166", "#97634f", "#704438", "#4f312c"]
const HAIR_STYLES := ["short", "long", "ponytail", "braided", "bob", "wavy", "messy", "spiky", "undercut", "curly", "buzzcut", "bald"]
const FACE_STYLES := ["angelic", "ordinary", "rugged", "goofy", "weathered", "asymmetric", "severe", "soft", "distinctive", "tired"]
const FACE_SHAPES := ["oval", "round", "square", "long", "heart", "wide", "narrow"]
const BODY_TYPES := ["slim", "average", "stocky", "athletic", "curvy", "heavy", "very_heavy"]
const ADULT_AGE_GROUPS := ["young_adult", "adult", "mature", "senior"]
const PRESENTATIONS := ["masculine", "feminine", "androgynous"]
const FACE_DETAILS := ["none", "freckles", "scar", "wrinkles", "beauty_mark", "eye_bags", "strong_brows", "crooked_nose"]
const OUTFIT_COLORS := {
    "Swordsman": "#506c99", "Lancer": "#924c47", "Archer": "#647e56", "Rogue": "#555064",
    "Mage": "#6e58a4", "Cleric": "#ddcfb1", "Tank": "#66727e", "Barbarian": "#99583e",
    "Ranger": "#537967", "Alchemist": "#906c9c", "Blacksmith": "#706454", "Merchant": "#a27b53",
    "Villager": "#85896c", "Noble": "#546da9", "Scholar": "#617f8d", "Beastkin": "#876b60"
}
# Bias affects likelihood, never possibility. Every color retains a nonzero weight.
const CATEGORY_BIAS := {
    "Swordsman": {"hair": {"brown": 1.2, "black": 1.1}, "eyes": {"gray": 1.3}},
    "Lancer": {"hair": {"auburn": 1.4, "copper": 1.2}, "eyes": {"hazel": 1.2}},
    "Archer": {"hair": {"blond": 1.3, "green": 1.2}, "eyes": {"green": 1.3}},
    "Rogue": {"hair": {"black": 1.5, "silver": 1.2}, "eyes": {"gray": 1.4}},
    "Mage": {"hair": {"white": 3.0, "violet": 3.0, "blue": 2.4}, "eyes": {"violet": 3.0, "gold": 2.0}},
    "Cleric": {"hair": {"blond": 1.6, "white": 1.8}, "eyes": {"blue": 1.3, "gold": 1.4}},
    "Tank": {"hair": {"brown": 1.4}, "eyes": {"brown": 1.3}},
    "Barbarian": {"hair": {"auburn": 1.7, "copper": 1.8}, "eyes": {"amber": 1.4}},
    "Ranger": {"hair": {"green": 1.9, "brown": 1.2}, "eyes": {"green": 1.5}},
    "Alchemist": {"hair": {"pink": 2.0, "teal": 2.2}, "eyes": {"teal": 2.5}},
    "Blacksmith": {"hair": {"black": 1.4, "brown": 1.3}, "eyes": {"amber": 1.4}},
    "Merchant": {"hair": {"brown": 1.4, "silver": 1.2}, "eyes": {"hazel": 1.3}},
    "Villager": {"hair": {"brown": 1.5, "black": 1.2}, "eyes": {"brown": 1.3}},
    "Noble": {"hair": {"blond": 1.6, "silver": 1.8}, "eyes": {"blue": 1.5}},
    "Scholar": {"hair": {"silver": 2.1, "black": 1.1}, "eyes": {"gray": 1.5}},
    "Beastkin": {"hair": {"copper": 1.8, "teal": 1.2}, "eyes": {"amber": 1.5, "gold": 1.8}}
}

static func generate(seed_text: String, forced_category: String = "") -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = abs(seed_text.hash())
    var category: String = forced_category if CATEGORIES.has(forced_category) else str(CATEGORIES[rng.randi_range(0, CATEGORIES.size() - 1)])
    var category_bias: Dictionary = CATEGORY_BIAS.get(category, {})
    var hair: String = _weighted_color(rng, HAIR_BASE_WEIGHTS, category_bias.get("hair", {}))
    var eyes: String = "red" if rng.randi_range(1, RED_EYE_DENOMINATOR) == 1 else _weighted_color(rng, EYE_BASE_WEIGHTS, category_bias.get("eyes", {}))
    var face_style: String = str(_one(rng, FACE_STYLES))
    var face_shape: String = str(_one(rng, FACE_SHAPES))
    var body_type: String = str(_one(rng, BODY_TYPES))
    var hair_style: String = str(_one(rng, HAIR_STYLES))
    var skin: String = str(_one(rng, SKIN_TONES))
    return {
        "version": 1, "category": category, "hair_color": hair, "hair_hex": HAIR_COLORS[hair],
        "eye_color": eyes, "eye_hex": EYE_COLORS[eyes], "skin_hex": skin,
        "hair_style": hair_style, "face_style": face_style, "face_shape": face_shape,
        "face_detail": str(_one(rng, FACE_DETAILS)), "body_type": body_type,
        "height_scale": snappedf(rng.randf_range(0.80, 1.20), 0.01),
        "body_width": snappedf(rng.randf_range(0.86, 1.16), 0.01),
        "eye_spacing": snappedf(rng.randf_range(0.82, 1.18), 0.01),
        "eye_size": snappedf(rng.randf_range(0.83, 1.24), 0.01),
        "jaw_width": snappedf(rng.randf_range(0.80, 1.24), 0.01),
        "nose_length": snappedf(rng.randf_range(0.85, 1.25), 0.01),
        "age_group": str(_one(rng, ADULT_AGE_GROUPS)),
        "presentation": str(_one(rng, PRESENTATIONS)),
        "outfit_hex": str(OUTFIT_COLORS[category]),
        "facial_hair": str(_one(rng, ["none", "none", "none", "stubble", "beard", "moustache"])),
        "glasses": rng.randf() < 0.12,
        "scar": rng.randf() < 0.08,
        "visual_seed": seed_text,
    }

static func _one(rng: RandomNumberGenerator, values: Array) -> Variant:
    return values[rng.randi_range(0, values.size() - 1)]

static func _weighted_color(rng: RandomNumberGenerator, base: Dictionary, bonus: Dictionary) -> String:
    var total := 0.0
    for key in base:
        total += float(base[key]) * float(bonus.get(key, 1.0))
    var roll := rng.randf() * total
    for key in base:
        roll -= float(base[key]) * float(bonus.get(key, 1.0))
        if roll < 0.0:
            return str(key)
    return str(base.keys().back())
