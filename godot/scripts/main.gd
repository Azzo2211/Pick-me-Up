extends Control

## Schermata principale: la base 3D occupa tutto lo schermo.
## Toccando un edificio la camera si avvicina e si apre il suo pannello laterale;
## la base resta visibile dietro. Sopra rimane solo un HUD minimo.

const HubViewScript := preload("res://scripts/hub3d/hub_view.gd")
const PanelsScript := preload("res://scripts/ui/facility_panels.gd")
const BattleScript := preload("res://scripts/battle/battle_scene.gd")
const HeroPortraitScript := preload("res://scripts/hero_portrait.gd")

const PANEL_WIDTH := 500.0
const TOP_BAR_HEIGHT := 78.0

var hub: HubView
var hud: Control
var panels: FacilityPanels
var side_panel: PanelContainer
var side_title: Label
var side_subtitle: Label
var side_scroll: ScrollContainer
var side_body: VBoxContainer
var side_footer: VBoxContainer
var current_panel := ""
var modal_layer: Control
var toast_layer: VBoxContainer
var resource_labels: Dictionary = {}
var master_label: Label
var master_sub: Label
var journal_badge: PanelContainer
var journal_badge_label: Label
var hint_label: PanelContainer
var battle: Node
var busy := false
var current_view := "hub"
var _refresh_queued := false
var _last_panel_render := 0.0

func _ready() -> void:
	theme = UIKit.build_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub = HubViewScript.new()
	hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub.building_clicked.connect(_on_building_clicked)
	hub.hero_clicked.connect(open_hero)
	add_child(hub)
	panels = PanelsScript.new(self)
	_build_hud()
	_build_side_panel()
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)
	toast_layer = VBoxContainer.new()
	toast_layer.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_layer.offset_left = -230
	toast_layer.offset_right = 230
	toast_layer.offset_top = TOP_BAR_HEIGHT + 14
	toast_layer.offset_bottom = 420
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_theme_constant_override("separation", 8)
	add_child(toast_layer)
	GameState.state_changed.connect(_queue_refresh)
	GameState.time_ticked.connect(_on_time_ticked)
	GameState.hero_leveled.connect(_on_hero_leveled)
	await get_tree().process_frame
	_refresh_all()
	if not bool(GameState.data.get("tutorial_seen", false)):
		await get_tree().create_timer(0.4).timeout
		_show_onboarding()

# =============================================================================
# HUD
# =============================================================================

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	# Barra superiore
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18
	top.offset_right = -18
	top.offset_top = 14
	top.offset_bottom = TOP_BAR_HEIGHT
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 12)
	hud.add_child(top)
	var master := PanelContainer.new()
	master.add_theme_stylebox_override("panel", UIKit.box(Color(0.1, 0.13, 0.26, 0.82), UIKit.GOLD, 2, 30, 8))
	var master_row := HBoxContainer.new()
	master_row.add_theme_constant_override("separation", 10)
	var emblem := PanelContainer.new()
	emblem.custom_minimum_size = Vector2(44, 44)
	emblem.add_theme_stylebox_override("panel", UIKit.box(UIKit.GOLD, Color.WHITE, 2, 22, 0))
	var emblem_label := UIKit.heading("R", 24, UIKit.NAVY_DEEP)
	emblem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblem.add_child(emblem_label)
	master_row.add_child(emblem)
	var master_text := VBoxContainer.new()
	master_text.add_theme_constant_override("separation", -4)
	master_label = UIKit.heading("Master Aster", 20, Color.WHITE)
	master_sub = UIKit.label("Base Lv.1 · Piano 1", 13, Color("#ffe39a"), UIKit.body_bold())
	master_text.add_child(master_label)
	master_text.add_child(master_sub)
	master_row.add_child(master_text)
	var spacer_m := Control.new(); spacer_m.custom_minimum_size.x = 8; master_row.add_child(spacer_m)
	master.add_child(master_row)
	top.add_child(master)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	top.add_child(_resource_pill("gold", "Oro", UIKit.GOLD))
	top.add_child(_resource_pill("gems", "Gemme", Color("#3fc6f0")))
	top.add_child(_resource_pill("stones", "Pietre", UIKit.VIOLET))
	var materials := _round_button("Materiali", _show_materials, "navy")
	top.add_child(materials)
	# Dock in basso a sinistra
	var dock := HBoxContainer.new()
	dock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dock.offset_left = 18
	dock.offset_top = -76
	dock.offset_bottom = -16
	dock.offset_right = 700
	dock.add_theme_constant_override("separation", 10)
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(dock)
	dock.add_child(_round_button("Eroi", open_panel.bind("roster"), "gold"))
	dock.add_child(_round_button("Squadra", open_panel.bind("gate"), "primary"))
	var journal := _round_button("Diario", _show_journal, "navy")
	journal_badge = UIKit.pill("0", UIKit.ROSE, Color.WHITE, 11)
	journal_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	journal_badge.position = Vector2(-6, -8)
	journal_badge_label = journal_badge.get_child(0)
	journal.add_child(journal_badge)
	dock.add_child(journal)
	dock.add_child(_round_button("Impostazioni", _show_settings, "ghost"))
	# Pulsante ricentra
	var recenter := _round_button("Vista base", _recenter, "ghost")
	recenter.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	recenter.offset_left = -150
	recenter.offset_right = -18
	recenter.offset_top = -66
	recenter.offset_bottom = -18
	hud.add_child(recenter)
	hint_label = UIKit.pill("Tocca un edificio della base per entrarci", Color(0.1, 0.13, 0.26, 0.78), Color.WHITE, 14)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_left = -180
	hint_label.offset_right = 180
	hint_label.offset_top = -64
	hint_label.offset_bottom = -30
	hud.add_child(hint_label)

func _resource_pill(key: String, title: String, color: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	var style := UIKit.box(Color(0.1, 0.13, 0.26, 0.82), color, 2, 26, 6)
	style.content_margin_left = 8
	style.content_margin_right = 16
	pill.add_theme_stylebox_override("panel", style)
	pill.custom_minimum_size.x = 150
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(30, 30)
	dot.add_theme_stylebox_override("panel", UIKit.box(color, Color.WHITE, 2, 15, 0))
	row.add_child(dot)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -5)
	stack.add_child(UIKit.label(title.to_upper(), 10, color.lightened(0.35), UIKit.body_bold()))
	var value := UIKit.heading("0", 19, Color.WHITE)
	stack.add_child(value)
	row.add_child(stack)
	pill.add_child(row)
	resource_labels[key] = value
	return pill

func _round_button(text: String, callback: Callable, kind: String) -> Button:
	var b := UIKit.button(text, callback, kind, 0)
	b.custom_minimum_size.y = 52
	b.add_theme_font_size_override("font_size", 17)
	return b

func _update_hud() -> void:
	for key in resource_labels: resource_labels[key].text = GameState.display_resource(key)
	master_label.text = "Master " + str(GameState.data.world.master_name)
	master_sub.text = "Base Lv.%d · Piano %d%s" % [GameState.base_level(), int(GameState.data.world.current_floor), "  · DEV ∞" if GameState.is_dev_unlimited() else ""]
	var unread := GameState.unread_events()
	journal_badge.visible = unread > 0
	journal_badge_label.text = str(mini(unread, 99))

# =============================================================================
# Pannello laterale
# =============================================================================

func _build_side_panel() -> void:
	side_panel = PanelContainer.new()
	side_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side_panel.offset_left = -PANEL_WIDTH - 16
	side_panel.offset_right = -16
	side_panel.offset_top = TOP_BAR_HEIGHT + 10
	side_panel.offset_bottom = -16
	side_panel.add_theme_stylebox_override("panel", UIKit.box(UIKit.PAPER, UIKit.GOLD, 3, 22, 0, 18))
	add_child(side_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	side_panel.add_child(outer)
	var header := PanelContainer.new()
	var header_style := UIKit.box(UIKit.NAVY, Color.TRANSPARENT, 0, 20, 18)
	header_style.corner_radius_bottom_left = 0
	header_style.corner_radius_bottom_right = 0
	header.add_theme_stylebox_override("panel", header_style)
	var header_row := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -2)
	side_subtitle = UIKit.label("", 13, Color("#ffe39a"), UIKit.body_bold())
	side_title = UIKit.heading("", 28, Color.WHITE)
	side_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(side_subtitle)
	titles.add_child(side_title)
	header_row.add_child(titles)
	var close := UIKit.button("✕", close_panel, "ghost", 46)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(close)
	header.add_child(header_row)
	outer.add_child(header)
	side_scroll = ScrollContainer.new()
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_right", 22)
	side_scroll.add_child(margin)
	side_body = VBoxContainer.new()
	side_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_body.add_theme_constant_override("separation", 12)
	margin.add_child(side_body)
	outer.add_child(side_scroll)
	var footer_margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]: footer_margin.add_theme_constant_override("margin_" + side, 18)
	footer_margin.add_theme_constant_override("margin_top", 6)
	side_footer = VBoxContainer.new()
	footer_margin.add_child(side_footer)
	outer.add_child(footer_margin)
	side_panel.visible = false

func open_panel(id: String) -> void:
	if busy: return
	current_panel = id
	current_view = id
	side_panel.visible = true
	hint_label.visible = false
	if id in GameState.FACILITIES or id == "crystal":
		hub.focus_on(id, PANEL_WIDTH + 16)
	_render_panel(true)
	side_panel.modulate.a = 0.0
	side_panel.offset_left = -PANEL_WIDTH + 30
	side_panel.offset_right = 30
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(side_panel, "modulate:a", 1.0, 0.22)
	tween.tween_property(side_panel, "offset_left", -PANEL_WIDTH - 16, 0.28)
	tween.tween_property(side_panel, "offset_right", -16.0, 0.28)

func close_panel() -> void:
	current_panel = ""
	current_view = "hub"
	side_panel.visible = false
	panels.reset_selection()
	hub.reset_view()

func _render_panel(reset_scroll: bool = false) -> void:
	if current_panel.is_empty() or not side_panel.visible: return
	_last_panel_render = Time.get_ticks_msec() / 1000.0
	var scroll := side_scroll.scroll_vertical
	UIKit.clear(side_body)
	UIKit.clear(side_footer)
	var header := panels.header_for(current_panel)
	side_subtitle.text = header.subtitle
	side_title.text = header.title
	panels.build(current_panel, side_body, side_footer)
	side_footer.get_parent().visible = side_footer.get_child_count() > 0
	if not reset_scroll:
		await get_tree().process_frame
		side_scroll.scroll_vertical = scroll
	else:
		side_scroll.scroll_vertical = 0

func _on_building_clicked(id: String) -> void:
	if busy or not modal_layer.get_children().is_empty(): return
	open_panel(id)

func _recenter() -> void:
	close_panel()

## Compatibilità con i vecchi nomi delle schermate.
func _set_view(view: String) -> void:
	var map := {"hub": "", "tower": "gate", "squad": "gate", "heroes": "roster", "summon": "crystal", "merge": "merging", "base": "crystal", "archive": "journal", "dev": "settings", "shop": "crystal"}
	var target: String = map.get(view, view)
	if target.is_empty(): close_panel()
	elif target == "journal": _show_journal()
	elif target == "settings": _show_settings()
	else: open_panel(target)

# =============================================================================
# Aggiornamenti
# =============================================================================

func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	call_deferred("_refresh_all")

func _refresh_all() -> void:
	_refresh_queued = false
	if battle != null: return
	_update_hud()
	hub.refresh(GameState)
	_render_panel()
	for modal in modal_layer.get_children():
		if modal.has_meta("refresh"): (modal.get_meta("refresh") as Callable).call()

## Il tempo che scorre aggiorna HUD e base subito; il pannello aperto solo ogni pochi
## secondi e mai mentre si sta premendo un pulsante.
func _on_time_ticked() -> void:
	if battle != null: return
	_update_hud()
	hub.refresh(GameState)
	var now := Time.get_ticks_msec() / 1000.0
	if current_panel in ["training", "dormitory", "roster"] and now - _last_panel_render > 4.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_render_panel()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal_layer.get_child_count() > 0:
			close_modal(modal_layer.get_child(modal_layer.get_child_count() - 1))
		elif side_panel.visible and not busy:
			close_panel()
		get_viewport().set_input_as_handled()

func _on_hero_leveled(hero_id: String, level: int) -> void:
	var agent: HubAgent = hub.world.agent_for(hero_id)
	if agent != null: agent.pop_emote("Lv.%d!" % level, 2.5)

# =============================================================================
# Modali, conferme e toast
# =============================================================================

func open_modal(title: String, subtitle: String, content: Control, width: float = 760.0, buttons: Array = [], refresh: Callable = Callable()) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.07, 0.18, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", UIKit.box(UIKit.PAPER, UIKit.GOLD, 3, 22, 0, 24))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var header := PanelContainer.new()
	var header_style := UIKit.box(UIKit.NAVY, Color.TRANSPARENT, 0, 20, 18)
	header_style.corner_radius_bottom_left = 0
	header_style.corner_radius_bottom_right = 0
	header.add_theme_stylebox_override("panel", header_style)
	var header_row := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -2)
	if not subtitle.is_empty(): titles.add_child(UIKit.label(subtitle, 13, Color("#ffe39a"), UIKit.body_bold()))
	titles.add_child(UIKit.heading(title, 26, Color.WHITE))
	header_row.add_child(titles)
	header_row.add_child(UIKit.button("✕", close_modal.bind(root), "ghost", 46))
	header.add_child(header_row)
	box.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = mini(int(size.y * 0.66), 640)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	scroll.add_child(margin)
	var content_holder := VBoxContainer.new()
	content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_holder.add_child(content)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content_holder)
	box.add_child(scroll)
	if not buttons.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 10)
		var bm := MarginContainer.new()
		for side in ["left", "right", "bottom"]: bm.add_theme_constant_override("margin_" + side, 20)
		bm.add_theme_constant_override("margin_top", 4)
		for b in buttons: row.add_child(b)
		bm.add_child(row)
		box.add_child(bm)
	root.set_meta("content_holder", content_holder)
	root.set_meta("scroll", scroll)
	if refresh.is_valid(): root.set_meta("refresh", refresh)
	panel.pivot_offset = Vector2(width * 0.5, 200)
	panel.scale = Vector2(0.94, 0.94)
	panel.modulate.a = 0.0
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.22)
	tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(content):
		scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y + 40.0, size.y * 0.66)
	return root

func close_modal(root: Control) -> void:
	if is_instance_valid(root): root.queue_free()

func close_all_modals() -> void:
	for child in modal_layer.get_children(): child.queue_free()

func confirm(title: String, text: String, ok_text: String, callback: Callable, kind: String = "primary") -> void:
	var holder := VBoxContainer.new()
	holder.add_child(UIKit.para(text, 17, UIKit.INK))
	var modal_ref := []
	var ok := UIKit.button(ok_text, _confirm_ok.bind(modal_ref, callback), kind, 180)
	var cancel := UIKit.button("Annulla", _confirm_cancel.bind(modal_ref), "ghost", 140)
	var modal: Control = await open_modal(title, "", holder, 620, [cancel, ok])
	modal_ref.append(modal)

func _confirm_ok(modal_ref: Array, callback: Callable) -> void:
	if not modal_ref.is_empty(): close_modal(modal_ref[0])
	callback.call()

func _confirm_cancel(modal_ref: Array) -> void:
	if not modal_ref.is_empty(): close_modal(modal_ref[0])

func toast(title: String, message: String, tone: String = "info") -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.box(UIKit.PAPER, UIKit.tone_color(tone), 3, 16, 12, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(UIKit.label(title, 17, UIKit.tone_color(tone).darkened(0.1), UIKit.head_font()))
	if not message.is_empty(): box.add_child(UIKit.para(message, 14, UIKit.INK_SOFT))
	panel.add_child(box)
	toast_layer.add_child(panel)
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_interval(2.8)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	tween.tween_callback(panel.queue_free)

func report(result: Dictionary, ok_title: String, ok_message: String = "") -> void:
	if bool(result.get("ok", false)): toast(ok_title, ok_message, "good")
	else: toast("Non disponibile", str(result.get("message", "")), "warn")

# =============================================================================
# Schede eroe, diario, impostazioni, materiali
# =============================================================================

func open_hero(hero_id: String) -> void:
	if busy: return
	var hero := GameState.hero_by_id(hero_id)
	if hero.is_empty(): return
	var content := VBoxContainer.new()
	var modal_ref := []
	panels.build_dossier(content, hero, modal_ref)
	var refresh := _refresh_dossier.bind(content, hero_id, modal_ref)
	var modal: Control = await open_modal(hero.name, "%s · %s · %s" % [GameState.stars(int(hero.current_rarity)), GameState.role_label(hero.role), GameState.RARITY_NAMES[int(hero.current_rarity)]], content, 880, [], refresh)
	modal_ref.append(modal)

func _refresh_dossier(content: VBoxContainer, hero_id: String, modal_ref: Array) -> void:
	if not is_instance_valid(content): return
	UIKit.clear(content)
	panels.build_dossier(content, GameState.hero_by_id(hero_id), modal_ref)

func _show_journal() -> void:
	var content := VBoxContainer.new()
	panels.build_journal(content)
	GameState.mark_events_read()
	_update_hud()
	await open_modal("Diario della base", "Rapporti, conseguenze e memoriale", content, 780)

func _show_materials() -> void:
	var content := VBoxContainer.new()
	panels.build_materials(content)
	await open_modal("Scorte della base", "Capacità per materiale: %d" % GameState.material_cap(), content, 640)

func _show_settings() -> void:
	var content := VBoxContainer.new()
	panels.build_settings(content)
	var refresh := _refresh_settings.bind(content)
	await open_modal("Impostazioni", "Mondo " + str(GameState.data.world.id), content, 680, [], refresh)

func _refresh_settings(content: VBoxContainer) -> void:
	if not is_instance_valid(content): return
	UIKit.clear(content)
	panels.build_settings(content)

func reset_world() -> void:
	close_all_modals()
	close_panel()
	GameState.new_world()
	_show_onboarding()

func _show_onboarding() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(UIKit.para("Questa isola è la tua base. Gli eroi ci vivono davvero: si allenano, riposano, passeggiano in piazza e partono dal Portale sospeso.", 17, UIKit.INK))
	var steps := [
		["Tocca gli edifici", "Addestramento, Dormitorio, Fusione e Portale si aprono direttamente sulla base."],
		["Prepara la squadra", "Cinque eroi in formazione 2 Front · 2 Mid · 1 Rear. In missione decidono da soli: tu dai solo ordini generali."],
		["Le perdite sono reali", "Un eroe a 0 HP muore per sempre. Riposa, cura e allena prima di salire la Torre."],
		["Fai crescere la base", "Dal Cristallo del Nexus evochi nuovi eroi ed espandi la base: ogni livello aggiunge un piano agli edifici e sblocca nuovi cantieri."],
	]
	for step in steps:
		var card := UIKit.card()
		var v := VBoxContainer.new()
		v.add_child(UIKit.label(step[0], 18, UIKit.NAVY, UIKit.head_font()))
		v.add_child(UIKit.para(step[1], 15))
		card.add_child(v)
		box.add_child(card)
	var modal_ref := []
	var start := UIKit.button("Entra nella base", _finish_onboarding.bind(modal_ref), "gold", 220)
	var modal: Control = await open_modal("Benvenuto nel Nexus", "Riftward · The Last Ascent", box, 720, [start])
	modal_ref.append(modal)

func _finish_onboarding(modal_ref: Array) -> void:
	GameState.data.tutorial_seen = true
	GameState.save_game()
	if not modal_ref.is_empty(): close_modal(modal_ref[0])
	toast("Benvenuto, Master", "Il Piano 1 attende la tua squadra al Portale.", "good")

# =============================================================================
# Missioni
# =============================================================================

func deploy(floor_index: int) -> void:
	var result := GameState.begin_mission(floor_index)
	if not result.ok:
		toast("Partenza bloccata", str(result.message), "warn")
		return
	busy = true
	side_panel.visible = false
	current_panel = ""
	var party_ids := []
	for hero in result.party: party_ids.append(hero.id)
	hub.refresh(GameState)
	hub.focus_on("gate", 0)
	await hub.world.play_deploy(party_ids)
	var fade := ColorRect.new()
	fade.color = Color(1, 1, 1, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.35)
	await tween.finished
	hud.visible = false
	hub.visible = false
	hub.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	battle = BattleScript.new()
	battle.setup(result.stage, result.party, int(result.attempt))
	battle.hero_died.connect(_on_battle_hero_died)
	battle.battle_finished.connect(_on_battle_finished)
	add_child(battle)
	move_child(fade, get_child_count() - 1)
	var tween2 := create_tween()
	tween2.tween_property(fade, "color:a", 0.0, 0.4)
	tween2.tween_callback(fade.queue_free)

func _on_battle_hero_died(hero_id: String, cause: String) -> void:
	GameState.record_death(hero_id, cause)

func _on_battle_finished(result: Dictionary) -> void:
	var resolved := GameState.finalize_mission(result)
	if battle != null:
		battle.queue_free()
		battle = null
	hub.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hub.visible = true
	hud.visible = true
	busy = false
	hub.world.restore_agents()
	_refresh_all()
	hub.reset_view()
	var content := VBoxContainer.new()
	panels.build_mission_result(content, result, resolved)
	await open_modal("Vittoria!" if result.victory else "Missione fallita", "Piano %d · %s" % [int(result.get("floor", 0)), panels.reason_text(str(result.get("reason", "")))], content, 720, [UIKit.button("Torna alla base", close_all_modals, "gold", 220)])
