shader_type spatial;
// The crowd: every fan is a head, a torso and legs out of the kit that
// tools/prep_crowd.py makes (or, far off, one plain mesh), each a MultiMesh
// instance in the same seat, animated here so that thousands of them cost a
// few hundred draw calls and nothing on the CPU.
//
// Per vertex (see prep_crowd.py):
//   UV    the kit's atlas
//   UV2.x 0.5 on the body; towards 1 the more it belongs to the left arm,
//         towards 0 the more it belongs to the right one. These swing up.
//   UV2.y how much it belongs to an arm that is held up already (the fans
//         with a sign), which only rocks from side to side; plus 2 on a head
//         and 4 on legs.
// Per instance, the same for every part of a fan (see Stadium._fan and
// crowd_motion.gdshaderinc):
//   COLOR.rgb shirt colour (linear)
//   COLOR.a   side (0 home, 0.5 neither, 1 away) + 2 x the trousers' colour
//   INSTANCE_CUSTOM: x phase, y skin tone (0..1) + the hair's colour (a whole
//             number), z place round the bowl, w random
render_mode specular_disabled, shadows_disabled;

#include "crowd_motion.gdshaderinc"

// Every fan's texture, with cloth, hair and skin reduced to their shading,
// and what may be painted there: R the part's own colour (shirt on a torso,
// hair on a head, trousers on legs), G the fan's skin tone.
uniform sampler2D atlas_tex : source_color, filter_linear_mipmap;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
// Darker and greyer than the field, so the players and the ball stand out.
uniform float dim = 0.62;
uniform float saturation = 0.7;
// Share of a fan's colour that shows whatever the light does.
uniform float self_lit = 0.4;
// How far the sun's light reaches round to the side that faces away from it
// (0 = a hard edge), and a glow along the outline: both make a body look round.
uniform float wrap = 0.5;
uniform float rim = 0.18;
// The shading is kept at 0.8 of full, to leave room for highlights; this
// brings a painted colour back to what was asked for.
uniform float detail_gain = 1.66;
// What is not painted (shoes, eyes, a print on a shirt) times this.
uniform float brightness = 1.0;
uniform vec3 light_skin : source_color = vec3(0.94, 0.76, 0.64);
uniform vec3 dark_skin : source_color = vec3(0.33, 0.2, 0.14);
uniform vec3 hair_colors[8] : source_color;
uniform vec3 pants_colors[8] : source_color;

varying vec3 tint;
varying vec3 skin;
varying float shade;


void vertex() {
	Motion m = crowd_motion(INSTANCE_CUSTOM, mod(COLOR.a, 2.0));
	float part = floor((UV2.y + 0.5) * 0.5);
	float held = clamp(UV2.y - 2.0 * part, 0.0, 1.0);
	float arm = UV2.x * 2.0 - 1.0;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (abs(arm) > 0.02) {
		// A vertex half on the arm turns half as far, which bends the shoulder.
		float angle = m.raise * abs(arm);
		v = crowd_swing(v, angle, shoulder);
		v.x += sign(arm) * abs(arm) * 0.08 * sin(angle);
		n = crowd_swing(n, angle, vec3(0.0));
	}
	if (held > 0.02) {
		v = crowd_rock(v, m.rock * held, shoulder.y);
		n = crowd_rock(n, m.rock * held, 0.0);
	}
	tint = COLOR.rgb;
	if (part > 1.5) {
		tint = pants_colors[int(clamp(floor(COLOR.a * 0.5), 0.0, 7.0))];
	} else if (part > 0.5) {
		// No two heads of hair quite the same.
		tint = hair_colors[int(clamp(floor(INSTANCE_CUSTOM.y), 0.0, 7.0))] * (0.8 + 0.4 * INSTANCE_CUSTOM.w);
	}
	skin = mix(light_skin, dark_skin, fract(INSTANCE_CUSTOM.y));
	// The lower half sits in the shade of the row in front.
	shade = mix(0.7, 1.0, smoothstep(0.0, 0.7, VERTEX.y));
	VERTEX = crowd_settle(v, m, VERTEX.y);
	NORMAL = n;
}


void fragment() {
	vec3 base = texture(atlas_tex, UV).rgb;
	vec2 paint = texture(mask_tex, UV).rg;
	vec3 shading = min(base * detail_gain, vec3(1.25));
	vec3 colour = base * brightness;
	colour = mix(colour, tint * shading, paint.r);
	colour = mix(colour, skin * shading, paint.g);
	float grey = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	colour = mix(vec3(grey), colour, saturation) * dim * shade;

	// Partly its own light, so the stand that faces away from the sun is not
	// a black wall; brighter where it faces the sky and along the outline.
	float sky = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y * 0.5 + 0.5;
	float outline = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = colour * (1.0 - self_lit);
	EMISSION = colour * (self_lit * mix(0.72, 1.1, sky) + rim * outline * (0.4 + 0.6 * sky));
	ROUGHNESS = 1.0;
}


void light() {
	// Lambert, but with the light carried on past the edge of the shadow.
	float lit = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
