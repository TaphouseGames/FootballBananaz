shader_type spatial;
// Dresses a player who is a whole character of his or her own (see
// PlayerParts.PEOPLE and tools/prep_player.py) in a team's kit. The model's
// own textures stay as they are for skin, hair, shoes and the rest; where the
// mask says a texel is kit, the colour texture only gives the shading and the
// team gives the colour. The number goes on the chest and the back, the name
// across the shoulders, on the jersey only.
//
// Baked into the mesh, as for kit_body.gdshader:
//   CUSTOM0  xyz = place at rest (x across, y back, z up), w = the y of the
//            normal at rest (front is negative)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic;
// r jersey, g pants, b socks; r and b together the jersey's second colour
// (the sleeves and the collar, unless painted otherwise in tools/kit_painter.gd).
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
// White on black, black too where a number's inline is: the name in the top
// quarter, the number below it. It has mipmaps (see PlayerModel._bake_kit_map):
// without them the print breaks up into sparkle on a player far from the camera.
uniform sampler2D kit_tex : filter_linear_mipmap_anisotropic, repeat_disable;

// As the model was painted, nothing repainted.
uniform bool plain = false;
uniform vec3 team_color : source_color = vec3(0.1, 0.3, 0.8);
uniform vec3 text_color : source_color = vec3(1.0);
// The home kit: white, with the team's colour where the jersey has its second.
uniform bool white_kit = false;
uniform vec3 white_color : source_color = vec3(0.94, 0.94, 0.92);
uniform vec3 pants_color : source_color = vec3(0.82, 0.78, 0.68);
// Brightness of the shading in the texture that comes out as exactly the
// colour asked for (prep_player.py paints a garment's middle tone as 0.8).
uniform float cloth_ref = 0.6;
// Centre z, half width, half height.
uniform vec3 front_number = vec3(0.6, 0.06, 0.045);
uniform vec3 back_number = vec3(0.585, 0.07, 0.052);
uniform vec3 back_name = vec3(0.672, 0.095, 0.026);

varying vec4 rest;

void vertex() {
	rest = CUSTOM0;
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
	vec3 mask = texture(mask_tex, UV).rgb;
	// Blue on the jersey is not a sock.
	float trim = min(mask.r, mask.b);
	float socks = mask.b - trim;
	float sum = mask.r + mask.g + socks;
	float cover = clamp(sum, 0.0, 1.0);
	float shade = clamp(dot(base, vec3(0.3, 0.59, 0.11)) / cloth_ref, 0.0, 1.3);

	vec3 jersey = white_kit ? mix(white_color, team_color, trim / max(mask.r, 0.001)) : team_color;
	float ink = 0.0;
	if (rest.w < -0.4) {
		ink = print_alpha(front_number, vec2(0.0, 0.25), vec2(1.0, 0.75), 1.0);
	} else if (rest.w > 0.4) {
		ink = max(print_alpha(back_number, vec2(0.0, 0.25), vec2(1.0, 0.75), -1.0),
			print_alpha(back_name, vec2(0.0), vec2(1.0, 0.25), -1.0));
	}
	jersey = mix(jersey, text_color, ink);

	vec3 kit = (jersey * mask.r + pants_color * mask.g + team_color * socks) / max(sum, 0.001);
	ALBEDO = plain ? base : mix(base, kit * shade, cover);
	ROUGHNESS = texture(rough_tex, UV).g;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
}
