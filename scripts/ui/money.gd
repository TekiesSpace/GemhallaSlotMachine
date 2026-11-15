extends RefCounted
## Money display. The game keeps every amount in whole cents (play money), so pays,
## Rune Gem values and jackpots are always exact.


## 34175 -> "$341.75", 125000000 -> "$1,250,000.00"
static func format(cents: int) -> String:
	var sign := "-" if cents < 0 else ""
	cents = absi(cents)
	return "%s$%s.%02d" % [sign, _group(cents / 100), cents % 100]


## Whole dollars without the cents, as on the Rune Gems: 2000 -> "$20", 125 -> "$1.25".
static func short(cents: int) -> String:
	return "$%s" % _group(cents / 100) if cents % 100 == 0 else format(cents)


## A denomination button: 1 -> "1¢", 25 -> "25¢", 100 -> "$1".
static func denomination(cents: int) -> String:
	return short(cents) if cents >= 100 else "%d¢" % cents


static func _group(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out
