extends GameState
## Clock hit zero and the last play is over. The booth has its say about the
## game, then the pause menu comes up with the numbers and the way back to the
## main menu (see PauseMenu): Start does nothing here.

## Seconds the booth has been silent with nothing more to say.
var _quiet: float = 0.0
## The menu has come up: it does not come up a second time.
var _menu_shown: bool = false


func enter() -> void:
	var home: Team = game.home
	var away: Team = game.away
	var headline: String = "TIE GAME"
	if home.score != away.score:
		var winner: Team = home if home.score > away.score else away
		headline = "%s WIN!" % winner.short_name
	game.hud.show_banner(headline, "Final:  %s %d  -  %d %s" % [home.short_name, home.score, away.score, away.short_name])
	game.hud.set_hint("")
	_quiet = 0.0
	_menu_shown = false


func physics_update(delta: float) -> void:
	pc.simulate_dead(delta)
	var menu: PauseMenu = game.hud.pause_menu
	if _menu_shown or menu.is_open():
		return
	_quiet = 0.0 if game.audio.booth_pending() else _quiet + delta
	var tuning: Tuning = game.tuning
	var done: bool = time_in_state >= tuning.game_over_menu_min and _quiet >= tuning.game_over_menu_breath
	if done or time_in_state >= tuning.game_over_menu_max:
		_menu_shown = true
		game.hud.hide_banner()
		menu.open()


func hold_update(delta: float) -> void:
	pc.simulate_dead(delta)
