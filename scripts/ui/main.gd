extends Control
## Playable prototype: spinning reels (reel_view.gd) of gem tiles over the shared SlotEngine.
## The math lives entirely in scripts/math.

const SlotEngine := preload("res://scripts/math/slot_engine.gd")
const Config := preload("res://scripts/math/slot_config.gd")
const ReelView := preload("res://scripts/ui/reel_view.gd")
const SymbolTile := preload("res://scripts/ui/symbol_tile.gd")
const WinLines := preload("res://scripts/ui/win_lines.gd")
const SoundBank := preload("res://scripts/audio/sound_bank.gd")
const Background := preload("res://scripts/ui/background.gd")
const GemArt := preload("res://scripts/ui/gem_art.gd")
const SessionClient := preload("res://scripts/net/session_client.gd")
const Paytable := preload("res://scripts/ui/paytable.gd")
const Money := preload("res://scripts/ui/money.gd")
const SoundButton := preload("res://scripts/ui/sound_button.gd")
const ChallengeView := preload("res://scripts/ui/challenge_view.gd")

# All money is in whole cents (play money): credits 34175 shows as $341.75.
const START_CREDITS := 100000  # $1,000, what the house starts (and refills) a player with
# user:// is %APPDATA%\Godot\app_userdata\Gemhalla on Windows, browser storage on the web.
const SAVE_PATH := "user://gemhalla_save.cfg"
# Server sessions each keep their own local save, so several tabs never overwrite each other.
const SESSION_SAVE_PATH := "user://gemhalla_save_%s.cfg"
# Bet = lines played x bet multiplier x denomination, like a Vegas cabinet.
# Like a cabinet: the coin (DENOM) sets the lines played, and so the minimum bet
# (1 credit per line, so MIN BET in credits equals the lines); the bet buttons along the
# bar multiply that and spin. [denomination in cents, lines]; every minimum is $0.25+.
const COINS := [[1, 25], [2, 25], [5, 25], [10, 25], [100, 5], [200, 5]]
const BET_MULTIPLIERS := [1, 2, 3, 5, 10]
const HINT_SWAP_SECONDS := 4.0  # the feature hint under the reels alternates this often
const CELL_SIZE := Vector2(170, 130)
const HS_STEP_DELAY := 0.35  # pause between Hold & Spin respins
const HS_SPIN_TIME := 0.7  # empty cells spin this long on each respin
const HS_LAND_STAGGER := 0.12  # delay between gems landing within one respin
const ANTICIPATION_TIME := 0.9  # extra spin on a reel that could complete a feature
const CELL_GAP := 6.0
const SPIN_TIME := 0.5  # all reels spin this long before the first one stops
const REEL_STAGGER := 0.2  # delay between reels stopping, left to right
const WIN_SHOW_ALL := 1.4  # all winning lines shown together for this long
const WIN_SHOW_EACH := 1.1  # then each win is shown alone for this long, on repeat

const GOLD := Color("f3c969")
const JACKPOT_COLORS := {
	"GRAND": Color("9b1c31"), "MAJOR": Color("5d2a8c"), "MINOR": Color("1f4f8f"), "MINI": Color("1d6b47"),
}

var engine: SlotEngine = SlotEngine.new()
var credits := START_CREDITS  # cents
var multiplier_index := 0
var denom_index := 0  # into COINS
var free_games_left := 0
var busy := false

var reels: Array = []  # one ReelView per reel
var win_lines: WinLines
# Bumped on every spin so an older win presentation knows to stop.
var _win_cycle_id := 0
var _count_tween: Tween
var _reels_spinning := false
var _slam := false  # set when the player presses a bet button / Space mid-spin
var jackpot_labels := {}
var celebration_dim: ColorRect
var celebration: VBoxContainer
var celebration_title: Label
var celebration_amount: Label
var sounds: SoundBank
var sound_button: SoundButton
var rules_button: Button
var paytable: Paytable
var _current_spin := {}  # the spin the reels are landing on, for landing sounds
var credits_label: Label
var bet_label: Label
var win_label: Label
var min_bet_label: Label
var message_label: Label
var multiplier_hint: Label
var feature_hint: Label
var line_plates: Array[Label] = []  # "25 LINES" on both sides of the reels
var denom_button: Button
var bet_buttons: Array[Button] = []  # one per BET_MULTIPLIERS entry
var _controls_enabled := true
var _hint_index := 0
var _preview_id := 0  # bumped so an older line preview knows to stop
var net: SessionClient
var session_label: Label
var _last_win := 0
var _spins := 0
var _pending_credits := -1  # credits the admin set mid-spin, applied when the spin ends
var _pending_clear_free := false  # ...and whether free games are cleared then too (a reset)
var challenge_view: ChallengeView
var _name_popup: Control  # the "name of the Player" popup while it's open


func _ready() -> void:
	GemArt.install()
	sounds = SoundBank.new()
	add_child(sounds)
	net = SessionClient.new()
	net.state_provider = _session_state
	add_child(net)
	net.welcomed.connect(_on_admin_credits.bind("Connected to the Gemhalla server."))
	net.credits_set.connect(_on_admin_credits.bind("Your credit was updated."))
	net.reset_requested.connect(_on_admin_reset)
	net.message_received.connect(func(text: String) -> void:
		sounds.play("click")
		_message(text))
	net.connection_changed.connect(func(_online: bool) -> void: _update_session_label())
	net.challenge_changed.connect(_on_challenge)
	net.jackpots_changed.connect(_on_shared_jackpots)
	engine.jackpot_claimed.connect(net.claim_jackpot)
	_build_ui()
	_update_session_label()
	# A server session without a player name loads its save once the name is known.
	var returning := false if net.needs_name() else _load_game()
	_refresh_meters()
	_set_controls_enabled(true)
	# Park the reels on a free random spin so the machine doesn't start blank.
	var spin := engine.spin_reels(total_bet())
	for reel in Config.REELS:
		reels[reel].pos = spin.stops[reel]
	_show_grid(spin)
	_message("Welcome back to Gemhalla." if returning else "Welcome to Gemhalla. Press SPIN or Space.")
	if net.needs_name():
		_ask_player_name()
	var hint_timer := Timer.new()
	hint_timer.wait_time = HINT_SWAP_SECONDS
	hint_timer.autostart = true
	hint_timer.timeout.connect(func() -> void:
		_hint_index += 1
		_refresh_hints())
	add_child(hint_timer)


## Space spins; keys 1-5 are the bet buttons (pick that bet and spin).
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_SPACE:
		_on_spin()
	elif key >= KEY_1 and key < KEY_1 + BET_MULTIPLIERS.size():
		_bet_and_spin(key - KEY_1)


## Cents bet on each played line: bet multiplier x denomination.
func line_bet() -> int:
	return BET_MULTIPLIERS[multiplier_index] * denomination()


func denomination() -> int:
	return COINS[denom_index][0]


## The coin decides how many lines are played.
func lines_played() -> int:
	return COINS[denom_index][1]


## The bet at x1 for this coin.
func min_bet() -> int:
	return denomination() * lines_played()


func total_bet() -> int:
	return line_bet() * lines_played()


# --- Game flow -------------------------------------------------------------

func _on_spin() -> void:
	if _name_popup != null or paytable.visible:
		return  # waiting for the player's name, or reading the pays
	if busy:
		# While the reels spin, a bet button / Space becomes a slam stop.
		if _reels_spinning:
			_slam = true
		return
	if challenge_view.is_blocking() or _challenge_locked():
		return  # a challenge countdown, "time's up", or its winner on screen
	var is_free := free_games_left > 0
	if is_free:
		free_games_left -= 1
	elif credits < total_bet():
		if challenge_view.phase == "running" and credits < COINS[0][0] * COINS[0][1]:
			# No refills in a challenge: that would be free money.
			_message("Out of credits for this challenge. Hang on for the results!")
			return
		# Play money: if even the smallest bet is out of reach, top the player back up.
		if credits < COINS[0][0] * COINS[0][1]:
			credits = START_CREDITS
			_refresh_meters()
			_save_game()
			net.report()
			_message("Out of credits. The hall refills you with %s." % Money.format(START_CREDITS))
		else:
			_message("Not enough credits. Lower your bet.")
		return
	else:
		credits -= total_bet()
		engine.contribute()
		net.contribute_jackpots(Config.PROGRESSIVE_RATES)

	busy = true
	_set_controls_enabled(false)
	_clear_wins()
	win_label.text = Money.format(0)
	_refresh_meters()
	net.report()  # busy: a finished challenge waits for this spin before naming the winner

	var force := net.take_forced()
	var spin := engine.spin_reels(total_bet(), force)
	await _spin_animation(spin)
	_show_grid(spin)
	if is_free and force.is_empty():  # a forced spin must land as the admin asked
		await _play_rune_storm(spin)
	var multiplier: int = Config.FREE_GAMES_MULTIPLIER if is_free else 1
	var result := engine.evaluate(spin, line_bet(), multiplier, lines_played(), is_free)
	var win: int = result.line_pay + result.scatter_pay

	var notes: Array[String] = []
	for line_win: Dictionary in result.line_wins:
		notes.append("%d x %s" % [line_win.count, Config.SYMBOL_NAMES[line_win.symbol].replace("\n", " ")])
	if result.free_games > 0:
		sounds.play("fanfare")
		free_games_left += result.free_games
		notes.append("%d FREE GAMES!" % result.free_games)

	if result.hold_and_spin:
		await get_tree().create_timer(0.4).timeout
		win += await _play_hold_and_spin(spin.orbs, spin.force_grand)
		_show_grid(spin)

	# Hold & Spin already celebrated its own win.
	if win > 0 and not result.hold_and_spin:
		sounds.play("big_win" if win >= 10 * total_bet() else "win")
	var credits_before := credits
	credits += win
	if _pending_credits >= 0:
		# The admin (or a challenge) set the credits during this spin: land on their amount.
		credits = _pending_credits
		credits_before = credits - win
		_pending_credits = -1
		if _pending_clear_free:
			free_games_left = 0
			_pending_clear_free = false
	if win > 0 and notes.is_empty():
		notes.append("Hold & Spin paid %s" % Money.format(win))
	_message(", ".join(notes) if not notes.is_empty() else "No win.")
	_refresh_meters()
	_count_up(credits_before, win)
	_save_game()
	_last_win = win
	_spins += 1
	net.report()
	busy = false
	_set_controls_enabled(true)
	_present_wins(result, spin)


## Rune Storm, in free games: lightning strikes some of the landed cells into Rune Gems,
## which can set off Hold & Spin.
func _play_rune_storm(spin: Dictionary) -> void:
	var struck := engine.rune_storm(spin, total_bet())
	if struck.is_empty():
		return
	_message("RUNE STORM!")
	await get_tree().create_timer(0.2).timeout
	for pos: Vector2i in struck:
		win_lines.strike_cell(pos.x, pos.y)
		sounds.play("firework", 0.7, -8.0)  # lowered, it's the thunder
		_set_orb_cell(pos, spin.orbs[pos])
		_pop(_tile(pos))
		await get_tree().create_timer(0.22).timeout
	await get_tree().create_timer(0.3).timeout


# --- Win presentation ------------------------------------------------------

## Shows every win together, then cycles through them one at a time until the next spin.
func _present_wins(result: Dictionary, spin: Dictionary) -> void:
	var cycle := _win_cycle_id
	var steps: Array = []  # each: [cells, line wins to draw, message]
	var all_cells: Array = []
	for line_win: Dictionary in result.line_wins:
		var cells := _line_cells(line_win)
		all_cells.append_array(cells)
		var symbol_name: String = Config.SYMBOL_NAMES[line_win.symbol].replace("\n", " ")
		steps.append([cells, [line_win], "Line %d: %d x %s pays %s" % [line_win.line + 1, line_win.count, symbol_name, Money.format(line_win.pay)]])
	if result.scatter_pay > 0:
		var cells: Array = []
		for reel in Config.REELS:
			for row in Config.ROWS:
				if spin.grid[reel][row] == Config.SCATTER:
					cells.append(Vector2i(reel, row))
		all_cells.append_array(cells)
		steps.append([cells, [], "%d VAULTS pay %s" % [result.scatters, Money.format(result.scatter_pay)]])
	if steps.is_empty():
		return

	_highlight(all_cells)
	win_lines.show_lines(result.line_wins)
	await get_tree().create_timer(WIN_SHOW_ALL).timeout
	if steps.size() == 1:
		return
	while cycle == _win_cycle_id:
		for step: Array in steps:
			if cycle != _win_cycle_id:
				return
			_highlight(step[0])
			win_lines.show_lines(step[1])
			_message(step[2])
			await get_tree().create_timer(WIN_SHOW_EACH).timeout


func _line_cells(line_win: Dictionary) -> Array:
	var rows: Array = Config.PAYLINES[line_win.line]
	var cells: Array = []
	for reel in line_win.count:
		cells.append(Vector2i(reel, rows[reel]))
	return cells


## Lights up `cells` and dims every other tile.
func _highlight(cells: Array) -> void:
	for reel in Config.REELS:
		for row in Config.ROWS:
			var pos := Vector2i(reel, row)
			_tile(pos).set_win_state(SymbolTile.WinState.WIN if cells.has(pos) else SymbolTile.WinState.DIM)


func _clear_wins() -> void:
	_win_cycle_id += 1
	if _count_tween:
		_count_tween.kill()
	sounds.stop_loop("coin_tick")
	win_lines.clear()
	for reel in Config.REELS:
		for row in Config.ROWS:
			_tile(Vector2i(reel, row)).set_win_state(SymbolTile.WinState.NORMAL)


## Rolls the WIN and CREDITS meters up; bigger wins (relative to the bet) roll longer.
func _count_up(credits_before: int, win: int) -> void:
	if win <= 0:
		return
	var seconds := clampf(0.4 + float(win) / total_bet() * 0.08, 0.4, 3.0)
	_count_tween = create_tween()
	_count_tween.tween_method(_show_count.bind(credits_before), 0.0, float(win), seconds)
	sounds.start_loop("coin_tick", -10.0)
	_count_tween.finished.connect(func() -> void: sounds.stop_loop("coin_tick"))


func _show_count(amount: float, credits_before: int) -> void:
	win_label.text = Money.format(int(amount))
	credits_label.text = Money.format(credits_before + int(amount))


## Spins every reel, then stops them left to right on the engine's result. A reel that
## could still complete a feature gets an anticipation spin; any bet button or Space
## slams them all.
func _spin_animation(spin: Dictionary) -> void:
	_slam = false
	_reels_spinning = true
	_current_spin = spin
	_update_bet_buttons()  # live again, as STOP
	sounds.start_loop("reel_spin", -8.0)
	for reel: ReelView in reels:
		reel.start_spin()
	await _wait_unless_slammed(SPIN_TIME)
	var orbs_seen := 0
	var scatters_seen := 0
	for i in reels.size():
		var reel: ReelView = reels[i]
		if i > 0:
			await _wait_unless_slammed(REEL_STAGGER)
		if not _slam and _near_feature(orbs_seen, scatters_seen):
			reel.set_anticipation(true)
			sounds.play("anticipation", 1.0, -3.0)
			await _wait_unless_slammed(ANTICIPATION_TIME)
			reel.set_anticipation(false)
		reel.stop_at(spin.stops[i], _slam)
		# Anticipation only reacts to what has visibly landed, like a real machine.
		var column: Array = spin.grid[i]
		orbs_seen += column.count(Config.ORB)
		scatters_seen += column.count(Config.SCATTER)
	_reels_spinning = false
	_refresh_meters()
	await reels[-1].stopped
	sounds.stop_loop("reel_spin")


## Thunk for every reel, plus a chime for Rune Gems (climbing in pitch as more land
## across the reels) and a bell for Vaults.
func _on_reel_stopped(reel: int) -> void:
	sounds.play("reel_stop", randf_range(0.95, 1.05), -2.0)
	if _current_spin.is_empty():
		return
	var column: Array = _current_spin.grid[reel]
	if column.has(Config.ORB):
		var gems := 0
		for r in reel + 1:
			gems += _current_spin.grid[r].count(Config.ORB)
		sounds.play("gem_land", SoundBank.scale_step(gems - 1))
	if column.has(Config.SCATTER):
		sounds.play("vault")


## True when the landed reels are close to a feature: 2 Vaults, or 4-5 Rune Gems.
func _near_feature(orbs: int, scatters: int) -> bool:
	return scatters == 2 or (orbs >= Config.HS_TRIGGER_COUNT - 2 and orbs < Config.HS_TRIGGER_COUNT)


func _wait_unless_slammed(seconds: float) -> void:
	var end_ms := Time.get_ticks_msec() + int(seconds * 1000)
	while not _slam and Time.get_ticks_msec() < end_ms:
		await get_tree().process_frame


## Plays back the engine's Hold & Spin result: locked gems framed in gold, empty cells
## spinning on each respin, new gems popping in, then jackpot and total celebrations.
## Returns the total won.
func _play_hold_and_spin(start_orbs: Dictionary, force_grand: bool = false) -> int:
	var hs := engine.play_hold_and_spin(start_orbs, total_bet(), force_grand)
	sounds.play("fanfare")
	await _celebrate("HOLD & SPIN", -1, 1.4)

	var locked := {}
	var running := 0
	for reel in Config.REELS:
		for row in Config.ROWS:
			var pos := Vector2i(reel, row)
			if start_orbs.has(pos):
				locked[pos] = start_orbs[pos]
				_set_orb_cell(pos, start_orbs[pos])
				_tile(pos).set_win_state(SymbolTile.WinState.WIN)
				if start_orbs[pos].kind == "CREDIT":
					running += start_orbs[pos].amount
			else:
				_tile(pos).show_symbol("")
	_set_message_big(true)
	var respins := Config.HS_RESPINS
	_hs_status(respins, running)

	for step: Dictionary in hs.steps:
		await get_tree().create_timer(HS_STEP_DELAY).timeout
		respins -= 1
		_hs_status(respins, running)
		sounds.play("whoosh", 1.0, -4.0)
		var empties: Array = []
		for reel in Config.REELS:
			for row in Config.ROWS:
				var pos := Vector2i(reel, row)
				if not locked.has(pos):
					empties.append(pos)
					_tile(pos).show_symbol(SymbolTile.SPINNING)
		await get_tree().create_timer(HS_SPIN_TIME).timeout
		for pos: Vector2i in empties:
			if not step.landed.has(pos):
				_tile(pos).show_symbol("")
				continue
			var orb: Dictionary = step.landed[pos]
			locked[pos] = orb
			_set_orb_cell(pos, orb)
			_tile(pos).set_win_state(SymbolTile.WinState.WIN)
			_pop(_tile(pos))
			# Each new gem chimes a step higher up the scale than the last.
			sounds.play("gem_land", SoundBank.scale_step(locked.size() - Config.HS_TRIGGER_COUNT))
			if orb.kind == "CREDIT":
				running += orb.amount
			_hs_status(Config.HS_RESPINS, running)
			await get_tree().create_timer(HS_LAND_STAGGER).timeout
		respins = step.respins_left
		_hs_status(respins, running)

	await get_tree().create_timer(0.6).timeout
	for jackpot: Dictionary in hs.jackpot_wins:
		_flash_meter(jackpot.kind)
		sounds.play("jackpot")
		await _celebrate("%s JACKPOT!" % jackpot.kind, jackpot.amount, 2.4)
	sounds.play("big_win")
	await _celebrate("HOLD & SPIN WIN", hs.total, 2.4)
	_set_message_big(false)
	for reel in Config.REELS:
		for row in Config.ROWS:
			_tile(Vector2i(reel, row)).set_win_state(SymbolTile.WinState.NORMAL)
	return hs.total


func _hs_status(respins: int, running: int) -> void:
	_message("RESPINS LEFT  %d          COLLECTED  %s" % [respins, Money.format(running)])


func _set_message_big(big: bool) -> void:
	message_label.add_theme_font_size_override("font_size", 30 if big else 20)
	message_label.add_theme_color_override("font_color", GOLD if big else Color.WHITE)


## A landing gem starts oversized and springs down to normal size.
func _pop(tile: Control) -> void:
	tile.pivot_offset = tile.size / 2
	tile.scale = Vector2(1.3, 1.3)
	create_tween().tween_property(tile, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash_meter(kind: String) -> void:
	var label: Label = jackpot_labels.get(kind)
	if label == null:
		return
	var tween := create_tween().set_loops(6)
	tween.tween_property(label, "modulate", Color(2.2, 2.2, 2.2), 0.15)
	tween.tween_property(label, "modulate", Color.WHITE, 0.15)


## Full-screen banner: title springs in, amount counts up (pass amount < 0 for none).
func _celebrate(title: String, amount: int, seconds: float) -> void:
	celebration_title.text = title
	celebration_amount.text = ""
	celebration_amount.visible = amount >= 0
	celebration_dim.visible = true
	celebration.visible = true
	celebration.pivot_offset = celebration.size / 2
	celebration.scale = Vector2(0.5, 0.5)
	celebration.modulate.a = 0.0
	celebration_dim.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(celebration_dim, "modulate:a", 1.0, 0.2)
	tween.tween_property(celebration, "modulate:a", 1.0, 0.2)
	tween.tween_property(celebration, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if amount >= 0:
		tween.tween_method(func(v: float) -> void: celebration_amount.text = Money.format(int(v)), 0.0, float(amount), minf(seconds * 0.6, 1.8))
	await get_tree().create_timer(seconds).timeout
	var fade := create_tween().set_parallel()
	fade.tween_property(celebration_dim, "modulate:a", 0.0, 0.25)
	fade.tween_property(celebration, "modulate:a", 0.0, 0.25)
	await fade.finished
	celebration_dim.visible = false
	celebration.visible = false


## A bet button, as on a cabinet's button panel: picks that multiple of the minimum
## bet and spins. (During free games the bet is locked, so it just spins.)
func _bet_and_spin(index: int) -> void:
	if busy:
		_on_spin()  # STOP while the reels spin
		return
	if _name_popup != null or paytable.visible:
		return
	if free_games_left == 0 and index != multiplier_index:
		multiplier_index = index
		_bet_changed()
	_on_spin()


## The denomination button steps through the coins and wraps around, like a cabinet's.
## The coin sets the lines, so they flash up when they change.
func _cycle_denomination() -> void:
	var old_lines := lines_played()
	denom_index = (denom_index + 1) % COINS.size()
	_bet_changed()
	if lines_played() != old_lines:
		_preview_lines()


func _bet_changed() -> void:
	sounds.play("click")
	_refresh_meters()
	_save_game()
	net.report()


## Shows the lines now being played for a moment, as a cabinet does when you change them.
func _preview_lines() -> void:
	_clear_wins()
	_preview_id += 1
	var preview := _preview_id
	var lines: Array = []
	for i in lines_played():
		lines.append({"line": i})
	win_lines.show_lines(lines)
	await get_tree().create_timer(1.2).timeout
	if preview == _preview_id and not busy:
		win_lines.clear()


# --- Server session (admin page) ------------------------------------------

## The state the admin page shows for this session.
func _session_state() -> Dictionary:
	return {"credits": credits, "bet": total_bet(), "free_games": free_games_left, "last_win": _last_win,
		"spins": _spins, "busy": busy}


## The admin set this session's credits (the server also sends them on connect, since
## it is the authority for a session's credits). Mid-spin, they apply when it ends.
func _on_admin_credits(amount: int, note: String) -> void:
	if busy:
		_pending_credits = amount
		return
	credits = amount
	_refresh_meters()
	_save_game()
	_message(note)
	net.report()


func _on_admin_reset(amount: int) -> void:
	_house_reset(amount, "Your session was reset.")


## Credits back to `amount` and no free games left (mid-spin: when the spin ends).
func _house_reset(amount: int, note: String) -> void:
	if busy:
		_pending_credits = amount
		_pending_clear_free = true
		return
	credits = amount
	free_games_left = 0
	_refresh_meters()
	_set_controls_enabled(true)
	_save_game()
	_message(note)
	net.report()


## The server's linked jackpot meters. Mid-spin the display waits, so a jackpot just won
## doesn't visibly drop before its celebration; the spin's end refreshes it.
func _on_shared_jackpots(meters: Dictionary) -> void:
	for kind: String in engine.progressive:
		if meters.has(kind):
			engine.progressive[kind] = maxf(float(meters[kind]), 0.0)
	if not busy:
		_refresh_jackpots()


## The timed challenge changed (server/Challenge.cs): the countdown locks play, the start
## and the results put everyone on the house default, "time's up" locks play again.
func _on_challenge(info: Dictionary) -> void:
	var was := challenge_view.phase
	challenge_view.show_info(info, net.session_id)
	var phase: String = info.get("phase", "idle")
	if info.has("credits"):
		var note: String = {
			"running": "The challenge is on! Most money when time runs out wins.",
			"results": "The challenge is over. Everyone is back to %s." % Money.format(int(info.credits)),
		}.get(phase, "The challenge was cancelled.")
		_house_reset(int(info.credits), note)
	if phase == "running" and was != "running":
		sounds.play("fanfare")
	elif phase == "ended" and was != "ended":
		sounds.play("reel_stop")
		_message("Time's up!")
	elif phase == "idle" and info.get("cancelled", false):
		_message("The challenge was cancelled.")
	_update_bet_buttons()


## A challenge is counting down or waiting for results: no new spins.
func _challenge_locked() -> bool:
	return challenge_view.phase in ["countdown", "ended"]


func _update_session_label() -> void:
	session_label.visible = net.is_enabled() and not net.needs_name()
	# Plain text only: the default font has no dot/bullet glyphs.
	if net.online:
		session_label.text = "SESSION  %s  -  ONLINE" % net.session_id
		session_label.add_theme_color_override("font_color", Color("6fe39a"))
	else:
		session_label.text = "SESSION  %s  -  connecting..." % net.session_id
		session_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))


## Asks for the player's name; the session is titled with it. Play is blocked until then.
func _ask_player_name() -> void:
	_set_controls_enabled(false)
	_name_popup = Control.new()
	_name_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_name_popup)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_popup.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_popup.add_child(center)
	var panel := PanelContainer.new()
	var style := _frame_style()
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(_make_label("What is the name of the Player?", 26, GOLD))
	var field := LineEdit.new()
	field.placeholder_text = "Player name"
	field.max_length = 32
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.custom_minimum_size = Vector2(380, 50)
	field.add_theme_font_size_override("font_size", 22)
	box.add_child(field)
	var hint := _make_label("", 15, Color("ff8fa3"))
	box.add_child(hint)
	var play := _make_button("PLAY", Callable())
	play.custom_minimum_size = Vector2(200, 58)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_spin_button(play)
	box.add_child(play)

	var submit := func() -> void:
		if not net.start(field.text):
			hint.text = "Please use letters or numbers."
			return
		sounds.play("click")
		_name_popup.queue_free()
		_name_popup = null
		_load_game()
		_refresh_meters()
		_set_controls_enabled(true)
		_update_session_label()
		_message("Welcome to Gemhalla, %s! Press SPIN or Space." % net.session_id)
	field.text_submitted.connect(func(_text: String) -> void: submit.call())
	play.pressed.connect(submit)
	field.grab_focus.call_deferred()


func _save_path() -> String:
	return SESSION_SAVE_PATH % net.session_id if net.is_enabled() else SAVE_PATH


## Opens the GAME RULES screen with pays at the current bet and live jackpot values.
func _open_paytable() -> void:
	if busy:
		return
	sounds.play("click")
	var jackpots := {}
	for kind: String in Config.JACKPOTS:
		jackpots[kind] = engine.jackpot_value(kind, total_bet())
	paytable.open(line_bet(), lines_played(), BET_MULTIPLIERS[multiplier_index], denomination(), jackpots, COINS)


func _toggle_sound() -> void:
	sounds.muted = not sounds.muted
	sounds.play("click")
	_update_sound_button()
	_save_game()


func _update_sound_button() -> void:
	sound_button.sound_on = not sounds.muted


# --- Save / load -----------------------------------------------------------

## Restores credits, bet, pending free games and the progressive meters.
## Returns false when there is no save yet (first launch).
func _load_game() -> bool:
	var file := ConfigFile.new()
	if file.load(_save_path()) != OK:
		return false
	credits = maxi(int(file.get_value("player", "credits", START_CREDITS)), 0)
	multiplier_index = clampi(int(file.get_value("player", "multiplier_index", 0)), 0, BET_MULTIPLIERS.size() - 1)
	# Saved as the coin's value, so changing the coin list never shifts a player's coin.
	var coin := int(file.get_value("player", "denomination", COINS[0][0]))
	denom_index = 0
	for i in COINS.size():
		if COINS[i][0] == coin:
			denom_index = i
	free_games_left = maxi(int(file.get_value("player", "free_games_left", 0)), 0)
	if not net.is_enabled():  # on the server, the meters are shared and come from it
		for kind: String in engine.progressive:
			engine.progressive[kind] = maxf(float(file.get_value("jackpots", kind, 0.0)), 0.0)
	sounds.muted = bool(file.get_value("settings", "muted", false))
	_update_sound_button()
	return true


## Called after every spin and bet change. A spin interrupted by quitting is never
## saved, so the player just keeps the credits they had before it.
func _save_game() -> void:
	if net.needs_name():
		return  # no player yet, so nothing to save under
	var file := ConfigFile.new()
	file.set_value("player", "credits", credits)
	file.set_value("player", "multiplier_index", multiplier_index)
	file.set_value("player", "denomination", denomination())
	file.set_value("player", "free_games_left", free_games_left)
	for kind: String in engine.progressive:
		file.set_value("jackpots", kind, engine.progressive[kind])
	file.set_value("settings", "muted", sounds.muted)
	var err := file.save(_save_path())
	if err != OK:
		push_warning("Could not save game: %s" % error_string(err))


# --- Display ---------------------------------------------------------------

func _show_grid(spin: Dictionary) -> void:
	for reel in Config.REELS:
		for row in Config.ROWS:
			var pos := Vector2i(reel, row)
			var symbol: String = spin.grid[reel][row]
			if symbol == Config.ORB:
				_set_orb_cell(pos, spin.orbs[pos])
			else:
				_tile(pos).show_symbol(symbol)


## Rune gems show their cash value or jackpot name.
func _set_orb_cell(pos: Vector2i, orb: Dictionary) -> void:
	var text: String = orb.kind if orb.kind != "CREDIT" else Money.short(orb.amount)
	_tile(pos).show_symbol(Config.ORB, text)


func _tile(pos: Vector2i) -> SymbolTile:
	return reels[pos.x].tile(pos.y)


func _refresh_jackpots() -> void:
	for kind: String in jackpot_labels:
		jackpot_labels[kind].text = "%s\n%s" % [kind, Money.format(engine.jackpot_value(kind, total_bet()))]


func _refresh_meters() -> void:
	_refresh_jackpots()
	credits_label.text = Money.format(credits)
	bet_label.text = Money.format(total_bet())
	denom_button.text = Money.denomination(denomination())
	# In credits, as the cabinet shows it: one credit a line, so it reads as the lines.
	min_bet_label.text = "MIN BET %d" % lines_played()
	min_bet_label.tooltip_text = "%d credits of %s = %s" % [lines_played(), Money.denomination(denomination()), Money.format(min_bet())]
	for plate in line_plates:
		plate.text = "%d\nLINE%s" % [lines_played(), "" if lines_played() == 1 else "S"]
	_refresh_hints()
	_update_bet_buttons()


## Under the reels, as on a cabinet: the bet multiplier on the left, and on the right a
## reminder of how the features start (or the free games multiplier while they play).
func _refresh_hints() -> void:
	multiplier_hint.text = "BET MULTIPLIER  x%d" % BET_MULTIPLIERS[multiplier_index]
	if free_games_left > 0:
		feature_hint.text = "RUNE STORM  -  WINS PAY x%d" % Config.FREE_GAMES_MULTIPLIER
	elif _hint_index % 2 == 0:
		feature_hint.text = "3 VAULTS START FREE GAMES"
	else:
		feature_hint.text = "%d RUNE GEMS START HOLD & SPIN" % Config.HS_TRIGGER_COUNT


func _message(text: String) -> void:
	message_label.text = text


func _set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	rules_button.disabled = not enabled
	_update_bet_buttons()


## The bet buttons are also SPIN (there is no separate one): the selected one is lit
## gold, reads STOP while the reels spin (any of them slams the reels), and during free
## games it plays the next one while the others are locked, so they play at the bet that
## won them.
func _update_bet_buttons() -> void:
	var free := free_games_left > 0
	var playable := _controls_enabled and not (challenge_view != null and _challenge_locked())
	denom_button.disabled = not playable or free
	for i in bet_buttons.size():
		var selected := i == multiplier_index
		if _reels_spinning:
			bet_buttons[i].disabled = false
		else:
			bet_buttons[i].disabled = not playable or (free and not selected)
		if selected and _reels_spinning:
			bet_buttons[i].text = "STOP"
		elif selected and free:
			bet_buttons[i].text = "FREE GAME\n%d LEFT" % free_games_left
		else:
			bet_buttons[i].text = "x%d\n%s" % [BET_MULTIPLIERS[i], Money.format(min_bet() * BET_MULTIPLIERS[i])]
		_style_bet_button(bet_buttons[i], i == multiplier_index)


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	theme = _make_theme()
	var bg := Background.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := _make_label("GEMHALLA", 46, GOLD)
	title.add_theme_color_override("font_outline_color", Color("5a3200"))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0.6, 0.3, 1.0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 16)
	root.add_child(title)

	var meters := HBoxContainer.new()
	meters.alignment = BoxContainer.ALIGNMENT_CENTER
	meters.add_theme_constant_override("separation", 16)
	root.add_child(meters)
	for kind: String in ["GRAND", "MAJOR", "MINOR", "MINI"]:
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", _plate_style(JACKPOT_COLORS[kind]))
		plate.custom_minimum_size = Vector2(176, 0)
		var label := _make_label("", 18, Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override("outline_size", 4)
		plate.add_child(label)
		meters.add_child(plate)
		jackpot_labels[kind] = label

	# Gold frame around the reels, with "N LINES" plates on both sides.
	var reel_row_outer := HBoxContainer.new()
	reel_row_outer.alignment = BoxContainer.ALIGNMENT_CENTER
	reel_row_outer.add_theme_constant_override("separation", 12)
	root.add_child(reel_row_outer)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _frame_style())
	reel_row_outer.add_child(_line_plate())
	reel_row_outer.add_child(frame)
	reel_row_outer.add_child(_line_plate())
	# The reels and the payline overlay share one area so lines line up with cells.
	var reel_area := Control.new()
	reel_area.custom_minimum_size = Vector2(
		CELL_SIZE.x * Config.REELS + CELL_GAP * (Config.REELS - 1),
		CELL_SIZE.y * Config.ROWS + CELL_GAP * (Config.ROWS - 1))
	frame.add_child(reel_area)
	var reel_row := HBoxContainer.new()
	reel_row.add_theme_constant_override("separation", int(CELL_GAP))
	reel_area.add_child(reel_row)
	for reel in Config.REELS:
		var view := ReelView.new()
		view.setup(engine.strips[reel], CELL_SIZE, CELL_GAP, 0)
		view.stopped.connect(_on_reel_stopped.bind(reel))
		reel_row.add_child(view)
		reels.append(view)
	win_lines = WinLines.new()
	win_lines.setup(CELL_SIZE, CELL_GAP)
	win_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	reel_area.add_child(win_lines)

	# Message in the middle, cabinet-style hints at each side, under the reels.
	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", 10)
	root.add_child(under)
	var edge := Control.new()
	edge.custom_minimum_size = Vector2(14, 0)
	under.add_child(edge)
	multiplier_hint = _make_label("", 15, GOLD)
	multiplier_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	multiplier_hint.custom_minimum_size = Vector2(270, 0)
	under.add_child(multiplier_hint)
	message_label = _make_label("", 20, Color.WHITE)
	# Fixed height so the larger Hold & Spin counter doesn't shift the layout.
	message_label.custom_minimum_size = Vector2(0, 44)
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.clip_text = true
	under.add_child(message_label)
	feature_hint = _make_label("", 15, GOLD)
	feature_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feature_hint.custom_minimum_size = Vector2(270, 0)
	under.add_child(feature_hint)
	under.add_child(edge.duplicate())

	# The bet bar, cabinet style: DENOM (with its minimum bet), CREDIT, BET, WIN, then
	# the bet buttons (each picks a multiple of the minimum bet and spins; no SPIN button).
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	root.add_child(bar)
	denom_button = _make_button("", _cycle_denomination)
	denom_button.custom_minimum_size = Vector2(72, 40)
	denom_button.add_theme_color_override("font_color", GOLD)
	var denom_box := _captioned("DENOM", denom_button)
	min_bet_label = _make_label("", 11, Color(1, 1, 1, 0.75))
	min_bet_label.mouse_filter = Control.MOUSE_FILTER_PASS  # so its tooltip (the $ amount) shows
	denom_box.add_child(min_bet_label)
	bar.add_child(denom_box)
	credits_label = _meter_value(Color.WHITE, 160)
	bar.add_child(_captioned("CREDIT", credits_label))
	bet_label = _meter_value(Color.WHITE, 116)
	bar.add_child(_captioned("BET", bet_label))
	win_label = _meter_value(GOLD, 140)
	win_label.text = Money.format(0)
	bar.add_child(_captioned("WIN", win_label))
	var bet_row := HBoxContainer.new()
	bet_row.add_theme_constant_override("separation", 6)
	for i in BET_MULTIPLIERS.size():
		var button := _make_button("", _bet_and_spin.bind(i))
		button.custom_minimum_size = Vector2(96, 60)
		button.add_theme_font_size_override("font_size", 15)
		button.tooltip_text = "Bet %d x the minimum and spin (key %d)" % [BET_MULTIPLIERS[i], i + 1]
		bet_buttons.append(button)
		bet_row.add_child(button)
	bar.add_child(_captioned("BET MULTIPLIER - PRESS TO PLAY", bet_row))

	# Top-left corner: the sound microphone and GAME RULES (the paytable pages).
	var corner := HBoxContainer.new()
	corner.add_theme_constant_override("separation", 8)
	corner.position = Vector2(16, 10)
	add_child(corner)
	sound_button = SoundButton.new()
	sound_button.pressed.connect(_toggle_sound)
	corner.add_child(sound_button)
	rules_button = _make_button("GAME RULES", _open_paytable)
	rules_button.custom_minimum_size = Vector2(128, 40)
	rules_button.add_theme_font_size_override("font_size", 15)
	corner.add_child(rules_button)

	# Session badge (server sessions only), top-right.
	session_label = _make_label("", 15, Color.WHITE)
	session_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(session_label)
	session_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	session_label.offset_left = -420
	session_label.offset_right = -16
	session_label.offset_top = 10
	session_label.offset_bottom = 40

	# The GAME RULES screen sits above the game (and takes keys first while open).
	paytable = Paytable.new()
	add_child(paytable)

	# Celebration overlay (added last so it draws over everything).
	celebration_dim = ColorRect.new()
	celebration_dim.color = Color(0, 0, 0, 0.6)
	celebration_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	celebration_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	celebration_dim.visible = false
	add_child(celebration_dim)
	celebration = VBoxContainer.new()
	celebration.set_anchors_preset(Control.PRESET_FULL_RECT)
	celebration.alignment = BoxContainer.ALIGNMENT_CENTER
	celebration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	celebration.visible = false
	add_child(celebration)
	celebration_title = _make_label("", 64, GOLD)
	celebration_title.add_theme_color_override("font_outline_color", Color("4a2c00"))
	celebration_title.add_theme_constant_override("outline_size", 14)
	celebration.add_child(celebration_title)
	celebration_amount = _make_label("", 84, Color.WHITE)
	celebration_amount.add_theme_color_override("font_outline_color", Color.BLACK)
	celebration_amount.add_theme_constant_override("outline_size", 14)
	celebration.add_child(celebration_amount)

	# The timed challenge's banner and cards, over everything else.
	challenge_view = ChallengeView.new()
	add_child(challenge_view)
	challenge_view.results_closed.connect(_update_bet_buttons)


## A gold-trimmed "25 LINES" plate beside the reels.
func _line_plate() -> PanelContainer:
	var plate := PanelContainer.new()
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := _plate_style(Color("2a1a44"))
	style.set_content_margin_all(8)
	plate.add_theme_stylebox_override("panel", style)
	var label := _make_label("", 20, GOLD)
	label.custom_minimum_size = Vector2(62, 0)
	label.add_theme_color_override("font_outline_color", Color("4a2c00"))
	label.add_theme_constant_override("outline_size", 6)
	plate.add_child(label)
	line_plates.append(label)
	return plate


## A small gold caption above a meter or control, like the labels on a cabinet's bar.
func _captioned(caption: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_make_label(caption, 12, GOLD.darkened(0.15)))
	control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(control)
	return box


func _meter_value(color: Color, width: float) -> Label:
	var label := _make_label("", 22, color)
	label.custom_minimum_size = Vector2(width, 44)
	return label


## The chosen bet button is gold with dark text; the others use the normal theme.
func _style_bet_button(button: Button, selected: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		if not selected:
			button.remove_theme_stylebox_override(state)
			continue
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e2a93a") if state != "disabled" else Color("6b5326")
		style.border_color = Color("fff1c4") if state != "disabled" else Color("8a744a")
		style.set_border_width_all(2)
		style.set_corner_radius_all(12)
		button.add_theme_stylebox_override(state, style)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		if selected:
			button.add_theme_color_override(key, Color("2b1600"))
		else:
			button.remove_theme_color_override(key)


## Dark violet buttons with gold trim for the whole screen.
func _make_theme() -> Theme:
	var t := Theme.new()
	var states := {
		"normal": [Color("2a1a44"), GOLD.darkened(0.35)],
		"hover": [Color("3b2560"), GOLD],
		"pressed": [Color("1a0f2c"), GOLD],
		"disabled": [Color("1a1426"), GOLD.darkened(0.7)],
	}
	for state: String in states:
		var style := StyleBoxFlat.new()
		style.bg_color = states[state][0]
		style.border_color = states[state][1]
		style.set_border_width_all(2)
		style.set_corner_radius_all(12)
		t.set_stylebox(state, "Button", style)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	# Text fields (the player-name popup).
	for state: String in ["normal", "focus"]:
		var field_style := StyleBoxFlat.new()
		field_style.bg_color = Color("1a1029")
		field_style.border_color = GOLD if state == "focus" else GOLD.darkened(0.45)
		field_style.set_border_width_all(2)
		field_style.set_corner_radius_all(10)
		field_style.set_content_margin_all(10)
		t.set_stylebox(state, "LineEdit", field_style)
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.35))
	t.set_color("caret_color", "LineEdit", GOLD)
	return t


## The SPIN button is a big gold lozenge so it's the obvious thing to press.
func _style_spin_button(button: Button) -> void:
	var colors := {"normal": Color("e2a93a"), "hover": Color("f6c457"), "pressed": Color("b8841f"), "disabled": Color("5c4a2a")}
	for state: String in colors:
		var style := StyleBoxFlat.new()
		style.bg_color = colors[state]
		style.border_color = Color("fff1c4") if state != "disabled" else Color("7a6a48")
		style.set_border_width_all(3)
		style.set_corner_radius_all(32)
		style.shadow_color = Color(1.0, 0.75, 0.2, 0.35 if state != "disabled" else 0.0)
		style.shadow_size = 10
		button.add_theme_stylebox_override(state, style)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, Color("2b1600"))
	button.add_theme_font_size_override("font_size", 24)


func _plate_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(4)
	style.shadow_color = Color(color, 0.5)
	style.shadow_size = 6
	return style


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b0714")
	style.border_color = GOLD
	style.set_border_width_all(5)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0.55, 0.3, 0.95, 0.45)
	style.shadow_size = 22
	return style


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(56, 56)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	if on_pressed.is_valid():
		button.pressed.connect(on_pressed)
	return button
