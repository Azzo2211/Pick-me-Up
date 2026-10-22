extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	state.new_world("portrait-zoom")
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.build_theme()
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color("#0d0a10")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var row := HBoxContainer.new()
	row.position = Vector2(20, 20)
	row.add_theme_constant_override("separation", 20)
	ui.add_child(row)
	var picks := [["zoom-a", 3, "Vanguard"], ["zoom-b", 5, "Mage"], ["zoom-c", 4, "Guardian"], ["zoom-d", 2, "Ranger"]]
	for pick in picks:
		var hero: Dictionary = state.generate_hero(pick[0], pick[1], pick[2])
		var card: HeroCard = HeroCard.new()
		card.setup(hero, 360.0)
		row.add_child(card)
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png("res://tests/captures/portrait_zoom.png")
	quit(0)
