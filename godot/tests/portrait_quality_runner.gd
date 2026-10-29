extends SceneTree

## Banco di prova dei ritratti: tutte le acconciature, carnagioni e ruoli in
## grande (come nelle carte) e in piccolo (liste e HUD).
## godot --path godot --rendering-driver opengl3 -s res://tests/portrait_quality_runner.gd -- --test-mode [--out=/percorso.png]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	state.new_world("portrait-quality")
	var out := "res://tests/captures/portrait_quality.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.build_theme()
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color("#0d0a10")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var roles := ["Guardian", "Vanguard", "Lancer", "Ranger", "Mage", "Support"]
	# [stile capelli, femminile, carnagione, capelli, occhi, barba, veterano, cicatrice]
	var looks := [
		[0, false, 1, 0, 0, 0, false, false], [1, true, 0, 7, 5, 0, false, false], [2, false, 3, 5, 1, 2, true, false],
		[3, true, 4, 9, 4, 0, false, false], [4, false, 5, 1, 3, 0, false, true], [5, true, 2, 12, 7, 0, false, false],
		[0, false, 6, 8, 6, 1, false, false], [3, false, 2, 10, 2, 0, false, true], [1, true, 5, 2, 1, 0, false, false],
		[2, false, 0, 11, 5, 2, true, false], [5, true, 3, 13, 3, 0, false, false], [4, true, 1, 6, 4, 0, false, false],
	]
	var heroes: Array = []
	for i in looks.size():
		var hero: Dictionary = state.generate_hero("pq-%d" % i, [1, 2, 3, 4, 5, 6, 7, 3, 4, 5, 2, 6][i], roles[i % roles.size()])
		heroes.append(hero)
	for i in looks.size():
		var l: Array = looks[i]
		var cell := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#141a26")
		cell.add_theme_stylebox_override("panel", style)
		cell.position = Vector2(14 + (i % 6) * 316, 8 + int(i / 6) * 376)
		cell.size = Vector2(272, 368)
		cell.clip_contents = true
		ui.add_child(cell)
		var p: HeroPortrait = HeroPortrait.new()
		p.setup(heroes[i], 300, "bust")
		_force(p, l, state)
		cell.add_child(p)
		p.position = Vector2.ZERO
		p.size = cell.size
		p.custom_minimum_size = Vector2.ZERO
		p.queue_redraw()
	for i in looks.size():
		var p: HeroPortrait = HeroPortrait.new()
		p.setup(heroes[i], 96 if i < 6 else 64)
		_force(p, looks[i], state)
		p.position = Vector2(20 + i * 108, 768) if i < 6 else Vector2(680 + (i - 6) * 80, 788)
		ui.add_child(p)
	if heroes.size() > 3:
		var dead: Dictionary = heroes[3].duplicate(true)
		dead["state"] = "DEAD"
		var pd: HeroPortrait = HeroPortrait.new()
		pd.setup(dead, 96)
		_force(pd, looks[3], state)
		pd.position = Vector2(1180, 768)
		ui.add_child(pd)
	await create_timer(0.6).timeout
	var path := out if out.begins_with("/") else ProjectSettings.globalize_path(out)
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)
	quit(0)

func _force(p: HeroPortrait, l: Array, state) -> void:
	p.look["hair_style"] = l[0]
	p.look["fem"] = l[1]
	p.look["skin"] = Color(state.SKIN_TONES[l[2]])
	p.look["hair"] = Color(state.HAIR_COLORS[l[3]])
	p.look["eyes"] = Color(state.EYE_COLORS[l[4]])
	p.look["beard"] = l[5]
	p.look["veteran"] = l[6]
	p.look["scar"] = l[7]
	if l[6]: p.look["hair"] = p.look["hair"].lerp(Color("#b9b4b4"), 0.62)
	p.queue_redraw()
