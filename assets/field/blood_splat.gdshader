shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A wet blood splat on the turf, drawn as a flat quad by FieldFx. The quad is
// stretched along the direction the drop was travelling.
// INSTANCE_CUSTOM.x = random seed. COLOR is the tint and opacity.

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
	vec2 c = (UV - 0.5) * 2.0;
	float r = length(c);
	float ang = atan(c.y, c.x);
	float seed = custom.x * 6.2831;
	// A lobed blob with a few satellite specks around it.
	float edge = 0.5 + 0.16 * sin(ang * 3.0 + seed) + 0.1 * sin(ang * 7.0 + seed * 2.3) + 0.07 * sin(ang * 13.0 + seed * 4.1);
	float blob = 1.0 - smoothstep(edge - 0.06, edge + 0.03, r);
	float specks = smoothstep(0.76, 0.84, vnoise(UV * 11.0 + vec2(seed * 3.0, seed))) * (1.0 - smoothstep(0.75, 1.0, r));
	float thick = 1.0 - smoothstep(0.0, edge, r);
	ALBEDO = COLOR.rgb * mix(1.0, 0.5, thick);
	// Low specular: at the game camera's shallow angle a mirror-like splat would
	// reflect the sky and turn pink.
	ROUGHNESS = 0.3;
	SPECULAR = 0.12;
	ALPHA = max(blob, specks) * COLOR.a;
}
