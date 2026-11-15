extends Control
## One spinning reel: a clipped window of SymbolTiles scrolling down the reel strip.
## start_spin() winds up and spins at constant speed; stop_at() lands on the engine's
## stop with a small overshoot-and-settle bounce, then emits `stopped`.
## set_anticipation() puts a pulsing gold frame on the reel while it teases a feature.

signal stopped

const SymbolTile := preload("res://scripts/ui/symbol_tile.gd")

const ROWS := 3
const SPEED := 22.0  # symbols per second
const WIND_UP := 0.3  # symbols the reel backs up before spinning
const LEAD_IN := 5  # symbols scrolled between stop_at() and landing
const QUICK_LEAD_IN := 1  # lead-in for a slam stop
const BOUNCE := 0.22  # overshoot past the stop, in symbols
const GOLD := Color("f3c969")

var strip: Array = []
## Strip index shown in the top row. Decreasing it scrolls the reel downward.
var pos := 0.0:
	set(value):
		pos = value
		_layout()

var _cell_size := Vector2.ZERO
var _gap := 0.0
var _spinning := false
var _tiles: Array = []
var _tween: Tween
var _frame: Panel
var _frame_tween: Tween


func setup(reel_strip: Array, cell_size: Vector2, gap: float, start_stop: int) -> void:
	strip = reel_strip
	_cell_size = cell_size
	_gap = gap
	clip_contents = true
	custom_minimum_size = Vector2(cell_size.x, cell_size.y * ROWS + gap * (ROWS - 1))
	# One extra tile so a partly scrolled reel never shows a gap.
	for i in ROWS + 1:
		var tile := SymbolTile.new()
		tile.size = cell_size
		add_child(tile)
		_tiles.append(tile)
	# Anticipation frame, drawn above the tiles.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(GOLD, 0.08)
	style.border_color = GOLD
	style.set_border_width_all(5)
	style.set_corner_radius_all(10)
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", style)
	_frame.size = custom_minimum_size
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)
	pos = start_stop


## The tile showing `row` (only meaningful while the reel is stopped).
func tile(row: int) -> SymbolTile:
	return _tiles[row]


func start_spin() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "pos", pos + WIND_UP, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void: _spinning = true)


func set_anticipation(on: bool) -> void:
	if _frame_tween:
		_frame_tween.kill()
	_frame.visible = on
	if on:
		_frame.modulate.a = 1.0
		_frame_tween = create_tween().set_loops()
		_frame_tween.tween_property(_frame, "modulate:a", 0.35, 0.25)
		_frame_tween.tween_property(_frame, "modulate:a", 1.0, 0.25)


## Lands on `stop`. quick (slam stop) skips most of the lead-in.
func stop_at(stop: int, quick: bool = false) -> void:
	if _tween:
		_tween.kill()
	_spinning = false
	# Jump the strip so the result is a few symbols above the window. At full speed the
	# swap is invisible, and it keeps every reel's stop time the same.
	pos = stop + (QUICK_LEAD_IN if quick else LEAD_IN) + (pos - floorf(pos))
	_tween = create_tween()
	_tween.tween_property(self, "pos", stop - BOUNCE, (pos - stop + BOUNCE) / SPEED)
	_tween.tween_property(self, "pos", float(stop), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(stopped.emit)


func _process(delta: float) -> void:
	if _spinning:
		pos = fposmod(pos - SPEED * delta, strip.size())


func _layout() -> void:
	if _tiles.is_empty():
		return
	var pitch := _cell_size.y + _gap
	var top := floori(pos)
	var frac := pos - top
	for j in _tiles.size():
		var t: SymbolTile = _tiles[j]
		t.position = Vector2(0, (j - frac) * pitch)
		var symbol: String = strip[posmod(top + j, strip.size())]
		# Re-skin only when needed; this also clears orb captions once the reel moves.
		if t.symbol != symbol or not t.caption.is_empty():
			t.show_symbol(symbol)
