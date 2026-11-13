shader_type spatial;
render_mode cull_disabled;
// Hair made by LookParts: a cap over the scalp and the locks on it.
//   UV.x   a number of its own for each lock, which sets it off from its
//          neighbours; UV.y runs from its root to its tip
//   UV2.x  how far inside the hairline a point of the cap is; the cap thins
//          out to nothing there, so a hairline is soft and not an edge
//   UV2.y  where across its lock a point is (-1..1). From 2 up it is the cap:
//          2 the cap itself, and up to 3 the shells stacked on it
//
// Very short hair is shells: the cap drawn several times, each a little
// further out, each with more of it cut away, so what is left stands up from
// the skin as hairs do and the outline is fuzzy. Longer hair is locks, with
// the strands drawn along them here.
//
// The light is hair's own: it wraps round to the shadow side, the highlight
// runs across the strands in two bands (Kajiya-Kay), and hair against the
// light glows at its edge.

uniform vec3 hair_color : source_color = vec3(0.25, 0.14, 0.07);
uniform vec3 skin_color : source_color = vec3(0.82, 0.62, 0.46);
// 1 for a buzz cut or stubble: the skin shows through the hair.
instance uniform float stubble = 0.0;
// 1 for hair in tight curls: drawn as curls, not as strands.
instance uniform float curls = 0.0;
// How far out the outermost shell is, in the mesh's own units.
instance uniform float shell_depth = 0.0;
// How strongly the strands show, and how much darker a lock is at its edges.
uniform float strand_depth = 0.5;
uniform float edge_shade = 0.34;
// How far light wraps round to the shadow side, how bright the two bands of
// the highlight are, and how much hair glows against the light.
uniform float wrap = 0.45;
uniform float shine = 0.018;
uniform float shine_tinted = 0.05;
uniform float back_glow = 0.25;

varying vec3 place;
varying float sheen;
varying vec3 strand_way;

void vertex() {
	// Where on the head, the same for every shell over one spot.
	place = VERTEX;
	VERTEX += NORMAL * clamp(UV2.y - 2.0, 0.0, 1.0) * shell_depth;
}

float hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

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

float noise2(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(cell), hash2(cell + vec2(1.0, 0.0)), f.x),
		mix(hash2(cell + vec2(0.0, 1.0)), hash2(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float cover = UV2.x;
	bool cap = UV2.y > 1.5;
	float shell = cap ? clamp(UV2.y - 2.0, 0.0, 1.0) : 0.0;
	if (cover < 0.0) {
		discard;
	}
	// Round the head and up it, for hair that has no lock to run along.
	vec2 round_head = vec2(atan(place.x, -place.y), place.z);
	float grit = hash2(floor(round_head * vec2(520.0, 1700.0)));
	// Thinner and thinner towards the hairline.
	if (cap && grit > smoothstep(0.0, mix(0.9, 2.2, stubble), cover) * 1.15) {
		discard;
	}
	if (shell > 0.0) {
		// What is left of this shell: single hairs of all lengths, or for
		// curls whole coils.
		float hairs = hash3(floor(place * 950.0)) * 0.65 + noise3(place * 330.0) * 0.35;
		float coils = noise3(place * 210.0) * 0.55 + noise3(place * 480.0) * 0.45;
		if (mix(hairs, coils, curls) < 0.12 + shell * 0.8) {
			discard;
		}
	}
	float streaks;
	float edge = 0.0;
	float along = 0.5;
	if (cap) {
		streaks = noise2(round_head * vec2(70.0, 22.0)) * 0.6 + noise2(round_head * vec2(190.0, 40.0)) * 0.4;
	} else {
		float across = UV2.y;
		vec2 lock_at = vec2(across * 4.0 + UV.x * 91.0, UV.y * 1.6 + UV.x * 13.0);
		streaks = noise2(lock_at) * 0.55 + noise2(lock_at * vec2(2.7, 1.3) + 5.0) * 0.45;
		edge = across * across;
		along = UV.y;
	}
	// No two locks quite the same brown.
	vec3 own = vec3(1.0 + 0.07 * (UV.x - 0.5), 1.0, 1.0 - 0.07 * (UV.x - 0.5)) * (0.93 + 0.14 * UV.x);
	vec3 color = hair_color * own * mix(0.82, 1.05, smoothstep(0.0, 0.8, along));
	color *= 1.0 - strand_depth * 0.5 + strand_depth * streaks;
	color *= 1.0 - edge_shade * edge;
	sheen = 1.0;
	if (cap) {
		// The ends of the hair, as fine as the strands along a lock.
		color *= 0.86 + 0.28 * noise3(place * 1100.0);
	}
	if (curls > 0.0) {
		// Coils: bright where one catches the light, dark between them.
		float coil = noise3(place * 210.0) * 0.55 + noise3(place * 480.0) * 0.45;
		float tight = smoothstep(0.3, 0.7, coil);
		color = hair_color * (0.5 + 0.8 * tight) * (0.9 + 0.2 * noise3(place * 1300.0));
		sheen = 0.15;
	}
	if (stubble > 0.0 && cap) {
		// Short ends standing on the skin, which shows between them.
		float ends = hash2(floor(round_head * vec2(300.0, 1000.0)));
		float thick = smoothstep(0.0, 1.6, cover) * 0.82;
		vec3 on_skin = mix(skin_color * 0.8, hair_color * (0.8 + 0.4 * ends), thick * (0.75 + 0.25 * streaks));
		color = mix(on_skin, hair_color * (0.8 + 0.4 * ends), smoothstep(0.0, 0.4, shell));
		sheen = 0.1;
	}
	if (cap && shell_depth > 0.0) {
		// Dark down among the hairs, light at their tips.
		color *= mix(0.6, 1.12, shell);
	}
	ALBEDO = color;
	ROUGHNESS = 0.6;
	SPECULAR = 0.2;
	strand_way = normalize(TANGENT);
	if (!FRONT_FACING) {
		ALBEDO *= 0.6;
	}
}

void light() {
	float facing = dot(NORMAL, LIGHT);
	float lit = clamp((facing + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Against the light, thin hair at the edge of the head lets it through.
	float behind = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	DIFFUSE_LIGHT += (lit / PI + behind * back_glow) * ATTENUATION * LIGHT_COLOR;

	// Two bands across the strands: a narrow white one, and a broader one a
	// little further along, in the colour of the hair.
	vec3 half_way = normalize(LIGHT + VIEW);
	float off = dot(strand_way, half_way);
	float narrow = pow(sqrt(max(1.0 - off * off, 0.0)), 260.0);
	float shifted = dot(normalize(strand_way + NORMAL * 0.25), half_way);
	float broad = pow(sqrt(max(1.0 - shifted * shifted, 0.0)), 60.0);
	float open = smoothstep(0.0, 0.5, facing) * sheen;
	SPECULAR_LIGHT += (narrow * shine + broad * shine_tinted * (ALBEDO * 2.0 + 0.05)) * open * ATTENUATION * LIGHT_COLOR;
}
