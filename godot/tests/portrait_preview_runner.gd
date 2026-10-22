extends SceneTree

## Rende una griglia di carte e ritratti per controllare lo stile (serve un display).
## godot --path godot --rendering-driver opengl3 -s res://tests/portrait_preview_runner.gd -- --test-mode

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	state.new_world("portrait-preview")
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.build_theme()
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color("#0d0a10")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.position = Vector2(20, 20)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	ui.add_child(grid)
	var heroes: Array = []
	for i in 16:
		var rarity: int = [1, 1, 2, 3, 4, 5, 6, 7][i % 8]
		heroes.append(state.generate_hero("portrait-%d" % i, rarity, ["Guardian", "Vanguard", "Lancer", "Ranger", "Mage", "Support"][i % 6]))
	heroes[3]["state"] = "DEAD"
	for i in 8:
		var card: HeroCard = HeroCard.new()
		card.setup(heroes[i], 200.0, "Caduto in\nbattaglia" if i == 3 else "")
		grid.add_child(card)
	for i in range(8, 16):
		var box := VBoxContainer.new()
		var p: HeroPortrait = HeroPortrait.new()
		p.setup(heroes[i], 150)
		box.add_child(p)
		var small: HeroPortrait = HeroPortrait.new()
		small.setup(heroes[i], 64)
		box.add_child(small)
		grid.add_child(box)
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png("res://tests/captures/portraits.png")
	print("CAPTURE portraits")
	quit(0)
