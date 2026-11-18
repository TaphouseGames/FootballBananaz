class_name ModelStage
extends RefCounted
## The little world a model is drawn in for a screen of the menus: a viewport
## of its own with a camera, a sun and an even light, drawn into a texture with
## nothing behind the model. The team select stands the mascots and the teams'
## players in one, the pause menu's roster the chosen player.

## How far the ground is above the bottom of the picture, in the world's units.
const GROUND_MARGIN: float = 0.08
const AMBIENT_COLOR: Color = Color(0.86, 0.9, 1.0)
const MOTION_NAME: StringName = &"Motion"


## A stage whose picture is `size_px` and shows `frame_tall` of the world from
## top to bottom, looked at from +Z with the origin on the ground in the
## middle. The sun comes from `sun_yaw` degrees to the side. Nothing is drawn
## until its render_target_update_mode is set.
static func build(size_px: Vector2i, frame_tall: float, sun_yaw: float) -> SubViewport:
	var view: SubViewport = SubViewport.new()
	view.size = size_px
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED

	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = frame_tall
	camera.position = Vector3(0.0, frame_tall * 0.5 - GROUND_MARGIN, 8.0)
	view.add_child(camera)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, sun_yaw, 0.0)
	sun.light_energy = 1.25
	view.add_child(sun)
	var sky: Environment = Environment.new()
	sky.background_mode = Environment.BG_CLEAR_COLOR
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = AMBIENT_COLOR
	sky.ambient_light_energy = 0.75
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = sky
	view.add_child(world)
	return view


## A player's model for a stage, with what keeps it moving there (see
## ModelMotion). `phase` is where in its motions it starts. Whose it is, is
## for show_look().
static func model(phase: float = 0.0) -> PlayerModel:
	var made: PlayerModel = PlayerModel.new()
	var motion: ModelMotion = ModelMotion.new()
	motion.name = MOTION_NAME
	motion.phase = phase
	made.add_child(motion)
	return made


## The model of the player with these ratings in the kit of a team of this
## colour, as Player has it on the field.
static func player(ratings: PlayerRatings, color: Color, white_kit: bool, phase: float = 0.0) -> PlayerModel:
	var made: PlayerModel = model(phase)
	made.show_look(ratings.look_or_default(), color, ratings.number, ratings.display_name, white_kit)
	return made


## What keeps a model made here moving.
static func motion_of(made: PlayerModel) -> ModelMotion:
	return made.get_node(NodePath(MOTION_NAME)) as ModelMotion
