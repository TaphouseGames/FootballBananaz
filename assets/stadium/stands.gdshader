shader_type spatial;
// Everything of the stadium that scripts/stadium.gd builds in code: the wall,
// the rows and steps, the seats, the rails and the ad boards. The colour of a
// vertex is the surface's own colour and its alpha says what it is made of
// (Stadium.Finish: 1.0 concrete, 0.8 padding, 0.6 metal, 0.4 plastic, 0.2 a lit
// board). UV is yards along the stand and yards up (or back), and UV2.x is how
// deep in a corner a vertex is (1 at the foot of a wall, 0 in the open).

uniform sampler2D mottle : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap_anisotropic;
// Yards between the seams of the wall's padding, and between the joints of
// the concrete walls.
uniform float pad_panel = 2.0;
uniform float joint = 3.5;
// How dark the corners are, and how much an ad board glows.
uniform float corner_shade = 0.4;
uniform float board_glow = 0.3;

varying vec3 world_pos;
varying float lying;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lying = abs(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// Yards to the nearest of the lines that lie every `every` yards along `x`.
float to_line(float x, float every) {
	return (fract(x / every + 0.5) - 0.5) * every;
}

void fragment() {
	int finish = int(floor((1.0 - COLOR.a) * 5.0 + 0.5));
	vec3 base = to_linear(COLOR.rgb);
	// Floors are laid out in the world, upright faces along their own stand,
	// so the pattern goes round the corners with them.
	float flat_face = step(0.7, lying);
	vec2 p = mix(UV, world_pos.xz, flat_face);
	float big = texture(mottle, p / 9.0).r;
	float fine = texture(grain, p * 0.8).r;
	float corner = UV2.x * UV2.x * UV2.x;
	float shade = 1.0 - corner_shade * corner;
	float aa = max(fwidth(UV.x), 0.002);

	vec3 color = base;
	float rough = 0.92;
	float spec = 0.2;
	float metal = 0.0;
	vec3 bump = vec3(0.5, 0.5, 1.0);
	vec3 glow = vec3(0.0);
	if (finish == 1) {
		// Padding in panels: a dark seam with the vinyl rolling into it.
		float d = to_line(UV.x, pad_panel);
		float roll = 1.0 - smoothstep(0.0, 0.09, abs(d));
		bump.x = 0.5 - sign(d) * roll * 0.32;
		color *= (0.9 + 0.14 * fine) * (1.0 - 0.55 * (1.0 - smoothstep(0.008, 0.008 + aa, abs(d))));
		rough = 0.48;
		spec = 0.5;
	} else if (finish == 2) {
		rough = 0.36;
		metal = 0.55;
		spec = 0.6;
	} else if (finish == 3) {
		color *= 0.95 + 0.08 * fine;
		rough = 0.4;
		spec = 0.5;
	} else if (finish == 4) {
		color *= 0.9 + 0.12 * big;
		glow = color * board_glow;
		rough = 0.22;
		spec = 0.6;
	} else {
		// Concrete: blotchy, grainy, grimy at the foot, jointed where it stands.
		color *= (0.8 + 0.34 * big) * (0.9 + 0.2 * fine);
		color = mix(color, color * vec3(0.72, 0.7, 0.66), corner * 0.6);
		float d = to_line(UV.x, joint);
		color *= 1.0 - 0.4 * (1.0 - smoothstep(0.012, 0.012 + aa, abs(d))) * (1.0 - flat_face);
		rough = 0.86 + 0.1 * fine;
	}
	ALBEDO = color * shade;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	EMISSION = glow;
	NORMAL_MAP = bump;
}
