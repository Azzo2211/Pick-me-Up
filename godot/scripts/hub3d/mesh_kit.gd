extends RefCounted
class_name MeshKit

## Costruttore di geometria low-poly in stile toon.
## Ogni istanza ha la propria cache di materiali: così un edificio può
## essere evidenziato modificando solo i suoi materiali.

var parent: Node3D
var materials: Dictionary = {}
var cast_shadows := true

func _init(target: Node3D) -> void:
	parent = target

func mat(color: Color, emission: float = 0.0, transparent: bool = false, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s|%s" % [color.to_html(), emission, transparent, unshaded]
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	m.metallic_specular = 0.15
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = m
	return m

func _add(mesh: Mesh, material: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, target: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	instance.scale = scale
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(target if target != null else parent).add_child(instance)
	return instance

func box(size: Vector3, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, emission: float = 0.0, target: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, mat(color, emission), pos, rot, Vector3.ONE, target)

func cyl(top_radius: float, bottom_radius: float, height: float, color: Color, pos: Vector3, segments: int = 12, rot: Vector3 = Vector3.ZERO, emission: float = 0.0, target: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _add(mesh, mat(color, emission), pos, rot, Vector3.ONE, target)

func cone(radius: float, height: float, color: Color, pos: Vector3, segments: int = 10, emission: float = 0.0, target: Node3D = null) -> MeshInstance3D:
	return cyl(0.0, radius, height, color, pos, segments, Vector3.ZERO, emission, target)

func sphere(radius: float, color: Color, pos: Vector3, scale: Vector3 = Vector3.ONE, segments: int = 12, emission: float = 0.0, target: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(4, segments / 2)
	return _add(mesh, mat(color, emission), pos, Vector3.ZERO, scale, target)

func dome(radius: float, color: Color, pos: Vector3, emission: float = 0.0, segments: int = 18, target: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius
	mesh.is_hemisphere = true
	mesh.radial_segments = segments
	mesh.rings = 8
	return _add(mesh, mat(color, emission), pos, Vector3.ZERO, Vector3.ONE, target)

func prism(size: Vector3, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, target: Node3D = null) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	return _add(mesh, mat(color), pos, rot, Vector3.ONE, target)

func torus(inner: float, outer: float, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, emission: float = 0.0, segments: int = 24, target: Node3D = null) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = segments
	mesh.ring_segments = 8
	return _add(mesh, mat(color, emission), pos, rot, Vector3.ONE, target)

func capsule(radius: float, height: float, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, target: Node3D = null) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 4
	return _add(mesh, mat(color), pos, rot, Vector3.ONE, target)

func rock(radius: float, color: Color, pos: Vector3, seed_value: int, target: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.5
	mesh.radial_segments = 6
	mesh.rings = 3
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var s := Vector3(r.randf_range(0.8, 1.3), r.randf_range(0.6, 1.0), r.randf_range(0.8, 1.3))
	return _add(mesh, mat(color), pos, Vector3(0, r.randf_range(0, TAU), 0), s, target)

## Applica (o rimuove) un bagliore a tutti i materiali di questo costruttore.
func set_highlight(amount: float) -> void:
	for key in materials:
		var m: StandardMaterial3D = materials[key]
		if m.has_meta("base_emission"):
			pass
		else:
			m.set_meta("base_emission", m.emission_energy_multiplier if m.emission_enabled else 0.0)
			m.set_meta("base_enabled", m.emission_enabled)
		if amount > 0.0:
			m.emission_enabled = true
			if not bool(m.get_meta("base_enabled")): m.emission = m.albedo_color
			m.emission_energy_multiplier = float(m.get_meta("base_emission")) + amount
		else:
			m.emission_enabled = bool(m.get_meta("base_enabled"))
			m.emission_energy_multiplier = float(m.get_meta("base_emission"))

static var _blob_material: StandardMaterial3D

## Ombra morbida a disco sotto personaggi e oggetti.
func blob_shadow(radius: float, pos: Vector3 = Vector3(0, 0.03, 0), alpha: float = 0.45, target: Node3D = null) -> MeshInstance3D:
	if _blob_material == null:
		_blob_material = StandardMaterial3D.new()
		_blob_material.albedo_texture = soft_texture(64, Color(0.05, 0.1, 0.08, 1.0))
		_blob_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var instance := _add(quad, _blob_material, pos, Vector3(-PI / 2, 0, 0), Vector3.ONE, target)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.transparency = 1.0 - alpha
	return instance

static func circle_texture(size: int, color: Color, ring: Color = Color.TRANSPARENT, ring_width: float = 0.0) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var radius := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var alpha := clampf(radius - d + 0.5, 0.0, 1.0)
			var px := color
			if ring_width > 0.0 and d > radius - ring_width: px = ring
			px.a *= alpha
			image.set_pixel(x, y, px)
	return ImageTexture.create_from_image(image)

static func soft_texture(size: int, color: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5)
			var px := color
			px.a *= clampf(1.0 - d, 0.0, 1.0) ** 1.6
			image.set_pixel(x, y, px)
	return ImageTexture.create_from_image(image)
