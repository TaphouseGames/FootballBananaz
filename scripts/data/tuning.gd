class_name Tuning
extends Resource
## Every gameplay-feel number in one place. Edit resources/tuning.tres in the inspector.
## Distances are yards (1 unit = 1 yard), times are seconds, speeds are yards/second.

@export_group("Field")
@export var field_length: float = 100.0
@export var end_zone_depth: float = 10.0
@export var field_width: float = 40.0
## Yard line (from own goal) where a new drive starts.
@export var drive_start_yard: float = 25.0
@export var touchback_yard: float = 20.0

@export_group("Rules")
@export var downs_per_series: int = 4
@export var yards_to_gain: float = 30.0
## Game clock in seconds. Only runs while the ball is live.
@export var game_length: float = 120.0
@export var touchdown_points: int = 6
@export var safety_points: int = 2

@export_group("Movement")
@export var run_speed: float = 7.6
@export var acceleration: float = 42.0
@export var deceleration: float = 55.0
@export var line_speed_scale: float = 0.86
## Pass rushers lined up within this many yards of the ball count as linemen.
@export var line_depth: float = 1.25
@export var carrier_speed_scale: float = 0.97
@export var player_radius: float = 0.5

@export_group("Turbo")
@export var turbo_speed_multiplier: float = 1.35
## Meter is 0..1. Units per second while held.
@export var turbo_drain: float = 0.42
@export var turbo_refill: float = 0.16
## After emptying the meter it must refill to this before turbo works again.
@export var turbo_restart_threshold: float = 0.2

@export_group("Actions")
@export var dive_speed: float = 13.5
@export var dive_time: float = 0.28
@export var dive_recover_time: float = 0.75
## Human defender: a dive auto-aims at the carrier (or late-hit victim) inside this range.
@export var dive_trigger_range: float = 6.5
@export var shove_radius: float = 2.0
## Minimum dot product between shove direction and the victim (cone width).
@export var shove_arc_dot: float = 0.15
@export var shove_time: float = 0.28
@export var shove_lunge_speed: float = 6.0
@export var shove_knockdown_impulse: float = 10.0
## Shared by spin and stiff arm: seconds before the next one of either kind.
@export var move_cooldown: float = 0.9
## A spin keeps the running line: no sidestep, no steering.
@export var spin_time: float = 0.4
## Window in which tackles against a spinning carrier mostly slide off.
@export var spin_evade_time: float = 0.45
@export var spin_speed_scale: float = 0.85
## How long the arm stays out. The carrier can still steer.
@export var stiff_arm_time: float = 0.5
@export var stiff_arm_speed_scale: float = 0.9
@export var knockdown_time: float = 1.1
@export var knockdown_friction: float = 16.0

@export_group("Jump")
@export var jump_time: float = 0.45
@export var jump_height: float = 1.3
## Seconds after landing before the next jump.
@export var jump_cooldown: float = 0.35
## Catch and interception radius multiplier for a player in the air.
@export var jump_catch_radius_scale: float = 1.5

@export_group("Passing")
## Pass power runs from 0 (lob) to 1 (bullet) and sets the flat speed between
## these two. Gravity is fixed, so a slower pass flies longer and arcs higher.
@export var pass_lob_speed: float = 16.0
@export var pass_bullet_speed: float = 32.0
## Holding a pass button this long or less is a tap: power 0.
@export var pass_tap_time: float = 0.12
## Holding this long is full power; the ball is thrown without waiting for release.
@export var pass_charge_time: float = 0.45
@export var pass_gravity: float = 22.0
@export var pass_release_height: float = 1.9
@export var pass_catch_height: float = 1.3
@export var pass_max_lead_time: float = 2.6
## Throwing on the run (turbo held): the pass can miss by up to this many yards
## per yard thrown.
@export var pass_scramble_error: float = 0.18
## Seconds after letting go of turbo before the QB's feet are set again. 0 = at once.
@export var pass_set_feet_time: float = 0.25
@export var catch_radius: float = 2.1
@export var catch_base_chance: float = 0.96
## Defenders closer than this to the receiver reduce the catch chance.
@export var cover_radius: float = 3.0
## Chance removed by one defender standing right on the receiver.
@export var cover_penalty: float = 0.65
## Share of that penalty a receiver takes off by shielding the ball: he is
## standing still or coming back to it, and the defender is behind him.
@export var cover_shield: float = 0.4
@export var catch_min_chance: float = 0.12
@export var defender_catch_radius: float = 1.7
## Interception chance when the receiver fails the catch and a defender is at the ball.
@export var interception_chance: float = 0.18
## Interception chance when no receiver is near the ball at all.
@export var interception_chance_open: float = 0.5
## Chance removed by each defender in the air within reach of the ball.
@export var contest_penalty: float = 0.15

@export_group("Tackling")
@export var tackle_radius: float = 1.1
@export var dive_tackle_radius: float = 1.5
@export var tackle_base_chance: float = 0.74
@export var dive_tackle_bonus: float = 0.2
@export var tackle_retry_time: float = 0.6
## Tackle chance multiplier for a defender who is tied up by a blocker.
@export var blocked_tackle_scale: float = 0.5
@export var broken_tackle_stun: float = 0.75
@export var tackle_knockdown_impulse: float = 8.0

@export_group("Ratings")
## Each pair is the value for a player rated 0 and one rated 100; ratings in
## between blend linearly, so 50 sits halfway.
## Run speed multiplier.
@export var speed_scale_low: float = 0.88
@export var speed_scale_high: float = 1.12
## Turbo drain multiplier.
@export var endurance_drain_low: float = 1.5
@export var endurance_drain_high: float = 0.5
## Catch chance multiplier (interception chance too).
@export var catch_scale_low: float = 0.8
@export var catch_scale_high: float = 1.1
## Tackle chance multiplier while the carrier's spin window is active (juke rating).
@export var spin_tackle_scale_low: float = 0.4
@export var spin_tackle_scale_high: float = 0.08
## Tackle chance multiplier for a tackler who runs into a stiff arm (strength rating).
@export var stiff_arm_tackle_scale_low: float = 0.6
@export var stiff_arm_tackle_scale_high: float = 0.1
## Chance that a carrier in the air clears a diving tackler.
@export var hurdle_chance_low: float = 0.6
@export var hurdle_chance_high: float = 1.0
## Longest throw in yards. A pass aimed further comes up short.
@export var pass_range_low: float = 28.0
@export var pass_range_high: float = 62.0
## Bullet pass speed multiplier.
@export var pass_speed_scale_low: float = 0.85
@export var pass_speed_scale_high: float = 1.15
## Yards a pass can miss by per yard thrown, even with the feet set.
@export var accuracy_error_low: float = 0.08
@export var accuracy_error_high: float = 0.0
## Multiplies pass_scramble_error and pass_set_feet_time.
@export var agility_scale_low: float = 1.6
@export var agility_scale_high: float = 0.4
## Tackle chance multiplier from the carrier's strength.
@export var strength_tackle_scale_low: float = 1.1
@export var strength_tackle_scale_high: float = 0.9
## Tackle chance multiplier from the tackler's tackling rating.
@export var tackling_scale_low: float = 0.85
@export var tackling_scale_high: float = 1.15
## Multiplies the time it takes to shed a block: the blocker's blocking rating...
@export var blocking_shed_scale_low: float = 0.7
@export var blocking_shed_scale_high: float = 1.3
## ...and the strength of the man being blocked.
@export var strength_shed_scale_low: float = 1.3
@export var strength_shed_scale_high: float = 0.7
## Multiply block_pancake_chance: the blocker's blocking rating and the strength
## of the man he is blocking.
@export var pancake_blocking_scale_low: float = 0.4
@export var pancake_blocking_scale_high: float = 1.6
@export var pancake_strength_scale_low: float = 1.6
@export var pancake_strength_scale_high: float = 0.4
## Multiply ai_cover_lag and ai_cover_cut_slow: the defender's coverage rating...
@export var coverage_scale_low: float = 1.4
@export var coverage_scale_high: float = 0.6
## ...and the get-open rating of the receiver he is covering.
@export var get_open_scale_low: float = 0.7
@export var get_open_scale_high: float = 1.3
## Multiply ai_cover_bust_chance: the receiver's get-open rating and the
## defender's coverage rating.
@export var bust_get_open_scale_low: float = 0.4
@export var bust_get_open_scale_high: float = 1.6
@export var bust_coverage_scale_low: float = 1.6
@export var bust_coverage_scale_high: float = 0.4
## A receiver working open after his route: seconds between looks for a better
## spot, yards of error in judging each spot, and his speed multiplier.
@export var get_open_rethink_low: float = 1.0
@export var get_open_rethink_high: float = 0.3
@export var get_open_noise_low: float = 3.0
@export var get_open_noise_high: float = 0.0
@export var get_open_speed_scale_low: float = 0.7
@export var get_open_speed_scale_high: float = 1.0
## Seconds a wrapped-up carrier drags his tackler before going down. Negative
## counts as none, so only carriers stronger than average drag anyone.
@export var drag_time_low: float = -0.9
@export var drag_time_high: float = 0.9
## Chance that the drag ends with the tackler shaken off instead.
@export var shake_off_chance_low: float = -0.35
@export var shake_off_chance_high: float = 0.35

## Chance that a tackle knocks the ball loose.
@export var fumble_chance_low: float = 0.11
@export var fumble_chance_high: float = 0.01

@export_group("Fumbles")
## Multiplies the fumble chance on a dive or shove tackle.
@export var fumble_big_hit_scale: float = 1.5
## A fumble goes to a random player on his feet this close to the ball. With
## nobody there, the carrier falls on it and the play ends as a tackle.
@export var fumble_recover_radius: float = 4.0

@export_group("Dragging")
## Drags shorter than this do not happen: the carrier just goes down.
@export var drag_min_time: float = 0.2
## Multiplies the drag time after a dive or a shove.
@export var drag_big_hit_scale: float = 0.5
## Carrier speed multiplier with a tackler hanging on.
@export var drag_speed_scale: float = 0.38
## How far behind the carrier the tackler hangs.
@export var drag_hold_distance: float = 0.8

@export_group("Blocking")
## Speed multiplier for a defender tied up by a blocker.
@export var block_slow_factor: float = 0.22
@export var block_shed_time_min: float = 1.3
@export var block_shed_time_max: float = 3.0
## How long a beaten blocker stays on the ground.
@export var block_beaten_time: float = 0.9
@export var block_immune_time: float = 1.2
## Run plays only: chance, each time a block is made, that the blocker puts his
## man on the ground (before ratings), how far into the block it happens, and
## how long the defender stays down.
@export var block_pancake_chance: float = 0.1
@export var block_pancake_time_min: float = 0.2
@export var block_pancake_time_max: float = 0.7
@export var block_pancake_down_time: float = 2.5

@export_group("Impact Feel")
## Real-time seconds of hit-stop on a tackle.
@export var hit_stop_time: float = 0.09
@export var hit_stop_time_scale: float = 0.05
## Camera trauma (0..1) added per event.
@export var tackle_shake: float = 0.75
@export var shove_shake: float = 0.4
@export var shake_decay: float = 2.2
@export var shake_max_offset: float = 1.1

@export_group("Turf FX")
@export var blood_enabled: bool = true
## Drops sprayed by a tackle, and by a shove or dive that flattens someone.
@export var blood_drops_tackle: int = 22
@export var blood_drops_knockdown: int = 10
## Splats and marks kept on the field; the oldest is reused past this.
@export var max_blood_splats: int = 900
@export var max_footprints: int = 6000
## Distance run between cleat prints.
@export var footprint_stride: float = 0.9

@export_group("Play Flow")
@export var pre_snap_delay: float = 0.5
@export var cpu_snap_delay_min: float = 1.0
@export var cpu_snap_delay_max: float = 1.8
## Seconds after the whistle during which late hits are allowed.
@export var late_hit_window: float = 1.6
@export var scored_banner_time: float = 3.0
@export var turnover_banner_time: float = 2.2

@export_group("AI")
@export var ai_qb_min_time: float = 0.9
@export var ai_qb_max_time: float = 3.0
## Receiver counts as open when the nearest defender is at least this far away.
@export var ai_qb_open_distance: float = 2.6
@export var ai_qb_pressure_radius: float = 3.0
## Until this many seconds after the snap the CPU quarterback only looks at
## receivers at least `ai_qb_min_depth` yards downfield; after that (or under
## pressure) he will take a checkdown.
@export var ai_qb_checkdown_time: float = 2.0
@export var ai_qb_min_depth: float = 3.0
## Out of time with every receiver covered this tightly, the CPU quarterback
## tucks the ball and runs instead of forcing a throw.
@export var ai_qb_scramble_open: float = 2.0
## An open receiver at least this far away gets a lob to run under.
@export var ai_qb_lob_distance: float = 22.0
## ...as long as he is running downfield at least this fast and no defender
## within `ai_qb_lob_clear` yards of him is deeper than he is.
@export var ai_qb_lob_min_speed: float = 3.0
@export var ai_qb_lob_clear: float = 9.0
## Pass power the CPU uses for a lob, a regular pass and a bullet.
@export var ai_qb_lob_power: float = 0.0
@export var ai_qb_normal_power: float = 0.55
@export var ai_qb_bullet_power: float = 1.0
## Pass power for a long throw that is not safe to lob.
@export var ai_qb_drive_power: float = 0.85
## Seconds after the snap before pass rushers start using turbo.
@export var ai_rush_turbo_delay: float = 0.7
## Seconds a coverage defender takes to read a change in his receiver's movement.
@export var ai_cover_lag: float = 0.35
## Share of his speed a coverage defender loses for a moment when his receiver
## makes a full change of direction (less for a gentler cut).
@export var ai_cover_cut_slow: float = 0.8
## Seconds ahead of the receiver a coverage defender aims.
@export var ai_cover_lead: float = 0.15
## Yards a coverage defender stays on the deep side of his receiver.
@export var ai_cover_cushion: float = 1.2
@export var ai_cover_speed_scale: float = 1.0
## A defender uses turbo to recover once his receiver is this far past him,
## or this far away in any direction.
@export var ai_cover_beaten_depth: float = 1.0
@export var ai_cover_beaten_gap: float = 4.0
## Chance that a coverage defender bites on a sharp cut by his receiver, before
## the ratings of the two are applied.
@export var ai_cover_bust_chance: float = 0.16
## Seconds he chases the wrong way, and his speed multiplier while he does.
@export var ai_cover_bust_time: float = 1.0
@export var ai_cover_bust_speed: float = 0.6
## How sharp a cut has to be to count (1 = a full stop or start, 2 = a full
## turnaround), seconds before the same defender can be fooled again, and
## seconds after the snap before anyone can be.
@export var ai_cover_bust_surprise: float = 0.8
@export var ai_cover_bust_cooldown: float = 1.2
@export var ai_cover_bust_min_time: float = 0.6
## Seconds a receiver waits at the end of his route before he goes looking for
## open space, and how far away he looks.
@export var ai_get_open_delay: float = 2.0
@export var ai_get_open_radius: float = 5.0
## He keeps this far from other receivers, and avoids spots with a defender
## within `lane_width` yards of the line from the quarterback.
@export var ai_get_open_spacing: float = 6.0
@export var ai_get_open_lane_width: float = 1.5
@export var ai_get_open_lane_penalty: float = 2.0
## Zone defenders judge receivers by where they will be this many seconds on.
@export var ai_zone_anticipate: float = 0.5
## How far from the middle of his zone a defender goes to sit on a receiver (0..1).
@export var ai_zone_tightness: float = 0.85
## With the zone empty, how far he leans toward the nearest receiver (share of radius).
@export var ai_zone_lean: float = 0.35
## Yards a deep-zone defender stays behind the deepest receiver.
@export var ai_deep_cushion: float = 3.5
## A deep-zone defender comes no shallower than this share of his radius in
## front of the middle of his zone, however short the receivers stay.
@export var ai_deep_step_up: float = 0.4
## A receiver thrown to this many times in the last few passes is "hot": zone
## defenders pick him up from further away and prefer him over others.
@export var ai_hot_targets: int = 3
@export var ai_hot_memory: int = 5
@export var ai_hot_zone_scale: float = 1.5
@export var ai_hot_bonus: float = 6.0
## Seconds coverage defenders keep covering after a handoff before they read run.
@export var ai_run_read_time: float = 0.4
## Delay before defenders break on a thrown ball.
@export var ai_ball_react_time: float = 0.25
@export var ai_ball_react_radius: float = 14.0
## The closest few defenders who are within `radius` of the landing spot, and can
## get within `margin` yards of it in time, go for the ball; the rest run to cut
## off the catch.
@export var ai_ball_breakers: int = 2
@export var ai_ball_break_margin: float = 3.0
@export var ai_ball_break_radius: float = 9.0
## Yards downfield of the landing spot the others aim for.
@export var ai_ball_cut_off: float = 4.0
## A defender this close to the landing spot, this long before the ball arrives,
## may jump for it.
@export var ai_contest_range: float = 2.6
@export var ai_contest_time: float = 0.3
@export var ai_contest_chance: float = 0.6
## Max seconds ahead of the carrier a pursuer aims.
@export var ai_pursuit_max_lead: float = 1.5
@export var ai_turbo_range: float = 9.0
@export var ai_dive_range: float = 2.3
@export var ai_dive_chance: float = 0.6
## Chance that a CPU carrier answers a tackler straight ahead with a spin.
@export var ai_spin_chance: float = 0.45
## Chance that a CPU carrier stiff-arms a tackler closing from the side.
@export var ai_stiff_arm_chance: float = 0.45
## How far to the side the tackler must be (0 = straight ahead, 1 = level with him).
@export var ai_stiff_arm_side_dot: float = 0.6
## A CPU carrier dives when the goal line or the first-down marker is this close
## and a defender is nearer than the matching pressure distance.
@export var ai_dive_reach: float = 3.0
@export var ai_dive_goal_pressure: float = 2.6
@export var ai_dive_marker_pressure: float = 1.8
@export var ai_carrier_avoid_radius: float = 9.0
## Chance per second that a CPU player takes a cheap shot after the whistle.
@export var ai_late_hit_chance: float = 0.1

@export_group("Camera")
## The camera sits behind the followed player: this high and this far back.
@export var camera_height: float = 19.5
@export var camera_distance: float = 24.7
@export var camera_fov: float = 50.0
@export var camera_follow_speed: float = 5.0
## Yards in front of the followed player the camera aims at.
@export var camera_look_ahead: float = 9.0
## How much of the player's sideways position the camera follows (0..1).
@export var camera_z_follow: float = 0.85


func half_width() -> float:
	return field_width * 0.5


## X of the goal line a team attacking in `dir` is trying to reach.
func goal_x(dir: int) -> float:
	return field_length if dir > 0 else 0.0


## X of the goal line a team attacking in `dir` defends.
func own_goal_x(dir: int) -> float:
	return 0.0 if dir > 0 else field_length


## World X for "own N yard line" of a team attacking in `dir`.
func yard_to_x(dir: int, yard: float) -> float:
	return yard if dir > 0 else field_length - yard
