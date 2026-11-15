extends Control
## The timed challenge on screen (server/Challenge.cs runs it): a full-screen card for the
## countdown, for "time's up" and for the winner, and while it runs a banner in the
## top-right corner with the time left, your place and the leader.
## main.gd passes every challenge message to show(); it decides what may be played.

const Money := preload("res://scripts/ui/money.gd")
const Fireworks := preload("res://scripts/ui/fireworks.gd")

const GOLD := Color("f3c969")
const RESULTS_SECONDS := 25.0  # the winner card closes by itself after this long
const TOP_PLACES := 5  # places listed on the winner card

## The winner card was closed (PLAY ON, or by itself).
signal results_closed

var phase := "idle"
var _deadline_ms := 0
var _seconds := 0
var _start_credits := 0
var _standings: Array = []
var _player := ""
var _last_second := -1
var _results_id := 0  # bumped so an older card's auto-close knows to stop

var _banner: PanelContainer
var _banner_time: Label
var _banner_rank: Label
var _card_root: Control
var _card_title: Label
var _card_big: Label
var _card_body: Label
var _card_places: Label
var _card_button: Button
var _fireworks: Fireworks


func _ready() -> void:
	# Already in the tree here, so the offsets must be set too or it keeps a zero size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_banner()
	_build_card()
	set_process(false)


## True while a card covers the game (nothing underneath may be played).
func is_blocking() -> bool:
	return _card_root.visible


## Shows a challenge message from the server for the player `player`.
func show_info(info: Dictionary, player: String) -> void:
	_player = player
	phase = str(info.get("phase", "idle"))
	_deadline_ms = Time.get_ticks_msec() + int(info.get("remaining_ms", 0))
	_seconds = int(info.get("seconds", 0))
	_start_credits = int(info.get("start_credits", info.get("credits", 0)))
	_standings = info.get("standings", [])
	_last_second = -1
	match phase:
		"countdown":
			_open_card("SLOT CHALLENGE", "",
				"Most money after %s wins.\nEveryone starts with %s. Get ready!" % [_duration(), Money.format(_start_credits)])
		"running":
			_card_root.visible = false
		"ended":
			_open_card("TIME'S UP!", "", "Waiting for the last spins to finish...")
		"results":
			_show_results(info)
		_:
			# Idle: close a countdown or "time's up" card (a cancelled challenge), but leave
			# a winner card up until it's read.
			if _card_button.visible == false:
				_card_root.visible = false
	_banner.visible = phase == "running"
	set_process(phase in ["countdown", "running"])
	_update_clock()


func _process(_delta: float) -> void:
	_update_clock()


func _update_clock() -> void:
	var left_ms := maxi(_deadline_ms - Time.get_ticks_msec(), 0)
	var second := ceili(left_ms / 1000.0)
	if phase == "countdown":
		_card_big.text = _clock(second)
		if second != _last_second and second <= 3 and second > 0:
			sounds_play("click")
	elif phase == "running":
		_banner_time.text = "CHALLENGE  %s" % _clock(second)
		# The last half minute in red.
		_banner_time.add_theme_color_override("font_color", Color("ff6b8a") if second <= 30 else GOLD)
		_banner_rank.text = _rank_text()
	_last_second = second


## "YOU #2 OF 5   LEADER alice $412.50"
func _rank_text() -> String:
	if _standings.is_empty():
		return ""
	var leader: Dictionary = _standings[0]
	var mine := -1
	for i in _standings.size():
		if str(_standings[i].id).nocasecmp_to(_player) == 0:
			mine = i
	var parts: Array[String] = []
	if mine >= 0:
		parts.append("YOU #%d OF %d" % [mine + 1, _standings.size()])
	if mine == 0:
		parts.append("YOU LEAD")
	else:
		parts.append("LEADER %s %s" % [leader.id, Money.format(int(leader.credits))])
	return "   ".join(parts)


func _show_results(info: Dictionary) -> void:
	sounds_play("jackpot" if _won(info) else "big_win")
	var winners: Array = info.get("winners", [])
	var best := int(info.get("winning_credits", 0))
	var body := ""
	if winners.is_empty():
		_open_card("CHALLENGE OVER", "", "Nobody played this time.")
	else:
		var names := " & ".join(PackedStringArray(winners.map(func(w): return str(w))))
		var mine := -1
		for i in _standings.size():
			if str(_standings[i].id).nocasecmp_to(_player) == 0:
				mine = i
		if _won(info):
			body = "You won with %s!" % Money.format(best) if winners.size() == 1 \
				else "You tied for first with %s!" % Money.format(best)
		elif mine >= 0:
			body = "With %s.\nYou finished #%d of %d with %s." % [Money.format(best), mine + 1, _standings.size(),
				Money.format(int(_standings[mine].credits))]
		else:
			body = "With %s." % Money.format(best)
		body += "\nEveryone is back to %s. Play on!" % Money.format(int(info.get("credits", 0)))
		_open_card("IT'S A TIE!" if winners.size() > 1 else "CHALLENGE WINNER", names, body)
	var places: Array[String] = []
	for i in mini(_standings.size(), TOP_PLACES):
		places.append("%d.  %s   %s" % [i + 1, _standings[i].id, Money.format(int(_standings[i].credits))])
	_card_places.text = "\n".join(places)
	_card_places.visible = not places.is_empty()
	_card_button.visible = true
	_fireworks.start()
	_results_id += 1
	var shown := _results_id
	await get_tree().create_timer(RESULTS_SECONDS).timeout
	if shown == _results_id and _card_root.visible:
		_close_results()


func _won(info: Dictionary) -> bool:
	for w in info.get("winners", []):
		if str(w).nocasecmp_to(_player) == 0:
			return true
	return false


func _open_card(title: String, big: String, body: String) -> void:
	_card_title.text = title
	_card_big.text = big
	_card_body.text = body
	_card_places.visible = false
	_card_button.visible = false
	_card_root.visible = true
	_fireworks.stop()


func _close_results() -> void:
	_card_root.visible = false
	_card_button.visible = false
	_fireworks.stop()
	results_closed.emit()


func sounds_play(sound: String) -> void:
	get_parent().sounds.play(sound)


func _duration() -> String:
	if _seconds % 60 == 0:
		return "%d minute%s" % [_seconds / 60, "" if _seconds == 60 else "s"]
	return _clock(_seconds)


static func _clock(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]


# --- UI ----------------------------------------------------------------------

func _build_banner() -> void:
	_banner = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.05, 0.18, 0.92)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(8)
	style.shadow_color = Color(0.9, 0.6, 0.15, 0.35)
	style.shadow_size = 10
	_banner.add_theme_stylebox_override("panel", style)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_banner.offset_left = -420
	_banner.offset_right = -16
	_banner.offset_top = 44
	_banner.visible = false
	add_child(_banner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_banner.add_child(box)
	_banner_time = _label(26, GOLD)
	box.add_child(_banner_time)
	_banner_rank = _label(15, Color.WHITE)
	box.add_child(_banner_rank)


func _build_card() -> void:
	_card_root = Control.new()
	_card_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_root.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing underneath can be clicked
	_card_root.visible = false
	add_child(_card_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_root.add_child(dim)
	# Fireworks over the dimmed game, behind the card (the winner's).
	_fireworks = Fireworks.new()
	_fireworks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fireworks.burst.connect(func() -> void:
		get_parent().sounds.play("firework", randf_range(0.85, 1.15), -9.0))
	_card_root.add_child(_fireworks)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_root.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b0714")
	style.border_color = GOLD
	style.set_border_width_all(5)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(30)
	style.shadow_color = Color(0.55, 0.3, 0.95, 0.5)
	style.shadow_size = 26
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_card_title = _label(40, GOLD)
	_card_title.add_theme_color_override("font_outline_color", Color("4a2c00"))
	_card_title.add_theme_constant_override("outline_size", 10)
	box.add_child(_card_title)
	_card_big = _label(72, Color.WHITE)
	_card_big.add_theme_color_override("font_outline_color", Color.BLACK)
	_card_big.add_theme_constant_override("outline_size", 12)
	box.add_child(_card_big)
	_card_body = _label(21, Color.WHITE)
	box.add_child(_card_body)
	_card_places = _label(18, Color(1, 1, 1, 0.8))
	box.add_child(_card_places)
	_card_button = Button.new()
	_card_button.text = "PLAY ON"
	_card_button.focus_mode = Control.FOCUS_NONE
	_card_button.custom_minimum_size = Vector2(220, 58)
	_card_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card_button.add_theme_font_size_override("font_size", 24)
	_card_button.pressed.connect(func() -> void:
		sounds_play("click")
		_close_results())
	box.add_child(_card_button)


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
