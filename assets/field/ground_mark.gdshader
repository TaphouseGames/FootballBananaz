shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;
// Marks pressed into the turf, drawn as flat quads by FieldFx.
// INSTANCE_CUSTOM.x = random seed, .y = 0 for a cleat print (toe toward local
// +X), 1 for a torn-up scuff. COLOR is the tint and opacity.

varying vec4 custom;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 c = UV - 0.5;
	vec2 seed = vec2(custom.x * 91.0, custom.x * 37.0);
	float alpha;
	if (custom.y < 0.5) {
		float sole = 1.0 - smoothstep(0.7, 1.0, length(vec2((c.x - 0.12) * 3.3, c.y * 2.6)));
		float heel = 1.0 - smoothstep(0.7, 1.0, length(vec2((c.x + 0.3) * 5.5, c.y * 3.2)));
		alpha = max(sole, heel) * (0.65 + 0.35 * vnoise(UV * 9.0 + seed));
	} else {
		float r = length(c) * 2.0;
		float n = vnoise(UV * 5.0 + seed) * 0.6 + vnoise(UV * 13.0 + seed) * 0.4;
		alpha = smoothstep(0.25, 0.6, n * (1.0 - r * r) * 1.7);
	}
	ALBEDO = COLOR.rgb * (0.8 + 0.4 * vnoise(UV * 17.0 + seed));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = alpha * COLOR.a;
}
