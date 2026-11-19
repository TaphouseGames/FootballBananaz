shader_type spatial;
// The whole pitch on one plane, laid out in world space (1 unit = 1 yard):
// grass with mowing stripes, worn patches, painted yard lines, hash marks and
// yard numbers, team coloured end zones, the two mascots at midfield, and a
// rougher apron under the stands. There are no sidelines or end lines: the
// wall is the edge, and the turf runs `margin` past the lines to meet it.
// Playing field: x = 0..field_length, z = -field_width/2..field_width/2.

uniform float field_length = 100.0;
uniform float field_width = 53.33;
uniform float end_zone_depth = 10.0;
// How far past the lines the mown turf goes, on all four sides.
uniform float margin = 0.9;
uniform vec3 left_color : source_color = vec3(0.8, 0.6, 0.1);
uniform vec3 right_color : source_color = vec3(0.7, 0.1, 0.1);
uniform vec3 grass_dark : source_color = vec3(0.07, 0.24, 0.06);
uniform vec3 grass_light : source_color = vec3(0.2, 0.46, 0.13);
uniform vec3 dirt_color : source_color = vec3(0.3, 0.24, 0.13);
uniform vec3 paint_color : source_color = vec3(0.93, 0.93, 0.9);
uniform sampler2D patch_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D blade_noise : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D blade_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
// The mascots painted either side of the 50, each on its team's half. Both
// pictures look to their right; the right-hand one is drawn mirrored, so the
// two face each other. Their heads are toward -z.
uniform sampler2D left_mascot : source_color, hint_default_transparent, repeat_disable, filter_linear_mipmap_anisotropic;
uniform sampler2D right_mascot : source_color, hint_default_transparent, repeat_disable, filter_linear_mipmap_anisotropic;
// Side of the square each mascot is painted in, and its gap to the 50.
uniform float mascot_size = 8.0;
uniform float mascot_gap = 0.5;
// Yard numbers: how far in from the side the row's middle is, half the width
// and height of one digit, the thickness of its strokes and its gap to the line.
uniform float number_inset = 11.0;
// The two inner rows of hash marks: yards from the middle of the field to each
// (18 feet 6 inches apart, as in the NFL).
uniform float hash_offset = 3.08;
uniform vec2 digit_half = vec2(0.7, 1.15);
uniform float digit_stroke = 0.34;
uniform float digit_gap = 0.42;
// The lettering Field draws once with a real typeface (Field._bake_paint): a
// row of the numerals 0 to 5, each filling its cell, and under it a row for
// each end zone's name (red: the paint, green: its outline). `atlas_rows` is
// the height of the numerals' row and of one name's row, as shares of the
// picture. Until it is there (and when nothing is drawn, headless) the
// numerals are the plain ones of numeral().
uniform sampler2D paint_atlas : hint_default_black, repeat_disable, filter_linear_mipmap_anisotropic;
uniform bool painted = false;
uniform vec2 atlas_rows = vec2(0.46, 0.27);
// Yards a name's row takes up in its end zone: along the goal line, and deep.
uniform vec2 name_size = vec2(38.4, 6.0);
// What lies round the stadium: yards from the lines to the outside of the
// bowl (0: no stadium, and the grass just runs on), then a paved walk
// `plaza_width` wide, then a car park `parking_width` wide, then grass.
uniform float bowl_reach = 0.0;
uniform float plaza_width = 9.0;
uniform float parking_width = 34.0;
uniform vec3 paving_color : source_color = vec3(0.46, 0.45, 0.43);
uniform vec3 asphalt_color : source_color = vec3(0.1, 0.1, 0.11);

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

// Signed distance to a box of half-size `half_size` centred on `centre`.
float box(vec2 q, vec2 centre, vec2 half_size) {
	vec2 d = abs(q - centre) - half_size;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

// Signed distance to the block numeral `digit` (0 to 5: all a field needs),
// centred on the origin: the seven bars of a calculator digit, drawn thick and
// touching, with the outer corners cut off.
float numeral(vec2 q, int digit) {
	vec2 h = digit_half;
	float t = digit_stroke * 0.5;
	if (digit == 1) {
		float one = box(q, vec2(0.0), vec2(t, h.y));
		one = min(one, box(q, vec2(-t * 1.4, h.y - t), vec2(t * 1.4, t)));
		return min(one, box(q, vec2(0.0, -h.y + t), vec2(h.x * 0.72, t)));
	}
	float top = box(q, vec2(0.0, h.y - t), vec2(h.x, t));
	float middle = box(q, vec2(0.0), vec2(h.x, t));
	float bottom = box(q, vec2(0.0, -h.y + t), vec2(h.x, t));
	float upper_left = box(q, vec2(-h.x + t, h.y * 0.5), vec2(t, h.y * 0.5));
	float upper_right = box(q, vec2(h.x - t, h.y * 0.5), vec2(t, h.y * 0.5));
	float lower_left = box(q, vec2(-h.x + t, -h.y * 0.5), vec2(t, h.y * 0.5));
	float lower_right = box(q, vec2(h.x - t, -h.y * 0.5), vec2(t, h.y * 0.5));
	if (digit == 4) {
		return min(min(upper_left, middle), min(upper_right, lower_right));
	}
	float d;
	if (digit == 0) {
		d = min(min(min(top, bottom), min(upper_left, upper_right)), min(lower_left, lower_right));
	} else if (digit == 2) {
		d = min(min(min(top, middle), bottom), min(upper_right, lower_left));
	} else if (digit == 3) {
		d = min(min(min(top, middle), bottom), min(upper_right, lower_right));
	} else {
		d = min(min(min(top, middle), bottom), min(upper_left, lower_right));
	}
	// The cut corners.
	float corner = (abs(q.x) + abs(q.y) - (h.x + h.y - digit_stroke * 0.55)) * 0.7071;
	return max(d, corner);
}

// How much of the numeral `digit` of the drawn lettering covers `q`, which is
// measured from the numeral's middle.
float drawn_numeral(vec2 q, int digit) {
	vec2 uv = q / (digit_half * 2.0) + 0.5;
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	float ink = texture(paint_atlas, vec2((float(digit) + uv.x) / 6.0, (1.0 - uv.y) * atlas_rows.x)).r;
	return smoothstep(0.25, 0.75, ink) * inside.x * inside.y;
}

// The name in row `row` of the drawn lettering at `uv` of its row (v down):
// its paint and its outline.
vec2 drawn_name(vec2 uv, float row) {
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return texture(paint_atlas, vec2(uv.x, atlas_rows.x + (row + uv.y) * atlas_rows.y)).rg * inside.x * inside.y;
}

// A number from 0 to 1 for the cell `cell`, the same every time.
float chance(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

// The picture `tex` in the unit square of `uv`, nothing outside it.
vec4 decal(sampler2D tex, vec2 uv) {
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return texture(tex, uv) * inside.x * inside.y;
}

void fragment() {
	vec2 p = world_pos.xz;
	float x = p.x;
	float az = abs(p.y);
	float half_w = field_width * 0.5;
	float edge_z = half_w + margin;
	float mid_x = field_length * 0.5;

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

	float in_z = step(az, edge_z);
	float in_field = step(-end_zone_depth - margin, x) * step(x, field_length + end_zone_depth + margin) * in_z;
	float in_play = step(0.0, x) * step(x, field_length) * in_z;

	// Mowing stripes: alternate 5-yard bands, including the end zones.
	float cycle = fract(x / 10.0);
	float aa_c = max(fwidth(x) * 0.1, 0.0005);
	float stripe = smoothstep(0.0, aa_c, cycle) - smoothstep(0.5, 0.5 + aa_c, cycle);
	// Grass bent away from the viewer reads lighter and a little yellower.
	vec3 mown = grass * mix(vec3(0.6, 0.64, 0.66), vec3(1.3, 1.24, 1.0), stripe);
	// The apron is longer, darker, unmown grass.
	vec3 apron = grass * vec3(0.5, 0.44, 0.34) * (0.7 + 0.5 * n_mid);
	vec3 color = mix(apron, mown, in_field);

	// Round the bowl: a paved walk, then a car park with cars in most bays.
	float rough = 0.92;
	if (bowl_reach > 0.0) {
		vec2 past = abs(vec2(x - mid_x, p.y)) - vec2(mid_x + end_zone_depth, half_w);
		float outside = length(max(past, vec2(0.0))) + min(max(past.x, past.y), 0.0) - bowl_reach;
		float aa_p = max(max(fwidth(x), fwidth(p.y)), 0.004);
		// Slabs two yards square.
		vec2 slab = (fract(p / 2.0 + 0.5) - 0.5) * 2.0;
		float joint = 1.0 - smoothstep(0.03, 0.03 + aa_p, min(abs(slab.x), abs(slab.y)));
		vec3 paving = paving_color * (0.82 + 0.3 * n_mid) * (0.94 + 0.12 * chance(floor(p / 2.0 + 0.5))) * (1.0 - 0.35 * joint);
		// Rows of bays three yards wide, nose to nose, a lane between the rows.
		float lane = 19.0;
		float row = (fract(p.y / lane + 0.5) - 0.5) * lane;
		float bay = (fract(x / 3.0) - 0.5) * 3.0;
		float in_bays = step(abs(row), 6.0);
		float lines = max(band(row, 0.06, aa_p), band(abs(bay) - 1.5, 0.06, aa_p)) * in_bays;
		vec3 parking = asphalt_color * (0.8 + 0.5 * n_fine) * (0.85 + 0.3 * n_patch);
		parking = mix(parking, vec3(0.8, 0.8, 0.76), lines * 0.85);
		vec2 bay_id = vec2(floor(x / 3.0), floor(p.y / lane + 0.5) * 2.0 + step(0.0, row));
		float car_d = box(vec2(bay, abs(row)), vec2(0.0, 3.2), vec2(0.72, 1.9)) - 0.28;
		float car = (1.0 - smoothstep(-aa_p, aa_p, car_d)) * step(chance(bay_id), 0.82) * in_bays;
		float pick = chance(bay_id + 7.3);
		vec3 paint_job = pick < 0.25 ? vec3(0.75, 0.76, 0.78) : pick < 0.45 ? vec3(0.08, 0.08, 0.1) : pick < 0.6 ? vec3(0.6, 0.08, 0.07) : pick < 0.75 ? vec3(0.1, 0.2, 0.5) : pick < 0.88 ? vec3(0.9, 0.9, 0.88) : vec3(0.75, 0.6, 0.12);
		// The roof and the glass: darker toward the windscreens.
		float glass = 1.0 - smoothstep(0.0, 0.15, abs(abs(abs(row) - 3.2) - 0.75) - 0.22);
		paint_job = mix(paint_job, vec3(0.05, 0.07, 0.1), glass * step(abs(bay), 0.78) * 0.85);
		parking = mix(parking, paint_job, car);
		float on_plaza = smoothstep(-aa_p, aa_p, outside) * (1.0 - smoothstep(plaza_width - aa_p, plaza_width + aa_p, outside));
		float on_parking = smoothstep(plaza_width - aa_p, plaza_width + aa_p, outside) * (1.0 - smoothstep(plaza_width + parking_width - 1.0, plaza_width + parking_width + 1.0, outside));
		color = mix(color, paving, on_plaza);
		color = mix(color, parking, on_parking);
		rough = mix(rough, 0.45, car * on_parking);
	}

	// Wear between the hash marks, where most plays start.
	float wear = (1.0 - smoothstep(2.0, 9.0, az)) * smoothstep(0.42, 0.72, n_mid * 0.6 + n_fine * 0.4) * in_play;
	color = mix(color, dirt_color * (0.7 + 0.5 * n_fine), wear * 0.45);

	// Paint soaks into the grass unevenly.
	float soak = 0.55 + 0.45 * smoothstep(0.2, 0.75, n_blade * 0.6 + n_fine * 0.4);

	float in_left = step(-end_zone_depth - margin, x) * step(x, 0.0) * in_z;
	float in_right = step(field_length, x) * step(x, field_length + end_zone_depth + margin) * in_z;
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
	// Hash marks every yard: two inner rows and one down each side.
	float tick = band(x - round(x), 0.045, aa_x) * in_play;
	float hash_z = hash_offset;
	float rows = max(band(az - hash_z, 0.3, aa_z), band(az - (half_w - 0.75), 0.3, aa_z));
	paint = max(paint, tick * rows);

	// Yard numbers on every ten, one digit each side of the line, in a row down
	// each side with their feet toward it: they read from the nearer stand.
	float ten = round(x / 10.0) * 10.0;
	float numbered = step(9.5, ten) * step(ten, field_length - 9.5);
	float side = p.y >= 0.0 ? 1.0 : -1.0;
	// Across and up the number, as its reader sees it.
	vec2 q = vec2(side * (x - ten), half_w - number_inset - az);
	float aa_n = max(aa_x, aa_z);
	int tens = int(round(min(ten, field_length - ten) / 10.0));
	float digit_x = digit_gap + digit_half.x;
	vec2 q_digit = q.x < 0.0 ? q + vec2(digit_x, 0.0) : q - vec2(digit_x, 0.0);
	int digit = q.x < 0.0 ? tens : 0;
	float glyph = numeral(q_digit, digit);
	// A small arrow beside the number, pointing at the nearer goal line.
	float toward = ten < mid_x ? -1.0 : 1.0;
	vec2 a = vec2((x - ten) * toward - (digit_gap + digit_half.x * 2.0 + 0.55), q.y - digit_half.y * 0.45);
	float arrow = max(-0.3 - a.x, (abs(a.y) - (0.3 - a.x) * 0.55) * 0.876);
	arrow += step(abs(ten - mid_x), 1.0) * 10.0;
	float number = 1.0 - smoothstep(-aa_n, aa_n, min(glyph, arrow));
	if (painted) {
		number = max(drawn_numeral(q_digit, digit), 1.0 - smoothstep(-aa_n, aa_n, arrow));
	}
	paint = max(paint, number * numbered);

	color = mix(color, paint_color * (0.78 + 0.22 * n_blade), paint * soak);

	// The teams' names across their end zones, read from midfield: white with
	// a dark edge in the team's colour.
	if (painted) {
		vec2 left_uv = vec2(0.5 - p.y / name_size.x, 0.5 + (x + end_zone_depth * 0.5) / name_size.y);
		vec2 right_uv = vec2(0.5 + p.y / name_size.x, 0.5 - (x - field_length - end_zone_depth * 0.5) / name_size.y);
		vec2 name = drawn_name(left_uv, 0.0) * in_left + drawn_name(right_uv, 1.0) * in_right;
		color = mix(color, zone * 0.22 * (0.7 + 0.5 * n_blade), smoothstep(0.2, 0.7, name.g) * (0.6 + 0.4 * soak));
		float letters = smoothstep(0.25, 0.75, name.r);
		color = mix(color, paint_color * (0.78 + 0.22 * n_blade), letters * soak);
		paint = max(paint, letters);
	}

	// The mascots go on last, over the lines they cover.
	float mascot_v = p.y / mascot_size + 0.5;
	vec4 mascot = decal(left_mascot, vec2((x - (mid_x - mascot_gap - mascot_size)) / mascot_size, mascot_v));
	mascot += decal(right_mascot, vec2(1.0 - (x - (mid_x + mascot_gap)) / mascot_size, mascot_v));
	color = mix(color, mascot.rgb * (0.72 + 0.28 * n_blade) * mix(0.9, 1.05, stripe), mascot.a * (0.5 + 0.5 * soak) * 0.92);
	paint = max(paint, mascot.a);

	ALBEDO = color;
	ROUGHNESS = rough - 0.12 * paint;
	// Nearly matte: sky reflections at a shallow angle wash the grass out.
	SPECULAR = 0.03;
	NORMAL_MAP = texture(blade_normal, blade_uv).rgb;
	NORMAL_MAP_DEPTH = 0.9;
}
