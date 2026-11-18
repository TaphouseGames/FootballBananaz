extends SceneTree
## Check of the stadium round the field. In a match: it is built, the crowd is
## there and sits behind the wall, each side of the bowl has the share of home
## fans Tuning asks for, a crowd reaction from the audio gets the right side up,
## and a touchdown shows on the jumbotrons. On its own: cheers and waves wear
## off, the density setting thins the crowd, and switching it off leaves
## nothing behind.
##
## Real time (the crowd runs on the wall clock), so no --fixed-fps. About 10 s.
## Run:  godot --headless --path . --script res://tests/stadium_check.gd

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Game = scene.instantiate() as Game
	game.autoplay = true
	game.tuning = game.tuning.duplicate() as Tuning
	game.tuning.audio_enabled = false
	root.add_child(game)
	await _real_wait(0.3)
	var tuning: Tuning = game.tuning
	var stadium: Stadium = game.field.stadium
	print("Fans: %d.  Home fans on the home side %s, on the away side %s." % [stadium.fan_count, stadium.home_side_fans, stadium.away_side_fans])
	if stadium.fan_count < 1500:
		_failures.append("only %d fans in the stands" % stadium.fan_count)
	if stadium.get_node_or_null(^"Stands") == null or stadium.get_node_or_null(^"Boards") == null:
		_failures.append("the stands or the ad boards are missing")
	for prop: String in ["Jumbotrons", "LightTowers", "HotDogStand", "BoothAnchor"]:
		if stadium.props.get_node_or_null(NodePath(prop)) == null:
			_failures.append("no %s under Stadium/Props" % prop)
	for file: String in ["jumbotron.glb", "light_tower.glb", "hot_dog_stand.glb", Stadium.MASCOT_FALLBACK, "crowd_people.glb", "crowd_people_atlas.png", "crowd_people_mask.png", "crowd_people_normal.png"]:
		if not ResourceLoader.exists(Stadium.PROP_DIR + file):
			_failures.append("assets/stadium/%s is missing" % file)

	# Nobody on the grass: every fan is up in the rows and clear of the lines.
	var counted: int = 0
	var inside: int = 0
	var field_rect: Rect2 = Rect2(-tuning.end_zone_depth, -tuning.half_width(), tuning.field_length + tuning.end_zone_depth * 2.0, tuning.field_width)
	# Every piece of the stands holds the same fans at each level of detail:
	# a head, a torso and legs each, at all three.
	var chunks: int = 0
	var uneven: int = 0
	# The fans (of tools/crowd_parts.json) whose heads are in the stands.
	var heads: Dictionary = {}
	var torsos: Dictionary = {}
	var legs: Dictionary = {}
	# The people (of tools/crowd_people.json) who are in the stands, where the
	# crowd is made of whole people: one mesh a fan at every level of detail.
	var whole: bool = not stadium._people.is_empty()
	var persons: Dictionary = {}
	for chunk: Node in stadium.get_node(^"Crowd").get_children():
		var parts: Dictionary = {}
		for child: Node in chunk.get_children():
			var tier: String = String(child.name).rstrip("0123456789")
			if tier in Stadium.TIER_NAMES:
				if String(child.get_meta(&"kind", "?")) == "head":
					heads[(child as MultiMeshInstance3D).multimesh.mesh.get_meta(&"fan", "")] = true
				elif String(child.get_meta(&"kind", "?")) == "torso":
					torsos[(child as MultiMeshInstance3D).multimesh.mesh.get_meta(&"fan", "")] = true
				elif String(child.get_meta(&"kind", "?")) == "person":
					persons[(child as MultiMeshInstance3D).multimesh.mesh.get_meta(&"fan", "")] = true
				elif String(child.get_meta(&"kind", "?")) == "legs":
					legs[(child as MultiMeshInstance3D).multimesh.mesh.get_meta(&"fan", "")] = true
				var key: String = "%s %s" % [tier, child.get_meta(&"kind", "?")]
				parts[key] = int(parts.get(key, 0)) + (child as MultiMeshInstance3D).multimesh.instance_count
		chunks += 1
		var fans: int = int(parts.get("Far person" if whole else "Far head", 0))
		counted += fans
		if parts.size() != (3 if whole else 9):
			uneven += 1
			continue
		var wanted: Array[String] = ["Near head", "Near torso", "Near legs", "Mid head", "Mid torso", "Mid legs", "Far torso", "Far legs"]
		if whole:
			wanted = ["Near person", "Mid person"]
		for key: String in wanted:
			if int(parts.get(key, -1)) != fans:
				uneven += 1
				break
	print("Pieces of the stands: %d.  People: %s.  Kits of parts: %d.  Heads from: %s.  Outfits from: %s." % [chunks, persons.keys(), stadium._kits.size(), heads.keys(), torsos.keys()])
	# Everybody is the one person that was asked for, or everyone is somewhere.
	if whole and tuning.crowd_person != "" and persons.keys() != [tuning.crowd_person]:
		_failures.append("crowd_person is '%s', but the people in the stands are %s" % [tuning.crowd_person, persons.keys()])
	if whole and tuning.crowd_person == "" and persons.size() != stadium._people.size():
		_failures.append("there are %d people, but the stands have %s only" % [stadium._people.size(), persons.keys()])
	# Everybody has the one head, the one outfit and the legs that were asked for.
	if not whole and tuning.crowd_legs != "" and legs.keys() != [tuning.crowd_legs]:
		_failures.append("crowd_legs is '%s', but the legs in the stands are from %s" % [tuning.crowd_legs, legs.keys()])
	if not whole and tuning.crowd_torso != "" and torsos.keys() != [tuning.crowd_torso]:
		_failures.append("crowd_torso is '%s', but the outfits in the stands are from %s" % [tuning.crowd_torso, torsos.keys()])
	# Or, with no one head asked for, every head of the kit is somewhere.
	if tuning.crowd_head == "" and not stadium._kits.is_empty() and heads.size() != (stadium._kits[0].heads[0] as Array).size():
		_failures.append("the kit has %d heads, but the stands have those of %s only" % [(stadium._kits[0].heads[0] as Array).size(), heads.keys()])
	if not whole and tuning.crowd_head != "" and heads.keys() != [tuning.crowd_head]:
		_failures.append("crowd_head is '%s', but the heads in the stands are from %s" % [tuning.crowd_head, heads.keys()])
	if uneven > 0:
		_failures.append("%d of %d pieces of the stands do not hold every fan (whole, or a head, a torso and legs) at every level of detail" % [uneven, chunks])
	for at: Vector3 in stadium.fan_positions:
		if at.y < Stadium.FIRST_ROW_HEIGHT or field_rect.grow(tuning.wall_gap).has_point(Vector2(at.x, at.z)):
			inside += 1
	if counted != stadium.fan_count or stadium.fan_positions.size() != counted:
		_failures.append("fan_count says %d, the MultiMeshes hold %d" % [stadium.fan_count, counted])
	if inside > 0:
		_failures.append("%d fans are inside the wall or on the ground" % inside)

	# The signs: the share that was asked for, and none near another.
	var signs: int = stadium.sign_positions.size()
	var wanted_signs: int = roundi(float(stadium.fan_count) * Stadium.SIGN_SHARE)
	var apart: float = Stadium.SIGN_SPACING_SEATS * Stadium.SEAT_PITCH
	var nearest: float = INF
	for a: int in signs:
		for b: int in a:
			nearest = minf(nearest, stadium.sign_positions[a].distance_to(stadium.sign_positions[b]))
	print("Signs: %d of %d wanted.  The two nearest are %.1f yards apart (at least %.1f)." % [signs, wanted_signs, nearest, apart])
	if signs < wanted_signs - 3 or signs > wanted_signs:
		_failures.append("%d fans hold a sign, not the %d that SIGN_SHARE asks for" % [signs, wanted_signs])
	if nearest < apart:
		_failures.append("two signs are %.1f yards apart, nearer than %d seats (%.1f yards)" % [nearest, int(Stadium.SIGN_SPACING_SEATS), apart])
	var boards: int = 0
	for chunk: Node in stadium.get_node(^"Crowd").get_children():
		for child: Node in chunk.get_children():
			if String(child.name).begins_with("Signs"):
				boards += (child as MultiMeshInstance3D).multimesh.instance_count
	if boards != signs:
		_failures.append("sign_positions has %d signs, the MultiMeshes hold %d boards" % [signs, boards])

	var home_share: float = float(stadium.home_side_fans.x) / maxf(float(stadium.home_side_fans.y), 1.0)
	var away_share: float = 1.0 - float(stadium.away_side_fans.x) / maxf(float(stadium.away_side_fans.y), 1.0)
	if absf(home_share - tuning.crowd_home_share) > 0.03:
		_failures.append("home fans are %.2f of the home side, not %.2f" % [home_share, tuning.crowd_home_share])
	if absf(away_share - tuning.crowd_away_share) > 0.03:
		_failures.append("away fans are %.2f of the away side, not %.2f" % [away_share, tuning.crowd_away_share])

	# The audio's crowd reactions reach the stands.
	stadium.cheer = PackedFloat32Array([0.0, 0.0])
	stadium.slump = PackedFloat32Array([0.0, 0.0])
	game.audio.crowd_react(game.home, 1.0)
	if stadium.cheer[0] < 0.99 or stadium.slump[1] <= 0.0 or stadium.cheer[1] > 0.0:
		_failures.append("a home score did not get the home fans up and the visitors down: cheer %s slump %s" % [stadium.cheer, stadium.slump])
	await process_frame
	await process_frame
	if float(stadium._material.get_shader_parameter(&"cheer_home")) < 0.8:
		_failures.append("the cheer did not reach the crowd shader")
	game.audio.crowd_react(game.away, 0.9)
	if stadium.cheer[1] < 0.89 or stadium.slump[0] <= 0.0:
		_failures.append("an away score did not get the visitors up")
	game.audio.crowd_react(game.home, 0.1)
	if stadium.slump[0] <= 0.0:
		_failures.append("a small reaction was taken for a cheer")

	# A touchdown goes up on the jumbotrons.
	await process_frame
	game.home.score += tuning.touchdown_points
	await process_frame
	await process_frame
	var score_text: String = stadium._score_labels[0].text
	if not score_text.contains(str(game.home.score)) or not score_text.contains(game.home.short_name):
		_failures.append("the jumbotron says '%s' at %d-%d" % [score_text.replace("\n", " / "), game.home.score, game.away.score])
	if stadium._flash <= 0.0:
		_failures.append("no TOUCHDOWN! flash on the jumbotron")

	game.free()

	# On its own, with teams made up like the main menu's.
	var own: Tuning = tuning.duplicate() as Tuning
	own.wave_lap_time = 1.0
	own.crowd_density = 1.0
	var home: Team = Team.new()
	home.short_name = "HOME"
	home.team_color = Color(0.9, 0.8, 0.1)
	var away: Team = Team.new()
	away.short_name = "AWAY"
	away.team_color = Color(0.7, 0.1, 0.1)
	var alone: Stadium = Stadium.new()
	root.add_child(alone)
	alone.setup(own, home, away, true)
	var seats: int = alone.fan_count
	alone.react(true, 1.0)
	alone.start_wave()
	await process_frame
	await process_frame
	if float(alone._material.get_shader_parameter(&"wave_on")) <= 0.0 and alone.wave_progress < 0.1:
		_failures.append("the wave did not start")
	await _real_wait(6.0)
	if alone.cheer[0] > 0.0 or alone.slump[1] > 0.0:
		_failures.append("the cheer had not worn off after 6 s: cheer %s slump %s" % [alone.cheer, alone.slump])
	if alone.wave_progress >= 0.0 or float(alone._material.get_shader_parameter(&"wave_on")) > 0.0:
		_failures.append("the wave was still going after 6 laps' time")

	# The same seed seats the same crowd, another seed another one.
	var first: PackedVector3Array = alone.fan_positions.duplicate()
	var first_split: Vector2i = alone.home_side_fans
	own.crowd_density = 0.8
	alone.setup(own, home, away, true)
	var before: PackedVector3Array = alone.fan_positions.duplicate()
	var split: Vector2i = alone.home_side_fans
	alone.setup(own, home, away, true)
	if alone.fan_positions != before or alone.home_side_fans != split:
		_failures.append("the same crowd_seed gave two different crowds")
	own.crowd_seed += 1
	alone.setup(own, home, away, true)
	if alone.fan_positions == before:
		_failures.append("another crowd_seed gave the same crowd")
	if first.is_empty() or first_split.y == 0:
		_failures.append("the stadium on its own has no crowd")

	own.crowd_density = 0.5
	alone.setup(own, home, away, true)
	print("Seats: %d.  At half density: %d fans." % [seats, alone.fan_count])
	if absf(float(alone.fan_count) / maxf(float(seats), 1.0) - 0.5) > 0.03:
		_failures.append("half density gave %d fans of %d seats" % [alone.fan_count, seats])
	own.stadium_enabled = false
	alone.setup(own, home, away, true)
	await process_frame
	if alone.get_child_count() > 0 or alone.fan_count != 0:
		_failures.append("a switched-off stadium still has %d nodes and %d fans" % [alone.get_child_count(), alone.fan_count])
	alone.free()
	home.free()
	away.free()

	for failure: String in _failures:
		print("FAIL: %s" % failure)
	print("STADIUM CHECK PASSED" if _failures.is_empty() else "STADIUM CHECK FAILED")
	quit(0 if _failures.is_empty() else 1)


## Seconds by the wall clock, whatever the engine's own time is doing.
func _real_wait(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
