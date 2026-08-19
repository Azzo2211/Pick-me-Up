extends Control
class_name BaseHeroAgent

enum AgentState { IDLE, WALKING, ACTIVITY }

var hero_id := ""
var hero_name := "Hero"
var role := "Guardian"
var hue := 45.0
var morale := 70
var fatigue := 0
var current_position := Vector2.ZERO
var current_building := "plaza"
var current_activity := "Osserva la base"
var state := AgentState.IDLE
var movement_speed := 72.0
var is_busy := false
var target_position := Vector2.ZERO
var destination_building := "plaza"
var movement_path: Array[Vector2] = []
var state_timer := 1.0
var animation_phase := 0.0
var rng := RandomNumberGenerator.new()

func setup(hero: Dictionary, start_position: Vector2, seed_text: String) -> void:
	hero_id = str(hero.get("id", "hero"))
	hero_name = str(hero.get("name", "Hero"))
	role = str(hero.get("role", "Guardian"))
	hue = float(hero.get("hue", 45.0))
	morale = int(hero.get("morale", 70))
	fatigue = int(hero.get("fatigue", 0))
	current_position = start_position
	target_position = start_position
	movement_speed = 62.0 + float(abs(hero_id.hash()) % 25)
	rng.seed = abs(seed_text.hash())
	state_timer = rng.randf_range(0.5, 2.5)
	size = Vector2(28, 38)
	custom_minimum_size = size
	position = current_position - size * 0.5
	tooltip_text = "%s · %s\n%s" % [hero_name, role, current_activity]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	queue_redraw()

func step(delta: float, destinations: Array) -> void:
	animation_phase += delta * (6.5 if state == AgentState.WALKING else 2.0)
	state_timer -= delta
	match state:
		AgentState.IDLE:
			is_busy = false
			if state_timer <= 0.0: _choose_destination(destinations)
		AgentState.WALKING:
			is_busy = true
			current_position = current_position.move_toward(target_position, movement_speed * delta)
			position = current_position - size * 0.5
			if current_position.distance_to(target_position) <= 2.0:
				current_position = target_position
				if movement_path.is_empty():
					_begin_activity()
				else:
					target_position = movement_path.pop_front()
		AgentState.ACTIVITY:
			is_busy = true
			if state_timer <= 0.0:
				state = AgentState.IDLE
				state_timer = rng.randf_range(0.8, 2.7)
				current_activity = "Valuta la prossima attività"
	queue_redraw()

func _choose_destination(destinations: Array) -> void:
	var available := destinations.filter(func(item): return item.is_unlocked and not item.activity_slots.is_empty())
	if available.is_empty():
		state_timer = 2.0
		return
	if available.size() > 1:
		var other_buildings := available.filter(func(item): return item.id != current_building)
		if not other_buildings.is_empty(): available = other_buildings
	var building: BaseBuildingData = available[rng.randi_range(0, available.size() - 1)]
	var slot: Vector2 = building.activity_slots[rng.randi_range(0, building.activity_slots.size() - 1)]
	destination_building = building.id
	var destination := slot + Vector2(rng.randf_range(-5, 5), rng.randf_range(-4, 4))
	movement_path = _route_to(building, destination, destinations)
	if movement_path.is_empty():
		target_position = destination
	else:
		target_position = movement_path.pop_front()
	current_activity = "Verso " + building.display_name
	state = AgentState.WALKING
	tooltip_text = "%s · %s\n%s" % [hero_name, role, current_activity]

func _route_to(destination: BaseBuildingData, final_position: Vector2, destinations: Array) -> Array[Vector2]:
	var route: Array[Vector2] = []
	var current_data := _find_building(current_building, destinations)
	if current_data != null:
		for index in range(current_data.navigation_path.size() - 1, -1, -1):
			_append_waypoint(route, current_data.navigation_path[index])
	for waypoint in destination.navigation_path:
		_append_waypoint(route, waypoint)
	_append_waypoint(route, final_position)
	while not route.is_empty() and current_position.distance_to(route[0]) < 7.0:
		route.pop_front()
	return route

func _find_building(building_id: String, destinations: Array) -> BaseBuildingData:
	for item in destinations:
		if item.id == building_id: return item
	return null

func _append_waypoint(route: Array[Vector2], waypoint: Vector2) -> void:
	if route.is_empty() or route[-1].distance_to(waypoint) > 4.0:
		route.append(waypoint)

func _begin_activity() -> void:
	current_building = destination_building
	state = AgentState.ACTIVITY
	state_timer = rng.randf_range(3.0, 7.0)
	current_activity = _activity_for(current_building)
	tooltip_text = "%s · %s\n%s" % [hero_name, role, current_activity]

func _activity_for(building_id: String) -> String:
	match building_id:
		"training": return "Si allena"
		"forge": return "Osserva la forgia"
		"lodgings": return "Riposa negli alloggi"
		"fusion": return "Studia la matrice"
		"alchemy": return "Prepara reagenti"
		"warehouse": return "Ordina le scorte"
		"portal": return "Attende il dispiegamento"
		_: return "Socializza in piazza"

func _draw() -> void:
	var bob := sin(animation_phase) * (1.8 if state == AgentState.WALKING else 0.7)
	var center := Vector2(size.x * 0.5, size.y * 0.54 + bob)
	var body_color := Color.from_hsv(hue / 360.0, 0.46, 0.68)
	_draw_ellipse_shape(Vector2(size.x * 0.5, size.y - 4), Vector2(10, 3), Color(0, 0, 0, 0.38))
	var cloak := PackedVector2Array([center + Vector2(-8, 13), center + Vector2(-6, -4), center + Vector2(0, -9), center + Vector2(7, -4), center + Vector2(9, 13)])
	draw_colored_polygon(cloak, body_color)
	draw_circle(center + Vector2(0, -12), 5.3, Color("#c8aa8a"))
	draw_arc(center + Vector2(0, -12), 5.8, PI, TAU, 8, body_color.darkened(0.62), 3.0, true)
	if role in ["Ranger", "Mage", "Support"]:
		draw_line(center + Vector2(7, -2), center + Vector2(11, -15), Color("#d9e5f5"), 1.5)
	else:
		draw_line(center + Vector2(6, -1), center + Vector2(12, -17), Color("#e8d493"), 1.7)
	if state == AgentState.ACTIVITY:
		var activity_color := Color("#66d9ff")
		activity_color.a = 0.7 + sin(animation_phase * 2.0) * 0.2
		draw_arc(center + Vector2(0, -12), 9.0, 0, TAU, 14, activity_color, 1.4, true)

func _draw_ellipse_shape(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(17):
		var angle := TAU * float(i) / 16.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
