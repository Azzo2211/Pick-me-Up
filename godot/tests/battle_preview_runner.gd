extends SceneTree

## Cattura la battaglia su più piani (serve un display).
## godot --path godot --rendering-driver opengl3 -s res://tests/battle_preview_runner.gd -- --test-mode

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	var battle_script := load("res://scripts/battle/battle_scene.gd")
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.build_theme()
	root.add_child(ui)
	for floor_index in [3, 4, 5]:
		state.new_world("battle-preview-%d" % floor_index)
		for hero in state.data.heroes:
			for i in 6: state._apply_level_up(hero)
		state.data.world.max_floor = floor_index
		var start: Dictionary = state.begin_mission(floor_index)
		var battle = battle_script.new()
		battle.setup(start.stage, start.party, int(start.attempt))
		ui.add_child(battle)
		battle.speed_scale = 2.0
		await create_timer(5.0).timeout
		_capture("res://tests/captures/battle_floor%d_a.png" % floor_index)
		await create_timer(5.0).timeout
		_capture("res://tests/captures/battle_floor%d_b.png" % floor_index)
		battle.queue_free()
		await process_frame
	quit(0)

func _capture(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)
