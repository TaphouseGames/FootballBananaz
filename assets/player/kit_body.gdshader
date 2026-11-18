shader_type spatial;
// Dresses a uniform body (white all over, no skin: see tests/base_proof.gd) in
// a team's kit: jersey, pants, socks, boots and gloves each in a colour of
// their own, the number front and back and the name across the shoulders.
// The texture only gives the shading.
//
// What is what goes by where a texel is on the model as it stands at rest,
// baked into the mesh:
//   COLOR    r = share of the head and neck bones (the collar), g = of the hand
//            bones, b = of the arm bones, a = of the foot bones
//   CUSTOM0  xyz = place at rest in the mesh's own space (x across, y back,
//            z up), w = the y of the normal at rest (front is negative)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
// White on black, black too where a number's inline is: the name in the top
// quarter, the number below it. It has mipmaps (see PlayerModel._bake_kit_map):
// without them the print breaks up into sparkle on a player far from the camera.
uniform sampler2D kit_tex : filter_linear_mipmap_anisotropic, repeat_disable;

// As the model was painted, nothing repainted.
uniform bool plain = false;
uniform vec3 team_color : source_color = vec3(0.1, 0.3, 0.8);
uniform vec3 text_color : source_color = vec3(1.0);
// The home kit: white, with the team's colour on the sleeves and the collar.
uniform bool white_kit = false;
uniform vec3 white_color : source_color = vec3(0.94, 0.94, 0.92);
uniform vec3 pants_color : source_color = vec3(0.82, 0.78, 0.68);
uniform vec3 boot_color : source_color = vec3(0.16, 0.1, 0.07);
uniform vec3 glove_color : source_color = vec3(0.3, 0.19, 0.11);
// Brightness of the painted cloth that comes out as exactly the colour asked for.
uniform float cloth_ref = 0.62;
// Heights at rest: the waistband, the hem of the pants and the top of the boots.
uniform float belt_z = 0.47;
uniform float hem_z = 0.19;
uniform float boot_z = 0.109;
// Centre z, half width, half height.
uniform vec3 front_number = vec3(0.6, 0.06, 0.045);
uniform vec3 back_number = vec3(0.585, 0.07, 0.052);
uniform vec3 back_name = vec3(0.672, 0.095, 0.026);

varying vec4 rest;
varying vec4 share;

void vertex() {
	rest = CUSTOM0;
	share = COLOR;
}

float print_alpha(vec3 box, vec2 cell_from, vec2 cell_size, float side) {
	vec2 uv = vec2(side * rest.x / box.y, (box.x - rest.z) / box.z) * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	// White is ink; black is the gap between a number and its outline, where
	// the jersey shows.
	vec4 print = texture(kit_tex, cell_from + uv * cell_size);
	return print.a * print.r;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	float luma = dot(base, vec3(0.3, 0.59, 0.11));
	float shade = clamp(luma / cloth_ref, 0.0, 1.3);

	float collar = smoothstep(0.45, 0.7, share.r);
	float hand = smoothstep(0.4, 0.6, share.g);
	float arm = smoothstep(0.4, 0.6, share.b);
	float boot = max(smoothstep(0.4, 0.6, share.a), 1.0 - smoothstep(boot_z - 0.004, boot_z + 0.004, rest.z));
	float upper = max(arm, smoothstep(belt_z - 0.004, belt_z + 0.004, rest.z));
	float sock = 1.0 - smoothstep(hem_z - 0.004, hem_z + 0.004, rest.z);

	vec3 jersey = white_kit ? mix(white_color, team_color, max(arm, collar)) : team_color;
	float ink = 0.0;
	if (rest.w < -0.15) {
		ink = print_alpha(front_number, vec2(0.0, 0.25), vec2(1.0, 0.75), 1.0);
	} else if (rest.w > 0.15) {
		ink = max(print_alpha(back_number, vec2(0.0, 0.25), vec2(1.0, 0.75), -1.0),
			print_alpha(back_name, vec2(0.0), vec2(1.0, 0.25), -1.0));
	}
	jersey = mix(jersey, text_color, ink * (1.0 - arm));

	vec3 color = mix(pants_color, team_color, sock);
	color = mix(color, jersey, upper);
	color = mix(color, boot_color, boot * (1.0 - upper));
	color = mix(color, glove_color, hand);

	ALBEDO = plain ? base : color * shade;
	ROUGHNESS = 0.85;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.6;
}
