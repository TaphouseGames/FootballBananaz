extends Node3D
## Developer tool, not part of the game: paint by hand which parts of a player
## are his kit. Run tools/kit_painter.tscn by itself (F6), or
## tools\kit_painter.bat.
##
## A player who is a whole character (PlayerParts.PEOPLE) is dressed through a
## mask: a picture that says which texels of the model are jersey (red), pants
## (green) and socks (blue), and where the jersey has its second colour (red
## and blue: the sleeves and the collar of the home kit, which the Trim brush
## paints; on the away kit it looks like the rest). kit_person.gdshader gives those the team's
## colours and leaves the rest as the model was painted. tools/prep_player.py
## works that mask out from the model's colours, which is close but not always
## right: a collar that takes in some of the neck, a waistband that came out
## as jersey. Here the mask is brushed straight onto the model, and the player
## is shown in the away kit, the home kit or as the regions themselves while
## it is done.
##
## The colour texture the game has is not the one the model came with:
## prep_player.py keeps only the shading (grey) of what its mask called kit.
## So the texture is worked out again here from the one the model came with
## (assets/player/source/people/<id>_colour.jpg, which prep_player.py saves,
## or <id>_colour_paint.png beside it if the texture was painted by hand in a
## texture painter: see `obj` in prep_player.py):
## where the kit is taken away the model shows as it was made, and what is
## made kit becomes its shading. Where the model itself is painted wrongly (a
## white sleeve that runs on down the arm) the Skin brush paints skin over
## it: the player's skin colour (that of the hands, or picked off the model
## with Alt and a click), as light and dark as what was there. Erase takes
## that away again with the kit.
##
## Saving writes, for a player:
##   assets/player/people/<id>_mask.png              the mask the game loads
##   assets/player/people/<id>_<id>_colour.jpg       the colour texture the
##                                                   game loads
##   assets/player/source/people/<id>_mask_paint.png what tools/prep_player.py
##                                                   takes instead of its own
##                                                   mask from then on
##   assets/player/source/people/<id>_skin_paint.png the skin that was painted
##                                                   (none: no file), which
##                                                   prep_player.py puts on too
## The game shows what was saved once the editor has imported it again (it
## does when its window is clicked on). prep_player.py need not be run after.
## A player without his <id>_colour.jpg can have his mask painted and no
## more: `prep_player.py -- only=<id> textures=1` makes the file.
##
## The brush is a ball on the model where the mouse points: it paints what is
## inside it and faces the same way as the spot pointed at, so the far side of
## an arm is not painted through. The keys are listed on the screen (KEYS).
##
## From a command line: `-- player=<id>` opens on that player.

const KEYS: String = """Left mouse     paint
Right mouse    turn
Middle mouse   move
Wheel          zoom
F              whole player
1 2 3 4 5      jersey, pants, socks, erase, skin
6              trim: the jersey's second colour
Alt+click      pick the skin colour
[  ]           smaller / bigger brush
Ctrl+wheel     the same
M              mirror left and right
Tab            next view
,  .           previous / next player
Ctrl+Z  Ctrl+Y undo / redo
Ctrl+S         save"""

const TEAMS_DIR: String = "res://resources/teams"
const PAINT_DIR: String = "res://assets/player/source/people"
## What a region is called, what the mask says where it is, and how it is
## shown in the view of the regions. ERASE takes the kit and painted skin
## away, SKIN the kit and paints skin into the texture. TRIM is jersey in its
## second colour: the team's on the home kit, where the rest is white.
const REGION_NAMES: PackedStringArray = ["Jersey", "Pants", "Socks", "Erase", "Skin", "Trim"]
const REGION_BYTES: Array[Color] = [Color(1.0, 0.0, 0.0), Color(0.0, 1.0, 0.0), Color(0.0, 0.0, 1.0), Color(0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0), Color(1.0, 0.0, 1.0)]
const REGION_TINTS: Array[Color] = [Color(0.95, 0.3, 0.25), Color(0.3, 0.85, 0.35), Color(0.3, 0.5, 1.0), Color(0.75, 0.75, 0.75), Color(0.95, 0.72, 0.58), Color(1.0, 0.75, 0.15)]
const ERASE: int = 3
const SKIN: int = 4
const TRIM: int = 5
## What is kit is kept in the colour texture as its shading: how light it is
## beside the middle of its garment, which comes out as this (as in
## prep_player.py).
const KIT_TONE: float = 0.8
## How much darker and lighter than the skin colour painted skin may be.
const SKIN_SHADE: Vector2 = Vector2(0.55, 1.3)
## How far up the colours of the hands, from darkest to lightest, the skin
## colour is taken.
const SKIN_PICK: float = 0.75
const SKIN_USUAL: Color = Color(0.85, 0.65, 0.55)
const JPG_QUALITY: float = 0.92
const NO_TEXTURE: String = "Only his mask can be painted: the texture he came with is not there. Make it with\nprep_player.py -- only=%s textures=1"
const VIEW_NAMES: PackedStringArray = ["Away kit", "Home kit", "Regions", "As painted"]
enum View { AWAY, HOME, REGIONS, PLAIN }
## The side of a box of the grid the triangles are sorted into, in the model's
## own units (a player is about one unit tall).
const CELL: float = 0.03
## How far past the edge of a triangle in the texture a texel is still painted
## with it, in texels: without it the seams of the texture show as lines.
const PAD: float = 2.5
## A triangle is painted if it faces within this of the way the spot pointed
## at does (the cosine of the angle between them).
const FACING: float = -0.2
## The brush's size, in the model's units: smallest, biggest, to start with.
const BRUSH_LIMITS: Vector2 = Vector2(0.003, 0.12)
const BRUSH_START: float = 0.02
const UNDO_STEPS: int = 25
const ORBIT_PER_PIXEL: float = 0.008
const BACK_COLOR: Color = Color(0.3, 0.32, 0.36)
const PANEL_WIDTH: float = 250.0

const REGIONS_SHADER: String = """shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D mask_tex : hint_default_black, filter_nearest;
uniform vec3 jersey : source_color;
uniform vec3 pants : source_color;
uniform vec3 socks : source_color;
uniform vec3 trim : source_color;
void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 mask = texture(mask_tex, UV).rgb;
	float second = min(mask.r, mask.b);
	float sum = mask.r + mask.g + mask.b - second;
	vec3 tint = (jersey * (mask.r - second) + trim * second + pants * mask.g + socks * (mask.b - second)) / max(sum, 0.001);
	float shade = 0.55 + 0.6 * dot(base, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(base, tint * shade, clamp(sum, 0.0, 1.0) * 0.85);
	ROUGHNESS = 0.9;
}
"""


## One player's model and mask, made ready to be painted on.
class Sheet:
	var id: String
	var width: int
	var height: int
	## The mask: three bytes a texel, rows from the top.
	var data: PackedByteArray
	var unsaved: bool = false
	## What undo and redo go back to: {mask, shown, skin (empty if unchanged)}.
	var undo: Array[Dictionary] = []
	var redo: Array[Dictionary] = []
	var mesh: ArrayMesh
	var albedo: Texture2D
	## The file the game has its colour texture from.
	var colour_path: String
	## The colour texture as the model came with it, three bytes a texel:
	## empty if its file is missing, and then only the mask is painted.
	var original: PackedByteArray
	## The skin painted over it, four bytes a texel: the last is 0 where none is.
	var skin: PackedByteArray
	## The colour texture as the game gets it: the two above, and only the
	## shading of them where the mask says kit.
	var shown: PackedByteArray
	## Per garment: how light its middle is, 0 to 255.
	var keys: PackedFloat32Array = PackedFloat32Array([153.0, 153.0, 153.0])
	## The colour the Skin brush paints.
	var tone: Color = SKIN_USUAL
	var tall: float
	## Per corner of the mesh: where it is, and where in the mask (in texels).
	var points: PackedVector3Array
	var texels: PackedVector2Array
	var index: PackedInt32Array
	## Per triangle: the way it faces.
	var normals: PackedVector3Array
	## The triangles that reach into each box of the grid.
	var grid: Dictionary[Vector3i, Array] = {}
	## 1 where a texel lies inside some triangle.
	var cover: PackedByteArray
	## Per triangle: 1 if one of its edges is an edge of its piece of the
	## texture, where the paint has to go on past it (see PAD).
	var seam: PackedByteArray
	var low: Vector3
	var high: Vector3


var _teams: Array[Dictionary] = []
var _team: int = 0
var _player: int = 0
var _sheets: Dictionary[String, Sheet] = {}
var _sheet: Sheet

var _region: int = 0
var _brush: float = BRUSH_START
var _mirror: bool = false
var _view: int = View.AWAY

var _camera: Camera3D
var _body: MeshInstance3D
## Dresses the player: only its material is used (see _show_player()).
var _dresser: PlayerModel
var _regions_material: ShaderMaterial
var _image: Image
var _texture: ImageTexture
var _texture_stale: bool = false
## The colour texture as it is being painted (Sheet.shown), if the player has one.
var _albedo_image: Image
var _albedo_texture: ImageTexture
var _albedo_stale: bool = false
var _rings: Array[MeshInstance3D] = []
var _ring_material: StandardMaterial3D

var _yaw: float = 0.0
var _pitch: float = 0.05
var _distance: float = 3.0
var _aim: Vector3 = Vector3.ZERO

var _painting: bool = false
var _stroke_changed: bool = false
var _last_px: Vector2 = Vector2.ZERO
## Where the mouse points on the model, if it does.
var _on_model: bool = false
var _hit_at: Vector3 = Vector3.ZERO
var _hit_normal: Vector3 = Vector3.UP
var _hit_triangle: int = -1
## How light the texture is where a stroke of skin began, 0 to 255: what is
## painted is as much lighter or darker than the skin colour as it is than this.
var _stroke_ref: float = 128.0

var _team_pick: OptionButton
var _player_list: ItemList
var _region_buttons: Array[Button] = []
var _size_slider: HSlider
var _mirror_box: CheckBox
var _view_pick: OptionButton
var _tone_swatch: ColorRect
var _status: Label
var _quit_dialog: ConfirmationDialog


func _ready() -> void:
	get_tree().auto_accept_quit = false
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	add_child(sun)
	var sky: Environment = Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = BACK_COLOR
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color.WHITE
	sky.ambient_light_energy = 0.6
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = sky
	add_child(world)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	_camera.near = 0.01
	add_child(_camera)
	_camera.make_current()
	# The sun comes from where the camera is, so what is painted is never in the dark.
	sun.reparent(_camera)
	sun.rotation_degrees = Vector3(-15.0, 20.0, 0.0)

	_body = MeshInstance3D.new()
	add_child(_body)
	_dresser = PlayerModel.new()
	_dresser.visible = false
	add_child(_dresser)
	var shader: Shader = Shader.new()
	shader.code = REGIONS_SHADER
	_regions_material = ShaderMaterial.new()
	_regions_material.shader = shader
	_regions_material.set_shader_parameter(&"jersey", REGION_TINTS[0])
	_regions_material.set_shader_parameter(&"pants", REGION_TINTS[1])
	_regions_material.set_shader_parameter(&"socks", REGION_TINTS[2])
	_regions_material.set_shader_parameter(&"trim", REGION_TINTS[TRIM])

	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.no_depth_test = true
	_ring_material.render_priority = 10
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	for i: int in 2:
		var ring: MeshInstance3D = MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.material_override = _ring_material
		ring.visible = false
		add_child(ring)
		_rings.append(ring)

	_collect()
	_build_panel()
	if _teams.is_empty():
		_status.text = "No player models found (PlayerParts.PEOPLE)."
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("player="):
			_find_player(arg.trim_prefix("player="))
	_fill_teams()
	_show_player()


## The teams and their players who are whole characters with a model and a
## mask: [{name, color, players: [{id, name, number, look}]}]. Characters no
## roster has come last, as a team of their own.
func _collect() -> void:
	var listed: Dictionary[String, bool] = {}
	var files: PackedStringArray = DirAccess.get_files_at(TEAMS_DIR)
	files.sort()
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var team: TeamData = load(TEAMS_DIR.path_join(file)) as TeamData
		if team == null or team.roster == null:
			continue
		var players: Array[Dictionary] = []
		for ratings: PlayerRatings in team.roster.players:
			if ratings.look == null or ratings.look.person_id() == "" or not _has_files(ratings.look.person):
				continue
			players.append({"id": ratings.look.person, "name": ratings.display_name, "number": ratings.number, "look": ratings.look})
			listed[ratings.look.person] = true
		if not players.is_empty():
			_teams.append({"name": team.team_name, "color": team.team_color, "players": players})
	var others: Array[Dictionary] = []
	for id: String in PlayerParts.PEOPLE:
		if listed.has(id) or not _has_files(id):
			continue
		var look: PlayerLook = PlayerLook.new()
		look.person = id
		others.append({"id": id, "name": PlayerParts.PEOPLE[id]["name"], "number": 1, "look": look})
	if not others.is_empty():
		_teams.append({"name": "On no team", "color": Color(0.1, 0.3, 0.8), "players": others})


func _has_files(id: String) -> bool:
	var who: Dictionary = PlayerParts.PEOPLE[id]
	return ResourceLoader.exists(who["path"]) and FileAccess.file_exists(who["mask"])


func _find_player(id: String) -> void:
	for t: int in _teams.size():
		var players: Array[Dictionary] = _teams[t]["players"]
		for p: int in players.size():
			if players[p]["id"] == id:
				_team = t
				_player = p
				return
	push_warning("kit painter: no player '%s'" % id)


# --- The panel -------------------------------------------------------------

func _build_panel() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = PANEL_WIDTH
	layer.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	margin.add_child(column)

	_team_pick = OptionButton.new()
	_team_pick.focus_mode = Control.FOCUS_NONE
	_team_pick.item_selected.connect(_on_team_picked)
	column.add_child(_team_pick)
	_player_list = ItemList.new()
	_player_list.focus_mode = Control.FOCUS_NONE
	_player_list.custom_minimum_size.y = 130.0
	_player_list.item_selected.connect(_on_player_picked)
	column.add_child(_player_list)

	column.add_child(_heading("Paint"))
	var regions: GridContainer = GridContainer.new()
	regions.columns = 2
	column.add_child(regions)
	var group: ButtonGroup = ButtonGroup.new()
	for i: int in REGION_NAMES.size():
		var button: Button = Button.new()
		button.text = "%d  %s" % [i + 1, REGION_NAMES[i]]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == _region
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_color_override(&"font_color", REGION_TINTS[i])
		button.add_theme_color_override(&"font_pressed_color", REGION_TINTS[i])
		button.add_theme_color_override(&"font_hover_color", REGION_TINTS[i])
		button.pressed.connect(_set_region.bind(i))
		regions.add_child(button)
		_region_buttons.append(button)

	var tone_row: HBoxContainer = HBoxContainer.new()
	column.add_child(tone_row)
	tone_row.add_child(_heading("Skin colour (Alt+click)"))
	_tone_swatch = ColorRect.new()
	_tone_swatch.custom_minimum_size = Vector2(40.0, 14.0)
	_tone_swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tone_row.add_child(_tone_swatch)

	column.add_child(_heading("Brush size"))
	_size_slider = HSlider.new()
	_size_slider.focus_mode = Control.FOCUS_NONE
	_size_slider.min_value = BRUSH_LIMITS.x
	_size_slider.max_value = BRUSH_LIMITS.y
	_size_slider.step = 0.001
	_size_slider.exp_edit = true
	_size_slider.value = _brush
	_size_slider.value_changed.connect(func(value: float) -> void: _brush = value)
	column.add_child(_size_slider)
	_mirror_box = CheckBox.new()
	_mirror_box.text = "Mirror left and right (M)"
	_mirror_box.focus_mode = Control.FOCUS_NONE
	_mirror_box.toggled.connect(func(on: bool) -> void: _mirror = on)
	column.add_child(_mirror_box)

	column.add_child(_heading("View (Tab)"))
	_view_pick = OptionButton.new()
	_view_pick.focus_mode = Control.FOCUS_NONE
	for view: String in VIEW_NAMES:
		_view_pick.add_item(view)
	_view_pick.item_selected.connect(_set_view)
	column.add_child(_view_pick)

	var edits: HBoxContainer = HBoxContainer.new()
	column.add_child(edits)
	edits.add_child(_button("Undo", _undo))
	edits.add_child(_button("Redo", _redo))
	edits.add_child(_button("Revert", _revert))
	column.add_child(_button("Save (Ctrl+S)", _save))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = PANEL_WIDTH - 20.0
	column.add_child(_status)
	# The keys, in the corner of the view.
	var keys: Label = Label.new()
	keys.text = KEYS
	keys.add_theme_font_size_override(&"font_size", 12)
	keys.add_theme_color_override(&"font_color", Color(0.85, 0.87, 0.9))
	keys.add_theme_color_override(&"font_outline_color", Color.BLACK)
	keys.add_theme_constant_override(&"outline_size", 3)
	var mono: SystemFont = SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New"])
	keys.add_theme_font_override(&"font", mono)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(keys)
	keys.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)

	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.title = "Unsaved changes"
	_quit_dialog.ok_button_text = "Save and quit"
	_quit_dialog.add_button("Quit without saving", true, "discard")
	_quit_dialog.confirmed.connect(func() -> void:
		if _save():
			get_tree().quit())
	_quit_dialog.custom_action.connect(func(_action: StringName) -> void: get_tree().quit())
	layer.add_child(_quit_dialog)


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", Color(0.75, 0.77, 0.8))
	return label


func _button(text: String, pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(pressed)
	return button


func _fill_teams() -> void:
	_team_pick.clear()
	for team: Dictionary in _teams:
		_team_pick.add_item(team["name"])
	_team_pick.select(_team)
	_fill_players()


## The players of the team that is picked, with a star on those whose mask has
## changes that are not saved.
func _fill_players() -> void:
	_player_list.clear()
	var players: Array[Dictionary] = _teams[_team]["players"]
	for player: Dictionary in players:
		var sheet: Sheet = _sheets.get(player["id"])
		_player_list.add_item("%s%2d  %s" % ["* " if sheet != null and sheet.unsaved else "", player["number"], player["name"]])
	_player_list.select(_player)
	_player_list.ensure_current_is_visible()


func _on_team_picked(team: int) -> void:
	_team = team
	_player = 0
	_fill_players()
	_show_player()


func _on_player_picked(player: int) -> void:
	_player = player
	_show_player()


func _step_player(by: int) -> void:
	var players: Array[Dictionary] = _teams[_team]["players"]
	_player = posmod(_player + by, players.size())
	_player_list.select(_player)
	_player_list.ensure_current_is_visible()
	_show_player()


func _set_region(region: int) -> void:
	_region = region
	_region_buttons[region].button_pressed = true
	_ring_material.albedo_color = REGION_TINTS[region]
	# (The away kit is one colour all over: the trim would be painted blind.)
	if region == TRIM and _view == View.AWAY:
		_set_view(View.HOME)


func _set_view(view: int) -> void:
	_view = view
	_view_pick.select(view)
	_dress()


func _say(text: String) -> void:
	var player: Dictionary = _teams[_team]["players"][_player]
	var unsaved: int = 0
	for sheet: Sheet in _sheets.values():
		if sheet.unsaved:
			unsaved += 1
	var lines: PackedStringArray = [player["name"]]
	if unsaved > 0:
		lines.append("%d player%s not saved" % [unsaved, "" if unsaved == 1 else "s"])
	if text != "":
		lines.append(text)
	_status.text = "\n".join(lines)


# --- The player ------------------------------------------------------------

## Puts the player that is picked on the screen, ready to be painted on.
func _show_player() -> void:
	_painting = false
	var player: Dictionary = _teams[_team]["players"][_player]
	var id: String = player["id"]
	if not _sheets.has(id):
		var sheet: Sheet = _make_sheet(id)
		if sheet == null:
			_status.text = "%s: the mask could not be read." % player["name"]
			return
		_sheets[id] = sheet
	_sheet = _sheets[id]
	_body.mesh = _sheet.mesh
	_image = Image.create_from_data(_sheet.width, _sheet.height, false, Image.FORMAT_RGB8, _sheet.data)
	_texture = ImageTexture.create_from_image(_image)
	_texture_stale = false
	_albedo_texture = null
	if not _sheet.shown.is_empty():
		_albedo_image = Image.create_from_data(_sheet.width, _sheet.height, false, Image.FORMAT_RGB8, _sheet.shown)
		_albedo_texture = ImageTexture.create_from_image(_albedo_image)
	_albedo_stale = false
	_tone_swatch.color = _sheet.tone
	_regions_material.set_shader_parameter(&"albedo_tex", _albedo())
	_regions_material.set_shader_parameter(&"mask_tex", _texture)
	_dress()
	_frame()
	_set_region(_region)
	_say("" if not _sheet.original.is_empty() else NO_TEXTURE % id)


## The colour texture the player is shown with: the one being painted, or the
## game's if he has none to paint.
func _albedo() -> Texture2D:
	return _albedo_texture if _albedo_texture != null else _sheet.albedo


## Gives the model the material of the view that is picked. The kit is the
## game's own: a PlayerModel is dressed as this player and its material taken,
## with the mask that is being painted in place of the saved one.
func _dress() -> void:
	if _sheet == null:
		return
	if _view == View.REGIONS:
		_body.material_override = _regions_material
		return
	var player: Dictionary = _teams[_team]["players"][_player]
	_dresser.show_look(player["look"], _teams[_team]["color"], player["number"], player["name"], _view == View.HOME)
	var material: ShaderMaterial = _dresser._material
	material.set_shader_parameter(&"mask_tex", _texture)
	material.set_shader_parameter(&"albedo_tex", _albedo())
	material.set_shader_parameter(&"plain", _view == View.PLAIN)
	_body.material_override = material


## The camera on the whole player, from the front.
func _frame() -> void:
	_aim = Vector3(0.0, _sheet.tall * 0.5, 0.0)
	_distance = _sheet.tall * 2.3
	_yaw = 0.0
	_pitch = 0.05


## A file of a player among the sources (PAINT_DIR).
func _source_file(id: String, ending: String) -> String:
	return ProjectSettings.globalize_path(PAINT_DIR).path_join(id + ending)


## The picture at `path` as bytes of `format`, at the size of the sheet's
## mask. Empty if there is none.
func _read_picture(path: String, sheet: Sheet, format: Image.Format) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return PackedByteArray()
	if image.is_compressed():
		image.decompress()
	if image.get_width() != sheet.width or image.get_height() != sheet.height:
		image.resize(sheet.width, sheet.height)
	image.convert(format)
	return image.get_data()


## Reads what is saved of the player: his mask, his colour texture as the
## game has it and as he came with it, the skin painted on it. False if the
## mask cannot be read.
func _read_saved(sheet: Sheet) -> bool:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(PlayerParts.PEOPLE[sheet.id]["mask"]))
	if image == null or image.is_empty():
		return false
	image.convert(Image.FORMAT_RGB8)
	sheet.width = image.get_width()
	sheet.height = image.get_height()
	sheet.data = image.get_data()
	sheet.original = PackedByteArray()
	sheet.skin = PackedByteArray()
	sheet.shown = PackedByteArray()
	if sheet.colour_path == "":
		return true
	# (One painted by hand in a texture painter is his texture from then on.)
	var original: PackedByteArray = _read_picture(_source_file(sheet.id, "_colour_paint.png"), sheet, Image.FORMAT_RGB8)
	if original.is_empty():
		original = _read_picture(_source_file(sheet.id, "_colour.jpg"), sheet, Image.FORMAT_RGB8)
	var shown: PackedByteArray = _read_picture(ProjectSettings.globalize_path(sheet.colour_path), sheet, Image.FORMAT_RGB8)
	if original.is_empty() or shown.is_empty():
		return true
	sheet.original = original
	sheet.shown = shown
	sheet.skin = _read_picture(_source_file(sheet.id, "_skin_paint.png"), sheet, Image.FORMAT_RGBA8)
	if sheet.skin.is_empty():
		sheet.skin.resize(sheet.width * sheet.height * 4)
	_find_keys(sheet, 3)
	return true


## How light the middle of each garment is in the texture under it (see
## KIT_TONE), going by every `step`th texel.
func _find_keys(sheet: Sheet, step: int) -> void:
	var counts: Array[PackedInt32Array] = []
	for garment: int in 3:
		var none: PackedInt32Array = PackedInt32Array()
		none.resize(256)
		counts.append(none)
	var totals: PackedInt32Array = PackedInt32Array([0, 0, 0])
	for texel: int in range(0, sheet.width * sheet.height, step):
		var at: int = texel * 3
		var garment: int = 0 if sheet.data[at] > 127 else 1 if sheet.data[at + 1] > 127 else 2 if sheet.data[at + 2] > 127 else -1
		if garment < 0:
			continue
		var luma: int
		if sheet.skin[texel * 4 + 3] != 0:
			luma = roundi(0.3 * sheet.skin[texel * 4] + 0.59 * sheet.skin[texel * 4 + 1] + 0.11 * sheet.skin[texel * 4 + 2])
		else:
			luma = roundi(0.3 * sheet.original[at] + 0.59 * sheet.original[at + 1] + 0.11 * sheet.original[at + 2])
		counts[garment][luma] += 1
		totals[garment] += 1
	for garment: int in 3:
		if totals[garment] == 0:
			continue
		var below: int = 0
		for luma: int in 256:
			below += counts[garment][luma]
			if below * 2 >= totals[garment]:
				sheet.keys[garment] = maxf(float(luma), 5.0)
				break


## Works out one texel of the colour texture the game gets: the skin painted
## there or else what the model came with, and only its shading if it is kit.
func _compose(sheet: Sheet, texel: int) -> void:
	var at: int = texel * 3
	var from: int = texel * 4
	var red: int
	var green: int
	var blue: int
	if sheet.skin[from + 3] != 0:
		red = sheet.skin[from]
		green = sheet.skin[from + 1]
		blue = sheet.skin[from + 2]
	else:
		red = sheet.original[at]
		green = sheet.original[at + 1]
		blue = sheet.original[at + 2]
	var garment: int = 0 if sheet.data[at] > 127 else 1 if sheet.data[at + 1] > 127 else 2 if sheet.data[at + 2] > 127 else -1
	if garment >= 0:
		red = clampi(roundi((0.3 * red + 0.59 * green + 0.11 * blue) / sheet.keys[garment] * KIT_TONE * 255.0), 0, 255)
		green = red
		blue = red
	sheet.shown[at] = red
	sheet.shown[at + 1] = green
	sheet.shown[at + 2] = blue


## The colour of the player's hands in the texture he came with: one on the
## light side of them (SKIN_PICK), as the folds between the fingers are dark
## and the skin that gets painted is not in a fold.
func _find_tone(sheet: Sheet, shares: PackedColorArray) -> Color:
	var found: Array[Color] = []
	for i: int in mini(shares.size(), sheet.texels.size()):
		if shares[i].g < 0.8:
			continue
		var x: int = clampi(floori(sheet.texels[i].x), 0, sheet.width - 1)
		var y: int = clampi(floori(sheet.texels[i].y), 0, sheet.height - 1)
		var at: int = (y * sheet.width + x) * 3
		found.append(Color8(sheet.original[at], sheet.original[at + 1], sheet.original[at + 2]))
	if found.size() < 20:
		return SKIN_USUAL
	found.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
	return found[int(float(found.size() - 1) * SKIN_PICK)]


## The player with this id made ready: its mesh sorted into the grid, and the
## mask and the texture as they are on disk.
func _make_sheet(id: String) -> Sheet:
	var sheet: Sheet = Sheet.new()
	sheet.id = id
	var info: KitBase = KitBase.of_person(id)
	sheet.mesh = info.mesh
	sheet.albedo = info.albedo
	sheet.colour_path = info.albedo.resource_path if info.albedo != null else ""
	if not sheet.colour_path.begins_with("res://") or sheet.colour_path.contains("::"):
		sheet.colour_path = ""
	sheet.tall = info.top_z("")
	if not _read_saved(sheet):
		return null
	var arrays: Array = info.mesh.surface_get_arrays(0)
	sheet.points = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var smooth: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if arrays[Mesh.ARRAY_INDEX] != null:
		sheet.index = arrays[Mesh.ARRAY_INDEX]
	if sheet.index.is_empty():
		sheet.index = PackedInt32Array(range(sheet.points.size()))
	sheet.texels.resize(uvs.size())
	var size: Vector2 = Vector2(sheet.width, sheet.height)
	for i: int in uvs.size():
		sheet.texels[i] = Vector2(fposmod(uvs[i].x, 1.0), fposmod(uvs[i].y, 1.0)) * size
	sheet.low = Vector3.ONE * INF
	sheet.high = Vector3.ONE * -INF
	for point: Vector3 in sheet.points:
		sheet.low = sheet.low.min(point)
		sheet.high = sheet.high.max(point)

	@warning_ignore("integer_division")
	var count: int = sheet.index.size() / 3
	sheet.normals.resize(count)
	sheet.seam.resize(count)
	sheet.cover.resize(sheet.width * sheet.height)
	# How many triangles each edge belongs to: one only at an edge of a piece
	# of the texture (the mesh has corners of its own on each side of a seam).
	var corners: int = sheet.points.size()
	var edges: Dictionary[int, int] = {}
	for t: int in count:
		for k: int in 3:
			var one: int = sheet.index[t * 3 + k]
			var two: int = sheet.index[t * 3 + (k + 1) % 3]
			var edge: int = mini(one, two) * corners + maxi(one, two)
			edges[edge] = edges.get(edge, 0) + 1
	for t: int in count:
		for k: int in 3:
			var one: int = sheet.index[t * 3 + k]
			var two: int = sheet.index[t * 3 + (k + 1) % 3]
			if edges[mini(one, two) * corners + maxi(one, two)] == 1:
				sheet.seam[t] = 1
	for t: int in count:
		var ia: int = sheet.index[t * 3]
		var ib: int = sheet.index[t * 3 + 1]
		var ic: int = sheet.index[t * 3 + 2]
		var a: Vector3 = sheet.points[ia]
		var b: Vector3 = sheet.points[ib]
		var c: Vector3 = sheet.points[ic]
		# Out of the model, whichever way round the corners go.
		var normal: Vector3 = (c - a).cross(b - a).normalized()
		if normal.dot(smooth[ia] + smooth[ib] + smooth[ic]) < 0.0:
			normal = -normal
		sheet.normals[t] = normal
		var from: Vector3i = Vector3i((a.min(b).min(c) / CELL).floor())
		var to: Vector3i = Vector3i((a.max(b).max(c) / CELL).floor())
		for x: int in range(from.x, to.x + 1):
			for y: int in range(from.y, to.y + 1):
				for z: int in range(from.z, to.z + 1):
					var key: Vector3i = Vector3i(x, y, z)
					if sheet.grid.has(key):
						sheet.grid[key].append(t)
					else:
						sheet.grid[key] = [t]
		_cover_triangle(sheet, sheet.texels[ia], sheet.texels[ib], sheet.texels[ic])
	if not sheet.original.is_empty() and arrays[Mesh.ARRAY_COLOR] != null:
		sheet.tone = _find_tone(sheet, arrays[Mesh.ARRAY_COLOR])
	return sheet


## Marks the texels whose middle lies inside the triangle a, b, c of the mask.
func _cover_triangle(sheet: Sheet, a: Vector2, b: Vector2, c: Vector2) -> void:
	var area: float = (b - a).cross(c - a)
	if absf(area) < 1e-6:
		return
	var inv: float = 1.0 / area
	var x0: int = maxi(floori(minf(a.x, minf(b.x, c.x))), 0)
	var x1: int = mini(ceili(maxf(a.x, maxf(b.x, c.x))), sheet.width - 1)
	var y0: int = maxi(floori(minf(a.y, minf(b.y, c.y))), 0)
	var y1: int = mini(ceili(maxf(a.y, maxf(b.y, c.y))), sheet.height - 1)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var wa: float = (b - p).cross(c - p) * inv
			var wb: float = (c - p).cross(a - p) * inv
			if wa >= 0.0 and wb >= 0.0 and wa + wb <= 1.0:
				sheet.cover[y * sheet.width + x] = 1


# --- Pointing and painting -------------------------------------------------

## Where the ray from `from` along `along` first meets the front of the
## model: sets _hit_at and _hit_normal. False if it misses.
func _cast(from: Vector3, along: Vector3) -> bool:
	if _sheet == null:
		return false
	# The stretch of the ray inside the box round the model.
	var enter: float = 0.0
	var leave: float = INF
	for axis: int in 3:
		if absf(along[axis]) < 1e-9:
			if from[axis] < _sheet.low[axis] or from[axis] > _sheet.high[axis]:
				return false
			continue
		var one: float = (_sheet.low[axis] - from[axis]) / along[axis]
		var two: float = (_sheet.high[axis] - from[axis]) / along[axis]
		enter = maxf(enter, minf(one, two))
		leave = minf(leave, maxf(one, two))
	if enter > leave:
		return false
	var best: float = INF
	var tried: Dictionary[int, bool] = {}
	var last: Vector3i = Vector3i(1 << 30, 0, 0)
	var t: float = enter
	while t <= leave + CELL:
		var key: Vector3i = Vector3i(((from + along * t) / CELL).floor())
		t += CELL * 0.5
		if key == last:
			continue
		last = key
		if _sheet.grid.has(key):
			for triangle: int in _sheet.grid[key]:
				if tried.has(triangle):
					continue
				tried[triangle] = true
				var normal: Vector3 = _sheet.normals[triangle]
				var toward: float = normal.dot(along)
				if toward >= -1e-9:
					continue
				var a: Vector3 = _sheet.points[_sheet.index[triangle * 3]]
				var reach: float = normal.dot(a - from) / toward
				if reach < 0.0 or reach >= best:
					continue
				var at: Vector3 = from + along * reach
				var b: Vector3 = _sheet.points[_sheet.index[triangle * 3 + 1]]
				var c: Vector3 = _sheet.points[_sheet.index[triangle * 3 + 2]]
				# Inside the triangle if it is on the same side of all three edges.
				var s0: float = (b - a).cross(at - a).dot(normal)
				var s1: float = (c - b).cross(at - b).dot(normal)
				var s2: float = (a - c).cross(at - c).dot(normal)
				if (s0 >= 0.0 and s1 >= 0.0 and s2 >= 0.0) or (s0 <= 0.0 and s1 <= 0.0 and s2 <= 0.0):
					best = reach
					_hit_at = at
					_hit_normal = normal
					_hit_triangle = triangle
		# Nothing nearer can turn up once the ray is past what it hit.
		if best < t - CELL:
			break
	return best < INF


## Points at the model from the pixel `px` of the window.
func _point(px: Vector2) -> bool:
	_on_model = _cast(_camera.project_ray_origin(px), _camera.project_ray_normal(px))
	return _on_model


## Where in the texture the spot pointed at is, in texels.
func _hit_texel() -> Vector2i:
	var a: Vector3 = _sheet.points[_sheet.index[_hit_triangle * 3]]
	var b: Vector3 = _sheet.points[_sheet.index[_hit_triangle * 3 + 1]]
	var c: Vector3 = _sheet.points[_sheet.index[_hit_triangle * 3 + 2]]
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var ap: Vector3 = _hit_at - a
	var d00: float = ab.dot(ab)
	var d01: float = ab.dot(ac)
	var d11: float = ac.dot(ac)
	var size: float = d00 * d11 - d01 * d01
	var wb: float = 0.0
	var wc: float = 0.0
	if absf(size) > 1e-18:
		wb = (d11 * ap.dot(ab) - d01 * ap.dot(ac)) / size
		wc = (d00 * ap.dot(ac) - d01 * ap.dot(ab)) / size
	var at: Vector2 = _sheet.texels[_sheet.index[_hit_triangle * 3]] * (1.0 - wb - wc) + _sheet.texels[_sheet.index[_hit_triangle * 3 + 1]] * wb + _sheet.texels[_sheet.index[_hit_triangle * 3 + 2]] * wc
	return Vector2i(clampi(floori(at.x), 0, _sheet.width - 1), clampi(floori(at.y), 0, _sheet.height - 1))


## The middle colour of the texture (what the model came with and the skin
## painted on it) within `reach` texels of `texel`, where the model has it.
func _colour_near(texel: Vector2i, reach: int) -> Color:
	var sum: Vector3 = Vector3.ZERO
	var count: int = 0
	for y: int in range(maxi(texel.y - reach, 0), mini(texel.y + reach, _sheet.height - 1) + 1):
		for x: int in range(maxi(texel.x - reach, 0), mini(texel.x + reach, _sheet.width - 1) + 1):
			var at: int = y * _sheet.width + x
			if _sheet.cover[at] == 0:
				continue
			if _sheet.skin[at * 4 + 3] != 0:
				sum += Vector3(_sheet.skin[at * 4], _sheet.skin[at * 4 + 1], _sheet.skin[at * 4 + 2])
			else:
				sum += Vector3(_sheet.original[at * 3], _sheet.original[at * 3 + 1], _sheet.original[at * 3 + 2])
			count += 1
	if count == 0:
		return _sheet.tone
	sum /= float(count) * 255.0
	return Color(sum.x, sum.y, sum.z)


## Takes the colour the Skin brush paints from where the pixel `px` points.
func _pick_tone(px: Vector2) -> void:
	if _sheet.original.is_empty() or not _point(px):
		return
	_sheet.tone = _colour_near(_hit_texel(), 2)
	_tone_swatch.color = _sheet.tone
	_say("Skin colour picked.")


## Paints one dab of the brush where the pixel `px` points, if it points at
## the model: on the other side as well with the mirror on.
func _paint_at(px: Vector2) -> void:
	if not _point(px):
		return
	var colour: Color = REGION_BYTES[_region]
	_dab(_hit_at, _hit_normal, colour)
	if _mirror:
		_dab(_hit_at * Vector3(-1.0, 1.0, 1.0), _hit_normal * Vector3(-1.0, 1.0, 1.0), colour)


## Paints from the last pixel painted at to `px`, a dab every so often.
func _paint_to(px: Vector2) -> void:
	# How big the brush is on the screen, to space the dabs by.
	var on_screen: float = _brush / (_distance * tan(deg_to_rad(_camera.fov) * 0.5)) * float(get_viewport().get_visible_rect().size.y) * 0.5
	var steps: int = clampi(ceili(_last_px.distance_to(px) / maxf(on_screen * 0.35, 3.0)), 1, 48)
	for i: int in range(1, steps + 1):
		_paint_at(_last_px.lerp(px, float(i) / float(steps)))
	_last_px = px


## Gives everything within the brush of `centre` that faces the way `normal`
## does the value `colour` in the mask (and with ERASE and SKIN what those
## do to the texture).
func _dab(centre: Vector3, normal: Vector3, colour: Color) -> void:
	var from: Vector3i = Vector3i(((centre - Vector3.ONE * _brush) / CELL).floor())
	var to: Vector3i = Vector3i(((centre + Vector3.ONE * _brush) / CELL).floor())
	var done: Dictionary[int, bool] = {}
	var red: int = roundi(colour.r * 255.0)
	var green: int = roundi(colour.g * 255.0)
	var blue: int = roundi(colour.b * 255.0)
	for x: int in range(from.x, to.x + 1):
		for y: int in range(from.y, to.y + 1):
			for z: int in range(from.z, to.z + 1):
				var key: Vector3i = Vector3i(x, y, z)
				if not _sheet.grid.has(key):
					continue
				for triangle: int in _sheet.grid[key]:
					if done.has(triangle):
						continue
					done[triangle] = true
					if _sheet.normals[triangle].dot(normal) >= FACING:
						_paint_triangle(triangle, centre, red, green, blue)


## The part of one triangle that is within the brush of `centre`.
func _paint_triangle(triangle: int, centre: Vector3, red: int, green: int, blue: int) -> void:
	var sheet: Sheet = _sheet
	var ia: int = sheet.index[triangle * 3]
	var ib: int = sheet.index[triangle * 3 + 1]
	var ic: int = sheet.index[triangle * 3 + 2]
	var pa: Vector3 = sheet.points[ia]
	var pb: Vector3 = sheet.points[ib]
	var pc: Vector3 = sheet.points[ic]
	var reach: float = _brush * _brush
	if centre.clamp(pa.min(pb).min(pc), pa.max(pb).max(pc)).distance_squared_to(centre) > reach:
		return
	var a: Vector2 = sheet.texels[ia]
	var b: Vector2 = sheet.texels[ib]
	var c: Vector2 = sheet.texels[ic]
	var area: float = (b - a).cross(c - a)
	if absf(area) < 1e-6:
		return
	var inv: float = 1.0 / area
	# How far below nothing a corner's share may go for a texel PAD outside its edge.
	# (Only a triangle at a seam has anything past its edges to paint.)
	var size: float = absf(area)
	var pad: float = PAD if sheet.seam[triangle] != 0 else 0.0
	var slack_a: float = pad * b.distance_to(c) / size
	var slack_b: float = pad * c.distance_to(a) / size
	var slack_c: float = pad * a.distance_to(b) / size
	var x0: int = maxi(floori(minf(a.x, minf(b.x, c.x)) - pad), 0)
	var x1: int = mini(ceili(maxf(a.x, maxf(b.x, c.x)) + pad), sheet.width - 1)
	var y0: int = maxi(floori(minf(a.y, minf(b.y, c.y)) - pad), 0)
	var y1: int = mini(ceili(maxf(a.y, maxf(b.y, c.y)) + pad), sheet.height - 1)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var wa: float = (b - p).cross(c - p) * inv
			var wb: float = (c - p).cross(a - p) * inv
			var wc: float = 1.0 - wa - wb
			var texel: int = y * sheet.width + x
			if wa < 0.0 or wb < 0.0 or wc < 0.0:
				# Past the edge: only where no triangle of its own has the texel.
				if wa < -slack_a or wb < -slack_b or wc < -slack_c or sheet.cover[texel] != 0:
					continue
			if (pa * wa + pb * wb + pc * wc).distance_squared_to(centre) > reach:
				continue
			var at: int = texel * 3
			var changed: bool = sheet.data[at] != red or sheet.data[at + 1] != green or sheet.data[at + 2] != blue
			sheet.data[at] = red
			sheet.data[at + 1] = green
			sheet.data[at + 2] = blue
			if not sheet.original.is_empty():
				var from: int = texel * 4
				if _region == ERASE and sheet.skin[from + 3] != 0:
					sheet.skin[from + 3] = 0
					changed = true
				elif _region == SKIN:
					# As much lighter or darker than the skin colour as what the
					# model has here is than where the stroke began.
					var shade: float = clampf((0.3 * sheet.original[at] + 0.59 * sheet.original[at + 1] + 0.11 * sheet.original[at + 2]) / _stroke_ref, SKIN_SHADE.x, SKIN_SHADE.y) * 255.0
					var skin_red: int = clampi(roundi(sheet.tone.r * shade), 0, 255)
					var skin_green: int = clampi(roundi(sheet.tone.g * shade), 0, 255)
					var skin_blue: int = clampi(roundi(sheet.tone.b * shade), 0, 255)
					if sheet.skin[from + 3] == 0 or sheet.skin[from] != skin_red or sheet.skin[from + 1] != skin_green or sheet.skin[from + 2] != skin_blue:
						sheet.skin[from] = skin_red
						sheet.skin[from + 1] = skin_green
						sheet.skin[from + 2] = skin_blue
						sheet.skin[from + 3] = 255
						changed = true
				if changed:
					_compose(sheet, texel)
					_albedo_stale = true
			if not changed:
				continue
			_stroke_changed = true
			_texture_stale = true


func _begin_stroke(px: Vector2) -> void:
	if _sheet == null:
		return
	if _region == SKIN:
		if _sheet.original.is_empty():
			_say(NO_TEXTURE % _sheet.id)
			return
		# (A stroke that begins beside the model takes the usual middle.)
		_stroke_ref = 128.0
		if _point(px):
			_stroke_ref = maxf(_colour_near(_hit_texel(), 4).get_luminance() * 255.0, 20.0)
	_painting = true
	_stroke_changed = false
	_sheet.undo.append(_snapshot(_region == ERASE or _region == SKIN))
	_last_px = px
	_paint_at(px)


func _end_stroke() -> void:
	if not _painting:
		return
	_painting = false
	if not _stroke_changed:
		_sheet.undo.pop_back()
		return
	if _sheet.undo.size() > UNDO_STEPS:
		_sheet.undo.pop_front()
	_sheet.redo.clear()
	_changed("")


## The mask and the texture as they are now, to come back to: the painted
## skin as well if `with_skin`.
func _snapshot(with_skin: bool) -> Dictionary:
	return {
		"mask": _sheet.data.duplicate(),
		"shown": _sheet.shown.duplicate(),
		"skin": _sheet.skin.duplicate() if with_skin else PackedByteArray(),
	}


func _restore(from: Dictionary) -> void:
	_sheet.data = from["mask"]
	_sheet.shown = from["shown"]
	if not (from["skin"] as PackedByteArray).is_empty():
		_sheet.skin = from["skin"]


## After the mask or the texture of the player on the screen has changed.
func _changed(text: String) -> void:
	_sheet.unsaved = true
	_texture_stale = true
	_albedo_stale = true
	_fill_players()
	_say(text)


func _undo() -> void:
	if _sheet == null or _painting or _sheet.undo.is_empty():
		return
	var back: Dictionary = _sheet.undo.pop_back()
	_sheet.redo.append(_snapshot(not (back["skin"] as PackedByteArray).is_empty()))
	_restore(back)
	_changed("Undone.")


func _redo() -> void:
	if _sheet == null or _painting or _sheet.redo.is_empty():
		return
	var again: Dictionary = _sheet.redo.pop_back()
	_sheet.undo.append(_snapshot(not (again["skin"] as PackedByteArray).is_empty()))
	_restore(again)
	_changed("Redone.")


## Back to the player as he is on disk (which can be undone).
func _revert() -> void:
	if _sheet == null or _painting:
		return
	var now: Dictionary = _snapshot(true)
	if not _read_saved(_sheet):
		_restore(now)
		_say("The saved mask could not be read.")
		return
	_sheet.undo.append(now)
	_sheet.redo.clear()
	_changed("Back to what is saved.")
	_sheet.unsaved = false
	_fill_players()
	_say("Back to what is saved.")


## Writes the files of every player that has changes (see the top of this
## file). False if one failed.
func _save() -> bool:
	var saved: int = 0
	for sheet: Sheet in _sheets.values():
		if not sheet.unsaved:
			continue
		var image: Image = Image.create_from_data(sheet.width, sheet.height, false, Image.FORMAT_RGB8, sheet.data)
		var errors: Dictionary[String, Error] = {}
		for path: String in [ProjectSettings.globalize_path(PlayerParts.PEOPLE[sheet.id]["mask"]), _source_file(sheet.id, "_mask_paint.png")]:
			errors[path] = image.save_png(path)
		if not sheet.original.is_empty():
			# The kit's shading goes by the middle of each garment as it is now.
			_find_keys(sheet, 1)
			var painted: bool = false
			for texel: int in sheet.width * sheet.height:
				if sheet.data[texel * 3] != 0 or sheet.data[texel * 3 + 1] != 0 or sheet.data[texel * 3 + 2] != 0:
					_compose(sheet, texel)
				if sheet.skin[texel * 4 + 3] != 0:
					painted = true
			if sheet == _sheet:
				_albedo_stale = true
			var colour: String = ProjectSettings.globalize_path(sheet.colour_path)
			errors[colour] = Image.create_from_data(sheet.width, sheet.height, false, Image.FORMAT_RGB8, sheet.shown).save_jpg(colour, JPG_QUALITY)
			var skin: String = _source_file(sheet.id, "_skin_paint.png")
			if painted:
				errors[skin] = Image.create_from_data(sheet.width, sheet.height, false, Image.FORMAT_RGBA8, sheet.skin).save_png(skin)
			elif FileAccess.file_exists(skin):
				errors[skin] = DirAccess.remove_absolute(skin)
		for path: String in errors:
			if errors[path] != OK:
				_say("Could not write %s (%s)." % [path, error_string(errors[path])])
				return false
		sheet.unsaved = false
		saved += 1
	if _sheet != null:
		_fill_players()
		_say("Saved %d player%s." % [saved, "" if saved == 1 else "s"] if saved > 0 else "Nothing to save.")
	return true


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	for sheet: Sheet in _sheets.values():
		if sheet.unsaved:
			_quit_dialog.dialog_text = "Some players have changes that are not saved."
			_quit_dialog.popup_centered()
			return
	get_tree().quit()


func _process(_delta: float) -> void:
	if _sheet == null:
		return
	if _texture_stale:
		_texture_stale = false
		_image.set_data(_sheet.width, _sheet.height, false, Image.FORMAT_RGB8, _sheet.data)
		_texture.update(_image)
	if _albedo_stale:
		_albedo_stale = false
		if _albedo_texture != null:
			_albedo_image.set_data(_sheet.width, _sheet.height, false, Image.FORMAT_RGB8, _sheet.shown)
			_albedo_texture.update(_albedo_image)
	var away: Vector3 = Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	# What is aimed at is in the middle of the view beside the panel, not of the window.
	var view: Vector2 = get_viewport().get_visible_rect().size
	var aside: Vector3 = Vector3(cos(_yaw), 0.0, -sin(_yaw)) * (PANEL_WIDTH * 0.5 / view.y * _distance * tan(deg_to_rad(_camera.fov) * 0.5) * 2.0)
	_camera.look_at_from_position(_aim - aside + away * _distance, _aim - aside)
	# The brush: a ring flat on the model where the mouse points.
	for i: int in _rings.size():
		var ring: MeshInstance3D = _rings[i]
		ring.visible = _on_model and (i == 0 or _mirror)
		if not ring.visible:
			continue
		var flip: Vector3 = Vector3(1.0, 1.0, 1.0) if i == 0 else Vector3(-1.0, 1.0, 1.0)
		var up: Vector3 = _hit_normal * flip
		var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP).normalized()
		ring.transform = Transform3D(Basis(side, up, side.cross(up)).scaled(Vector3.ONE * _brush), _hit_at * flip)


func _unhandled_input(event: InputEvent) -> void:
	if _sheet == null:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT != 0:
			_yaw -= motion.relative.x * ORBIT_PER_PIXEL
			_pitch = clampf(_pitch + motion.relative.y * ORBIT_PER_PIXEL, -1.4, 1.4)
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE != 0:
			var per_pixel: float = _distance * tan(deg_to_rad(_camera.fov) * 0.5) * 2.0 / float(get_viewport().get_visible_rect().size.y)
			_aim -= _camera.global_basis.x * motion.relative.x * per_pixel
			_aim += _camera.global_basis.y * motion.relative.y * per_pixel
		elif _painting:
			_paint_to(motion.position)
		else:
			_point(motion.position)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed and button.alt_pressed:
					_pick_tone(button.position)
				elif button.pressed:
					_begin_stroke(button.position)
				else:
					_end_stroke()
			MOUSE_BUTTON_WHEEL_UP:
				if not button.pressed:
					pass
				elif button.ctrl_pressed:
					_size_slider.value = _brush * 1.1
				else:
					_distance = maxf(_distance * 0.9, _sheet.tall * 0.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if not button.pressed:
					pass
				elif button.ctrl_pressed:
					_size_slider.value = _brush / 1.1
				else:
					_distance = minf(_distance / 0.9, _sheet.tall * 8.0)
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.ctrl_pressed or key.meta_pressed:
		if key.echo and key.keycode == KEY_S:
			return
		match key.keycode:
			KEY_Z:
				if key.shift_pressed:
					_redo()
				else:
					_undo()
			KEY_Y:
				_redo()
			KEY_S:
				_save()
		return
	match key.keycode:
		KEY_BRACKETLEFT:
			_size_slider.value = _brush / 1.2
		KEY_BRACKETRIGHT:
			_size_slider.value = _brush * 1.2
	if key.echo:
		return
	match key.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_set_region(key.keycode - KEY_1)
		KEY_M:
			_mirror_box.button_pressed = not _mirror
		KEY_TAB:
			_set_view((_view + 1) % VIEW_NAMES.size())
		KEY_F:
			_frame()
		KEY_COMMA:
			_step_player(-1)
		KEY_PERIOD:
			_step_player(1)
