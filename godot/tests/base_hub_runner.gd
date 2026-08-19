extends SceneTree

var failed := 0
var tested := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	tested += 1
	if condition:
		print("PASS  " + label)
	else:
		failed += 1
		push_error("FAIL  " + label)

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Avvia questa suite con: -- --test-mode")
		quit(2)
		return
	print("Riftward Base/HUB vertical slice suite")
	var state := RiftwardState.new()
	state.name = "GameState"
	root.add_child(state)
	state.new_world("base-hub-test-seed")
	state.data.tutorial_seen = true
	var main_scene: PackedScene = load("res://Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	var hub = main.base_hub
	_check(main.current_view == "hub" and hub.visible, "la Home apre la base visuale")
	_check(not is_instance_valid(main.sidebar_panel) and not main.content_scroll.visible, "la sidebar non viene più creata")
	var configured_viewport := Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")), int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	_check(configured_viewport == Vector2i(1920, 890), "viewport PC impostato a 1920x890")
	_check(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "expand", "ridimensionamento senza fasce nere")
	_check(hub.buildings.size() == 8, "otto punti interattivi allineati alla Base Lv.1")
	_check(hub.buildings.all(func(building): return building._has_point(building.size * Vector2(0.5, 0.48)) and not building._has_point(Vector2(-10, -10))), "sagome cliccabili coerenti con gli edifici")
	_check(hub.building_data.all(func(data): return not data.navigation_path.is_empty()), "ogni edificio dispone di un percorso sui sentieri")
	_check(hub.hero_agents.size() >= 3, "Hero Agent presenti nella base")
	var runtime_state = hub.get_node("/root/GameState")
	runtime_state.new_world("base-hub-runtime-sync")
	await process_frame
	hub.refresh_state()
	var previous_agents: int = hub.hero_agents.size()
	runtime_state.data.heroes.append(runtime_state.generate_hero("base-hub-extra-agent", 2, "Ranger"))
	hub.refresh_state()
	_check(hub.hero_agents.size() == previous_agents + 1, "agenti sincronizzati con il roster vivo")
	_check(hub.building_by_id.has("portal") and hub.building_by_id.has("training"), "portale e training interattivi")
	_check(hub.building_by_id["warehouse"].data.secondary_interaction_type == "archive", "Archivio accessibile dal Magazzino")
	_check(hub.building_by_id["plaza"].data.secondary_interaction_type == "dev", "DEV / QA accessibile dal Nexus")
	_check(hub.building_by_id["fusion"].data.interaction_type == "merge", "il Centro di Fusione apre la fusione")
	_check(hub.building_by_id["summoning"].data.interaction_type == "summon", "il Centro Evocativo apre l'evocazione")

	var training = hub.building_by_id["training"]
	hub._select_building(training)
	await process_frame
	_check(hub.context_panel.visible and hub.selected_building == training, "selezione apre il pannello contestuale")
	_check(not training.name_label.visible, "clic e hover non mostrano indicatori accanto agli edifici")
	training._set_hovered(true)
	_check(not training.name_label.visible, "l'area cliccabile resta invisibile al passaggio del mouse")
	training._set_hovered(false)
	var old_zoom: float = hub.camera_zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = Vector2(640, 360)
	hub._gui_input(wheel)
	_check(is_equal_approx(hub.camera_zoom, old_zoom), "rotellina disattivata sulla mappa")
	_check(hub.world_root.size.x * hub.camera_zoom >= hub.size.x and hub.world_root.size.y * hub.camera_zoom >= hub.size.y, "la mappa copre tutta la visuale")
	var old_center: Vector2 = hub.camera_center
	hub.dragging = true
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(48, 20)
	hub._gui_input(drag)
	hub.dragging = false
	var camera_inside_world: bool = hub.camera_center.x >= 0.0 and hub.camera_center.x <= hub.world_root.size.x and hub.camera_center.y >= 0.0 and hub.camera_center.y <= hub.world_root.size.y
	_check(camera_inside_world and (hub.camera_center.distance_to(old_center) > 5.0 or hub.world_root.size.x * hub.camera_zoom <= hub.size.x), "pan camera confinato alla base")
	_check(bool(hub.notification_system.get_state("portal").active), "notifiche diegetiche disponibili")

	var old_level: int = training.data.level
	var upgrade: Dictionary = hub.upgrade_system.upgrade(training.data)
	_check(upgrade.ok and training.data.level == old_level + 1, "upgrade modifica il livello della struttura")
	training.set_level(training.data.level)
	_check(training.name_label.text.contains("LV.%d" % training.data.level), "upgrade modifica la variante visuale mostrata")

	var agent = hub.hero_agents[0]
	var planned_route: Array[Vector2] = agent._route_to(hub.building_by_id["portal"].data, hub.building_by_id["portal"].data.activity_slots[0], hub.building_data)
	_check(planned_route.size() >= 4, "Hero Agent pianifica waypoint evitando gli edifici")
	_check(_route_avoids_buildings(agent.current_position, planned_route, hub.buildings, ["plaza", "portal"]), "percorso verso il Portale non attraversa altre strutture")
	var start_position: Vector2 = agent.current_position
	for i in range(120): agent.step(0.1, hub.building_data)
	_check(agent.current_position.distance_to(start_position) > 8.0, "Hero Agent percorre la base")
	_check(not agent.current_building.is_empty() and not agent.current_activity.is_empty(), "Hero Agent espone stato e attività")

	hub._open_selected_facility()
	await process_frame
	_check(main.current_view == "heroes", "l'edificio apre il sistema esistente corretto")
	main._set_view("hub")
	hub.drag_distance = 0.0
	hub._select_building(hub.building_by_id["fusion"])
	hub._open_selected_facility()
	await process_frame
	_check(main.current_view == "merge", "il Centro di Fusione apre la sintesi di tre eroi")
	main._set_view("hub")
	hub.drag_distance = 0.0
	hub._select_building(hub.building_by_id["summoning"])
	hub._open_selected_facility()
	await process_frame
	_check(main.current_view == "summon", "il Centro Evocativo apre le risonanze")
	main._set_view("hub")
	hub.drag_distance = 0.0
	hub._select_building(hub.building_by_id["warehouse"])
	hub._open_secondary_facility()
	await process_frame
	_check(main.current_view == "archive", "il Magazzino apre l'Archivio senza sidebar")
	main._set_view("hub")
	hub.drag_distance = 0.0
	hub._select_building(hub.building_by_id["plaza"])
	hub._open_secondary_facility()
	await process_frame
	_check(main.current_view == "dev", "il Nexus apre DEV / QA senza sidebar")
	main.brand_button.pressed.emit()
	await process_frame
	_check(main.current_view == "hub", "il comando superiore torna sempre alla Base")

	main.queue_free()
	state.queue_free()
	await process_frame
	print("\nRisultato Base/HUB: %d passati, %d falliti" % [tested - failed, failed])
	quit(0 if failed == 0 else 1)

func _route_avoids_buildings(start: Vector2, route: Array[Vector2], buildings: Array[BaseBuilding], ignored_ids: Array[String]) -> bool:
	var previous := start
	for target in route:
		var sample_count := maxi(1, ceili(previous.distance_to(target) / 10.0))
		for index in range(sample_count + 1):
			var point := previous.lerp(target, float(index) / float(sample_count))
			for building in buildings:
				if building.data.id in ignored_ids: continue
				if building._has_point(point - building.position): return false
		previous = target
	return true
