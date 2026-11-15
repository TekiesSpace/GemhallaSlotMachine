extends RefCounted
## Pure slot logic: no nodes or rendering, so the game scene and the RTP simulator
## run exactly the same math.

const Config := preload("res://scripts/math/slot_config.gd")

## Safety cap so a long retrigger chain can't loop forever.
const MAX_FREE_GAMES := 500

## A progressive was won and its growth (multiples of total bet) paid: for linked meters.
signal jackpot_claimed(kind: String, growth: float)

var rng := RandomNumberGenerator.new()
var strips: Array = Config.build_strips()
## Progressive growth above each meter's reset value, in multiples of total bet
## (so the meters scale with the bet level, like separate per-bet pools).
var progressive := {}
var _orb_weight_total := 0


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	for entry: Dictionary in Config.ORB_VALUES:
		_orb_weight_total += entry.weight
	for kind: String in Config.PROGRESSIVE_RATES:
		progressive[kind] = 0.0


## Feeds the progressive meters from one paid game (free games don't contribute).
func contribute() -> void:
	for kind: String in progressive:
		progressive[kind] += Config.PROGRESSIVE_RATES[kind]


## Current value of a jackpot in credits at this bet, including progressive growth.
func jackpot_value(kind: String, total_bet: int) -> int:
	return int((Config.JACKPOTS[kind] + progressive.get(kind, 0.0)) * total_bet)


## Pays a jackpot at its current value and resets its progressive meter.
func claim_jackpot(kind: String, total_bet: int) -> int:
	var value := jackpot_value(kind, total_bet)
	if progressive.has(kind):
		jackpot_claimed.emit(kind, progressive[kind])
		progressive[kind] = 0.0
	return value


## Spins every reel. Returns {grid: grid[reel][row] -> symbol id, orbs: {Vector2i(reel, row): orb},
## stops: strip index of each reel's top row}.
## `force` (one of FORCED_OUTCOMES, used by the admin page) picks real reel stops that
## produce that outcome, so a forced spin looks and pays exactly like a natural one.
func spin_reels(total_bet: int, force: String = "") -> Dictionary:
	var forced_stops := _forced_stops(force)
	var grid: Array = []
	var orbs := {}
	var stops: Array[int] = []
	for reel in Config.REELS:
		var strip: Array = strips[reel]
		var stop: int = forced_stops[reel] if not forced_stops.is_empty() else rng.randi_range(0, strip.size() - 1)
		stops.append(stop)
		var column: Array = []
		for row in Config.ROWS:
			var symbol: String = strip[(stop + row) % strip.size()]
			column.append(symbol)
			if symbol == Config.ORB:
				orbs[Vector2i(reel, row)] = draw_orb_value(total_bet)
		grid.append(column)
	var jackpot := _forced_jackpot(force)
	if not jackpot.is_empty() and jackpot != "GRAND" and not orbs.is_empty():
		# Make one of the landed Rune Gems carry the requested jackpot.
		orbs[orbs.keys()[0]] = {"kind": jackpot, "amount": jackpot_value(jackpot, total_bet)}
	return {"grid": grid, "orbs": orbs, "stops": stops, "force_grand": jackpot == "GRAND"}


# --- Forced outcomes (admin) -------------------------------------------------

const FORCED_OUTCOMES := [
	"line_win", "free_games", "hold_spin",
	"jackpot_mini", "jackpot_minor", "jackpot_major", "jackpot_grand",
]


## Reel stops that produce `force`, or [] for a normal random spin.
func _forced_stops(force: String) -> Array:
	match force:
		"line_win":
			# Five diamonds (or wilds after the first) across the middle line.
			var stops := []
			for reel in Config.REELS:
				var wanted := ["H1"] if reel == 0 else ["H1", Config.WILD]
				stops.append(_random_stop_where(reel, func(window: Array) -> bool: return wanted.has(window[1])))
			return stops
		"free_games":
			# A Vault on three different reels.
			var reels := range(Config.REELS)
			reels.shuffle()
			var stops := []
			for reel in Config.REELS:
				if reels.slice(0, 3).has(reel):
					stops.append(_random_stop_where(reel, func(window: Array) -> bool: return window.has(Config.SCATTER)))
				else:
					stops.append(rng.randi_range(0, strips[reel].size() - 1))
			return stops
		"":
			return []
	if force == "hold_spin" or not _forced_jackpot(force).is_empty():
		return _hold_spin_stops()
	push_warning("Unknown forced outcome '%s'; spinning normally." % force)
	return []


## "jackpot_major" -> "MAJOR"; anything else -> "".
func _forced_jackpot(force: String) -> String:
	return force.trim_prefix("jackpot_").to_upper() if force.begins_with("jackpot_") else ""


## Stops with at least HS_TRIGGER_COUNT Rune Gems in view: each reel takes one of its
## gem-richest windows; a random search covers the rare case that isn't enough.
func _hold_spin_stops() -> Array:
	var stops := []
	var total := 0
	for reel in Config.REELS:
		var best := 0
		for candidate in strips[reel].size():
			best = maxi(best, _window(reel, candidate).count(Config.ORB))
		var stop := _random_stop_where(reel, func(window: Array) -> bool: return window.count(Config.ORB) == best)
		stops.append(stop)
		total += best
	if total >= Config.HS_TRIGGER_COUNT:
		return stops
	for attempt in 50000:
		stops = []
		total = 0
		for reel in Config.REELS:
			var stop := rng.randi_range(0, strips[reel].size() - 1)
			stops.append(stop)
			total += _window(reel, stop).count(Config.ORB)
		if total >= Config.HS_TRIGGER_COUNT:
			return stops
	return stops


## The three symbols visible on `reel` when stopped at `stop`.
func _window(reel: int, stop: int) -> Array:
	var strip: Array = strips[reel]
	return [strip[stop % strip.size()], strip[(stop + 1) % strip.size()], strip[(stop + 2) % strip.size()]]


## A random stop on `reel` whose visible window satisfies `test`.
func _random_stop_where(reel: int, test: Callable) -> int:
	var matches := []
	for stop in strips[reel].size():
		if test.call(_window(reel, stop)):
			matches.append(stop)
	if matches.is_empty():
		return rng.randi_range(0, strips[reel].size() - 1)
	return matches[rng.randi_range(0, matches.size() - 1)]


## Scores a spin: left-to-right line wins, scatter pays and feature triggers.
## multiplier applies to line and scatter pays (used for free games). Only the first
## `lines` paylines are played; every line has the same expected pay, so the return to
## player doesn't depend on how many are played. in_free_games uses the smaller retrigger awards.
func evaluate(spin: Dictionary, line_bet: int, multiplier: int = 1, lines: int = Config.PAYLINES.size(),
		in_free_games: bool = false) -> Dictionary:
	var grid: Array = spin.grid
	lines = clampi(lines, 1, Config.PAYLINES.size())
	var total_bet := line_bet * lines

	var line_wins: Array = []
	var line_pay := 0
	for i in lines:
		var line: Array = Config.PAYLINES[i]
		var symbol: String = grid[0][line[0]]
		if not Config.PAYTABLE.has(symbol):
			continue
		var count := 1
		while count < Config.REELS:
			var next: String = grid[count][line[count]]
			if next != symbol and next != Config.WILD:
				break
			count += 1
		if count >= 3:
			var pay: int = Config.PAYTABLE[symbol][count - 3] * line_bet * multiplier
			line_pay += pay
			line_wins.append({"line": i, "symbol": symbol, "count": count, "pay": pay})

	var scatters := 0
	for column: Array in grid:
		scatters += column.count(Config.SCATTER)
	var scatter_pay := 0
	var free_games := 0
	if scatters >= 3:
		var tier := mini(scatters, 5) - 3
		scatter_pay = Config.SCATTER_PAYS[tier] * total_bet * multiplier
		free_games = (Config.FREE_GAMES_RETRIGGER if in_free_games else Config.FREE_GAMES_AWARD)[tier]

	return {
		"line_wins": line_wins,
		"line_pay": line_pay,
		"scatters": scatters,
		"scatter_pay": scatter_pay,
		"free_games": free_games,
		"hold_and_spin": spin.orbs.size() >= Config.HS_TRIGGER_COUNT,
	}


## Rune Storm (free games): strikes random cells into Rune Gems, updating the spin's grid
## and orbs before it's evaluated. Returns the cells struck, for the UI to play back.
func rune_storm(spin: Dictionary, total_bet: int) -> Array[Vector2i]:
	var struck: Array[Vector2i] = []
	for reel in Config.REELS:
		for row in Config.ROWS:
			var symbol: String = spin.grid[reel][row]
			if symbol in [Config.ORB, Config.SCATTER, Config.WILD] or rng.randf() >= Config.STORM_CHANCE:
				continue
			var pos := Vector2i(reel, row)
			spin.grid[reel][row] = Config.ORB
			spin.orbs[pos] = draw_orb_value(total_bet)
			struck.append(pos)
	return struck


## Picks a value for a newly landed orb: {kind: "CREDIT"|"MINI"|"MINOR"|"MAJOR", amount: credits}.
func draw_orb_value(total_bet: int) -> Dictionary:
	var roll := rng.randi_range(1, _orb_weight_total)
	for entry: Dictionary in Config.ORB_VALUES:
		roll -= entry.weight
		if roll <= 0:
			var mult: int = entry.mult if entry.kind == "CREDIT" else Config.JACKPOTS[entry.kind]
			return {"kind": entry.kind, "amount": mult * total_bet}
	push_error("ORB_VALUES weights out of sync")
	return {"kind": "CREDIT", "amount": total_bet}


## Plays the Hold & Spin feature from the orbs that triggered it.
## Returns {orbs, steps, total, jackpots, grand}; each step is {landed: {pos: orb}, respins_left}
## so the UI can replay it one respin at a time.
## force_grand (admin) makes gems land often and fills every cell on the last chance,
## so the feature always ends with the Grand.
func play_hold_and_spin(start_orbs: Dictionary, total_bet: int, force_grand: bool = false) -> Dictionary:
	var locked := start_orbs.duplicate()
	var cell_count := Config.REELS * Config.ROWS
	var respins := Config.HS_RESPINS
	var steps: Array = []
	while respins > 0 and locked.size() < cell_count:
		respins -= 1
		var chance := Config.HS_ORB_CHANCE
		if force_grand:
			chance = 0.3 if respins > 0 else 1.0
		var landed := {}
		for reel in Config.REELS:
			for row in Config.ROWS:
				var pos := Vector2i(reel, row)
				if not locked.has(pos) and rng.randf() < chance:
					landed[pos] = draw_orb_value(total_bet)
		if not landed.is_empty():
			locked.merge(landed)
			respins = Config.HS_RESPINS
		steps.append({"landed": landed, "respins_left": respins})

	var total := 0
	var jackpots: Array = []
	var jackpot_wins: Array = []  # [{kind, amount}] for the UI's celebrations
	for orb: Dictionary in locked.values():
		# Progressive orbs pay the meter as it stands when the feature ends.
		if progressive.has(orb.kind):
			orb.amount = claim_jackpot(orb.kind, total_bet)
		total += orb.amount
		if orb.kind != "CREDIT":
			jackpots.append(orb.kind)
			jackpot_wins.append({"kind": orb.kind, "amount": orb.amount})
	var grand := locked.size() == cell_count
	if grand:
		var grand_amount := claim_jackpot("GRAND", total_bet)
		total += grand_amount
		jackpots.append("GRAND")
		jackpot_wins.append({"kind": "GRAND", "amount": grand_amount})
	return {
		"orbs": locked, "steps": steps, "total": total,
		"jackpots": jackpots, "jackpot_wins": jackpot_wins, "grand": grand,
	}


## Resolves one whole paid game, features included. The simulator uses this; the UI
## makes the same calls itself so it can animate between them.
func play_round(line_bet: int, lines: int = Config.PAYLINES.size()) -> Dictionary:
	var total_bet := line_bet * lines
	var out := {
		"bet": total_bet, "win": 0,
		"base": 0, "scatter": 0, "hold_spin": 0, "free_games": 0,
		"hs_triggers": 0, "hs_pay": 0, "fg_triggers": 0, "jackpots": [],
	}
	contribute()

	var spin := spin_reels(total_bet)
	var result := evaluate(spin, line_bet, 1, lines)
	out.base = result.line_pay
	out.scatter = result.scatter_pay
	if result.hold_and_spin:
		var hs := play_hold_and_spin(spin.orbs, total_bet)
		out.hold_spin = hs.total
		out.hs_triggers += 1
		out.hs_pay += hs.total
		out.jackpots.append_array(hs.jackpots)

	var free_left: int = result.free_games
	if free_left > 0:
		out.fg_triggers = 1
	var played := 0
	while free_left > 0 and played < MAX_FREE_GAMES:
		free_left -= 1
		played += 1
		var free_spin := spin_reels(total_bet)
		rune_storm(free_spin, total_bet)
		var free_result := evaluate(free_spin, line_bet, Config.FREE_GAMES_MULTIPLIER, lines, true)
		out.free_games += free_result.line_pay + free_result.scatter_pay
		free_left += free_result.free_games
		if free_result.hold_and_spin:
			var free_hs := play_hold_and_spin(free_spin.orbs, total_bet)
			out.free_games += free_hs.total
			out.hs_triggers += 1
			out.hs_pay += free_hs.total
			out.jackpots.append_array(free_hs.jackpots)

	out.win = out.base + out.scatter + out.hold_spin + out.free_games
	return out
