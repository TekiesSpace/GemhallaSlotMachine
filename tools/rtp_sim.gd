extends SceneTree
## Headless RTP simulator: plays the real SlotEngine for N paid games and reports the math.
##
## Usage (from the project folder):
##   <Godot>_console.exe --headless --path . --script res://tools/rtp_sim.gd -- --spins=1000000 --seed=42 [--lines=5]
## Or just run tools/run_sim.ps1.

const SlotEngine := preload("res://scripts/math/slot_engine.gd")
const Config := preload("res://scripts/math/slot_config.gd")


func _initialize() -> void:
	var spins := 200000
	var seed_value := -1
	var lines: int = Config.PAYLINES.size()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spins="):
			spins = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--seed="):
			seed_value = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--lines="):
			lines = clampi(arg.get_slice("=", 1).to_int(), 1, Config.PAYLINES.size())

	var engine := SlotEngine.new(seed_value)
	var line_bet := 1
	var totals := {"bet": 0, "win": 0, "base": 0, "scatter": 0, "hold_spin": 0, "free_games": 0,
		"hs_triggers": 0, "hs_pay": 0, "fg_triggers": 0}
	var jackpot_hits := {"MINI": 0, "MINOR": 0, "MAJOR": 0, "GRAND": 0}
	var hits := 0
	var max_win := 0.0
	var sum_sq := 0.0
	var fg_pay := 0

	var started := Time.get_ticks_msec()
	var progress_every := maxi(spins / 10, 1)
	for i in spins:
		var r := engine.play_round(line_bet, lines)
		for key: String in totals:
			totals[key] += r[key]
		for kind: String in r.jackpots:
			jackpot_hits[kind] += 1
		if r.fg_triggers > 0:
			fg_pay += r.free_games
		if r.win > 0:
			hits += 1
		var x: float = float(r.win) / r.bet
		sum_sq += x * x
		max_win = maxf(max_win, x)
		if (i + 1) % progress_every == 0:
			print("  ... %d / %d" % [i + 1, spins])

	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var bet := float(totals.bet)
	var rtp: float = totals.win / bet
	var mean := rtp
	var std_dev := sqrt(maxf(sum_sq / spins - mean * mean, 0.0))
	var ci := 1.96 * std_dev / sqrt(spins)

	print("")
	print("=== RTP simulation: %d games, %d lines, seed %d, %.1fs ===" % [spins, lines, seed_value, seconds])
	print("Total RTP            %6.2f%%  (+/- %.2f%% at 95%%)" % [rtp * 100, ci * 100])
	print("  Line wins          %6.2f%%" % [totals.base / bet * 100])
	print("  Scatter pays       %6.2f%%" % [totals.scatter / bet * 100])
	print("  Hold & Spin (base) %6.2f%%" % [totals.hold_spin / bet * 100])
	print("  Free games         %6.2f%%  (includes Hold & Spin won inside them)" % [totals.free_games / bet * 100])
	print("Hit frequency        %6.2f%%  (1 in %.2f)" % [hits * 100.0 / spins, _one_in(hits, spins)])
	print("Hold & Spin          1 in %.0f games, avg %.1fx bet" % [_one_in(totals.hs_triggers, spins), _avg(totals.hs_pay, totals.hs_triggers) / (bet / spins)])
	print("Free games           1 in %.0f games, avg %.1fx bet" % [_one_in(totals.fg_triggers, spins), _avg(fg_pay, totals.fg_triggers) / (bet / spins)])
	for kind: String in jackpot_hits:
		print("  %-6s jackpot     %d hits (1 in %.0f)" % [kind, jackpot_hits[kind], _one_in(jackpot_hits[kind], spins)])
	var contribution := 0.0
	for kind: String in engine.progressive:
		contribution += Config.PROGRESSIVE_RATES[kind]
		print("  %-6s meter now   %.0fx bet (reset %dx + %.1fx growth)" % [kind, Config.JACKPOTS[kind] + engine.progressive[kind], Config.JACKPOTS[kind], engine.progressive[kind]])
	print("Progressive feed     %.2f%% of every bet (already inside Total RTP)" % [contribution * 100])
	print("Max win              %.1fx bet" % max_win)
	print("Volatility (std dev) %.2f" % std_dev)
	quit()


func _one_in(count: int, games: int) -> float:
	return INF if count == 0 else float(games) / count


func _avg(total: int, count: int) -> float:
	return 0.0 if count == 0 else float(total) / count
