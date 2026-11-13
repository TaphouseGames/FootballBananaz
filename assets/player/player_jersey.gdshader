shader_type spatial;
// Repaints the kit in the team colour, keeping the cloth shading. Which texels
// count as kit depends on the model:
//  - green jersey (default): green-dominant texels; skin, leather and the
//    printed numbers are left alone.
//  - grey kit: mid-grey cloth, picked out as "not warm" so skin and brown hair
//    are left alone, with black cloth and the whites of the eyes excluded by
//    brightness.
// The home team wears white with a band of its colour round the chest. The
// band is cut by height on the model as it stands at rest, which Player bakes
// into the red of the vertex colour (0 at the feet, 1 at the top of the head),
// so it stays on the cloth however the body bends.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 team_color : source_color = vec3(1.0);
uniform bool grey_kit = false;
uniform bool white_kit = false;
uniform vec3 white_color : source_color = vec3(0.94, 0.94, 0.92);
// Bottom and top of the band, as a share of the model's height.
uniform float stripe_low = 0.46;
uniform float stripe_high = 0.57;
uniform float jersey_gain = 4.0;
uniform float brightness = 1.5;
// The player's own look. What is left of the texture once the kit is taken out
// and is warm in colour is his body: the bright part skin, the dark part hair
// (head, beard and the hair on his arms and chest). Skin is multiplied by
// skin_tint, so white leaves it as painted. Hair is repainted in hair_color,
// keeping the strands, when recolor_hair is set.
uniform vec3 skin_tint : source_color = vec3(1.0);
uniform vec3 hair_color : source_color = vec3(0.17, 0.05, 0.02);
uniform bool recolor_hair = false;
// Brightness below which a body texel is all hair, and above which all skin.
uniform float hair_low = 0.13;
uniform float hair_high = 0.3;
// Brightness of the painted hair that comes out as exactly hair_color.
uniform float hair_ref_luma = 0.09;
// Hair is also redder than skin in shadow: red over blue at which a dark texel
// starts to count as hair, and at which it fully does.
uniform float hair_warm_low = 2.7;
uniform float hair_warm_high = 3.8;

varying float rest_height;

void vertex() {
	rest_height = COLOR.r;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	float luma = dot(base, vec3(0.3, 0.59, 0.11));
	float mask;
	if (grey_kit) {
		float warmth = base.r / max(base.b, 0.0005);
		mask = (1.0 - smoothstep(1.15, 1.45, warmth))
			* smoothstep(0.05, 0.1, luma) * (1.0 - smoothstep(0.5, 0.7, luma));
	} else {
		float other = max(max(base.r, base.b), 0.0005);
		mask = smoothstep(1.08, 1.35, base.g / other) * smoothstep(0.004, 0.02, base.g);
	}
	float shade = clamp(luma * jersey_gain, 0.0, 1.0);
	vec3 kit = team_color;
	if (white_kit) {
		float band = smoothstep(stripe_low - 0.004, stripe_low + 0.004, rest_height)
			* (1.0 - smoothstep(stripe_high - 0.004, stripe_high + 0.004, rest_height));
		kit = mix(white_color, team_color, band);
	}
	float body_warmth = base.r / max(base.b, 0.0005);
	float body = smoothstep(1.3, 1.6, body_warmth) * smoothstep(0.006, 0.018, luma);
	float hair = (1.0 - smoothstep(hair_low, hair_high, luma)) * smoothstep(hair_warm_low, hair_warm_high, body_warmth);
	vec3 hair_paint = base;
	if (recolor_hair) {
		hair_paint = hair_color * clamp(luma / hair_ref_luma, 0.0, 1.4);
	}
	base = mix(base, mix(base * skin_tint, hair_paint, hair), body);
	ALBEDO = mix(base * brightness, kit * shade, mask);
	ROUGHNESS = 0.85;
}
