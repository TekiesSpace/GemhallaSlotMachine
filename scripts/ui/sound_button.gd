extends Button
## The sound toggle: a microphone drawn in code. Deep gold when sound is on, pale and
## faded when it's off.

const ON_COLOR := Color("d99a2b")
const OFF_COLOR := Color(0.85, 0.82, 0.92, 0.45)

var sound_on := true:
	set(value):
		sound_on = value
		tooltip_text = "Sound on (click to mute)" if value else "Sound off (click to turn on)"
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(46, 40)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Sound on (click to mute)"


func _draw() -> void:
	var color := ON_COLOR if sound_on else OFF_COLOR
	var c := size / 2
	var unit := minf(size.x, size.y) / 40.0
	# Capsule head.
	var head := Rect2(c + Vector2(-5, -14) * unit, Vector2(10, 17) * unit)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(5 * unit))
	draw_style_box(style, head)
	# Cradle around the head, stem and base.
	var width := 2.2 * unit
	draw_arc(c + Vector2(0, -2) * unit, 8.5 * unit, 0.0, PI, 24, color, width, true)
	draw_line(c + Vector2(0, 6.5) * unit, c + Vector2(0, 12) * unit, color, width, true)
	draw_line(c + Vector2(-6, 12.5) * unit, c + Vector2(6, 12.5) * unit, color, width, true)
