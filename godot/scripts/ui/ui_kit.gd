extends RefCounted
class_name UIKit

## Tema e widget condivisi. Direzione "mista": il mondo 3D resta fantasy,
## l'interfaccia è il Sistema che ha evocato il Master. Pannelli quasi neri,
## cornici sottili con accenti neon (azzurro per la base, magenta per
## l'evocazione, ambra per risorse e azioni importanti), caratteri tecnici
## (Oxanium / Exo 2, licenza SIL OFL).

const FONT_TITLE_FILE := preload("res://assets/fonts/Oxanium.ttf")
const FONT_BODY_FILE := preload("res://assets/fonts/Exo2.ttf")

# Testi
const INK := Color("#e6eef8")
const INK_SOFT := Color("#a9b7cb")
const MUTED := Color("#6f7d94")
# Fondi e linee
const PAPER := Color("#0c1119")
const PAPER_DEEP := Color("#111824")
const PAPER_LINE := Color("#25324a")
const NAVY := Color("#131c2b")
const NAVY_DEEP := Color("#070a10")
# Accenti neon. I nomi storici (GOLD, BRONZE…) restano per compatibilità:
# GOLD è l'ambra di risorse e azioni, BRONZE è la linea azzurra delle cornici.
const CYAN := Color("#46dcf2")
const MAGENTA := Color("#f052c8")
const GOLD := Color("#ffbb4d")
const GOLD_DEEP := Color("#c98a2e")
const BRONZE := Color("#2fb4cf")
const BRONZE_LIGHT := Color("#a3eefa")
const TEAL := Color("#4fe3a3")
const SKY := Color("#4fb9ff")
const ROSE := Color("#ff4f74")
const VIOLET := Color("#b57cff")
const LILAC := Color("#bfe9ff")
const LEAF := Color("#7fd16a")
const WHITE := Color("#ffffff")

static var _title: FontVariation
static var _head: FontVariation
static var _head_medium: FontVariation
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

static func head_font() -> FontVariation:
	if _head == null: _head = _weighted(FONT_TITLE_FILE, 600, 1)
	return _head

static func head_medium() -> FontVariation:
	if _head_medium == null: _head_medium = _weighted(FONT_TITLE_FILE, 500, 1)
	return _head_medium

static func body_font() -> FontVariation:
	if _body == null: _body = _weighted(FONT_BODY_FILE, 450)
	return _body

static func body_bold() -> FontVariation:
	if _body_bold == null: _body_bold = _weighted(FONT_BODY_FILE, 650)
	return _body_bold

static func rarity_color(rarity: int) -> Color:
	match rarity:
		1: return Color("#9aa6b6")
		2: return Color("#4fe3a3")
		3: return Color("#4fb9ff")
		4: return Color("#b57cff")
		5: return Color("#ffbb4d")
		6: return Color("#ff4f74")
		7: return Color("#d9fbff")
		_: return Color("#9aa6b6")

## Nome della rarità come lo mostra il Sistema (cornici e carte).
static func rarity_tag(rarity: int) -> String:
	return ["COMMON", "TRAINED", "RARE", "ELITE", "EPIC", "LEGEND", "TRANSCEND"][clampi(rarity, 1, 7) - 1]

## Colore iridescente per il 7★: scorre lungo lo spettro con il tempo.
static func prism_color(t: float, offset: float = 0.0, value: float = 1.0) -> Color:
	return Color.from_hsv(fposmod(t * 0.12 + offset, 1.0), 0.55, value)

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
			s = OrnateStyle.make(Color(0.06, 0.085, 0.13, 0.96), Color(0.035, 0.05, 0.08, 0.96), Color(BRONZE.r, BRONZE.g, BRONZE.b, 0.8), 12.0, padding)
			s.border_width = 1.2
			s.ornament = OrnateStyle.Ornament.BRONZE
			s.ornament_color = CYAN
			s.inner = Color(CYAN.r, CYAN.g, CYAN.b, 0.10)
			s.inner_inset = 5.0
			s.glow = Color(CYAN.r, CYAN.g, CYAN.b, 0.22)
			s.glow_size = 6.0
			s.shadow = 14.0
		"header":
			s = OrnateStyle.make(Color("#122036"), Color("#0b1320"), Color(CYAN.r, CYAN.g, CYAN.b, 0.45), 8.0, padding)
			s.border_width = 1.0
			s.inner = Color(0, 0, 0, 0)
			s.ornament = OrnateStyle.Ornament.PLATE
			s.ornament_color = CYAN
		"system":
			s = OrnateStyle.make(Color(0.05, 0.09, 0.15, 0.97), Color(0.03, 0.05, 0.09, 0.97), Color("#7fe9fb"), 4.0, padding)
			s.border_width = 1.2
			s.inner = Color(CYAN.r, CYAN.g, CYAN.b, 0.16)
			s.ornament = OrnateStyle.Ornament.SYSTEM
			s.ornament_color = Color("#d6fbff")
			s.glow = Color(CYAN.r, CYAN.g, CYAN.b, 0.45)
			s.glow_size = 9.0
			s.shadow = 10.0
		"card":
			s = OrnateStyle.make(Color("#121a27"), Color("#0d131d"), Color("#26344b"), 5.0, padding)
			s.border_width = 1.0
			s.inner = Color(0, 0, 0, 0)
		"inset":
			s = OrnateStyle.make(Color("#0a0f17"), Color("#080c13"), Color("#1e293b"), 4.0, padding)
			s.border_width = 1.0
			s.inner = Color(0, 0, 0, 0)
		"hud":
			s = OrnateStyle.make(Color(0.05, 0.08, 0.12, 0.88), Color(0.03, 0.05, 0.08, 0.88), Color(CYAN.r, CYAN.g, CYAN.b, 0.55), 8.0, padding)
			s.border_width = 1.0
			s.inner = Color(CYAN.r, CYAN.g, CYAN.b, 0.08)
			s.inner_inset = 3.0
		"plate":
			s = OrnateStyle.make(Color("#0b111b"), Color("#070b12"), Color(CYAN.r, CYAN.g, CYAN.b, 0.7), 10.0, padding)
			s.border_width = 1.0
			s.ornament = OrnateStyle.Ornament.PLATE
			s.ornament_color = CYAN
			s.inner = Color(0, 0, 0, 0)
		_:
			s = OrnateStyle.make(PAPER_DEEP, PAPER, BRONZE, 6.0, padding)
	return s

## Riquadro tinto per avvisi e stati (bordo colorato su fondo scuro).
static func tinted(color: Color, padding: float = 12.0) -> OrnateStyle:
	var s := OrnateStyle.make(color.darkened(0.82).lerp(Color("#0e1520"), 0.4), color.darkened(0.9).lerp(Color("#090d14"), 0.4), Color(color.r, color.g, color.b, 0.75), 5.0, padding)
	s.inner = Color(color.r, color.g, color.b, 0.10)
	s.inner_inset = 3.0
	s.border_width = 1.0
	return s

## [fondo alto, fondo basso, bordo neon]
const BUTTON_KINDS := {
	"primary": [Color("#0f3340"), Color("#0a1f29"), Color("#46dcf2")],
	"gold": [Color("#47300f"), Color("#2a1b08"), Color("#ffbb4d")],
	"navy": [Color("#152132"), Color("#0d1522"), Color("#3f6a8c")],
	"ghost": [Color("#0f1520"), Color("#0a0f17"), Color("#2c3a52")],
	"danger": [Color("#45111f"), Color("#280a12"), Color("#ff4f74")],
	"violet": [Color("#3d1238"), Color("#230a21"), Color("#f052c8")],
	"sky": [Color("#0f2a45"), Color("#0a1a2c"), Color("#4fb9ff")],
}

static func _button_style(top: Color, bottom: Color, edge: Color, state: String) -> OrnateStyle:
	var s := OrnateStyle.make(top, bottom, edge, 6.0, 0.0)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 7
	s.content_margin_bottom = 9
	s.border_width = 1.2
	s.inner_inset = 3.0
	s.inner = Color(edge.r, edge.g, edge.b, 0.14)
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
			s.fill_top = Color("#0e131b")
			s.fill_bottom = Color("#0a0e14")
			s.border = Color("#253041")
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
	theme.set_color("font_disabled_color", "Button", Color("#56627a"))
	var colors: Array = BUTTON_KINDS["navy"]
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "Button", _button_style(colors[0], colors[1], colors[2], state))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PanelContainer", ornate("card"))
	theme.set_stylebox("background", "ProgressBar", box(Color("#070b11"), Color("#22304a"), 1, 2, 0))
	theme.set_stylebox("fill", "ProgressBar", box(TEAL, Color.TRANSPARENT, 0, 2, 0))
	theme.set_stylebox("panel", "TooltipPanel", ornate("system", 8.0))
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_font("font", "TooltipLabel", body_font())
	theme.set_stylebox("grabber", "VScrollBar", box(Color(CYAN.r, CYAN.g, CYAN.b, 0.35), Color.TRANSPARENT, 0, 3, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(Color(CYAN.r, CYAN.g, CYAN.b, 0.6), Color.TRANSPARENT, 0, 3, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(Color(CYAN.r, CYAN.g, CYAN.b, 0.8), Color.TRANSPARENT, 0, 3, 0))
	theme.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 0, 3, 0))
	return theme

static func style_button(button: Button, kind: String = "primary") -> Button:
	var colors: Array = BUTTON_KINDS.get(kind, BUTTON_KINDS["navy"])
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _button_style(colors[0], colors[1], colors[2], state))
	var text_color := INK
	if kind == "gold": text_color = Color("#ffe7bf")
	elif kind == "ghost": text_color = INK_SOFT
	elif kind in ["primary", "sky"]: text_color = Color("#dff8ff")
	elif kind == "violet": text_color = Color("#ffe0f6")
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

static func eyebrow(text: String, color: Color = CYAN) -> Label:
	return label(text.to_upper(), 12, color, head_medium())

static func card(color: Color = PAPER_DEEP, border: Color = PAPER_LINE, radius: int = 6, padding: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var s := OrnateStyle.make(color.lightened(0.02), color.darkened(0.25), border, float(radius), float(padding))
	s.inner = Color(0, 0, 0, 0)
	p.add_theme_stylebox_override("panel", s)
	return p

static func pill(text: String, color: Color, text_color: Color = Color(-1, 0, 0), size: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var s := OrnateStyle.make(color.darkened(0.8), color.darkened(0.86), Color(color.r, color.g, color.b, 0.8), 4.0, 3.0)
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

## Medaglione circolare neon con l'emblema (logo del Master, intestazioni).
static func medal(size: float, color: Color = CYAN) -> Control:
	var m := Control.new()
	m.custom_minimum_size = Vector2(size, size)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.draw.connect(func():
		var c := m.size * 0.5
		var r := minf(m.size.x, m.size.y) * 0.5 - 1.0
		m.draw_circle(c, r, Color("#0a1019"))
		m.draw_arc(c, r - 1.0, 0, TAU, 40, Color(CYAN.r, CYAN.g, CYAN.b, 0.9), 1.4, true)
		m.draw_arc(c, r - 5.0, -0.4, PI - 0.4, 24, Color(CYAN.r, CYAN.g, CYAN.b, 0.35), 1.0, true)
		m.draw_arc(c, r - 5.0, PI + 0.2, TAU - 0.6, 18, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.35), 1.0, true)
		draw_emblem(m, c, r * 0.55, color))
	return m
