shader_type spatial;
// The whole pitch on one plane, laid out in world space (1 unit = 1 yard):
// grass with mowing stripes, worn patches, painted lines and hash marks, team
// coloured end zones, and a rougher apron outside the lines.
// Playing field: x = 0..field_length, z = -field_width/2..field_width/2.

uniform float field_length = 100.0;
uniform float field_width = 40.0;
uniform float end_zone_depth = 10.0;
uniform vec3 left_color : source_color = vec3(0.8, 0.6, 0.1);
uniform vec3 right_color : source_color = vec3(0.7, 0.1, 0.1);
uniform vec3 grass_dark : source_color = vec3(0.07, 0.24, 0.06);
uniform vec3 grass_light : source_color = vec3(0.2, 0.46, 0.13);
uniform vec3 dirt_color : source_color = vec3(0.3, 0.24, 0.13);
uniform vec3 paint_color : source_color = vec3(0.93, 0.93, 0.9);
uniform sampler2D patch_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D blade_noise : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D blade_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 inside a band of half-width `half_w` around distance 0, antialiased over
// `aa`. The caller passes the pixel footprint of the underlying coordinate:
// taking fwidth() of `dist` itself would spike where round() jumps and paint a
// stray hairline halfway between lines.
float band(float dist, float half_w, float aa) {
	return 1.0 - smoothstep(half_w - aa, half_w + aa, abs(dist));
}

void fragment() {
	vec2 p = world_pos.xz;
	float x = p.x;
	float az = abs(p.y);
	float half_w = field_width * 0.5;

	float n_patch = texture(patch_noise, p / 41.0).r;
	float n_mid = texture(patch_noise, p / 11.0 + vec2(0.37, 0.61)).r;
	// Blades lie mostly along the mowing direction, so stretch the fine noise.
	vec2 blade_uv = p * vec2(1.6, 0.55);
	float n_blade = texture(blade_noise, blade_uv).r;
	float n_fine = texture(blade_noise, p * 2.9 + vec2(0.5, 0.2)).r;

	// Clumps a hand wide, so the grass still has grain from the game camera.
	float n_clump = texture(blade_noise, p * vec2(0.27, 0.19)).r;

	vec3 grass = mix(grass_dark, grass_light, clamp(n_blade * 0.35 + n_fine * 0.2 + n_clump * 0.45 + n_mid * 0.25 - 0.1, 0.0, 1.0));
	grass *= 0.8 + 0.4 * n_patch;
	// Dry, yellowish patches.
	grass = mix(grass, grass * vec3(1.25, 1.12, 0.7), smoothstep(0.55, 0.8, n_mid) * 0.35);

	float in_x = step(-end_zone_depth, x) * step(x, field_length + end_zone_depth);
	float in_field = in_x * step(az, half_w);
	float in_play = step(0.0, x) * step(x, field_length) * step(az, half_w);

	// Mowing stripes: alternate 5-yard bands, including the end zones.
	float cycle = fract(x / 10.0);
	float aa_c = max(fwidth(x) * 0.1, 0.0005);
	float stripe = smoothstep(0.0, aa_c, cycle) - smoothstep(0.5, 0.5 + aa_c, cycle);
	// Grass bent away from the viewer reads lighter and a little yellower.
	vec3 mown = grass * mix(vec3(0.6, 0.64, 0.66), vec3(1.3, 1.24, 1.0), stripe);
	// The apron is longer, darker, unmown grass.
	vec3 apron = grass * vec3(0.5, 0.44, 0.34) * (0.7 + 0.5 * n_mid);
	vec3 color = mix(apron, mown, in_field);

	// Wear between the hash marks, where most plays start.
	float wear = (1.0 - smoothstep(2.0, 9.0, az)) * smoothstep(0.42, 0.72, n_mid * 0.6 + n_fine * 0.4) * in_play;
	color = mix(color, dirt_color * (0.7 + 0.5 * n_fine), wear * 0.45);

	// Paint soaks into the grass unevenly.
	float soak = 0.55 + 0.45 * smoothstep(0.2, 0.75, n_blade * 0.6 + n_fine * 0.4);

	float in_left = step(-end_zone_depth, x) * step(x, 0.0) * step(az, half_w);
	float in_right = step(field_length, x) * step(x, field_length + end_zone_depth) * step(az, half_w);
	vec3 zone = mix(left_color, right_color, in_right);
	color = mix(color, zone * (0.45 + 0.4 * n_clump) * mix(0.85, 1.1, stripe), (in_left + in_right) * 0.8 * soak);

	// Yard lines every 5, heavier every 10, heaviest on the goal lines.
	float nearest5 = round(x / 5.0) * 5.0;
	float is_ten = 1.0 - step(0.01, abs(nearest5 - round(x / 10.0) * 10.0));
	float is_goal = max(1.0 - step(0.01, abs(nearest5)), 1.0 - step(0.01, abs(nearest5 - field_length)));
	float line_w = mix(mix(0.05, 0.08, is_ten), 0.18, is_goal);
	float aa_x = max(fwidth(x), 0.004);
	float aa_z = max(fwidth(p.y), 0.004);
	float paint = band(x - nearest5, line_w, aa_x) * in_play;
	// Hash marks every yard: two inner rows and one along each sideline.
	float tick = band(x - round(x), 0.045, aa_x) * in_play;
	float hash_z = field_width * 0.125;
	float rows = max(band(az - hash_z, 0.3, aa_z), band(az - (half_w - 0.75), 0.3, aa_z));
	paint = max(paint, tick * rows);
	// Border: sidelines and end lines, 0.4 wide, just outside the field.
	float out_z = az - half_w;
	float out_x = max(-end_zone_depth - x, x - (field_length + end_zone_depth));
	float border = step(0.0, max(out_z, out_x)) * step(out_z, 0.4) * step(out_x, 0.4);
	paint = max(paint, border);

	color = mix(color, paint_color * (0.78 + 0.22 * n_blade), paint * soak);

	ALBEDO = color;
	ROUGHNESS = 0.92 - 0.12 * paint;
	// Nearly matte: sky reflections at a shallow angle wash the grass out.
	SPECULAR = 0.03;
	NORMAL_MAP = texture(blade_normal, blade_uv).rgb;
	NORMAL_MAP_DEPTH = 0.9;
}
