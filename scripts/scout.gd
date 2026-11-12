class_name Scout
extends RefCounted
## What a defense remembers about the offense it is facing: which plays it has
## called lately, who the ball went to and whether the quarterback kept it.
## PlayController asks at the line-up and adjusts the coverage, so the same play
## run the same way gets harder each time, and leaves something else open.

## Plays remembered per offense.
const MEMORY: int = 6
## Calls of one play within MEMORY that make it fully recognised (one call is
## never recognised).
const FULL_READ: int = 4
## Yards per call that make a repeated play worth stopping. One that gains less
## gets less attention.
const GOOD_GAIN: float = 8.0
## Scrambles within MEMORY that make a spy certain, and the yards a scramble
## must gain to count.
const SPY_SCRAMBLES: int = 3
const SCRAMBLE_GAIN: float = 2.0

## Per offensive team: its last plays, newest last. Each entry is
## { play: OffensePlay, target: int, scrambled: bool, gain: float }.
var _log: Dictionary[Team, Array] = {}


## Called at the whistle. `target` is the receiver thrown to (his place in the
## play's order of receivers), or -1 if there was no pass.
func record(team: Team, play: OffensePlay, target: int, scrambled: bool, gain: float) -> void:
	var log: Array = _log.get(team, [])
	log.append({"play": play, "target": target, "scrambled": scrambled, "gain": gain})
	while log.size() > MEMORY:
		log.pop_front()
	_log[team] = log


## How well the defense knows `play` by now: 0 = never or once seen, 1 = seen
## again and again, and gaining yards.
func recognition(team: Team, play: OffensePlay) -> float:
	var seen: int = 0
	var gain: float = 0.0
	for entry: Dictionary in _log.get(team, []):
		if entry["play"] == play:
			seen += 1
			gain += float(entry["gain"])
	if seen < 2:
		return 0.0
	var working: float = clampf(gain / float(seen) / GOOD_GAIN, 0.4, 1.0)
	return clampf(float(seen - 1) / float(FULL_READ - 1), 0.0, 1.0) * working


## The receiver `play` keeps going to: thrown to at least twice and on more
## than half of its passes. -1 if the ball is spread around.
func favourite(team: Team, play: OffensePlay) -> int:
	var counts: Dictionary[int, int] = {}
	var passes: int = 0
	for entry: Dictionary in _log.get(team, []):
		var target: int = entry["target"]
		if entry["play"] == play and target >= 0:
			passes += 1
			counts[target] = counts.get(target, 0) + 1
	for target: int in counts:
		if counts[target] >= 2 and counts[target] * 2 > passes:
			return target
	return -1


## How much the quarterback's legs worry the defense (0..1): the share of a
## spy-worthy number of scrambles it has seen lately.
func scramble_threat(team: Team) -> float:
	var scrambles: int = 0
	for entry: Dictionary in _log.get(team, []):
		if entry["scrambled"] and float(entry["gain"]) >= SCRAMBLE_GAIN:
			scrambles += 1
	return clampf(float(scrambles) / float(SPY_SCRAMBLES), 0.0, 1.0)
