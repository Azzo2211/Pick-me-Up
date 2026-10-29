extends RefCounted
class_name WorldLook

## Luce e atmosfera condivise da base e missioni: cielo, nebbia, sole, luce di
## riempimento e regolazioni del colore. "preset": dusk, day, night.

const SkyShader := preload("res://scripts/hub3d/shaders/sky.gdshader")

## Qualità grafica scelta nelle Impostazioni (vedi GameState.quality()).
static var quality := "high"

## Applica antialias e filtri della qualità scelta alla finestra di gioco.
static func apply_quality(viewport: Viewport, level: String) -> void:
	quality = level
	if viewport == null: return
	viewport.msaa_3d = Viewport.MSAA_4X if level == "high" else Viewport.MSAA_2X if level == "medium" else Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA

const PRESETS := {
	"dusk": {
		"zenith": Color("#1b2550"), "upper": Color("#4e4f86"), "horizon": Color("#f0a46a"), "horizon_far": Color("#a77790"), "below": Color("#2a2340"),
		"sun_color": Color("#ffc184"), "cloud": Color("#c98a86"), "stars": 0.25,
		"sun_rot": Vector3(-36, 152, 0), "sun_energy": 1.75, "light": Color("#ffc896"),
		"fill_rot": Vector3(-40, -30, 0), "fill_energy": 0.38, "fill": Color("#8e9be0"),
		"ambient": Color("#8b8fc0"), "ambient_energy": 0.75, "sky_contrib": 0.55,
		"fog": Color("#9d7f97"), "fog_density": 0.0028, "fog_height": -3.0, "fog_height_density": 0.16,
		"exposure": 1.12, "saturation": 1.12, "contrast": 1.06,
		"mist_low": Color("#3b2c48"), "mist_high": Color("#c79486"),
		"water_base": Color("#1a2133"), "water_sky": Color("#9e666b"), "water_foam": Color("#d9ccd9"),
	},
	"day": {
		"zenith": Color("#2f5fa8"), "upper": Color("#5f8fd0"), "horizon": Color("#d8e4ef"), "horizon_far": Color("#b7c9dc"), "below": Color("#4a5a70"),
		"sun_color": Color("#fff2d6"), "cloud": Color("#e8eef5"), "stars": 0.0,
		"sun_rot": Vector3(-52, 140, 0), "sun_energy": 1.6, "light": Color("#fff1dc"),
		"fill_rot": Vector3(-40, -30, 0), "fill_energy": 0.3, "fill": Color("#a9c4ff"),
		"ambient": Color("#a9b8cf"), "ambient_energy": 0.7, "sky_contrib": 0.6,
		"fog": Color("#a9bbd0"), "fog_density": 0.0016, "fog_height": -3.0, "fog_height_density": 0.1,
		"exposure": 0.95, "saturation": 1.1, "contrast": 1.08,
		"mist_low": Color("#7d93b3"), "mist_high": Color("#eef2f8"),
		"water_base": Color("#1d3a57"), "water_sky": Color("#8fb4d8"), "water_foam": Color("#eef4f8"),
	},
	"night": {
		"zenith": Color("#05070f"), "upper": Color("#121a33"), "horizon": Color("#2a3157"), "horizon_far": Color("#1a2040"), "below": Color("#080a14"),
		"sun_color": Color("#b9c8ff"), "cloud": Color("#2c3352"), "stars": 1.0,
		"sun_rot": Vector3(-48, 200, 0), "sun_energy": 0.55, "light": Color("#9fb3ff"),
		"fill_rot": Vector3(-40, -30, 0), "fill_energy": 0.22, "fill": Color("#5d6fb8"),
		"ambient": Color("#4a5888"), "ambient_energy": 0.7, "sky_contrib": 0.4,
		"fog": Color("#2c3456"), "fog_density": 0.006, "fog_height": -3.0, "fog_height_density": 0.18,
		"exposure": 1.2, "saturation": 1.0, "contrast": 1.08,
		"mist_low": Color("#0e1222"), "mist_high": Color("#36406a"),
		"water_base": Color("#0a0f1c"), "water_sky": Color("#33427a"), "water_foam": Color("#8f9cc9"),
	},
}

## Crea ambiente e luci sotto "parent". Restituisce i nodi creati.
static func setup(parent: Node3D, preset_name: String = "dusk", overrides: Dictionary = {}, shadow_distance: float = 120.0) -> Dictionary:
	var p: Dictionary = PRESETS.get(preset_name, PRESETS["dusk"]).duplicate()
	p.merge(overrides, true)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SkyShader
	sky_mat.set_shader_parameter("zenith", p.zenith)
	sky_mat.set_shader_parameter("upper", p.upper)
	sky_mat.set_shader_parameter("horizon", p.horizon)
	sky_mat.set_shader_parameter("horizon_far", p.horizon_far)
	sky_mat.set_shader_parameter("below", p.below)
	sky_mat.set_shader_parameter("sun_color", p.sun_color)
	sky_mat.set_shader_parameter("cloud_color", p.cloud)
	sky_mat.set_shader_parameter("stars", p.stars)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = p.ambient
	env.ambient_light_energy = p.ambient_energy
	env.ambient_light_sky_contribution = p.sky_contrib
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = p.exposure
	env.tonemap_white = 6.0
	# occlusione e luce rimbalzata in screen space (renderer Forward+): volumi,
	# angoli e contatti col terreno prendono profondità
	env.ssao_enabled = quality != "low"
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.8
	env.ssao_power = 1.6
	env.ssao_detail = 0.7
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.12
	env.ssil_enabled = quality == "high"
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.7
	env.ssil_normal_rejection = 1.0
	env.fog_enabled = true
	env.fog_light_color = p.fog
	env.fog_density = p.fog_density
	env.fog_sky_affect = 0.12
	env.fog_height = p.fog_height
	env.fog_height_density = p.fog_height_density
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = p.saturation
	env.adjustment_contrast = p.contrast
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = p.sun_rot
	sun.light_color = p.light
	sun.light_energy = p.sun_energy
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.82
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = shadow_distance
	sun.directional_shadow_fade_start = 0.9
	parent.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = p.fill_rot
	fill.light_color = p.fill
	fill.light_energy = p.fill_energy
	fill.shadow_enabled = false
	fill.light_specular = 0.1
	parent.add_child(fill)
	return {"environment": env, "world_environment": we, "sun": sun, "fill": fill, "sky": sky_mat, "preset": p}
