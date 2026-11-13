extends SceneTree
## Checks the comeback assist curve (RubberBand): nothing inside the dead zone,
## never shrinking as the gap grows, never past the caps, the right sign for
## each side, and nothing at all when it is switched off. Prints the table.
##
## Run:  godot --headless --path . --script res://tests/rubber_band_check.gd

const GAPS: Array[int] = [0, 7, 8, 14, 21, 28, 35]

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var tuning: Tuning = load("res://resources/tuning.tres") as Tuning
	print("gap   late  strength  trailing  leader")
	for late: float in [0.0, 1.0]:
		for gap: int in GAPS:
			var s: float = RubberBand.strength_for(gap, late, tuning)
			print("%3d   %4.1f  %8.3f  %+7.2f%%  %+6.2f%%" % [gap, late, s,
				RubberBand.modifier_for(-gap, late, tuning) * 100.0, RubberBand.modifier_for(gap, late, tuning) * 100.0])

	for late: float in [0.0, 0.5, 1.0]:
		var last: float = 0.0
		for gap: int in range(0, 61):
			var s: float = RubberBand.strength_for(gap, late, tuning)
			var boost: float = RubberBand.modifier_for(-gap, late, tuning)
			var penalty: float = RubberBand.modifier_for(gap, late, tuning)
			if gap <= tuning.comeback_dead_zone and (s != 0.0 or boost != 0.0 or penalty != 0.0):
				_failures.append("gap %d late %.1f is inside the dead zone but has an effect" % [gap, late])
			if s < last - 0.000001:
				_failures.append("strength drops at gap %d late %.1f" % [gap, late])
			last = s
			if s < 0.0 or s > 1.0:
				_failures.append("strength %.3f out of 0..1 at gap %d" % [s, gap])
			if boost < 0.0 or boost > tuning.comeback_max_boost + 0.000001:
				_failures.append("trailing modifier %.4f out of range at gap %d" % [boost, gap])
			if penalty > 0.0 or penalty < -tuning.comeback_max_penalty - 0.000001:
				_failures.append("leading modifier %.4f out of range at gap %d" % [penalty, gap])
		if absf(RubberBand.strength_for(tuning.comeback_full_gap, late, tuning) - 1.0) > 0.000001:
			_failures.append("not at full strength at comeback_full_gap (late %.1f)" % late)

	var off: Tuning = tuning.duplicate() as Tuning
	off.comeback_enabled = false
	for gap: int in GAPS:
		if RubberBand.modifier_for(-gap, 1.0, off) != 0.0 or RubberBand.modifier_for(gap, 1.0, off) != 0.0:
			_failures.append("switched off but gap %d still has an effect" % gap)

	if _failures.is_empty():
		print("RUBBER BAND CHECK PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("FAIL: ", failure)
		print("RUBBER BAND CHECK FAILED")
		quit(1)
