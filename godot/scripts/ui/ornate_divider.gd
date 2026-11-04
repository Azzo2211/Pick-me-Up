extends Control
class_name OrnateDivider

## Linea divisoria neon che sfuma ai lati, con un segmento acceso al centro.

var color := Color("#46dcf2")

func _ready() -> void:
	custom_minimum_size.y = 10
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var y := size.y * 0.5
	var steps := 24
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var a := 1.0 - absf((t0 + t1) - 1.0)
		var c := color
		c.a = a * 0.6
		draw_line(Vector2(size.x * t0, y), Vector2(size.x * t1, y), c, 1.0, true)
	var center := Vector2(size.x * 0.5, y)
	draw_line(center - Vector2(18, 0), center + Vector2(18, 0), color.lightened(0.3), 2.5, true)
