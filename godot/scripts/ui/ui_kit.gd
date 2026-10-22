extends RefCounted
class_name UIKit

## Tema e widget condivisi. Direzione: fantasy scuro e adulto.
## Fondi nero-prugna, cornici in bronzo, testi avorio, caratteri con grazie
## (Alegreya / Alegreya SC / Cinzel, licenza SIL OFL).

const FONT_TITLE_FILE := preload("res://assets/fonts/Cinzel.ttf")
const FONT_HEAD_FILE := preload("res://assets/fonts/AlegreyaSC-Bold.ttf")
const FONT_HEAD_MEDIUM_FILE := preload("res://assets/fonts/AlegreyaSC-Medium.ttf")
const FONT_BODY_FILE := preload("res://assets/fonts/Alegreya.ttf")

# Testi
const INK := Color("#ece3d0")
const INK_SOFT := Color("#c2b7a6")
const MUTED := Color("#8f8494")
# Fondi e linee
const PAPER := Color("#141019")
const PAPER_DEEP := Color("#1b1621")
const PAPER_LINE := Color("#45372c")
const NAVY := Color("#1f1829")
const NAVY_DEEP := Color("#0b080e")
# Accenti
const GOLD := Color("#d9ae62")
const GOLD_DEEP := Color("#b08250")
const BRONZE := Color("#9c7448")
const BRONZE_LIGHT := Color("#e2c08a")
const TEAL := Color("#57b38f")
const SKY := Color("#6f9fd8")
const ROSE := Color("#cf4d60")
const VIOLET := Color("#a07fe6")
const LILAC := Color("#d8cbf3")
const LEAF := Color("#6b9a52")
const WHITE := Color("#ffffff")

static var _title: FontVariation
static var _head: Font
static var _head_medium: Font
static var _body: FontVariation
static var _body_bold: FontVariation

static func _weighted(file: FontFile, weight: int, spacing: int = 0) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = file
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	font.variation_opentype = {tag: weight}
	if spacing != 0: font.spacing_glyph = spacing
	return font

static func title_font() -> FontVariation:
	if _title == null: _title = _weighted(FONT_TITLE_FILE, 700, 1)
	return _title

static func head_font() -> Font:
	if _head == null: _head = FONT_HEAD_FILE
	return _head

static func head_medium() -> Font:
	if _head_medium == null: _head_medium = FONT_HEAD_MEDIUM_FILE
	return _head_medium

static func body_font() -> FontVariation:
	if _body == null: _body = _weighted(FONT_BODY_FILE, 500)
	return _body

static func body_bold() -> FontVariation:
	if _body_bold == null: _body_bold = _weighted(FONT_BODY_FILE, 700)
	return _body_bold

static func rarity_color(rarity: int) -> Color:
	match rarity:
		1: return Color("#a9a39a")
		2: return Color("#6fbf86")
		3: return Color("#62a2e3")
		4: return Color("#a97de8")
		5: return Color("#e6b24c")
		6: return Color("#e65872")
		7: return Color("#86ecf2")
		_: return Color("#a9a39a")

static func tone_color(tone: String) -> Color:
	match tone:
		"good": return TEAL
		"warn": return GOLD
		"danger": return ROSE
		_: return LILAC

# =============================================================================
# Stili
# =============================================================================

## Compatibilità: riquadro semplice (usato da barre e piccoli elementi).
static func box(color: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 6, padding: int = 12, shadow: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	style.anti_aliasing = true
	if shadow > 0:
		style.shadow_color = Color(0, 0, 0, 0.45)
		style.shadow_size = shadow
		style.shadow_offset = Vector2(0, shadow * 0.4)
	return style

## Stili decorati per i contenitori principali.
static func ornate(kind: String, padding: float = 14.0) -> OrnateStyle:
	var s: OrnateStyle
	match kind:
		"panel":
			s = OrnateStyle.make(Color("#1a1420"), Color("#0e0a12"), BRONZE, 10.0, padding)
			s.ornament = OrnateStyle.Ornament.BRONZE
			s.inner_inset = 5.0
			s.shadow = 14.0
		"header":
			s = OrnateStyle.make(Color("#2a1f36"), Color("#160f1d"), BRONZE, 8.0, padding)
			s.inner = Color(0, 0, 0, 0)
		"system":
			s = OrnateStyle.make(Color("#2b2140"), Color("#140f1e"), LILAC, 4.0, padding)
			s.border_width = 1.4
			s.inner = Color(LILAC.r, LILAC.g, LILAC.b, 0.25)
			s.ornament = OrnateStyle.Ornament.SYSTEM
			s.ornament_color = Color("#efe7ff")
			s.glow = Color("#b79cff")
			s.glow_size = 9.0
			s.shadow = 10.0
		"card":
			s = OrnateStyle.make(Color("#1d1724"), Color("#141019"), Color("#4d3c2e"), 5.0, padding)
			s.inner = Color(0, 0, 0, 0)
		"inset":
			s = OrnateStyle.make(Color("#100c13"), Color("#0c090f"), Color("#3a2e26"), 4.0, padding)
			s.inner = Color(0, 0, 0, 0)
		"hud":
			s = OrnateStyle.make(Color(0.09, 0.07, 0.11, 0.9), Color(0.05, 0.04, 0.06, 0.9), BRONZE, 8.0, padding)
			s.inner = Color(0.69, 0.51, 0.31, 0.22)
			s.inner_inset = 3.0
		"plate":
			s = OrnateStyle.make(Color("#120e15"), Color("#0b080d"), BRONZE, 10.0, padding)
			s.ornament = OrnateStyle.Ornament.PLATE
			s.inner = Color(0, 0, 0, 0)
		_:
			s = OrnateStyle.make(PAPER_DEEP, PAPER, BRONZE, 6.0, padding)
	return s

## Riquadro tinto per avvisi e stati (bordo colorato su fondo scuro).
static func tinted(color: Color, padding: float = 12.0) -> OrnateStyle:
	var s := OrnateStyle.make(color.darkened(0.78).lerp(Color("#15111a"), 0.35), color.darkened(0.86).lerp(Color("#0e0b11"), 0.4), color.darkened(0.25), 5.0, padding)
	s.inner = Color(0, 0, 0, 0)
	s.border_width = 1.2
	return s

const BUTTON_KINDS := {
	"primary": [Color("#3b2a58"), Color("#211836"), Color("#c9a25f")],
	"gold": [Color("#6c4a24"), Color("#3a2712"), Color("#e8c47e")],
	"navy": [Color("#262030"), Color("#16121c"), Color("#8a6a45")],
	"ghost": [Color("#1a151f"), Color("#110d15"), Color("#5c4836")],
	"danger": [Color("#5c1f2a"), Color("#331018"), Color("#d4806e")],
	"violet": [Color("#3d2b68"), Color("#1f1638"), Color("#c6b2f2")],
	"sky": [Color("#21354d"), Color("#121e2c"), Color("#8fb6e6")],
}

static func _button_style(top: Color, bottom: Color, edge: Color, state: String) -> OrnateStyle:
	var s := OrnateStyle.make(top, bottom, edge, 7.0, 0.0)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 7
	s.content_margin_bottom = 9
	s.inner_inset = 3.0
	s.inner = Color(edge.r, edge.g, edge.b, 0.28)
	match state:
		"hover":
			s.fill_top = top.lightened(0.12)
			s.fill_bottom = bottom.lightened(0.08)
			s.border = edge.lightened(0.25)
			s.glow = Color(edge.r, edge.g, edge.b, 0.55)
			s.glow_size = 6.0
		"pressed":
			s.fill_top = bottom
			s.fill_bottom = top.darkened(0.1)
		"disabled":
			s.fill_top = Color("#1a171c")
			s.fill_bottom = Color("#121014")
			s.border = Color("#3a3236")
			s.inner = Color(0, 0, 0, 0)
	return s

static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "RichTextLabel", INK)
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_font("normal_font", "RichTextLabel", body_font())
	theme.set_font("bold_font", "RichTextLabel", body_bold())
	theme.set_font("font", "Button", head_font())
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", WHITE)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color("#6d6470"))
	var colors: Array = BUTTON_KINDS["navy"]
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "Button", _button_style(colors[0], colors[1], colors[2], state))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PanelContainer", ornate("card"))
	theme.set_stylebox("background", "ProgressBar", box(Color("#0b080d"), Color("#3a2e26"), 1, 2, 0))
	theme.set_stylebox("fill", "ProgressBar", box(TEAL, Color.TRANSPARENT, 0, 2, 0))
	theme.set_stylebox("panel", "TooltipPanel", ornate("system", 8.0))
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_font("font", "TooltipLabel", body_font())
	theme.set_stylebox("grabber", "VScrollBar", box(Color(0.69, 0.51, 0.31, 0.45), Color.TRANSPARENT, 0, 3, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(Color(0.69, 0.51, 0.31, 0.7), Color.TRANSPARENT, 0, 3, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(Color(0.85, 0.68, 0.38, 0.85), Color.TRANSPARENT, 0, 3, 0))
	theme.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 0, 3, 0))
	return theme

static func style_button(button: Button, kind: String = "primary") -> Button:
	var colors: Array = BUTTON_KINDS.get(kind, BUTTON_KINDS["navy"])
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _button_style(colors[0], colors[1], colors[2], state))
	var text_color := INK
	if kind == "gold": text_color = Color("#fff1d6")
	elif kind == "ghost": text_color = INK_SOFT
	for state in ["font_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, text_color)
	button.add_theme_color_override("font_hover_color", WHITE)
	return button

static func button(text: String, callback: Callable, kind: String = "primary", min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 46)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	style_button(b, kind)
	if callback.is_valid(): b.pressed.connect(callback)
	return b

# =============================================================================
# Testi e piccoli widget
# =============================================================================

static func label(text: String, size: int = 16, color: Color = INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null: l.add_theme_font_override("font", font)
	return l

static func heading(text: String, size: int = 28, color: Color = INK) -> Label:
	return label(text, size, color, head_font())

static func title(text: String, size: int = 30, color: Color = INK) -> Label:
	var l := label(text, size, color, title_font())
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

static func para(text: String, size: int = 16, color: Color = INK_SOFT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func eyebrow(text: String, color: Color = GOLD) -> Label:
	return label(text.to_upper(), 12, color, head_medium())

static func card(color: Color = PAPER_DEEP, border: Color = PAPER_LINE, radius: int = 6, padding: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var s := OrnateStyle.make(color.lightened(0.02), color.darkened(0.25), border, float(radius), float(padding))
	s.inner = Color(0, 0, 0, 0)
	p.add_theme_stylebox_override("panel", s)
	return p

static func pill(text: String, color: Color, text_color: Color = Color(-1, 0, 0), size: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var s := OrnateStyle.make(color.darkened(0.62), color.darkened(0.75), color.darkened(0.1), 6.0, 3.0)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.inner = Color(0, 0, 0, 0)
	s.border_width = 1.0
	p.add_theme_stylebox_override("panel", s)
	var tc := color.lightened(0.35) if text_color.r < 0.0 else text_color
	p.add_child(label(text, size, tc, head_medium()))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func bar(value: float, max_value: float, color: Color, height: float = 10.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = max(1.0, max_value)
	p.value = clampf(value, 0.0, max_value)
	p.show_percentage = false
	p.custom_minimum_size.y = height
	p.add_theme_stylebox_override("fill", box(color, Color.TRANSPARENT, 0, 1, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func stat_row(name_text: String, value_text: String, value_color: Color = INK) -> HBoxContainer:
	var row := HBoxContainer.new()
	var n := label(name_text, 14, MUTED)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	row.add_child(label(value_text, 15, value_color, body_bold()))
	return row

static func hsep(height: float = 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func divider() -> Control:
	var d := OrnateDivider.new()
	return d

static func icon(kind: String, size: float = 22.0) -> UIIcon:
	var i := UIIcon.new()
	i.kind = kind
	i.custom_minimum_size = Vector2(size, size)
	return i

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

## Stella dorata a cinque punte (usata da carte e ritratti).
static func star_points(center: Vector2, outer: float, inner_ratio: float = 0.45) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var r := outer if i % 2 == 0 else outer * inner_ratio
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts

static func draw_star(canvas: CanvasItem, center: Vector2, outer: float, color: Color) -> void:
	var pts := star_points(center, outer)
	canvas.draw_colored_polygon(pts, color.darkened(0.35))
	var inner_pts := star_points(center + Vector2(-outer * 0.04, -outer * 0.06), outer * 0.78)
	canvas.draw_colored_polygon(inner_pts, color)
	var shine := PackedVector2Array([center, inner_pts[8], inner_pts[9], inner_pts[0]])
	canvas.draw_colored_polygon(shine, color.lightened(0.35))

## Emblema originale del Nexus: un varco a losanga attraversato da un taglio di luce.
static func draw_emblem(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.62, 0), c + Vector2(0, r), c + Vector2(-r * 0.62, 0)])
	canvas.draw_colored_polygon(diamond, color.darkened(0.35))
	canvas.draw_polyline(OrnateStyle.closed(diamond), color.lightened(0.2), maxf(1.0, r * 0.1), true)
	canvas.draw_line(c + Vector2(-r * 0.25, r * 0.55), c + Vector2(r * 0.25, -r * 0.55), Color(1, 0.97, 0.9, 0.9), maxf(1.0, r * 0.14), true)
	canvas.draw_circle(c, r * 0.16, Color(1, 0.97, 0.9))

## Medaglione circolare in bronzo con l'emblema (logo del Master, intestazioni).
static func medal(size: float, color: Color = GOLD) -> Control:
	var m := Control.new()
	m.custom_minimum_size = Vector2(size, size)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.draw.connect(func():
		var c := m.size * 0.5
		var r := minf(m.size.x, m.size.y) * 0.5 - 1.0
		m.draw_circle(c, r, Color("#4f3a26"))
		m.draw_circle(c, r - 2.0, Color("#140f17"))
		m.draw_arc(c, r - 2.0, 0, TAU, 32, Color("#b08250"), 1.6, true)
		m.draw_arc(c, r - 5.0, 0, TAU, 32, Color(0.69, 0.51, 0.31, 0.35), 1.0, true)
		draw_emblem(m, c, r * 0.55, color))
	return m
