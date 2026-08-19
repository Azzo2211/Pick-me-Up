extends Control
class_name HeroPortrait

var hero_name := "HERO"
var role := "Guardian"
var hue := 45.0
var rarity := 1
var dead := false

func setup(hero: Dictionary) -> void:
	hero_name = hero.get("name", "Hero")
	role = hero.get("role", "Guardian")
	hue = float(hero.get("hue", 45))
	rarity = clampi(int(hero.get("current_rarity", 1)), 1, 7)
	dead = hero.get("state", "ALIVE") != "ALIVE"
	queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(104, 132)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _rarity_color() -> Color:
	match rarity:
		1: return Color("#8a94a6")
		2: return Color("#39c5bb")
		3: return Color("#4ba3ff")
		4: return Color("#8f5bff")
		5: return Color("#f4c95d")
		6: return Color("#70eeff")
		7: return Color("#fff2be")
		_: return Color("#8a94a6")

func _frame_points(inset: float) -> PackedVector2Array:
	var cut := 8.0
	return PackedVector2Array([
		Vector2(inset + cut, inset),
		Vector2(size.x - inset - cut, inset),
		Vector2(size.x - inset, inset + cut),
		Vector2(size.x - inset, size.y - inset - cut),
		Vector2(size.x - inset - cut, size.y - inset),
		Vector2(inset + cut, size.y - inset),
		Vector2(inset, size.y - inset - cut),
		Vector2(inset, inset + cut),
		Vector2(inset + cut, inset),
	])

func _draw() -> void:
	var frame := _rarity_color()
	var base := Color.from_hsv(hue / 360.0, 0.46, 0.38 if not dead else 0.19)
	var plate := _frame_points(2.0)
	draw_colored_polygon(plate, Color("#090e18"))
	for i in range(5):
		var radius := size.x * (0.54 - i * 0.075)
		var glow := base.lerp(frame, 0.35)
		glow.a = 0.075 + float(4 - i) * 0.025
		draw_circle(Vector2(size.x * 0.52, size.y * 0.43), radius, glow)

	var horizon := PackedVector2Array([
		Vector2(8, size.y * 0.73), Vector2(size.x * 0.26, size.y * 0.58),
		Vector2(size.x * 0.52, size.y * 0.64), Vector2(size.x * 0.76, size.y * 0.52),
		Vector2(size.x - 8, size.y * 0.66), Vector2(size.x - 8, size.y - 9),
		Vector2(8, size.y - 9),
	])
	var horizon_color := base.darkened(0.42)
	horizon_color.a = 0.75
	draw_colored_polygon(horizon, horizon_color)

	var skin := Color("#c9ad8e") if not dead else Color("#717785")
	var face_center := Vector2(size.x * 0.52, size.y * 0.29)
	draw_circle(face_center, size.x * 0.125, skin)
	var hair := PackedVector2Array([
		face_center + Vector2(-14, -2), face_center + Vector2(-10, -14),
		face_center + Vector2(2, -18), face_center + Vector2(14, -10),
		face_center + Vector2(12, 2), face_center + Vector2(5, -7),
		face_center + Vector2(-3, -2),
	])
	draw_colored_polygon(hair, base.darkened(0.62))

	var cloak := PackedVector2Array([
		Vector2(size.x * 0.16, size.y * 0.89), Vector2(size.x * 0.25, size.y * 0.52),
		Vector2(size.x * 0.40, size.y * 0.42), Vector2(size.x * 0.64, size.y * 0.42),
		Vector2(size.x * 0.79, size.y * 0.52), Vector2(size.x * 0.90, size.y * 0.89),
	])
	draw_colored_polygon(cloak, base.lightened(0.16))
	draw_polyline(PackedVector2Array([Vector2(size.x * 0.26, size.y * 0.55), Vector2(size.x * 0.52, size.y * 0.72), Vector2(size.x * 0.78, size.y * 0.55)]), frame.darkened(0.12), 1.5)

	var weapon_color := Color("#dce6f5") if rarity < 5 else frame
	if role in ["Ranger", "Mage", "Support"]:
		draw_line(Vector2(size.x * 0.74, size.y * 0.60), Vector2(size.x * 0.87, size.y * 0.19), weapon_color, 2.0)
		draw_circle(Vector2(size.x * 0.875, size.y * 0.17), 4.0, frame)
	else:
		draw_line(Vector2(size.x * 0.69, size.y * 0.60), Vector2(size.x * 0.88, size.y * 0.18), weapon_color, 2.4)
		draw_line(Vector2(size.x * 0.79, size.y * 0.32), Vector2(size.x * 0.90, size.y * 0.37), weapon_color, 1.8)

	draw_polyline(_frame_points(2.0), frame, 2.0 if rarity >= 4 else 1.2, true)
	if rarity >= 6:
		var inner := frame.darkened(0.18) if rarity == 6 else Color("#9a6bff")
		draw_polyline(_frame_points(6.0), inner, 1.0, true)

	var marker_y := size.y - 6.0
	var total_width := float(rarity) * 8.0
	for i in range(rarity):
		var x := size.x * 0.5 - total_width * 0.5 + float(i) * 8.0 + 4.0
		var diamond := PackedVector2Array([Vector2(x, marker_y - 4), Vector2(x + 3, marker_y - 1), Vector2(x, marker_y + 2), Vector2(x - 3, marker_y - 1)])
		draw_colored_polygon(diamond, frame)

	if dead:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(0.04, 0.04, 0.07, 0.56))
		draw_line(Vector2(13, 13), size - Vector2(13, 13), Color("#ff4d5a"), 3.0)
		draw_line(Vector2(size.x - 13, 13), Vector2(13, size.y - 13), Color("#ff4d5a"), 3.0)
