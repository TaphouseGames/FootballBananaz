// How a fan moves: shared by the fans (crowd.gdshader) and the signs they
// hold up (crowd_sign.gdshader), so that a sign stays in its holder's hands.
// The Stadium script sets these on both materials every frame.
//
// Per instance (see Stadium):
//   COLOR.a side: 0 home, 0.5 neither, 1 away
//   INSTANCE_CUSTOM: x phase 0..1, y skin tone 0..1, z place round the bowl 0..1, w a second random number

// How worked up the crowd is, 0..1 (AudioDirector.excitement).
uniform float excitement = 0.0;
// Each side on its feet with its arms up (0..1), or sunk in its seats.
uniform float cheer_home = 0.0;
uniform float cheer_away = 0.0;
uniform float slump_home = 0.0;
uniform float slump_away = 0.0;
// The stadium wave: how strong, where round the bowl its crest is, how wide.
uniform float wave_on = 0.0;
uniform float wave_pos = 0.0;
uniform float wave_width = 0.035;
// Where the arms turn: x of the left shoulder, its height above the seat and
// its z, in the mesh's units (written by tools/prep_fan.py).
uniform vec3 shoulder = vec3(0.2, 0.56, -0.08);

struct Motion {
	// Out of the seat, 0..1, and how sunk into it.
	float up;
	float slump;
	// Yards the whole fan rises, and the lean to the side per yard of height.
	float lift;
	float sway;
	// Angle the hanging arms swing forward and up by, and the angle arms that
	// are up already (and the sign in them) rock to the side by.
	float raise;
	float rock;
};


Motion crowd_motion(vec4 custom, float side) {
	float phase = custom.x;
	float seed = custom.w;
	float cheer = max(cheer_home, cheer_away) * 0.6;
	float slump = 0.0;
	if (side < 0.25) {
		cheer = cheer_home;
		slump = slump_home;
	} else if (side > 0.75) {
		cheer = cheer_away;
		slump = slump_away;
	}
	Motion m;
	// Not everyone gets up at once, and the keenest sit down last.
	m.up = clamp(cheer * 1.5 - phase * 0.5, 0.0, 1.0);
	m.slump = slump;
	float off = fract(custom.z - wave_pos + 0.5) - 0.5;
	float wave = wave_on * exp(-off * off / (wave_width * wave_width));

	float rate = 1.6 + phase * 1.4;
	float bob = sin(TIME * rate + phase * 6.283);
	float hop = abs(sin(TIME * (5.0 + 3.0 * seed) + phase * 40.0));
	m.lift = m.up * (0.2 + 0.3 * hop) + wave * 0.4 + bob * 0.015 * (1.0 + 3.0 * excitement) - slump * 0.07;
	m.sway = sin(TIME * rate * 0.5 + seed * 6.283) * 0.03;
	m.raise = max(m.up * (2.5 + 0.4 * sin(TIME * 9.0 + phase * 30.0)), wave * 2.9);
	// A lively crowd: now and then somebody pumps their fists.
	m.raise = max(m.raise, excitement * smoothstep(0.75, 1.0, sin(TIME * rate * 0.6 + seed * 50.0)) * 2.3);
	m.rock = (0.06 + 0.16 * max(m.up, wave)) * sin(TIME * (2.0 + 2.0 * seed) + phase * 20.0);
	return m;
}


// Turns `v` (a place or a direction, with `pivot` zero for a direction) about
// the line across the shoulders: forward and up.
vec3 crowd_swing(vec3 v, float angle, vec3 pivot) {
	float c = cos(angle);
	float s = sin(angle);
	float y = v.y - pivot.y;
	float z = v.z - pivot.z;
	return vec3(v.x, pivot.y + y * c + z * s, pivot.z - y * s + z * c);
}


// Turns `v` about the line from back to front through the middle of the
// shoulders: rocking from side to side.
vec3 crowd_rock(vec3 v, float angle, float pivot_y) {
	float c = cos(angle);
	float s = sin(angle);
	float y = v.y - pivot_y;
	return vec3(v.x * c - y * s, pivot_y + v.x * s + y * c, v.z);
}


// Swaying in the seat, leaning forward when it goes badly, up in a cheer.
// `height` is how high above the seat the vertex was before any of it.
vec3 crowd_settle(vec3 v, Motion m, float height) {
	v.x += m.sway * height;
	v.z += m.slump * 0.14 * height;
	v.y += m.lift;
	return v;
}
