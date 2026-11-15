extends RefCounted
## The math model: symbols, reel strips, paytable, paylines and feature tables.
## All tuning lives here so the game and the RTP simulator share one source of truth.
## After changing anything, re-run tools/rtp_sim.gd to see the effect on RTP.

const REELS := 5
const ROWS := 3

# Special symbol ids.
const WILD := "WILD"
const SCATTER := "SCAT"
const ORB := "ORB"

# Theme: Gemhalla, a Norse hall of precious gems. Ids stay generic so a re-theme never touches the math.
const SYMBOL_NAMES := {
	"WILD": "GEMHALLA\nWILD", "SCAT": "VAULT\nFREE GAMES", "ORB": "RUNE GEM",
	"H1": "DIAMOND", "H2": "RUBY", "H3": "EMERALD", "H4": "SAPPHIRE",
	"A": "A", "K": "K", "Q": "Q", "J": "J", "T": "10", "N": "9",
}

# Line pays as multiples of the line bet, for 3 / 4 / 5 of a kind.
# Wild substitutes for every symbol listed here.
const PAYTABLE := {
	"H1": [150, 400, 1500],
	"H2": [80, 300, 800],
	"H3": [60, 150, 500],
	"H4": [40, 150, 400],
	"A": [30, 75, 300],
	"K": [30, 75, 300],
	"Q": [20, 50, 200],
	"J": [20, 50, 200],
	"T": [20, 50, 200],
	"N": [20, 50, 200],
}

# Symbol counts on each reel strip (80 stops per reel). No wilds on reel 1.
const REEL_COUNTS := [
	{"ORB": 11, "SCAT": 2, "H1": 4, "H2": 5, "H3": 6, "H4": 7, "A": 8, "K": 8, "Q": 9, "J": 8, "T": 6, "N": 6},
	{"WILD": 3, "ORB": 11, "SCAT": 2, "H1": 4, "H2": 5, "H3": 6, "H4": 6, "A": 8, "K": 8, "Q": 8, "J": 7, "T": 6, "N": 6},
	{"WILD": 3, "ORB": 11, "SCAT": 2, "H1": 4, "H2": 5, "H3": 6, "H4": 6, "A": 8, "K": 8, "Q": 8, "J": 7, "T": 6, "N": 6},
	{"WILD": 3, "ORB": 11, "SCAT": 2, "H1": 4, "H2": 5, "H3": 6, "H4": 6, "A": 8, "K": 8, "Q": 8, "J": 7, "T": 6, "N": 6},
	{"WILD": 3, "ORB": 11, "SCAT": 2, "H1": 4, "H2": 5, "H3": 6, "H4": 6, "A": 8, "K": 8, "Q": 8, "J": 7, "T": 6, "N": 6},
]

# Fixed seed so the strips are identical every run (and between game and simulator).
const STRIP_SEED := 20151

# 25 paylines; each entry is the row (0 = top) used on reels 1-5.
const PAYLINES := [
	[1, 1, 1, 1, 1], [0, 0, 0, 0, 0], [2, 2, 2, 2, 2], [0, 1, 2, 1, 0], [2, 1, 0, 1, 2],
	[0, 0, 1, 2, 2], [2, 2, 1, 0, 0], [1, 0, 0, 0, 1], [1, 2, 2, 2, 1], [1, 0, 1, 2, 1],
	[1, 2, 1, 0, 1], [0, 1, 1, 1, 0], [2, 1, 1, 1, 2], [0, 1, 0, 1, 0], [2, 1, 2, 1, 2],
	[1, 1, 0, 1, 1], [1, 1, 2, 1, 1], [0, 0, 2, 0, 0], [2, 2, 0, 2, 2], [0, 2, 0, 2, 0],
	[2, 0, 2, 0, 2], [0, 2, 2, 2, 0], [2, 0, 0, 0, 2], [1, 0, 2, 0, 1], [1, 2, 0, 2, 1],
]

# Scatters anywhere: pay (x total bet) and free games for 3 / 4 / 5+.
const SCATTER_PAYS := [4, 20, 100]
const FREE_GAMES_AWARD := [9, 15, 20]
# Vaults landing during free games add only this many more, for 3 / 4 / 5+.
const FREE_GAMES_RETRIGGER := [3, 5, 8]
# Rune Storm: during free games, the chance that each cell not already holding a Rune Gem,
# Vault or Wild is struck into a Rune Gem after the reels stop.
const STORM_CHANCE := 0.035
# Line and scatter pays are multiplied by this during free games (Hold & Spin is not).
const FREE_GAMES_MULTIPLIER := 3

# Hold & Spin: this many orbs triggers it; each new orb resets the respins.
const HS_TRIGGER_COUNT := 6
const HS_RESPINS := 3
# Chance that an empty cell lands an orb on each respin.
const HS_ORB_CHANCE := 0.045

# Jackpots as multiples of total bet. GRAND is won by filling all 15 cells.
# For progressives these are the reset (starting) values.
const JACKPOTS := {"MINI": 10, "MINOR": 40, "MAJOR": 400, "GRAND": 2000}

# MAJOR and GRAND are progressive: each paid game adds this fraction of the bet to the
# meter, which resets when won. Every contribution is eventually paid out, so these
# rates add straight onto RTP (+1.0% here).
const PROGRESSIVE_RATES := {"MAJOR": 0.004, "GRAND": 0.006}

# Orb value table. CREDIT orbs pay mult x total bet; jackpot orbs pay from JACKPOTS.
const ORB_VALUES := [
	{"weight": 3000, "kind": "CREDIT", "mult": 1},
	{"weight": 2000, "kind": "CREDIT", "mult": 2},
	{"weight": 1200, "kind": "CREDIT", "mult": 3},
	{"weight": 600, "kind": "CREDIT", "mult": 5},
	{"weight": 300, "kind": "CREDIT", "mult": 8},
	{"weight": 150, "kind": "CREDIT", "mult": 10},
	{"weight": 200, "kind": "MINI", "mult": 0},
	{"weight": 40, "kind": "MINOR", "mult": 0},
	{"weight": 3, "kind": "MAJOR", "mult": 0},
]


## Expands REEL_COUNTS into shuffled reel strips (deterministic via STRIP_SEED).
static func build_strips() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = STRIP_SEED
	var strips: Array = []
	for counts: Dictionary in REEL_COUNTS:
		var strip: Array[String] = []
		for symbol: String in counts:
			for i in counts[symbol]:
				strip.append(symbol)
		# Fisher-Yates with our own RNG so the order never depends on the global seed.
		for i in range(strip.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := strip[i]
			strip[i] = strip[j]
			strip[j] = tmp
		strips.append(strip)
	return strips
