extends RefCounted
class_name UIKit

## Tema e widget condivisi. Palette luminosa da fantasy isekai:
## pannelli avorio con bordi dorati, intestazioni blu notte, accenti turchese.

const FONT_HEAD_FILE := preload("res://assets/fonts/Fredoka.ttf")
const FONT_BODY_FILE := preload("res://assets/fonts/Nunito.ttf")

const INK := Color("#2b2740")
const INK_SOFT := Color("#5d5672")
const MUTED := Color("#8a8299")
const PAPER := Color("#fdf8ec")
const PAPER_DEEP := Color("#f3ead4")
const PAPER_LINE := Color("#e2d3ad")
const GOLD := Color("#e0a93b")
const GOLD_DEEP := Color("#b9822a")
const NAVY := Color("#24315a")
const NAVY_DEEP := Color("#1a2342")
const TEAL := Color("#21a99b")
const SKY := Color("#3f8fe6")
const ROSE := Color("#e45b72")
const VIOLET := Color("#8b67ec")
const LEAF := Color("#5bb357")
const WHITE := Color("#ffffff")

static var _head: FontVariation
static var _body: FontVariation
static var _body_bold: FontVariation

static func _weighted(file: FontFile, weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = file
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	font.variation_opentype = {tag: weight}
	return font

static func head_font() -> FontVariation:
	if _head == null: _head = _weighted(FONT_HEAD_FILE, 600)
	return _head

static func body_font() -> FontVariation:
	if _body == null: _body = _weighted(FONT_BODY_FILE, 600)
	return _body

static func body_bold() -> FontVariation:
	if _body_bold == null: _body_bold = _weighted(FONT_BODY_FILE, 800)
	return _body_bold

static func rarity_color(rarity: int) -> Color:
	match rarity:
		1: return Color("#9aa3b2")
		2: return Color("#3cb878")
		3: return Color("#3f8fe6")
		4: return Color("#9a5cf0")
		5: return Color("#f0a92a")
		6: return Color("#ff5f8f")
		7: return Color("#22d3e6")
		_: return Color("#9aa3b2")

static func tone_color(tone: String) -> Color:
	match tone:
		"good": return TEAL
		"warn": return GOLD_DEEP
		"danger": return ROSE
		_: return SKY

static func box(color: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 14, padding: int = 14, shadow: int = 0) -> StyleBoxFlat:
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
		style.shadow_color = Color(0.08, 0.06, 0.18, 0.28)
		style.shadow_size = shadow
		style.shadow_offset = Vector2(0, shadow * 0.4)
	return style

static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "RichTextLabel", INK)
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_font("normal_font", "RichTextLabel", body_font())
	theme.set_font("bold_font", "RichTextLabel", body_bold())
	theme.set_font("font", "Button", head_font())
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Button", WHITE)
	theme.set_color("font_hover_color", "Button", WHITE)
	theme.set_color("font_pressed_color", "Button", WHITE)
	theme.set_color("font_focus_color", "Button", WHITE)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.6))
	theme.set_stylebox("normal", "Button", _button_box(TEAL))
	theme.set_stylebox("hover", "Button", _button_box(TEAL.lightened(0.12)))
	theme.set_stylebox("pressed", "Button", _button_box(TEAL.darkened(0.15)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "Button", _button_box(Color("#b9b3c4")))
	theme.set_stylebox("panel", "PanelContainer", box(PAPER, PAPER_LINE, 2, 18, 16))
	theme.set_stylebox("background", "ProgressBar", box(Color("#e8e0cc"), Color.TRANSPARENT, 0, 6, 0))
	theme.set_stylebox("fill", "ProgressBar", box(TEAL, Color.TRANSPARENT, 0, 6, 0))
	theme.set_stylebox("panel", "TooltipPanel", box(NAVY_DEEP, GOLD, 1, 8, 8))
	theme.set_color("font_color", "TooltipLabel", WHITE)
	var scroll_grabber := box(Color(0.36, 0.33, 0.45, 0.45), Color.TRANSPARENT, 0, 6, 0)
	theme.set_stylebox("grabber", "VScrollBar", scroll_grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(Color(0.36, 0.33, 0.45, 0.7), Color.TRANSPARENT, 0, 6, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(Color(0.36, 0.33, 0.45, 0.85), Color.TRANSPARENT, 0, 6, 0))
	theme.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.05), Color.TRANSPARENT, 0, 6, 0))
	return theme

static func _button_box(color: Color) -> StyleBoxFlat:
	var style := box(color, color.darkened(0.25), 0, 12, 10, 0)
	style.border_width_bottom = 4
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	return style

static func style_button(button: Button, kind: String = "primary") -> Button:
	var color := TEAL
	match kind:
		"gold": color = GOLD
		"navy": color = NAVY
		"danger": color = ROSE
		"violet": color = VIOLET
		"sky": color = SKY
		"ghost": color = Color("#ece3cc")
	button.add_theme_stylebox_override("normal", _button_box(color))
	button.add_theme_stylebox_override("hover", _button_box(color.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _button_box(color.darkened(0.15)))
	button.add_theme_stylebox_override("disabled", _button_box(Color("#c9c3d2")))
	if kind == "ghost":
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, INK)
	return button

static func button(text: String, callback: Callable, kind: String = "primary", min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 46)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	style_button(b, kind)
	if callback.is_valid(): b.pressed.connect(callback)
	return b

static func label(text: String, size: int = 16, color: Color = INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null: l.add_theme_font_override("font", font)
	return l

static func heading(text: String, size: int = 28, color: Color = INK) -> Label:
	return label(text, size, color, head_font())

static func para(text: String, size: int = 15, color: Color = INK_SOFT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func eyebrow(text: String, color: Color = GOLD_DEEP) -> Label:
	var l := label(text.to_upper(), 12, color, body_bold())
	return l

static func card(color: Color = PAPER_DEEP, border: Color = PAPER_LINE, radius: int = 14, padding: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, border, 2, radius, padding))
	return p

static func pill(text: String, color: Color, text_color: Color = WHITE, size: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var style := box(color, Color.TRANSPARENT, 0, 20, 4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	p.add_theme_stylebox_override("panel", style)
	p.add_child(label(text, size, text_color, body_bold()))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func bar(value: float, max_value: float, color: Color, height: float = 10.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = max(1.0, max_value)
	p.value = clampf(value, 0.0, max_value)
	p.show_percentage = false
	p.custom_minimum_size.y = height
	p.add_theme_stylebox_override("fill", box(color, Color.TRANSPARENT, 0, 6, 0))
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

static func divider() -> ColorRect:
	var r := ColorRect.new()
	r.color = PAPER_LINE
	r.custom_minimum_size.y = 2
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
