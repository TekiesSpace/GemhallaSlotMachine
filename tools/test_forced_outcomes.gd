extends SceneTree
## Checks every admin-forced outcome: forces each one 200 times through the real engine
## and verifies the result is what was asked for.
##
## Usage: <Godot>_console.exe --headless --path . --script res://tools/test_forced_outcomes.gd

const SlotEngine := preload("res://scripts/math/slot_engine.gd")
const Config := preload("res://scripts/math/slot_config.gd")
const TRIES := 200


func _initialize() -> void:
	var engine := SlotEngine.new(11)
	var bet := 25
	var failures := 0
	for force: String in SlotEngine.FORCED_OUTCOMES:
		var ok := 0
		for i in TRIES:
			var spin := engine.spin_reels(bet, force)
			var result := engine.evaluate(spin, 1)
			if _check(engine, force, spin, result, bet):
				ok += 1
		print("%-14s %d/%d" % [force, ok, TRIES])
		failures += TRIES - ok
	print("ALL FORCED OUTCOMES OK" if failures == 0 else "FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(engine: SlotEngine, force: String, spin: Dictionary, result: Dictionary, bet: int) -> bool:
	match force:
		"line_win":
			for line_win: Dictionary in result.line_wins:
				if line_win.line == 0 and line_win.count == 5 and line_win.symbol == "H1":
					return true
			return false
		"free_games":
			return result.free_games > 0
		"hold_spin":
			return result.hold_and_spin
	# Jackpots: the feature must trigger and pay the requested jackpot.
	if not result.hold_and_spin:
		return false
	var hs := engine.play_hold_and_spin(spin.orbs, bet, spin.force_grand)
	return hs.jackpots.has(force.trim_prefix("jackpot_").to_upper())
