shader_type spatial;
// A modelled piece of the stadium that shows a team's colour: the pictures of
// its own material, with whatever is white in them (the banner on a bay of
// the facade) dyed with `tint`, which each instance sets for itself.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
// Roughness in green, metal in blue, as glTF has them.
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform bool has_orm = false;
// How light and how grey a place has to be to count as white.
uniform float white_from = 0.62;
uniform float grey_within = 0.12;
instance uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec3 color = texture(albedo_tex, UV).rgb;
	float low = min(color.r, min(color.g, color.b));
	float high = max(color.r, max(color.g, color.b));
	float white = smoothstep(white_from, white_from + 0.2, low) * (1.0 - smoothstep(grey_within, grey_within * 2.0, high - low));
	ALBEDO = mix(color, tint * (0.35 + 0.75 * low), white);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	ROUGHNESS = has_orm ? orm.g : 0.85;
	METALLIC = has_orm ? orm.b : 0.0;
}
