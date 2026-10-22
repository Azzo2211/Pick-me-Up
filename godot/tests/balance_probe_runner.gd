extends SceneTree

## Simula alcuni piani con la squadra iniziale a vari livelli e stampa gli esiti.
## godot --headless --path godot -s res://tests/balance_probe_runner.gd -- --test-mode

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = root.get_node("GameState")
	var battle_script := load("res://scripts/battle/battle_scene.gd")
	for level in [1, 6, 10, 15]:
		for floor_index in [1, 2, 3, 4, 5, 8, 10]:
			var wins := 0
			var deaths := 0
			var times := []
			for trial in 2:
				state.new_world("balance-%d-%d-%d" % [level, floor_index, trial])
				for hero in state.data.heroes:
					for i in level - 1: state._apply_level_up(hero)
				state.data.world.max_floor = floor_index
				var start: Dictionary = state.begin_mission(floor_index)
				var battle = battle_script.new()
				battle.setup(start.stage, start.party, int(start.attempt))
				root.add_child(battle)
				var guard := 0
				while not battle.completed and guard < 3000:
					battle.accumulator += 0.1
					while battle.accumulator >= battle.TICK and not battle.completed:
						battle._tick(battle.TICK)
						battle.accumulator -= battle.TICK
					guard += 1
				var victory: bool = battle._heroes().size() > 0 and battle.completed and (battle.elapsed < float(start.stage.duration) or str(start.stage.type) == "Survival") and not battle.command_state.extracting and float(battle.objective.beacon) > 0.0
				if victory: wins += 1
				for u in battle.units:
					if u.hero and not u.alive: deaths += 1
				times.append(roundi(battle.elapsed))
				battle.queue_free()
				await process_frame
			print("Lv%2d  Piano %2d (%s)  vittorie %d/2  morti %d  durate %s" % [level, floor_index, state.get_stage(floor_index).descriptor.type, wins, deaths, str(times)])
	quit(0)
