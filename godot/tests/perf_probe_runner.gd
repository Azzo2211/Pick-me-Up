extends SceneTree

## Misura i tempi di generazione della base (senza rendering).
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state: RiftwardState = root.get_node("GameState")
	state.new_world("perf-seed")
	var t0 := Time.get_ticks_msec()
	var view := HubView.new()
	root.add_child(view)
	await process_frame
	var t1 := Time.get_ticks_msec()
	view.refresh(state)
	var t2 := Time.get_ticks_msec()
	state.data.world.base_level = 3
	view.refresh(state)
	var t3 := Time.get_ticks_msec()
	state.assign_hero(state.data.heroes[0].id, "training")
	view.refresh(state)
	var t4 := Time.get_ticks_msec()
	var meshes := 0
	var stack: Array = [view]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D or n is MultiMeshInstance3D: meshes += 1
		stack.append_array(n.get_children())
	print("ready %d ms · prima refresh %d ms · cambio livello %d ms · refresh normale %d ms · mesh %d" % [t1 - t0, t2 - t1, t3 - t2, t4 - t3, meshes])
	quit(0)
