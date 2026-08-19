extends Control

const BattleViewScript := preload("res://scripts/battle_view.gd")
const HeroPortraitScript := preload("res://scripts/hero_portrait.gd")
const BaseHubScript := preload("res://scripts/base/base_hub.gd")
const NexusBackground := preload("res://assets/backgrounds/nexus_waiting_room.png")
const SummonBackground := preload("res://assets/backgrounds/summon_rift.png")

const BG := Color("#0b0f1a")
const BG_SOFT := Color("#101625")
const PANEL := Color("#151b2a")
const PANEL_ALT := Color("#1b2436")
const LINE := Color("#3a4255")
const TEXT := Color("#f5f7fb")
const MUTED := Color("#9da7b8")
const FAINT := Color("#6e778a")
const AMBER := Color("#f0c75e")
const CYAN := Color("#66d9ff")
const BLUE := Color("#4e7cff")
const GREEN := Color("#39c5bb")
const RED := Color("#ff4d5a")
const VIOLET := Color("#9a6bff")

var current_view := "hub"
var selected_floor := 1
var selected_hero_id := ""
var last_summon: Array = []
var merge_selected_ids: Array[String] = []

var shell: VBoxContainer
var main_row: HBoxContainer
var sidebar_panel: PanelContainer
var base_hub
var brand_button: Button
var content_scroll: ScrollContainer
var content: VBoxContainer
var resource_values: Dictionary = {}
var floor_badge: Label
var roster_badge: Label
var party_badge: Label
var nav_buttons: Dictionary = {}
var toast_layer: VBoxContainer
var battle_view: BattleView

func _ready() -> void:
	_build_theme()
	_build_shell()
	GameState.state_changed.connect(_on_state_changed)
	_render()
	if not bool(GameState.data.tutorial_seen):
		await get_tree().create_timer(0.25).timeout
		_show_onboarding()

func _build_theme() -> void:
	var new_theme := Theme.new()
	new_theme.default_font_size = 14
	new_theme.set_color("font_color", "Label", TEXT)
	new_theme.set_color("font_color", "Button", TEXT)
	new_theme.set_color("font_hover_color", "Button", Color.WHITE)
	new_theme.set_color("font_disabled_color", "Button", FAINT)
	new_theme.set_color("font_color", "RichTextLabel", TEXT)
	new_theme.set_stylebox("normal", "Button", _box(PANEL_ALT, LINE, 1, 3, 12))
	new_theme.set_stylebox("hover", "Button", _box(Color("#222f49"), CYAN.darkened(0.18), 1, 3, 12))
	new_theme.set_stylebox("pressed", "Button", _box(Color("#121a2b"), BLUE, 1, 3, 12))
	new_theme.set_stylebox("disabled", "Button", _box(Color("#101522"), Color("#2a3140"), 1, 3, 12))
	new_theme.set_stylebox("panel", "PanelContainer", _box(PANEL, LINE, 1, 3, 12))
	new_theme.set_stylebox("background", "ProgressBar", _box(Color("#080c11"), Color.TRANSPARENT, 0, 0, 0))
	new_theme.set_stylebox("fill", "ProgressBar", _box(CYAN, Color.TRANSPARENT, 0, 0, 0))
	theme = new_theme

func _box(color: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 0, padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	shell = VBoxContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)
	add_child(shell)
	_build_topbar()

	main_row = HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 0)
	shell.add_child(main_row)
	base_hub = BaseHubScript.new()
	base_hub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_hub.size_flags_vertical = Control.SIZE_EXPAND_FILL
	base_hub.facility_requested.connect(_open_hub_facility)
	base_hub.hub_toast_requested.connect(_on_hub_toast)
	main_row.add_child(base_hub)

	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_row.add_child(content_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 34)
	content_scroll.add_child(margin)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)

	toast_layer = VBoxContainer.new()
	toast_layer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toast_layer.offset_left = -380
	toast_layer.offset_right = -18
	toast_layer.offset_top = 82
	toast_layer.offset_bottom = 400
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_theme_constant_override("separation", 8)
	add_child(toast_layer)

func _build_topbar() -> void:
	var top_panel := PanelContainer.new()
	top_panel.custom_minimum_size.y = 70
	top_panel.add_theme_stylebox_override("panel", _box(Color("#090e14"), LINE, 1, 0, 10))
	shell.add_child(top_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top_panel.add_child(row)
	brand_button = Button.new()
	brand_button.text = "R  RIFTWARD\n    THE LAST ASCENT"
	brand_button.custom_minimum_size.x = 235
	brand_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	brand_button.add_theme_color_override("font_color", AMBER)
	brand_button.add_theme_font_size_override("font_size", 15)
	brand_button.flat = true
	brand_button.pressed.connect(_set_view.bind("hub"))
	row.add_child(brand_button)
	var online := Label.new()
	online.text = "◆  DEV BUILD // RISORSE ∞"
	online.add_theme_color_override("font_color", Color("#ffb45f"))
	online.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(online)
	row.add_child(_resource_capsule("gold", "◉", "ORO", AMBER, Color("#4a3514")))
	row.add_child(_resource_capsule("gems", "◆", "GEMME", CYAN, Color("#123b42")))
	row.add_child(_resource_capsule("stones", "✦", "PIETRE", VIOLET, Color("#302450")))
	var settings := Button.new()
	settings.text = "IMPOSTAZIONI"
	settings.pressed.connect(_show_settings)
	row.add_child(settings)

func _resource_capsule(key: String, icon_text: String, title: String, color: Color, fill: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(124, 50)
	panel.add_theme_stylebox_override("panel", _box(fill, color.darkened(0.2), 1, 10, 7))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8)
	var icon := Label.new(); icon.text = icon_text; icon.add_theme_color_override("font_color", color); icon.add_theme_font_size_override("font_size", 25); icon.custom_minimum_size.x = 28; icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var stack := VBoxContainer.new(); stack.add_theme_constant_override("separation", -3)
	var name := Label.new(); name.text = title; name.add_theme_color_override("font_color", color.lightened(0.15)); name.add_theme_font_size_override("font_size", 9)
	var value := Label.new(); value.text = "∞"; value.add_theme_color_override("font_color", Color.WHITE); value.add_theme_font_size_override("font_size", 18)
	stack.add_child(name); stack.add_child(value); row.add_child(icon); row.add_child(stack); panel.add_child(row)
	resource_values[key] = value
	return panel

func _build_sidebar(parent: HBoxContainer) -> void:
	sidebar_panel = PanelContainer.new()
	sidebar_panel.custom_minimum_size.x = 190
	sidebar_panel.add_theme_stylebox_override("panel", _box(Color("#0a0f15"), LINE, 1, 0, 10))
	parent.add_child(sidebar_panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 5)
	sidebar_panel.add_child(side)
	var nav_data := [
		["hub", "NEXUS", "N"], ["tower", "TORRE", "T"], ["heroes", "EROI", "H"], ["squad", "SQUADRA", "P"],
		["summon", "EVOCA", "E"], ["base", "BASE", "B"], ["shop", "SHOP", "€"], ["archive", "ARCHIVIO", "A"], ["dev", "DEV / QA", "⚙"],
	]
	for item in nav_data:
		var button := Button.new()
		button.text = "%s    %s" % [item[2], item[1]]
		button.custom_minimum_size.y = 48
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_set_view.bind(item[0]))
		side.add_child(button)
		nav_buttons[item[0]] = button
		if item[0] == "tower": floor_badge = _badge(); button.add_child(floor_badge)
		elif item[0] == "heroes": roster_badge = _badge(); button.add_child(roster_badge)
		elif item[0] == "squad": party_badge = _badge(); button.add_child(party_badge)
		elif item[0] == "shop":
			var free := _badge(); free.text = "FREE"; free.add_theme_color_override("font_color", GREEN); button.add_child(free)
		elif item[0] == "dev":
			var dev_badge := _badge(); dev_badge.text = "ON"; dev_badge.add_theme_color_override("font_color", Color("#ffb45f")); button.add_child(dev_badge)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var master_panel := PanelContainer.new()
	master_panel.add_theme_stylebox_override("panel", _box(BG_SOFT, LINE, 1, 2, 12))
	var master := Label.new()
	master.text = "MASTER\nAster\nRANK E"
	master.add_theme_color_override("font_color", AMBER)
	master_panel.add_child(master)
	side.add_child(master_panel)

func _badge() -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	label.offset_left = -52
	label.offset_right = -8
	label.offset_top = -10
	label.offset_bottom = 10
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", FAINT)
	label.add_theme_font_size_override("font_size", 10)
	return label

func _on_state_changed() -> void:
	_update_chrome()
	_render()

func _set_view(view: String) -> void:
	current_view = view
	if view == "tower": selected_floor = clampi(int(GameState.data.world.current_floor), 1, int(GameState.data.world.max_floor))
	_render()
	content_scroll.scroll_vertical = 0

func _clear_content() -> void:
	for child in content.get_children(): child.queue_free()

func _render() -> void:
	_update_chrome()
	_clear_content()
	var showing_hub := current_view == "hub"
	content_scroll.visible = not showing_hub
	base_hub.visible = showing_hub
	if showing_hub:
		base_hub.refresh_state()
		return
	if current_view == "hub": _render_hub()
	elif current_view == "tower": _render_tower()
	elif current_view == "heroes": _render_heroes()
	elif current_view == "hero": _render_hero_detail()
	elif current_view == "squad": _render_squad()
	elif current_view == "summon": _render_summon()
	elif current_view == "merge": _render_merge()
	elif current_view == "base": _render_base()
	elif current_view == "shop": _render_shop()
	elif current_view == "archive": _render_archive()
	elif current_view == "dev": _render_dev()

func _open_hub_facility(view_id: String) -> void:
	if view_id.is_empty(): return
	_set_view(view_id)

func _on_hub_toast(title_text: String, message: String, tone: String) -> void:
	_toast(title_text, message, tone)

func _update_chrome() -> void:
	if resource_values.is_empty(): return
	resource_values.gold.text = GameState.display_resource("gold")
	resource_values.gems.text = GameState.display_resource("gems")
	resource_values.stones.text = GameState.display_resource("stones")
	if is_instance_valid(brand_button):
		brand_button.text = "R  RIFTWARD\n    THE LAST ASCENT" if current_view == "hub" else "←  TORNA ALLA BASE\n    %s" % current_view.to_upper()
	if is_instance_valid(floor_badge): floor_badge.text = "%02d" % int(GameState.data.world.current_floor)
	if is_instance_valid(roster_badge): roster_badge.text = str(GameState.get_alive_heroes().size())
	if is_instance_valid(party_badge): party_badge.text = "%d/5" % GameState.get_party().filter(func(hero): return not hero.is_empty()).size()
	for view in nav_buttons:
		var button: Button = nav_buttons[view]
		button.modulate = Color.WHITE if view == current_view else Color(0.74, 0.78, 0.81)

func _screen_header(eyebrow: String, title: String, description: String, actions: Array = []) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var eye := Label.new(); eye.text = eyebrow.to_upper(); eye.add_theme_color_override("font_color", AMBER); eye.add_theme_font_size_override("font_size", 11)
	var heading := Label.new(); heading.text = title.to_upper(); heading.add_theme_font_size_override("font_size", 36); heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var body := Label.new(); body.text = description; body.add_theme_color_override("font_color", MUTED); body.add_theme_font_size_override("font_size", 13); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(eye); text_box.add_child(heading); text_box.add_child(body)
	row.add_child(text_box)
	if not actions.is_empty():
		var action_box := HBoxContainer.new()
		action_box.alignment = BoxContainer.ALIGNMENT_END
		for action in actions: action_box.add_child(_action_button(action[0], action[1], action[2] if action.size() > 2 else "secondary"))
		row.add_child(action_box)
	content.add_child(row)

func _action_button(text: String, callback: Callable, kind: String = "secondary") -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.custom_minimum_size = Vector2(132, 42)
	button.add_theme_font_size_override("font_size", 11)
	if kind == "primary":
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _box(BLUE, BLUE.lightened(0.20), 1, 2, 11))
		button.add_theme_stylebox_override("hover", _box(BLUE.lightened(0.10), CYAN, 1, 2, 11))
	elif kind == "danger":
		button.add_theme_color_override("font_color", Color("#ffaaa5"))
		button.add_theme_stylebox_override("normal", _box(Color("#391a1c"), RED.darkened(0.2), 1, 2, 11))
	button.pressed.connect(callback)
	return button

func _art_banner(texture: Texture2D, height: float, eyebrow: String, title_text: String, subtitle: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = height
	panel.add_theme_stylebox_override("panel", _box(Color("#090d17"), accent.darkened(0.28), 1, 4, 0))
	var canvas := Control.new()
	canvas.custom_minimum_size.y = height
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(canvas)
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.03, 0.08, 0.34)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var caption_margin := MarginContainer.new()
	caption_margin.add_theme_constant_override("margin_left", 26)
	caption_margin.add_theme_constant_override("margin_right", 26)
	caption_margin.add_theme_constant_override("margin_top", 22)
	caption_margin.add_theme_constant_override("margin_bottom", 22)
	canvas.add_child(caption_margin)
	caption_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var caption := VBoxContainer.new()
	caption.alignment = BoxContainer.ALIGNMENT_END
	caption.add_theme_constant_override("separation", 3)
	var eye := Label.new()
	eye.text = eyebrow.to_upper()
	eye.add_theme_color_override("font_color", accent)
	eye.add_theme_font_size_override("font_size", 10)
	var heading := Label.new()
	heading.text = title_text.to_upper()
	heading.add_theme_color_override("font_color", TEXT)
	heading.add_theme_font_size_override("font_size", 30)
	var body := Label.new()
	body.text = subtitle
	body.add_theme_color_override("font_color", TEXT.darkened(0.08))
	body.add_theme_font_size_override("font_size", 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_child(eye)
	caption.add_child(heading)
	caption.add_child(body)
	caption_margin.add_child(caption)
	return panel

func _rarity_color(rarity: int) -> Color:
	match rarity:
		1: return Color("#8a94a6")
		2: return Color("#39c5bb")
		3: return Color("#4ba3ff")
		4: return Color("#8f5bff")
		5: return Color("#f4c95d")
		6: return Color("#70eeff")
		7: return Color("#fff2be")
		_: return LINE

func _stat_tile(title: String, value: String, note: String, color: Color = TEXT) -> PanelContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.custom_minimum_size.y = 102
	var box := VBoxContainer.new()
	var a := Label.new(); a.text = title.to_upper(); a.add_theme_color_override("font_color", FAINT); a.add_theme_font_size_override("font_size", 9)
	var b := Label.new(); b.text = value; b.add_theme_color_override("font_color", color); b.add_theme_font_size_override("font_size", 27)
	var c := Label.new(); c.text = note; c.add_theme_color_override("font_color", MUTED); c.add_theme_font_size_override("font_size", 10)
	box.add_child(a); box.add_child(b); box.add_child(c); panel.add_child(box)
	return panel

func _info_panel(title_text: String, body_text: String, title_color: Color = CYAN) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	var title := Label.new(); title.text = title_text; title.add_theme_color_override("font_color", title_color); title.add_theme_font_size_override("font_size", 11)
	var body := Label.new(); body.text = body_text; body.add_theme_color_override("font_color", MUTED); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title); box.add_child(body); panel.add_child(box)
	return panel

func _dev_values(body_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("#0d2228"), CYAN.darkened(0.25), 1, 4, 9))
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 2)
	var title := Label.new(); title.text = "EXTRA DEV · VALORI NASCOSTI"; title.add_theme_color_override("font_color", CYAN); title.add_theme_font_size_override("font_size", 9)
	var body := Label.new(); body.text = body_text; body.add_theme_color_override("font_color", Color("#b9e7ea")); body.add_theme_font_size_override("font_size", 11); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title); box.add_child(body); panel.add_child(box)
	return panel

func _render_hub() -> void:
	_screen_header("Waiting Room // Master Layer", "Il Nexus attende le tue decisioni", "Costruisci condizioni di successo. Nel Rift, gli eroi combatteranno e sceglieranno autonomamente.", [["Riposo roster", _rest_roster]])
	content.add_child(_art_banner(NexusBackground, 286.0, "WAITING ROOM // LIVE", "IL NEXUS", "La base resta concreta e silenziosa; il sistema evidenzia soltanto ciò che richiede una decisione.", CYAN))
	var alive := GameState.get_alive_heroes()
	var fatigue := 0
	for hero in alive: fatigue += int(hero.fatigue)
	var stats := HBoxContainer.new(); stats.add_theme_constant_override("separation", 1)
	stats.add_child(_stat_tile("Avanzamento torre", "%d / 100" % GameState.data.world.completed.size(), "Piano attivo %02d" % int(GameState.data.world.current_floor), AMBER))
	stats.add_child(_stat_tile("Roster operativo", str(alive.size()), "%d nel Memoriale" % GameState.data.memorial.size()))
	stats.add_child(_stat_tile("Fatigue media", "%d%%" % (roundi(float(fatigue) / alive.size()) if not alive.is_empty() else 0), "Nessuna account energy"))
	stats.add_child(_stat_tile("Shop sandbox", "€0,00", "%d articoli riscattati" % GameState.data.shop_history.size(), GREEN))
	content.add_child(stats)

	var stage_record := GameState.get_stage(int(GameState.data.world.current_floor))
	var stage: Dictionary = stage_record.descriptor
	var feature := PanelContainer.new(); feature.custom_minimum_size.y = 285
	feature.add_theme_stylebox_override("panel", _box(Color(stage.color).darkened(0.60), Color(stage.color).lightened(0.1), 1, 4, 28))
	var feature_row := HBoxContainer.new(); feature_row.add_theme_constant_override("separation", 30)
	var copy := VBoxContainer.new(); copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tag := Label.new(); tag.text = "%s // THREAT %d" % [stage.type.to_upper(), stage.threat]; tag.add_theme_color_override("font_color", AMBER)
	var name := Label.new(); name.text = "PIANO %02d · %s" % [stage.floor, stage.name.to_upper()]; name.add_theme_font_size_override("font_size", 28); name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var desc := Label.new(); desc.text = stage.description; desc.add_theme_color_override("font_color", MUTED); desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(tag); copy.add_child(name); copy.add_child(desc); copy.add_spacer(false)
	var buttons := HBoxContainer.new(); buttons.add_child(_action_button("Apri briefing", _open_current_stage, "primary")); buttons.add_child(_action_button("Prepara party", _set_view.bind("squad")))
	copy.add_child(buttons); feature_row.add_child(copy)
	var rift := Control.new(); rift.custom_minimum_size = Vector2(260, 220); rift.draw.connect(_draw_rift.bind(rift, Color(stage.color))); rift.queue_redraw(); feature_row.add_child(rift)
	feature.add_child(feature_row); content.add_child(feature)

	var lower := HBoxContainer.new(); lower.add_theme_constant_override("separation", 14)
	lower.add_child(_quick_card("VALUTA EROI", "Stat, skill, tratti e potential hidden", _set_view.bind("heroes")))
	lower.add_child(_quick_card("FORMAZIONE", "2 Front · 2 Mid · 1 Rear", _set_view.bind("squad")))
	lower.add_child(_quick_card("SHOP GRATUITO", "Catalogo sandbox · nessun pagamento", _set_view.bind("shop"), GREEN))
	content.add_child(lower)
	content.add_child(_reports_panel(5))

func _draw_rift(control: Control, color: Color) -> void:
	var center := control.size / 2.0
	for i in 5:
		var points := PackedVector2Array()
		var radius := 92.0 - i * 15.0
		for p in 6:
			var angle := TAU * p / 6.0 - PI / 2
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		points.append(points[0])
		var draw_color := color.lightened(0.18); draw_color.a = 0.70 - i * 0.10
		control.draw_polyline(points, draw_color, 2.0)

func _quick_card(title: String, note: String, callback: Callable, color: Color = AMBER) -> PanelContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.custom_minimum_size.y = 86
	var button := Button.new(); button.flat = true; button.text = title + "\n" + note; button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.add_theme_color_override("font_color", color); button.pressed.connect(callback)
	panel.add_child(button); return panel

func _reports_panel(limit: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	var heading := Label.new(); heading.text = "RAPPORTI RECENTI"; heading.add_theme_color_override("font_color", AMBER); box.add_child(heading)
	for event in GameState.data.events.slice(0, limit):
		var label := RichTextLabel.new(); label.fit_content = true; label.bbcode_enabled = true
		label.text = "[b]%s[/b]  [color=#657682]%s[/color]\n%s" % [event.title, event.category, event.text]
		box.add_child(label)
	panel.add_child(box)
	return panel

func _render_tower() -> void:
	_screen_header("Missioni persistenti", "Torre del Rift", "Ogni scheda mostra prima il briefing normale del giocatore e, in fondo, le informazioni aggiuntive della modalità DEV.")
	var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 14); grid.add_theme_constant_override("v_separation", 14)
	for floor_index in range(1, 6):
		var stage_record := GameState.get_stage(floor_index)
		var stage: Dictionary = stage_record.descriptor
		var unlocked: bool = floor_index <= int(GameState.data.world.max_floor) or bool(GameState.data.dev.all_content)
		var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(400, 300); panel.add_theme_stylebox_override("panel", _box(Color(stage.color).darkened(0.68), Color(stage.color), 1, 4, 18))
		var box := VBoxContainer.new()
		var title := Label.new(); title.text = "PIANO %02d // %s" % [floor_index, stage.name.to_upper()]; title.add_theme_font_size_override("font_size", 21); title.add_theme_color_override("font_color", AMBER if unlocked else FAINT); box.add_child(title)
		var status_text := "COMPLETATO" if bool(stage_record.cleared) else "DISPONIBILE" if unlocked else "BLOCCATO"
		var status := Label.new(); status.text = "%s  ·  %s  ·  Tentativi %d" % [status_text, stage.type, stage_record.attempts]; status.add_theme_color_override("font_color", GREEN if stage_record.cleared else AMBER if unlocked else FAINT); status.add_theme_font_size_override("font_size", 10); box.add_child(status)
		var meta := Label.new(); meta.text = "%s\n\nOBIETTIVO\n%s\n\n%s" % [stage.biome, stage.objective, stage.description]; meta.add_theme_color_override("font_color", MUTED); meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(meta)
		var threat_value: int = int(stage.get("threat_budget", stage.get("threat", 100)))
		box.add_child(_dev_values("Minaccia %d  ·  Durata %.0fs  ·  Ondate %d" % [threat_value, stage.duration, stage.waves.size()]))
		var deploy := _action_button("Schiera" if unlocked else "Bloccato", _confirm_deployment.bind(floor_index), "primary"); deploy.disabled = not unlocked; box.add_child(deploy)
		panel.add_child(box); grid.add_child(panel)
	content.add_child(grid)

func _open_current_stage() -> void:
	selected_floor = int(GameState.data.world.current_floor)
	_set_view("tower")

func _render_heroes() -> void:
	_screen_header("Roster completo + Extra DEV", "Roster eroi", "Le schede mostrano lo stato normale dell'eroe; il riquadro azzurro aggiunge soltanto i valori normalmente nascosti.")
	var grid := GridContainer.new(); grid.columns = 3; grid.add_theme_constant_override("h_separation", 12); grid.add_theme_constant_override("v_separation", 12)
	for hero in GameState.data.heroes: grid.add_child(_hero_card(hero))
	content.add_child(grid)

func _hero_card(hero: Dictionary) -> PanelContainer:
	var rarity := int(hero.current_rarity)
	var rarity_color := _rarity_color(rarity)
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(285, 276)
	panel.add_theme_stylebox_override("panel", _box(Color("#101522f2"), rarity_color, 3 if rarity >= 6 else 2 if rarity >= 4 else 1, 5, 12))
	var box := VBoxContainer.new(); var row := HBoxContainer.new()
	var portrait := HeroPortraitScript.new(); portrait.setup(hero); row.add_child(portrait)
	var text := VBoxContainer.new(); text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Label.new(); name.text = hero.name.to_upper(); name.add_theme_font_size_override("font_size", 17); name.add_theme_color_override("font_color", RED if hero.state != "ALIVE" else TEXT); text.add_child(name)
	var role := Label.new(); role.text = "%s · %s · Lv.%d" % [GameState.stars(hero.current_rarity), hero.role, hero.level]; role.add_theme_color_override("font_color", rarity_color); text.add_child(role)
	var normal := Label.new(); normal.text = "Potenza %s\nMorale %d  ·  Fatigue %d\n%s" % [GameState.format_number(GameState.hero_power(hero)), hero.morale, hero.fatigue, "Caduto" if hero.state != "ALIVE" else "Operativo"]; normal.add_theme_color_override("font_color", MUTED); normal.add_theme_font_size_override("font_size", 10); text.add_child(normal)
	var growth_label := "Eccezionale" if float(hero.growth) >= 4.7 else "Alta" if float(hero.growth) >= 4.2 else "Normale"
	row.add_child(text); box.add_child(row)
	box.add_child(_dev_values("Potenziale %d/100  ·  Crescita %s\nCoraggio %d  ·  Disciplina %d" % [hero.potential, growth_label, hero.personality.courage, hero.personality.discipline]))
	var open := Button.new(); open.text = "APRI DOSSIER"; open.pressed.connect(_open_hero.bind(hero.id)); box.add_child(open)
	panel.add_child(box); return panel

func _open_hero(hero_id: String) -> void:
	selected_hero_id = hero_id
	_set_view("hero")

func _render_hero_detail() -> void:
	var hero := GameState.hero_by_id(selected_hero_id)
	if hero.is_empty(): _set_view("heroes"); return
	var in_party: bool = GameState.data.party.has(hero.id)
	_screen_header("Dossier eroe", hero.name, "%s · %s" % [hero.origin, hero.profession], [["Roster", _set_view.bind("heroes")], ["Rimuovi party" if in_party else "Aggiungi party", _toggle_party.bind(hero.id)]])
	var derived := GameState.derived_stats(hero)
	var overview := HBoxContainer.new(); overview.add_theme_constant_override("separation", 8)
	overview.add_child(_stat_tile("Livello e rarità", "Lv.%d  %s" % [hero.level, GameState.stars(hero.current_rarity)], "%s · %s" % [hero.role, hero.state], AMBER))
	overview.add_child(_stat_tile("Potenza", GameState.format_number(GameState.hero_power(hero)), "HP %d · ATK %.0f" % [derived.max_hp, derived.attack], AMBER))
	overview.add_child(_stat_tile("Morale", "%d / 100" % hero.morale, "stato mentale", GREEN if hero.morale >= 60 else RED))
	overview.add_child(_stat_tile("Fatigue", "%d / 100" % hero.fatigue, "stanchezza persistente", GREEN if hero.fatigue < 50 else RED))
	content.add_child(overview)

	var core_stats := HBoxContainer.new(); core_stats.add_theme_constant_override("separation", 8)
	core_stats.add_child(_stat_tile("Forza", str(hero.stats.str), "danno fisico"))
	core_stats.add_child(_stat_tile("Intelletto", str(hero.stats.int), "magia e supporto"))
	core_stats.add_child(_stat_tile("Stamina", str(hero.stats.sta), "HP e difesa"))
	core_stats.add_child(_stat_tile("Agilità", str(hero.stats.agi), "precisione ed evasione"))
	content.add_child(core_stats)

	var combat_stats := "HP massimi %d  ·  Attacco %.1f  ·  Magia %.1f  ·  Difesa %.1f\nPrecisione %.1f%%  ·  Evasione %.1f%%  ·  Critico %.1f%%  ·  Blocco %d" % [derived.max_hp, derived.attack, derived.magic, derived.defense, derived.accuracy, derived.evasion, derived.crit, derived.block]
	content.add_child(_info_panel("STATISTICHE DI COMBATTIMENTO", combat_stats, AMBER))

	var skill_lines := []
	for skill in hero.skills: skill_lines.append("%s Lv.%d" % [skill.name, skill.level])
	var equipment_text := "Arma: %s [%s]\nSecondaria: %s [%s]\nArmatura: %s [%s]\n\nAbilità: %s\nTratti: %s\nFerite: %s" % [hero.equipment.main.get("name", "Nessuna"), hero.equipment.main.get("grade", "-"), hero.equipment.sub.get("name", "Nessuna"), hero.equipment.sub.get("grade", "-"), hero.equipment.armor.get("name", "Nessuna"), hero.equipment.armor.get("grade", "-"), " · ".join(skill_lines), ", ".join(hero.traits), "Nessuna" if hero.injuries.is_empty() else ", ".join(hero.injuries)]
	content.add_child(_info_panel("EQUIPAGGIAMENTO, ABILITÀ E STATO", equipment_text, AMBER))

	var assessment_text := "\n".join(hero.assessment)
	if not hero.memories.is_empty(): assessment_text += "\n\nMemoria recente: " + str(hero.memories[0])
	content.add_child(_info_panel("VALUTAZIONE DEL MASTER", assessment_text, AMBER))

	var dev_heading := Label.new(); dev_heading.text = "EXTRA DEV // INFORMAZIONI NORMALMENTE NASCOSTE"; dev_heading.add_theme_color_override("font_color", CYAN); dev_heading.add_theme_font_size_override("font_size", 12); content.add_child(dev_heading)
	var stats := HBoxContainer.new(); stats.add_theme_constant_override("separation", 8)
	stats.add_child(_stat_tile("Potenziale nascosto", "%d / 100" % hero.potential, "DEV REVEAL", CYAN))
	stats.add_child(_stat_tile("Crescita nascosta", "%.2f" % hero.growth, "velocità di crescita", VIOLET))
	stats.add_child(_stat_tile("Aggressività", str(hero.personality.aggression), "scelta dei bersagli", CYAN))
	stats.add_child(_stat_tile("Lealtà", str(hero.personality.loyalty), "tenuta del gruppo", CYAN))
	content.add_child(stats)
	var personality_text := "Coraggio %d  ·  Disciplina %d  ·  Aggressività %d\nAltruismo %d  ·  Compostezza %d  ·  Lealtà %d\n\nTratti: %s\nFerite: %s" % [hero.personality.courage, hero.personality.discipline, hero.personality.aggression, hero.personality.altruism, hero.personality.composure, hero.personality.loyalty, ", ".join(hero.traits), "Nessuna" if hero.injuries.is_empty() else ", ".join(hero.injuries)]
	content.add_child(_dev_values(personality_text))
	var actions := HBoxContainer.new(); actions.add_child(_action_button("Training +1", _train_hero.bind(hero.id), "primary")); actions.add_child(_action_button("Promuovi", _promote_hero.bind(hero.id))); content.add_child(actions)

func _toggle_party(hero_id: String) -> void:
	var index: int = GameState.data.party.find(hero_id)
	if index >= 0: GameState.remove_party(index)
	else: _add_to_first_slot(hero_id)

func _train_hero(hero_id: String) -> void:
	var result := GameState.train_hero(hero_id)
	_toast("Training" if result.ok else "Training bloccato", "Livello aumentato senza consumare risorse (DEV)." if result.ok else result.message, "good" if result.ok else "warn")

func _promote_hero(hero_id: String) -> void:
	var result := GameState.promote_hero(hero_id)
	_toast("Promozione" if result.ok else "Promozione bloccata", "Rarità aumentata." if result.ok else result.message, "good" if result.ok else "warn")

func _render_squad() -> void:
	_screen_header("Formation // 2 Front · 2 Mid · 1 Rear", "Squadra operativa", "Cinque slot persistenti. Usa il roster di riserva per riempire i vuoti.")
	var ready := GameState.party_readiness()
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new(); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in GameState.PARTY_SIZE:
		var hero: Dictionary = GameState.get_party()[i]
		var slot := Button.new(); slot.custom_minimum_size.y = 58; slot.text = "SLOT %d · VUOTO" % (i + 1) if hero.is_empty() else "SLOT %d · %s · %s Lv.%d" % [i + 1, hero.name, hero.role, hero.level]; slot.pressed.connect(GameState.remove_party.bind(i)); left.add_child(slot)
	var reserve_title := Label.new(); reserve_title.text = "RISERVE"; reserve_title.add_theme_color_override("font_color", AMBER); left.add_child(reserve_title)
	var reserve := GridContainer.new(); reserve.columns = 3
	for hero in GameState.get_alive_heroes():
		if GameState.data.party.has(hero.id): continue
		var add := Button.new(); add.text = "%s\n%s · Lv.%d" % [hero.name, hero.role, hero.level]; add.pressed.connect(_add_to_first_slot.bind(hero.id)); reserve.add_child(add)
	left.add_child(reserve); row.add_child(left)
	var analysis := PanelContainer.new(); analysis.custom_minimum_size.x = 320
	var analysis_box := VBoxContainer.new(); var title := Label.new(); title.text = "ANALISI FORMAZIONE"; title.add_theme_color_override("font_color", AMBER); analysis_box.add_child(title)
	var score := Label.new(); score.text = GameState.format_number(ready.score); score.add_theme_font_size_override("font_size", 42); score.add_theme_color_override("font_color", AMBER); analysis_box.add_child(score)
	var grade := Label.new(); grade.text = "POTENZA STIMATA · " + ready.grade; grade.add_theme_color_override("font_color", MUTED); analysis_box.add_child(grade)
	for warning in ready.warnings:
		var warn := Label.new(); warn.text = "! " + warning; warn.add_theme_color_override("font_color", RED); analysis_box.add_child(warn)
	if ready.warnings.is_empty(): var ok := Label.new(); ok.text = "✓ Nessun avviso tattico"; ok.add_theme_color_override("font_color", GREEN); analysis_box.add_child(ok)
	analysis.add_child(analysis_box); row.add_child(analysis); content.add_child(row)

func _add_to_first_slot(hero_id: String) -> void:
	var empty: int = GameState.data.party.find("")
	if empty >= 0: GameState.assign_party(empty, hero_id)
	else: _toast("Party completo", "Rimuovi prima un eroe.", "warn")

func _render_summon() -> void:
	_screen_header("Summoning Hall // Odds disclosed", "Evocazione procedurale", "Ogni pull genera un HeroSeed nuovo. Questa demo non utilizza denaro reale.")
	content.add_child(_art_banner(SummonBackground, 300.0, "RIFT DIMENSIONALE", "RISONANZA DEL NEXUS", "Il colore anticipa il livello di rarità, mentre ogni risultato resta leggibile prima di ogni nuova evocazione.", VIOLET))
	var notice := _info_panel("RARITÀ ENDGAME", "6★ e 7★ esistono nel data model ma non appartengono ai pool standard. Entrano tramite progression endgame e pool Transcendent."); content.add_child(notice)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 16); row.add_child(_summon_banner("normal")); row.add_child(_summon_banner("high")); content.add_child(row)
	if not last_summon.is_empty():
		var heading := Label.new(); heading.text = "ULTIMA RISONANZA"; heading.add_theme_color_override("font_color", AMBER); content.add_child(heading)
		var grid := GridContainer.new(); grid.columns = 5
		for hero in last_summon: grid.add_child(_hero_card(hero))
		content.add_child(grid)

func _summon_banner(pool: String) -> PanelContainer:
	var high := pool == "high"
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.custom_minimum_size.y = 390
	panel.add_theme_stylebox_override("panel", _box(Color("#17142a") if high else Color("#111c2b"), VIOLET if high else CYAN, 2, 4, 24))
	var box := VBoxContainer.new()
	var eye := Label.new(); eye.text = "HIGH-GRADE RESONANCE" if high else "COMMON RESONANCE"; eye.add_theme_color_override("font_color", VIOLET if high else CYAN); box.add_child(eye)
	var title := Label.new(); title.text = "GIURAMENTO ASTRALE" if high else "RICHIAMO DEL NEXUS"; title.add_theme_font_size_override("font_size", 27); box.add_child(title)
	var rates := Label.new(); rates.text = "3★  93,5%%\n4★  5,5%%\n5★  1,0%%" % [] if high else "1★  78%%\n2★  19%%\n3★  3%%" % []; rates.add_theme_color_override("font_color", MUTED); rates.add_theme_font_size_override("font_size", 16); box.add_child(rates)
	if high:
		var pity := Label.new(); pity.text = "PITY 5★  %d / 100\nSoft pity dal pull 70 · hard pity al 100" % int(GameState.data.pity.high); pity.add_theme_color_override("font_color", AMBER); box.add_child(pity)
	box.add_spacer(false)
	var buttons := HBoxContainer.new(); var cost := 500 if high else 10000; var currency := "GEMME" if high else "ORO"
	buttons.add_child(_action_button("1 · %s %s" % [GameState.format_number(cost), currency], _confirm_summon.bind(pool, 1), "primary"))
	buttons.add_child(_action_button("10 · %s %s" % [GameState.format_number(cost * 10), currency], _confirm_summon.bind(pool, 10)))
	box.add_child(buttons); panel.add_child(box); return panel

func _confirm_summon(pool: String, count: int) -> void:
	var high := pool == "high"; var total := (500 if high else 10000) * count
	var rates := "3★ 93,5% · 4★ 5,5% · 5★ 1,0%" if high else "1★ 78% · 2★ 19% · 3★ 3%"
	_confirm("EVOCAZIONE // PROBABILITÀ DICHIARATE", "Costo: %s %s\n\nProbabilità: %s\n\nOgni risultato usa un HeroSeed nuovo. Nessun pagamento reale." % [GameState.format_number(total), "Gemme" if high else "Oro", rates], _execute_summon.bind(pool, count), "EVOCA")

func _execute_summon(pool: String, count: int) -> void:
	var result := GameState.summon(pool, count)
	if result.ok: last_summon = result.heroes; _toast("Risonanza completata", "%d eroi aggiunti al roster." % count, "good")
	else: _toast("Evocazione bloccata", result.message, "warn")

func _render_merge() -> void:
	_screen_header("Merging Center // Sintesi controllata", "Fusione eroi", "Seleziona tre eroi della stessa rarità. Il primo selezionato resta come nucleo; gli altri due vengono consumati.")
	content.add_child(_info_panel("REGOLE DELLA FUSIONE", "Servono esattamente 3 eroi vivi, della stessa rarità e non assegnati al party. Il nucleo sale di una rarità e assorbe parte delle statistiche dei due donatori.", VIOLET))
	var selected_names: Array[String] = []
	for hero_id in merge_selected_ids:
		var selected_hero := GameState.hero_by_id(hero_id)
		if not selected_hero.is_empty(): selected_names.append(str(selected_hero.name))
	var selection := _info_panel("SELEZIONE %d / 3" % merge_selected_ids.size(), " → ".join(selected_names) if not selected_names.is_empty() else "Seleziona per primo l'eroe che vuoi conservare come nucleo.", AMBER)
	content.add_child(selection)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for hero in GameState.get_alive_heroes():
		if GameState.data.party.has(hero.id) or int(hero.current_rarity) >= 7: continue
		grid.add_child(_merge_candidate_card(hero))
	content.add_child(grid)

	var validation: Dictionary = GameState.validate_merge_heroes(merge_selected_ids)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	var merge_button := _action_button("FONDI I TRE EROI", _confirm_merge, "primary")
	merge_button.disabled = not bool(validation.ok)
	action_row.add_child(merge_button)
	action_row.add_child(_action_button("SVUOTA SELEZIONE", _clear_merge_selection))
	content.add_child(action_row)
	if not bool(validation.ok):
		content.add_child(_info_panel("FUSIONE NON PRONTA", str(validation.message), RED))

func _merge_candidate_card(hero: Dictionary) -> PanelContainer:
	var selected := merge_selected_ids.has(str(hero.id))
	var rarity_color := _rarity_color(int(hero.current_rarity))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 150)
	panel.add_theme_stylebox_override("panel", _box(Color("#211936") if selected else Color("#101522"), VIOLET if selected else rarity_color, 3 if selected else 1, 5, 11))
	var button := Button.new()
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "%s%s\n%s · %s · Lv.%d\nPotenza %s" % ["✓ NUCLEO · " if selected and merge_selected_ids[0] == str(hero.id) else "✓ " if selected else "", hero.name, GameState.stars(hero.current_rarity), hero.role, hero.level, GameState.format_number(GameState.hero_power(hero))]
	button.add_theme_color_override("font_color", VIOLET.lightened(0.25) if selected else rarity_color)
	button.pressed.connect(_toggle_merge_candidate.bind(str(hero.id)))
	panel.add_child(button)
	return panel

func _toggle_merge_candidate(hero_id: String) -> void:
	if merge_selected_ids.has(hero_id):
		merge_selected_ids.erase(hero_id)
	elif merge_selected_ids.size() < 3:
		merge_selected_ids.append(hero_id)
	else:
		_toast("Selezione completa", "Puoi fondere al massimo tre eroi alla volta.", "warn")
		return
	_render()

func _clear_merge_selection() -> void:
	merge_selected_ids.clear()
	_render()

func _confirm_merge() -> void:
	var validation: Dictionary = GameState.validate_merge_heroes(merge_selected_ids)
	if not bool(validation.ok):
		_toast("Fusione bloccata", str(validation.message), "warn")
		return
	var names: Array[String] = []
	for hero in validation.heroes: names.append(str(hero.name))
	_confirm("FUSIONE EROI", "%s resterà come nucleo e salirà di rarità.\n\n%s e %s verranno consumati definitivamente." % [names[0], names[1], names[2]], _execute_merge, "FONDI")

func _execute_merge() -> void:
	var result := GameState.merge_heroes(merge_selected_ids)
	if bool(result.ok):
		merge_selected_ids.clear()
		_toast("Fusione completata", "%s ha raggiunto %s." % [result.hero.name, GameState.stars(result.hero.current_rarity)], "good")
	else:
		_toast("Fusione bloccata", str(result.message), "warn")
	_render()

func _render_base() -> void:
	_screen_header("Waiting Room // Facilities", "Base persistente", "Training, recupero, crafting e professioni continuano tra una missione e l'altra.", [["Riposo roster", _rest_roster], ["Commissiona equip", _craft_item, "primary"]])
	var grid := GridContainer.new(); grid.columns = 3; grid.add_theme_constant_override("h_separation", 12); grid.add_theme_constant_override("v_separation", 12)
	var unlocks := {"Smithy": 5, "Workshop": 5, "Archive": 10, "Infirmary": 15, "Synthesis Chamber": 15, "Magic Hall": 25, "Dimension Gate": 50}
	for facility in GameState.data.facilities:
		var level: int = GameState.data.facilities[facility]
		var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(270, 145)
		var box := VBoxContainer.new(); var name := Label.new(); name.text = facility.to_upper(); name.add_theme_color_override("font_color", AMBER if level > 0 else FAINT); name.add_theme_font_size_override("font_size", 17); box.add_child(name)
		var meta := Label.new(); meta.text = "LEVEL %d\nOperativa" % level if level > 0 else "BLOCCATA\nUnlock Floor %d" % unlocks.get(facility, 99); meta.add_theme_color_override("font_color", MUTED); box.add_child(meta)
		if level > 0:
			var use := Button.new(); use.text = "USA"; use.pressed.connect(_use_facility.bind(facility)); box.add_child(use)
		panel.add_child(box); grid.add_child(panel)
	content.add_child(grid)
	var materials_title := Label.new(); materials_title.text = "WAREHOUSE // MATERIALI ∞"; materials_title.add_theme_color_override("font_color", CYAN); materials_title.add_theme_font_size_override("font_size", 13); content.add_child(materials_title)
	var material_grid := GridContainer.new(); material_grid.columns = 6; material_grid.add_theme_constant_override("h_separation", 8)
	var material_meta := {
		"ore": ["⬢", "MINERALE", Color("#9eb2bf")], "leather": ["◒", "PELLE", Color("#c98d65")], "wood": ["♠", "LEGNO", Color("#8eb278")],
		"cores": ["✹", "NUCLEI", VIOLET], "food": ["●", "RAZIONI", AMBER], "medicine": ["✚", "MEDICINE", GREEN],
	}
	for key in material_meta: material_grid.add_child(_material_capsule(key, material_meta[key][0], material_meta[key][1], material_meta[key][2]))
	content.add_child(material_grid)

func _material_capsule(key: String, icon_text: String, title: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(132, 82); panel.add_theme_stylebox_override("panel", _box(color.darkened(0.72), color.darkened(0.15), 1, 5, 9))
	var box := VBoxContainer.new(); box.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := Label.new(); icon.text = icon_text; icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; icon.add_theme_color_override("font_color", color); icon.add_theme_font_size_override("font_size", 22); box.add_child(icon)
	var value := Label.new(); value.text = "∞"; value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; value.add_theme_color_override("font_color", Color.WHITE); value.add_theme_font_size_override("font_size", 20); box.add_child(value)
	var name := Label.new(); name.text = title; name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; name.add_theme_color_override("font_color", color.lightened(0.2)); name.add_theme_font_size_override("font_size", 9); box.add_child(name)
	panel.tooltip_text = "Valore reale nel save: %s" % GameState.format_number(GameState.data.world.materials.get(key, 0)); panel.add_child(box); return panel

func _use_facility(facility: String) -> void:
	if facility == "Summoning Hall": _set_view("summon")
	elif facility == "Synthesis Chamber": _set_view("merge")
	elif facility == "Training Center": _set_view("heroes")
	elif facility == "Lodging": _rest_roster()
	elif facility in ["Armory", "Smithy"]: _craft_item()
	else: _toast(facility, "Il layer completo è predisposto per una milestone successiva.", "info")

func _craft_item() -> void:
	var result := GameState.craft_item()
	if result.ok: _toast("Oggetto creato", "%s [%s] · risorse non consumate (DEV)" % [result.item.name, result.item.grade], "good")
	else: _toast("Forgiatura bloccata", result.message, "warn")

func _render_shop() -> void:
	_screen_header("Sandbox Store // No real payments", "Shop", "Tutti gli articoli costano €0,00. Il checkout è simulato localmente: nessun account, carta, rete o pagamento reale.")
	var warning := _info_panel("SHOP DI PROTOTIPO", "Gli articoli sono riscattabili una volta per world per mantenere leggibile il bilanciamento. Ogni operazione genera una ricevuta SIM nello storico."); content.add_child(warning)
	var grid := GridContainer.new(); grid.columns = 3; grid.add_theme_constant_override("h_separation", 12); grid.add_theme_constant_override("v_separation", 12)
	for product in GameState.SHOP_PRODUCTS:
		grid.add_child(_shop_card(product))
	content.add_child(grid)
	var history_box := PanelContainer.new(); var history := VBoxContainer.new(); var title := Label.new(); title.text = "STORICO RISCATTI"; title.add_theme_color_override("font_color", AMBER); history.add_child(title)
	if GameState.data.shop_history.is_empty(): var empty := Label.new(); empty.text = "Nessun articolo riscattato."; empty.add_theme_color_override("font_color", MUTED); history.add_child(empty)
	else:
		for receipt in GameState.data.shop_history:
			var line := Label.new(); line.text = "%s  ·  %s  ·  %s" % [receipt.price, receipt.name, receipt.transaction]; line.add_theme_color_override("font_color", MUTED); history.add_child(line)
	history_box.add_child(history); content.add_child(history_box)

func _shop_card(product: Dictionary) -> PanelContainer:
	var claimed := int(GameState.data.shop_claims.get(product.id, 0)) >= int(product.limit)
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(285, 230); panel.add_theme_stylebox_override("panel", _box(Color("#142125") if not claimed else Color("#101419"), GREEN.darkened(0.25) if not claimed else LINE, 1, 4, 18))
	var box := VBoxContainer.new()
	var category := Label.new(); category.text = product.category; category.add_theme_color_override("font_color", GREEN); category.add_theme_font_size_override("font_size", 10); box.add_child(category)
	var title := Label.new(); title.text = product.name.to_upper(); title.add_theme_font_size_override("font_size", 20); title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(title)
	var price := Label.new(); price.text = product.price; price.add_theme_font_size_override("font_size", 28); price.add_theme_color_override("font_color", GREEN); box.add_child(price)
	var desc := Label.new(); desc.text = product.description; desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; desc.add_theme_color_override("font_color", MUTED); box.add_child(desc)
	box.add_spacer(false)
	var claim := _action_button("Già riscattato" if claimed else "Riscatta gratis", _confirm_shop.bind(product), "primary"); claim.disabled = claimed; box.add_child(claim)
	panel.add_child(box); return panel

func _confirm_shop(product: Dictionary) -> void:
	_confirm("CHECKOUT SIMULATO // €0,00", "%s\n\n%s\n\nTotale: €0,00\nNessun dato di pagamento verrà richiesto o trasmesso." % [product.name, product.description], _claim_shop.bind(product.id), "RISCATTA €0,00")

func _claim_shop(product_id: String) -> void:
	var result := GameState.claim_shop_product(product_id)
	if result.ok: _toast("Riscatto completato", result.product.name + " · €0,00", "good")
	else: _toast("Riscatto non disponibile", result.message, "warn")

func _render_archive() -> void:
	_screen_header("Event Store // Append-only", "Archivio del Nexus", "Rapporti, transazioni e tombstone rendono leggibili le conseguenze irreversibili.")
	var tabs := TabContainer.new(); tabs.custom_minimum_size.y = 560
	var reports := VBoxContainer.new(); reports.name = "Rapporti"
	for event in GameState.data.events:
		var line := Label.new(); line.text = "%s // %s\n%s" % [event.category, event.title, event.text]; line.add_theme_color_override("font_color", RED if event.tone == "danger" else GREEN if event.tone == "good" else MUTED); line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; reports.add_child(line)
	var ledger := VBoxContainer.new(); ledger.name = "Ledger"
	for entry in GameState.data.ledger:
		var line := Label.new(); line.text = "%s  %s%d  // %s" % [str(entry.currency).to_upper(), "+" if entry.delta >= 0 else "", entry.delta, entry.reason]; line.add_theme_color_override("font_color", GREEN if entry.delta >= 0 else RED); ledger.add_child(line)
	var memorial := VBoxContainer.new(); memorial.name = "Memoriale"
	if GameState.data.memorial.is_empty(): var empty := Label.new(); empty.text = "Il Memoriale è vuoto. Che resti così il più a lungo possibile."; empty.add_theme_color_override("font_color", MUTED); memorial.add_child(empty)
	else:
		for record in GameState.data.memorial:
			var line := Label.new(); line.text = "† %s · Lv.%d · %s\nCaduto al Piano %d: %s" % [record.name, record.level, record.role, record.floor, record.cause]; line.add_theme_color_override("font_color", RED); memorial.add_child(line)
	tabs.add_child(reports); tabs.add_child(ledger); tabs.add_child(memorial); content.add_child(tabs)

func _render_dev() -> void:
	_screen_header("Strumenti di prova", "Pannello sviluppatore", "Risorse infinite e comandi rapidi per provare il gioco senza mostrare dati tecnici.")
	var banner := PanelContainer.new(); banner.add_theme_stylebox_override("panel", _box(Color("#2d1c12"), Color("#ff9a4a"), 2, 5, 18))
	var banner_text := Label.new(); banner_text.text = "⚠ MODALITÀ SVILUPPO ATTIVA\nORO ∞  ·  GEMME ∞  ·  PIETRE ∞  ·  MATERIALI ∞\nI costi rimangono visibili ma non vengono sottratti."; banner_text.add_theme_color_override("font_color", Color("#ffd2a7")); banner_text.add_theme_font_size_override("font_size", 17); banner.add_child(banner_text); content.add_child(banner)
	var metrics := HBoxContainer.new(); metrics.add_theme_constant_override("separation", 8)
	metrics.add_child(_stat_tile("Roster", str(GameState.data.heroes.size()), "%d vivi · %d morti" % [GameState.get_alive_heroes().size(), GameState.data.memorial.size()]))
	metrics.add_child(_stat_tile("Pity high", "%d / 100" % int(GameState.data.pity.high), "soft 70 · hard 100", VIOLET))
	metrics.add_child(_stat_tile("Piani disponibili", "%d / 5" % mini(5, int(GameState.data.world.max_floor)), "sbloccabili per i test", CYAN))
	metrics.add_child(_stat_tile("Shop gratuito", "%d / %d" % [GameState.data.shop_claims.size(), GameState.SHOP_PRODUCTS.size()], "articoli riscattati", GREEN))
	content.add_child(metrics)

	var actions_panel := PanelContainer.new(); var actions := VBoxContainer.new(); var title := Label.new(); title.text = "AZIONI DI TEST"; title.add_theme_color_override("font_color", Color("#ffb45f")); actions.add_child(title)
	var buttons := GridContainer.new(); buttons.columns = 3
	buttons.add_child(_action_button("Sblocca tutto", _dev_unlock_all, "primary"))
	buttons.add_child(_action_button("Ripristina roster", _dev_restore_roster))
	buttons.add_child(_action_button("Genera eroe 5★", _dev_spawn_hero))
	buttons.add_child(_action_button("Pity a 99", _dev_set_pity))
	buttons.add_child(_action_button("Reset shop", _dev_reset_shop))
	buttons.add_child(_action_button("Valida salvataggio", _dev_validate))
	actions.add_child(buttons); actions_panel.add_child(actions); content.add_child(actions_panel)


func _dev_unlock_all() -> void:
	GameState.dev_unlock_all(); _toast("DEV", "Piani e facilities sbloccati.", "good")

func _dev_restore_roster() -> void:
	GameState.dev_restore_roster(); _toast("DEV", "Roster ripristinato e party ricostruito.", "good")

func _dev_spawn_hero() -> void:
	var hero := GameState.dev_spawn_hero(5); _toast("DEV", hero.name + " 5★ aggiunto al roster.", "good")

func _dev_set_pity() -> void:
	GameState.dev_set_pity(99); _toast("DEV", "Prossimo high-grade garantisce il test hard pity.", "good")

func _dev_reset_shop() -> void:
	GameState.dev_reset_shop(); _toast("DEV", "Shop resettato.", "good")

func _dev_validate() -> void:
	var issues := GameState.dev_validate()
	_message("DEV VALIDATION", "Nessuna incoerenza rilevata." if issues.is_empty() else "Problemi rilevati:\n- " + "\n- ".join(issues))

func _rest_roster() -> void:
	var result := GameState.rest_roster()
	if result.ok: _toast("Roster riposato", "%d Fatigue recuperata." % result.recovered, "good")
	else: _toast("Riposo bloccato", result.message, "warn")

func _confirm_deployment(floor_index: int) -> void:
	var stage: Dictionary = GameState.get_stage(floor_index).descriptor
	_confirm("DEPLOYMENT // PERMADEATH ATTIVO", "%s\n\n%s\n\nParty e loadout saranno bloccati. 0 HP registra immediatamente un tombstone e non esiste resurrezione." % [stage.name, stage.objective], _start_battle.bind(floor_index), "ENTRA NEL RIFT")

func _start_battle(floor_index: int) -> void:
	var result := GameState.begin_mission(floor_index)
	if not result.ok: _toast("Deployment bloccato", result.message, "warn"); return
	shell.hide()
	battle_view = BattleViewScript.new()
	battle_view.setup(result.stage, result.party, result.attempt)
	battle_view.hero_died.connect(_on_battle_hero_died)
	battle_view.battle_finished.connect(_on_battle_finished)
	add_child(battle_view)
	battle_view.move_to_front()

func _on_battle_hero_died(hero_id: String, cause: String) -> void:
	GameState.record_death(hero_id, cause)

func _on_battle_finished(result: Dictionary) -> void:
	var resolved := GameState.finalize_mission(result)
	var result_text := "Missione completata.\n%s Oro · %d XP per superstite." % [GameState.format_number(resolved.gold), resolved.xp] if result.victory else "Missione fallita o estrazione completata.\nNessun avanzamento; lo stage resta identico."
	if not resolved.deaths.is_empty(): result_text += "\n\n%d morte/i permanenti registrate nel Memoriale." % resolved.deaths.size()
	battle_view.queue_free(); battle_view = null; shell.show(); current_view = "hub"; _render()
	_message("MISSION RESULT", result_text)

func _confirm(title_text: String, message: String, callback: Callable, confirm_text: String = "CONFERMA") -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	dialog.dialog_text = message
	dialog.ok_button_text = confirm_text
	dialog.cancel_button_text = "ANNULLA"
	dialog.min_size = Vector2i(620, 310)
	dialog.confirmed.connect(_dialog_confirmed.bind(callback, dialog))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _dialog_confirmed(callback: Callable, dialog: Window) -> void:
	callback.call()
	dialog.queue_free()

func _message(title_text: String, message: String) -> void:
	var dialog := AcceptDialog.new(); dialog.title = title_text; dialog.dialog_text = message; dialog.ok_button_text = "CONTINUA"; dialog.min_size = Vector2i(560, 300); dialog.canceled.connect(dialog.queue_free); dialog.confirmed.connect(dialog.queue_free); add_child(dialog); dialog.popup_centered()

func _toast(title_text: String, message: String, tone: String = "info") -> void:
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(350, 66); panel.add_theme_stylebox_override("panel", _box(Color("#101821f5"), RED if tone == "warn" else GREEN if tone == "good" else CYAN, 1, 3, 10))
	var label := Label.new(); label.text = title_text.to_upper() + "\n" + message; label.add_theme_color_override("font_color", TEXT); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; panel.add_child(label); toast_layer.add_child(panel)
	await get_tree().create_timer(3.2).timeout
	if is_instance_valid(panel): panel.queue_free()

func _show_onboarding() -> void:
	_confirm("MASTER ONBOARDING", "PREPARARE. OSSERVARE. CONVIVERE CON LE CONSEGUENZE.\n\n1. Valuta eroi, Fatigue, equip e formazione.\n2. Nel Rift l'IA decide movimento, bersagli e skill.\n3. Stage e memorie persistono; 0 HP è morte permanente.\n\nLo Shop è una sandbox gratuita: tutti i prezzi sono €0,00.", _finish_onboarding, "ASSUMO IL COMANDO")

func _finish_onboarding() -> void:
	GameState.data.tutorial_seen = true
	GameState.save_game()
	_toast("Comando accettato", "Il Piano 1 attende il tuo party.", "good")

func _show_settings() -> void:
	_confirm("IMPOSTAZIONI // WORLD LOCALE", "World: %s\nSeed: %s\nSave: %s\n\nIl salvataggio vive in user:// e non viene inviato in rete. Confermando creerai un nuovo world e perderai il salvataggio corrente." % [GameState.data.world.id, GameState.data.world.seed, GameState.SAVE_PATH], _reset_world, "NUOVO WORLD")

func _reset_world() -> void:
	GameState.new_world()
	current_view = "hub"
	_render()
	_show_onboarding()
