shader_type sky;

// A bright cartoon sky: a blue that pales towards the horizon, a round sun
// where the scene's light comes from, and a few puffy clouds that drift by.
// The clouds are left out of the picture the lighting is taken from, so the
// light on the field does not change as they move.

uniform vec3 top_color : source_color = vec3(0.07, 0.42, 0.96);
uniform vec3 horizon_color : source_color = vec3(0.56, 0.86, 1.0);
uniform vec3 ground_color : source_color = vec3(0.3, 0.52, 0.34);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade_color : source_color = vec3(0.74, 0.86, 1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.55);
/// Share of the places for a cloud that hold one (0 to 1).
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.65;
/// Places for a cloud once round the horizon: more makes smaller clouds.
uniform float cloud_columns = 20.0;
/// How fast the clouds drift round, in places a second.
uniform float cloud_speed = 0.02;
/// Width of the sun, as a share of the sky.
uniform float sun_size : hint_range(0.0, 0.3) = 0.06;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float smooth_min(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Distance to the edge of the cloud of one cell (negative inside): a row of
// four round puffs on a flat base, the middle ones bigger and higher. Only the
// two rows of cells nearest the horizon hold clouds.
float cloud_distance(vec2 p, vec2 cell) {
	if (cell.y < 0.0 || cell.y > 1.0) {
		return 1.0;
	}
	vec2 id = vec2(mod(cell.x, cloud_columns), cell.y);
	float seed = hash(id);
	if (seed > cloud_cover) {
		return 1.0;
	}
	float pick = seed / max(cloud_cover, 0.001);
	// The lower row sits just over the top of the stands, which is all of the
	// sky the cameras on the field get to see.
	float height = cell.y < 0.5 ? 0.2 + 0.4 * hash(id + 3.7) : 0.3 + 0.4 * hash(id + 3.7);
	vec2 centre = cell + vec2(0.3 + 0.4 * hash(id + 7.1), height);
	float size = 0.8 + 0.6 * pick;
	vec2 q = (p - centre) / size;
	float d = 1.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float bump = hash(id + fi * 1.9 + 11.0);
		bool end = i == 0 || i == 3;
		float radius = end ? 0.07 + 0.02 * bump : 0.1 + 0.035 * bump;
		vec2 at = vec2((fi - 1.5) * 0.115, end ? 0.02 : 0.05 + 0.03 * bump);
		d = smooth_min(d, length(q - at) - radius, 0.03);
	}
	d = max(d, -q.y - 0.02);
	return d * size;
}

float clouds_at(vec2 p) {
	vec2 cell = floor(p);
	float d = 1.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			d = min(d, cloud_distance(p, cell + vec2(float(x), float(y))));
		}
	}
	return d;
}

void sky() {
	float up = EYEDIR.y;
	vec3 color = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.55));
	color = mix(color, ground_color, smoothstep(0.0, -0.06, up));

	if (!AT_CUBEMAP_PASS && up > 0.0) {
		if (LIGHT0_ENABLED) {
			float to_sun = distance(EYEDIR, LIGHT0_DIRECTION);
			color = mix(color, sun_color, 0.35 * smoothstep(sun_size * 3.0, sun_size, to_sun));
			color = mix(color, sun_color, smoothstep(sun_size, sun_size * 0.92, to_sun));
		}

		// The clouds stand round the horizon as if painted on a wall, so they
		// keep their shape low in the sky, which is where they are seen from
		// inside the stadium.
		vec2 p = vec2(atan(EYEDIR.x, EYEDIR.z) / TAU + 0.5, asin(clamp(up, 0.0, 1.0)) / TAU) * cloud_columns;
		p.x += cloud_speed * TIME;
		float d = clouds_at(p);
		// A darker underside.
		float lit = clouds_at(p - vec2(0.025, 0.05));
		vec3 cloud = mix(cloud_shade_color, cloud_color, smoothstep(0.012, -0.012, lit));
		color = mix(color, cloud, smoothstep(0.006, -0.006, d));
	}
	COLOR = color;
}
