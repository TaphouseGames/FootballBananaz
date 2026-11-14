class_name Stadium
extends Node3D
## The bowl round the field: a wall, tiered stands with aisles, a crowd in the
## teams' colours, and the dressing (ad boards, jumbotrons, light towers, hot
## dog stand, mascot). Built from Tuning by Field.setup(), so it follows the
## field's size, and it takes no part in the game: nothing here collides.
##
## The outline is a rectangle with rounded corners, made of eight runs (four
## straights, four quarter circles); every row is the same outline pushed
## further out and higher up. The fans are as big as the players. Each is put
## together from a head, a torso and legs out of a kit of parts
## (tools/prep_crowd.py), as MultiMesh instances that share a seat, and is
## animated by assets/stadium/crowd.gdshader; this script only feeds it a few
## numbers.

const CROWD_SHADER: Shader = preload("res://assets/stadium/crowd.gdshader")
const SIGN_SHADER: Shader = preload("res://assets/stadium/crowd_sign.gdshader")
## The parts the fans are put together from, and the picture and the mask
## their shader paints them with (all three made by tools/prep_crowd.py).
const KIT_SCENE: String = "res://assets/stadium/crowd_kit.glb"
const KIT_ATLAS: String = "res://assets/stadium/crowd_atlas.png"
const KIT_MASK: String = "res://assets/stadium/crowd_mask.png"
## Share of the fans who hold a sign over their heads.
const SIGN_SHARE: float = 0.03
## The levels of detail: up close and in the middle distance a fan is three
## parts, far off one plain mesh for the whole fan.
const TIER_NAMES: PackedStringArray = ["Near", "Mid", "Far"]
## What a fan's hair may be painted. The shader has room for this many.
const HAIR_COLORS: Array[Color] = [
	Color(0.07, 0.06, 0.05), Color(0.2, 0.12, 0.07), Color(0.36, 0.22, 0.12), Color(0.55, 0.38, 0.2),
	Color(0.85, 0.7, 0.4), Color(0.62, 0.24, 0.1), Color(0.5, 0.5, 0.5), Color(0.86, 0.85, 0.8)]
## What a fan's trousers may be painted; the two teams' colours come after
## these (so there may be six at most).
const PANTS_COLORS: Array[Color] = [
	Color(0.2, 0.3, 0.5), Color(0.1, 0.13, 0.24), Color(0.07, 0.07, 0.08), Color(0.62, 0.54, 0.38),
	Color(0.33, 0.34, 0.36), Color(0.3, 0.33, 0.2)]
## Share of a team's fans whose trousers are in the team's colour too.
const TEAM_PANTS_SHARE: float = 0.2
## The fans' meshes are the size of the character they are made from; this
## makes them the size of the players (the scale of Model in player.tscn).
const FAN_SCALE: float = 1.25
## A sign, in the fan mesh's units (so FAN_SCALE times this in yards): as wide
## as this, with the shape of a cell of the picture of the signs, its bottom
## edge this far below the holder's finger tips.
const SIGN_WIDTH: float = 2.0
const SIGN_GRIP: float = 0.08
## Where a fan's arms turn and where the hands of one with a sign are, if
## KIT_SCENE does not say (tools/prep_crowd.py writes both into it).
const DEFAULT_SHOULDER: Vector3 = Vector3(0.2, 0.56, -0.08)
const DEFAULT_HAND: Vector3 = Vector3(0.38, 1.09, -0.08)
## A quarter circle of the bowl is cut into this many pieces, each of which
## picks its level of detail by itself (a straight is cut at its aisles).
const ARC_CHUNKS: int = 3
## Yards over which one level of detail gives way to the next.
const LOD_BLEND: float = 4.0
## What the signs in the crowd say. One cell each of a picture SIGN_GRID cells
## across and down, drawn once at the start (see _bake_signs); a fan with a
## sign gets one of them at random. A cell has the shape of the board (see
## _board_mesh).
const SIGN_TEXTS: PackedStringArray = [
	"I LOVE YOU TONY!\nLove, Carol", "JIM, CALL YOUR MOTHER", "HAS ANYONE SEEN THE COMMISSIONER?",
	"I'M ONLY HERE FOR THE NACHOS", "MY EX IS IN SECTION 12", "HI MOM! SEND MONEY",
	"4TH & 20? GO FOR IT!", "THIS SIGN IS BLOCKING YOUR VIEW", "DEFENSE!\n(please)",
	"I SKIPPED MY WEDDING FOR THIS", "WHO LET THE DOG ON THE FIELD?", "REF, YOUR GLASSES ARE AT HOME",
	"NO MAYO. EVER.", "CAROL, DROP ME FROM THE LEAGUE", "MARRY ME, HOT DOG GUY",
	"GO TEAM!\n(either one)"]
const SIGN_GRID: Vector2i = Vector2i(4, 4)
const SIGN_CELL: Vector2i = Vector2i(540, 300)
const SIGN_FONT_NAMES: PackedStringArray = ["Comic Sans MS", "Segoe Print", "Arial Black"]
const SIGN_PAPER: Array[Color] = [Color(0.97, 0.96, 0.9), Color(1.0, 0.93, 0.45), Color(1.0, 0.8, 0.86), Color(0.8, 0.93, 1.0)]
const SIGN_INK: Array[Color] = [Color(0.08, 0.08, 0.1), Color(0.75, 0.08, 0.1), Color(0.1, 0.2, 0.6)]
const PROP_DIR: String = "res://assets/stadium/"
## A team's mascot, by its short name in lower case (see tools/prep_mascot.py);
## a team without one gets the banana.
const MASCOT_FILE: String = "mascot_%s.glb"
const MASCOT_FALLBACK: String = "mascot_bananaz.glb"
## Yards tall, unless that makes it wider than MASCOT_WIDTH: a round fruit as
## tall as the banana would hide the front rows.
const MASCOT_HEIGHT: float = 2.8
const MASCOT_WIDTH: float = 2.0
## How loud its side's cheer or slump has to be (0..1) for a mascot to join in.
const MASCOT_REACTS_FROM: float = 0.2

## Yards from the sidelines and the end lines to the wall.
const WALL_GAP_SIDE: float = 6.0
const WALL_GAP_END: float = 8.0
const CORNER_RADIUS: float = 10.0
const WALL_HEIGHT: float = 1.7
const WALL_THICKNESS: float = 0.4
## Height of the first row's floor; each row is ROW_DEPTH deep and ROW_RISE higher.
const FIRST_ROW_HEIGHT: float = 1.1
const ROW_DEPTH: float = 1.5
const ROW_RISE: float = 0.75
## A fan's seat above the floor of its row, and the room each one gets.
const SEAT_HEIGHT: float = 0.48
const SEAT_PITCH: float = 1.2
const AISLE_WIDTH: float = 1.8
const BAY_SEATS: int = 9
## The walkway behind the top row, and the wall behind that.
const CONCOURSE_DEPTH: float = 4.0
const BACK_WALL_HEIGHT: float = 2.6
const BACK_WALL_THICKNESS: float = 0.6
const ARC_STEPS: int = 8
## Tunnel mouths in the long stands: the rows they take up and half their width.
const TUNNEL_ROWS: Vector2i = Vector2i(3, 6)
const TUNNEL_HALF_WIDTH: float = 1.6

const CONCRETE: Color = Color(0.23, 0.24, 0.27)
const STEP_COLOR: Color = Color(0.37, 0.37, 0.39)
const SEAT_GREY: Color = Color(0.2, 0.21, 0.25)
const WALL_COLOR: Color = Color(0.09, 0.11, 0.19)
const WALL_CAP_COLOR: Color = Color(0.42, 0.43, 0.46)
const BACK_WALL_COLOR: Color = Color(0.15, 0.16, 0.2)
const TUNNEL_COLOR: Color = Color(0.02, 0.02, 0.03)
const BOARD_TEXT_COLOR: Color = Color(0.86, 0.84, 0.76)
const BOARD_COLORS: Array[Color] = [
	Color(0.36, 0.12, 0.12), Color(0.12, 0.26, 0.36), Color(0.14, 0.3, 0.18),
	Color(0.38, 0.28, 0.08), Color(0.26, 0.14, 0.34), Color(0.1, 0.1, 0.12)]
const BOARD_WIDTH: float = 8.0
const BOARD_GAP: float = 0.5
## The sponsors on the wall: the booth's world (see docs/booth.md).
const BOARD_TEXTS: PackedStringArray = [
	"CAROL'S FANTASY LEAGUE", "NACHO LINE THIS WAY", "MAYO-FREE ZONE", "JIM & TONY LIVE!",
	"HEADSET GUYS LLC", "MISSING: 1 COMMISSIONER", "LAWN CHAIR DEPOT", "HOT DOGS! HOT DOGS!",
	"FOAM FINGER EMPORIUM", "DOG-ON-FIELD INSURANCE", "GO BANANAZ", "4TH & 20 CLUB",
	"BIG AL'S USED PYLONS", "EAT MORE NACHOS"]
const FONT_NAMES: PackedStringArray = ["Impact", "Haettenschweiler", "Arial Black"]
const SCREEN_COLOR: Color = Color(0.03, 0.04, 0.07)
const SCREEN_TEXT_COLOR: Color = Color(1.0, 0.86, 0.3)
## The screen of jumbotron.glb, as shares of the model's width and height: its
## middle (x is unused) and its size.
const SCREEN_RECT: Rect2 = Rect2(0.5, 0.658, 0.72, 0.44)
## Seconds "TOUCHDOWN!" flashes on the jumbotrons.
const FLASH_TIME: float = 4.0
## A reaction smaller than this does not get anyone out of their seat.
const REACT_FROM: float = 0.3
## How fast a cheer (or a sulk) wears off, per second.
const CHEER_DECAY: float = 0.3
const WAVE_STATES: Array[StringName] = [&"PlaySelect", &"PreSnap"]


## One stretch of the outline: a straight or a quarter circle. `s` runs along
## it (yards on a straight, radians on an arc) and `d` is yards out from the
## wall, so point(s, d) is the same seat one row further back as d grows.
class Run:
	var arc: bool = false
	var start: Vector3
	var dir: Vector3
	var normal: Vector3
	var length: float = 0.0
	var centre: Vector3
	var from_angle: float = 0.0
	## Chance that a fan of a team in this part is the home team's.
	var home_chance: float = 0.5
	## [from, to, is aisle, has a tunnel] along the run.
	var slices: Array = []

	func span() -> float:
		return PI * 0.5 if arc else length

	func outward(s: float) -> Vector3:
		if not arc:
			return normal
		var angle: float = from_angle + s
		return Vector3(cos(angle), 0.0, sin(angle))

	func point(s: float, d: float) -> Vector3:
		if not arc:
			return start + dir * s + normal * d
		return centre + outward(s) * (CORNER_RADIUS + d)


## The parts of the fans of one gender. Any head goes on any torso and any
## torso on any legs: tools/prep_crowd.py cut them to fit.
class Kit:
	var gender: String = ""
	## Per level of detail (near, mid), the meshes of each kind of part.
	var heads: Array = [[], []]
	var torsos: Array = [[], []]
	var legs: Array = [[], []]
	## Torsos with the arms up, for a fan with a sign.
	var sign_torsos: Array = [[], []]
	## A whole fan at the plainest level, and one with the arms up.
	var far: Mesh
	var far_sign: Mesh
	## Where the arms turn, and where the hands of a fan with a sign are.
	var shoulder: Vector3 = DEFAULT_SHOULDER
	var hand: Vector3 = DEFAULT_HAND
	var material: ShaderMaterial
	var sign_material: ShaderMaterial
	var sign_mesh: Mesh

	func complete() -> bool:
		for tier: int in 2:
			for parts: Array in [heads, torsos, legs, sign_torsos]:
				if (parts[tier] as Array).is_empty() or (parts[tier] as Array).size() != (parts[0] as Array).size():
					return false
		return far != null and far_sign != null


var tuning: Tuning
## Fans in the stands, and how many of them are for the home team in the
## parts given to the home team and to the visitors (the tests read these).
var fan_count: int = 0
## Where each one sits (headless Godot cannot read a MultiMesh back).
var fan_positions: PackedVector3Array = PackedVector3Array()
var home_side_fans: Vector2i = Vector2i.ZERO
var away_side_fans: Vector2i = Vector2i.ZERO
## What the shader is told, 0 = home and 1 = away.
var cheer: PackedFloat32Array = [0.0, 0.0]
var slump: PackedFloat32Array = [0.0, 0.0]
var excitement: float = 0.0
## 0..1 round the bowl while a wave is going, else -1.
var wave_progress: float = -1.0
var runs: Array[Run] = []

var _game: Game
## One kit of parts per gender there are parts for.
var _kits: Array[Kit] = []
## The first kit's material (they are all told the same; the tests read it).
var _material: ShaderMaterial
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _home_color: Color
var _away_color: Color
var _names: PackedStringArray = ["HOME", "AWAY"]
var _wave_in: float = 0.0
var _wave_from: float = 0.0
var _last_tick: int = 0
var _scores: Vector2i = Vector2i(-1, -1)
var _flash: float = 0.0
var _score_labels: Array[Label3D] = []
var _flash_labels: Array[Label3D] = []
## The home team's mascot and the visitors', with the height each stands at,
## its AnimationPlayer (null for a model without clips) and the clip it is in.
var _mascots: Array[Node3D] = []
var _mascot_y: PackedFloat32Array = PackedFloat32Array()
var _mascot_players: Array[AnimationPlayer] = []
var _mascot_clips: PackedStringArray = PackedStringArray()
var _font: Font
var _clock: float = 0.0
## The picture of the signs, once it has been drawn (never when headless).
var sign_atlas: Texture2D

## Where things are, for whoever wants to move them.
var props: Node3D
var booth_anchor: Marker3D


## `left_is_home`: the home team's own end zone is the one at x < 0.
func setup(p_tuning: Tuning, home: Team, away: Team, left_is_home: bool) -> void:
	tuning = p_tuning
	for old: Node in get_children():
		old.free()
	fan_count = 0
	fan_positions.clear()
	_score_labels.clear()
	_flash_labels.clear()
	_mascots.clear()
	_mascot_y.clear()
	_mascot_players.clear()
	_mascot_clips.clear()
	if not tuning.stadium_enabled:
		set_process(false)
		return
	# The teams of the main menu are gone after this call: keep what is needed.
	_home_color = home.team_color
	_away_color = away.team_color
	_names = PackedStringArray([home.short_name, away.short_name])
	# Moved every rendered frame, never by physics.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = tuning.crowd_seed
	var font: SystemFont = SystemFont.new()
	font.font_names = FONT_NAMES
	_font = font

	_lay_out(left_is_home)
	_build_shell()
	_build_boards()
	_build_crowd()
	_bake_signs()
	_build_props()
	_wave_in = _rng.randf_range(tuning.wave_min_gap, tuning.wave_max_gap) * 0.5
	_last_tick = Time.get_ticks_usec()
	set_process(true)
	_push_uniforms()


## The match whose score, mood and breaks in play the stadium follows.
func watch(game: Game) -> void:
	_game = game


## Something good happened for the home team (or the visitors), `size` 0..1:
## their fans get up, the others sink into their seats.
func react(for_home: bool, size: float) -> void:
	if size < REACT_FROM:
		return
	var mine: int = 0 if for_home else 1
	cheer[mine] = maxf(cheer[mine], size)
	cheer[1 - mine] *= 0.3
	slump[1 - mine] = maxf(slump[1 - mine], size * 0.8)
	slump[mine] = 0.0


## Sets a wave off round the bowl, starting from a random place.
func start_wave() -> void:
	wave_progress = 0.0
	_wave_from = _rng.randf()


## The main menu's title stands where the far jumbotron is.
func show_jumbotrons(shown: bool) -> void:
	if props != null:
		(props.get_node(^"Jumbotrons") as Node3D).visible = shown


func rows() -> int:
	return maxi(tuning.stadium_rows, 1)


## Height of the walkway behind the top row.
func top_height() -> float:
	return FIRST_ROW_HEIGHT + float(rows()) * ROW_RISE


## Yards from the wall to the inside of the back wall.
func depth() -> float:
	return float(rows()) * ROW_DEPTH + CONCOURSE_DEPTH


func _process(_delta: float) -> void:
	# Real time, like the audio: hit-stop and the tests' fast-forward bend delta.
	var now: int = Time.get_ticks_usec()
	var delta: float = minf(float(now - _last_tick) / 1000000.0, 0.1)
	_last_tick = now
	_clock += delta
	for i: int in 2:
		cheer[i] = move_toward(cheer[i], 0.0, CHEER_DECAY * delta)
		slump[i] = move_toward(slump[i], 0.0, CHEER_DECAY * 0.6 * delta)

	var between_plays: bool = true
	if _game != null:
		excitement = _game.audio.excitement
		between_plays = _game.play_controller.state_machine.current_name() in WAVE_STATES
		_follow_score(delta)
	if wave_progress >= 0.0:
		wave_progress += delta / maxf(tuning.wave_lap_time, 0.1)
		if wave_progress >= 1.0:
			wave_progress = -1.0
			_wave_in = _rng.randf_range(tuning.wave_min_gap, tuning.wave_max_gap)
	else:
		_wave_in -= delta
		if _wave_in <= 0.0 and between_plays:
			start_wave()
	for i: int in _mascots.size():
		var hop: float = absf(sin(_clock * 3.0 + float(i))) * (0.12 + 0.9 * cheer[i])
		_mascots[i].position.y = _mascot_y[i] + hop
		_mascots[i].rotation.z = sin(_clock * 1.5 + float(i)) * 0.06
		_play_mascot(i)
	_push_uniforms()


func _push_uniforms() -> void:
	if _material == null:
		return
	var on: float = 0.0
	if wave_progress >= 0.0:
		# Up over the first tenth of the lap, away over the last.
		on = smoothstep(0.0, 0.1, wave_progress) * (1.0 - smoothstep(0.9, 1.0, wave_progress))
	var at: float = fposmod(_wave_from + maxf(wave_progress, 0.0), 1.0)
	# The signs move with the fans who hold them.
	var materials: Array[ShaderMaterial] = []
	for kit: Kit in _kits:
		materials.append(kit.material)
		materials.append(kit.sign_material)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter(&"excitement", excitement)
		material.set_shader_parameter(&"cheer_home", cheer[0])
		material.set_shader_parameter(&"cheer_away", cheer[1])
		material.set_shader_parameter(&"slump_home", slump[0])
		material.set_shader_parameter(&"slump_away", slump[1])
		material.set_shader_parameter(&"wave_on", on)
		material.set_shader_parameter(&"wave_pos", at)


# --- Layout ------------------------------------------------------------------------

## The eight runs, going round from the right end (+X) by the +Z sideline.
func _lay_out(left_is_home: bool) -> void:
	runs.clear()
	var mid_x: float = tuning.field_length * 0.5
	var half_x: float = mid_x + tuning.end_zone_depth + WALL_GAP_END
	var half_z: float = tuning.half_width() + WALL_GAP_SIDE
	var inner_x: float = half_x - CORNER_RADIUS
	var inner_z: float = half_z - CORNER_RADIUS
	var home: float = tuning.crowd_home_share
	var away: float = 1.0 - tuning.crowd_away_share
	var left: float = home if left_is_home else away
	var right: float = away if left_is_home else home
	# The home crowd has the stand at -Z and its own team's end.
	_add_straight(Vector3(mid_x + half_x, 0.0, -inner_z), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), inner_z * 2.0, right)
	_add_arc(Vector3(mid_x + inner_x, 0.0, inner_z), 0.0)
	_add_straight(Vector3(mid_x + inner_x, 0.0, half_z), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), inner_x * 2.0, away)
	_add_arc(Vector3(mid_x - inner_x, 0.0, inner_z), PI * 0.5)
	_add_straight(Vector3(mid_x - half_x, 0.0, inner_z), Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0), inner_z * 2.0, left)
	_add_arc(Vector3(mid_x - inner_x, 0.0, -inner_z), PI)
	_add_straight(Vector3(mid_x - inner_x, 0.0, -half_z), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), inner_x * 2.0, home)
	_add_arc(Vector3(mid_x + inner_x, 0.0, -inner_z), PI * 1.5)


func _add_straight(start: Vector3, dir: Vector3, normal: Vector3, length: float, home_chance: float) -> void:
	var run: Run = Run.new()
	run.start = start
	run.dir = dir
	run.normal = normal
	run.length = length
	run.home_chance = home_chance
	# aisle, bay, aisle, ... aisle, with the bays stretched to fit.
	var bay_length: float = float(BAY_SEATS) * SEAT_PITCH
	var bays: int = maxi(roundi((length - AISLE_WIDTH) / (bay_length + AISLE_WIDTH)), 1)
	bay_length = (length - float(bays + 1) * AISLE_WIDTH) / float(bays)
	var at: float = 0.0
	for bay: int in bays:
		run.slices.append([at, at + AISLE_WIDTH, true, false])
		at += AISLE_WIDTH
		run.slices.append([at, at + bay_length, false, length > 60.0 and bay % 2 == 1])
		at += bay_length
	run.slices.append([at, length, true, false])
	runs.append(run)


func _add_arc(centre: Vector3, from_angle: float) -> void:
	var run: Run = Run.new()
	run.arc = true
	run.centre = centre
	run.from_angle = from_angle
	var step: float = PI * 0.5 / float(ARC_STEPS)
	for i: int in ARC_STEPS:
		run.slices.append([float(i) * step, float(i + 1) * step, false, false])
	runs.append(run)


# --- Stands ------------------------------------------------------------------------

func _build_shell() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = rows()
	var top: float = top_height()
	var back: float = depth()
	for run: Run in runs:
		var seat_color: Color = SEAT_GREY.lerp(_home_color.lerp(_away_color, 1.0 - run.home_chance), 0.3).darkened(0.25)
		for slice: Array in run.slices:
			var s0: float = slice[0]
			var s1: float = slice[1]
			var aisle: bool = slice[2]
			# The wall: the face to the field, the cap, the face to the stands.
			_strip(st, run, s0, s1, -WALL_THICKNESS, 0.0, -WALL_THICKNESS, WALL_HEIGHT, WALL_COLOR, -1.0)
			_strip(st, run, s0, s1, -WALL_THICKNESS, WALL_HEIGHT, 0.0, WALL_HEIGHT, WALL_CAP_COLOR, 0.0)
			_strip(st, run, s0, s1, 0.0, FIRST_ROW_HEIGHT, 0.0, WALL_HEIGHT, WALL_COLOR, 1.0)
			for row: int in count:
				var d0: float = float(row) * ROW_DEPTH
				var d1: float = d0 + ROW_DEPTH
				var h: float = FIRST_ROW_HEIGHT + float(row) * ROW_RISE
				if not aisle:
					if row > 0:
						_strip(st, run, s0, s1, d0, h - ROW_RISE, d0, h, seat_color, -1.0)
					_strip(st, run, s0, s1, d0, h, d1, h, CONCRETE, 0.0)
					continue
				# Two steps to a row in the aisles.
				var half_d: float = d0 + ROW_DEPTH * 0.5
				var half_h: float = h - ROW_RISE * 0.5
				if row > 0:
					_strip(st, run, s0, s1, d0, h - ROW_RISE, d0, half_h, STEP_COLOR.darkened(0.3), -1.0)
					_strip(st, run, s0, s1, d0, half_h, half_d, half_h, STEP_COLOR, 0.0)
					_strip(st, run, s0, s1, half_d, half_h, half_d, h, STEP_COLOR.darkened(0.3), -1.0)
					# The sides of the rows next to the lower step.
					_side(st, run, s0, d0, half_d, half_h, h, CONCRETE.darkened(0.2), 1.0)
					_side(st, run, s1, d0, half_d, half_h, h, CONCRETE.darkened(0.2), -1.0)
					_strip(st, run, s0, s1, half_d, h, d1, h, STEP_COLOR, 0.0)
				else:
					_strip(st, run, s0, s1, d0, h, d1, h, STEP_COLOR, 0.0)
			# Walkway, back wall and the outside of the bowl.
			var d_top: float = float(count) * ROW_DEPTH
			var wall_top: float = top + BACK_WALL_HEIGHT
			_strip(st, run, s0, s1, d_top, top - ROW_RISE, d_top, top, CONCRETE.darkened(0.2), -1.0)
			_strip(st, run, s0, s1, d_top, top, back, top, CONCRETE.lightened(0.06), 0.0)
			_strip(st, run, s0, s1, back, top, back, wall_top, BACK_WALL_COLOR, -1.0)
			_strip(st, run, s0, s1, back, wall_top, back + BACK_WALL_THICKNESS, wall_top, WALL_CAP_COLOR, 0.0)
			_strip(st, run, s0, s1, back + BACK_WALL_THICKNESS, 0.0, back + BACK_WALL_THICKNESS, wall_top, BACK_WALL_COLOR.darkened(0.3), 1.0)
			if slice[3]:
				_tunnel(st, run, (s0 + s1) * 0.5)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "Stands"
	shell.mesh = st.commit()
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)


## A strip along a slice of a run, between (d0, y0) and (d1, y1) in the run's
## cross-section. `facing`: 0 for a floor (normal up), -1 for a face turned to
## the field, +1 for one turned away from it.
func _strip(st: SurfaceTool, run: Run, s0: float, s1: float, d0: float, y0: float, d1: float, y1: float, color: Color, facing: float) -> void:
	var up0: Vector3 = Vector3(0.0, y0, 0.0)
	var up1: Vector3 = Vector3(0.0, y1, 0.0)
	var mid: float = (s0 + s1) * 0.5
	var normal: Vector3 = Vector3.UP if facing == 0.0 else run.outward(mid) * facing
	_quad(st, run.point(s0, d0) + up0, run.point(s1, d0) + up0, run.point(s1, d1) + up1, run.point(s0, d1) + up1, normal, color)


## An upright face across a run at `s`, from d0 to d1 and y0 to y1, turned
## along the run (`toward` +1) or back along it (-1).
func _side(st: SurfaceTool, run: Run, s: float, d0: float, d1: float, y0: float, y1: float, color: Color, toward: float) -> void:
	var a: Vector3 = run.point(s, d0)
	var b: Vector3 = run.point(s, d1)
	var up0: Vector3 = Vector3(0.0, y0, 0.0)
	var up1: Vector3 = Vector3(0.0, y1, 0.0)
	_quad(st, a + up0, b + up0, b + up1, a + up1, run.dir * toward, color)


## A tunnel mouth: a block let into the rows with a dark opening to the field.
func _tunnel(st: SurfaceTool, run: Run, at: float) -> void:
	var s0: float = at - TUNNEL_HALF_WIDTH
	var s1: float = at + TUNNEL_HALF_WIDTH
	var d0: float = float(TUNNEL_ROWS.x) * ROW_DEPTH
	var d1: float = float(TUNNEL_ROWS.y) * ROW_DEPTH
	var floor_y: float = FIRST_ROW_HEIGHT + float(TUNNEL_ROWS.x - 1) * ROW_RISE
	var top_y: float = FIRST_ROW_HEIGHT + float(TUNNEL_ROWS.y) * ROW_RISE + 0.35
	_strip(st, run, s0, s1, d0, floor_y, d0, top_y, CONCRETE.darkened(0.25), -1.0)
	_strip(st, run, s0 + 0.25, s1 - 0.25, d0 - 0.01, floor_y, d0 - 0.01, top_y - 0.3, TUNNEL_COLOR, -1.0)
	_strip(st, run, s0, s1, d0, top_y, d1, top_y, CONCRETE, 0.0)
	_side(st, run, s0, d0, d1, floor_y, top_y, CONCRETE.darkened(0.2), -1.0)
	_side(st, run, s1, d0, d1, floor_y, top_y, CONCRETE.darkened(0.2), 1.0)


## Two triangles for the corners a, b, c, d (in order round the quad), wound so
## that the side `normal` points out of is the front.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var corners: Array[Vector3] = [a, b, c, a, c, d]
	# Godot's front faces are clockwise.
	if (b - a).cross(c - a).dot(normal) > 0.0:
		corners = [a, c, b, a, d, c]
	for corner: Vector3 in corners:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(corner)


# --- Ad boards -----------------------------------------------------------------------

func _build_boards() -> void:
	var boards: Node3D = Node3D.new()
	boards.name = "Boards"
	add_child(boards)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var next: int = 0
	for run: Run in runs:
		if run.arc:
			continue
		var count: int = maxi(int(run.length / (BOARD_WIDTH + BOARD_GAP)), 1)
		var room: float = run.length / float(count)
		for i: int in count:
			var s0: float = float(i) * room + BOARD_GAP * 0.5
			var s1: float = float(i + 1) * room - BOARD_GAP * 0.5
			var out: float = -WALL_THICKNESS - 0.03
			_strip(st, run, s0, s1, out, 0.2, out, WALL_HEIGHT - 0.15, BOARD_COLORS[next % BOARD_COLORS.size()], -1.0)
			var text: String = BOARD_TEXTS[next % BOARD_TEXTS.size()]
			var label: Label3D = _label(text, 96, BOARD_TEXT_COLOR)
			# As big as fits the board, in height and in width.
			var size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 96)
			label.pixel_size = minf((WALL_HEIGHT - 0.75) / size.y, (s1 - s0 - 0.6) / size.x)
			label.position = run.point((s0 + s1) * 0.5, out - 0.03) + Vector3(0.0, WALL_HEIGHT * 0.5 + 0.02, 0.0)
			label.basis = _facing_field(run, (s0 + s1) * 0.5)
			boards.add_child(label)
			next += 1
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	var panels: MeshInstance3D = MeshInstance3D.new()
	panels.name = "Panels"
	panels.mesh = st.commit()
	panels.material_override = material
	panels.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	boards.add_child(panels)


func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = font_size
	label.outline_size = 0
	label.modulate = color
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return label


## Turned to look in over the field from the run at `s` (local +Z points in).
func _facing_field(run: Run, s: float) -> Basis:
	var inward: Vector3 = -run.outward(s)
	return Basis(Vector3.UP.cross(inward), Vector3.UP, inward)


# --- Crowd -------------------------------------------------------------------------

func _build_crowd() -> void:
	var crowd: Node3D = Node3D.new()
	crowd.name = "Crowd"
	add_child(crowd)
	home_side_fans = Vector2i.ZERO
	away_side_fans = Vector2i.ZERO
	_material = null
	_kits = _load_kits()
	if _kits.is_empty():
		push_warning("Stadium: %s is missing or out of date (run tools/prep_crowd.py), so the stands are empty." % KIT_SCENE)
		return
	var atlas: Texture2D = _kit_texture(KIT_ATLAS)
	var mask: Texture2D = _kit_texture(KIT_MASK)
	var hair: PackedColorArray = PackedColorArray(HAIR_COLORS)
	var pants: PackedColorArray = PackedColorArray(PANTS_COLORS)
	pants.append(_home_color)
	pants.append(_away_color)
	for kit: Kit in _kits:
		kit.material = ShaderMaterial.new()
		kit.material.shader = CROWD_SHADER
		kit.material.set_shader_parameter(&"dim", tuning.crowd_dim)
		kit.material.set_shader_parameter(&"saturation", tuning.crowd_saturation)
		kit.material.set_shader_parameter(&"shoulder", kit.shoulder)
		kit.material.set_shader_parameter(&"atlas_tex", atlas)
		kit.material.set_shader_parameter(&"mask_tex", mask)
		kit.material.set_shader_parameter(&"hair_colors", hair)
		kit.material.set_shader_parameter(&"pants_colors", pants)
		kit.sign_material = ShaderMaterial.new()
		kit.sign_material.shader = SIGN_SHADER
		kit.sign_material.set_shader_parameter(&"shoulder", kit.shoulder)
		kit.sign_material.set_shader_parameter(&"sign_grid", Vector2(SIGN_GRID))
		kit.sign_mesh = _board_mesh(kit.hand)
		for parts: Array in [kit.heads, kit.torsos, kit.legs, kit.sign_torsos, [[kit.far, kit.far_sign]]]:
			for meshes: Array in parts:
				for mesh: Mesh in meshes:
					mesh.set_meta(&"material", kit.material)
	_material = _kits[0].material

	var mid_x: float = tuning.field_length * 0.5
	for index: int in runs.size():
		var run: Run = runs[index]
		# Per chunk of the run (a bay, or a piece of a corner): what
		# _new_chunk() makes, filled by _seat().
		var chunks: Dictionary = {}
		for row: int in rows():
			var d: float = (float(row) + 0.55) * ROW_DEPTH
			var y: float = FIRST_ROW_HEIGHT + float(row) * ROW_RISE + SEAT_HEIGHT
			var stretches: Array = run.slices
			if run.arc:
				stretches = [[0.0, PI * 0.5, false, false]]
			for slice_index: int in stretches.size():
				var slice: Array = stretches[slice_index]
				if slice[2]:
					continue
				var s0: float = slice[0]
				var s1: float = slice[1]
				var yards: float = (s1 - s0) * (CORNER_RADIUS + d) if run.arc else s1 - s0
				var seats: int = int(yards / SEAT_PITCH)
				var in_tunnel: bool = slice[3] and row >= TUNNEL_ROWS.x and row < TUNNEL_ROWS.y
				for seat: int in seats:
					var s: float = s0 + (float(seat) + 0.5) * (s1 - s0) / float(seats)
					if in_tunnel and absf(s - (s0 + s1) * 0.5) < TUNNEL_HALF_WIDTH + SEAT_PITCH * 0.5:
						continue
					if _rng.randf() >= tuning.crowd_density:
						continue
					var at: Vector3 = run.point(s, d) + Vector3(0.0, y, 0.0)
					var chunk: int = slice_index
					if run.arc:
						chunk = mini(int(s / (PI * 0.5) * float(ARC_CHUNKS)), ARC_CHUNKS - 1)
					if not chunks.has(chunk):
						chunks[chunk] = _new_chunk()
					_seat(chunks[chunk], _fan(run, s, at, mid_x))
					fan_positions.append(at)
		for chunk: int in chunks:
			_add_chunk(crowd, "Chunk%d_%d" % [index, chunk], chunks[chunk])


## What is gathered for one piece of the stands before it is built: per level
## of detail the fans each mesh is drawn for (mesh -> list of fans), per kit
## the fans with a sign, and all the fans. A fan is [transform, colour, custom].
func _new_chunk() -> Array:
	var signs: Array = []
	for kit: Kit in _kits:
		signs.append([])
	return [[{}, {}, {}], signs, []]


## Gives `fan` a gender, a head, an outfit and legs, and enters it in `chunk`
## under each of the meshes it is drawn with. All its parts get the same
## transform, colour and custom data, so they move as one; the shader takes
## from them what each part needs.
func _seat(chunk: Array, fan: Array) -> void:
	var which: int = 0
	if _kits.size() > 1 and _rng.randf() < tuning.crowd_female_share:
		which = 1
	var kit: Kit = _kits[which]
	var holds_sign: bool = _rng.randf() < SIGN_SHARE
	var head: int = _rng.randi() % (kit.heads[0] as Array).size()
	var torso: int = _rng.randi() % (kit.torsos[0] as Array).size()
	var legs: int = _rng.randi() % (kit.legs[0] as Array).size()
	var tiers: Array = chunk[0]
	for tier: int in 2:
		var parts: Array[Mesh] = [kit.heads[tier][head], kit.torsos[tier][torso], kit.legs[tier][legs]]
		if holds_sign:
			# Only the first outfit is made with the arms up.
			parts[1] = kit.sign_torsos[tier][0]
		for mesh: Mesh in parts:
			_enter(tiers[tier], mesh, fan)
	_enter(tiers[2], kit.far_sign if holds_sign else kit.far, fan)
	if holds_sign:
		(chunk[1][which] as Array).append(fan)
	(chunk[2] as Array).append(fan)


func _enter(group: Dictionary, mesh: Mesh, fan: Array) -> void:
	if not group.has(mesh):
		group[mesh] = []
	(group[mesh] as Array).append(fan)


## One piece of the stands: the same fans three times over, as parts in full
## detail up to crowd_lod_near yards from the camera, as plainer parts up to
## crowd_lod_far, and as one plain mesh each beyond. `record` is what
## _new_chunk() and _seat() made.
func _add_chunk(crowd: Node3D, chunk_name: String, record: Array) -> void:
	var all: Array = record[2]
	if all.is_empty():
		return
	var centre: Vector3 = Vector3.ZERO
	for fan: Array in all:
		centre += (fan[0] as Transform3D).origin
	centre /= float(all.size())
	# The ranges are measured from here.
	var chunk: Node3D = Node3D.new()
	chunk.name = chunk_name
	chunk.position = centre
	crowd.add_child(chunk)
	fan_count += all.size()
	var near: float = maxf(tuning.crowd_lod_near, 0.0)
	var far: float = maxf(tuning.crowd_lod_far, near)
	for tier: int in TIER_NAMES.size():
		var group: Dictionary = record[0][tier]
		var number: int = 0
		for mesh: Mesh in group:
			var instance: MultiMeshInstance3D = _scatter(mesh, group[mesh], centre, mesh.get_meta(&"material"))
			instance.name = "%s%d" % [TIER_NAMES[tier], number]
			instance.set_meta(&"kind", mesh.get_meta(&"kind"))
			number += 1
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if tier > 0:
				instance.visibility_range_begin = near if tier == 1 else far
				instance.visibility_range_begin_margin = LOD_BLEND
			if tier < 2:
				instance.visibility_range_end = near if tier == 0 else far
				instance.visibility_range_end_margin = LOD_BLEND
			chunk.add_child(instance)
	# The signs are one flat board each: no levels of detail.
	for which: int in _kits.size():
		var holders: Array = record[1][which]
		if holders.is_empty():
			continue
		var signs: MultiMeshInstance3D = _scatter(_kits[which].sign_mesh, holders, centre, _kits[which].sign_material)
		signs.name = "Signs%d" % which
		chunk.add_child(signs)


## A MultiMesh of `mesh`, one for each of `fans` ([transform, colour, custom]),
## on a node that will stand at `centre`.
func _scatter(mesh: Mesh, fans: Array, centre: Vector3, material: Material) -> MultiMeshInstance3D:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = fans.size()
	for f: int in fans.size():
		var seat: Transform3D = fans[f][0]
		seat.origin -= centre
		multimesh.set_instance_transform(f, seat)
		multimesh.set_instance_color(f, fans[f][1])
		multimesh.set_instance_custom_data(f, fans[f][2])
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader lifts fans out of their seats, past the mesh's bounds.
	instance.extra_cull_margin = 2.0
	return instance


## The board a fan with a sign holds over the head, in the fan mesh's own
## space: its front faces the field (+Z) and its bottom edge is in the hands,
## which are at `hand` (the left one).
func _board_mesh(hand: Vector3) -> Mesh:
	var half: float = SIGN_WIDTH * 0.5
	var bottom: float = hand.y - SIGN_GRIP
	var top: float = bottom + SIGN_WIDTH * float(SIGN_CELL.y) / float(SIGN_CELL.x)
	var z: float = hand.z + 0.04
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0.0, 0.0, 1.0))
	# Seen from the field, +X is on the right.
	var corners: Array = [
		[Vector3(half, top, z), Vector2(1.0, 0.0)], [Vector3(-half, top, z), Vector2(0.0, 0.0)],
		[Vector3(-half, bottom, z), Vector2(0.0, 1.0)], [Vector3(half, bottom, z), Vector2(1.0, 1.0)]]
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.set_uv(corners[i][1])
		st.add_vertex(corners[i][0])
	return st.commit()


## Draws every sign into one picture, once, and hands it to the crowd shader:
## a grid of paper-coloured cells with the texts written on them, drawn by a
## viewport that is thrown away afterwards.
func _bake_signs() -> void:
	if _kits.is_empty() or DisplayServer.get_name() == "headless":
		return
	var materials: Array[ShaderMaterial] = []
	for kit: Kit in _kits:
		materials.append(kit.sign_material)
	var font: SystemFont = SystemFont.new()
	font.font_names = SIGN_FONT_NAMES
	font.font_weight = 700
	var viewport: SubViewport = SubViewport.new()
	viewport.name = "SignBake"
	viewport.size = SIGN_GRID * SIGN_CELL
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i: int in SIGN_GRID.x * SIGN_GRID.y:
		var text: String = SIGN_TEXTS[i % SIGN_TEXTS.size()]
		@warning_ignore("integer_division")
		var cell: Vector2 = Vector2(i % SIGN_GRID.x, i / SIGN_GRID.x) * Vector2(SIGN_CELL)
		var paper: ColorRect = ColorRect.new()
		paper.color = SIGN_PAPER[i % SIGN_PAPER.size()]
		paper.position = cell
		paper.size = Vector2(SIGN_CELL)
		viewport.add_child(paper)
		var label: Label = Label.new()
		label.text = text
		label.position = Vector2(21.0, 12.0)
		label.size = Vector2(SIGN_CELL) - Vector2(42.0, 24.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override(&"font", font)
		label.add_theme_font_size_override(&"font_size", _sign_font_size(font, text, label.size))
		label.add_theme_color_override(&"font_color", SIGN_INK[(i + i / SIGN_PAPER.size()) % SIGN_INK.size()])
		paper.add_child(label)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	# setup() may have run again, or the stadium may be gone.
	if not is_instance_valid(viewport):
		return
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return
	image.generate_mipmaps()
	sign_atlas = ImageTexture.create_from_image(image)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter(&"sign_atlas", sign_atlas)


## The biggest lettering with which `text` fits a sign of `room` pixels
## without a word being broken.
func _sign_font_size(font: Font, text: String, room: Vector2) -> int:
	var size: int = 96
	while size > 30:
		var fits: bool = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, room.x, size).y <= room.y
		for word: String in text.split(" ", false):
			for piece: String in word.split("
", false):
				fits = fits and font.get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x <= room.x
		if fits:
			break
		size -= 2
	return size


## One fan in the seat at `at`: [transform, colour, custom data], as the
## crowd shader reads them (see crowd.gdshader). The colour is the shirt's,
## with the side and the trousers' colour in its alpha; the custom data are a
## phase, the skin tone with the hair colour, the place round the bowl and a
## random number.
func _fan(run: Run, s: float, at: Vector3, mid_x: float) -> Array:
	# Up to 5 % taller or shorter, and broader or slighter by itself.
	var size: float = FAN_SCALE * _rng.randf_range(0.95, 1.05)
	var basis: Basis = _facing_field(run, s).rotated(Vector3.UP, _rng.randf_range(-0.12, 0.12))
	basis = basis.scaled(Vector3(size * _rng.randf_range(0.9, 1.12), size * _rng.randf_range(0.97, 1.05), size))
	var side: float = 0.5
	var pants: int = _rng.randi() % PANTS_COLORS.size()
	var shirt: Color
	if _rng.randf() < tuning.crowd_neutral_share:
		shirt = Color.from_hsv(_rng.randf(), _rng.randf_range(0.2, 0.6), _rng.randf_range(0.4, 0.9))
	else:
		var for_home: bool = _rng.randf() < run.home_chance
		side = 0.0 if for_home else 1.0
		shirt = _home_color if for_home else _away_color
		var roll: float = _rng.randf()
		if _rng.randf() < TEAM_PANTS_SHARE:
			pants = PANTS_COLORS.size() + (0 if for_home else 1)
		if roll < 0.14:
			shirt = shirt.lerp(Color.WHITE, 0.8)
		elif roll < 0.3:
			shirt = shirt.darkened(_rng.randf_range(0.15, 0.4))
		else:
			shirt = shirt.lightened(_rng.randf_range(0.0, 0.15))
		# The parts given to the home crowd are the ones with home_chance over a half.
		if run.home_chance > 0.5:
			home_side_fans += Vector2i(1 if for_home else 0, 1)
		elif run.home_chance < 0.5:
			away_side_fans += Vector2i(1 if for_home else 0, 1)
	var color: Color = shirt.srgb_to_linear()
	color.a = side + 2.0 * float(pants)
	var around: float = fposmod(atan2(at.z, at.x - mid_x) / TAU, 1.0)
	# The skin tone stays under 1, so that the whole number is the hair's.
	var look: float = minf(_rng.randf(), 0.98) + float(_rng.randi() % HAIR_COLORS.size())
	return [Transform3D(basis, at), color, Color(_rng.randf(), look, around, _rng.randf())]


## The kits in KIT_SCENE, the men's first; only those with every part at every
## level of detail. tools/prep_crowd.py says what each mesh is in its "extras".
func _load_kits() -> Array[Kit]:
	var kits: Array[Kit] = []
	if not ResourceLoader.exists(KIT_SCENE):
		return kits
	var scene: Node = (load(KIT_SCENE) as PackedScene).instantiate()
	var by_gender: Dictionary = {}
	# gender -> kind -> tier -> index -> mesh
	var found: Dictionary = {}
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = node.get_meta(&"extras", {})
		if not extras.has("kind") or not extras.has("gender"):
			continue
		var mesh: Mesh = (node as MeshInstance3D).mesh
		var gender: String = extras["gender"]
		var kind: String = extras["kind"]
		var holds_sign: bool = int(extras.get("sign", 0)) == 1
		mesh.set_meta(&"kind", kind)
		if not by_gender.has(gender):
			var made: Kit = Kit.new()
			made.gender = gender
			by_gender[gender] = made
			found[gender] = {}
		var kit: Kit = by_gender[gender]
		if kind == "far":
			if holds_sign:
				kit.far_sign = mesh
				kit.hand = _kit_point(extras, "hand", kit.hand)
			else:
				kit.far = mesh
				kit.shoulder = _kit_point(extras, "shoulder", kit.shoulder)
			continue
		var slot: String = "%s%s%d" % [kind, "_sign" if holds_sign else "", int(extras.get("tier", 0))]
		if not (found[gender] as Dictionary).has(slot):
			found[gender][slot] = {}
		found[gender][slot][int(extras.get("index", 0))] = mesh
	scene.free()
	for gender: String in ["m", "f"]:
		if not by_gender.has(gender):
			continue
		var kit: Kit = by_gender[gender]
		for tier: int in 2:
			kit.heads[tier] = _in_order((found[gender] as Dictionary).get("head%d" % tier, {}))
			kit.torsos[tier] = _in_order((found[gender] as Dictionary).get("torso%d" % tier, {}))
			kit.legs[tier] = _in_order((found[gender] as Dictionary).get("legs%d" % tier, {}))
			kit.sign_torsos[tier] = _in_order((found[gender] as Dictionary).get("torso_sign%d" % tier, {}))
		if kit.complete():
			kits.append(kit)
		else:
			push_warning("Stadium: the %s parts in %s are not all there; leaving them out." % [gender, KIT_SCENE])
	return kits


## The meshes of `by_index` (index -> mesh) by their index.
func _in_order(by_index: Dictionary) -> Array:
	var keys: Array = by_index.keys()
	keys.sort()
	var meshes: Array = []
	for key: int in keys:
		meshes.append(by_index[key])
	return meshes


## A point tools/prep_crowd.py wrote down for a mesh (its "shoulder" or its
## "hand"), or `fallback` if it is not there.
func _kit_point(extras: Dictionary, point: String, fallback: Vector3) -> Vector3:
	if extras.has(point):
		var numbers: Array = extras[point]
		if numbers.size() == 3:
			return Vector3(numbers[0], numbers[1], numbers[2])
	push_warning("Stadium: %s does not say where the fans' %s is; guessing." % [KIT_SCENE, point])
	return fallback


## A picture of the kit with mipmaps, whatever way it was imported: the fans
## are small on the screen, and without them the crowd sparkles.
func _kit_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("Stadium: %s is missing (run tools/prep_crowd.py)." % path)
		return null
	var texture: Texture2D = load(path) as Texture2D
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return texture
	if image.is_compressed():
		image.decompress()
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# --- Dressing ------------------------------------------------------------------------

func _build_props() -> void:
	props = Node3D.new()
	props.name = "Props"
	add_child(props)
	var top: float = top_height()
	var back: float = depth() + BACK_WALL_THICKNESS

	# A jumbotron over each end, standing behind the back wall.
	var boards: Node3D = Node3D.new()
	boards.name = "Jumbotrons"
	props.add_child(boards)
	for index: int in [0, 4]:
		var run: Run = runs[index]
		var at: float = run.length * 0.5
		var board: Node3D = _prop("Jumbotron%d" % index, "jumbotron.glb", 32.0, Vector3(36.0, 32.0, 6.0), Color(0.12, 0.13, 0.17))
		board.transform = Transform3D(_facing_field(run, at), run.point(at, back + 3.0))
		boards.add_child(board)
		_add_screen(board)

	# A light tower outside each corner.
	var towers: Node3D = Node3D.new()
	towers.name = "LightTowers"
	props.add_child(towers)
	for index: int in [1, 3, 5, 7]:
		var run: Run = runs[index]
		var tower: Node3D = _prop("LightTower%d" % index, "light_tower.glb", 36.0, Vector3(3.0, 36.0, 3.0), Color(0.3, 0.31, 0.34))
		tower.transform = Transform3D(_facing_field(run, PI * 0.25), run.point(PI * 0.25, back + 5.0))
		towers.add_child(tower)

	# On the walkway at the top of the home stand, and bigger than life so it
	# can be made out from the field.
	var home_stand: Run = runs[6]
	var stand: Node3D = _prop("HotDogStand", "hot_dog_stand.glb", 4.2, Vector3(4.0, 4.2, 2.4), Color(0.7, 0.2, 0.15))
	var stand_at: float = home_stand.length * 0.3
	stand.transform = Transform3D(_facing_field(home_stand, stand_at), home_stand.point(stand_at, depth() - CONCOURSE_DEPTH * 0.45) + Vector3(0.0, top, 0.0))
	props.add_child(stand)

	# The home team's mascot works the home sideline, inside the wall and
	# clear of the two yards past the line the players can reach. The
	# visitors' does the same across the field.
	for side: int in 2:
		var mascot: Node3D = mascot_model(_names[side])
		if mascot == null:
			# No file at all: a plain box.
			mascot = _prop("Mascot", "", MASCOT_HEIGHT, Vector3(1.2, MASCOT_HEIGHT, 1.2), _home_color if side == 0 else _away_color)
		else:
			_no_shadows(mascot)
		mascot.name = "Mascot" if side == 0 else "MascotAway"
		var sideline: Run = home_stand if side == 0 else runs[2]
		var mascot_at: float = sideline.length * 0.5 - 14.0
		mascot.transform = Transform3D(_facing_field(sideline, mascot_at), sideline.point(mascot_at, -WALL_THICKNESS - 1.6))
		props.add_child(mascot)
		var players: Array[Node] = mascot.find_children("*", "AnimationPlayer", true, false)
		var player: AnimationPlayer = players[0] as AnimationPlayer if not players.is_empty() else null
		if player != null:
			for clip: StringName in player.get_animation_list():
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_mascots.append(mascot)
		_mascot_y.append(mascot.position.y)
		_mascot_players.append(player)
		_mascot_clips.append("")
		_play_mascot(side)

	# Where the commentary booth would go: top of the home stand, at midfield.
	booth_anchor = Marker3D.new()
	booth_anchor.name = "BoothAnchor"
	booth_anchor.transform = Transform3D(_facing_field(home_stand, home_stand.length * 0.5), home_stand.point(home_stand.length * 0.5, depth()) + Vector3(0.0, top + BACK_WALL_HEIGHT, 0.0))
	props.add_child(booth_anchor)


## The model of the mascot of the team with this short name (the banana for a
## team without one), as it stands on the sideline and runs on the field:
## MASCOT_HEIGHT tall but no wider than MASCOT_WIDTH, on its origin, facing +Z.
## Its size is in the meta "size". Null with no file to load.
static func mascot_model(short_name: String) -> Node3D:
	var path: String = PROP_DIR + MASCOT_FILE % short_name.to_lower()
	if not ResourceLoader.exists(path):
		path = PROP_DIR + MASCOT_FALLBACK
	if not ResourceLoader.exists(path):
		return null
	var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	var bounds: AABB = _bounds(model, Transform3D.IDENTITY)
	var scale_by: float = minf(MASCOT_HEIGHT / maxf(bounds.size.y, 0.001), MASCOT_WIDTH / maxf(bounds.size.x, 0.001))
	var centre: Vector3 = bounds.get_center()
	model.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale_by), Vector3(-centre.x, -bounds.position.y, -centre.z) * scale_by)
	var holder: Node3D = Node3D.new()
	holder.add_child(model)
	holder.set_meta(&"size", bounds.size * scale_by)
	return holder


## The two on the sidelines are out of sight while they are on the field for
## the scramble (see Mascot).
func set_mascots_visible(shown: bool) -> void:
	for mascot: Node3D in _mascots:
		mascot.visible = shown


## The clip a mascot should be in: up with its own crowd, down when the other
## side has scored, waving along with a wave, else idling.
func _play_mascot(side: int) -> void:
	var player: AnimationPlayer = _mascot_players[side]
	if player == null:
		return
	var clip: String = "idle"
	if cheer[side] > MASCOT_REACTS_FROM:
		clip = "cheer"
	elif slump[side] > MASCOT_REACTS_FROM:
		clip = "sulk"
	elif wave_progress >= 0.0:
		clip = "wave"
	if clip == _mascot_clips[side] or not player.has_animation(clip):
		return
	_mascot_clips[side] = clip
	player.play(clip, 0.25)


## A model from assets/stadium scaled to `height`, standing on its origin and
## facing +Z; a plain box of `fallback` size and colour while there is no file.
func _prop(node_name: String, file: String, height: float, fallback: Vector3, color: Color) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	var path: String = PROP_DIR + file
	if ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		var bounds: AABB = _bounds(model, Transform3D.IDENTITY)
		var scale_by: float = height / maxf(bounds.size.y, 0.001)
		var centre: Vector3 = bounds.get_center()
		model.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale_by), Vector3(-centre.x, -bounds.position.y, -centre.z) * scale_by)
		_no_shadows(model)
		holder.add_child(model)
		holder.set_meta(&"size", bounds.size * scale_by)
		return holder
	var box: BoxMesh = BoxMesh.new()
	box.size = fallback
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.position.y = fallback.y * 0.5
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(instance)
	holder.set_meta(&"size", fallback)
	return holder


## Bounds of every mesh under `node`, in the space `xform` leads to.
static func _bounds(node: Node, xform: Transform3D) -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	var here: Transform3D = xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		bounds = here * (node as MeshInstance3D).mesh.get_aabb()
		first = false
	for child: Node in node.get_children():
		var inner: AABB = _bounds(child, here)
		if inner.size == Vector3.ZERO:
			continue
		bounds = inner if first else bounds.merge(inner)
		first = false
	return bounds


func _no_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_no_shadows(child)


## The picture on a jumbotron: a dark screen across its upper half with the
## score on it, and "TOUCHDOWN!" in its place for a few seconds after one.
func _add_screen(board: Node3D) -> void:
	var size: Vector3 = board.get_meta(&"size")
	var width: float = size.x * SCREEN_RECT.size.x
	var height: float = size.y * SCREEN_RECT.size.y
	var front: float = size.z * 0.5 + 0.1
	var middle: float = size.y * SCREEN_RECT.position.y
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(width, height)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = SCREEN_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var screen: MeshInstance3D = MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = quad
	screen.material_override = material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.position = Vector3(0.0, middle, front)
	board.add_child(screen)

	var score: Label3D = _label("GAME DAY", 160, SCREEN_TEXT_COLOR)
	score.name = "Score"
	score.pixel_size = height * 0.42 / 160.0
	score.position = Vector3(0.0, middle, front + 0.05)
	board.add_child(score)
	_score_labels.append(score)
	var flash: Label3D = _label("TOUCHDOWN!", 160, Color.WHITE)
	flash.name = "Flash"
	flash.pixel_size = width * 0.9 / maxf(_font.get_string_size("TOUCHDOWN!", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 160).x, 1.0)
	flash.position = Vector3(0.0, middle, front + 0.05)
	flash.visible = false
	board.add_child(flash)
	_flash_labels.append(flash)


func _follow_score(delta: float) -> void:
	var now: Vector2i = Vector2i(_game.home.score, _game.away.score)
	if now != _scores:
		var first: bool = _scores.x < 0
		var gain: int = now.x + now.y - _scores.x - _scores.y
		_scores = now
		var text: String = "%s  %d
%s  %d" % [_names[0], now.x, _names[1], now.y]
		var size: Vector2 = _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 160)
		for label: Label3D in _score_labels:
			label.text = text
			# Never wider than the screen behind it.
			var screen: MeshInstance3D = label.get_parent().get_node(^"Screen") as MeshInstance3D
			var room: Vector2 = (screen.mesh as QuadMesh).size
			label.pixel_size = minf(room.y * 0.8 / maxf(size.y, 1.0), room.x * 0.86 / maxf(size.x, 1.0))
		if not first and gain >= _game.tuning.touchdown_points:
			_flash = FLASH_TIME
	if _flash > 0.0 or (not _flash_labels.is_empty() and _flash_labels[0].visible):
		_flash = maxf(_flash - delta, 0.0)
		var lit: bool = _flash > 0.0 and fmod(_flash, 0.5) > 0.2
		for i: int in _flash_labels.size():
			_flash_labels[i].visible = lit
			_score_labels[i].visible = not lit
