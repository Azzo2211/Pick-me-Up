shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, cull_disabled;

#define CUTOUT
#include "res://scripts/hub3d/shaders/foliage_common.gdshaderinc"
