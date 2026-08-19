extends Control
class_name BaseBuilding

signal building_selected(building: BaseBuilding)

const TEXT := Color("#f5f7fb")
const MUTED := Color("#9da7b8")
const CYAN := Color("#66d9ff")
const BLUE := Color("#4e7cff")
const VIOLET := Color("#9a6bff")
const AMBER := Color("#f0c75e")
const RED := Color("#ff4d5a")

var data: BaseBuildingData
var is_hovered := false
var is_selected := false
var notification_state := {"active": false, "text": "", "tone": "system"}
var pulse := 0.0
var press_origin := Vector2.ZERO
var name_label: Label
var notification_label: Label

func setup(value: BaseBuildingData) -> void:
	data = value
	position = data.world_position - data.footprint * 0.5
	size = data.footprint
	custom_minimum_size = data.footprint
	pivot_offset = data.footprint * 0.5
	tooltip_text = "" if data.visual_variant == "level_one_background" else "%s · Livello %d" % [data.display_name, data.level]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	_build_labels()
	set_process(data.building_type in ["portal", "forge", "fusion", "alchemy"])
	queue_redraw()

func _build_labels() -> void:
	name_label = Label.new()
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_left = 8
	name_label.offset_right = -8
	name_label.offset_top = -35
	name_label.offset_bottom = -8
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", TEXT if data.is_unlocked else MUTED)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	name_label.add_theme_constant_override("shadow_offset_x", 2)
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	name_label.text = "%s  ·  LV.%d" % [data.display_name.to_upper(), data.level] if data.is_unlocked else "PIATTAFORMA BLOCCATA"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.visible = data.visual_variant != "level_one_background"
	add_child(name_label)

	notification_label = Label.new()
	notification_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	notification_label.offset_left = -34
	notification_label.offset_right = -8
	notification_label.offset_top = 8
	notification_label.offset_bottom = 34
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notification_label.add_theme_font_size_override("font_size", 18)
	notification_label.text = "!"
	notification_label.tooltip_text = str(notification_state.get("text", ""))
	notification_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_label.hide()
	add_child(notification_label)

func set_level(value: int) -> void:
	data.level = value
	tooltip_text = "%s · Livello %d" % [data.display_name, data.level]
	if is_instance_valid(name_label):
		name_label.text = "%s  ·  LV.%d" % [data.display_name.to_upper(), data.level]
	queue_redraw()

func set_selected(value: bool) -> void:
	is_selected = value
	if is_instance_valid(name_label) and data.visual_variant == "level_one_background":
		name_label.visible = false
	queue_redraw()

func set_notification(value: Dictionary) -> void:
	notification_state = value
	if not is_instance_valid(notification_label): return
	var active := bool(value.get("active", false))
	notification_label.visible = active
	notification_label.tooltip_text = str(value.get("text", ""))
	var tone := str(value.get("tone", "system"))
	notification_label.add_theme_color_override("font_color", RED if tone == "danger" else AMBER if tone == "reward" else VIOLET if tone == "meta" else CYAN)

func _set_hovered(value: bool) -> void:
	is_hovered = value
	if is_instance_valid(name_label) and data.visual_variant == "level_one_background":
		name_label.visible = false
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_origin = event.position
		elif event.position.distance_to(press_origin) < 8.0 and data.is_unlocked:
			building_selected.emit(self)
	if event is InputEventScreenTouch and not event.pressed and data.is_unlocked:
		building_selected.emit(self)

func _has_point(point: Vector2) -> bool:
	if data == null or data.visual_variant != "level_one_background":
		return Rect2(Vector2.ZERO, size).has_point(point)
	return Geometry2D.is_point_in_polygon(point, _hotspot_polygon(size * Vector2(0.5, 0.48)))

func _process(delta: float) -> void:
	pulse = fmod(pulse + delta, TAU)
	queue_redraw()

func _accent() -> Color:
	match data.building_type:
		"portal": return CYAN
		"fusion": return VIOLET
		"summoning": return VIOLET.lightened(0.18)
		"alchemy": return Color("#6fe3b4")
		"forge": return AMBER
		"training": return BLUE
		"lodgings": return Color("#d88b9d")
		"warehouse": return Color("#b59b77")
		"plaza": return Color("#e7d7a5")
		_: return MUTED

func _draw() -> void:
	var center := size * Vector2(0.5, 0.48)
	var accent := _accent()
	if data.visual_variant == "level_one_background":
		return
	var platform := PackedVector2Array([
		center + Vector2(0, -54), center + Vector2(96, -12),
		center + Vector2(96, 25), center + Vector2(0, 62),
		center + Vector2(-96, 25), center + Vector2(-96, -12),
	])
	var base_color := Color("#152033d9") if data.is_unlocked else Color("#11141cdd")
	draw_colored_polygon(platform, base_color)
	draw_polyline(PackedVector2Array(Array(platform) + [platform[0]]), accent if is_hovered or is_selected else Color("#566176"), 3.0 if is_selected else 2.0 if is_hovered else 1.0, true)
	if is_hovered or is_selected:
		var glow := accent
		glow.a = 0.08 if is_hovered else 0.14
		draw_circle(center, 76.0, glow)
	if not data.is_unlocked:
		_draw_ruins(center)
		return
	match data.building_type:
		"portal": _draw_portal(center, accent)
		"training": _draw_training(center, accent)
		"forge": _draw_forge(center, accent)
		"lodgings": _draw_lodgings(center, accent)
		"fusion": _draw_fusion(center, accent)
		"alchemy": _draw_alchemy(center, accent)
		"warehouse": _draw_warehouse(center, accent)
		"plaza": _draw_plaza(center, accent)
		_: _draw_ruins(center)

func _draw_background_hotspot(center: Vector2, accent: Color) -> void:
	var polygon := _hotspot_polygon(center)
	var bounds := PackedVector2Array(polygon)
	bounds.append(polygon[0])
	if is_hovered or is_selected:
		var fill := accent
		fill.a = 0.10 if is_hovered else 0.16
		draw_colored_polygon(polygon, fill)
		draw_polyline(bounds, accent, 3.5 if is_selected else 2.4, true)
		for radius in [18.0, 27.0]:
			var ring := accent
			ring.a = 0.65 if is_selected else 0.38
			draw_arc(center, radius, 0, TAU, 24, ring, 1.8, true)
	elif data.building_type in ["portal", "fusion"]:
		var pulse_color := accent
		pulse_color.a = 0.30 + sin(pulse * 2.0) * 0.10
		draw_arc(center, 18.0, 0, TAU, 18, pulse_color, 1.6, true)
	if data.level >= 2:
		var upgrade_glow := accent
		upgrade_glow.a = 0.28
		draw_arc(center, 34.0 + data.level * 3.0, pulse, pulse + PI * 1.5, 20, upgrade_glow, 2.0, true)

func _hotspot_polygon(center: Vector2) -> PackedVector2Array:
	var half_width := size.x * 0.48
	var half_height := size.y * 0.46
	if data.building_type in ["plaza", "fusion"]:
		var ellipse := PackedVector2Array()
		for index in range(18):
			var angle := TAU * float(index) / 18.0
			ellipse.append(center + Vector2(cos(angle) * half_width, sin(angle) * half_height))
		return ellipse
	if data.building_type == "training":
		return PackedVector2Array([
			center + Vector2(-half_width * 0.72, -half_height), center + Vector2(half_width * 0.72, -half_height),
			center + Vector2(half_width, -half_height * 0.45), center + Vector2(half_width, half_height * 0.55),
			center + Vector2(half_width * 0.45, half_height), center + Vector2(-half_width * 0.45, half_height),
			center + Vector2(-half_width, half_height * 0.55), center + Vector2(-half_width, -half_height * 0.45),
		])
	if data.building_type == "portal":
		return PackedVector2Array([
			center + Vector2(-half_width * 0.55, -half_height), center + Vector2(half_width * 0.60, -half_height),
			center + Vector2(half_width, -half_height * 0.45), center + Vector2(half_width, half_height * 0.35),
			center + Vector2(half_width * 0.25, half_height), center + Vector2(-half_width, half_height * 0.75),
			center + Vector2(-half_width * 0.80, -half_height * 0.25),
		])
	return PackedVector2Array([
		center + Vector2(-half_width * 0.70, -half_height), center + Vector2(half_width * 0.70, -half_height),
		center + Vector2(half_width, -half_height * 0.40), center + Vector2(half_width, half_height * 0.62),
		center + Vector2(half_width * 0.55, half_height), center + Vector2(-half_width * 0.55, half_height),
		center + Vector2(-half_width, half_height * 0.62), center + Vector2(-half_width, -half_height * 0.40),
	])

func _draw_portal(center: Vector2, accent: Color) -> void:
	var portal_center := center + Vector2(0, -12)
	for i in range(3):
		var ring := accent.lerp(VIOLET, float(i) * 0.25)
		ring.a = 0.72 - float(i) * 0.15 + sin(pulse + i) * 0.08
		draw_arc(portal_center, 29.0 + i * 9.0, PI, TAU, 24, ring, 4.0 - i * 0.7, true)
	draw_rect(Rect2(portal_center + Vector2(-49, 27), Vector2(98, 12)), Color("#263450"), true)
	draw_rect(Rect2(portal_center + Vector2(-48, -13), Vector2(12, 46)), Color("#354460"), true)
	draw_rect(Rect2(portal_center + Vector2(36, -13), Vector2(12, 46)), Color("#354460"), true)
	var energy := accent
	energy.a = 0.18 + sin(pulse * 2.0) * 0.05
	draw_circle(portal_center, 25.0, energy)

func _draw_training(center: Vector2, accent: Color) -> void:
	draw_rect(Rect2(center + Vector2(-62, -34), Vector2(124, 62)), Color("#25334a"), true)
	for x in [-39.0, 0.0, 39.0]:
		draw_circle(center + Vector2(x, -8), 7, Color("#91775b"))
		draw_line(center + Vector2(x, -1), center + Vector2(x, 20), Color("#bfa477"), 3)
		draw_line(center + Vector2(x - 10, 8), center + Vector2(x + 10, 8), accent, 2)
	if data.level >= 2:
		draw_line(center + Vector2(-72, -38), center + Vector2(-72, 25), Color("#c6d2e5"), 3)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-70, -36), center + Vector2(-36, -27), center + Vector2(-70, -14)]), accent)
	if data.level >= 3:
		draw_rect(Rect2(center + Vector2(48, -46), Vector2(28, 22)), Color("#1e2a3e"), true)

func _draw_forge(center: Vector2, accent: Color) -> void:
	draw_rect(Rect2(center + Vector2(-58, -35), Vector2(116, 64)), Color("#2a2630"), true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-68, -35), center + Vector2(0, -67), center + Vector2(68, -35)]), Color("#4a3040"))
	draw_rect(Rect2(center + Vector2(31, -61), Vector2(18, 34)), Color("#313849"), true)
	for i in range(3):
		var smoke := Color("#b7c5d4")
		smoke.a = 0.10 + float(i) * 0.04
		draw_circle(center + Vector2(40 + sin(pulse + i) * 4, -72 - i * 10), 7.0 + i * 2.0, smoke)
	draw_circle(center + Vector2(-24, 5), 14, Color("#ff6b38"))
	draw_circle(center + Vector2(-24, 5), 7 + sin(pulse * 3.0) * 2, accent)
	draw_rect(Rect2(center + Vector2(12, 5), Vector2(32, 9)), Color("#8592a5"), true)

func _draw_lodgings(center: Vector2, accent: Color) -> void:
	for offset in [-35.0, 35.0]:
		draw_rect(Rect2(center + Vector2(offset - 29, -30), Vector2(58, 57)), Color("#3c3342"), true)
		draw_colored_polygon(PackedVector2Array([center + Vector2(offset - 36, -30), center + Vector2(offset, -58), center + Vector2(offset + 36, -30)]), Color("#594052"))
		draw_rect(Rect2(center + Vector2(offset - 8, 2), Vector2(16, 25)), Color("#171d29"), true)
		draw_rect(Rect2(center + Vector2(offset - 22, -18), Vector2(11, 12)), accent.darkened(0.25), true)

func _draw_fusion(center: Vector2, accent: Color) -> void:
	for i in range(3):
		var ring := accent
		ring.a = 0.65 - i * 0.16
		draw_arc(center + Vector2(0, -5), 24 + i * 12, pulse + i, pulse + i + PI * 1.35, 22, ring, 3.0, true)
	var crystal := PackedVector2Array([center + Vector2(0, -58), center + Vector2(18, -12), center + Vector2(0, 22), center + Vector2(-18, -12)])
	draw_colored_polygon(crystal, accent.lightened(0.10))
	draw_polyline(PackedVector2Array(Array(crystal) + [crystal[0]]), Color.WHITE, 1.0, true)

func _draw_alchemy(center: Vector2, accent: Color) -> void:
	draw_circle(center + Vector2(0, -7), 48, Color("#26384a"))
	draw_arc(center + Vector2(0, -7), 48, PI, TAU, 24, accent, 3, true)
	draw_rect(Rect2(center + Vector2(-47, -8), Vector2(94, 38)), Color("#26384a"), true)
	for x in [-25.0, 0.0, 25.0]:
		draw_rect(Rect2(center + Vector2(x - 6, -2), Vector2(12, 22)), Color("#b5dbe0"), true)
		draw_circle(center + Vector2(x, 18), 9, accent.lerp(VIOLET, (x + 25.0) / 50.0))

func _draw_warehouse(center: Vector2, accent: Color) -> void:
	draw_rect(Rect2(center + Vector2(-65, -39), Vector2(130, 69)), Color("#3a3230"), true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-72, -39), center + Vector2(0, -65), center + Vector2(72, -39)]), Color("#514139"))
	for x in [-36.0, 0.0, 36.0]:
		draw_rect(Rect2(center + Vector2(x - 14, -2), Vector2(28, 27)), Color("#72563c"), true)
		draw_line(center + Vector2(x - 14, 10), center + Vector2(x + 14, 10), accent.darkened(0.3), 1)

func _draw_plaza(center: Vector2, accent: Color) -> void:
	for radius in [48.0, 34.0, 17.0]:
		draw_arc(center + Vector2(0, -6), radius, 0, TAU, 32, accent.darkened(radius / 140.0), 2, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -55), center + Vector2(10, -8), center + Vector2(0, 9), center + Vector2(-10, -8)]), accent)
	draw_circle(center + Vector2(0, -6), 6, CYAN)

func _draw_ruins(center: Vector2) -> void:
	draw_rect(Rect2(center + Vector2(-50, -20), Vector2(32, 48)), Color("#343844"), true)
	draw_rect(Rect2(center + Vector2(13, -35), Vector2(24, 60)), Color("#2a2e39"), true)
	draw_line(center + Vector2(-65, 32), center + Vector2(58, -31), Color("#525968"), 3)
