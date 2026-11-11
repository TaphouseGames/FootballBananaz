shader_type spatial;
// Football skin: the model's colour texture plus a pebbled leather grain. The
// grain is projected along the three object axes (the model's own UVs are an
// atlas with seams) and left off the white paint and laces.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grain_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float grain_scale = 6.0;
uniform float grain_strength = 1.1;
uniform float brightness = 1.25;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 n = normalize(obj_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec2 gx = texture(grain_normal, obj_pos.yz * grain_scale).xy * 2.0 - 1.0;
	vec2 gy = texture(grain_normal, obj_pos.xz * grain_scale).xy * 2.0 - 1.0;
	vec2 gz = texture(grain_normal, obj_pos.xy * grain_scale).xy * 2.0 - 1.0;
	vec3 offset = w.x * vec3(0.0, gx) + w.y * vec3(gy.x, 0.0, gy.y) + w.z * vec3(gz, 0.0);

	float leather = 1.0 - smoothstep(0.35, 0.6, min(base.r, min(base.g, base.b)));
	vec3 bumped = normalize(n + offset * grain_strength * leather);
	NORMAL = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * bumped, 0.0)).xyz);
	// Darken the creases between pebbles a little.
	float crease = clamp(length(offset) * 1.6, 0.0, 1.0) * leather;
	ALBEDO = base * brightness * (1.0 - 0.3 * crease);
	ROUGHNESS = mix(0.45, 0.62, leather);
	SPECULAR = 0.4;
}
