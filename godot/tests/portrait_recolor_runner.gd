extends SceneTree

## Stesso volto dipinto con i colori di capelli e occhi del generatore personaggi:
## la prima carta di ogni riga è il dipinto originale. Serve un display.
## xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/portrait_recolor_runner.gd -- --test-mode

const FACES := ["p039", "p052", "p010"]
## [capelli, occhi] dal generatore; la prima colonna resta come dipinta.
const LOOKS := [["", ""], ["brown", "green"], ["blond", "blue"], ["auburn", "amber"], ["silver", "violet"], ["blue", "gold"], ["pink", "teal"]]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	state.new_world("portrait-recolor")
	var generator = load("res://scripts/characters/character_generator.gd")
	var library = load("res://scripts/portrait_library.gd")
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.build_theme()
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color("#0d0a10")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = LOOKS.size()
	grid.position = Vector2(40, 12)
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	ui.add_child(grid)
	for r in FACES.size():
		for c in LOOKS.size():
			var hero: Dictionary = state.generate_hero("recolor-%d-%d" % [r, c], [3, 4, 5, 6, 7, 2, 1][c], "Mage")
			hero.portrait = FACES[r]
			var hair: String = LOOKS[c][0] if not LOOKS[c][0].is_empty() else str(library.entry(FACES[r]).hair)
			hero.appearance.hair_color = hair
			hero.appearance.hair_hex = generator.HAIR_COLORS.get(hair, "#25222b")
			if not LOOKS[c][1].is_empty():
				hero.appearance.eye_color = LOOKS[c][1]
				hero.appearance.eye_hex = generator.EYE_COLORS[LOOKS[c][1]]
			var card: HeroCard = HeroCard.new()
			card.setup(hero, 186.0)
			grid.add_child(card)
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png("res://tests/captures/portrait_recolor.png")
	print("CAPTURE portrait_recolor")
	quit(0)
