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
@export var qb_speed_scale: float = 0.94
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
## Human defender: Action dives if the carrier is within this range, otherwise shoves.
@export var dive_trigger_range: float = 6.5
@export var shove_radius: float = 2.0
## Minimum dot product between shove direction and the victim (cone width).
@export var shove_arc_dot: float = 0.15
@export var shove_time: float = 0.28
@export var shove_lunge_speed: float = 6.0
@export var shove_knockdown_impulse: float = 10.0
@export var juke_speed: float = 11.0
@export var juke_forward_scale: float = 0.75
@export var juke_time: float = 0.2
## Window in which tackles against a juking carrier mostly whiff.
@export var juke_evade_time: float = 0.34
@export var juke_cooldown: float = 0.9
@export var knockdown_time: float = 1.1
@export var knockdown_friction: float = 16.0

@export_group("Passing")
@export var pass_speed: float = 25.0
@export var pass_gravity: float = 22.0
@export var pass_release_height: float = 1.9
@export var pass_catch_height: float = 1.3
@export var pass_max_lead_time: float = 2.6
@export var catch_radius: float = 2.1
@export var catch_base_chance: float = 0.96
## Defenders closer than this to the receiver reduce the catch chance.
@export var cover_radius: float = 3.0
## Chance removed by one defender standing right on the receiver.
@export var cover_penalty: float = 0.5
@export var catch_min_chance: float = 0.12
@export var defender_catch_radius: float = 1.7
## Interception chance when the receiver fails the catch and a defender is at the ball.
@export var interception_chance: float = 0.3
## Interception chance when no receiver is near the ball at all.
@export var interception_chance_open: float = 0.75

@export_group("Tackling")
@export var tackle_radius: float = 1.1
@export var dive_tackle_radius: float = 1.5
@export var tackle_base_chance: float = 0.74
@export var dive_tackle_bonus: float = 0.2
## Multiplies tackle chance while the carrier's juke window is active.
@export var juke_tackle_scale: float = 0.2
@export var tackle_retry_time: float = 0.6
@export var broken_tackle_stun: float = 0.75
@export var tackle_knockdown_impulse: float = 8.0

@export_group("Blocking")
## Speed multiplier for a defender tied up by a blocker.
@export var block_slow_factor: float = 0.22
@export var block_shed_time_min: float = 1.3
@export var block_shed_time_max: float = 3.0
## How long a beaten blocker stays on the ground.
@export var block_beaten_time: float = 0.9
@export var block_immune_time: float = 1.2

@export_group("Impact Feel")
## Real-time seconds of hit-stop on a tackle.
@export var hit_stop_time: float = 0.09
@export var hit_stop_time_scale: float = 0.05
## Camera trauma (0..1) added per event.
@export var tackle_shake: float = 0.75
@export var shove_shake: float = 0.4
@export var shake_decay: float = 2.2
@export var shake_max_offset: float = 1.1

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
@export var ai_qb_open_distance: float = 3.5
@export var ai_qb_pressure_radius: float = 3.0
## Seconds after the snap before pass rushers start using turbo.
@export var ai_rush_turbo_delay: float = 2.0
## Seconds a man defender lags behind his receiver's movement.
@export var ai_cover_lag: float = 0.2
@export var ai_cover_cushion: float = 1.5
@export var ai_cover_speed_scale: float = 0.95
## Delay before defenders break on a thrown ball.
@export var ai_ball_react_time: float = 0.25
@export var ai_ball_react_radius: float = 14.0
## Max seconds ahead of the carrier a pursuer aims.
@export var ai_pursuit_max_lead: float = 1.5
@export var ai_turbo_range: float = 9.0
@export var ai_dive_range: float = 2.3
@export var ai_dive_chance: float = 0.6
@export var ai_juke_chance: float = 0.45
@export var ai_carrier_avoid_radius: float = 9.0
## Chance per second that a CPU player takes a cheap shot after the whistle.
@export var ai_late_hit_chance: float = 0.1

@export_group("Camera")
@export var camera_height: float = 27.0
@export var camera_distance: float = 36.0
@export var camera_fov: float = 40.0
@export var camera_follow_speed: float = 5.0
## Yards the camera looks ahead in the offense's direction.
@export var camera_lead: float = 5.0
@export var camera_z_follow: float = 0.35


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
