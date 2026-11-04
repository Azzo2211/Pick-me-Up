extends Control
class_name RiftwardCharacterPortrait

# Vector preview: every feature is drawn from the saved procedural appearance.
# This is a 2D prototype/portrait, NOT a finished rigged 3D character.
var appearance: Dictionary = {}
const INK := Color("#29212b")
const LIGHT := Color("#ffe9d7")

func set_appearance(value: Dictionary) -> void:
    appearance = value.duplicate(true)
    queue_redraw()

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
    if appearance.is_empty():
        return
    var factor := Vector2(size.x / 240.0, size.y / 240.0)
    draw_set_transform(Vector2.ZERO, 0.0, factor)
    _render()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _ellipse(center: Vector2, radii: Vector2, count: int = 32) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(count):
        var angle := TAU * float(i) / float(count)
        points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
    return points

func _poly(points: Array, color: Color) -> void:
    var poly := PackedVector2Array()
    for point in points:
        poly.append(point)
    draw_colored_polygon(poly, color)

func _disc(center: Vector2, radius: float, color: Color) -> void:
    draw_circle(center, radius, color)

func _render() -> void:
    var skin := Color(str(appearance.get("skin_hex", "#edc9a7")))
    var hair := Color(str(appearance.get("hair_hex", "#704833")))
    var eye := Color(str(appearance.get("eye_hex", "#815137")))
    var cloth := Color(str(appearance.get("outfit_hex", "#6a6f8c")))
    var body_type := str(appearance.get("body_type", "average"))
    var face_shape := str(appearance.get("face_shape", "oval"))
    var face_style := str(appearance.get("face_style", "ordinary"))
    var hair_style := str(appearance.get("hair_style", "short"))
    var width_scale := float(appearance.get("body_width", 1.0))
    var body_width := 56.0 * width_scale
    match body_type:
        "slim": body_width *= 0.70
        "stocky": body_width *= 1.12
        "athletic": body_width *= 1.09
        "curvy": body_width *= 1.16
        "heavy": body_width *= 1.37
        "very_heavy": body_width *= 1.60
    var face_width := 37.0 * float(appearance.get("jaw_width", 1.0))
    match face_shape:
        "round": face_width *= 1.18
        "square": face_width *= 1.17
        "wide": face_width *= 1.25
        "narrow": face_width *= 0.82
        "heart": face_width *= 0.92
    var face_height := 48.0
    if face_shape == "long": face_height = 55.0
    if face_shape == "round": face_height = 43.0

    # Back hair and neck.
    if hair_style in ["long", "wavy", "braided", "ponytail", "curly"]:
        draw_colored_polygon(_ellipse(Vector2(120, 106), Vector2(face_width + 12, 82)), INK)
        draw_colored_polygon(_ellipse(Vector2(120, 107), Vector2(face_width + 8, 78)), hair)
    draw_rect(Rect2(106, 125, 28, 37), INK)
    draw_rect(Rect2(109, 125, 22, 37), skin.darkened(0.07))

    # Different bodies, including heavy and very heavy character silhouettes.
    draw_colored_polygon(_ellipse(Vector2(120, 235), Vector2(body_width + 5, 80)), INK)
    draw_colored_polygon(_ellipse(Vector2(120, 235), Vector2(body_width, 76)), cloth)
    draw_colored_polygon(_ellipse(Vector2(120, 235), Vector2(body_width * 0.68, 73)), cloth.lightened(0.11))
    _poly([Vector2(105, 156), Vector2(120, 187), Vector2(135, 156)], skin)

    var category := str(appearance.get("category", "Villager"))
    _draw_clothing(category, cloth, body_width)

    # Head outline, ears, and face.
    _disc(Vector2(81 - face_width * 0.03, 104), 9.0, INK)
    _disc(Vector2(159 + face_width * 0.03, 104), 9.0, INK)
    _disc(Vector2(81 - face_width * 0.03, 104), 6.3, skin)
    _disc(Vector2(159 + face_width * 0.03, 104), 6.3, skin)
    draw_colored_polygon(_ellipse(Vector2(120, 98), Vector2(face_width + 2.5, face_height + 2.5)), INK)
    draw_colored_polygon(_ellipse(Vector2(120, 97), Vector2(face_width, face_height)), skin)
    draw_colored_polygon(_ellipse(Vector2(134, 106), Vector2(face_width * 0.25, face_height * 0.46)), skin.darkened(0.06))

    if face_style == "angelic":
        _disc(Vector2(102, 118), 10, Color(1, 0.54, 0.57, 0.17))
        _disc(Vector2(138, 118), 10, Color(1, 0.54, 0.57, 0.17))
    if face_style == "weathered" or str(appearance.get("age_group", "adult")) == "senior":
        draw_line(Vector2(92, 113), Vector2(98, 128), skin.darkened(0.27), 1.2)
        draw_line(Vector2(142, 113), Vector2(146, 128), skin.darkened(0.27), 1.2)
    _draw_hair(hair_style, hair, face_width, face_height)

    # Independent eye shape/spacing/color. Red uses the exact rare appearance event.
    var spacing := 16.0 * float(appearance.get("eye_spacing", 1.0))
    var eye_size := 4.9 * float(appearance.get("eye_size", 1.0))
    var eyebrow_y := 85.0
    if face_style == "severe": eyebrow_y = 83.0
    for sign_value in [-1, 1]:
        var px := 120.0 + spacing * float(sign_value)
        draw_line(Vector2(px - 7, eyebrow_y), Vector2(px + 7, eyebrow_y + (2 if face_style == "goofy" else 0)), hair.darkened(0.38), 2.2)
        draw_colored_polygon(_ellipse(Vector2(px, 99), Vector2(eye_size + 3.0, eye_size * 0.72)), INK)
        draw_colored_polygon(_ellipse(Vector2(px, 98.4), Vector2(eye_size + 1.4, eye_size * 0.61)), Color("#fff8ef"))
        draw_circle(Vector2(px, 99), eye_size * 0.70, eye)
        draw_circle(Vector2(px, 99), eye_size * 0.36, INK)
        draw_circle(Vector2(px - 1.6, 97.5), 1.6, Color.WHITE)
    if face_style == "asymmetric":
        draw_line(Vector2(128, 84), Vector2(149, 89), INK, 2.2)
    var nose_length := float(appearance.get("nose_length", 1.0))
    draw_line(Vector2(120, 106), Vector2(116, 114 + 5.0 * nose_length), skin.darkened(0.34), 1.4)
    draw_line(Vector2(116, 114 + 5.0 * nose_length), Vector2(122, 121), skin.darkened(0.34), 1.1)
    var mouth_y := 133.0
    if face_style == "goofy":
        draw_arc(Vector2(120, 127), 7, 0.1, PI - 0.1, 10, INK, 1.5)
    else:
        draw_line(Vector2(113, mouth_y), Vector2(127, mouth_y + (1 if face_style == "tired" else 0)), skin.darkened(0.51), 1.6)
    _draw_details(skin, face_style)
    _draw_accessory(category, cloth)

func _draw_hair(style: String, hair: Color, fw: float, fh: float) -> void:
    if style == "bald": return
    var top_y := 49.0 - (5 if style in ["spiky", "messy"] else 0)
    draw_colored_polygon(_ellipse(Vector2(120, top_y + 18), Vector2(fw + 6, 27)), INK)
    draw_colored_polygon(_ellipse(Vector2(120, top_y + 17), Vector2(fw + 4, 25)), hair)
    if style in ["buzzcut", "undercut"]:
        return
    if style in ["bob", "long", "wavy", "curly"]:
        _poly([Vector2(87, 73), Vector2(80, 116), Vector2(96, 127), Vector2(104, 74)], hair)
        _poly([Vector2(142, 74), Vector2(151, 122), Vector2(164, 108), Vector2(152, 65)], hair)
    if style in ["spiky", "messy"]:
        _poly([Vector2(91, 62), Vector2(88, 34), Vector2(111, 55), Vector2(119, 25), Vector2(130, 52), Vector2(157, 35), Vector2(153, 74)], hair)
    if style in ["ponytail", "braided"]:
        _poly([Vector2(152, 61), Vector2(178, 78), Vector2(170, 158), Vector2(155, 123)], hair.darkened(0.12))
    _poly([Vector2(94, 68), Vector2(113, 74), Vector2(121, 61), Vector2(134, 75), Vector2(152, 68), Vector2(152, 79), Vector2(110, 82), Vector2(91, 84)], hair.darkened(0.04))

func _draw_clothing(category: String, cloth: Color, body_width: float) -> void:
    if category in ["Tank", "Swordsman", "Lancer", "Barbarian"]:
        draw_colored_polygon(_ellipse(Vector2(120 - body_width + 13, 179), Vector2(19, 14)), Color("#9ba5b4"))
        draw_colored_polygon(_ellipse(Vector2(120 + body_width - 13, 179), Vector2(19, 14)), Color("#9ba5b4"))
        draw_line(Vector2(116, 175), Vector2(124, 231), Color("#a9b8c9"), 4)
    elif category in ["Mage", "Cleric", "Scholar", "Noble", "Alchemist"]:
        _poly([Vector2(92, 155), Vector2(120, 188), Vector2(148, 155), Vector2(133, 231), Vector2(107, 231)], Color("#eee2c9"))
        draw_line(Vector2(120, 189), Vector2(120, 235), Color("#c3a15d"), 3)
    elif category in ["Merchant", "Villager", "Blacksmith"]:
        draw_rect(Rect2(104, 180, 32, 55), Color("#7a5d4d"))
        draw_line(Vector2(89, 205), Vector2(149, 205), Color("#b89b74"), 5)
    else:
        draw_line(Vector2(87, 159), Vector2(150, 237), Color("#c6aa79"), 7)

func _draw_details(skin: Color, face_style: String) -> void:
    var detail := str(appearance.get("face_detail", "none"))
    if detail == "freckles":
        for point in [Vector2(94, 115), Vector2(101, 118), Vector2(139, 117), Vector2(146, 115)]:
            _disc(point, 1.2, skin.darkened(0.38))
    if detail == "scar" or bool(appearance.get("scar", false)):
        draw_line(Vector2(143, 112), Vector2(151, 125), Color("#b15b5c"), 1.8)
    if detail == "wrinkles":
        draw_line(Vector2(99, 124), Vector2(107, 127), skin.darkened(0.28), 1.3)
    var facial_hair := str(appearance.get("facial_hair", "none"))
    if facial_hair == "beard":
        draw_colored_polygon(_ellipse(Vector2(120, 138), Vector2(25, 15)), Color(str(appearance.get("hair_hex", "#704833"))).darkened(0.17))
        draw_rect(Rect2(109, 131, 22, 9), skin)
    elif facial_hair == "moustache":
        draw_line(Vector2(110, 125), Vector2(119, 126), INK, 3)
        draw_line(Vector2(121, 126), Vector2(130, 125), INK, 3)
    elif facial_hair == "stubble":
        draw_arc(Vector2(120, 115), 23, 0.2, PI - 0.2, 14, INK, 1.0)
    if bool(appearance.get("glasses", false)):
        draw_arc(Vector2(104, 99), 12, 0, TAU, 20, Color("#60473b"), 2)
        draw_arc(Vector2(136, 99), 12, 0, TAU, 20, Color("#60473b"), 2)
        draw_line(Vector2(116, 98), Vector2(124, 98), Color("#60473b"), 2)

func _draw_accessory(category: String, cloth: Color) -> void:
    var steel := Color("#d2d7dd")
    var gold := Color("#e8c37b")
    match category:
        "Swordsman":
            draw_line(Vector2(42, 214), Vector2(63, 102), steel, 7)
            draw_line(Vector2(43, 165), Vector2(79, 171), gold, 6)
        "Lancer":
            draw_line(Vector2(57, 237), Vector2(56, 63), Color("#755746"), 6)
            _poly([Vector2(56, 42), Vector2(46, 74), Vector2(65, 74)], steel)
        "Archer", "Ranger":
            draw_arc(Vector2(38, 160), 65, -PI / 2, PI / 2, 16, Color("#9e7447"), 6)
            draw_line(Vector2(38, 95), Vector2(38, 225), Color("#e9d3ad"), 2)
        "Rogue":
            draw_line(Vector2(36, 213), Vector2(71, 164), steel, 5)
        "Mage":
            draw_line(Vector2(55, 238), Vector2(48, 80), gold, 5)
            _disc(Vector2(48, 72), 15, Color("#69c5eb"))
        "Cleric":
            draw_line(Vector2(48, 153), Vector2(48, 194), gold, 6)
            draw_line(Vector2(37, 164), Vector2(59, 164), gold, 6)
        "Tank":
            draw_colored_polygon(_ellipse(Vector2(48, 192), Vector2(30, 46)), steel)
            _disc(Vector2(48, 186), 9, gold)
        "Barbarian":
            draw_line(Vector2(57, 223), Vector2(56, 96), Color("#704932"), 8)
            _poly([Vector2(40, 103), Vector2(27, 65), Vector2(71, 79), Vector2(66, 117)], steel)
        "Alchemist":
            _disc(Vector2(55, 190), 17, Color("#6dc89c"))
            draw_rect(Rect2(47, 160, 16, 17), Color("#8b6b4a"))
        "Blacksmith":
            draw_line(Vector2(54, 219), Vector2(55, 153), Color("#765844"), 8)
            draw_rect(Rect2(29, 147, 50, 20), steel)
        "Merchant":
            _poly([Vector2(32, 180), Vector2(71, 180), Vector2(76, 235), Vector2(28, 235)], Color("#9d7e59"))
            _disc(Vector2(51, 199), 12, gold)
        "Villager":
            draw_colored_polygon(_ellipse(Vector2(48, 216), Vector2(30, 16)), Color("#a37a4e"))
            for p in [Vector2(31, 204), Vector2(48, 200), Vector2(58, 207)]: _disc(p, 7, Color("#85ad68"))
        "Noble":
            draw_line(Vector2(91, 178), Vector2(148, 178), gold, 5)
            _disc(Vector2(120, 178), 6, Color("#67bed3"))
        "Scholar":
            draw_rect(Rect2(34, 182, 41, 45), Color("#ded5bd"))
            draw_line(Vector2(54, 181), Vector2(54, 226), Color("#877052"), 2)
        "Beastkin":
            var hair := Color(str(appearance.get("hair_hex", "#704833")))
            _poly([Vector2(87, 71), Vector2(88, 28), Vector2(115, 56)], hair)
            _poly([Vector2(129, 56), Vector2(153, 25), Vector2(154, 75)], hair)
