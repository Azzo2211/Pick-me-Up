extends Control
class_name HeroPortrait

## Ritratto chibi disegnato in 2D, coerente con il modello 3D dell'eroe
## (stessi colori di capelli, pelle, occhi e abito).

var hero_name := "HERO"
var role := "Guardian"
var rarity := 1
var dead := false
var appearance: Dictionary = {}
var portrait_size := Vector2(96, 96)

func setup(hero: Dictionary, size_px: float = 96.0) -> void:
	hero_name = str(hero.get("name", "Hero"))
	role = str(hero.get("role", "Guardian"))
	rarity = clampi(int(hero.get("current_rarity", 1)), 1, 7)
	dead = str(hero.get("state", "ALIVE")) != "ALIVE"
	appearance = GameState.hero_appearance(hero) if is_instance_valid(GameState) else {}
	portrait_size = Vector2(size_px, size_px)
	custom_minimum_size = portrait_size
	queue_redraw()

func _ready() -> void:
	custom_minimum_size = portrait_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ellipse(center: Vector2, rx: float, ry: float, color: Color, segments: int = 28) -> void:
	var points := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(points, color)

func _draw() -> void:
	var s := minf(size.x, size.y)
	var frame := UIKit.rarity_color(rarity)
	var hair: Color = appearance.get("hair", Color("#6b4a2f"))
	var skin: Color = appearance.get("skin", Color("#ffe3cf"))
	var eyes: Color = appearance.get("eyes", Color("#3b6fd8"))
	var outfit: Color = appearance.get("outfit", Color("#4f7ac7"))
	var style := int(appearance.get("hair_style", 0))
	if dead:
		hair = hair.lerp(Color("#7d7d88"), 0.75)
		skin = skin.lerp(Color("#9a9aa5"), 0.6)
		outfit = outfit.lerp(Color("#6d6d78"), 0.75)
	# Sfondo
	var bg := StyleBoxFlat.new()
	bg.bg_color = frame.lerp(Color.WHITE, 0.72)
	bg.set_corner_radius_all(int(s * 0.18))
	bg.border_color = frame
	bg.set_border_width_all(maxi(2, int(s * 0.035)))
	draw_style_box(bg, Rect2(Vector2.ZERO, Vector2(s, s)))
	_ellipse(Vector2(s * 0.5, s * 0.42), s * 0.36, s * 0.36, frame.lerp(Color.WHITE, 0.5))
	# Spalle e abito
	_ellipse(Vector2(s * 0.5, s * 1.02), s * 0.36, s * 0.24, outfit)
	_ellipse(Vector2(s * 0.5, s * 0.84), s * 0.07, s * 0.06, skin.darkened(0.08))
	var c := Vector2(s * 0.5, s * 0.5)
	var r := s * 0.27
	# Capelli dietro
	_ellipse(c + Vector2(0, -r * 0.12), r * 1.14, r * 1.08, hair.darkened(0.12))
	match style:
		0: _ellipse(c + Vector2(r * 1.0, -r * 0.2), r * 0.32, r * 0.5, hair.darkened(0.08))
		2:
			draw_rect(Rect2(c + Vector2(-r * 1.1, -r * 0.1), Vector2(r * 2.2, r * 1.25)), hair.darkened(0.12))
		3:
			_ellipse(c + Vector2(-r * 0.95, -r * 0.85), r * 0.34, r * 0.34, hair)
			_ellipse(c + Vector2(r * 0.95, -r * 0.85), r * 0.34, r * 0.34, hair)
	# Volto
	_ellipse(c + Vector2(0, r * 0.08), r * 0.94, r * 0.9, skin)
	# Frangia
	var bangs := PackedVector2Array([
		c + Vector2(-r * 1.05, r * 0.05), c + Vector2(-r * 1.0, -r * 0.65), c + Vector2(-r * 0.4, -r * 1.05),
		c + Vector2(r * 0.4, -r * 1.05), c + Vector2(r * 1.0, -r * 0.65), c + Vector2(r * 1.05, r * 0.05),
		c + Vector2(r * 0.8, -r * 0.2), c + Vector2(r * 0.55, -r * 0.05), c + Vector2(r * 0.35, -r * 0.35),
		c + Vector2(0.0, -r * 0.1), c + Vector2(-r * 0.3, -r * 0.38), c + Vector2(-r * 0.55, -r * 0.05), c + Vector2(-r * 0.8, -r * 0.22),
	])
	draw_colored_polygon(bangs, hair)
	if style == 1:
		for i in 3:
			var x := -r * 0.5 + i * r * 0.5
			draw_colored_polygon(PackedVector2Array([c + Vector2(x - r * 0.25, -r * 0.85), c + Vector2(x, -r * 1.45), c + Vector2(x + r * 0.25, -r * 0.85)]), hair)
	_ellipse(c + Vector2(-r * 0.25, -r * 0.7), r * 0.22, r * 0.08, hair.lightened(0.35))
	# Occhi grandi
	for side in [-1.0, 1.0]:
		var e := c + Vector2(r * 0.4 * side, r * 0.22)
		if dead:
			draw_line(e + Vector2(-r * 0.14, -r * 0.1), e + Vector2(r * 0.14, r * 0.1), Color("#3a3a46"), maxf(1.5, s * 0.025))
			draw_line(e + Vector2(r * 0.14, -r * 0.1), e + Vector2(-r * 0.14, r * 0.1), Color("#3a3a46"), maxf(1.5, s * 0.025))
			continue
		_ellipse(e, r * 0.19, r * 0.26, Color("#221d33"))
		_ellipse(e + Vector2(0, r * 0.05), r * 0.14, r * 0.18, eyes)
		_ellipse(e + Vector2(-r * 0.06, -r * 0.08), r * 0.06, r * 0.07, Color.WHITE)
		_ellipse(c + Vector2(r * 0.62 * side, r * 0.5), r * 0.14, r * 0.07, Color(1.0, 0.55, 0.62, 0.55))
	draw_arc(c + Vector2(0, r * 0.52), r * 0.12, 0.3, PI - 0.3, 10, Color("#a5525e"), maxf(1.2, s * 0.018))
	# Stemma del ruolo
	var badge_c := Vector2(s * 0.84, s * 0.84)
	_ellipse(badge_c, s * 0.12, s * 0.12, Color("#24315a"))
	var icon := str(GameState.ROLES.get(role, {}).get("icon", "?")) if is_instance_valid(GameState) else "?"
	var font := UIKit.head_font()
	var fs := int(s * 0.15)
	var text_size := font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, badge_c + Vector2(-text_size.x * 0.5, fs * 0.36), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if dead:
		var veil := StyleBoxFlat.new()
		veil.bg_color = Color(0.15, 0.13, 0.22, 0.35)
		veil.set_corner_radius_all(int(s * 0.18))
		draw_style_box(veil, Rect2(Vector2.ZERO, Vector2(s, s)))
