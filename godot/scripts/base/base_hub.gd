extends Control
class_name BaseHub

signal facility_requested(view_id: String)
signal hub_toast_requested(title: String, message: String, tone: String)

const BuildingScript := preload("res://scripts/base/base_building.gd")
const HeroAgentScript := preload("res://scripts/base/hero_agent.gd")
const HubBackground := preload("res://assets/backgrounds/base_level_1_wide.png")
const SummoningCenterArt := preload("res://assets/buildings/summoning_plaza_connected.png")

const WORLD_SIZE := Vector2(1920, 804)
const MAP_CONTENT_SCALE := Vector2(0.746, 0.542)
const MAP_CONTENT_OFFSET := Vector2(364, 72)
const SUMMONING_ART_POSITION := Vector2(990, 525)
const SUMMONING_ART_SIZE := Vector2(390, 260)
const MAX_VISIBLE_AGENTS := 10
const FOCUS_ZOOM_FACTOR := 1.06
const PANEL := Color("#111827ee")
const LINE := Color("#3a4255")
const TEXT := Color("#f5f7fb")
const MUTED := Color("#9da7b8")
const CYAN := Color("#66d9ff")
const BLUE := Color("#4e7cff")
const VIOLET := Color("#9a6bff")
const AMBER := Color("#f0c75e")

var building_data: Array[BaseBuildingData] = []
var buildings: Array[BaseBuilding] = []
var building_by_id: Dictionary = {}
var hero_agents: Array[BaseHeroAgent] = []
var notification_system := BaseNotificationSystem.new()
var upgrade_system := BuildingUpgradeSystem.new()

var world_root: Control
var camera_center := WORLD_SIZE * 0.5
var camera_zoom := 1.0
var dragging := false
var drag_distance := 0.0
var active_touches: Dictionary = {}
var selected_building: BaseBuilding
var context_panel: PanelContainer
var context_title: Label
var context_meta: Label
var context_description: Label
var context_status: Label
var context_action: Button
var context_secondary_action: Button
var upgrade_action: Button

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_world()
	_build_context_panel()
	_build_overlay_hud()
	resized.connect(_on_resized)
	call_deferred("reset_camera")
	set_process(true)

func _box(color: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 4, padding: int = 12) -> StyleBoxFlat:
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

func _build_world() -> void:
	world_root = Control.new()
	world_root.size = WORLD_SIZE
	world_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(world_root)

	var background := TextureRect.new()
	background.texture = HubBackground
	background.position = Vector2.ZERO
	background.size = WORLD_SIZE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_root.add_child(background)

	var veil := ColorRect.new()
	veil.position = Vector2.ZERO
	veil.size = WORLD_SIZE
	veil.color = Color(0.02, 0.03, 0.08, 0.02)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_root.add_child(veil)

	var summoning_art := TextureRect.new()
	summoning_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	summoning_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	summoning_art.texture = SummoningCenterArt
	summoning_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_root.add_child(summoning_art)
	# Imposta il rettangolo dopo l'ingresso nell'albero: la texture importata non
	# può così imporre temporaneamente le sue dimensioni native (1302×1208).
	summoning_art.position = SUMMONING_ART_POSITION
	summoning_art.size = SUMMONING_ART_SIZE

	_create_building_data()
	_map_building_data_to_wide_background()
	for data in building_data:
		var building: BaseBuilding = BuildingScript.new()
		building.setup(data)
		building.building_selected.connect(_select_building)
		world_root.add_child(building)
		buildings.append(building)
		building_by_id[data.id] = building

	_create_hero_agents()
	refresh_state()

func _slots(center: Vector2, spread := Vector2(55, 28)) -> Array[Vector2]:
	return [
		center + Vector2(-spread.x, 0), center + Vector2(spread.x, 0),
		center + Vector2(0, -spread.y), center + Vector2(0, spread.y),
	]

func _facility_level(key: String, fallback := 1) -> int:
	if key.is_empty(): return fallback
	return maxi(fallback, int(GameState.data.facilities.get(key, fallback)))

func _create_building_data() -> void:
	building_data = [
		BaseBuildingData.create({"id": "plaza", "building_type": "plaza", "display_name": "Nexus Centrale", "description": "Cristallo di comando della Base Lv.1. Qui il Master prepara la squadra e accede agli strumenti di collaudo.", "level": 1, "max_level": 1, "world_position": Vector2(750, 500), "interaction_type": "squad", "secondary_interaction_type": "dev", "secondary_label": "APRI DEV / QA", "visual_variant": "level_one_background", "activity_slots": [Vector2(545, 445), Vector2(560, 490), Vector2(585, 525), Vector2(615, 550)], "navigation_path": [Vector2(520, 460)], "footprint": Vector2(300, 230)}),
		BaseBuildingData.create({"id": "training", "building_type": "training", "state_key": "Training Center", "display_name": "Centro di Addestramento", "description": "Gli eroi provano armi, formazioni e capacità prima delle missioni.", "level": _facility_level("Training Center"), "world_position": Vector2(790, 245), "interaction_type": "heroes", "upgrade_cost": 8000, "visual_variant": "level_one_background", "activity_slots": [Vector2(690, 225), Vector2(750, 210), Vector2(820, 210), Vector2(875, 225)], "navigation_path": [Vector2(520, 460), Vector2(570, 380), Vector2(680, 325), Vector2(790, 285)], "footprint": Vector2(440, 310)}),
		BaseBuildingData.create({"id": "portal", "building_type": "portal", "display_name": "Portale delle Missioni", "description": "Il varco principale verso la Torre. Le squadre si radunano qui prima del dispiegamento.", "level": 1, "max_level": 1, "world_position": Vector2(1375, 193), "interaction_type": "tower", "visual_variant": "level_one_background", "activity_slots": [Vector2(1185, 305), Vector2(1225, 320), Vector2(1265, 340), Vector2(1200, 350)], "navigation_path": [Vector2(520, 460), Vector2(540, 550), Vector2(610, 610), Vector2(900, 610), Vector2(1010, 520), Vector2(1100, 430), Vector2(1215, 330)], "footprint": Vector2(430, 480)}),
		BaseBuildingData.create({"id": "lodgings", "building_type": "lodgings", "state_key": "Lodging", "display_name": "Alloggi degli Eroi", "description": "Riposo, recupero, morale e gestione personale del roster.", "level": _facility_level("Lodging"), "world_position": Vector2(382, 315), "interaction_type": "heroes", "upgrade_cost": 7000, "visual_variant": "level_one_background", "activity_slots": [Vector2(405, 325), Vector2(435, 340), Vector2(465, 355), Vector2(390, 360)], "navigation_path": [Vector2(520, 460), Vector2(485, 405), Vector2(435, 350)], "footprint": Vector2(350, 260)}),
		BaseBuildingData.create({"id": "warehouse", "building_type": "warehouse", "state_key": "Warehouse", "display_name": "Magazzino", "description": "Scorte, materiali, equipaggiamenti, consegne dello shop e registri della cittadella.", "level": _facility_level("Warehouse"), "world_position": Vector2(300, 595), "interaction_type": "shop", "secondary_interaction_type": "archive", "secondary_label": "APRI ARCHIVIO", "upgrade_cost": 6500, "visual_variant": "level_one_background", "activity_slots": [Vector2(405, 525), Vector2(430, 545), Vector2(455, 565), Vector2(390, 575)], "navigation_path": [Vector2(520, 460), Vector2(480, 505), Vector2(425, 545)], "footprint": Vector2(350, 245)}),
		BaseBuildingData.create({"id": "fusion", "building_type": "fusion", "state_key": "Synthesis Chamber", "display_name": "Centro di Fusione", "description": "Tre eroi della stessa rarità vengono fusi: il primo resta come nucleo e sale di una rarità.", "level": _facility_level("Synthesis Chamber"), "world_position": Vector2(745, 775), "interaction_type": "merge", "upgrade_cost": 12000, "visual_variant": "level_one_background", "activity_slots": [Vector2(680, 755), Vector2(725, 770), Vector2(770, 770), Vector2(815, 755)], "navigation_path": [Vector2(520, 460), Vector2(555, 535), Vector2(625, 585), Vector2(690, 625), Vector2(730, 690)], "footprint": Vector2(280, 280)}),
		BaseBuildingData.create({"id": "alchemy", "building_type": "alchemy", "state_key": "Workshop", "display_name": "Centro Alchemico", "description": "Pozioni, reagenti, conversione materiali, crafting e ricerca applicata al Rift.", "level": _facility_level("Workshop"), "world_position": Vector2(1115, 638), "interaction_type": "base", "upgrade_cost": 9500, "visual_variant": "level_one_background", "activity_slots": [Vector2(1015, 545), Vector2(1040, 570), Vector2(1070, 590), Vector2(1100, 600)], "navigation_path": [Vector2(520, 460), Vector2(540, 550), Vector2(610, 610), Vector2(900, 610), Vector2(980, 590), Vector2(1045, 550)], "footprint": Vector2(320, 245)}),
		BaseBuildingData.create({"id": "summoning", "building_type": "summoning", "state_key": "Summoning Hall", "display_name": "Centro Evocativo", "description": "Una piazza rituale bassa, collegata ai sentieri centrali e dedicata esclusivamente all'arrivo di nuovi eroi.", "level": _facility_level("Summoning Hall"), "world_position": Vector2(1195, 1140), "interaction_type": "summon", "upgrade_cost": 11000, "visual_variant": "level_one_background", "activity_slots": [], "navigation_path": [Vector2(520, 460), Vector2(540, 550), Vector2(610, 610), Vector2(900, 610), Vector2(1040, 820), Vector2(1160, 1080)], "footprint": Vector2(255, 325)}),
	]

func _map_building_data_to_wide_background() -> void:
	for data in building_data:
		data.world_position = _map_content_point(data.world_position)
		data.footprint *= MAP_CONTENT_SCALE
		for index in range(data.activity_slots.size()):
			data.activity_slots[index] = _map_content_point(data.activity_slots[index])
		for index in range(data.navigation_path.size()):
			data.navigation_path[index] = _map_content_point(data.navigation_path[index])

func _map_content_point(point: Vector2) -> Vector2:
	return MAP_CONTENT_OFFSET + point * MAP_CONTENT_SCALE

func _create_hero_agents() -> void:
	_sync_hero_agents()

func _sync_hero_agents() -> void:
	var alive := GameState.get_alive_heroes()
	var alive_ids: Dictionary = {}
	for hero in alive: alive_ids[str(hero.id)] = true
	for i in range(hero_agents.size() - 1, -1, -1):
		if not alive_ids.has(hero_agents[i].hero_id):
			hero_agents[i].queue_free()
			hero_agents.remove_at(i)
	var existing_ids: Dictionary = {}
	for agent in hero_agents: existing_ids[agent.hero_id] = true
	for hero in alive:
		if hero_agents.size() >= MAX_VISIBLE_AGENTS: break
		if existing_ids.has(str(hero.id)): continue
		var i := hero_agents.size()
		var plaza_slots: Array[Vector2] = building_data[0].activity_slots
		var start := plaza_slots[i % plaza_slots.size()] + Vector2(0, floori(float(i) / float(plaza_slots.size())) * 16)
		var agent: BaseHeroAgent = HeroAgentScript.new()
		agent.setup(hero, start, "%s:hub:%s" % [GameState.data.world.seed, hero.id])
		world_root.add_child(agent)
		hero_agents.append(agent)
		existing_ids[str(hero.id)] = true

func _build_context_panel() -> void:
	context_panel = PanelContainer.new()
	context_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	context_panel.offset_left = -382
	context_panel.offset_right = -22
	context_panel.offset_top = -235
	context_panel.offset_bottom = 235
	context_panel.add_theme_stylebox_override("panel", _box(PANEL, CYAN.darkened(0.36), 1, 5, 20))
	context_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(context_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	context_panel.add_child(box)
	var close := Button.new()
	close.text = "CHIUDI  ×"
	close.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close.flat = true
	close.pressed.connect(_close_context)
	box.add_child(close)
	context_meta = Label.new()
	context_meta.add_theme_color_override("font_color", CYAN)
	context_meta.add_theme_font_size_override("font_size", 10)
	box.add_child(context_meta)
	context_title = Label.new()
	context_title.add_theme_color_override("font_color", TEXT)
	context_title.add_theme_font_size_override("font_size", 26)
	context_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(context_title)
	context_description = Label.new()
	context_description.add_theme_color_override("font_color", MUTED)
	context_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(context_description)
	context_status = Label.new()
	context_status.add_theme_color_override("font_color", AMBER)
	context_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(context_status)
	upgrade_action = Button.new()
	upgrade_action.pressed.connect(_upgrade_selected)
	box.add_child(upgrade_action)
	context_secondary_action = Button.new()
	context_secondary_action.pressed.connect(_open_secondary_facility)
	box.add_child(context_secondary_action)
	context_action = Button.new()
	context_action.add_theme_stylebox_override("normal", _box(BLUE, BLUE.lightened(0.2), 1, 3, 12))
	context_action.add_theme_stylebox_override("hover", _box(BLUE.lightened(0.10), CYAN, 1, 3, 12))
	context_action.pressed.connect(_open_selected_facility)
	box.add_child(context_action)
	context_panel.hide()

func _build_overlay_hud() -> void:
	var controls := HBoxContainer.new()
	controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	controls.offset_left = 22
	controls.offset_right = 210
	controls.offset_top = -62
	controls.offset_bottom = -18
	controls.add_theme_constant_override("separation", 8)
	add_child(controls)
	var reset := Button.new()
	reset.text = "RICENTRA BASE"
	reset.pressed.connect(reset_camera)
	controls.add_child(reset)

func refresh_state() -> void:
	if building_data.is_empty(): return
	_sync_hero_agents()
	notification_system.refresh_from_game()
	for building in buildings:
		if not building.data.state_key.is_empty():
			building.set_level(_facility_level(building.data.state_key, building.data.level))
		building.set_notification(notification_system.get_state(building.data.id))
	if is_instance_valid(selected_building): _update_context(selected_building)

func _process(delta: float) -> void:
	for agent in hero_agents:
		agent.step(delta, building_data)
	_update_camera_transform()

func _on_resized() -> void:
	camera_zoom = _cover_zoom() * (FOCUS_ZOOM_FACTOR if is_instance_valid(selected_building) else 1.0)
	_update_camera_transform()

func reset_camera() -> void:
	camera_zoom = _cover_zoom()
	camera_center = WORLD_SIZE * 0.5
	_close_context()
	_update_camera_transform()

func _cover_zoom() -> float:
	if size.x <= 1.0 or size.y <= 1.0: return 1.0
	return maxf(size.x / WORLD_SIZE.x, size.y / WORLD_SIZE.y) * 1.002

func _update_camera_transform() -> void:
	if not is_instance_valid(world_root): return
	_clamp_camera()
	world_root.scale = Vector2.ONE * camera_zoom
	world_root.position = size * 0.5 - camera_center * camera_zoom

func _clamp_camera() -> void:
	var half_view := size / maxf(camera_zoom * 2.0, 0.01)
	camera_center.x = WORLD_SIZE.x * 0.5 if half_view.x >= WORLD_SIZE.x * 0.5 else clampf(camera_center.x, half_view.x, WORLD_SIZE.x - half_view.x)
	camera_center.y = WORLD_SIZE.y * 0.5 if half_view.y >= WORLD_SIZE.y * 0.5 else clampf(camera_center.y, half_view.y, WORLD_SIZE.y - half_view.y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			accept_event()
			return
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			if event.pressed: drag_distance = 0.0
	elif event is InputEventMouseMotion and dragging:
		drag_distance += event.relative.length()
		camera_center -= event.relative / camera_zoom
		_clamp_camera()
	elif event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event.index] = event.position
		else:
			active_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		active_touches[event.index] = event.position
		if active_touches.size() == 1:
			camera_center -= event.relative / camera_zoom
			_clamp_camera()
	elif event is InputEventMagnifyGesture:
		accept_event()
	elif event is InputEventPanGesture:
		camera_center += event.delta * 12.0 / camera_zoom
		_clamp_camera()

func _select_building(building: BaseBuilding) -> void:
	if drag_distance > 8.0: return
	if is_instance_valid(selected_building): selected_building.set_selected(false)
	selected_building = building
	selected_building.set_selected(true)
	_update_context(building)
	context_panel.show()
	var target_zoom := _cover_zoom() * FOCUS_ZOOM_FACTOR
	var target_center := building.data.world_position + Vector2(110, 0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "camera_center", target_center, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "camera_zoom", target_zoom, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _update_context(building: BaseBuilding) -> void:
	var data := building.data
	context_meta.text = "%s // LIVELLO %d / %d" % [data.building_type.to_upper(), data.level, data.max_level]
	context_title.text = data.display_name.to_upper()
	context_description.text = data.description + ("\n\nAccesso rituale interno: nessuna postazione esterna." if data.activity_slots.is_empty() else "\n\nPostazioni attività disponibili: %d." % data.activity_slots.size())
	var notification := notification_system.get_state(data.id)
	context_status.text = "STATO // " + (str(notification.get("text", "Operativa")) if bool(notification.get("active", false)) else "OPERATIVA · NESSUN AVVISO")
	context_action.text = _action_label(data.interaction_type)
	context_action.disabled = data.interaction_type.is_empty()
	context_secondary_action.visible = not data.secondary_interaction_type.is_empty()
	context_secondary_action.text = data.secondary_label if not data.secondary_label.is_empty() else _action_label(data.secondary_interaction_type)
	upgrade_action.visible = upgrade_system.can_upgrade(data)
	upgrade_action.text = "UPGRADE LV.%d  ·  %s ORO%s" % [data.level + 1, GameState.format_number(upgrade_system.cost_for(data)), "  (DEV ∞)" if GameState.is_dev_unlimited() else ""]

func _action_label(view_id: String) -> String:
	match view_id:
		"tower": return "PREPARA UNA SPEDIZIONE"
		"heroes": return "APRI GESTIONE EROI"
		"squad": return "GESTISCI FORMAZIONE"
		"summon": return "APRI RISONANZA"
		"merge": return "APRI FUSIONE EROI"
		"shop": return "APRI MAGAZZINO / SHOP"
		"base": return "APRI SERVIZI DELLA BASE"
		"archive": return "APRI ARCHIVIO"
		"dev": return "APRI DEV / QA"
		_: return "FUNZIONE IN SVILUPPO"

func _close_context() -> void:
	context_panel.hide()
	if is_instance_valid(selected_building): selected_building.set_selected(false)
	selected_building = null

func _open_selected_facility() -> void:
	if not is_instance_valid(selected_building): return
	facility_requested.emit(selected_building.data.interaction_type)

func _open_secondary_facility() -> void:
	if not is_instance_valid(selected_building): return
	facility_requested.emit(selected_building.data.secondary_interaction_type)

func _upgrade_selected() -> void:
	if not is_instance_valid(selected_building): return
	var result := upgrade_system.upgrade(selected_building.data)
	if result.ok:
		selected_building.set_level(int(result.level))
		_update_context(selected_building)
		hub_toast_requested.emit("Base potenziata", "%s ha raggiunto il livello %d." % [selected_building.data.display_name, result.level], "good")
	else:
		hub_toast_requested.emit("Upgrade bloccato", str(result.message), "warn")
