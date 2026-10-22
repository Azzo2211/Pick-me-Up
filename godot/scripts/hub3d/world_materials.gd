extends RefCounted
class_name WorldMaterials

## Materiali condivisi del mondo 3D (base e missioni). Ogni variante viene
## creata una volta sola e riusata da tutti gli edifici e gli oggetti.

const TerrainShader := preload("res://scripts/hub3d/shaders/terrain.gdshader")
const StoneShader := preload("res://scripts/hub3d/shaders/stone.gdshader")
const PlasterShader := preload("res://scripts/hub3d/shaders/plaster.gdshader")
const WoodShader := preload("res://scripts/hub3d/shaders/wood.gdshader")
const RoofShader := preload("res://scripts/hub3d/shaders/roof.gdshader")
const FoliageShader := preload("res://scripts/hub3d/shaders/foliage.gdshader")
const HighlightShader := preload("res://scripts/hub3d/shaders/highlight.gdshader")
const MistShader := preload("res://scripts/hub3d/shaders/mist.gdshader")

static var _cache: Dictionary = {}

static func _put(key: String, m: Material) -> Material:
	_cache[key] = m
	return m

static func fallback() -> Material:
	return lit(Color.WHITE)

## Materiale semplice che usa i colori dei vertici (stoffa, pelle, oggetti).
static func lit(tint: Color = Color.WHITE, roughness: float = 0.9) -> StandardMaterial3D:
	var key := "lit|%s|%.2f" % [tint.to_html(), roughness]
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.metallic_specular = 0.3
	return _put(key, m)

static func metal(tint: Color = Color.WHITE, roughness: float = 0.42, metallic: float = 0.75) -> StandardMaterial3D:
	var key := "metal|%s|%.2f|%.2f" % [tint.to_html(), roughness, metallic]
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = metallic
	m.roughness = roughness
	m.metallic_specular = 0.6
	return _put(key, m)

static func glow(color: Color, energy: float = 2.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "glow|%s|%.2f|%s" % [color.to_html(), energy, unshaded]
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _put(key, m)

## Vetro delle finestre illuminate dall'interno.
static func window(color: Color = Color("#ffb45e"), energy: float = 1.6) -> StandardMaterial3D:
	var key := "window|%s|%.2f" % [color.to_html(), energy]
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.3)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	return _put(key, m)

static func transparent(color: Color, unshaded: bool = true, energy: float = 0.0) -> StandardMaterial3D:
	var key := "alpha|%s|%s|%.2f" % [color.to_html(), unshaded, energy]
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if unshaded: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = energy
	return _put(key, m)

const TERRAIN_COLORS := {
	"grass_dark": Color("#2f4419"), "grass_light": Color("#5f7c2c"), "grass_dry": Color("#8d8443"),
	"dirt_color": Color("#5a4431"), "dirt_light": Color("#8a7255"),
	"cobble_a": Color("#8c867b"), "cobble_b": Color("#67625b"), "gap_color": Color("#2a2621"),
	"rock_a": Color("#857668"), "rock_b": Color("#4b433d"), "moss_color": Color("#3f4d22"),
}

static func terrain() -> ShaderMaterial:
	if _cache.has("terrain"): return _cache["terrain"]
	var m := ShaderMaterial.new()
	m.shader = TerrainShader
	for key in TERRAIN_COLORS: m.set_shader_parameter(key, TERRAIN_COLORS[key])
	return _put("terrain", m)

## Terreno per i biomi delle missioni: stesso shader con altri colori.
static func terrain_biome(grass_dark: Color, grass_light: Color, dry: Color, dirt: Color) -> ShaderMaterial:
	var key := "terrain|%s|%s" % [grass_dark.to_html(), dirt.to_html()]
	if _cache.has(key): return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TerrainShader
	for k in TERRAIN_COLORS: m.set_shader_parameter(k, TERRAIN_COLORS[k])
	m.set_shader_parameter("grass_dark", grass_dark)
	m.set_shader_parameter("grass_light", grass_light)
	m.set_shader_parameter("grass_dry", dry)
	m.set_shader_parameter("dirt_color", dirt)
	m.set_shader_parameter("dirt_light", dirt.lightened(0.3))
	return _put(key, m)

const STONE_VARIANTS := {
	"wall": [Color("#8f877c"), Color("#6c665e"), Color("#3b3732"), Vector2(0.62, 0.3), 0.35],
	"dark": [Color("#5d5a58"), Color("#45423f"), Color("#24211f"), Vector2(0.7, 0.34), 0.3],
	"pale": [Color("#b9b2a5"), Color("#a29a8c"), Color("#5f5850"), Vector2(0.9, 0.42), 0.15],
	"rubble": [Color("#7d766b"), Color("#5b554e"), Color("#2e2a26"), Vector2(0.42, 0.26), 0.5],
	"paving": [Color("#7f786e"), Color("#655f57"), Color("#2c2925"), Vector2(0.85, 0.85), 0.25],
	"basalt": [Color("#3e3c45"), Color("#2c2a31"), Color("#141218"), Vector2(0.8, 0.4), 0.1],
}

static func stone(variant: String = "wall") -> ShaderMaterial:
	var key := "stone|" + variant
	if _cache.has(key): return _cache[key]
	var v: Array = STONE_VARIANTS.get(variant, STONE_VARIANTS["wall"])
	var m := ShaderMaterial.new()
	m.shader = StoneShader
	m.set_shader_parameter("tint_a", v[0])
	m.set_shader_parameter("tint_b", v[1])
	m.set_shader_parameter("mortar", v[2])
	m.set_shader_parameter("block", v[3])
	m.set_shader_parameter("moss", v[4])
	return _put(key, m)

const PLASTER_VARIANTS := {
	"warm": [Color("#c4ad8c"), Color("#8a7458")],
	"white": [Color("#cfc6b6"), Color("#8f8778")],
	"ochre": [Color("#b8935f"), Color("#7d6140")],
	"grey": [Color("#9e978c"), Color("#6b655d")],
}

static func plaster(variant: String = "warm") -> ShaderMaterial:
	var key := "plaster|" + variant
	if _cache.has(key): return _cache[key]
	var v: Array = PLASTER_VARIANTS.get(variant, PLASTER_VARIANTS["warm"])
	var m := ShaderMaterial.new()
	m.shader = PlasterShader
	m.set_shader_parameter("base_color", v[0])
	m.set_shader_parameter("stain_color", v[1])
	return _put(key, m)

const WOOD_VARIANTS := {
	"timber": [Color("#4a3322"), Color("#2a1b12"), 0.0],
	"dark": [Color("#33241a"), Color("#1a120d"), 0.0],
	"light": [Color("#7a5c3e"), Color("#4b3523"), 0.0],
	"planks": [Color("#5a4029"), Color("#2e2016"), 0.22],
	"weathered": [Color("#6b6158"), Color("#3d3631"), 0.0],
	"bark": [Color("#3d2f25"), Color("#1e1712"), 0.0],
}

static func wood(variant: String = "timber") -> ShaderMaterial:
	var key := "wood|" + variant
	if _cache.has(key): return _cache[key]
	var v: Array = WOOD_VARIANTS.get(variant, WOOD_VARIANTS["timber"])
	var m := ShaderMaterial.new()
	m.shader = WoodShader
	m.set_shader_parameter("base_color", v[0])
	m.set_shader_parameter("dark_color", v[1])
	m.set_shader_parameter("planks", v[2])
	return _put(key, m)

const ROOF_VARIANTS := {
	"slate": [Color("#454c58"), Color("#2c313a"), 0, Vector2(0.24, 0.16), 0.25],
	"slate_blue": [Color("#3d4a66"), Color("#262e42"), 0, Vector2(0.24, 0.16), 0.15],
	"clay": [Color("#7a3b2c"), Color("#57291f"), 0, Vector2(0.2, 0.15), 0.3],
	"shingle": [Color("#5b4532"), Color("#3a2b1f"), 1, Vector2(0.28, 0.2), 0.35],
	"thatch": [Color("#8d7445"), Color("#5e4b2b"), 2, Vector2(0.3, 0.2), 0.2],
	"copper": [Color("#4e8478"), Color("#3a6158"), 0, Vector2(0.3, 0.2), 0.0],
	"violet": [Color("#4a3b66"), Color("#2f2645"), 0, Vector2(0.24, 0.16), 0.05],
}

static func roof(variant: String = "slate") -> ShaderMaterial:
	var key := "roof|" + variant
	if _cache.has(key): return _cache[key]
	var v: Array = ROOF_VARIANTS.get(variant, ROOF_VARIANTS["slate"])
	var m := ShaderMaterial.new()
	m.shader = RoofShader
	m.set_shader_parameter("tile_a", v[0])
	m.set_shader_parameter("tile_b", v[1])
	m.set_shader_parameter("style", v[2])
	m.set_shader_parameter("tile", v[3])
	m.set_shader_parameter("moss", v[4])
	return _put(key, m)

static func foliage(textured: bool = false) -> ShaderMaterial:
	var key := "foliage|%s" % textured
	if _cache.has(key): return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = FoliageShader
	m.set_shader_parameter("use_texture", textured)
	if textured: m.set_shader_parameter("leaf_tex", leaf_texture())
	return _put(key, m)

static func mist(low: Color, high: Color, density: float = 0.75, scale: float = 0.035) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = MistShader
	m.set_shader_parameter("color_low", low)
	m.set_shader_parameter("color_high", high)
	m.set_shader_parameter("density", density)
	m.set_shader_parameter("scale", scale)
	return m

## Overlay per evidenziare un oggetto (ogni edificio ha la sua istanza).
static func highlight() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HighlightShader
	return m

## Texture di un ciuffo di foglie (scala di grigi + alfa) generata una volta.
static func leaf_texture() -> ImageTexture:
	if _cache.has("leaf_tex"): return _cache["leaf_tex"]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 1337
	for i in 170:
		var c := Vector2(r.randf_range(10, size - 10), r.randf_range(10, size - 10))
		var to_center := (c - Vector2(size, size) * 0.5).length() / (size * 0.5)
		if to_center > 0.95 or (to_center > 0.75 and r.randf() < 0.5): continue
		var angle := r.randf_range(0, TAU)
		var length := r.randf_range(6.0, 11.0)
		var width := length * r.randf_range(0.38, 0.5)
		var shade := r.randf_range(0.55, 1.0)
		var dir := Vector2(cos(angle), sin(angle))
		var side := Vector2(-dir.y, dir.x)
		var x0 := int(c.x - length) - 1
		var y0 := int(c.y - length) - 1
		for y in range(maxi(0, y0), mini(size, y0 + int(length * 2) + 3)):
			for x in range(maxi(0, x0), mini(size, x0 + int(length * 2) + 3)):
				var d := Vector2(x + 0.5, y + 0.5) - c
				var along := d.dot(dir) / length
				var across := d.dot(side) / width
				var k := along * along + across * across
				if k <= 1.0:
					var vein := 1.0 - 0.18 * clampf(1.0 - absf(across) * 6.0, 0.0, 1.0)
					var light := shade * (0.85 + 0.15 * along) * vein
					img.set_pixel(x, y, Color(light, light, light, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["leaf_tex"] = tex
	return tex

## Texture rotonda sfumata (fumo, aloni, chiazze di luce), messa in cache.
static func soft_texture(size: int, color: Color) -> ImageTexture:
	var key := "softtex|%d|%s" % [size, color.to_html()]
	if _cache.has(key): return _cache[key]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5)
			var px := color
			px.a *= clampf(1.0 - d, 0.0, 1.0) ** 1.6
			image.set_pixel(x, y, px)
	var tex := ImageTexture.create_from_image(image)
	_cache[key] = tex
	return tex

## Disco morbido per ombre e aloni.
static func soft_disc(color: Color = Color(0.02, 0.02, 0.03, 0.6)) -> StandardMaterial3D:
	var key := "soft|%s" % color.to_html()
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft_texture(64, color)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _put(key, m)
