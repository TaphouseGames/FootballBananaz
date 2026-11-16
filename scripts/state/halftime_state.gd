extends GameState
## The first half's clock has run out and its last play is over. The halftime
## report comes up: the score, the teams' numbers and a word from Jim and Tony
## about the half (see HalftimeExchanges). After Tuning.halftime_show_time, or
## when (A) is pressed, the second half starts with a kickoff to the team that
## kicked off the first.
## With the report off, or the CPU playing both teams, it is just a banner.

## Seconds before a press of (A) counts, so one meant for the last play of the
## half does not skip the report.
const SKIP_AFTER: float = 0.5

var _card: HalftimeCard
var _exchange: Dictionary = {}
var _asked: bool = false


func enter() -> void:
	var home: Team = game.home
	var away: Team = game.away
	_card = null
	_exchange = {}
	_asked = false
	game.add_stat(&"halftimes")
	game.audio.play_music(&"music_halftime")
	game.hud.set_hint("")
	if not game.has_halftime_show():
		game.hud.show_banner("HALFTIME", "%s %d  -  %d %s" % [home.short_name, home.score, away.score, away.short_name])
		return
	game.hud.hide_banner()
	_exchange = HalftimeExchanges.pick(HalftimeExchanges.facts(game), game.tuning, _is_recorded)
	_card = game.hud.show_halftime()


func exit() -> void:
	game.audio.stop_music()
	game.hud.hide_banner()
	game.hud.hide_halftime()
	_card = null


func physics_update(delta: float) -> void:
	var tuning: Tuning = game.tuning
	pc.simulate_dead(delta)
	var done: bool = false
	if _card == null:
		done = time_in_state >= tuning.halftime_banner_time
	else:
		if not _asked and time_in_state >= tuning.halftime_voice_delay:
			_asked = true
			if not _exchange.is_empty():
				game.audio.play_show(_exchange[&"id"], _exchange[&"first"] == HalftimeExchanges.TONY)
		# Lets the booth finish the sentence, within reason.
		var talking: bool = _asked and game.audio.booth_busy()
		done = time_in_state >= tuning.halftime_show_max or (time_in_state >= tuning.halftime_show_time and not talking)
		if time_in_state >= SKIP_AFTER and Input.is_action_just_pressed(&"confirm"):
			done = true
		if done:
			game.audio.hush()
	if done:
		game.start_second_half()
		machine.transition(&"Kickoff")


func hold_update(delta: float) -> void:
	pc.simulate_dead(delta)


## There is a recording of every line of `exchange`.
func _is_recorded(exchange: Dictionary) -> bool:
	return game.audio.show_size(exchange[&"id"]) == (exchange[&"lines"] as Array).size()
