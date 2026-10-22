extends Control
class_name UIIcon

## Piccole icone vettoriali (risorse e materiali), disegnate in codice.

var kind := "gold":
	set(value):
		kind = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _circle_pts(c: Vector2, r: float, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n: pts.append(c + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r)
	return pts

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.42
	match kind:
		"gold":
			draw_circle(c + Vector2(1, 1.5), r, Color(0, 0, 0, 0.45))
			draw_circle(c, r, Color("#9a6b22"))
			draw_circle(c, r * 0.86, Color("#e3b14d"))
			draw_arc(c, r * 0.62, 0, TAU, 24, Color("#a8752a"), maxf(1.0, s * 0.06), true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.34), c + Vector2(r * 0.22, 0), c + Vector2(0, r * 0.34), c + Vector2(-r * 0.22, 0)]), Color("#fff0c2"))
		"gems":
			var top := PackedVector2Array([c + Vector2(-r * 0.9, -r * 0.2), c + Vector2(-r * 0.5, -r * 0.7), c + Vector2(r * 0.5, -r * 0.7), c + Vector2(r * 0.9, -r * 0.2)])
			var gem := top.duplicate()
			gem.append(c + Vector2(0, r * 0.95))
			draw_colored_polygon(gem, Color("#2f8fb8"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.9, -r * 0.2), c + Vector2(r * 0.9, -r * 0.2), c + Vector2(0, r * 0.95)]), Color("#59c6ea"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.7), c + Vector2(0, -r * 0.2), c + Vector2(-r * 0.9, -r * 0.2)]), Color("#b9ecff"))
			draw_polyline(PackedVector2Array([gem[0], gem[1], gem[2], gem[3], gem[4], gem[0]]), Color("#0f3a4f"), maxf(1.0, s * 0.05), true)
		"stones":
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.72, -r * 0.35), c + Vector2(r * 0.6, r * 0.7), c + Vector2(-r * 0.15, r * 0.95), c + Vector2(-r * 0.75, r * 0.3), c + Vector2(-r * 0.6, -r * 0.5)])
			draw_colored_polygon(pts, Color("#5b3f8f"))
			var inner := PackedVector2Array()
			for p in pts: inner.append(c + (p - c) * 0.72)
			draw_colored_polygon(inner, Color("#8a63d2"))
			draw_line(c + Vector2(-r * 0.2, -r * 0.45), c + Vector2(r * 0.15, r * 0.45), Color("#efe2ff"), maxf(1.2, s * 0.07), true)
			draw_line(c + Vector2(-r * 0.3, 0), c + Vector2(r * 0.3, -r * 0.05), Color("#efe2ff"), maxf(1.2, s * 0.06), true)
		"ore":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r, r * 0.4), c + Vector2(-r * 0.5, -r * 0.6), c + Vector2(r * 0.3, -r * 0.8), c + Vector2(r, 0), c + Vector2(r * 0.4, r * 0.8), c + Vector2(-r * 0.6, r * 0.8)]), Color("#6d7380"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.6), c + Vector2(r * 0.3, -r * 0.8), c + Vector2(0, -r * 0.1)]), Color("#aab2bf"))
		"leather":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.9, -r * 0.6), c + Vector2(r * 0.9, -r * 0.7), c + Vector2(r * 0.7, r * 0.2), c + Vector2(r * 0.95, r * 0.8), c + Vector2(-r * 0.8, r * 0.75), c + Vector2(-r * 0.6, 0)]), Color("#8a5a35"))
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.35), c + Vector2(r * 0.55, -r * 0.4)]), Color("#c08a5a"), 1.2, true)
		"wood":
			draw_rect(Rect2(c + Vector2(-r, -r * 0.35), Vector2(r * 2.0, r * 0.7)), Color("#7a5232"))
			draw_circle(c + Vector2(r, 0), r * 0.35, Color("#c79a62"))
			draw_arc(c + Vector2(r, 0), r * 0.2, 0, TAU, 12, Color("#8a5f36"), 1.0, true)
		"herbs":
			for k in 3:
				var a := -PI / 2.0 + (k - 1) * 0.6
				var tip := c + Vector2(cos(a), sin(a)) * r
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.8), tip + Vector2(-r * 0.2, 0), tip, tip + Vector2(r * 0.2, 0)]), Color("#5d9a4e").lightened(k * 0.08))
		"cores":
			draw_circle(c, r * 0.95, Color(0.62, 0.45, 1.0, 0.25))
			draw_circle(c, r * 0.6, Color("#b48cff"))
			draw_circle(c + Vector2(-r * 0.15, -r * 0.15), r * 0.22, Color("#f3eaff"))
		"medicine":
			draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.6), Vector2(r * 1.4, r * 1.3)), Color("#d9d2c4"))
			draw_rect(Rect2(c + Vector2(-r * 0.12, -r * 0.4), Vector2(r * 0.24, r * 0.9)), Color("#b8323f"))
			draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.07), Vector2(r * 0.9, r * 0.24)), Color("#b8323f"))
		"star":
			UIKit.draw_star(self, c, r, Color("#e6b24c"))
		_:
			draw_circle(c, r * 0.6, UIKit.GOLD)
