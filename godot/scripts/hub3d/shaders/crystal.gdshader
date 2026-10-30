shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Cristallo del Nexus: facce lucide, bordo che si accende in controluce e
// venature di energia che salgono lentamente all'interno.
#include "res://scripts/hub3d/shaders/noise.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.04, 0.16, 0.42);
uniform vec3 glow : source_color = vec3(0.42, 0.84, 1.0);
uniform float energy = 2.4;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float swirl = vnoise(lpos.xz * 5.0 + vec2(0.0, TIME * 0.3)) * 3.0;
	float band = sin(lpos.y * 8.0 - TIME * 1.4 + swirl) * 0.5 + 0.5;
	float veins = smoothstep(0.7, 1.0, band);
	float core = smoothstep(0.5, 0.0, length(lpos.xz)) * 0.5;
	ALBEDO = deep;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	EMISSION = glow * energy * (0.18 + fres * 0.9 + veins * 0.5 + core * 0.4);
}
