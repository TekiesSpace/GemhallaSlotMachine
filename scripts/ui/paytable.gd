extends Control
## The GAME RULES screen, Vegas style: a full-screen, multi-page paytable that shows every
## pay in dollars at the current bet. Pages: symbol pays, features, paylines, rules.
## Everything is read from slot_config.gd, so it always matches what the game pays.

signal closed

const Config := preload("res://scripts/math/slot_config.gd")
const SymbolTile := preload("res://scripts/ui/symbol_tile.gd")
const WinLines := preload("res://scripts/ui/win_lines.gd")
const Money := preload("res://scripts/ui/money.gd")

const GOLD := Color("f3c969")
const PAGE_TITLES := ["SYMBOL PAYS", "FEATURES", "PAYLINES", "RULES"]
const PAYING := ["H1", "H2", "H3", "H4", "A", "K", "Q", "J", "T", "N"]
const JACKPOT_COLORS := {
	"GRAND": Color("9b1c31"), "MAJOR": Color("5d2a8c"), "MINOR": Color("1f4f8f"), "MINI": Color("1d6b47"),
}

var _pages: Array[Control] = []
var _page := 0
var _title: Label
var _page_label: Label
var _content: Control


func _ready() -> void:
	# Already in the tree here, so set the offsets too, or the overlay keeps a zero size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	_title = _label("", 32, GOLD)
	_title.add_theme_color_override("font_outline_color", Color("5a3200"))
	_title.add_theme_constant_override("outline_size", 8)
	column.add_child(_title)
	_content = Control.new()
	_content.custom_minimum_size = Vector2(1120, 470)
	column.add_child(_content)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 18)
	column.add_child(footer)
	footer.add_child(_button("<  PREV", func() -> void: _show_page(_page - 1)))
	_page_label = _label("", 18, Color(1, 1, 1, 0.7))
	_page_label.custom_minimum_size = Vector2(150, 0)
	footer.add_child(_page_label)
	footer.add_child(_button("NEXT  >", func() -> void: _show_page(_page + 1)))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(120, 0)
	footer.add_child(spacer)
	var back := _button("RETURN TO GAME", close)
	back.custom_minimum_size = Vector2(230, 52)
	_style_gold(back)
	footer.add_child(back)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			close()
		KEY_RIGHT:
			_show_page(_page + 1)
		KEY_LEFT:
			_show_page(_page - 1)
	get_viewport().set_input_as_handled()  # keep Space etc. from spinning underneath


## Opens on the first page, with pays worked out for this bet (all amounts in cents)
## and live jackpot values. coins is the game's [[denomination, lines], ...] table.
func open(line_bet: int, lines: int, multiplier: int, denomination: int, jackpot_values: Dictionary, coins: Array) -> void:
	for page in _pages:
		page.queue_free()
	var total_bet := line_bet * lines
	_pages = [
		_symbol_page(line_bet, lines, multiplier, denomination),
		_features_page(total_bet, jackpot_values),
		_paylines_page(lines, coins),
		_rules_page(),
	]
	for page in _pages:
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		_content.add_child(page)
	_show_page(0)
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _show_page(index: int) -> void:
	_page = wrapi(index, 0, _pages.size())
	for i in _pages.size():
		_pages[i].visible = i == _page
	_title.text = PAGE_TITLES[_page]
	_page_label.text = "PAGE %d OF %d" % [_page + 1, _pages.size()]


# --- Pages -------------------------------------------------------------------

func _symbol_page(line_bet: int, lines: int, multiplier: int, denomination: int) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(_label("Pays for your BET of %s: %d line%s x bet multiplier %d x %s denomination = %s per line. Wins pay on played lines only." % [
		Money.format(line_bet * lines), lines, "" if lines == 1 else "s", multiplier, Money.denomination(denomination),
		Money.format(line_bet)], 17, Color(1, 1, 1, 0.8)))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(grid)
	for symbol: String in PAYING:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(_tile(symbol, Vector2(88, 76)))
		var pays: Array = Config.PAYTABLE[symbol]
		var pay_rows := PackedStringArray()
		for count in [5, 4, 3]:
			pay_rows.append("%d  %s" % [count, Money.format(pays[count - 3] * line_bet)])
		var text := _label("\n".join(pay_rows), 17, Color.WHITE)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.custom_minimum_size = Vector2(124, 0)
		cell.add_child(text)
		grid.add_child(cell)
	var wild := HBoxContainer.new()
	wild.alignment = BoxContainer.ALIGNMENT_CENTER
	wild.add_theme_constant_override("separation", 16)
	wild.add_child(_tile("WILD", Vector2(120, 92)))
	wild.add_child(_paragraph("WILD substitutes for every symbol except VAULT and RUNE GEM.\nIt appears on reels 2, 3, 4 and 5.", 20, 560))
	page.add_child(wild)
	return page


func _features_page(total_bet: int, jackpot_values: Dictionary) -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 40)
	page.alignment = BoxContainer.ALIGNMENT_CENTER

	var hold := VBoxContainer.new()
	hold.add_theme_constant_override("separation", 10)
	hold.add_child(_heading("HOLD & SPIN"))
	var hold_row := HBoxContainer.new()
	hold_row.add_theme_constant_override("separation", 14)
	hold_row.add_child(_tile("ORB", Vector2(120, 104), "MINOR"))
	hold_row.add_child(_paragraph(
		"- %d or more RUNE GEMS trigger HOLD & SPIN.\n- Rune Gems lock in place and you get %d respins.\n- Every new Rune Gem resets the respins to %d.\n- Each Rune Gem pays its cash prize or a MINI, MINOR or MAJOR jackpot.\n- Fill all %d positions to win the GRAND." % [
		Config.HS_TRIGGER_COUNT, Config.HS_RESPINS, Config.HS_RESPINS, Config.REELS * Config.ROWS], 18, 400))
	hold.add_child(hold_row)
	var plates := HBoxContainer.new()
	plates.add_theme_constant_override("separation", 10)
	for kind: String in ["GRAND", "MAJOR", "MINOR", "MINI"]:
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", _plate_style(JACKPOT_COLORS[kind]))
		plate.custom_minimum_size = Vector2(124, 0)
		plate.add_child(_label("%s\n%s" % [kind, Money.format(jackpot_values.get(kind, 0))], 17, Color.WHITE))
		plates.add_child(plate)
	hold.add_child(plates)
	hold.add_child(_paragraph("MINI and MINOR are fixed. MAJOR and GRAND grow with every bet until won.", 16, 540, Color(1, 1, 1, 0.75)))
	page.add_child(hold)

	var free := VBoxContainer.new()
	free.add_theme_constant_override("separation", 10)
	free.add_child(_heading("FREE GAMES"))
	var free_row := HBoxContainer.new()
	free_row.add_theme_constant_override("separation", 14)
	free_row.add_child(_tile("SCAT", Vector2(120, 104)))
	var scatter_lines := PackedStringArray()
	for i in 3:
		scatter_lines.append("- %d VAULTS anywhere: %d FREE GAMES and %s" % [
			i + 3, Config.FREE_GAMES_AWARD[i], Money.format(Config.SCATTER_PAYS[i] * total_bet)])
	free_row.add_child(_paragraph("\n".join(scatter_lines) +
		"\n- All wins during free games pay x%d.\n- RUNE STORM: during free games, lightning can strike symbols into RUNE GEMS.\n- 3, 4 or 5 VAULTS during free games add %d, %d or %d more.\n- HOLD & SPIN can trigger during free games." % [
			Config.FREE_GAMES_MULTIPLIER, Config.FREE_GAMES_RETRIGGER[0], Config.FREE_GAMES_RETRIGGER[1], Config.FREE_GAMES_RETRIGGER[2]], 18, 400))
	free.add_child(free_row)
	page.add_child(free)
	return page


func _paylines_page(lines: int, coins: Array) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var by_coin := PackedStringArray()
	for coin: Array in coins:
		by_coin.append("%s %d" % [Money.denomination(coin[0]), coin[1]])
	page.add_child(_label("You are playing lines 1 to %d (bright). The coin sets the lines: %s. Wins pay left to right." % [
		lines, ", ".join(by_coin)], 17, Color(1, 1, 1, 0.8)))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(grid)
	for i in Config.PAYLINES.size():
		var diagram := LineDiagram.new()
		diagram.line_index = i
		if i >= lines:
			diagram.modulate.a = 0.3  # not played at this bet
		grid.add_child(diagram)
	return page


func _rules_page() -> Control:
	var rules := PackedStringArray([
		"- DENOM picks the coin, which sets the lines played and the minimum bet: 1 credit a line, so MIN BET 25 is 25 credits.",
		"- The bet buttons (x1, x2, x3, x5, x10, or keys 1-5) bet that multiple of the minimum and spin. Space repeats the bet.",
		"- Only played lines can win.",
		"- Line wins pay left to right on adjacent reels, starting with the leftmost reel.",
		"- Each line pays one win at most. Wins on different lines are added together.",
		"- VAULT wins, Rune Gems and jackpots pay on the total bet, and are added to line wins.",
		"- Pays are shown in dollars at the current bet; changing the bet changes the pays.",
		"- Free games play at the bet that won them.",
		"- MAJOR starts at %dx and GRAND at %dx the total bet; each grows by %s%% and %s%% of every paid bet." % [
			Config.JACKPOTS.MAJOR, Config.JACKPOTS.GRAND,
			str(Config.PROGRESSIVE_RATES.MAJOR * 100), str(Config.PROGRESSIVE_RATES.GRAND * 100)],
		"- Online, every player's bets feed the same MAJOR and GRAND meters, shown here at your bet.",
		"- Theoretical return to player is about 93.7% over a very long period of play.",
		"- Gemhalla is played for fun with play money only. It has no cash value.",
		"- Malfunction voids all pays and plays.",
	])
	var page := CenterContainer.new()
	page.add_child(_paragraph("\n".join(rules), 18, 960))
	return page


# --- Building blocks -----------------------------------------------------------

## Draws one payline on a mini 5x3 grid, with its number, in the same color as on the reels.
class LineDiagram extends Control:
	const CELL := Vector2(26, 17)
	const GAP := 3.0
	var line_index := 0

	func _init() -> void:
		custom_minimum_size = Vector2(190, 66)

	func _draw() -> void:
		var rows: Array = Config.PAYLINES[line_index]
		var color: Color = WinLines.LINE_COLORS[line_index % WinLines.LINE_COLORS.size()]
		var origin := Vector2(46, 6)
		var points := PackedVector2Array()
		for reel in Config.REELS:
			for row in Config.ROWS:
				var pos := origin + Vector2(reel, row) * (CELL + Vector2(GAP, GAP))
				var on_line: bool = rows[reel] == row
				draw_rect(Rect2(pos, CELL), Color(color, 0.85) if on_line else Color("2a1f42"))
			points.append(origin + Vector2(reel, rows[reel]) * (CELL + Vector2(GAP, GAP)) + CELL / 2)
		draw_polyline(points, Color.WHITE, 2.0, true)
		draw_circle(Vector2(18, 33), 15, color)
		draw_string(get_theme_default_font(), Vector2(3, 39), str(line_index + 1), HORIZONTAL_ALIGNMENT_CENTER, 30, 16, Color.BLACK)


func _tile(symbol: String, tile_size: Vector2, caption: String = "") -> SymbolTile:
	var tile := SymbolTile.new()
	tile.custom_minimum_size = tile_size
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # keep its size beside tall text
	tile.show_symbol(symbol, caption)
	return tile


func _heading(text: String) -> Label:
	var label := _label(text, 24, GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


func _paragraph(text: String, font_size: int, width: float, color: Color = Color.WHITE) -> Label:
	var label := _label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.add_theme_constant_override("line_spacing", 4)
	return label


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(130, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(on_pressed)
	return button


func _style_gold(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = {"normal": Color("e2a93a"), "hover": Color("f6c457"), "pressed": Color("b8841f")}[state]
		style.border_color = Color("fff1c4")
		style.set_border_width_all(3)
		style.set_corner_radius_all(26)
		button.add_theme_stylebox_override(state, style)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, Color("2b1600"))


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("120a20")
	style.border_color = GOLD
	style.set_border_width_all(5)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(22)
	style.shadow_color = Color(0.55, 0.3, 0.95, 0.45)
	style.shadow_size = 22
	return style


func _plate_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(4)
	return style
