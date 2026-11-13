shader_type spatial;
// Dresses a base model (see PlayerModel) as one player: skin in his own
// colour, the jersey in the team's with his number front and back and his
// name across the shoulders, and his face painted on the blank head.
//
// What is skin and what is jersey goes by where a texel is on the model as it
// stands at rest, which PlayerModel bakes into the mesh:
//   COLOR    r = share of the head and neck bones, g = share of the hand bones,
//            b = share of the arm bones
//   CUSTOM0  xyz = place at rest in the mesh's own space (x across, y back,
//            z up, 1 tall), w = the y of the normal at rest (front is negative)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
// The face, unrolled round the head: PlayerModel's FacePainter.
uniform sampler2D face_tex : source_color, filter_linear, repeat_enable;
// White on clear: the name in the top quarter, the number below it.
uniform sampler2D kit_tex : filter_linear, repeat_disable;

uniform vec3 skin_color : source_color = vec3(0.82, 0.62, 0.46);
uniform vec3 team_color : source_color = vec3(0.1, 0.3, 0.8);
uniform vec3 text_color : source_color = vec3(1.0);
// The home kit: white, with the team's colour on the sleeves.
uniform bool white_kit = false;
// The pants, whatever the jersey is, and how much lighter than it is painted
// everything else is shown (leather, boots, socks): the base models are
// painted dark, and on the field under the sun that came out nearly black.
uniform vec3 pants_color : source_color = vec3(0.82, 0.78, 0.68);
uniform float base_gain = 1.7;
uniform vec3 white_color : source_color = vec3(0.94, 0.94, 0.92);
// Brightness of the painted skin and cloth that comes out as exactly the
// colour asked for.
uniform float skin_ref = 0.15;
uniform float cloth_ref = 0.11;
// Red over blue of a texel at which cloth starts to count as leather, and at
// which it fully does.
uniform float leather_low = 3.4;
uniform float leather_high = 5.0;

// The axis the face is unrolled round (y), the bottom and the top of the map (z).
uniform vec3 head_map = vec3(0.0, 0.76, 1.0);
uniform float chin_z = 0.76;
uniform float belt_z = 0.5;
// Skin is not one flat colour: how much it varies in tone from place to
// place, how much its pores show, and how much redder it is on the cheeks,
// the ears and the chin.
uniform float skin_mottle = 0.16;
uniform float skin_pores = 0.1;
uniform float skin_blush = 0.3;
// Centre z, half width, half height.
uniform vec3 front_number = vec3(0.64, 0.06, 0.045);
uniform vec3 back_number = vec3(0.62, 0.072, 0.054);
uniform vec3 back_name = vec3(0.7, 0.085, 0.021);

varying vec4 rest;
varying vec3 share;

void vertex() {
	rest = CUSTOM0;
	share = COLOR.rgb;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Smooth noise, 0..1, the same at the same place on the model in any pose.
float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float low = mix(mix(hash3(cell), hash3(cell + vec3(1.0, 0.0, 0.0)), f.x),
		mix(hash3(cell + vec3(0.0, 1.0, 0.0)), hash3(cell + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float high = mix(mix(hash3(cell + vec3(0.0, 0.0, 1.0)), hash3(cell + vec3(1.0, 0.0, 1.0)), f.x),
		mix(hash3(cell + vec3(0.0, 1.0, 1.0)), hash3(cell + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(low, high, f.z);
}

// 1 at `at` (turn round the head, height on it), fading out over `size`.
float patch_at(vec2 where, vec2 at, vec2 size) {
	vec2 d = (where - at) / size;
	return exp(-dot(d, d));
}

float print_alpha(vec3 box, vec2 cell_from, vec2 cell_size, float side) {
	vec2 uv = vec2(side * rest.x / box.y, (box.x - rest.z) / box.z) * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(kit_tex, cell_from + uv * cell_size).a;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	float luma = dot(base, vec3(0.3, 0.59, 0.11));

	float head = smoothstep(0.35, 0.65, share.r);
	float hand = smoothstep(0.4, 0.6, share.g);
	float skin = max(head, hand);
	// The neck runs into the collar: there the cloth is told by its yellow.
	float yellow = base.g / max(base.b, 0.0005);
	float collar = smoothstep(1.75, 2.1, yellow) * (1.0 - smoothstep(head_map.y + 0.03, head_map.y + 0.07, rest.z));
	skin *= 1.0 - collar * (1.0 - hand);

	float arm = smoothstep(0.4, 0.6, share.b);
	float upper = max(arm, smoothstep(belt_z - 0.004, belt_z + 0.004, rest.z));
	float warmth = base.r / max(base.b, 0.0005);
	float cloth = 1.0 - smoothstep(leather_low, leather_high, warmth);
	float jersey = upper * cloth * (1.0 - skin);

	vec3 kit = white_kit ? mix(white_color, team_color, arm) : team_color;
	float ink = 0.0;
	if (rest.w < -0.15) {
		ink = print_alpha(front_number, vec2(0.0, 0.25), vec2(1.0, 0.75), 1.0);
	} else if (rest.w > 0.15) {
		ink = max(print_alpha(back_number, vec2(0.0, 0.25), vec2(1.0, 0.75), -1.0),
			print_alpha(back_name, vec2(0.0), vec2(1.0, 0.25), -1.0));
	}
	kit = mix(kit, text_color, ink * (1.0 - arm));

	vec3 color = base * base_gain;
	float cloth_shade = clamp(luma / cloth_ref, 0.0, 1.35);
	// Boots and belts are painted dark: they stay leather.
	color = mix(color, pants_color * cloth_shade, (1.0 - upper) * cloth * (1.0 - skin) * smoothstep(0.035, 0.075, luma));
	color = mix(color, kit * cloth_shade, jersey);
	vec3 skin_paint = skin_color * clamp(luma / skin_ref, 0.0, 1.5);
	// The face: unrolled round the head, the front in the middle.
	float angle = atan(rest.x, -(rest.y - head_map.x));
	// Tone that wanders, pores, and blood under the thin skin.
	float mottle = noise3(rest.xyz * 34.0) * 0.6 + noise3(rest.xyz * 85.0) * 0.4;
	float pores = noise3(rest.xyz * 520.0);
	skin_paint *= 1.0 + (mottle - 0.5) * 2.0 * skin_mottle;
	skin_paint *= 1.0 - skin_pores * smoothstep(0.45, 0.9, pores);
	vec2 on_face = vec2(abs(angle), (rest.z - chin_z) / (head_map.z - chin_z));
	float blush = patch_at(on_face, vec2(0.75, 0.27), vec2(0.4, 0.13))
		+ 0.8 * patch_at(on_face, vec2(1.6, 0.42), vec2(0.3, 0.14))
		+ 0.5 * patch_at(on_face, vec2(0.0, 0.03), vec2(0.5, 0.08));
	blush = clamp(blush * head + hand * 0.35 * mottle, 0.0, 1.0);
	skin_paint = mix(skin_paint, skin_paint * vec3(1.16, 0.84, 0.82), blush * skin_blush);
	// The jaw's shadow on the neck.
	skin_paint *= 1.0 - 0.22 * head * smoothstep(chin_z + 0.012, chin_z - 0.03, rest.z) * smoothstep(-0.2, -0.05, -abs(angle) + 1.5);
	vec2 face_uv = vec2(angle / TAU + 0.5, (head_map.z - rest.z) / (head_map.z - head_map.y));
	vec4 face = texture(face_tex, face_uv);
	float on_head = head * step(0.0, face_uv.y) * step(face_uv.y, 1.0);
	// The paint takes the shading of the skin under it, but less of it.
	vec3 face_paint = face.rgb * mix(1.0, clamp(luma / skin_ref, 0.0, 1.5), 0.5);
	skin_paint = mix(skin_paint, face_paint, face.a * on_head);
	color = mix(color, skin_paint, skin);

	ALBEDO = color;
	ROUGHNESS = mix(0.85, 0.5 + 0.25 * pores, skin);
	SPECULAR = mix(0.5, 0.35, skin);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.6;
}
