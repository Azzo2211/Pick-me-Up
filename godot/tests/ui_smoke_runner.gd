extends SceneTree

## Smoke test dell'interfaccia: apre ogni pannello, esegue le azioni principali
## e completa una missione intera. Avvio:
## godot --headless --path godot -s res://tests/ui_smoke_runner.gd -- --test-mode

var failures := 0
var checks := 0
var state: RiftwardState
var main

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS  " + label)
	else:
		failures += 1
		push_error("FAIL  " + label)

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--test-mode"):
		push_error("Avvia questa suite con: -- --test-mode")
		quit(2)
		return
	print("Riftward Godot UI smoke suite")
	state = root.get_node("GameState")
	state.new_world("ui-smoke-seed")
	state.data.tutorial_seen = true
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var world: HubWorld = main.hub.world
	_check(main.hub != null and main.hub.visible, "la base 3D è la schermata principale")
	_check(world.buildings.has("training") and world.buildings.has("dormitory") and world.buildings.has("merging") and world.buildings.has("gate"), "Base Lv.1: addestramento, dormitorio, fusione e portale presenti")
	_check(not world.buildings.has("armory") and not world.buildings.has("workshop") and not world.buildings.has("warehouse"), "armeria, laboratorio e magazzino assenti al Lv.1")
	_check(world.agents.size() == state.get_alive_heroes().size(), "ogni eroe vivo cammina nella base")
	_check(world.nav.get_point_count() > 20 and world.site_nodes.has("training"), "rete di sentieri navigabile")
	_check(world.buildings.training.floors == 1 and world.buildings.dormitory.floors == 1 and world.buildings.merging.floors == 1, "edifici del Lv.1 a un solo piano")
	# Pannelli delle strutture
	for id in ["training", "dormitory", "merging", "gate", "crystal", "roster"]:
		main.open_panel(id)
		await _frames(2)
		_check(main.side_panel.visible and main.side_body.get_child_count() > 0, "pannello %s si apre sopra la base" % id)
	main.panels.gate_tab = "squad"
	main.open_panel("gate")
	await _frames(2)
	_check(main.side_body.get_child_count() > 5, "composizione squadra")
	main.panels.gate_tab = "mission"
	# Addestramento con la UI
	var trainee: Dictionary = state.data.heroes[5]
	main.panels._assign(str(trainee.id), "training")
	await _frames(3)
	_check(state.hero_activity(trainee) == "training" and world.agent_for(str(trainee.id)).activity == "training", "l'eroe assegnato va al campo di addestramento")
	state.advance_time(900.0)
	state.save_and_notify()
	await _frames(3)
	_check(int(trainee.level) > 1, "l'addestramento fa salire di livello")
	# Evocazione e fusione
	state.data.world.gold = 200000
	main.panels._summon("normal", 10)
	await _frames(4)
	_check(state.data.heroes.size() == 16, "evocazione x10 dal Cristallo")
	main.close_all_modals()
	var same_rarity := {}
	for hero in state.get_alive_heroes():
		if state.data.party.has(hero.id): continue
		var r := int(hero.current_rarity)
		if not same_rarity.has(r): same_rarity[r] = []
		same_rarity[r].append(str(hero.id))
	var merged := false
	for r in same_rarity:
		if same_rarity[r].size() >= 3 and r < 5:
			main.panels.merge_selected.assign(same_rarity[r].slice(0, 3))
			main.panels._do_merge()
			merged = true
			break
	_check(merged and main.panels.merge_selected.is_empty(), "fusione dal Centro di Fusione")
	# Espansione base e nuovo cantiere
	state.debug_clear_floors(3)
	state.data.world.gold = 300000
	main.panels._upgrade_base()
	await _frames(4)
	_check(state.base_level() == 2 and world.buildings.has("armory") and world.building_states.armory == "plot", "Base Lv.2 mostra il cantiere dell'Armeria")
	main.open_panel("armory")
	await _frames(2)
	main.panels._build_facility("armory")
	await _frames(4)
	_check(world.building_states.armory == "built:1", "Armeria costruita fisicamente nella base")
	main.panels._forge("weapon")
	await _frames(2)
	_check(state.data.inventory.size() == 1, "forgia in Armeria")
	main.panels._upgrade("training")
	await _frames(4)
	_check(state.facility_level("training") == 2 and world.buildings.training.floors == 2, "il potenziamento aggiunge un piano all'edificio")
	# Scheda eroe, diario, impostazioni
	main.open_hero(state.data.heroes[0].id)
	await _frames(3)
	_check(main.modal_layer.get_child_count() == 1, "scheda eroe in finestra")
	main.close_all_modals()
	main._show_journal()
	await _frames(2)
	main.close_all_modals()
	main._show_settings()
	await _frames(2)
	main.close_all_modals()
	await _frames(2)
	# Missione completa
	main.close_panel()
	main.panels._auto_party()
	await _frames(2)
	_check(state.party_readiness().ready, "formazione consigliata completa")
	var max_floor_before := int(state.data.world.max_floor)
	main.deploy(1)
	var waited := 0.0
	while main.battle == null and waited < 20.0:
		await create_timer(0.1).timeout
		waited += 0.1
	_check(main.battle != null, "la squadra attraversa il Portale e inizia la missione")
	if main.battle != null:
		main.battle.speed_scale = 8.0
		var limit := 0.0
		while main.battle != null and limit < 60.0:
			await create_timer(0.1).timeout
			limit += 0.1
	_check(main.battle == null and main.hub.visible and not main.busy, "fine missione e ritorno alla base")
	_check(state.data.active_mission.is_empty() and int(state.data.stages["1"].attempts) == 1, "missione registrata nel salvataggio")
	print("Piano 1 %s · piani sbloccati %d → %d" % ["completato" if state.data.stages["1"].cleared else "fallito", max_floor_before, int(state.data.world.max_floor)])
	main.queue_free()
	await process_frame
	print("\nRisultato: %d controlli, %d falliti" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _frames(count: int) -> void:
	for i in count: await process_frame
