class_name Stadium
extends Node3D
## The bowl round the field: a wall, tiered stands with aisles, a crowd in the
## teams' colours, and the dressing (ad boards, jumbotrons, light towers, hot
## dog stand, tunnel mouths, facade, roof, press box). Built from Tuning by
## Field.setup(), so it follows the field's size, and it takes no part in the
## game: nothing here collides.
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
## The whole people the crowd is made of instead, where this file is there,
## with their picture, the mask of what is repainted in it (the top and the
## trousers) and their normal map (all four made by tools/prep_people.py).
const PEOPLE_SCENE: String = "res://assets/stadium/crowd_people.glb"
const PEOPLE_ATLAS: String = "res://assets/stadium/crowd_people_atlas.png"
const PEOPLE_MASK: String = "res://assets/stadium/crowd_people_mask.png"
const PEOPLE_NORMAL: String = "res://assets/stadium/crowd_people_normal.png"
## Share of the fans who hold a sign over their heads.
const SIGN_SHARE: float = 0.007
## Nobody holds a sign within this many seats of somebody else who does.
const SIGN_SPACING_SEATS: float = 8.0
## The levels of detail. A fan is a head, an outfit and legs at each of them
## (the same ones, so that nobody changes shirts as the camera comes closer),
## with fewer triangles the farther off.
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
## The fans' meshes are the size of the character they are made from. The
## players are 1.25 of that (the scale of Model in player.tscn); the fans are
## 0.7 of the players, or they look like giants behind a player at the wall.
## The seats and the rows below are sized to fit fans of this size.
const FAN_SCALE: float = 0.875
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
## Yards over which two levels of detail are both drawn where one gives way
## to the next, so that no fan is ever in neither.
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
## The wall stands Tuning.wall_gap past the lines, on all four sides. The
## corners are tight: any rounder and they would cut across the end zone corners.
const CORNER_RADIUS: float = 1.5
## A little taller than a player (1.95): nobody gets over it, and a ball has to
## be well up in the air to.
const WALL_HEIGHT: float = 2.3
const WALL_THICKNESS: float = 0.4
## Height of the first row's floor; each row is ROW_DEPTH deep and ROW_RISE higher.
const FIRST_ROW_HEIGHT: float = 1.7
const ROW_DEPTH: float = 1.05
const ROW_RISE: float = 0.525
## A fan's seat above the floor of its row, and the room each one gets.
const SEAT_HEIGHT: float = 0.336
const SEAT_PITCH: float = 0.84
## A fan sits this far back from the front of his row, as a share of its depth.
const SEAT_AT: float = 0.55
## The seat under him: how wide it is, how far it reaches to the front and to
## the back of where he sits, how thick it is, and the back it hangs from (how
## thick, and how high above the floor of the row). tools/prep_crowd.py seats
## the fans on y = 0 with their backs 0.4 yards behind their middles, at the
## players' size.
const SEAT_WIDTH: float = 0.644
const SEAT_FRONT: float = 0.154
const SEAT_BACK: float = 0.294
const SEAT_THICKNESS: float = 0.07
## The top of the seat is this far below where the fan sits: his thighs hang
## a little lower than that.
const SEAT_SINK: float = 0.063
const SEAT_REST_THICKNESS: float = 0.056
const SEAT_REST_HEIGHT: float = 0.735
const AISLE_WIDTH: float = 1.3
const BAY_SEATS: int = 13
## The walkway behind the top row, and the wall behind that.
const CONCOURSE_DEPTH: float = 4.0
const BACK_WALL_HEIGHT: float = 2.6
const BACK_WALL_THICKNESS: float = 0.6
const ARC_STEPS: int = 12
## What the stands, the seats, the rails and the ad boards are drawn with.
const STANDS_SHADER: Shader = preload("res://assets/stadium/stands.gdshader")
## What a surface is made of. It goes into the alpha of its vertices' colour
## (1 - 0.2 a step), where the shader reads it.
enum Finish { CONCRETE, PAD, METAL, PLASTIC, BOARD }
## The rails: how thick a tube is, how high the one on the wall and the one in
## front of the walkway stand, and the yards between their posts.
const RAIL_RADIUS: float = 0.035
const WALL_RAIL_HEIGHT: float = 0.42
const WALKWAY_RAIL_HEIGHT: float = 0.6
const RAIL_POST_GAP: float = 2.4
## The wall's cap reaches this far past its faces, and its kick plate is this high.
const CAP_OVERHANG: float = 0.04
const KICK_HEIGHT: float = 0.2
## The frame round an ad board: how wide its bars are and how far they stand
## off the board.
const BOARD_FRAME: float = 0.08
const BOARD_FRAME_DEPTH: float = 0.05
## The modelled pieces (tools/make_stadium_part.sh, tools/prep_prop.py): the
## mouth of a tunnel, one bay of the outside wall, one bay of the roof over
## the walkway and the press box. Without a file the piece is left out (a
## tunnel is then a plain block).
const TUNNEL_FILE: String = "tunnel.glb"
const FACADE_FILE: String = "facade_bay.glb"
const ROOF_FILE: String = "roof_bay.glb"
const PRESS_BOX_FILE: String = "press_box.glb"
const FACADE_SHADER: Shader = preload("res://assets/stadium/facade.gdshader")
## How far the facade stands out from the back wall, how far the roof reaches
## in over the walkway and how high it stands on it, and the bays either has
## round a corner.
const FACADE_DEPTH: float = 1.6
const ROOF_DEPTH: float = 4.4
const ROOF_HEIGHT: float = 4.6
const CORNER_BAYS: int = 4
## The share of the tunnel model's height that is the rail on its roof.
const TUNNEL_RAIL_SHARE: float = 0.07
## The press box is as wide as this many bays of the home stand.
const PRESS_BOX_BAYS: int = 2
## Tunnel mouths in the long stands: the rows they take up and half their width.
const TUNNEL_ROWS: Vector2i = Vector2i(4, 9)
const TUNNEL_HALF_WIDTH: float = 1.6

const CONCRETE: Color = Color(0.23, 0.24, 0.27)
const STEP_COLOR: Color = Color(0.37, 0.37, 0.39)
const SEAT_GREY: Color = Color(0.2, 0.21, 0.25)
const WALL_COLOR: Color = Color(0.09, 0.11, 0.19)
const WALL_CAP_COLOR: Color = Color(0.42, 0.43, 0.46)
const BACK_WALL_COLOR: Color = Color(0.15, 0.16, 0.2)
const TUNNEL_COLOR: Color = Color(0.02, 0.02, 0.03)
const RAIL_COLOR: Color = Color(0.62, 0.64, 0.68)
const KICK_COLOR: Color = Color(0.05, 0.05, 0.06)
const FRAME_COLOR: Color = Color(0.16, 0.17, 0.2)
const NOSING_COLOR: Color = Color(0.85, 0.7, 0.18)
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
## middle and its size. SCREEN_DEPTH is how far in front of the model's middle
## it is, as a share of the model's depth (the housing's rim, the lamps and the
## base stand further forward than the screen). All four are the SCREEN line
## tools/prep_prop.py prints for the model.
const SCREEN_RECT: Rect2 = Rect2(0.4989, 0.7138, 0.9289, 0.4774)
const SCREEN_DEPTH: float = 0.2046
## How far in front of the model's screen the picture is, in yards.
const SCREEN_LIFT: float = 0.06
## The screen with the main menu's title on it (show_title): lit, and the
## words outlined so the darker of them stands off it.
const TITLE_SCREEN_COLOR: Color = Color(0.04, 0.07, 0.17)
const TITLE_OUTLINE_COLOR: Color = Color(0.86, 0.93, 1.0)
const TITLE_FONT_SIZE: int = 160
## Shares of the screen's width and height the title's words may fill, and the
## subtitle's lines; and how far above and below the screen's middle they sit.
const TITLE_FIT: Vector2 = Vector2(0.84, 0.62)
const SUBTITLE_FIT: Vector2 = Vector2(0.84, 0.26)
const TITLE_RAISE: float = 0.13
const SUBTITLE_DROP: float = 0.31
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

	## The way the run goes at `s`.
	func along(s: float) -> Vector3:
		if not arc:
			return dir
		var angle: float = from_angle + s
		return Vector3(-sin(angle), 0.0, cos(angle))

	## Yards for one unit of `s`, `d` yards out.
	func reach(d: float) -> float:
		return CORNER_RADIUS + d if arc else 1.0


## The parts of the fans of one gender. Any head goes on any torso and any
## torso on any legs: tools/prep_crowd.py cut them to fit.
class Kit:
	var gender: String = ""
	## Per level of detail (near, mid, far), the meshes of each kind of part.
	var heads: Array = [[], [], []]
	var torsos: Array = [[], [], []]
	var legs: Array = [[], [], []]
	## Torsos with the arms up, for a fan with a sign.
	var sign_torsos: Array = [[], [], []]
	## A whole fan at the plainest level, and one with the arms up (not what
	## the stands draw: they draw the parts there too).
	var far: Mesh
	var far_sign: Mesh
	## Where the arms turn, and where the hands of a fan with a sign are.
	var shoulder: Vector3 = DEFAULT_SHOULDER
	var hand: Vector3 = DEFAULT_HAND
	var material: ShaderMaterial
	var sign_material: ShaderMaterial
	var sign_mesh: Mesh

	func complete() -> bool:
		for tier: int in 3:
			for parts: Array in [heads, torsos, legs, sign_torsos]:
				if (parts[tier] as Array).is_empty() or (parts[tier] as Array).size() != (parts[0] as Array).size():
					return false
		return far != null and far_sign != null


## One of the whole people of tools/crowd_people.json: a single mesh per level
## of detail, with its own place in the people's picture.
class Person:
	var id: String = ""
	var gender: String = ""
	## Per level of detail (near, mid, far): sitting with the arms down, and
	## with the arms up, for a fan with a sign.
	var meshes: Array[Mesh] = [null, null, null]
	var sign_meshes: Array[Mesh] = [null, null, null]
	## Where the arms turn, and where the hands are when they are up.
	var shoulder: Vector3 = DEFAULT_SHOULDER
	var hand: Vector3 = DEFAULT_HAND
	var material: ShaderMaterial
	var sign_material: ShaderMaterial
	var sign_mesh: Mesh

	func complete() -> bool:
		return not meshes.has(null) and not sign_meshes.has(null)


var tuning: Tuning
## Fans in the stands, and how many of them are for the home team in the
## parts given to the home team and to the visitors (the tests read these).
var fan_count: int = 0
## Where each one sits (headless Godot cannot read a MultiMesh back).
var fan_positions: PackedVector3Array = PackedVector3Array()
## Where the ones with a sign sit.
var sign_positions: PackedVector3Array = PackedVector3Array()
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
## The whole people, if PEOPLE_SCENE is there: then the crowd is made of them
## and the kits are not loaded.
var _people: Array[Person] = []
## Every material that moves with the crowd (fans and signs), and the board
## and the material of the sign of each kit, or of each person.
var _materials: Array[ShaderMaterial] = []
var _sign_meshes: Array[Mesh] = []
var _sign_materials: Array[ShaderMaterial] = []
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
## Half the outline's length and width, to the stand side of the wall.
var _half_x: float = 0.0
var _half_z: float = 0.0
var _font: Font
## The one material of everything built here in code (see STANDS_SHADER).
var _stands: ShaderMaterial
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
	sign_positions.clear()
	_score_labels.clear()
	_flash_labels.clear()
	_half_x = 0.0
	_half_z = 0.0
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
	_stands = ShaderMaterial.new()
	_stands.shader = STANDS_SHADER
	_stands.set_shader_parameter(&"mottle", Field.noise_texture(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 4, false))
	_stands.set_shader_parameter(&"grain", Field.noise_texture(FastNoiseLite.TYPE_SIMPLEX, 0.12, 3, false))

	_lay_out(left_is_home)
	_build_shell()
	_build_seats()
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
	if NetEvents.recording:
		NetEvents.tell(NetEvents.Part.STADIUM, &"react", [for_home, size])
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


## The main menu's title, on the screen of the jumbotron at the +X end in
## place of the score: `words` side by side in their `colors`, and `subtitle`
## (which may run over several lines) under them. The board stands `scale_by`
## times its size, so the title can be read from the field.
func show_title(words: PackedStringArray, colors: PackedColorArray, subtitle: String, scale_by: float) -> void:
	if props == null or words.is_empty():
		return
	var board: Node3D = props.get_node_or_null(^"Jumbotrons/Jumbotron0") as Node3D
	if board == null or board.has_node(^"Title"):
		return
	var size: Vector3 = board.get_meta(&"size")
	# Grown about the foot of its back, so its face stays where it was.
	board.position -= board.basis.z.normalized() * size.z * 0.5 * (scale_by - 1.0)
	board.scale = Vector3.ONE * scale_by
	(board.get_node(^"Score") as Label3D).visible = false
	(board.get_node(^"Flash") as Label3D).visible = false
	var screen: MeshInstance3D = board.get_node(^"Screen") as MeshInstance3D
	(screen.material_override as StandardMaterial3D).albedo_color = TITLE_SCREEN_COLOR
	var room: Vector2 = (screen.mesh as QuadMesh).size
	var front: float = screen.position.z + 0.05

	# The words in a row, as wide as the screen lets them be.
	var gap: float = float(TITLE_FONT_SIZE) * 0.22
	var widths: PackedFloat32Array = PackedFloat32Array()
	var total: float = gap * float(words.size() - 1)
	var tall: float = 1.0
	for word: String in words:
		var word_size: Vector2 = _font.get_string_size(word, HORIZONTAL_ALIGNMENT_CENTER, -1.0, TITLE_FONT_SIZE)
		widths.append(word_size.x)
		total += word_size.x
		tall = maxf(tall, word_size.y)
	var pixel: float = minf(room.x * TITLE_FIT.x / maxf(total, 1.0), room.y * TITLE_FIT.y / tall)
	var title: Node3D = Node3D.new()
	title.name = "Title"
	title.position = Vector3(0.0, screen.position.y + room.y * TITLE_RAISE, front)
	board.add_child(title)
	var at: float = -total * 0.5
	for i: int in words.size():
		var word: Label3D = _label(words[i], TITLE_FONT_SIZE, colors[i % colors.size()] if not colors.is_empty() else SCREEN_TEXT_COLOR)
		word.name = "Word%d" % i
		word.outline_size = TITLE_FONT_SIZE / 14
		word.outline_modulate = TITLE_OUTLINE_COLOR
		word.pixel_size = pixel
		word.position.x = (at + widths[i] * 0.5) * pixel
		title.add_child(word)
		at += widths[i] + gap

	if subtitle == "":
		return
	var line: Label3D = _label(subtitle, TITLE_FONT_SIZE, Color.WHITE)
	line.name = "Subtitle"
	var line_size: Vector2 = _font.get_multiline_string_size(subtitle, HORIZONTAL_ALIGNMENT_CENTER, -1.0, TITLE_FONT_SIZE)
	line.pixel_size = minf(room.x * SUBTITLE_FIT.x / maxf(line_size.x, 1.0), room.y * SUBTITLE_FIT.y / maxf(line_size.y, 1.0))
	line.position = Vector3(0.0, screen.position.y - room.y * SUBTITLE_DROP, front)
	board.add_child(line)


func rows() -> int:
	return maxi(tuning.stadium_rows, 1)


## Height of the walkway behind the top row.
func top_height() -> float:
	return FIRST_ROW_HEIGHT + float(rows()) * ROW_RISE


## Yards from the wall to the inside of the back wall.
func depth() -> float:
	return float(rows()) * ROW_DEPTH + CONCOURSE_DEPTH


## Yards from (x, z) to the face of the wall that looks onto the field: below 0
## on the field, above 0 in the wall or behind it. The wall is solid whether
## the stadium is drawn or not, so this goes by the Tuning alone.
static func wall_distance(p_tuning: Tuning, x: float, z: float) -> float:
	var corner: Vector2 = _from_corner(p_tuning, x, z)
	return Vector2(maxf(corner.x, 0.0), maxf(corner.y, 0.0)).length() + minf(maxf(corner.x, corner.y), 0.0) - CORNER_RADIUS + WALL_THICKNESS


## The way the wall nearest to (x, z) faces: a flat unit vector pointing from
## it onto the field. It turns with the wall round the corners.
static func wall_normal(p_tuning: Tuning, x: float, z: float) -> Vector3:
	var corner: Vector2 = _from_corner(p_tuning, x, z)
	var side_x: float = 1.0 if x >= p_tuning.field_length * 0.5 else -1.0
	var side_z: float = 1.0 if z >= 0.0 else -1.0
	if corner.x > 0.0 and corner.y > 0.0:
		return -Vector3(corner.x * side_x, 0.0, corner.y * side_z).normalized()
	if corner.x > corner.y:
		return Vector3(-side_x, 0.0, 0.0)
	return Vector3(0.0, 0.0, -side_z)


## `spot` if it is at least `margin` yards in from the face of the wall, else
## the nearest place that is.
static func keep_inside(p_tuning: Tuning, spot: Vector3, margin: float) -> Vector3:
	var over: float = wall_distance(p_tuning, spot.x, spot.z) + margin
	if over <= 0.0:
		return spot
	return spot + wall_normal(p_tuning, spot.x, spot.z) * over


## (x, z) folded into one quarter of the field and measured from the middle of
## that quarter's rounded corner: along the field, across it.
static func _from_corner(p_tuning: Tuning, x: float, z: float) -> Vector2:
	var half_x: float = p_tuning.field_length * 0.5 + p_tuning.end_zone_depth + p_tuning.wall_gap + WALL_THICKNESS
	var half_z: float = p_tuning.half_width() + p_tuning.wall_gap + WALL_THICKNESS
	return Vector2(absf(x - p_tuning.field_length * 0.5) - (half_x - CORNER_RADIUS), absf(z) - (half_z - CORNER_RADIUS))


## How high the ground is at (x, z): the turf inside the wall, the top of the
## wall, the floor of whichever row is there, the walkway, the back wall. What
## a ball that leaves the field comes down on.
func surface_height(x: float, z: float) -> float:
	if tuning == null or not tuning.stadium_enabled or _half_x <= 0.0:
		return 0.0
	# Yards out from the outline, as `d` in Run.point().
	var d: float = wall_distance(tuning, x, z) - WALL_THICKNESS
	if d < -WALL_THICKNESS:
		return 0.0
	if d < 0.0:
		return WALL_HEIGHT
	var seats: float = float(rows()) * ROW_DEPTH
	if d < seats:
		return FIRST_ROW_HEIGHT + floorf(d / ROW_DEPTH) * ROW_RISE
	if d < depth():
		return top_height()
	if d < depth() + BACK_WALL_THICKNESS:
		return top_height() + BACK_WALL_HEIGHT
	return 0.0


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
	for material: ShaderMaterial in _materials:
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
	var half_x: float = mid_x + tuning.end_zone_depth + tuning.wall_gap + WALL_THICKNESS
	var half_z: float = tuning.half_width() + tuning.wall_gap + WALL_THICKNESS
	_half_x = half_x
	_half_z = half_z
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
		var band_color: Color = _home_color.lerp(_away_color, 1.0 - run.home_chance).darkened(0.1)
		for slice: Array in run.slices:
			var s0: float = slice[0]
			var s1: float = slice[1]
			var aisle: bool = slice[2]
			# The wall: the padded face to the field with a kick plate at its
			# foot, the cap, the face to the stands.
			_strip(st, run, s0, s1, -WALL_THICKNESS, 0.0, -WALL_THICKNESS, WALL_HEIGHT, WALL_COLOR, -1.0, Finish.PAD)
			_slab(st, run, s0, s1, -WALL_THICKNESS - 0.03, -WALL_THICKNESS, 0.0, KICK_HEIGHT, KICK_COLOR, Finish.PLASTIC)
			_slab(st, run, s0, s1, -WALL_THICKNESS - CAP_OVERHANG, CAP_OVERHANG, WALL_HEIGHT - 0.1, WALL_HEIGHT + 0.03, WALL_CAP_COLOR, Finish.PLASTIC, true)
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
					# A painted edge on both steps.
					_strip(st, run, s0, s1, d0, half_h + 0.012, d0 + 0.09, half_h + 0.012, NOSING_COLOR, 0.0, Finish.PLASTIC, false)
					_strip(st, run, s0, s1, half_d, h + 0.012, half_d + 0.09, h + 0.012, NOSING_COLOR, 0.0, Finish.PLASTIC, false)
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
			_strip(st, run, s0, s1, back, wall_top, back + BACK_WALL_THICKNESS, wall_top, WALL_CAP_COLOR, 0.0, Finish.CONCRETE, false)
			_strip(st, run, s0, s1, back + BACK_WALL_THICKNESS, 0.0, back + BACK_WALL_THICKNESS, wall_top, BACK_WALL_COLOR.darkened(0.3), 1.0)
			# A band in the colour of this part's fans along the back wall, and
			# a pilaster behind every aisle.
			_slab(st, run, s0, s1, back - 0.06, back, wall_top - 0.95, wall_top - 0.4, band_color, Finish.PLASTIC, true)
			if aisle and not run.arc:
				var mid: float = (s0 + s1) * 0.5
				_slab(st, run, mid - 0.35, mid + 0.35, back - 0.2, back, top, wall_top, BACK_WALL_COLOR.lightened(0.12), Finish.CONCRETE, false, true)
				# A handrail up the middle of the steps, in short flights.
				for row: int in range(1, count - 1, 3):
					var foot: Vector3 = run.point(mid, float(row) * ROW_DEPTH + 0.3) + Vector3(0.0, FIRST_ROW_HEIGHT + float(row) * ROW_RISE, 0.0)
					var head: Vector3 = run.point(mid, float(row + 1) * ROW_DEPTH + 0.9) + Vector3(0.0, FIRST_ROW_HEIGHT + float(row + 1) * ROW_RISE, 0.0)
					var up: Vector3 = Vector3(0.0, 0.55, 0.0)
					_tube(st, foot - up * 0.6, foot + up, RAIL_RADIUS, RAIL_COLOR)
					_tube(st, head - up * 0.2, head + up, RAIL_RADIUS, RAIL_COLOR)
					_tube(st, foot + up, head + up, RAIL_RADIUS, RAIL_COLOR)
			elif not aisle:
				# A rail between the top row and the walkway, open at the aisles.
				_rail(st, run, s0, s1, d_top + 0.2, top, top + WALKWAY_RAIL_HEIGHT, RAIL_POST_GAP)
			if slice[3] and not ResourceLoader.exists(PROP_DIR + TUNNEL_FILE):
				_tunnel(st, run, (s0 + s1) * 0.5)
		# A rail on the wall, all the way round.
		_rail(st, run, 0.0, run.span(), -WALL_THICKNESS * 0.5, WALL_HEIGHT, WALL_HEIGHT + WALL_RAIL_HEIGHT, RAIL_POST_GAP)

	st.generate_tangents()
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "Stands"
	shell.mesh = st.commit()
	shell.material_override = _stands
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)


## Where the seats of one row of a run are: for each, the slice it is in (x)
## and how far along the run (y). The seats are built here and the fans sit
## here, so the two cannot come apart. None in the aisles or over a tunnel.
func _seat_spots(run: Run, row: int) -> PackedVector2Array:
	var spots: PackedVector2Array = PackedVector2Array()
	var d: float = (float(row) + SEAT_AT) * ROW_DEPTH
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
			spots.append(Vector2(float(slice_index), s))
	return spots


## A seat at every place a fan can sit, taken or not: a moulded shell on a
## leg, in the colour of that part of the crowd. One mesh, drawn once per seat
## (a MultiMesh for each piece of the stands); beyond crowd_lod_far a piece
## shows plain boxes instead.
func _build_seats() -> void:
	var seats: Node3D = Node3D.new()
	seats.name = "Seats"
	add_child(seats)
	var shapes: Array[Mesh] = [_seat_mesh(true), _seat_mesh(false)]
	var far: float = maxf(tuning.crowd_lod_far, 0.0)
	for index: int in runs.size():
		var run: Run = runs[index]
		var color: Color = SEAT_GREY.lerp(_home_color.lerp(_away_color, 1.0 - run.home_chance), 0.55)
		# Where the seats of each piece of the run stand.
		var pieces: Dictionary = {}
		for row: int in rows():
			var d: float = (float(row) + SEAT_AT) * ROW_DEPTH
			var floor_y: float = FIRST_ROW_HEIGHT + float(row) * ROW_RISE
			for spot: Vector2 in _seat_spots(run, row):
				var out: Vector3 = run.outward(spot.y)
				var piece: int = int(spot.x)
				if run.arc:
					piece = mini(int(spot.y / (PI * 0.5) * float(ARC_CHUNKS)), ARC_CHUNKS - 1)
				if not pieces.has(piece):
					pieces[piece] = []
				# The seat's own +Z is its back.
				(pieces[piece] as Array).append(Transform3D(Basis(Vector3(out.z, 0.0, -out.x), Vector3.UP, out), run.point(spot.y, d) + Vector3(0.0, floor_y, 0.0)))
		for piece: int in pieces:
			var places: Array = pieces[piece]
			var centre: Vector3 = Vector3.ZERO
			for place: Transform3D in places:
				centre += place.origin
			centre /= float(places.size())
			# The ranges are measured from here.
			var holder: Node3D = Node3D.new()
			holder.name = "Seats%d_%d" % [index, piece]
			holder.position = centre
			seats.add_child(holder)
			for level: int in shapes.size():
				var multimesh: MultiMesh = MultiMesh.new()
				multimesh.transform_format = MultiMesh.TRANSFORM_3D
				multimesh.use_colors = true
				multimesh.mesh = shapes[level]
				multimesh.instance_count = places.size()
				for i: int in places.size():
					var place: Transform3D = places[i]
					place.origin -= centre
					multimesh.set_instance_transform(i, place)
					multimesh.set_instance_color(i, color)
				var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
				instance.name = "Near" if level == 0 else "Far"
				instance.multimesh = multimesh
				instance.material_override = _stands
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# A straight swap with an overlap, as for the fans (_add_chunk).
				instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				if level == 0:
					instance.visibility_range_end = far + LOD_BLEND
				else:
					instance.visibility_range_begin = far
				holder.add_child(instance)


## One seat, standing on the floor of its row where the fan sits, its back
## toward +Z, in white (the MultiMesh gives it its colour). `moulded`: a
## curved shell on a leg, else the two boxes that stand for it from far off.
func _seat_mesh(moulded: bool) -> Mesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = SEAT_WIDTH * 0.5
	# Under the fan's thighs, which hang a little below where he sits.
	var top: float = SEAT_HEIGHT - SEAT_SINK
	if not moulded:
		_box(st, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, half, -SEAT_FRONT, SEAT_BACK, top - SEAT_THICKNESS, top, Color.WHITE, true)
		_box(st, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, half, SEAT_BACK, SEAT_BACK + SEAT_REST_THICKNESS, 0.0, SEAT_REST_HEIGHT, Color.WHITE.darkened(0.15), false)
		st.generate_tangents()
		return st.commit()
	# The shell from the side (z, y): a lip, the pan, the bend, the back. That
	# is the side the fan touches; the other is `thick` behind it.
	var line: PackedVector2Array = [
		Vector2(-SEAT_FRONT, top - 0.035), Vector2(-SEAT_FRONT + 0.035, top), Vector2(SEAT_BACK - 0.11, top - 0.012),
		Vector2(SEAT_BACK - 0.035, top + 0.03), Vector2(SEAT_BACK, top + 0.11),
		Vector2(SEAT_BACK + 0.035, SEAT_REST_HEIGHT - 0.07), Vector2(SEAT_BACK + 0.03, SEAT_REST_HEIGHT)]
	# The back is narrower toward its top.
	var widths: PackedFloat32Array = [1.0, 1.0, 1.0, 1.0, 1.0, 0.97, 0.86]
	var thick: float = 0.04
	var last: int = line.size() - 1
	var inner: Array = []
	var outer: Array = []
	var normals: Array[Vector3] = []
	var ways: Array[Vector3] = []
	for i: int in line.size():
		var way: Vector2 = (line[mini(i + 1, last)] - line[maxi(i - 1, 0)]).normalized()
		var normal: Vector3 = Vector3(0.0, way.x, -way.y)
		normals.append(normal)
		ways.append(Vector3(0.0, way.y, way.x))
		var pair: Array[Vector3] = []
		var behind: Array[Vector3] = []
		for side: float in [-1.0, 1.0]:
			var point: Vector3 = Vector3(side * half * widths[i], line[i].y, line[i].x)
			pair.append(point)
			behind.append(point - normal * thick)
		inner.append(pair)
		outer.append(behind)
	var shade: Color = Color.WHITE.darkened(0.25)
	for i: int in last:
		_soft_quad(st, [inner[i][0], inner[i][1], inner[i + 1][1], inner[i + 1][0]], [normals[i], normals[i], normals[i + 1], normals[i + 1]], Color.WHITE, Finish.PLASTIC)
		_soft_quad(st, [outer[i][0], outer[i][1], outer[i + 1][1], outer[i + 1][0]], [-normals[i], -normals[i], -normals[i + 1], -normals[i + 1]], shade, Finish.PLASTIC)
		for side: int in 2:
			_quad(st, inner[i][side], inner[i + 1][side], outer[i + 1][side], outer[i][side], Vector3.LEFT if side == 0 else Vector3.RIGHT, shade, Finish.PLASTIC)
	_quad(st, inner[0][0], inner[0][1], outer[0][1], outer[0][0], -ways[0], shade, Finish.PLASTIC)
	_quad(st, inner[last][0], inner[last][1], outer[last][1], outer[last][0], ways[last], Color.WHITE, Finish.PLASTIC)
	# The leg it stands on.
	_box(st, Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, 0.04, SEAT_BACK - 0.13, SEAT_BACK - 0.04, 0.0, top - thick, Color(0.3, 0.3, 0.32), false, Finish.METAL)
	st.generate_tangents()
	return st.commit()


## A box standing at `at`: `half` wide to either side along `along`, from d0
## to d1 along `out` (away from the field) and from y0 to y1. `under`: with
## its underside, for one that hangs in the air.
func _box(st: SurfaceTool, at: Vector3, along: Vector3, out: Vector3, half: float, d0: float, d1: float, y0: float, y1: float, color: Color, under: bool, finish: int = Finish.PLASTIC) -> void:
	var corners: Array[Vector3] = []
	for y: float in [y0, y1]:
		for d: float in [d0, d1]:
			for side: float in [-half, half]:
				corners.append(at + along * side + out * d + Vector3(0.0, y, 0.0))
	# 0-3 the bottom (front left, front right, back left, back right), 4-7 the top.
	_quad(st, corners[4], corners[5], corners[7], corners[6], Vector3.UP, color, finish)
	_quad(st, corners[0], corners[1], corners[5], corners[4], -out, color.darkened(0.2), finish)
	_quad(st, corners[2], corners[3], corners[7], corners[6], out, color.darkened(0.3), finish)
	_quad(st, corners[0], corners[2], corners[6], corners[4], -along, color.darkened(0.25), finish)
	_quad(st, corners[1], corners[3], corners[7], corners[5], along, color.darkened(0.25), finish)
	if under:
		_quad(st, corners[0], corners[1], corners[3], corners[2], Vector3.DOWN, color.darkened(0.4), finish)


## A strip along a slice of a run, between (d0, y0) and (d1, y1) in the run's
## cross-section. `facing`: 0 for a floor (normal up), -1 for a face turned to
## the field, +1 for one turned away from it. `shaded`: darker toward its foot
## (an upright face) or toward its back (a floor), where it meets the next
## surface.
func _strip(st: SurfaceTool, run: Run, s0: float, s1: float, d0: float, y0: float, d1: float, y1: float, color: Color, facing: float, finish: int = Finish.CONCRETE, shaded: bool = true) -> void:
	var up0: Vector3 = Vector3(0.0, y0, 0.0)
	var up1: Vector3 = Vector3(0.0, y1, 0.0)
	var mid: float = (s0 + s1) * 0.5
	var normal: Vector3 = Vector3.UP if facing == 0.0 else run.outward(mid) * facing
	# Yards along the run, and yards up (or back, on a floor).
	var reach: float = run.reach((d0 + d1) * 0.5)
	var v0: float = d0 if facing == 0.0 else y0
	var v1: float = d1 if facing == 0.0 else y1
	var uvs: PackedVector2Array = [Vector2(s0 * reach, v0), Vector2(s1 * reach, v0), Vector2(s1 * reach, v1), Vector2(s0 * reach, v1)]
	var corner: PackedFloat32Array = [0.0, 0.0, 1.0, 1.0] if facing == 0.0 else [1.0, 1.0, 0.0, 0.0]
	if not shaded:
		corner = [0.0, 0.0, 0.0, 0.0]
	_quad(st, run.point(s0, d0) + up0, run.point(s1, d0) + up0, run.point(s1, d1) + up1, run.point(s0, d1) + up1, normal, color, finish, uvs, corner)


## An upright face across a run at `s`, from d0 to d1 and y0 to y1, turned
## along the run (`toward` +1) or back along it (-1).
func _side(st: SurfaceTool, run: Run, s: float, d0: float, d1: float, y0: float, y1: float, color: Color, toward: float, finish: int = Finish.CONCRETE) -> void:
	var a: Vector3 = run.point(s, d0)
	var b: Vector3 = run.point(s, d1)
	var up0: Vector3 = Vector3(0.0, y0, 0.0)
	var up1: Vector3 = Vector3(0.0, y1, 0.0)
	_quad(st, a + up0, b + up0, b + up1, a + up1, run.along(s) * toward, color, finish)


## A solid bar along a slice of a run: from d0 (its face to the field) to d1
## and from y0 to y1. `under`: with its underside. `ends`: with its two ends,
## for one that does not carry on into the next slice.
func _slab(st: SurfaceTool, run: Run, s0: float, s1: float, d0: float, d1: float, y0: float, y1: float, color: Color, finish: int, under: bool = false, ends: bool = false) -> void:
	_strip(st, run, s0, s1, d0, y0, d0, y1, color.darkened(0.12), -1.0, finish, false)
	_strip(st, run, s0, s1, d1, y0, d1, y1, color.darkened(0.25), 1.0, finish, false)
	_strip(st, run, s0, s1, d0, y1, d1, y1, color, 0.0, finish, false)
	if under:
		var low: Vector3 = Vector3(0.0, y0, 0.0)
		_quad(st, run.point(s0, d0) + low, run.point(s1, d0) + low, run.point(s1, d1) + low, run.point(s0, d1) + low, Vector3.DOWN, color.darkened(0.4), finish)
	if ends:
		_side(st, run, s0, d0, d1, y0, y1, color.darkened(0.2), -1.0, finish)
		_side(st, run, s1, d0, d1, y0, y1, color.darkened(0.2), 1.0, finish)


## A round bar from `a` to `b`, six-sided and smooth, without ends.
func _tube(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, color: Color, finish: int = Finish.METAL) -> void:
	var axis: Vector3 = (b - a).normalized()
	var side: Vector3 = axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var other: Vector3 = axis.cross(side)
	var length: float = a.distance_to(b)
	var girth: float = radius * TAU / 6.0
	for i: int in 6:
		var n0: Vector3 = side * cos(float(i) * TAU / 6.0) + other * sin(float(i) * TAU / 6.0)
		var n1: Vector3 = side * cos(float(i + 1) * TAU / 6.0) + other * sin(float(i + 1) * TAU / 6.0)
		var uvs: PackedVector2Array = [Vector2(float(i) * girth, 0.0), Vector2(float(i + 1) * girth, 0.0), Vector2(float(i + 1) * girth, length), Vector2(float(i) * girth, length)]
		_soft_quad(st, [a + n0 * radius, a + n1 * radius, b + n1 * radius, b + n0 * radius], [n0, n1, n1, n0], color, finish, uvs)


## A rail along a run from s0 to s1, `d` yards out: posts from y0 to y1 about
## every `gap` yards, a bar along their tops and a thinner one half way up.
func _rail(st: SurfaceTool, run: Run, s0: float, s1: float, d: float, y0: float, y1: float, gap: float) -> void:
	var posts: int = maxi(roundi((s1 - s0) * run.reach(d) / gap), 1)
	# Round a corner the bars are cut finer than the posts stand, to follow it.
	var cuts: int = 1
	if run.arc:
		cuts = maxi(ceili(float(ARC_STEPS) * (s1 - s0) / (PI * 0.5) / float(posts)), 1)
	var step: float = (s1 - s0) / float(posts)
	for post: int in posts + 1:
		var s: float = s0 + step * float(post)
		var foot: Vector3 = run.point(s, d)
		_tube(st, foot + Vector3(0.0, y0, 0.0), foot + Vector3(0.0, y1, 0.0), RAIL_RADIUS, RAIL_COLOR)
		if post == posts:
			break
		for cut: int in cuts:
			var from: Vector3 = run.point(s + step * float(cut) / float(cuts), d)
			var to: Vector3 = run.point(s + step * float(cut + 1) / float(cuts), d)
			_tube(st, from + Vector3(0.0, y1, 0.0), to + Vector3(0.0, y1, 0.0), RAIL_RADIUS, RAIL_COLOR)
			_tube(st, from + Vector3(0.0, (y0 + y1) * 0.5, 0.0), to + Vector3(0.0, (y0 + y1) * 0.5, 0.0), RAIL_RADIUS * 0.7, RAIL_COLOR)


## A tunnel mouth: a block let into the rows with a dark opening to the field.
func _tunnel(st: SurfaceTool, run: Run, at: float) -> void:
	var s0: float = at - TUNNEL_HALF_WIDTH
	var s1: float = at + TUNNEL_HALF_WIDTH
	var d0: float = float(TUNNEL_ROWS.x) * ROW_DEPTH
	var d1: float = float(TUNNEL_ROWS.y) * ROW_DEPTH
	var floor_y: float = FIRST_ROW_HEIGHT + float(TUNNEL_ROWS.x - 1) * ROW_RISE
	var top_y: float = FIRST_ROW_HEIGHT + float(TUNNEL_ROWS.y) * ROW_RISE + 0.35
	_strip(st, run, s0, s1, d0, floor_y, d0, top_y, CONCRETE.darkened(0.25), -1.0)
	_strip(st, run, s0 + 0.25, s1 - 0.25, d0 - 0.01, floor_y, d0 - 0.01, top_y - 0.3, TUNNEL_COLOR, -1.0, Finish.CONCRETE, false)
	_strip(st, run, s0, s1, d0, top_y, d1, top_y, CONCRETE, 0.0, Finish.CONCRETE, false)
	_side(st, run, s0, d0, d1, floor_y, top_y, CONCRETE.darkened(0.2), -1.0)
	_side(st, run, s1, d0, d1, floor_y, top_y, CONCRETE.darkened(0.2), 1.0)


## Two triangles for the corners a, b, c, d (in order round the quad), wound so
## that the side `normal` points out of is the front. `uvs` and `corner` (how
## deep in a corner each is, 0..1) are per corner; without `uvs` the quad is
## laid out by its own size.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color, finish: int = Finish.CONCRETE, uvs: PackedVector2Array = PackedVector2Array(), corner: PackedFloat32Array = PackedFloat32Array()) -> void:
	_soft_quad(st, [a, b, c, d], [normal, normal, normal, normal], color, finish, uvs, corner)


## The same with a normal of its own at each corner, for a rounded surface.
func _soft_quad(st: SurfaceTool, points: Array, normals: Array, color: Color, finish: int, uvs: PackedVector2Array = PackedVector2Array(), corner: PackedFloat32Array = PackedFloat32Array()) -> void:
	var a: Vector3 = points[0]
	var b: Vector3 = points[1]
	var c: Vector3 = points[2]
	var facing: Vector3 = (normals[0] as Vector3) + (normals[1] as Vector3) + (normals[2] as Vector3) + (normals[3] as Vector3)
	var order: PackedInt32Array = [0, 1, 2, 0, 2, 3]
	# Godot's front faces are clockwise.
	if (b - a).cross(c - a).dot(facing) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	if uvs.is_empty():
		var wide: float = a.distance_to(b)
		uvs = [Vector2.ZERO, Vector2(wide, 0.0), Vector2(wide, b.distance_to(c)), Vector2(0.0, a.distance_to(points[3]))]
	var tint: Color = Color(color.r, color.g, color.b, 1.0 - float(finish) * 0.2)
	for i: int in order:
		st.set_color(tint)
		st.set_normal(normals[i])
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(corner[i] if not corner.is_empty() else 0.0, 0.0))
		st.add_vertex(points[i])


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
			var low: float = KICK_HEIGHT
			var high: float = WALL_HEIGHT - 0.15
			_strip(st, run, s0, s1, out, low, out, high, BOARD_COLORS[next % BOARD_COLORS.size()], -1.0, Finish.BOARD, false)
			# The frame round it.
			var front: float = out - BOARD_FRAME_DEPTH
			_slab(st, run, s0, s1, front, out, low, low + BOARD_FRAME, FRAME_COLOR, Finish.METAL, false, true)
			_slab(st, run, s0, s1, front, out, high - BOARD_FRAME, high, FRAME_COLOR, Finish.METAL, true, true)
			_slab(st, run, s0, s0 + BOARD_FRAME, front, out, low + BOARD_FRAME, high - BOARD_FRAME, FRAME_COLOR, Finish.METAL, false, true)
			_slab(st, run, s1 - BOARD_FRAME, s1, front, out, low + BOARD_FRAME, high - BOARD_FRAME, FRAME_COLOR, Finish.METAL, false, true)
			var text: String = BOARD_TEXTS[next % BOARD_TEXTS.size()]
			var label: Label3D = _label(text, 96, BOARD_TEXT_COLOR)
			# As big as fits the board, in height and in width.
			var size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 96)
			label.pixel_size = minf((WALL_HEIGHT - 0.75) / size.y, (s1 - s0 - 0.6) / size.x)
			label.position = run.point((s0 + s1) * 0.5, out - 0.03) + Vector3(0.0, WALL_HEIGHT * 0.5 + 0.02, 0.0)
			label.basis = _facing_field(run, (s0 + s1) * 0.5)
			boards.add_child(label)
			next += 1
	st.generate_tangents()
	var panels: MeshInstance3D = MeshInstance3D.new()
	panels.name = "Panels"
	panels.mesh = st.commit()
	panels.material_override = _stands
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
	_materials.clear()
	_sign_meshes.clear()
	_sign_materials.clear()
	_kits.clear()
	_people = _load_people()
	if _people.is_empty():
		_kits = _load_kits()
		if _kits.is_empty():
			push_warning("Stadium: %s is missing or out of date (run tools/prep_people.py), so the stands are empty." % PEOPLE_SCENE)
			return
	var hair: PackedColorArray = PackedColorArray(HAIR_COLORS)
	var pants: PackedColorArray = PackedColorArray(PANTS_COLORS)
	pants.append(_home_color)
	pants.append(_away_color)
	if not _people.is_empty():
		var picture: Texture2D = _kit_texture(PEOPLE_ATLAS)
		var paint: Texture2D = _kit_texture(PEOPLE_MASK)
		var bumps: Texture2D = _kit_texture(PEOPLE_NORMAL)
		for person: Person in _people:
			person.material = ShaderMaterial.new()
			person.material.shader = CROWD_SHADER
			person.material.set_shader_parameter(&"people", true)
			person.material.set_shader_parameter(&"dim", tuning.crowd_dim)
			person.material.set_shader_parameter(&"saturation", tuning.crowd_saturation)
			person.material.set_shader_parameter(&"shoulder", person.shoulder)
			person.material.set_shader_parameter(&"atlas_tex", picture)
			person.material.set_shader_parameter(&"mask_tex", paint)
			person.material.set_shader_parameter(&"normal_tex", bumps)
			person.material.set_shader_parameter(&"pants_colors", pants)
			person.sign_material = ShaderMaterial.new()
			person.sign_material.shader = SIGN_SHADER
			person.sign_material.set_shader_parameter(&"shoulder", person.shoulder)
			person.sign_material.set_shader_parameter(&"sign_grid", Vector2(SIGN_GRID))
			person.sign_mesh = _board_mesh(person.hand)
			for mesh: Mesh in person.meshes + person.sign_meshes:
				mesh.set_meta(&"material", person.material)
			_materials.append(person.material)
			_materials.append(person.sign_material)
			_sign_meshes.append(person.sign_mesh)
			_sign_materials.append(person.sign_material)
		_material = _people[0].material
		if tuning.crowd_person != "" and person_index(tuning.crowd_person) < 0:
			push_warning("Stadium: nobody in %s is '%s' (crowd_person), so the fans are people at random." % [PEOPLE_SCENE, tuning.crowd_person])
	var atlas: Texture2D = _kit_texture(KIT_ATLAS) if not _kits.is_empty() else null
	var mask: Texture2D = _kit_texture(KIT_MASK) if not _kits.is_empty() else null
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
		_materials.append(kit.material)
		_materials.append(kit.sign_material)
		_sign_meshes.append(kit.sign_mesh)
		_sign_materials.append(kit.sign_material)
	if not _kits.is_empty():
		_material = _kits[0].material
	if _people.is_empty() and tuning.crowd_head != "" and not _kits.any(func(kit: Kit) -> bool: return head_index(kit, tuning.crowd_head) >= 0):
		push_warning("Stadium: no head in %s is from the fan '%s' (crowd_head), so the fans get heads at random." % [KIT_SCENE, tuning.crowd_head])
	if _people.is_empty() and tuning.crowd_torso != "" and not _kits.any(func(kit: Kit) -> bool: return torso_index(kit, tuning.crowd_torso) >= 0):
		push_warning("Stadium: no outfit in %s is from the fan '%s' (crowd_torso), so the fans get outfits at random." % [KIT_SCENE, tuning.crowd_torso])
	if _people.is_empty() and tuning.crowd_legs != "" and not _kits.any(func(kit: Kit) -> bool: return legs_index(kit, tuning.crowd_legs) >= 0):
		push_warning("Stadium: no legs in %s are from the fan '%s' (crowd_legs), so the fans get legs at random." % [KIT_SCENE, tuning.crowd_legs])

	var mid_x: float = tuning.field_length * 0.5
	# Every fan with the piece of the stands it is in ([chunk, fan], in the
	# order of fan_positions), and the pieces by name ([name, chunk]).
	var seated: Array = []
	var records: Array = []
	for index: int in runs.size():
		var run: Run = runs[index]
		# Per chunk of the run (a bay, or a piece of a corner): what
		# _new_chunk() makes, filled by _seat().
		var chunks: Dictionary = {}
		for row: int in rows():
			var d: float = (float(row) + SEAT_AT) * ROW_DEPTH
			var y: float = FIRST_ROW_HEIGHT + float(row) * ROW_RISE + SEAT_HEIGHT
			for spot: Vector2 in _seat_spots(run, row):
				if _rng.randf() >= tuning.crowd_density:
					continue
				var s: float = spot.y
				var at: Vector3 = run.point(s, d) + Vector3(0.0, y, 0.0)
				var chunk: int = int(spot.x)
				if run.arc:
					chunk = mini(int(s / (PI * 0.5) * float(ARC_CHUNKS)), ARC_CHUNKS - 1)
				if not chunks.has(chunk):
					chunks[chunk] = _new_chunk()
					records.append(["Chunk%d_%d" % [index, chunk], chunks[chunk]])
				seated.append([chunks[chunk], _fan(run, s, at, mid_x)])
				fan_positions.append(at)
	# Who holds a sign is settled for the whole bowl at once, so that the
	# signs keep their distance across the pieces too; only then can each fan
	# be given its meshes.
	var holders: Dictionary = _pick_sign_holders()
	for index: int in seated.size():
		_seat(seated[index][0], seated[index][1], holders.has(index))
	for record: Array in records:
		_add_chunk(crowd, record[0], record[1])


## Which of the fans (by their place in fan_positions) hold a sign: SIGN_SHARE
## of them, picked at random, but nobody within SIGN_SPACING_SEATS seats of
## another who does. Fewer than that if they do not fit.
func _pick_sign_holders() -> Dictionary:
	var holders: Dictionary = {}
	var wanted: int = roundi(float(fan_positions.size()) * SIGN_SHARE)
	var apart: float = SIGN_SPACING_SEATS * SEAT_PITCH
	var tries: int = wanted * 30
	while holders.size() < wanted and tries > 0:
		tries -= 1
		var index: int = _rng.randi() % fan_positions.size()
		var at: Vector3 = fan_positions[index]
		var free: bool = true
		for taken: Vector3 in sign_positions:
			if taken.distance_to(at) < apart:
				free = false
				break
		if free:
			holders[index] = true
			sign_positions.append(at)
	return holders


## What is gathered for one piece of the stands before it is built: per level
## of detail the fans each mesh is drawn for (mesh -> list of fans), per kit
## (or per person) the fans with a sign, and all the fans. A fan is
## [transform, colour, custom].
func _new_chunk() -> Array:
	var signs: Array = []
	for mesh: Mesh in _sign_meshes:
		signs.append([])
	return [[{}, {}, {}], signs, []]


## Which of the people is `person_id` of tools/crowd_people.json, or -1.
func person_index(person_id: String) -> int:
	for index: int in _people.size():
		if _people[index].id == person_id:
			return index
	return -1


## Makes `fan` one of the people, a woman or a man by crowd_female_share, and
## enters it in `chunk` under that person's mesh at each level of detail.
func _seat_person(chunk: Array, fan: Array, holds_sign: bool) -> void:
	var wanted: String = "f" if _rng.randf() < tuning.crowd_female_share else "m"
	var of_gender: Array[int] = []
	for index: int in _people.size():
		if _people[index].gender == wanted:
			of_gender.append(index)
	# Drawn even when it is not used, so that the rest of the crowd is the
	# same whoever is in it.
	var roll: int = _rng.randi()
	var which: int = of_gender[roll % of_gender.size()] if not of_gender.is_empty() else roll % _people.size()
	var same: int = person_index(tuning.crowd_person)
	if same >= 0:
		which = same
	var person: Person = _people[which]
	for tier: int in 3:
		_enter(chunk[0][tier], person.sign_meshes[tier] if holds_sign else person.meshes[tier], fan)
	if holds_sign:
		(chunk[1][which] as Array).append(fan)
	(chunk[2] as Array).append(fan)


## Gives `fan` a gender, a head, an outfit and legs, and enters it in `chunk`
## under each of the meshes it is drawn with. All its parts get the same
## transform, colour and custom data, so they move as one; the shader takes
## from them what each part needs. `holds_sign`: with the arms up and a sign
## in them (see _pick_sign_holders).
func _seat(chunk: Array, fan: Array, holds_sign: bool) -> void:
	if not _people.is_empty():
		_seat_person(chunk, fan, holds_sign)
		return
	var which: int = 0
	if _kits.size() > 1 and _rng.randf() < tuning.crowd_female_share:
		which = 1
	var kit: Kit = _kits[which]
	# Drawn even when everybody gets the same head, so that the rest of the
	# crowd is the same with it and without.
	var head: int = _rng.randi() % (kit.heads[0] as Array).size()
	var same: int = head_index(kit, tuning.crowd_head)
	if same >= 0:
		head = same
	var torso: int = _rng.randi() % (kit.torsos[0] as Array).size()
	# Only the first outfit is worn with the arms up, unless everybody has
	# the same one.
	var sign_torso: int = 0
	same = torso_index(kit, tuning.crowd_torso)
	if same >= 0:
		torso = same
		sign_torso = same
	var legs: int = _rng.randi() % (kit.legs[0] as Array).size()
	same = legs_index(kit, tuning.crowd_legs)
	if same >= 0:
		legs = same
	var tiers: Array = chunk[0]
	for tier: int in 3:
		var parts: Array[Mesh] = [kit.heads[tier][head], kit.torsos[tier][torso], kit.legs[tier][legs]]
		if holds_sign:
			parts[1] = kit.sign_torsos[tier][sign_torso]
		for mesh: Mesh in parts:
			_enter(tiers[tier], mesh, fan)
	if holds_sign:
		(chunk[1][which] as Array).append(fan)
	(chunk[2] as Array).append(fan)


## Which of `kit`'s heads was cut from the fan `fan_id` of
## tools/crowd_parts.json, or -1 if none was (or `fan_id` is empty).
func head_index(kit: Kit, fan_id: String) -> int:
	return _part_index(kit.heads[0], fan_id)


## The same for `kit`'s outfits.
func torso_index(kit: Kit, fan_id: String) -> int:
	return _part_index(kit.torsos[0], fan_id)


## And for `kit`'s legs.
func legs_index(kit: Kit, fan_id: String) -> int:
	return _part_index(kit.legs[0], fan_id)


func _part_index(parts: Array, fan_id: String) -> int:
	if fan_id == "":
		return -1
	for index: int in parts.size():
		if String((parts[index] as Mesh).get_meta(&"fan", "")) == fan_id:
			return index
	return -1


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
			# A straight swap, not a fade, and no slack either: with a fade a
			# piece that sits at the swapping range for a camera that stands
			# still (the main menu) stays half faded, and with slack it can be
			# in neither level and not drawn at all. Instead the nearer level
			# is drawn LOD_BLEND yards into the next one's range, so that there
			# is no range at which a fan is in no level.
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if tier > 0:
				instance.visibility_range_begin = near if tier == 1 else far
			if tier < 2:
				instance.visibility_range_end = (near if tier == 0 else far) + LOD_BLEND
			chunk.add_child(instance)
	# The signs are one flat board each: no levels of detail.
	for which: int in _sign_meshes.size():
		var holders: Array = record[1][which]
		if holders.is_empty():
			continue
		var signs: MultiMeshInstance3D = _scatter(_sign_meshes[which], holders, centre, _sign_materials[which])
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
	if _sign_materials.is_empty() or DisplayServer.get_name() == "headless":
		return
	# A copy: the picture is made over a few frames, and the list is emptied
	# if the stadium is built again meanwhile.
	var materials: Array[ShaderMaterial] = _sign_materials.duplicate()
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


## The people in PEOPLE_SCENE, in the order of tools/crowd_people.json; only
## those with a mesh at every level of detail. tools/prep_people.py says what
## each mesh is in its "extras".
func _load_people() -> Array[Person]:
	var people: Array[Person] = []
	if not ResourceLoader.exists(PEOPLE_SCENE):
		return people
	var scene: Node = (load(PEOPLE_SCENE) as PackedScene).instantiate()
	var by_index: Dictionary = {}
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = node.get_meta(&"extras", {})
		if String(extras.get("kind", "")) != "person":
			continue
		var index: int = int(extras.get("index", 0))
		if not by_index.has(index):
			var made: Person = Person.new()
			made.id = String(extras.get("fan", ""))
			made.gender = String(extras.get("gender", "m"))
			by_index[index] = made
		var person: Person = by_index[index]
		var mesh: Mesh = (node as MeshInstance3D).mesh
		var tier: int = clampi(int(extras.get("tier", 0)), 0, 2)
		mesh.set_meta(&"kind", "person")
		mesh.set_meta(&"fan", person.id)
		if int(extras.get("sign", 0)) == 1:
			person.sign_meshes[tier] = mesh
			if tier == 0:
				person.hand = _kit_point(extras, "hand", person.hand)
		else:
			person.meshes[tier] = mesh
			if tier == 0:
				person.shoulder = _kit_point(extras, "shoulder", person.shoulder)
	scene.free()
	var keys: Array = by_index.keys()
	keys.sort()
	for key: int in keys:
		if (by_index[key] as Person).complete():
			people.append(by_index[key])
		else:
			push_warning("Stadium: '%s' in %s is not there at every level of detail; leaving it out." % [(by_index[key] as Person).id, PEOPLE_SCENE])
	return people


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
		mesh.set_meta(&"fan", String(extras.get("fan", "")))
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
		for tier: int in 3:
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

	# A mouth on every tunnel: let into the rows, its roof level with the row
	# behind it.
	if ResourceLoader.exists(PROP_DIR + TUNNEL_FILE):
		var tunnels: Node3D = Node3D.new()
		tunnels.name = "Tunnels"
		props.add_child(tunnels)
		var d0: float = float(TUNNEL_ROWS.x) * ROW_DEPTH
		var d1: float = float(TUNNEL_ROWS.y) * ROW_DEPTH
		var floor_y: float = FIRST_ROW_HEIGHT + float(TUNNEL_ROWS.x - 1) * ROW_RISE
		var block: float = FIRST_ROW_HEIGHT + float(TUNNEL_ROWS.y) * ROW_RISE + 0.1 - floor_y
		for index: int in runs.size():
			var run: Run = runs[index]
			for slice: Array in run.slices:
				if not slice[3]:
					continue
				var at: float = (float(slice[0]) + float(slice[1])) * 0.5
				var mouth: Node3D = _fitted("Tunnel%d_%d" % [index, tunnels.get_child_count()], TUNNEL_FILE, Vector3(TUNNEL_HALF_WIDTH * 2.0, block / (1.0 - TUNNEL_RAIL_SHARE), d1 - d0))
				mouth.transform = Transform3D(_facing_field(run, at), run.point(at, (d0 + d1) * 0.5) + Vector3(0.0, floor_y, 0.0))
				tunnels.add_child(mouth)

	# The press box stands on the walkway at the top of the home stand, at
	# midfield, in a gap in the roof.
	var gap: Vector2 = Vector2.ZERO
	if ResourceLoader.exists(PROP_DIR + PRESS_BOX_FILE):
		var wide: float = home_stand.length / float(_bays(home_stand)) * float(PRESS_BOX_BAYS)
		var box: Node3D = _prop("PressBox", PRESS_BOX_FILE, 1.0, Vector3.ONE, Color.BLACK)
		var size: Vector3 = box.get_meta(&"size")
		var grow: float = wide / maxf(size.x, 0.001)
		box.set_meta(&"size", size * grow)
		var mid: float = home_stand.length * 0.5
		box.transform = Transform3D(_facing_field(home_stand, mid).scaled(Vector3.ONE * grow), home_stand.point(mid, depth() - size.z * grow * 0.5) + Vector3(0.0, top, 0.0))
		props.add_child(box)
		gap = Vector2(mid - wide * 0.5, mid + wide * 0.5)

	# The outside wall, bay by bay, each with a banner in the colour of the
	# fans behind it; and the roof over the walkway.
	_build_ring("Facade", FACADE_FILE, 1.0, back, 0.0, Vector3(0.0, top + BACK_WALL_HEIGHT, FACADE_DEPTH), true, Vector2.ZERO)
	_build_ring("Roof", ROOF_FILE, -1.0, depth(), top, Vector3(0.0, ROOF_HEIGHT, ROOF_DEPTH), false, gap)

	# Where the commentary booth would go: top of the home stand, at midfield.
	booth_anchor = Marker3D.new()
	booth_anchor.name = "BoothAnchor"
	booth_anchor.transform = Transform3D(_facing_field(home_stand, home_stand.length * 0.5), home_stand.point(home_stand.length * 0.5, depth()) + Vector3(0.0, top + BACK_WALL_HEIGHT, 0.0))
	props.add_child(booth_anchor)


## The model of the mascot of the team with this short name (the banana for a
## team without one), as it stands and runs on the field:
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


## A model from assets/stadium stretched to exactly `size` (wide, high, deep),
## standing on its origin with the middle of its footprint there, facing +Z.
func _fitted(node_name: String, file: String, size: Vector3) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	var model: Node3D = (load(PROP_DIR + file) as PackedScene).instantiate() as Node3D
	var bounds: AABB = _bounds(model, Transform3D.IDENTITY)
	var scale_by: Vector3 = size / Vector3(maxf(bounds.size.x, 0.001), maxf(bounds.size.y, 0.001), maxf(bounds.size.z, 0.001))
	var centre: Vector3 = bounds.get_center()
	model.transform = Transform3D(Basis.from_scale(scale_by), Vector3(-centre.x, -bounds.position.y, -centre.z) * scale_by)
	_no_shadows(model)
	holder.add_child(model)
	holder.set_meta(&"size", size)
	return holder


## How many bays (stretches of seats between two aisles) a straight has.
func _bays(run: Run) -> int:
	var bays: int = 0
	for slice: Array in run.slices:
		if not slice[2]:
			bays += 1
	return maxi(bays, 1)


## Every mesh under `node` with the transform that leads to it: [mesh, xform].
func _meshes(node: Node, xform: Transform3D, found: Array) -> void:
	var here: Transform3D = xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append([(node as MeshInstance3D).mesh, here])
	for child: Node in node.get_children():
		_meshes(child, here, found)


## One model repeated all the way round the bowl, a bay at a time: as wide as
## a bay of each straight, and bent round the corners, CORNER_BAYS to each.
## Its back stands `d_back` yards out from the wall at the height `y0`, and it
## reaches `size.z` further out (`face` +1, its front turned away from the
## field) or back in (`face` -1, its front turned to the field); `size.y` is
## its height. `tinted`: its white parts take the colour of the fans of that
## part of the bowl. No bay stands in `gap` (from, to) of the home stand.
func _build_ring(node_name: String, file: String, face: float, d_back: float, y0: float, size: Vector3, tinted: bool, gap: Vector2) -> void:
	if not ResourceLoader.exists(PROP_DIR + file):
		return
	var model: Node3D = (load(PROP_DIR + file) as PackedScene).instantiate() as Node3D
	var found: Array = []
	_meshes(model, Transform3D.IDENTITY, found)
	var bounds: AABB = _bounds(model, Transform3D.IDENTITY)
	model.free()
	if found.is_empty():
		return
	var ring: Node3D = Node3D.new()
	ring.name = node_name
	props.add_child(ring)
	# Into a box one unit wide and deep about its middle, and one high from 0.
	var unit: Transform3D = Transform3D(Basis.from_scale(Vector3.ONE / Vector3(maxf(bounds.size.x, 0.001), maxf(bounds.size.y, 0.001), maxf(bounds.size.z, 0.001))), Vector3.ZERO)
	unit = unit * Transform3D(Basis.IDENTITY, -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z))
	var materials: Dictionary = {}
	# The bays of a corner, bent once and turned to each of the four.
	var bent: Array = []
	for bay: int in CORNER_BAYS:
		var pieces: Array = []
		for entry: Array in found:
			pieces.append(_bent(entry[0], unit * (entry[1] as Transform3D), face, CORNER_RADIUS + d_back, size, PI * 0.5 * float(bay) / float(CORNER_BAYS), PI * 0.5 * float(bay + 1) / float(CORNER_BAYS)))
		bent.append(pieces)
	for index: int in runs.size():
		var run: Run = runs[index]
		var tint: Color = _home_color.lerp(_away_color, 1.0 - run.home_chance)
		var bays: int = CORNER_BAYS if run.arc else _bays(run)
		for bay: int in bays:
			if not run.arc and index == 6 and (float(bay) + 0.5) * run.length / float(bays) > gap.x and (float(bay) + 0.5) * run.length / float(bays) < gap.y:
				continue
			var holder: Node3D = Node3D.new()
			holder.name = "%s%d_%d" % [node_name, index, bay]
			var meshes: Array = []
			if run.arc:
				holder.transform = Transform3D(Basis(Vector3.UP, -run.from_angle), run.centre + Vector3(0.0, y0, 0.0))
				for mesh: Mesh in bent[bay]:
					meshes.append([mesh, Transform3D.IDENTITY])
			else:
				var wide: float = run.length / float(bays)
				var mid: float = (float(bay) + 0.5) * wide
				var basis: Basis = Basis(run.dir * -face, Vector3.UP, run.normal * face)
				holder.transform = Transform3D(basis, run.point(mid, d_back + face * size.z * 0.5) + Vector3(0.0, y0, 0.0))
				var fit: Transform3D = Transform3D(Basis.from_scale(Vector3(wide, size.y, size.z)), Vector3.ZERO) * unit
				for entry: Array in found:
					meshes.append([entry[0], fit * (entry[1] as Transform3D)])
			for entry: Array in meshes:
				var instance: MeshInstance3D = MeshInstance3D.new()
				instance.mesh = entry[0]
				instance.transform = entry[1]
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if tinted:
					for surface: int in instance.mesh.get_surface_count():
						instance.set_surface_override_material(surface, _tinted(instance.mesh.surface_get_material(surface), materials))
					instance.set_instance_shader_parameter(&"tint", tint)
				holder.add_child(instance)
			ring.add_child(holder)


## `mesh` (brought into the unit box by `xform`) as one bay of a corner: bent
## about the corner's middle from the angle `from` to `to`, its back at
## `radius`, `size.z` deep and `size.y` high. See _build_ring for `face`.
func _bent(mesh: Mesh, xform: Transform3D, face: float, radius: float, size: Vector3, from: float, to: float) -> Mesh:
	var out: ArrayMesh = ArrayMesh.new()
	var normal_xform: Basis = xform.basis.inverse().transposed()
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		for i: int in points.size():
			var p: Vector3 = xform * points[i]
			var angle: float = (from + to) * 0.5 - face * p.x * (to - from)
			var away: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
			# The model's own +X and +Z, where this point ends up.
			var x_axis: Vector3 = Vector3(-sin(angle), 0.0, cos(angle)) * -face
			var z_axis: Vector3 = away * face
			points[i] = away * (radius + face * (p.z + 0.5) * size.z) + Vector3(0.0, p.y * size.y, 0.0)
			if i < normals.size():
				var n: Vector3 = (normal_xform * normals[i]) / Vector3(radius * (to - from), size.y, size.z)
				normals[i] = (x_axis * n.x + Vector3.UP * n.y + z_axis * n.z).normalized()
			if i * 4 + 3 < tangents.size():
				var t: Vector3 = xform.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2]) * Vector3(radius * (to - from), size.y, size.z)
				t = (x_axis * t.x + Vector3.UP * t.y + z_axis * t.z).normalized()
				tangents[i * 4] = t.x
				tangents[i * 4 + 1] = t.y
				tangents[i * 4 + 2] = t.z
		arrays[Mesh.ARRAY_VERTEX] = points
		if not normals.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = normals
		if not tangents.is_empty():
			arrays[Mesh.ARRAY_TANGENT] = tangents
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(surface, mesh.surface_get_material(surface))
	return out


## A material that shows `source`'s pictures and dyes what is white in them
## with each instance's own `tint` (see FACADE_SHADER); one per source, kept
## in `made`.
func _tinted(source: Material, made: Dictionary) -> Material:
	if made.has(source):
		return made[source]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = FACADE_SHADER
	var plain: BaseMaterial3D = source as BaseMaterial3D
	if plain != null:
		material.set_shader_parameter(&"albedo_tex", plain.albedo_texture)
		material.set_shader_parameter(&"normal_tex", plain.normal_texture)
		if plain.roughness_texture != null:
			material.set_shader_parameter(&"orm_tex", plain.roughness_texture)
			material.set_shader_parameter(&"has_orm", true)
	made[source] = material
	return material


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
	var front: float = size.z * SCREEN_DEPTH + SCREEN_LIFT
	var middle: float = size.y * SCREEN_RECT.position.y
	var across: float = size.x * (SCREEN_RECT.position.x - 0.5)
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
	screen.position = Vector3(across, middle, front)
	board.add_child(screen)

	var score: Label3D = _label("GAME DAY", 160, SCREEN_TEXT_COLOR)
	score.name = "Score"
	score.pixel_size = height * 0.42 / 160.0
	score.position = Vector3(across, middle, front + 0.05)
	board.add_child(score)
	_score_labels.append(score)
	var flash: Label3D = _label("TOUCHDOWN!", 160, Color.WHITE)
	flash.name = "Flash"
	flash.pixel_size = width * 0.9 / maxf(_font.get_string_size("TOUCHDOWN!", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 160).x, 1.0)
	flash.position = Vector3(across, middle, front + 0.05)
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
