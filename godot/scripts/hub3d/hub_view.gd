extends SubViewportContainer
class_name HubView

## Contenitore della base 3D: gestisce camera (pan, zoom, pinch, focus),
## hover e clic su strutture ed eroi.

signal building_clicked(id: String)
signal hero_clicked(hero_id: String)

const HubWorldScript := preload("res://scripts/hub3d/hub_world.gd")

const PITCH := deg_to_rad(44.0)
const YAW := deg_to_rad(24.0)
const MIN_DISTANCE := 15.0
const MAX_DISTANCE := 78.0
const HOME_TARGET := Vector3(2.2, 0.0, -2.6)
const HOME_DISTANCE := 61.0

var viewport: SubViewport
var world: HubWorld
var camera: Camera3D
var target := HOME_TARGET
var distance := HOME_DISTANCE
var dragging := false
var press_position := Vector2.ZERO
var drag_moved := 0.0
var touches: Dictionary = {}
var pinch_start := 0.0
var pinch_distance := 0.0
var camera_tween: Tween
var hover_timer := 0.0
var last_mouse := Vector2.ZERO
var hovered_hero := ""
var panel_width := 0.0

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	viewport.physics_object_picking = false
	add_child(viewport)
	world = HubWorldScript.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.near = 0.5
	camera.far = 260.0
	viewport.add_child(camera)
	camera.current = true
	_apply_camera()

func refresh(state: RiftwardState) -> void:
	world.refresh(state)

func _apply_camera() -> void:
	var offset := Vector3(sin(YAW) * cos(PITCH), sin(PITCH), cos(YAW) * cos(PITCH)) * distance
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)

func _clamp_target() -> void:
	var flat := Vector2(target.x, target.z)
	if flat.length() > 18.0: flat = flat.normalized() * 18.0
	target = Vector3(flat.x, target.y, flat.y)
	distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)

func _process(delta: float) -> void:
	hover_timer -= delta
	if hover_timer <= 0.0 and not dragging:
		hover_timer = 0.08
		_update_hover(last_mouse)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(0.9)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(1.1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				dragging = true
				drag_moved = 0.0
				press_position = event.position
			else:
				dragging = false
				if drag_moved < 8.0 and event.button_index == MOUSE_BUTTON_LEFT: _click(event.position)
	elif event is InputEventMouseMotion:
		last_mouse = event.position
		if dragging and touches.size() < 2:
			drag_moved += event.relative.length()
			_pan(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed: touches[event.index] = event.position
		else: touches.erase(event.index)
		if touches.size() == 2:
			var pts: Array = touches.values()
			pinch_start = (pts[0] as Vector2).distance_to(pts[1])
			pinch_distance = distance
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() == 2:
			var pts: Array = touches.values()
			var d := (pts[0] as Vector2).distance_to(pts[1])
			if pinch_start > 1.0:
				distance = pinch_distance * pinch_start / maxf(d, 1.0)
				_clamp_target()
				_apply_camera()
	elif event is InputEventMagnifyGesture:
		zoom_by(1.0 / event.factor)
	elif event is InputEventPanGesture:
		_pan(-event.delta * 6.0)

func _pan(relative: Vector2) -> void:
	_kill_tween()
	var scale := distance * 0.0016
	var right := Vector3(cos(YAW), 0, -sin(YAW))
	var forward := Vector3(-sin(YAW), 0, -cos(YAW))
	target -= right * relative.x * scale
	target -= forward * -relative.y * scale * 1.3
	_clamp_target()
	_apply_camera()

func zoom_by(factor: float) -> void:
	_kill_tween()
	distance *= factor
	_clamp_target()
	_apply_camera()

func _kill_tween() -> void:
	if camera_tween != null and camera_tween.is_valid(): camera_tween.kill()

func _pick(screen_pos: Vector2) -> Dictionary:
	if camera == null or world == null: return {}
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 300.0, 2 | 4)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {}
	var collider: Object = hit.collider
	if collider.has_meta("hero_id"): return {"hero": str(collider.get_meta("hero_id"))}
	if collider.has_meta("facility_id"): return {"building": str(collider.get_meta("facility_id"))}
	return {}

func _update_hover(screen_pos: Vector2) -> void:
	var hit := _pick(screen_pos)
	var building_id := str(hit.get("building", ""))
	world.set_hovered(building_id)
	var hero := str(hit.get("hero", ""))
	if hero != hovered_hero:
		var old: HubAgent = world.agent_for(hovered_hero)
		if old != null: old.show_hover(false)
		hovered_hero = hero
		var agent: HubAgent = world.agent_for(hero)
		if agent != null: agent.show_hover(true)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hit.is_empty() else Control.CURSOR_ARROW

func _click(screen_pos: Vector2) -> void:
	var hit := _pick(screen_pos)
	if hit.has("hero"): hero_clicked.emit(str(hit.hero))
	elif hit.has("building"): building_clicked.emit(str(hit.building))

## Centra la camera su una struttura lasciando spazio al pannello laterale.
func focus_on(id: String, side_panel_px: float = 0.0) -> void:
	world.set_selected(id)
	panel_width = side_panel_px
	var point := world.focus_position(id)
	var focus_distance := 26.0 if id != "gate" else 32.0
	var right := Vector3(cos(YAW), 0, -sin(YAW))
	var view_w := maxf(size.x, 1.0)
	var half_width_world := focus_distance * tan(deg_to_rad(camera.fov) * 0.5) * (view_w / maxf(size.y, 1.0))
	var shift := right * half_width_world * (side_panel_px / view_w)
	_animate_camera(point + shift, focus_distance)

func reset_view() -> void:
	world.set_selected("")
	_animate_camera(HOME_TARGET, HOME_DISTANCE)

func _animate_camera(new_target: Vector3, new_distance: float) -> void:
	_kill_tween()
	camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	camera_tween.tween_method(_set_target, target, new_target, 0.55)
	camera_tween.tween_method(_set_distance, distance, new_distance, 0.55)

func _set_target(value: Vector3) -> void:
	target = value
	_apply_camera()

func _set_distance(value: float) -> void:
	distance = value
	_apply_camera()
