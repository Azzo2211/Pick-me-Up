shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Capelli del kit: colore dell'eroe, radici e strato interno più scuri, ombra a due
// toni e l'"anello di luce" degli anime sulla parte alta della testa, spezzato in
// ciocche. Le coordinate del modello sono quelle della testa (y in alto).
#include "res://scripts/hub3d/shaders/toon.gdshaderinc"

uniform vec3 hair_color : source_color = vec3(0.3, 0.22, 0.16);
uniform vec3 tie_color : source_color = vec3(0.45, 0.2, 0.18);
uniform float ring_y = 0.222;
uniform float ring_strength = 0.55;

varying vec3 local_pos;
varying vec3 local_n;
varying vec2 shade;

void vertex() {
	local_pos = VERTEX;
	local_n = NORMAL;
	shade = UV2;
}

void fragment() {
	vec3 col = hair_color * shade.y;
	if (shade.x > 0.5 && shade.x < 1.5) col *= 0.74;
	if (shade.x > 1.5) col = tie_color;
	// anello di luce: fascia chiara sulla calotta, spezzata dalle ciocche
	float ang = atan(local_pos.x, local_pos.z + 0.01);
	float wob = sin(ang * 23.0) * 0.006 + sin(ang * 9.0 + 1.3) * 0.004;
	float h = local_pos.y + wob;
	float band = smoothstep(ring_y - 0.012, ring_y - 0.004, h) * (1.0 - smoothstep(ring_y + 0.006, ring_y + 0.016, h));
	float up = smoothstep(0.1, 0.5, local_n.y + 0.35);
	float facing = smoothstep(0.25, 0.7, dot(NORMAL, VIEW));
	float strands = smoothstep(0.1, 0.5, sin(ang * 31.0) * 0.5 + 0.5);
	float hl = band * facing * up * strands * ring_strength * step(shade.x, 1.5);
	col = mix(col, col * 1.55 + vec3(0.07), hl);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	AO = toon_ambient;
	AO_LIGHT_AFFECT = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = ALBEDO * rim * toon_rim;
}
