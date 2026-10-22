extends RefCounted
class_name FacilityPanels

## Contenuti dei pannelli che si aprono sopra la base quando si tocca un edificio,
## più scheda eroe, diario, materiali, impostazioni e resoconto missione.

const HeroPortraitScript := preload("res://scripts/hero_portrait.gd")

var main
var merge_selected: Array[String] = []
var merging_tab := "fusion"
var gate_tab := "mission"
var gate_floor := -1
var last_summon: Array = []

func _init(owner) -> void:
	main = owner

func reset_selection() -> void:
	merge_selected.clear()
	gate_floor = -1

var GS: RiftwardState:
	get: return GameState

# =============================================================================
# Intestazioni e smistamento
# =============================================================================

func header_for(id: String) -> Dictionary:
	if GS.FACILITIES.has(id):
		var info: Dictionary = GS.FACILITIES[id]
		if GS.facility_built(id): return {"title": str(info.name), "subtitle": "STRUTTURA · LIVELLO %d / %d" % [GS.facility_level(id), GS.facility_max_level()]}
		return {"title": "Cantiere: " + str(info.name), "subtitle": "NUOVA STRUTTURA DISPONIBILE"}
	match id:
		"crystal": return {"title": "Cristallo del Nexus", "subtitle": "EVOCAZIONE · BASE LV.%d" % GS.base_level()}
		"roster": return {"title": "I tuoi eroi", "subtitle": "%d EROI VIVI · %d CADUTI" % [GS.get_alive_heroes().size(), GS.data.memorial.size()]}
	return {"title": id.capitalize(), "subtitle": ""}

func build(id: String, body: VBoxContainer, footer: VBoxContainer) -> void:
	if GS.FACILITIES.has(id) and not GS.facility_built(id):
		_build_plot(id, body)
		return
	match id:
		"training": _build_training(body)
		"dormitory": _build_dormitory(body)
		"merging": _build_merging(body)
		"gate": _build_gate(body)
		"crystal": _build_crystal(body)
		"armory": _build_armory(body)
		"warehouse": _build_warehouse(body)
		"workshop": _build_workshop(body)
		"alchemy": _build_alchemy(body)
		"roster": _build_roster(body)
	if GS.FACILITIES.has(id): _build_upgrade_footer(id, footer)

# =============================================================================
# Widget comuni
# =============================================================================

func section(title: String, note: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	var t := UIKit.label(title, 19, UIKit.NAVY, UIKit.head_font())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	if not note.is_empty(): row.add_child(UIKit.label(note, 14, UIKit.MUTED, UIKit.body_bold()))
	box.add_child(row)
	box.add_child(UIKit.divider())
	return box

func info_card(text: String, tone: String = "info") -> PanelContainer:
	var color := UIKit.tone_color(tone)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.box(color.lerp(Color.WHITE, 0.86), color.lerp(Color.WHITE, 0.4), 2, 12, 12))
	card.add_child(UIKit.para(text, 15, UIKit.INK))
	return card

func activity_pill(hero: Dictionary) -> PanelContainer:
	match GS.hero_activity(hero):
		"training": return UIKit.pill("In allenamento", UIKit.TEAL)
		"resting": return UIKit.pill("A riposo", UIKit.SKY)
		"injured": return UIKit.pill("Ferito", UIKit.ROSE)
		"party": return UIKit.pill("In squadra", UIKit.GOLD_DEEP)
		"dead": return UIKit.pill("Caduto", Color("#6d6878"))
	return UIKit.pill("Libero", Color("#9a93a8"))

func stars_label(rarity: int, size: int = 15) -> Label:
	return UIKit.label(GS.stars(rarity), size, UIKit.rarity_color(rarity), UIKit.body_bold())

func hero_row(hero: Dictionary, actions: Array = [], extra: Control = null, show_activity: bool = true, highlight: Color = Color.TRANSPARENT) -> PanelContainer:
	var card := PanelContainer.new()
	var border := highlight if highlight != Color.TRANSPARENT else UIKit.PAPER_LINE
	card.add_theme_stylebox_override("panel", UIKit.box(UIKit.PAPER_DEEP if highlight == Color.TRANSPARENT else highlight.lerp(Color.WHITE, 0.82), border, 2, 14, 10))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_row_input.bind(str(hero.get("id", ""))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var portrait: HeroPortrait = HeroPortraitScript.new()
	portrait.setup(hero, 64)
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.add_child(UIKit.label(str(hero.name), 17, UIKit.INK, UIKit.head_font()))
	name_row.add_child(stars_label(int(hero.current_rarity), 13))
	info.add_child(name_row)
	info.add_child(UIKit.label("%s · Lv.%d/%d · Potenza %s" % [GS.role_label(hero.role), int(hero.level), GS.level_cap(hero), GS.format_number(GS.hero_power(hero))], 13, UIKit.INK_SOFT))
	if extra != null: info.add_child(extra)
	row.add_child(info)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 6)
	if show_activity:
		var pill := activity_pill(hero)
		pill.size_flags_horizontal = Control.SIZE_SHRINK_END
		side.add_child(pill)
	for action in actions: side.add_child(action)
	row.add_child(side)
	card.add_child(row)
	return card

func _on_row_input(event: InputEvent, hero_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		main.open_hero(hero_id)

func small_button(text: String, callback: Callable, kind: String = "primary", disabled_reason: String = "") -> Button:
	var b := UIKit.button(text, callback, kind, 112)
	b.custom_minimum_size.y = 38
	b.add_theme_font_size_override("font_size", 14)
	if not disabled_reason.is_empty():
		b.disabled = true
		b.tooltip_text = disabled_reason
	return b

func bars(hero: Dictionary, show_xp: bool = false) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	if show_xp:
		var cap_reached := int(hero.level) >= GS.level_cap(hero)
		var need := GS.xp_to_next(int(hero.level))
		box.add_child(_bar_line("XP", float(hero.get("xp", 0)), float(need), UIKit.TEAL, "MAX" if cap_reached else "%d/%d" % [int(hero.get("xp", 0)), need]))
	box.add_child(_bar_line("Stanchezza", float(hero.fatigue), 100.0, UIKit.ROSE if float(hero.fatigue) >= 70 else UIKit.GOLD, "%d" % roundi(float(hero.fatigue))))
	box.add_child(_bar_line("Morale", float(hero.morale), 100.0, UIKit.SKY, "%d" % roundi(float(hero.morale))))
	return box

func _bar_line(title: String, value: float, max_value: float, color: Color, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var t := UIKit.label(title, 12, UIKit.MUTED, UIKit.body_bold())
	t.custom_minimum_size.x = 74
	row.add_child(t)
	var b := UIKit.bar(value, max_value, color, 9)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	var v := UIKit.label(text, 12, UIKit.INK_SOFT, UIKit.body_bold())
	v.custom_minimum_size.x = 56
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row

func cost_line(costs: Dictionary) -> Label:
	var ok := GS.can_afford(costs)
	return UIKit.label("Costo: " + GS.cost_text(costs), 14, UIKit.INK_SOFT if ok else UIKit.ROSE, UIKit.body_bold())

func stat_tile(title: String, value: String, color: Color = UIKit.INK) -> PanelContainer:
	var card := UIKit.card(UIKit.PAPER_DEEP, UIKit.PAPER_LINE, 12, 10)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.add_child(UIKit.label(title.to_upper(), 11, UIKit.MUTED, UIKit.body_bold()))
	box.add_child(UIKit.label(value, 22, color, UIKit.head_font()))
	card.add_child(box)
	return card

func tabs(options: Array, current: String, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for option in options:
		var b := UIKit.button(option[1], callback.bind(option[0]), "navy" if option[0] == current else "ghost", 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 42
		row.add_child(b)
	return row

## Apre un selettore eroi in un modale.
func pick_hero(title: String, candidates: Array, callback: Callable, note: Callable = Callable()) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	var modal_ref := []
	if candidates.is_empty(): list.add_child(info_card("Nessun eroe disponibile.", "warn"))
	for hero in candidates:
		var extra: Control = null
		if note.is_valid():
			var text: String = note.call(hero)
			if not text.is_empty(): extra = UIKit.label(text, 13, UIKit.GOLD_DEEP, UIKit.body_bold())
		list.add_child(hero_row(hero, [small_button("Scegli", _picked.bind(modal_ref, callback, str(hero.id)), "primary")], extra))
	var modal: Control = await main.open_modal(title, "SCEGLI UN EROE", list, 640)
	modal_ref.append(modal)

func _picked(modal_ref: Array, callback: Callable, hero_id: String) -> void:
	if not modal_ref.is_empty(): main.close_modal(modal_ref[0])
	callback.call(hero_id)

func _build_upgrade_footer(id: String, footer: VBoxContainer) -> void:
	var check := GS.can_upgrade_facility(id)
	var level := GS.facility_level(id)
	if level >= 5:
		footer.add_child(UIKit.label("Livello massimo raggiunto.", 14, UIKit.MUTED, UIKit.body_bold()))
		return
	var cost := GS.facility_upgrade_cost(id)
	var text := "Aggiungi un piano · Lv.%d  (%s Oro)" % [level + 1, GS.format_number(cost.gold)]
	var b := UIKit.button(text, _upgrade.bind(id), "gold", 0)
	b.disabled = not check.ok
	footer.add_child(b)
	if not check.ok: footer.add_child(UIKit.label(str(check.message), 13, UIKit.ROSE, UIKit.body_bold()))

func _upgrade(id: String) -> void:
	main.report(GS.upgrade_facility(id), "%s potenziato" % GS.FACILITIES[id].short, "La struttura cresce di un piano.")

# =============================================================================
# Addestramento
# =============================================================================

func _build_training(body: VBoxContainer) -> void:
	var assigned := GS.assigned_to("training")
	body.add_child(info_card("Gli eroi sul campo rialzato guadagnano esperienza col passare del tempo, anche quando sei offline (fino a 8 ore). Allenarsi stanca: quando la stanchezza sale, mandali al Dormitorio."))
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(stat_tile("Posti", "%d / %d" % [assigned.size(), GS.training_slots()], UIKit.TEAL))
	tiles.add_child(stat_tile("Velocità", "+%d%%" % roundi(35.0 * (GS.facility_level("training") - 1)), UIKit.NAVY))
	body.add_child(tiles)
	var on_field := section("Sul campo", "%d/%d" % [assigned.size(), GS.training_slots()])
	body.add_child(on_field)
	if assigned.is_empty(): body.add_child(UIKit.para("Nessuno si sta allenando. Scegli qualcuno qui sotto.", 15))
	for hero in assigned:
		var extra := VBoxContainer.new()
		extra.add_child(bars(hero, true))
		extra.add_child(UIKit.label("≈ %d XP al minuto" % roundi(GS.training_xp_per_minute(hero)), 12, UIKit.TEAL, UIKit.body_bold()))
		body.add_child(hero_row(hero, [small_button("Richiama", _unassign.bind(str(hero.id)), "ghost")], extra, false, UIKit.TEAL))
	body.add_child(section("Disponibili"))
	var free := GS.get_alive_heroes().filter(func(h): return not GS.data.assignments.has(h.id))
	free.sort_custom(func(a, b): return int(a.level) < int(b.level))
	var full := assigned.size() >= GS.training_slots()
	for hero in free:
		var reason := ""
		if int(hero.level) >= GS.level_cap(hero): reason = "Cap raggiunto"
		elif not hero.injuries.is_empty(): reason = "Ferito"
		elif int(hero.fatigue) >= 85: reason = "Troppo stanco"
		elif full: reason = "Posti esauriti"
		var b := small_button("Allena", _assign.bind(str(hero.id), "training"), "primary", reason)
		var extra: Control = UIKit.label(reason, 12, UIKit.ROSE, UIKit.body_bold()) if not reason.is_empty() and reason != "Posti esauriti" else null
		body.add_child(hero_row(hero, [b], extra))

func _assign(hero_id: String, facility: String) -> void:
	var result := GS.assign_hero(hero_id, facility)
	if not result.ok: main.toast("Non disponibile", str(result.message), "warn")

func _unassign(hero_id: String) -> void:
	GS.unassign_hero(hero_id)

# =============================================================================
# Dormitorio
# =============================================================================

func _build_dormitory(body: VBoxContainer) -> void:
	var resting := GS.assigned_to("dormitory")
	body.add_child(info_card("Nel Dormitorio gli eroi recuperano stanchezza e morale e guariscono dalle ferite. Escono da soli quando sono di nuovo in forma."))
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(stat_tile("Letti", "%d / %d" % [resting.size(), GS.dormitory_slots()], UIKit.SKY))
	tiles.add_child(stat_tile("Recupero", "+%d%%" % roundi(25.0 * (GS.facility_level("dormitory") - 1)), UIKit.NAVY))
	body.add_child(tiles)
	body.add_child(section("A riposo", "%d/%d" % [resting.size(), GS.dormitory_slots()]))
	if resting.is_empty(): body.add_child(UIKit.para("I letti sono liberi.", 15))
	for hero in resting:
		var extra := VBoxContainer.new()
		extra.add_child(bars(hero))
		if not hero.injuries.is_empty(): extra.add_child(UIKit.label("%s · guarisce tra %d min" % [hero.injuries[0].name, ceili(float(hero.injuries[0].minutes))], 12, UIKit.ROSE, UIKit.body_bold()))
		body.add_child(hero_row(hero, [small_button("Sveglia", _unassign.bind(str(hero.id)), "ghost")], extra, false, UIKit.SKY))
	body.add_child(section("Chi ne ha bisogno"))
	var free := GS.get_alive_heroes().filter(func(h): return not GS.data.assignments.has(h.id))
	free.sort_custom(func(a, b): return _need(a) > _need(b))
	var full := resting.size() >= GS.dormitory_slots()
	for hero in free:
		var extra := VBoxContainer.new()
		extra.add_child(bars(hero))
		if not hero.injuries.is_empty(): extra.add_child(UIKit.label(str(hero.injuries[0].name), 12, UIKit.ROSE, UIKit.body_bold()))
		body.add_child(hero_row(hero, [small_button("Riposa", _assign.bind(str(hero.id), "dormitory"), "sky", "Letti esauriti" if full else "")], extra))

func _need(hero: Dictionary) -> float:
	return float(hero.fatigue) + (100.0 - float(hero.morale)) * 0.5 + (200.0 if not hero.injuries.is_empty() else 0.0)

# =============================================================================
# Centro di Fusione
# =============================================================================

func _build_merging(body: VBoxContainer) -> void:
	body.add_child(tabs([["fusion", "Fusione"], ["promotion", "Promozione"]], merging_tab, _set_merging_tab))
	if merging_tab == "promotion":
		_build_promotion(body)
		return
	body.add_child(info_card("Unisci tre eroi della stessa rarità (fino a 4★). Il primo scelto è il nucleo: sale di una stella e assorbe parte delle statistiche degli altri due, che vengono consumati per sempre."))
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 12)
	for i in 3:
		var holder := VBoxContainer.new()
		holder.alignment = BoxContainer.ALIGNMENT_CENTER
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(104, 104)
		frame.add_theme_stylebox_override("panel", UIKit.box(Color("#e9f1ff"), Color("#7fb4ff") if i == 0 else UIKit.PAPER_LINE, 3, 18, 6))
		if i < merge_selected.size():
			var p: HeroPortrait = HeroPortraitScript.new()
			p.setup(GS.hero_by_id(merge_selected[i]), 88)
			frame.add_child(p)
		else:
			var q := UIKit.heading("?", 34, Color("#a9b8d6"))
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			frame.add_child(q)
		holder.add_child(frame)
		var caption := UIKit.label("Nucleo" if i == 0 else "Donatore", 13, UIKit.SKY if i == 0 else UIKit.MUTED, UIKit.body_bold())
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(caption)
		slots.add_child(holder)
		if i < 2: slots.add_child(UIKit.heading("+", 26, UIKit.MUTED))
	body.add_child(slots)
	var validation := GS.validate_merge_heroes(merge_selected)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var fuse := UIKit.button("Fondi", _confirm_merge, "violet", 0)
	fuse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuse.disabled = not validation.ok
	actions.add_child(fuse)
	actions.add_child(UIKit.button("Svuota", _clear_merge, "ghost", 120))
	body.add_child(actions)
	if not validation.ok and merge_selected.size() > 0: body.add_child(UIKit.label(str(validation.message), 14, UIKit.ROSE, UIKit.body_bold()))
	body.add_child(section("Candidati", "fuori squadra"))
	var candidates := GS.get_alive_heroes().filter(func(h): return not GS.data.party.has(h.id) and int(h.current_rarity) <= 4)
	candidates.sort_custom(func(a, b): return int(a.current_rarity) * 1000 + int(a.level) > int(b.current_rarity) * 1000 + int(b.level))
	if candidates.is_empty(): body.add_child(UIKit.para("Nessun eroe fuori squadra da fondere. Evoca nuovi eroi al Cristallo del Nexus.", 15))
	for hero in candidates:
		var selected := merge_selected.has(str(hero.id))
		var b := small_button("Togli" if selected else "Scegli", _toggle_merge.bind(str(hero.id)), "ghost" if selected else "violet")
		body.add_child(hero_row(hero, [b], null, true, UIKit.VIOLET if selected else Color.TRANSPARENT))

func _set_merging_tab(tab: String) -> void:
	merging_tab = tab
	main._render_panel(true)

func _toggle_merge(hero_id: String) -> void:
	if merge_selected.has(hero_id): merge_selected.erase(hero_id)
	elif merge_selected.size() < 3: merge_selected.append(hero_id)
	else: main.toast("Selezione completa", "Puoi fondere tre eroi alla volta.", "warn")
	main._render_panel()

func _clear_merge() -> void:
	merge_selected.clear()
	main._render_panel()

func _confirm_merge() -> void:
	var validation := GS.validate_merge_heroes(merge_selected)
	if not validation.ok:
		main.toast("Fusione non pronta", str(validation.message), "warn")
		return
	var heroes: Array = validation.heroes
	main.confirm("Fusione degli eroi", "%s diventerà %s.\n\n%s e %s verranno consumati per sempre." % [heroes[0].name, GS.stars(int(heroes[0].current_rarity) + 1), heroes[1].name, heroes[2].name], "Fondi", _do_merge, "violet")

func _do_merge() -> void:
	var result := GS.merge_heroes(merge_selected)
	if result.ok:
		merge_selected.clear()
		main.toast("Fusione completata", "%s ora è %s" % [result.hero.name, GS.stars(int(result.hero.current_rarity))], "good")
	else: main.toast("Fusione bloccata", str(result.message), "warn")

func _build_promotion(body: VBoxContainer) -> void:
	body.add_child(info_card("Un eroe al livello massimo della sua rarità può essere promosso con le Pietre. Le promozioni a 6★ e 7★ sono molto difficili: richiedono di aver superato i Piani 30 e 60."))
	body.add_child(stat_tile("Pietre disponibili", GS.display_resource("stones"), UIKit.VIOLET))
	var heroes := GS.get_alive_heroes()
	heroes.sort_custom(func(a, b): return float(a.level) / GS.level_cap(a) > float(b.level) / GS.level_cap(b))
	for hero in heroes:
		var req := GS.promotion_requirements(hero)
		var extra := UIKit.label(("Pronto · %d Pietre" % int(req.stones)) if req.ok else str(req.message), 13, UIKit.TEAL if req.ok else UIKit.MUTED, UIKit.body_bold())
		var b := small_button("Promuovi", _promote.bind(str(hero.id)), "violet", "" if req.ok else str(req.message))
		body.add_child(hero_row(hero, [b] if int(hero.current_rarity) < 7 else [], extra))

func _promote(hero_id: String) -> void:
	main.report(GS.promote_hero(hero_id), "Promozione riuscita", "%s sale di rarità." % GS.hero_by_id(hero_id).name)

# =============================================================================
# Portale delle Missioni e squadra
# =============================================================================

func _build_gate(body: VBoxContainer) -> void:
	body.add_child(tabs([["mission", "Missione"], ["squad", "Squadra"]], gate_tab, _set_gate_tab))
	if gate_tab == "squad":
		_build_squad(body)
		return
	var max_floor := int(GS.data.world.max_floor)
	if gate_floor < 1 or gate_floor > max_floor: gate_floor = int(GS.data.world.current_floor)
	var selector := HBoxContainer.new()
	selector.add_theme_constant_override("separation", 8)
	var prev := UIKit.button("◀", _shift_floor.bind(-1), "ghost", 52)
	prev.disabled = gate_floor <= 1
	selector.add_child(prev)
	var title := UIKit.heading("Piano %d" % gate_floor, 30, UIKit.NAVY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_child(title)
	var next := UIKit.button("▶", _shift_floor.bind(1), "ghost", 52)
	next.disabled = gate_floor >= max_floor
	selector.add_child(next)
	body.add_child(selector)
	var record := GS.get_stage(gate_floor)
	var stage: Dictionary = record.descriptor
	var color := Color(str(stage.get("color", "#3c7968")))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.box(color.lerp(Color.WHITE, 0.82), color, 3, 16, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.add_child(UIKit.pill(_type_label(str(stage.type)), color.darkened(0.15)))
	tags.add_child(UIKit.pill(str(stage.biome), Color("#6d6878")))
	if bool(record.cleared): tags.add_child(UIKit.pill("Completato", UIKit.TEAL))
	v.add_child(tags)
	v.add_child(UIKit.label(str(stage.name), 24, UIKit.INK, UIKit.head_font()))
	v.add_child(UIKit.para(str(stage.description), 15))
	v.add_child(UIKit.label("Obiettivo: " + str(stage.objective), 15, UIKit.INK, UIKit.body_bold()))
	v.add_child(UIKit.label("Minaccia %d · Tentativi %d%s" % [int(stage.get("threat_budget", 100)), int(record.attempts), (" · Record %ds" % roundi(float(record.best_time))) if float(record.best_time) > 0 else ""], 13, UIKit.INK_SOFT, UIKit.body_bold()))
	card.add_child(v)
	body.add_child(card)
	var rewards := GS.floor_rewards(gate_floor, int(record.attempts) + 1, not bool(record.cleared))
	var reward_text := "%s Oro · %d XP a superstite" % [GS.format_number(rewards.gold), int(rewards.xp)]
	if rewards.has("gems"): reward_text += " · %d Gemme (primo completamento)" % int(rewards.gems)
	if rewards.has("stones"): reward_text += " · %d Pietre" % int(rewards.stones)
	body.add_child(info_card("Ricompense: " + reward_text, "good"))
	if int(record.attempts) > 0 and not bool(record.cleared): body.add_child(info_card("Il piano non cambia tra un tentativo e l'altro: stesso schieramento nemico, ricompense ridotte a ogni nuovo tentativo.", "warn"))
	var ready := GS.party_readiness()
	body.add_child(section("Squadra pronta?", "Potenza %s · %s" % [GS.format_number(ready.score), ready.grade]))
	var faces := HBoxContainer.new()
	faces.add_theme_constant_override("separation", 6)
	for i in GS.PARTY_SIZE:
		var hero: Dictionary = GS.get_party()[i]
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 0)
		if hero.is_empty():
			var empty := PanelContainer.new()
			empty.custom_minimum_size = Vector2(72, 72)
			empty.add_theme_stylebox_override("panel", UIKit.box(Color("#ece3cc"), UIKit.PAPER_LINE, 2, 14, 0))
			slot.add_child(empty)
		else:
			var p: HeroPortrait = HeroPortraitScript.new()
			p.setup(hero, 72)
			slot.add_child(p)
		var line_label := UIKit.label(GS.FORMATION_LINES[i], 12, UIKit.MUTED, UIKit.body_bold())
		line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(line_label)
		faces.add_child(slot)
	body.add_child(faces)
	for warning in ready.warnings.slice(0, 5): body.add_child(UIKit.label("• " + str(warning), 14, UIKit.ROSE, UIKit.body_bold()))
	var go := UIKit.button("Parti per il Piano %d" % gate_floor, _confirm_deploy.bind(gate_floor), "gold", 0)
	go.custom_minimum_size.y = 56
	go.add_theme_font_size_override("font_size", 20)
	go.disabled = not ready.ready
	body.add_child(go)
	if not ready.ready: body.add_child(UIKit.button("Componi la squadra", _set_gate_tab.bind("squad"), "primary", 0))

func _type_label(type: String) -> String:
	return {"Subjugation": "Sterminio", "Survival": "Sopravvivenza", "Exploration": "Esplorazione", "Defense": "Difesa", "Boss": "Guardiano"}.get(type, type)

func _set_gate_tab(tab: String) -> void:
	gate_tab = tab
	main._render_panel(true)

func _shift_floor(delta: int) -> void:
	gate_floor = clampi(gate_floor + delta, 1, int(GS.data.world.max_floor))
	main._render_panel()

func _confirm_deploy(floor_index: int) -> void:
	main.confirm("Partenza per il Piano %d" % floor_index, "In missione gli eroi combattono da soli: tu puoi dare solo ordini generali.\n\nUn eroe che arriva a 0 HP muore per sempre. Non esistono resurrezioni.", "Attraversa il Portale", main.deploy.bind(floor_index), "gold")

func _build_squad(body: VBoxContainer) -> void:
	body.add_child(info_card("Formazione 2 Front · 2 Mid · 1 Rear. Metti Guardiani e Avanguardie davanti, Lancieri e Supporti al centro, Ranger o Maghi dietro."))
	body.add_child(UIKit.button("Formazione consigliata", _auto_party, "primary", 0))
	var party := GS.get_party()
	for i in GS.PARTY_SIZE:
		var hero: Dictionary = party[i]
		var line: String = GS.FORMATION_LINES[i]
		var title := UIKit.label("Slot %d · %s" % [i + 1, line], 14, UIKit.NAVY, UIKit.body_bold())
		body.add_child(title)
		if hero.is_empty():
			var b := UIKit.button("Scegli un eroe per %s" % line, _pick_slot.bind(i), "ghost", 0)
			body.add_child(b)
		else:
			var mismatch: bool = str(GS.ROLES[hero.role].line) != line
			var extra: Control = UIKit.label("Ruolo da %s" % GS.ROLES[hero.role].line, 12, UIKit.ROSE, UIKit.body_bold()) if mismatch else bars(hero)
			body.add_child(hero_row(hero, [small_button("Cambia", _pick_slot.bind(i), "primary"), small_button("Togli", _clear_slot.bind(i), "ghost")], extra, false))

func _pick_slot(slot: int) -> void:
	var line: String = GS.FORMATION_LINES[slot]
	var candidates := GS.get_alive_heroes().filter(func(h): return GS.data.party[slot] != h.id)
	candidates.sort_custom(func(a, b):
		var ma := 1 if str(GS.ROLES[a.role].line) == line else 0
		var mb := 1 if str(GS.ROLES[b.role].line) == line else 0
		if ma != mb: return ma > mb
		return GS.hero_power(a) > GS.hero_power(b))
	pick_hero("Slot %d · %s" % [slot + 1, line], candidates, _assign_slot.bind(slot), _slot_note.bind(line))

func _slot_note(hero: Dictionary, line: String) -> String:
	var parts := []
	if str(GS.ROLES[hero.role].line) == line: parts.append("Adatto a " + line)
	if GS.data.party.has(hero.id): parts.append("già in squadra")
	if GS.data.assignments.has(hero.id): parts.append("lascerà l'attività")
	return " · ".join(parts)

func _assign_slot(hero_id: String, slot: int) -> void:
	GS.assign_party(slot, hero_id)

func _clear_slot(slot: int) -> void:
	GS.remove_party(slot)

func _auto_party() -> void:
	var available := GS.get_alive_heroes().filter(func(h): return h.injuries.is_empty())
	available.sort_custom(func(a, b): return GS.hero_power(a) > GS.hero_power(b))
	var chosen: Array[String] = []
	for i in GS.PARTY_SIZE:
		var line: String = GS.FORMATION_LINES[i]
		var pick := ""
		for hero in available:
			if chosen.has(str(hero.id)): continue
			if str(GS.ROLES[hero.role].line) == line:
				pick = str(hero.id)
				break
		if pick.is_empty():
			for hero in available:
				if not chosen.has(str(hero.id)):
					pick = str(hero.id)
					break
		chosen.append(pick)
	for i in GS.PARTY_SIZE: GS.data.party[i] = chosen[i] if i < chosen.size() else ""
	GS.save_and_notify()
	main.toast("Squadra composta", "Gli eroi più forti per ogni linea.", "good")

# =============================================================================
# Cristallo del Nexus: evocazione ed espansione della base
# =============================================================================

func _build_crystal(body: VBoxContainer) -> void:
	body.add_child(section("Espansione della base", "Base Lv.%d" % GS.base_level()))
	var next := GS.next_base_level()
	if next.is_empty():
		body.add_child(info_card("La base ha raggiunto il livello massimo.", "good"))
	else:
		var unlocks := []
		for id in GS.FACILITY_ORDER:
			if int(GS.FACILITIES[id].unlock) == int(next.level): unlocks.append(GS.FACILITIES[id].name)
		var text := "Base Lv.%d: tutte le strutture potranno crescere fino al Lv.%d (un piano in più)." % [int(next.level), int(next.level)]
		if not unlocks.is_empty(): text += "\nNuovi cantieri: " + ", ".join(unlocks) + "."
		text += "\nAnche la zona migliora: lampioni, aiuole, sentieri lastricati."
		body.add_child(info_card(text))
		var req := UIKit.label("Requisiti: Piano %d completato · %s Oro" % [int(next.floor), GS.format_number(next.gold)], 14, UIKit.INK_SOFT, UIKit.body_bold())
		body.add_child(req)
		var check := GS.can_upgrade_base()
		var b := UIKit.button("Espandi la base a Lv.%d" % int(next.level), _upgrade_base, "gold", 0)
		b.disabled = not check.ok
		body.add_child(b)
		if not check.ok: body.add_child(UIKit.label(str(check.message), 13, UIKit.ROSE, UIKit.body_bold()))
	body.add_child(section("Evocazione", "%d eroi vivi" % GS.get_alive_heroes().size()))
	var emergency := GS.emergency_recruit_status()
	if emergency.visible:
		body.add_child(info_card("Ti restano meno di cinque eroi. Il Nexus può richiamare gratis una recluta 1★ ogni 30 minuti.", "warn"))
		var eb := UIKit.button("Richiamo d'emergenza (gratis)", _emergency, "gold", 0)
		eb.disabled = not emergency.ok
		body.add_child(eb)
		if not emergency.ok: body.add_child(UIKit.label(str(emergency.message), 13, UIKit.MUTED, UIKit.body_bold()))
	for pool in ["normal", "high", "transcendent"]: body.add_child(_pool_card(pool))
	if not last_summon.is_empty():
		body.add_child(section("Ultimi arrivati"))
		for hero in last_summon:
			var current := GS.hero_by_id(str(hero.id))
			if not current.is_empty(): body.add_child(hero_row(current))

func _pool_card(pool: String) -> PanelContainer:
	var info: Dictionary = GS.SUMMON_POOLS[pool]
	var color: Color = {"normal": UIKit.SKY, "high": UIKit.VIOLET, "transcendent": Color("#ff5f8f")}[pool]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.box(color.lerp(Color.WHITE, 0.85), color, 3, 16, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UIKit.label(str(info.name), 21, color.darkened(0.25), UIKit.head_font()))
	var rates := []
	for r in info.rates: rates.append("%s %s%%" % [GS.stars(int(r[0])), str(r[1]).replace(".", ",")])
	v.add_child(UIKit.label("  ·  ".join(rates), 14, UIKit.INK, UIKit.body_bold()))
	if pool == "high": v.add_child(UIKit.label("5★ garantito entro %d evocazioni · ora %d/%d" % [GS.HIGH_HARD_PITY, int(GS.data.pity.high), GS.HIGH_HARD_PITY], 13, UIKit.INK_SOFT))
	var currency := "Oro" if info.currency == "gold" else "Gemme"
	var unlocked := GS.summon_pool_unlocked(pool)
	if not unlocked:
		v.add_child(UIKit.label("Si sblocca completando il Piano %d" % int(info.unlock_floor), 14, UIKit.ROSE, UIKit.body_bold()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for count in [1, 10]:
		var cost: int = int(info.cost) * int(count)
		var b := UIKit.button("×%d · %s %s" % [count, GS.format_number(cost), currency], _summon.bind(pool, count), "violet" if pool != "normal" else "sky", 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not unlocked or not GS.can_afford({str(info.currency): cost})
		row.add_child(b)
	v.add_child(row)
	card.add_child(v)
	return card

func _emergency() -> void:
	var result := GS.emergency_recruit()
	main.report(result, "Nuova recluta", str(result.get("hero", {}).get("name", "")))

func _upgrade_base() -> void:
	var result := GS.upgrade_base()
	if result.ok:
		main.toast("Base Lv.%d!" % int(result.level), ("Nuovi cantieri: " + ", ".join(result.unlocked)) if not result.unlocked.is_empty() else "Gli edifici possono crescere di un piano.", "good")
	else: main.toast("Non ancora", str(result.message), "warn")

func _summon(pool: String, count: int) -> void:
	var result := GS.summon(pool, count)
	if not result.ok:
		main.toast("Evocazione bloccata", str(result.message), "warn")
		return
	last_summon = result.heroes
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var sorted: Array = result.heroes.duplicate()
	sorted.sort_custom(func(a, b): return int(a.current_rarity) > int(b.current_rarity))
	for hero in sorted:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var p: HeroPortrait = HeroPortraitScript.new()
		p.setup(hero, 112)
		cell.add_child(p)
		var n := UIKit.label(str(hero.name).split(" ")[0], 15, UIKit.INK, UIKit.head_font())
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(n)
		var s := stars_label(int(hero.current_rarity), 14)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(s)
		var r := UIKit.label(GS.role_label(hero.role), 12, UIKit.MUTED, UIKit.body_bold())
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(r)
		grid.add_child(cell)
		cell.modulate.a = 0.0
		cell.create_tween().tween_property(cell, "modulate:a", 1.0, 0.3).set_delay(0.08 * grid.get_child_count())
	var best := int(sorted[0].current_rarity)
	await main.open_modal("Nuovi eroi!" if best < 5 else "Risonanza leggendaria!", "%d EVOCAZIONI · %s" % [count, GS.SUMMON_POOLS[pool].name.to_upper()], grid, 700 if count > 1 else 360)

# =============================================================================
# Strutture sbloccate più avanti
# =============================================================================

func _build_plot(id: String, body: VBoxContainer) -> void:
	var info: Dictionary = GS.FACILITIES[id]
	body.add_child(UIKit.para(str(info.description), 16, UIKit.INK))
	if GS.facility_available(id):
		var cost := {"gold": int(info.build_cost)}
		body.add_child(cost_line(cost))
		var b := UIKit.button("Costruisci %s" % info.name, _build_facility.bind(id), "gold", 0)
		b.disabled = not GS.can_afford(cost)
		body.add_child(b)
	else:
		body.add_child(info_card("Si sblocca con la Base Lv.%d." % int(info.unlock), "warn"))

func _build_facility(id: String) -> void:
	var result := GS.build_facility(id)
	main.report(result, "%s costruita!" % GS.FACILITIES[id].name, "La nuova struttura è pronta.")
	if result.ok: main.hub.focus_on(id, main.PANEL_WIDTH + 16)

func _build_armory(body: VBoxContainer) -> void:
	body.add_child(info_card("Forgia armi, armature e amuleti. Più l'Armeria è alta, più è probabile ottenere gradi migliori (D → S)."))
	for recipe_id in GS.FORGE_RECIPES:
		var recipe: Dictionary = GS.FORGE_RECIPES[recipe_id]
		var card := UIKit.card()
		var v := VBoxContainer.new()
		v.add_child(UIKit.label(str(recipe.name), 18, UIKit.NAVY, UIKit.head_font()))
		v.add_child(cost_line(recipe.cost))
		var b := small_button("Forgia", _forge.bind(recipe_id), "gold", "" if GS.can_afford(recipe.cost) else "Risorse insufficienti")
		v.add_child(b)
		card.add_child(v)
		body.add_child(card)
	body.add_child(section("Equipaggiamento in deposito", "%d oggetti" % GS.data.inventory.size()))
	if GS.data.inventory.is_empty(): body.add_child(UIKit.para("Nessun oggetto forgiato.", 15))
	for item in GS.data.inventory:
		var stat := "Attacco +%d" % int(item.get("power", 0)) if item.slot == "main" else "Difesa +%d" % int(item.get("defense", 0)) if item.slot == "armor" else "HP +%d" % int(item.get("hp", 0))
		var row := HBoxContainer.new()
		var t := VBoxContainer.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_child(UIKit.label(str(item.name), 16, UIKit.INK, UIKit.head_font()))
		t.add_child(UIKit.label(stat, 13, UIKit.INK_SOFT, UIKit.body_bold()))
		row.add_child(t)
		row.add_child(small_button("Equipaggia", _equip_pick.bind(str(item.id)), "primary"))
		var card := UIKit.card()
		card.add_child(row)
		body.add_child(card)

func _forge(recipe_id: String) -> void:
	var result := GS.forge_item(recipe_id)
	main.report(result, "Forgiato!", str(result.get("item", {}).get("name", "")))

func _equip_pick(item_id: String) -> void:
	pick_hero("Chi lo indossa?", GS.get_alive_heroes(), _equip.bind(item_id))

func _equip(hero_id: String, item_id: String) -> void:
	main.report(GS.equip_item(hero_id, item_id), "Equipaggiato", GS.hero_by_id(hero_id).name)

func _build_warehouse(body: VBoxContainer) -> void:
	body.add_child(info_card("Il Magazzino aumenta le scorte massime di ogni materiale (ora %d)." % GS.material_cap()))
	build_materials(body)

func _build_workshop(body: VBoxContainer) -> void:
	body.add_child(info_card("Raffina i materiali grezzi raccolti nella Torre."))
	for recipe_id in GS.WORKSHOP_RECIPES:
		var recipe: Dictionary = GS.WORKSHOP_RECIPES[recipe_id]
		var card := UIKit.card()
		var v := VBoxContainer.new()
		v.add_child(UIKit.label(str(recipe.name), 18, UIKit.NAVY, UIKit.head_font()))
		v.add_child(cost_line(recipe.cost))
		v.add_child(small_button("Produci", _refine.bind(recipe_id), "primary", "" if GS.can_afford(recipe.cost) else "Risorse insufficienti"))
		card.add_child(v)
		body.add_child(card)

func _refine(recipe_id: String) -> void:
	main.report(GS.refine_material(recipe_id), "Prodotto", str(GS.WORKSHOP_RECIPES[recipe_id].name))

func _build_alchemy(body: VBoxContainer) -> void:
	body.add_child(info_card("Tonici che curano subito le ferite o risollevano il morale."))
	for recipe_id in GS.ALCHEMY_RECIPES:
		var recipe: Dictionary = GS.ALCHEMY_RECIPES[recipe_id]
		var card := UIKit.card()
		var v := VBoxContainer.new()
		v.add_child(UIKit.label(str(recipe.name), 18, UIKit.NAVY, UIKit.head_font()))
		v.add_child(UIKit.para(str(recipe.description), 14))
		v.add_child(cost_line(recipe.cost))
		v.add_child(small_button("Distilla", _brew_pick.bind(recipe_id), "violet", "" if GS.can_afford(recipe.cost) else "Risorse insufficienti"))
		card.add_child(v)
		body.add_child(card)

func _brew_pick(recipe_id: String) -> void:
	var candidates := GS.get_alive_heroes()
	if recipe_id == "heal": candidates = candidates.filter(func(h): return not h.injuries.is_empty())
	pick_hero(str(GS.ALCHEMY_RECIPES[recipe_id].name), candidates, _brew.bind(recipe_id))

func _brew(hero_id: String, recipe_id: String) -> void:
	main.report(GS.brew_potion(recipe_id, hero_id), "Tonico somministrato", GS.hero_by_id(hero_id).name)

# =============================================================================
# Roster
# =============================================================================

func _build_roster(body: VBoxContainer) -> void:
	var alive := GS.get_alive_heroes()
	alive.sort_custom(func(a, b): return int(a.current_rarity) * 1000 + int(a.level) > int(b.current_rarity) * 1000 + int(b.level))
	var counts := {}
	for hero in alive:
		var a := GS.hero_activity(hero)
		counts[a] = int(counts.get(a, 0)) + 1
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(stat_tile("Squadra", "%d/5" % int(counts.get("party", 0) + _party_busy()), UIKit.GOLD_DEEP))
	tiles.add_child(stat_tile("Allenamento", str(counts.get("training", 0)), UIKit.TEAL))
	tiles.add_child(stat_tile("Riposo", str(counts.get("resting", 0)), UIKit.SKY))
	body.add_child(tiles)
	body.add_child(UIKit.para("Tocca un eroe per aprire la sua scheda.", 14))
	for hero in alive: body.add_child(hero_row(hero, [], bars(hero, true)))
	if not GS.data.memorial.is_empty():
		body.add_child(section("Memoriale", "%d caduti" % GS.data.memorial.size()))
		for record in GS.data.memorial:
			body.add_child(UIKit.label("† %s · %s Lv.%d · Piano %d" % [record.name, GS.role_label(str(record.role)), int(record.level), int(record.floor)], 15, UIKit.INK_SOFT, UIKit.body_bold()))
			body.add_child(UIKit.para(str(record.cause), 13, UIKit.MUTED))

func _party_busy() -> int:
	var count := 0
	for hero in GS.get_party():
		if not hero.is_empty() and GS.hero_activity(hero) != "party": count += 1
	return count

# =============================================================================
# Scheda eroe
# =============================================================================

func build_dossier(content: VBoxContainer, hero: Dictionary, modal_ref: Array) -> void:
	if hero.is_empty():
		content.add_child(UIKit.para("Eroe non più disponibile.", 16))
		return
	content.add_theme_constant_override("separation", 12)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	var portrait: HeroPortrait = HeroPortraitScript.new()
	portrait.setup(hero, 150)
	top.add_child(portrait)
	var id_box := VBoxContainer.new()
	id_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_box.add_theme_constant_override("separation", 4)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 6)
	pills.add_child(UIKit.pill(GS.RARITY_NAMES[int(hero.current_rarity)], UIKit.rarity_color(int(hero.current_rarity))))
	pills.add_child(activity_pill(hero))
	id_box.add_child(pills)
	id_box.add_child(UIKit.label("%s · Livello %d / %d" % [GS.role_label(hero.role), int(hero.level), GS.level_cap(hero)], 20, UIKit.INK, UIKit.head_font()))
	id_box.add_child(UIKit.label("%s · ex %s" % [hero.origin, str(hero.profession).to_lower()], 14, UIKit.INK_SOFT, UIKit.body_bold()))
	id_box.add_child(bars(hero, true))
	id_box.add_child(UIKit.label("Potenza %s · Missioni %d · Vittorie %d · Abbattimenti %d" % [GS.format_number(GS.hero_power(hero)), int(hero.missions), int(hero.victories), int(hero.kills)], 13, UIKit.MUTED, UIKit.body_bold()))
	top.add_child(id_box)
	content.add_child(top)
	if hero.state == "ALIVE":
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		var activity := GS.hero_activity(hero)
		if activity in ["training", "resting"]:
			actions.add_child(UIKit.button("Richiama dall'attività", _unassign.bind(str(hero.id)), "ghost", 0))
		else:
			actions.add_child(UIKit.button("Allena", _assign.bind(str(hero.id), "training"), "primary", 0))
			actions.add_child(UIKit.button("Riposa", _assign.bind(str(hero.id), "dormitory"), "sky", 0))
		var in_party: bool = GS.data.party.has(hero.id)
		actions.add_child(UIKit.button("Togli dalla squadra" if in_party else "Metti in squadra", _toggle_party.bind(str(hero.id)), "ghost" if in_party else "gold", 0))
		var req := GS.promotion_requirements(hero)
		if req.ok: actions.add_child(UIKit.button("Promuovi (%d Pietre)" % int(req.stones), _promote.bind(str(hero.id)), "violet", 0))
		content.add_child(actions)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(stat_tile("Forza", str(hero.stats.str), UIKit.ROSE))
	grid.add_child(stat_tile("Intelletto", str(hero.stats.int), UIKit.VIOLET))
	grid.add_child(stat_tile("Stamina", str(hero.stats.sta), UIKit.TEAL))
	grid.add_child(stat_tile("Agilità", str(hero.stats.agi), UIKit.SKY))
	content.add_child(grid)
	var d := GS.derived_stats(hero)
	var derived := UIKit.card()
	var dv := VBoxContainer.new()
	dv.add_child(UIKit.label("Combattimento", 17, UIKit.NAVY, UIKit.head_font()))
	dv.add_child(UIKit.para("HP %d · Attacco %.0f · Magia %.0f · Difesa %.0f · Precisione %.0f%% · Evasione %.0f%% · Critico %.0f%%%s" % [d.max_hp, d.attack, d.magic, d.defense, d.accuracy, d.evasion, d.crit, (" · Blocco %d" % int(d.block)) if int(d.block) > 0 else (" · Frecce %d" % int(d.ammo)) if int(d.ammo) > 0 else ""], 15, UIKit.INK))
	derived.add_child(dv)
	content.add_child(derived)
	var gear := UIKit.card()
	var gv := VBoxContainer.new()
	gv.add_child(UIKit.label("Equipaggiamento e abilità", 17, UIKit.NAVY, UIKit.head_font()))
	var eq: Dictionary = hero.equipment
	gv.add_child(UIKit.para("Arma: %s [%s] · Secondaria: %s · Armatura: %s [%s]%s" % [eq.main.get("name", "—"), eq.main.get("grade", "-"), eq.sub.get("name", "—"), eq.armor.get("name", "—"), eq.armor.get("grade", "-"), (" · Amuleto: " + str(eq.accessory.name)) if not eq.get("accessory", {}).is_empty() else ""], 14, UIKit.INK))
	var skills := []
	for skill in hero.skills: skills.append("%s Lv.%d" % [skill.name, int(skill.level)])
	gv.add_child(UIKit.para("Abilità: " + " · ".join(skills), 14, UIKit.INK))
	gv.add_child(UIKit.para("Tratti: " + ", ".join(hero.traits), 14, UIKit.INK))
	if not hero.injuries.is_empty():
		var inj := []
		for injury in hero.injuries: inj.append("%s (%d min di riposo)" % [injury.name, ceili(float(injury.minutes))])
		gv.add_child(UIKit.label("Ferite: " + ", ".join(inj), 14, UIKit.ROSE, UIKit.body_bold()))
	gear.add_child(gv)
	content.add_child(gear)
	var notes := UIKit.card()
	var nv := VBoxContainer.new()
	nv.add_child(UIKit.label("Valutazione del Master", 17, UIKit.NAVY, UIKit.head_font()))
	for line in hero.assessment: nv.add_child(UIKit.para("• " + str(line), 14, UIKit.INK))
	for memory in hero.memories.slice(0, 3): nv.add_child(UIKit.para("“%s”" % memory, 14, UIKit.INK_SOFT))
	notes.add_child(nv)
	content.add_child(notes)
	if bool(GS.data.dev.get("reveal_hidden", false)):
		var p: Dictionary = hero.personality
		content.add_child(info_card("DEV · Potenziale %d/100 · Crescita %.2f · Coraggio %d · Disciplina %d · Aggressività %d · Altruismo %d · Compostezza %d · Lealtà %d" % [int(hero.potential), float(hero.growth), int(p.courage), int(p.discipline), int(p.aggression), int(p.altruism), int(p.composure), int(p.loyalty)], "warn"))

func _toggle_party(hero_id: String) -> void:
	var index: int = GS.data.party.find(hero_id)
	if index >= 0:
		GS.remove_party(index)
		return
	var empty: int = GS.data.party.find("")
	if empty < 0:
		main.toast("Squadra completa", "Togli prima un eroe dal Portale → Squadra.", "warn")
		return
	GS.assign_party(empty, hero_id)

# =============================================================================
# Diario, materiali, impostazioni
# =============================================================================

func build_journal(content: VBoxContainer) -> void:
	content.add_theme_constant_override("separation", 8)
	for event in GS.data.events.slice(0, 60):
		var card := PanelContainer.new()
		var color := UIKit.tone_color(str(event.get("tone", "info")))
		card.add_theme_stylebox_override("panel", UIKit.box(UIKit.PAPER_DEEP, color.lerp(Color.WHITE, 0.3), 2, 12, 10))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var row := HBoxContainer.new()
		var t := UIKit.label(str(event.title), 16, UIKit.INK, UIKit.head_font())
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		row.add_child(UIKit.label(str(event.category), 11, color, UIKit.body_bold()))
		v.add_child(row)
		v.add_child(UIKit.para(str(event.text), 14))
		card.add_child(v)
		content.add_child(card)
	if not GS.data.memorial.is_empty():
		content.add_child(section("Memoriale"))
		for record in GS.data.memorial:
			content.add_child(UIKit.para("† %s, %s Lv.%d — caduto al Piano %d. %s" % [record.name, GS.role_label(str(record.role)), int(record.level), int(record.floor), record.cause], 14, UIKit.INK))

func build_materials(content: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for key in GS.MATERIALS:
		var info: Dictionary = GS.MATERIALS[key]
		var card := UIKit.card()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_child(UIKit.label("%s  %s" % [info.icon, info.name], 16, UIKit.NAVY, UIKit.head_font()))
		v.add_child(UIKit.label("%s / %d" % [GS.display_resource(key), GS.material_cap()], 20, UIKit.INK, UIKit.head_font()))
		v.add_child(UIKit.bar(float(GS.resource_amount(key)), float(GS.material_cap()), UIKit.TEAL, 8))
		card.add_child(v)
		grid.add_child(card)
	content.add_child(grid)
	content.add_child(UIKit.para("I materiali si trovano completando i piani della Torre.", 14))

func build_settings(content: VBoxContainer) -> void:
	content.add_theme_constant_override("separation", 10)
	content.add_child(UIKit.para("Il salvataggio è locale (%s) e si aggiorna da solo. Il tempo della base scorre anche quando chiudi il gioco, fino a 8 ore." % GS.SAVE_PATH, 15))
	var dev_on := bool(GS.data.dev.get("enabled", false))
	content.add_child(section("Modalità sviluppo", "attiva" if dev_on else "spenta"))
	content.add_child(UIKit.para("Risorse infinite e valori nascosti visibili, per provare il gioco velocemente. Disattivala per giocare con l'economia reale.", 14))
	content.add_child(UIKit.button("Disattiva modalità sviluppo" if dev_on else "Attiva modalità sviluppo", GS.set_dev_mode.bind(not dev_on), "ghost" if dev_on else "navy", 0))
	if dev_on:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.add_child(UIKit.button("Ignora requisiti di progressione", GS.dev_unlock_all, "navy", 0))
		grid.add_child(UIKit.button("Ripristina roster", GS.dev_restore_roster, "navy", 0))
		grid.add_child(UIKit.button("Genera eroe 5★", GS.dev_spawn_hero.bind(5), "navy", 0))
		grid.add_child(UIKit.button("Avanza il tempo di 30 min", _dev_time, "navy", 0))
		content.add_child(grid)
	content.add_child(section("Nuovo mondo"))
	content.add_child(UIKit.para("Ricomincia da zero con un nuovo seme. Il salvataggio attuale verrà cancellato.", 14))
	content.add_child(UIKit.button("Crea un nuovo mondo", _confirm_reset, "danger", 0))

func _dev_time() -> void:
	GS.advance_time(1800.0)
	GS.save_and_notify()

func _confirm_reset() -> void:
	main.confirm("Nuovo mondo", "Perderai eroi, base e progressi attuali. Continuare?", "Ricomincia", main.reset_world, "danger")

# =============================================================================
# Resoconto missione
# =============================================================================

func reason_text(reason: String) -> String:
	return {"clear": "zona ripulita", "survived": "resistito fino alla fine", "intel": "punti messi in sicurezza", "boss": "guardiano abbattuto", "party_wipe": "squadra annientata", "extracted": "estrazione completata", "timeout": "tempo scaduto", "beacon_lost": "faro perduto"}.get(reason, reason)

func build_mission_result(content: VBoxContainer, result: Dictionary, resolved: Dictionary) -> void:
	content.add_theme_constant_override("separation", 12)
	if bool(result.victory):
		var tiles := HBoxContainer.new()
		tiles.add_theme_constant_override("separation", 8)
		var rewards: Dictionary = resolved.get("rewards", {})
		tiles.add_child(stat_tile("Oro", "+" + GS.format_number(rewards.get("gold", 0)), UIKit.GOLD_DEEP))
		tiles.add_child(stat_tile("XP a testa", "+%d" % int(rewards.get("xp", 0)), UIKit.TEAL))
		if rewards.has("gems"): tiles.add_child(stat_tile("Gemme", "+%d" % int(rewards.gems), UIKit.SKY))
		if rewards.has("stones"): tiles.add_child(stat_tile("Pietre", "+%d" % int(rewards.stones), UIKit.VIOLET))
		content.add_child(tiles)
		var drops: Dictionary = resolved.get("drops", {})
		if not drops.is_empty():
			var parts := []
			for key in drops: parts.append("%s +%d" % [GS.MATERIALS[key].name, int(drops[key])])
			content.add_child(info_card("Bottino: " + " · ".join(parts), "good"))
		for up in resolved.get("level_ups", []):
			content.add_child(UIKit.label("▲ %s sale dal Lv.%d al Lv.%d" % [up.name, int(up.from), int(up.to)], 15, UIKit.TEAL, UIKit.body_bold()))
	else:
		content.add_child(info_card("Il piano resta identico: ritenta con una squadra più forte o più riposata.", "warn"))
	var deaths: Array = resolved.get("deaths", [])
	if not deaths.is_empty():
		content.add_child(section("Caduti", "%d" % deaths.size()))
		for record in deaths:
			var hero := GS.hero_by_id(str(record.id))
			if not hero.is_empty(): content.add_child(hero_row(hero, [], UIKit.label(str(record.cause), 13, UIKit.ROSE, UIKit.body_bold()), true))
	var injured := []
	for hero in GS.get_party():
		if not hero.is_empty() and not hero.injuries.is_empty(): injured.append(hero.name)
	if not injured.is_empty(): content.add_child(info_card("Feriti: %s. Mandali al Dormitorio prima della prossima missione." % ", ".join(injured), "warn"))
