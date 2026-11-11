shader_type spatial;
// Repaints the kit in the team colour, keeping the cloth shading. Which texels
// count as kit depends on the model:
//  - green jersey (default): green-dominant texels; skin, leather and the
//    printed numbers are left alone.
//  - grey kit: mid-grey cloth, picked out as "not warm" so skin and brown hair
//    are left alone, with black cloth and the whites of the eyes excluded by
//    brightness.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 team_color : source_color = vec3(1.0);
uniform bool grey_kit = false;
uniform float jersey_gain = 4.0;
uniform float brightness = 1.5;

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
	ALBEDO = mix(base * brightness, team_color * shade, mask);
	ROUGHNESS = 0.85;
}
