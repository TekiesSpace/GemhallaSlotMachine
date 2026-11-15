# Gemhalla's rules and math

The whole math model is in `scripts/math/slot_config.gd`: reel strips, paytable, paylines, the Hold & Spin and free-game tables, and the jackpot settings. `scripts/math/slot_engine.gd` plays it, with no visuals, so the game, the simulator and the forced-outcome test all run the same code. The in-game paytable (**GAME RULES**) is built from `slot_config.gd` too, so it always matches.

## Current numbers

From 40 million simulated games:

| Measure | Value |
| --- | --- |
| Return to player (RTP) | about 93.7%, +/- 0.3%, including a 1% progressive feed |
| Hit frequency | 1 in 4.6 games |
| Hold & Spin | about 1 in 91 games, paying on average about 27x the bet |
| Free games | about 1 in 266 games, paying on average about 21.5x the bet |

Every line has the same expected pay, so the RTP is the same at any denomination, line count and bet multiplier.

## Measuring it

```bash
godot --headless --path . --script res://tools/rtp_sim.gd -- --spins=1000000 --seed=1
godot --headless --path . --script res://tools/rtp_sim.gd -- --spins=1000000 --seed=1 --lines=5
```

The simulator plays paid games through the real engine (free games and Hold & Spin included) and reports the RTP, hit frequency and how often each feature comes and what it pays. A million games gives a rough figure; feature-heavy changes need tens of millions for a tight one. On Windows, `tools/run_sim.ps1 -Spins 1000000 -Seed 1 -Lines 25` does the same.

## Rules

- **Reels and lines:** 5x3 reels and 25 paylines, paying left to right. Only played lines can win; "N LINES" plates beside the reels show how many are played.
- **Wild:** appears on reels 2 to 5 and substitutes for everything except the Vault and the Rune Gem.
- **Betting:** **DENOM** picks the coin, and the coin sets the lines played and so the minimum bet (one credit a line, shown under DENOM in credits, so "MIN BET 25" is 25 lines). 1c, 2c, 5c and 10c play 25 lines; $1 and $2 play 5, so every minimum bet is $0.25 or more. The bet buttons x1, x2, x3, x5 and x10 (keys 1 to 5) bet that multiple of the minimum and spin; there is no separate SPIN button. Space repeats the bet. While the reels spin, the lit button reads STOP, and any bet button or Space slams them; during free games it reads FREE GAME n LEFT and plays the next one.
- **Money:** shown in dollars and kept in whole cents everywhere: game, saves, server and admin page.
- **Vaults and free games:** 3 or more Vault scatters anywhere pay a scatter win and start 9, 15 or 20 free games. Line and scatter wins are tripled during free games. Vaults that land during free games add 3, 5 or 8 more.
- **Rune Storm:** during free games, after the reels stop, lightning strikes cells into Rune Gems: 3.5% of each cell that isn't already a Rune Gem, Vault or Wild. That can set off Hold & Spin.
- **Hold & Spin:** 6 or more Rune Gems start it. The gems lock and you get 3 respins; every new gem resets the count to 3. Gems carry credits or the MINI, MINOR or MAJOR jackpot, and filling all 15 cells adds the GRAND.
- **Jackpots:** MINI and MINOR are fixed. MAJOR and GRAND are progressive: 0.4% and 0.6% of every paid bet grow them, and a meter resets when it's won. Meters are kept in multiples of the total bet, so the return is the same at every bet. On the server, MAJOR and GRAND are shared by everyone online (see [SERVER.md](SERVER.md)).
- **Vaults, Rune Gems and jackpots** pay on the total bet; line wins pay on the line bet.

## Forced outcomes

The admin page can force the next spin (see [SERVER.md](SERVER.md)). The engine finds real reel positions that produce the outcome, so a forced spin looks and pays like a natural one. To check every forced outcome:

```bash
godot --headless --path . --script res://tools/test_forced_outcomes.gd
```

It forces each outcome 200 times through the real engine and checks the result is what was asked for.
