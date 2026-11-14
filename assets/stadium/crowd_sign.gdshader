shader_type spatial;
// The signs the crowd holds up: one flat board per fan with a sign, a
// MultiMesh instance with the same transform, colour and custom data as its
// holder, moved the way crowd.gdshader moves the holder's raised arms.
// The front (facing the field) shows one cell of the picture of all the
// signs (see Stadium._bake_signs); the back is plain card.
render_mode specular_disabled, shadows_disabled, cull_disabled;

#include "crowd_motion.gdshaderinc"

uniform sampler2D sign_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 sign_grid = vec2(4.0, 4.0);
// A sign is paper in the sun: brighter than the people round it.
uniform float sign_dim = 0.9;
uniform float self_lit = 0.4;
uniform vec3 back_color : source_color = vec3(0.55, 0.5, 0.42);

varying vec2 cell_uv;


void vertex() {
	// The alpha also carries the colour of the holder's trousers (see crowd.gdshader).
	Motion m = crowd_motion(INSTANCE_CUSTOM, mod(COLOR.a, 2.0));
	vec3 v = crowd_rock(VERTEX, m.rock, shoulder.y);
	NORMAL = crowd_rock(NORMAL, m.rock, 0.0);
	// Carried by the shoulders, so it leans as far as they do.
	VERTEX = crowd_settle(v, m, shoulder.y);
	float cells = sign_grid.x * sign_grid.y;
	float cell = floor(clamp(INSTANCE_CUSTOM.w * cells, 0.0, cells - 1.0));
	cell_uv = (vec2(mod(cell, sign_grid.x), floor(cell / sign_grid.x)) + UV) / sign_grid;
}


void fragment() {
	vec3 colour = FRONT_FACING ? texture(sign_atlas, cell_uv).rgb * sign_dim : back_color * 0.6;
	ALBEDO = colour * (1.0 - self_lit);
	EMISSION = colour * self_lit;
	ROUGHNESS = 1.0;
}
