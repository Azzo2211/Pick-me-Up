extends Node3D
## Standalone 3D viewer for the original Riftward animation library.
## Run res://RiftwardMotionPreview.tscn with F6. Does not replace the main scene.

const MODEL := preload("res://assets/animations/riftward_original_motions.glb")

var animation_player: AnimationPlayer
var animation_names: Array[String] = []
var current_index := 0
var title_label: Label
var detail_label: Label
var orbit_angle := 0.0
var orbiting := false
var camera: Camera3D

func _ready() -> void:
	var mannequin := MODEL.instantiate()
	add_child(mannequin)
	animation_player = _find_animation_player(mannequin)
	if animation_player == null:
		push_error("Riftward: AnimationPlayer non trovato nel GLB importato")
		return
	for item in animation_player.get_animation_list():
		animation_names.append(str(item))
	animation_names.sort()
	if animation_names.is_empty():
		push_error("Riftward: nessuna animazione trovata")
		return
	animation_player.animation_finished.connect(_on_animation_finished)
	_create_environment()
	_create_interface()
	var idle_index := _find_animation_index("Idle")
	current_index = maxi(0, idle_index)
	_play_selected()

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var candidate := _find_animation_player(child)
		if candidate != null:
			return candidate
	return null

func _create_environment() -> void:
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	_update_camera()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.5
	add_child(light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-2, 3.5, -2.5)
	fill.light_energy = 230.0
	fill.omni_range = 8.0
	add_child(fill)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8, 8)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position.y = -0.035
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#22293a")
	floor_material.roughness = 0.95
	floor_instance.material_override = floor_material
	add_child(floor_instance)

	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#101728")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#bed9ff")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	add_child(environment)

func _create_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(390, 140)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := Label.new()
	header.text = "RIFTWARD  |  ANIMAZIONI ORIGINALI 3D"
	column.add_child(header)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	column.add_child(title_label)
	detail_label = Label.new()
	column.add_child(detail_label)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_add_button(buttons, "◀ Precedente", -1)
	_add_button(buttons, "Successiva ▶", 1)
	var help := Label.new()
	help.text = "← / →: cambia animazione     Trascina con mouse: ruota camera"
	column.add_child(help)

func _add_button(parent: HBoxContainer, label_text: String, delta: int) -> void:
	var button := Button.new()
	button.text = label_text
	button.pressed.connect(func() -> void: _change_animation(delta))
	parent.add_child(button)

func _change_animation(delta: int) -> void:
	if animation_names.is_empty():
		return
	current_index = posmod(current_index + delta, animation_names.size())
	_play_selected()

func _play_selected() -> void:
	if animation_player == null or animation_names.is_empty():
		return
	var animation_name := animation_names[current_index]
	animation_player.play(animation_name)
	title_label.text = animation_name
	detail_label.text = "%d / %d animazioni | controlla il modello 3D" % [current_index + 1, animation_names.size()]

func _find_animation_index(suffix: String) -> int:
	for i in range(animation_names.size()):
		if animation_names[i] == suffix or animation_names[i].ends_with("/" + suffix):
			return i
	return -1

func _on_animation_finished(animation_name: StringName) -> void:
	var raw_name := str(animation_name).get_slice("/", str(animation_name).get_slice_count("/") - 1)
	var repeat := raw_name.begins_with("Walk_") or raw_name in ["Idle", "Idle_Breathe", "Jog_F", "Sprint_F", "Crouch_Idle", "Crouch_Walk", "Sit_Idle", "Wave", "Carry", "Push", "Hammer_Work", "Panic"]
	if repeat and str(animation_name) == animation_names[current_index]:
		animation_player.play(animation_name)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			_change_animation(-1)
		elif event.keycode == KEY_RIGHT:
			_change_animation(1)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		orbiting = event.pressed
	elif event is InputEventMouseMotion and orbiting:
		orbit_angle += event.relative.x * 0.01
		_update_camera()

func _update_camera() -> void:
	if camera == null:
		return
	camera.position = Vector3(sin(orbit_angle) * 4.2, 1.6, -cos(orbit_angle) * 4.2)
	camera.look_at(Vector3(0, 1.12, 0))
