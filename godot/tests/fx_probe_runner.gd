extends SceneTree

## Banco di prova delle animazioni: salva una sequenza di fotogrammi (da montare in GIF/video).
##   xvfb-run godot --path godot --fixed-fps 30 -s res://tests/fx_probe_runner.gd -- --test-mode --scene=summon [--rarities=1,2,3,4,5,6,7,3,2,1] [--seconds=7] [--out=/cartella]
##   ... --scene=kill [--floor=3] [--seconds=14]
## Con --fixed-fps ogni fotogramma vale 1/30 di secondo, anche se il PC renderizza più lento.

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.get_slice("=", 1)
	return fallback

func _run() -> void:
	var state = root.get_node("GameState")
	var out := _arg("out", ProjectSettings.globalize_path("res://tests/captures/fx"))
	DirAccess.make_dir_recursive_absolute(out)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.build_theme()
	root.add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color("#0b111a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var scene := _arg("scene", "summon")
	if scene == "summon":
		var heroes := []
		var i := 0
		for r in _arg("rarities", "1,2,3,4,5,6,7,3,2,1").split(","):
			heroes.append(state.generate_hero("fx-summon-%d" % i, int(r)))
			i += 1
		var event: Control = load("res://scripts/ui/summon_event.gd").new().setup(heroes, "Evocazione di prova")
		ui.add_child(event)
	else:
		state.new_world("fx-kill")
		for hero in state.data.heroes:
			for l in 14: state._apply_level_up(hero)
		var floor_index := int(_arg("floor", "3"))
		state.data.world.max_floor = floor_index
		var start: Dictionary = state.begin_mission(floor_index)
		var battle = load("res://scripts/battle/battle_scene.gd").new()
		battle.setup(start.stage, start.party, int(start.attempt))
		ui.add_child(battle)
		battle.speed_scale = float(_arg("speed", "1.0"))
	var frames := int(float(_arg("seconds", "7")) * 30.0)
	var every := int(_arg("every", "1"))
	for f in frames:
		await process_frame
		if f % every == 0:
			root.get_texture().get_image().save_png(out.path_join("f%04d.png" % (f / every)))
	print("FRAMES ", frames / every, " ", out)
	quit(0)
