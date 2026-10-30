extends RefCounted
class_name FacilityPanels

## Contenuti dei pannelli che si aprono sopra la base quando si tocca un edificio,
## più scheda eroe, diario, scorte, impostazioni e resoconto missione.

const HeroPortraitScript := preload("res://scripts/hero_portrait.gd")
const HeroCardScript := preload("res://scripts/ui/hero_card.gd")
const SummonEventScript := preload("res://scripts/ui/summon_event.gd")
const TowerMapScript := preload("res://scripts/ui/tower_map.gd")
const ROSTER_PAGE := 24

var main
var merge_selected: Array[String] = []
var merging_tab := "fusion"
var gate_tab := "mission"
var gate_floor := -1
var last_summon: Array = []
var roster_limit := ROSTER_PAGE
var shop_tab := "daily"
var _shop_screen: VBoxContainer
var dyn_rows: Dictionary = {}
var rendered_signature := ""

func _init(owner) -> void:
	main = owner

func reset_selection() -> void:
	merge_selected.clear()
	gate_floor = -1
	roster_limit = ROSTER_PAGE

var GS: RiftwardState:
	get: return GameState

# =============================================================================
# Aggiornamento senza ricostruire
# =============================================================================

## Chiamato da main prima di ricostruire il pannello aperto.
func begin_render() -> void:
	dyn_rows.clear()
	rendered_signature = signature(main.current_panel)

## Firma di ciò che cambia la struttura del pannello (non i valori delle barre):
## se non cambia, il tempo che scorre aggiorna solo barre e numeri.
func signature(panel: String) -> String:
	if panel == "crystal": return str(GS.emergency_recruit_status())
	if not panel in ["training", "dormitory", "roster", "gate"]: return "static"
	var parts := PackedStringArray()
	parts.append(str(GS.data.assignments.keys()))
	parts.append(str(GS.data.party))
	for hero in GS.get_alive_heroes():
		parts.append("%s:%d:%d:%d:%d" % [hero.id, int(hero.level), hero.injuries.size(), int(float(hero.fatigue) >= 85.0), int(float(hero.fatigue) >= 70.0)])
	return "|".join(parts)

func needs_rebuild(panel: String) -> bool:
	return signature(panel) != rendered_signature

func refresh_dynamic() -> void:
	for hero_id in dyn_rows:
		var hero := GS.hero_by_id(hero_id)
		if hero.is_empty(): continue
		var row: Dictionary = dyn_rows[hero_id]
		if row.has("xp") and is_instance_valid(row.xp):
			var need := GS.xp_to_next(int(hero.level))
			row.xp.max_value = need
			row.xp.value = float(hero.get("xp", 0))
			row.xp_label.text = "MAX" if int(hero.level) >= GS.level_cap(hero) else "%d/%d" % [int(hero.get("xp", 0)), need]
		if row.has("fat") and is_instance_valid(row.fat):
			row.fat.value = float(hero.fatigue)
			row.fat_label.text = str(roundi(float(hero.fatigue)))
			row.mor.value = float(hero.morale)
			row.mor_label.text = str(roundi(float(hero.morale)))
		if row.has("heal") and is_instance_valid(row.heal) and not hero.injuries.is_empty():
			row.heal.text = "%s · guarisce tra %d min" % [hero.injuries[0].name, ceili(float(hero.injuries[0].minutes))]

# =============================================================================
# Intestazioni e smistamento
# =============================================================================

func header_for(id: String) -> Dictionary:
	if GS.FACILITIES.has(id):
		var info: Dictionary = GS.FACILITIES[id]
		if GS.facility_built(id): return {"title": str(info.name), "subtitle": "Struttura · livello %d di %d" % [GS.facility_level(id), GS.facility_max_level()]}
		return {"title": str(info.name), "subtitle": "Cantiere disponibile"}
	match id:
		"crystal": return {"title": "Cristallo del Nexus", "subtitle": "Evocazione · base livello %d" % GS.base_level()}
		"roster": return {"title": "I tuoi eroi", "subtitle": "%d vivi · %d caduti" % [GS.get_alive_heroes().size(), GS.data.memorial.size()]}
	return {"title": id.capitalize(), "subtitle": ""}

func build(id: String, body: VBoxContainer, footer: VBoxContainer) -> void:
	if GS.FACILITIES.has(id) and not GS.facility_built(id):
		_build_plot(id, body, footer)
		return
	match id:
		"training": _build_training(body)
		"dormitory": _build_dormitory(body)
		"merging": _build_merging(body)
		"gate": _build_gate(body, footer)
		"crystal": _build_crystal(body)
		"armory": _build_armory(body)
		"warehouse": _build_warehouse(body)
		"workshop": _build_workshop(body)
		"alchemy": _build_alchemy(body)
		"roster": _build_roster(body)
	if GS.FACILITIES.has(id):
		# Nel Portale il fondo del pannello è riservato alla partenza.
		if id == "gate":
			body.add_child(section("La struttura"))
			_build_upgrade_footer(id, body)
		else:
			_build_upgrade_footer(id, footer)

# =============================================================================
# Widget comuni
# =============================================================================

func section(title: String, note: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	var t := UIKit.label(title.to_upper(), 17, UIKit.GOLD, UIKit.head_font())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	if not note.is_empty(): row.add_child(UIKit.label(note, 14, UIKit.MUTED, UIKit.body_bold()))
	box.add_child(row)
	box.add_child(UIKit.divider())
	return box

func info_card(text: String, tone: String = "info") -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.tinted(UIKit.tone_color(tone), 12.0))
	card.add_child(UIKit.para(text, 15, UIKit.INK_SOFT))
	return card

func activity_pill(hero: Dictionary) -> PanelContainer:
	match GS.hero_activity(hero):
		"training": return UIKit.pill("In allenamento", UIKit.TEAL)
		"resting": return UIKit.pill("A riposo", UIKit.SKY)
		"injured": return UIKit.pill("Ferito", UIKit.ROSE)
		"party": return UIKit.pill("In squadra", UIKit.GOLD)
		"dead": return UIKit.pill("Caduto", Color("#7d8696"))
	return UIKit.pill("Libero", Color("#7d8a9e"))

func stars_label(rarity: int, size: int = 15) -> Label:
	return UIKit.label(GS.stars(rarity), size, UIKit.rarity_color(rarity), UIKit.body_bold())

func hero_row(hero: Dictionary, actions: Array = [], extra: Control = null, show_activity: bool = true, highlight: Color = Color.TRANSPARENT) -> PanelContainer:
	var card := PanelContainer.new()
	if highlight != Color.TRANSPARENT: card.add_theme_stylebox_override("panel", UIKit.tinted(highlight, 10.0))
	else: card.add_theme_stylebox_override("panel", UIKit.ornate("card", 10.0))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_row_input.bind(str(hero.get("id", ""))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var portrait: HeroPortrait = HeroPortraitScript.new()
	portrait.setup(hero, 68)
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(UIKit.label(str(hero.name), 18, UIKit.INK, UIKit.head_font()))
	name_row.add_child(stars_label(int(hero.current_rarity), 13))
	info.add_child(name_row)
	info.add_child(UIKit.label("%s · Lv.%d/%d · Potenza %s" % [GS.role_label(hero.role), int(hero.level), GS.level_cap(hero), GS.format_number(GS.hero_power(hero))], 14, UIKit.INK_SOFT))
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
	var b := UIKit.button(text, callback, kind, 116)
	b.custom_minimum_size.y = 38
	b.add_theme_font_size_override("font_size", 14)
	if not disabled_reason.is_empty():
		b.disabled = true
		b.tooltip_text = disabled_reason
	return b

## Barre di esperienza, stanchezza e morale. Vengono registrate per
## l'aggiornamento in tempo reale senza ricostruire il pannello.
func bars(hero: Dictionary, show_xp: bool = false) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var entry: Dictionary = dyn_rows.get(str(hero.id), {})
	if show_xp:
		var cap_reached := int(hero.level) >= GS.level_cap(hero)
		var need := GS.xp_to_next(int(hero.level))
		var line := _bar_line("Esperienza", float(hero.get("xp", 0)), float(need), UIKit.TEAL, "MAX" if cap_reached else "%d/%d" % [int(hero.get("xp", 0)), need])
		entry["xp"] = line.get_child(1)
		entry["xp_label"] = line.get_child(2)
		box.add_child(line)
	var fat := _bar_line("Stanchezza", float(hero.fatigue), 100.0, UIKit.ROSE if float(hero.fatigue) >= 70 else UIKit.GOLD, str(roundi(float(hero.fatigue))))
	var mor := _bar_line("Morale", float(hero.morale), 100.0, UIKit.SKY, str(roundi(float(hero.morale))))
	entry["fat"] = fat.get_child(1)
	entry["fat_label"] = fat.get_child(2)
	entry["mor"] = mor.get_child(1)
	entry["mor_label"] = mor.get_child(2)
	box.add_child(fat)
	box.add_child(mor)
	dyn_rows[str(hero.id)] = entry
	return box

func _bar_line(title: String, value: float, max_value: float, color: Color, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := UIKit.label(title, 13, UIKit.MUTED, UIKit.body_bold())
	t.custom_minimum_size.x = 82
	row.add_child(t)
	var b := UIKit.bar(value, max_value, color, 8)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	var v := UIKit.label(text, 13, UIKit.INK_SOFT, UIKit.body_bold())
	v.custom_minimum_size.x = 60
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row

func cost_line(costs: Dictionary) -> HBoxContainer:
	var ok := GS.can_afford(costs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UIKit.label("Costo:", 15, UIKit.MUTED, UIKit.body_bold()))
	for key in costs:
		var enough := GS.can_afford({key: costs[key]})
		var icon := UIKit.icon(str(key), 20)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		row.add_child(UIKit.label(GS.format_number(costs[key]), 15, UIKit.INK if enough else UIKit.ROSE, UIKit.body_bold()))
	if not ok: row.add_child(UIKit.label("· non basta", 14, UIKit.ROSE, UIKit.body_font()))
	return row

func stat_tile(title: String, value: String, color: Color = UIKit.INK) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.ornate("inset", 10.0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(UIKit.label(title.to_upper(), 12, UIKit.MUTED, UIKit.head_medium()))
	box.add_child(UIKit.label(value, 23, color, UIKit.head_font()))
	card.add_child(box)
	return card

func tabs(options: Array, current: String, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for option in options:
		var b := UIKit.button(option[1], callback.bind(option[0]), "primary" if option[0] == current else "ghost", 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 42
		row.add_child(b)
	return row

## Apre un selettore eroi in una finestra.
func pick_hero(title: String, candidates: Array, callback: Callable, note: Callable = Callable()) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	var modal_ref := []
	if candidates.is_empty(): list.add_child(info_card("Nessun eroe disponibile.", "warn"))
	for hero in candidates:
		var extra: Control = null
		if note.is_valid():
			var text: String = note.call(hero)
			if not text.is_empty(): extra = UIKit.label(text, 14, UIKit.GOLD, UIKit.body_bold())
		list.add_child(hero_row(hero, [small_button("Scegli", _picked.bind(modal_ref, callback, str(hero.id)), "primary")], extra))
	var modal: Control = await main.open_modal(title, "Scegli un eroe", list, 660)
	modal_ref.append(modal)

func _picked(modal_ref: Array, callback: Callable, hero_id: String) -> void:
	if not modal_ref.is_empty(): main.close_modal(modal_ref[0])
	callback.call(hero_id)

func _build_upgrade_footer(id: String, footer: VBoxContainer) -> void:
	var check := GS.can_upgrade_facility(id)
	var level := GS.facility_level(id)
	if level >= 5:
		footer.add_child(UIKit.label("Livello massimo raggiunto.", 15, UIKit.MUTED, UIKit.body_bold()))
		return
	var cost := GS.facility_upgrade_cost(id)
	var b := UIKit.button("Aggiungi un piano · Lv.%d  (%s Oro)" % [level + 1, GS.format_number(cost.gold)], _upgrade.bind(id), "gold", 0)
	b.disabled = not check.ok
	footer.add_child(b)
	if not check.ok: footer.add_child(UIKit.label(str(check.message), 14, UIKit.ROSE, UIKit.body_bold()))

func _upgrade(id: String) -> void:
	main.report(GS.upgrade_facility(id), "%s potenziato" % GS.FACILITIES[id].short, "La struttura cresce di un piano.")

# =============================================================================
# Addestramento
# =============================================================================

func _build_training(body: VBoxContainer) -> void:
	var assigned := GS.assigned_to("training")
	body.add_child(info_card("Sul campo rialzato gli eroi guadagnano esperienza col passare del tempo, anche a gioco chiuso (fino a 8 ore). Allenarsi stanca: quando la stanchezza sale, mandali al Dormitorio."))
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(stat_tile("Posti", "%d / %d" % [assigned.size(), GS.training_slots()], UIKit.TEAL))
	tiles.add_child(stat_tile("Velocità", "+%d%%" % roundi(35.0 * (GS.facility_level("training") - 1)), UIKit.GOLD))
	body.add_child(tiles)
	body.add_child(section("Sul campo", "%d/%d" % [assigned.size(), GS.training_slots()]))
	if assigned.is_empty(): body.add_child(UIKit.para("Nessuno si sta allenando. Scegli qualcuno qui sotto.", 15))
	for hero in assigned:
		var extra := VBoxContainer.new()
		extra.add_child(bars(hero, true))
		extra.add_child(UIKit.label("circa %d esperienza al minuto" % roundi(GS.training_xp_per_minute(hero)), 13, UIKit.TEAL, UIKit.body_bold()))
		body.add_child(hero_row(hero, [small_button("Richiama", _unassign.bind(str(hero.id)), "ghost")], extra, false, UIKit.TEAL))
	body.add_child(section("Disponibili"))
	var free := GS.get_alive_heroes().filter(func(h): return not GS.data.assignments.has(h.id))
	free.sort_custom(func(a, b): return int(a.level) < int(b.level))
	var full := assigned.size() >= GS.training_slots()
	for hero in free:
		var reason := ""
		if int(hero.level) >= GS.level_cap(hero): reason = "Livello massimo: serve una promozione"
		elif not hero.injuries.is_empty(): reason = "Ferito"
		elif int(hero.fatigue) >= 85: reason = "Troppo stanco"
		elif full: reason = "Posti esauriti"
		var b := small_button("Allena", _assign.bind(str(hero.id), "training"), "primary", reason)
		var extra: Control = UIKit.label(reason, 13, UIKit.ROSE, UIKit.body_bold()) if not reason.is_empty() and reason != "Posti esauriti" else null
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
	tiles.add_child(stat_tile("Recupero", "+%d%%" % roundi(25.0 * (GS.facility_level("dormitory") - 1)), UIKit.GOLD))
	body.add_child(tiles)
	body.add_child(section("A riposo", "%d/%d" % [resting.size(), GS.dormitory_slots()]))
	if resting.is_empty(): body.add_child(UIKit.para("I letti sono liberi.", 15))
	for hero in resting:
		var extra := VBoxContainer.new()
		extra.add_child(bars(hero))
		if not hero.injuries.is_empty():
			var heal := UIKit.label("%s · guarisce tra %d min" % [hero.injuries[0].name, ceili(float(hero.injuries[0].minutes))], 13, UIKit.ROSE, UIKit.body_bold())
			dyn_rows[str(hero.id)]["heal"] = heal
			extra.add_child(heal)
		body.add_child(hero_row(hero, [small_button("Sveglia", _unassign.bind(str(hero.id)), "ghost")], extra, false, UIKit.SKY))
	body.add_child(section("Chi ne ha bisogno"))
	var free := GS.get_alive_heroes().filter(func(h): return not GS.data.assignments.has(h.id))
	free.sort_custom(func(a, b): return _need(a) > _need(b))
	var full := resting.size() >= GS.dormitory_slots()
	for hero in free:
		var extra := VBoxContainer.new()
		extra.add_child(bars(hero))
		if not hero.injuries.is_empty(): extra.add_child(UIKit.label(str(hero.injuries[0].name), 13, UIKit.ROSE, UIKit.body_bold()))
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
	body.add_child(info_card("Unisci tre eroi della stessa rarità (fino a 4★). Il primo scelto è il nucleo: sale di una stella e assorbe parte della forza degli altri due, che se ne vanno per sempre."))
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 10)
	for i in 3:
		var holder := VBoxContainer.new()
		holder.alignment = BoxContainer.ALIGNMENT_CENTER
		if i < merge_selected.size():
			var card: HeroCard = HeroCardScript.new()
			card.setup(GS.hero_by_id(merge_selected[i]), 112.0)
			card.pressed.connect(_toggle_merge)
			card.tooltip_text = "Tocca per togliere"
			holder.add_child(card)
		else:
			var empty := PanelContainer.new()
			empty.custom_minimum_size = Vector2(112, 174)
			var st := UIKit.ornate("inset", 0.0)
			st.border = Color("#3f6a8c") if i == 0 else Color("#22304a")
			empty.add_theme_stylebox_override("panel", st)
			var q := UIKit.title("?", 34, Color("#3f6a8c"))
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.add_child(q)
			holder.add_child(empty)
		var caption := UIKit.label("NUCLEO" if i == 0 else "DONATORE", 13, UIKit.LILAC if i == 0 else UIKit.MUTED, UIKit.head_medium())
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(caption)
		slots.add_child(holder)
		if i < 2: slots.add_child(UIKit.title("+", 26, UIKit.MUTED))
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
	main.confirm("Fusione degli eroi", "%s diventerà %s.\n\n%s e %s se ne andranno per sempre." % [heroes[0].name, GS.stars(int(heroes[0].current_rarity) + 1), heroes[1].name, heroes[2].name], "Fondi", _do_merge, "violet")

func _do_merge() -> void:
	var result := GS.merge_heroes(merge_selected)
	if result.ok:
		merge_selected.clear()
		main.toast("Fusione completata", "%s ora è %s" % [result.hero.name, GS.stars(int(result.hero.current_rarity))], "good")
	else: main.toast("Fusione bloccata", str(result.message), "warn")

func _build_promotion(body: VBoxContainer) -> void:
	body.add_child(info_card("Un eroe al livello massimo della sua rarità può essere promosso con le Pietre. Le promozioni a 6★ e 7★ sono durissime: servono i Piani 30 e 60."))
	body.add_child(stat_tile("Pietre disponibili", GS.display_resource("stones"), UIKit.VIOLET))
	var heroes := GS.get_alive_heroes()
	heroes.sort_custom(func(a, b): return float(a.level) / GS.level_cap(a) > float(b.level) / GS.level_cap(b))
	for hero in heroes:
		var req := GS.promotion_requirements(hero)
		var extra := UIKit.label(("Pronto · %d Pietre" % int(req.stones)) if req.ok else str(req.message), 14, UIKit.TEAL if req.ok else UIKit.MUTED, UIKit.body_bold())
		var b := small_button("Promuovi", _promote.bind(str(hero.id)), "violet", "" if req.ok else str(req.message))
		body.add_child(hero_row(hero, [b] if int(hero.current_rarity) < 7 else [], extra))

func _promote(hero_id: String) -> void:
	main.report(GS.promote_hero(hero_id), "Promozione riuscita", "%s sale di rarità." % GS.hero_by_id(hero_id).name)

# =============================================================================
# Portale delle Missioni e squadra
# =============================================================================

func _build_gate(body: VBoxContainer, footer: VBoxContainer) -> void:
	body.add_child(tabs([["mission", "Missione"], ["squad", "Squadra"]], gate_tab, _set_gate_tab))
	if gate_tab == "squad":
		_build_squad(body)
		return
	var max_floor := int(GS.data.world.max_floor)
	if gate_floor < 1 or gate_floor > max_floor: gate_floor = int(GS.data.world.current_floor)
	var selector := HBoxContainer.new()
	selector.add_theme_constant_override("separation", 8)
	if max_floor > 10:
		var back10 := UIKit.button("«10", _shift_floor.bind(-10), "ghost", 58)
		back10.disabled = gate_floor <= 1
		selector.add_child(back10)
	var prev := UIKit.button("‹", _shift_floor.bind(-1), "ghost", 52)
	prev.add_theme_font_size_override("font_size", 28)
	prev.disabled = gate_floor <= 1
	selector.add_child(prev)
	var title := UIKit.title("Piano %d" % gate_floor, 30, UIKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_child(title)
	var next := UIKit.button("›", _shift_floor.bind(1), "ghost", 52)
	next.add_theme_font_size_override("font_size", 28)
	next.disabled = gate_floor >= max_floor
	selector.add_child(next)
	if max_floor > 10:
		var fwd10 := UIKit.button("10»", _shift_floor.bind(10), "ghost", 58)
		fwd10.disabled = gate_floor >= max_floor
		selector.add_child(fwd10)
	body.add_child(selector)
	body.add_child(UIKit.button("Mappa della Torre", open_tower_map, "ghost", 0))
	var record := GS.get_stage(gate_floor)
	var stage: Dictionary = record.descriptor
	var color := Color(str(stage.get("color", "#3c7968")))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.tinted(color.lightened(0.15), 14.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.add_child(UIKit.pill(_type_label(str(stage.type)), color.lightened(0.25)))
	tags.add_child(UIKit.pill(str(stage.biome), Color("#7d8a9e")))
	if bool(record.cleared): tags.add_child(UIKit.pill("Completato", UIKit.TEAL))
	v.add_child(tags)
	var name_label := UIKit.title(str(stage.name), 22, UIKit.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_label)
	v.add_child(UIKit.para(str(stage.description), 15))
	var objective := UIKit.para("Obiettivo: " + str(stage.objective), 15, UIKit.INK)
	objective.add_theme_font_override("font", UIKit.body_bold())
	v.add_child(objective)
	v.add_child(UIKit.label("Minaccia %d · Tentativi %d%s" % [int(stage.get("threat_budget", 100)), int(record.attempts), (" · Record %ds" % roundi(float(record.best_time))) if float(record.best_time) > 0 else ""], 14, UIKit.MUTED, UIKit.body_bold()))
	card.add_child(v)
	body.add_child(card)
	var rewards := GS.floor_rewards(gate_floor, int(record.attempts) + 1, not bool(record.cleared))
	var reward_text := "%s Oro · %d esperienza a superstite" % [GS.format_number(rewards.gold), int(rewards.xp)]
	if rewards.has("gems"): reward_text += " · %d Gemme al primo completamento" % int(rewards.gems)
	if rewards.has("stones"): reward_text += " · %d Pietre" % int(rewards.stones)
	body.add_child(info_card("Ricompense: " + reward_text, "good"))
	if int(record.attempts) > 0 and not bool(record.cleared): body.add_child(info_card("Il piano non cambia tra un tentativo e l'altro: stessi nemici, ricompense ridotte a ogni nuovo tentativo.", "warn"))
	var ready := GS.party_readiness()
	body.add_child(section("La squadra", "Potenza %s · %s" % [GS.format_number(ready.score), ready.grade]))
	var faces := HBoxContainer.new()
	faces.alignment = BoxContainer.ALIGNMENT_CENTER
	faces.add_theme_constant_override("separation", 8)
	for i in GS.PARTY_SIZE:
		var hero: Dictionary = GS.get_party()[i]
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 2)
		if hero.is_empty():
			var empty := PanelContainer.new()
			empty.custom_minimum_size = Vector2(80, 80)
			empty.add_theme_stylebox_override("panel", UIKit.ornate("inset", 0.0))
			slot.add_child(empty)
		else:
			var p: HeroPortrait = HeroPortraitScript.new()
			p.setup(hero, 80)
			p.tooltip_text = str(hero.name)
			slot.add_child(p)
		var line_label := UIKit.label(_line_label(GS.FORMATION_LINES[i]).to_upper(), 12, UIKit.MUTED, UIKit.head_medium())
		line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(line_label)
		faces.add_child(slot)
	body.add_child(faces)
	for warning in ready.warnings.slice(0, 6):
		body.add_child(UIKit.para("• " + str(warning), 15, UIKit.ROSE))
	var go := UIKit.button("Attraversa il Portale · Piano %d" % gate_floor, _confirm_deploy.bind(gate_floor), "gold", 0)
	go.custom_minimum_size.y = 56
	go.add_theme_font_size_override("font_size", 19)
	go.disabled = not ready.ready
	footer.add_child(go)
	if not ready.ready: footer.add_child(UIKit.button("Componi la squadra", _set_gate_tab.bind("squad"), "primary", 0))

func _line_label(line: String) -> String:
	return {"Front": "Prima linea", "Mid": "Centro", "Rear": "Retroguardia"}.get(line, line)

func _type_label(type: String) -> String:
	return {"Subjugation": "Sterminio", "Survival": "Sopravvivenza", "Exploration": "Esplorazione", "Defense": "Difesa", "Boss": "Guardiano"}.get(type, type)

func _set_gate_tab(tab: String) -> void:
	gate_tab = tab
	main._render_panel(true)

func _shift_floor(delta: int) -> void:
	gate_floor = clampi(gate_floor + delta, 1, int(GS.data.world.max_floor))
	main._render_panel()

func _confirm_deploy(floor_index: int) -> void:
	main.confirm("Partenza per il Piano %d" % floor_index, "In missione gli eroi combattono da soli: tu puoi dare solo ordini generali.\n\nChi cade non torna. Non esistono resurrezioni.", "Attraversa il Portale", main.deploy.bind(floor_index), "gold")

# --- Mappa della Torre ---------------------------------------------------------

func open_tower_map() -> void:
	var max_floor := int(GS.data.world.max_floor)
	if gate_floor < 1 or gate_floor > max_floor: gate_floor = int(GS.data.world.current_floor)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	var tower = TowerMapScript.new()
	tower.setup(GS, gate_floor)
	# la mappa deve stare tutta nella finestra senza scorrere
	tower.custom_minimum_size.y = clampf(main.size.y * 0.66 - 44.0 - 70.0, 400.0, 620.0)
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 8)
	var page_label := UIKit.label("", 15, UIKit.CYAN, UIKit.head_font())
	page_label.custom_minimum_size.x = 140
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 400
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	var modal_ref := []
	var show_page := func(first: int):
		tower.set_page(first)
		page_label.text = "PIANI %d–%d" % [tower.first_floor, tower.first_floor + TowerMapScript.PER_PAGE - 1]
	pager.add_child(UIKit.button("‹ Giù", func(): show_page.call(tower.first_floor - TowerMapScript.PER_PAGE), "ghost", 90))
	pager.add_child(page_label)
	pager.add_child(UIKit.button("Su ›", func(): show_page.call(tower.first_floor + TowerMapScript.PER_PAGE), "ghost", 90))
	var to_frontier := func():
		show_page.call(int((max_floor - 1) / TowerMapScript.PER_PAGE) * TowerMapScript.PER_PAGE + 1)
		tower.selected = max_floor
		_tower_info(info, max_floor, modal_ref)
	pager.add_child(UIKit.button("Prossimo piano", to_frontier, "gold", 0))
	show_page.call(tower.first_floor)
	left.add_child(pager)
	left.add_child(tower)
	row.add_child(left)
	row.add_child(info)
	tower.floor_selected.connect(func(f: int): _tower_info(info, f, modal_ref))
	_tower_info(info, gate_floor, modal_ref)
	var modal: Control = await main.open_modal("Mappa della Torre", "Piano più alto raggiunto: %d di %d" % [max_floor, GS.MAX_FLOOR], row, 1000)
	modal_ref.append(modal)

## Scheda del piano scelto sulla mappa: rischio, squadra e ricompense prima di entrare.
func _tower_info(info: VBoxContainer, floor_index: int, modal_ref: Array) -> void:
	UIKit.clear(info)
	var max_floor := int(GS.data.world.max_floor)
	info.add_child(UIKit.eyebrow("PIANO %d%s" % [floor_index, " · GUARDIANO" if floor_index % 5 == 0 else ""]))
	if floor_index > max_floor:
		info.add_child(UIKit.title("???", 30, UIKit.MUTED))
		info.add_child(UIKit.pill("Bloccato", Color("#5b6678")))
		info.add_child(UIKit.para("Il Sistema non mostra questo piano finché non completi il Piano %d." % (max_floor), 16))
		return
	var record := GS.get_stage(floor_index)
	var stage: Dictionary = record.descriptor
	var color := Color(str(stage.get("color", "#3c7968")))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.add_child(UIKit.pill(_type_label(str(stage.type)), color.lightened(0.25)))
	tags.add_child(UIKit.pill(str(stage.biome), Color("#7d8a9e")))
	if bool(record.cleared): tags.add_child(UIKit.pill("Completato", UIKit.TEAL))
	elif floor_index == max_floor: tags.add_child(UIKit.pill("Prossimo", UIKit.GOLD))
	info.add_child(tags)
	var name_label := UIKit.title(str(stage.name), 26, UIKit.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_label)
	info.add_child(UIKit.para(str(stage.description), 15))
	var objective := UIKit.para("Obiettivo: " + str(stage.objective), 15, UIKit.INK)
	objective.add_theme_font_override("font", UIKit.body_bold())
	info.add_child(objective)
	var threat := int(stage.get("threat_budget", 100))
	var threat_color := UIKit.TEAL if threat < 600 else UIKit.GOLD if threat < 1800 else UIKit.ROSE
	info.add_child(_bar_line("Minaccia", float(threat), 3800.0, threat_color, str(threat)))
	var ready := GS.party_readiness()
	info.add_child(UIKit.label("Potenza della squadra: %s · grado %s" % [GS.format_number(ready.score), ready.grade], 15, UIKit.INK_SOFT, UIKit.body_bold()))
	var rewards := GS.floor_rewards(floor_index, int(record.attempts) + 1, not bool(record.cleared))
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(stat_tile("Oro", GS.format_number(rewards.gold), UIKit.GOLD))
	tiles.add_child(stat_tile("Esperienza", str(int(rewards.xp)), UIKit.TEAL))
	if rewards.has("gems"): tiles.add_child(stat_tile("Gemme", str(int(rewards.gems)), UIKit.SKY))
	if rewards.has("stones"): tiles.add_child(stat_tile("Pietre", str(int(rewards.stones)), UIKit.VIOLET))
	info.add_child(tiles)
	info.add_child(UIKit.label("Tentativi %d%s" % [int(record.attempts), (" · Record %ds" % roundi(float(record.best_time))) if float(record.best_time) > 0 else ""], 14, UIKit.MUTED, UIKit.body_bold()))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.add_child(UIKit.button("Scegli questo piano", _tower_choose.bind(floor_index, modal_ref, false), "primary", 0))
	var go := UIKit.button("Parti", _tower_choose.bind(floor_index, modal_ref, true), "gold", 140)
	go.disabled = not ready.ready
	actions.add_child(go)
	info.add_child(UIKit.hsep(4))
	info.add_child(actions)

func _tower_choose(floor_index: int, modal_ref: Array, deploy: bool) -> void:
	gate_floor = floor_index
	if not modal_ref.is_empty(): main.close_modal(modal_ref[0])
	if main.current_panel == "gate": main._render_panel()
	if deploy: _confirm_deploy(floor_index)

func _build_squad(body: VBoxContainer) -> void:
	body.add_child(info_card("Due eroi in prima linea, due al centro, uno in retroguardia. Guardiani e Avanguardie davanti, Lancieri e Supporti al centro, Ranger o Maghi dietro."))
	body.add_child(UIKit.button("Formazione consigliata", _auto_party, "primary", 0))
	body.add_child(_formation_board())
	body.add_child(section("Dettagli dei posti"))
	var party := GS.get_party()
	for i in GS.PARTY_SIZE:
		var hero: Dictionary = party[i]
		var line: String = GS.FORMATION_LINES[i]
		body.add_child(UIKit.label("POSTO %d · %s" % [i + 1, _line_label(line).to_upper()], 15, UIKit.GOLD, UIKit.head_medium()))
		if hero.is_empty():
			body.add_child(UIKit.button("Scegli un eroe", _pick_slot.bind(i), "ghost", 0))
		else:
			var mismatch: bool = str(GS.ROLES[hero.role].line) != line
			var extra: Control = UIKit.label("Ruolo da %s" % _line_label(str(GS.ROLES[hero.role].line)).to_lower(), 13, UIKit.ROSE, UIKit.body_bold()) if mismatch else bars(hero)
			body.add_child(hero_row(hero, [small_button("Cambia", _pick_slot.bind(i), "primary"), small_button("Togli", _clear_slot.bind(i), "ghost")], extra, false))

## Schema visivo della formazione: tre linee di posti, riserve trascinabili sotto.
## Trascina una carta della riserva su un posto, o tocca un posto per scegliere.
func _formation_board() -> Control:
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", UIKit.ornate("inset", 12.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	board.add_child(v)
	var party := GS.get_party()
	for line_def in [["Front", [0, 1], "PRIMA LINEA"], ["Mid", [2, 3], "CENTRO"], ["Rear", [4], "RETROGUARDIA"]]:
		var label := UIKit.eyebrow(line_def[2])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(label)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		for slot in line_def[1]: row.add_child(_formation_slot(slot, party[slot], str(line_def[0])))
		v.add_child(row)
	var reserve := GS.get_alive_heroes().filter(func(h): return not GS.data.party.has(h.id))
	reserve.sort_custom(func(a, b): return GS.hero_power(a) > GS.hero_power(b))
	v.add_child(UIKit.divider())
	v.add_child(UIKit.label("RISERVA · trascina una carta su un posto", 12, UIKit.INK_SOFT, UIKit.head_medium()))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for hero in reserve.slice(0, 18):
		var card: HeroCard = HeroCardScript.new()
		card.setup(hero, 70.0)
		card.tooltip_text = "%s · %s · Lv.%d" % [hero.name, GS.role_label(hero.role), int(hero.level)]
		card.set_drag_forwarding(_drag_hero.bind(str(hero.id), card), Callable(), Callable())
		card.pressed.connect(main.open_hero)
		flow.add_child(card)
	if reserve.is_empty(): flow.add_child(UIKit.label("Tutti gli eroi vivi sono già in squadra.", 14, UIKit.MUTED))
	v.add_child(flow)
	return board

func _formation_slot(slot: int, hero: Dictionary, line: String) -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 2)
	var target: Control
	if hero.is_empty():
		var empty := UIKit.button("+", _pick_slot.bind(slot), "ghost", 96)
		empty.custom_minimum_size = Vector2(96, 149)
		empty.add_theme_font_size_override("font_size", 30)
		empty.tooltip_text = "Posto %d · scegli un eroe" % (slot + 1)
		target = empty
	else:
		var card: HeroCard = HeroCardScript.new()
		card.setup(hero, 96.0)
		card.pressed.connect(func(_id): _pick_slot(slot))
		card.tooltip_text = "Tocca per cambiare · %s" % hero.name
		target = card
	target.set_drag_forwarding(Callable(), _can_drop_hero, _drop_hero.bind(slot))
	holder.add_child(target)
	var note := "Posto %d" % (slot + 1)
	var color := UIKit.MUTED
	if not hero.is_empty():
		var fits := str(GS.ROLES[hero.role].line) == line
		note = GS.role_label(hero.role) if fits else "Fuori ruolo"
		color = UIKit.INK_SOFT if fits else UIKit.ROSE
	var l := UIKit.label(note, 12, color, UIKit.body_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(l)
	return holder

func _drag_hero(_at: Vector2, hero_id: String, card: HeroCard) -> Variant:
	var preview: HeroCard = HeroCardScript.new()
	preview.setup(card.hero, 70.0)
	preview.modulate.a = 0.85
	card.set_drag_preview(preview)
	return {"hero_id": hero_id}

func _can_drop_hero(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("hero_id")

func _drop_hero(_at: Vector2, data: Variant, slot: int) -> void:
	_assign_slot(str(data.hero_id), slot)

func _pick_slot(slot: int) -> void:
	var line: String = GS.FORMATION_LINES[slot]
	var candidates := GS.get_alive_heroes().filter(func(h): return GS.data.party[slot] != h.id)
	candidates.sort_custom(func(a, b):
		var ma := 1 if str(GS.ROLES[a.role].line) == line else 0
		var mb := 1 if str(GS.ROLES[b.role].line) == line else 0
		if ma != mb: return ma > mb
		return GS.hero_power(a) > GS.hero_power(b))
	pick_hero("Posto %d · %s" % [slot + 1, _line_label(line)], candidates, _assign_slot.bind(slot), _slot_note.bind(line))

func _slot_note(hero: Dictionary, line: String) -> String:
	var parts := []
	if str(GS.ROLES[hero.role].line) == line: parts.append("Adatto")
	if GS.data.party.has(hero.id): parts.append("già in squadra")
	if GS.data.assignments.has(hero.id): parts.append("lascerà l'attività")
	if not hero.injuries.is_empty(): parts.append("ferito")
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
	body.add_child(section("Evocazione", "%d eroi vivi" % GS.get_alive_heroes().size()))
	var emergency := GS.emergency_recruit_status()
	if emergency.visible:
		body.add_child(info_card("Ti restano meno di cinque eroi. Il Nexus può richiamare gratis una recluta 1★ ogni 30 minuti.", "warn"))
		var eb := UIKit.button("Richiamo d'emergenza (gratis)", _emergency, "gold", 0)
		eb.disabled = not emergency.ok
		body.add_child(eb)
		if not emergency.ok: body.add_child(UIKit.label(str(emergency.message), 14, UIKit.MUTED, UIKit.body_bold()))
	for pool in ["normal", "high", "transcendent"]: body.add_child(_pool_card(pool))
	body.add_child(section("Espansione della base", "Base Lv.%d" % GS.base_level()))
	var next := GS.next_base_level()
	if next.is_empty():
		body.add_child(info_card("La base ha raggiunto il livello massimo.", "good"))
	else:
		var unlocks := []
		for id in GS.FACILITY_ORDER:
			if int(GS.FACILITIES[id].unlock) == int(next.level): unlocks.append(GS.FACILITIES[id].name)
		var text := "Base Lv.%d: ogni struttura potrà crescere fino al Lv.%d (un piano in più)." % [int(next.level), int(next.level)]
		if not unlocks.is_empty(): text += "\nNuovi cantieri: " + ", ".join(unlocks) + "."
		text += "\nAnche il villaggio cresce: nuove case, strade lastricate, lampioni e stendardi."
		body.add_child(info_card(text))
		body.add_child(UIKit.label("Requisiti: Piano %d completato · %s Oro" % [int(next.floor), GS.format_number(next.gold)], 15, UIKit.INK_SOFT, UIKit.body_bold()))
		var check := GS.can_upgrade_base()
		var b := UIKit.button("Espandi la base a Lv.%d" % int(next.level), _upgrade_base, "gold", 0)
		b.disabled = not check.ok
		body.add_child(b)
		if not check.ok: body.add_child(UIKit.label(str(check.message), 14, UIKit.ROSE, UIKit.body_bold()))

func _pool_card(pool: String) -> PanelContainer:
	var info: Dictionary = GS.SUMMON_POOLS[pool]
	var color: Color = {"normal": UIKit.CYAN, "high": UIKit.MAGENTA, "transcendent": UIKit.rarity_color(6)}[pool]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.tinted(color, 14.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UIKit.title(str(info.name), 21, color.lightened(0.35)))
	var rates := []
	for r in info.rates: rates.append("%s %s%%" % [GS.stars(int(r[0])), str(r[1]).replace(".", ",")])
	var rate_label := UIKit.para("  ·  ".join(rates), 15, UIKit.INK)
	rate_label.add_theme_font_override("font", UIKit.body_bold())
	v.add_child(rate_label)
	if pool == "high": v.add_child(UIKit.label("5★ garantito entro %d evocazioni · ora %d/%d" % [GS.HIGH_HARD_PITY, int(GS.data.pity.high), GS.HIGH_HARD_PITY], 14, UIKit.INK_SOFT))
	var currency := "Oro" if info.currency == "gold" else "Gemme"
	var unlocked := GS.summon_pool_unlocked(pool)
	if not unlocked: v.add_child(UIKit.label("Si sblocca completando il Piano %d" % int(info.unlock_floor), 15, UIKit.ROSE, UIKit.body_bold()))
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
		main.toast("Base Lv.%d" % int(result.level), ("Nuovi cantieri: " + ", ".join(result.unlocked)) if not result.unlocked.is_empty() else "Gli edifici possono crescere di un piano.", "good")
	else: main.toast("Non ancora", str(result.message), "warn")

## Evocazione: evento a schermo intero (vedi SummonEvent).
func _summon(pool: String, count: int) -> void:
	var result := GS.summon(pool, count)
	if not result.ok:
		main.toast("Evocazione bloccata", str(result.message), "warn")
		return
	last_summon = result.heroes
	var event = SummonEventScript.new()
	event.setup(result.heroes, str(GS.SUMMON_POOLS[pool].name))
	event.hero_pressed.connect(_open_from_summon)
	main.modal_layer.add_child(event)

func _open_from_summon(hero_id: String) -> void:
	main.open_hero(hero_id)

# =============================================================================
# Strutture sbloccate più avanti
# =============================================================================

func _build_plot(id: String, body: VBoxContainer, footer: VBoxContainer) -> void:
	var info: Dictionary = GS.FACILITIES[id]
	body.add_child(UIKit.para(str(info.description), 17, UIKit.INK))
	if GS.facility_available(id):
		var cost := {"gold": int(info.build_cost)}
		body.add_child(cost_line(cost))
		var b := UIKit.button("Costruisci", _build_facility.bind(id), "gold", 0)
		b.disabled = not GS.can_afford(cost)
		footer.add_child(b)
	else:
		body.add_child(info_card("Si sblocca con la Base Lv.%d." % int(info.unlock), "warn"))

func _build_facility(id: String) -> void:
	var result := GS.build_facility(id)
	main.report(result, "%s costruita" % GS.FACILITIES[id].name, "La nuova struttura è pronta.")
	if result.ok: main.hub.focus_on(id, main.PANEL_WIDTH + 16)

func _recipe_card(title: String, description: String, costs: Dictionary, button_text: String, callback: Callable, kind: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.ornate("card", 12.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(UIKit.label(title.to_upper(), 17, UIKit.GOLD, UIKit.head_font()))
	if not description.is_empty(): v.add_child(UIKit.para(description, 15))
	v.add_child(cost_line(costs))
	var b := small_button(button_text, callback, kind, "" if GS.can_afford(costs) else "Risorse insufficienti")
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(b)
	card.add_child(v)
	return card

func _build_armory(body: VBoxContainer) -> void:
	body.add_child(info_card("Forgia armi, armature e amuleti. Più l'Armeria è alta, più è facile ottenere gradi migliori (da D a S)."))
	for recipe_id in GS.FORGE_RECIPES:
		var recipe: Dictionary = GS.FORGE_RECIPES[recipe_id]
		body.add_child(_recipe_card(str(recipe.name), "", recipe.cost, "Forgia", _forge.bind(recipe_id), "gold"))
	body.add_child(section("In deposito", "%d oggetti" % GS.data.inventory.size()))
	if GS.data.inventory.is_empty(): body.add_child(UIKit.para("Nessun oggetto forgiato.", 15))
	for item in GS.data.inventory:
		var slot := str(item.get("slot", "main"))
		var stat := ("Attacco +%d" % int(item.get("power", 0))) if slot == "main" else ("Difesa +%d" % int(item.get("defense", 0))) if slot == "armor" else ("Vita +%d" % int(item.get("hp", 0)))
		var row := HBoxContainer.new()
		var t := VBoxContainer.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_child(UIKit.label(str(item.get("name", "Oggetto")), 17, UIKit.INK, UIKit.head_font()))
		t.add_child(UIKit.label("%s · grado %s" % [stat, str(item.get("grade", "D"))], 14, UIKit.INK_SOFT, UIKit.body_bold()))
		row.add_child(t)
		var item_id := str(item.get("id", ""))
		row.add_child(small_button("Equipaggia", _equip_pick.bind(item_id), "primary", "" if not item_id.is_empty() else "Oggetto non valido"))
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.ornate("card", 10.0))
		card.add_child(row)
		body.add_child(card)

func _forge(recipe_id: String) -> void:
	var result := GS.forge_item(recipe_id)
	main.report(result, "Forgiato", str(result.get("item", {}).get("name", "")))

func _equip_pick(item_id: String) -> void:
	pick_hero("Chi lo indossa?", GS.get_alive_heroes(), _equip.bind(item_id))

func _equip(hero_id: String, item_id: String) -> void:
	main.report(GS.equip_item(hero_id, item_id), "Equipaggiato", GS.hero_by_id(hero_id).name)

func _build_warehouse(body: VBoxContainer) -> void:
	body.add_child(info_card("Il Magazzino aumenta le scorte massime di ogni materiale (ora %d)." % GS.material_cap()))
	build_materials(body, 2)

func _build_workshop(body: VBoxContainer) -> void:
	body.add_child(info_card("Raffina i materiali grezzi raccolti nella Torre."))
	for recipe_id in GS.WORKSHOP_RECIPES:
		var recipe: Dictionary = GS.WORKSHOP_RECIPES[recipe_id]
		body.add_child(_recipe_card(str(recipe.name), "", recipe.cost, "Produci", _refine.bind(recipe_id), "primary"))

func _refine(recipe_id: String) -> void:
	main.report(GS.refine_material(recipe_id), "Prodotto", str(GS.WORKSHOP_RECIPES[recipe_id].name))

func _build_alchemy(body: VBoxContainer) -> void:
	body.add_child(info_card("Tonici che curano subito le ferite o risollevano il morale."))
	for recipe_id in GS.ALCHEMY_RECIPES:
		var recipe: Dictionary = GS.ALCHEMY_RECIPES[recipe_id]
		body.add_child(_recipe_card(str(recipe.name), str(recipe.description), recipe.cost, "Distilla", _brew_pick.bind(recipe_id), "violet"))

func _brew_pick(recipe_id: String) -> void:
	var candidates := GS.get_alive_heroes()
	if recipe_id == "heal": candidates = candidates.filter(func(h): return not h.injuries.is_empty())
	pick_hero(str(GS.ALCHEMY_RECIPES[recipe_id].name), candidates, _brew.bind(recipe_id))

func _brew(hero_id: String, recipe_id: String) -> void:
	main.report(GS.brew_potion(recipe_id, hero_id), "Tonico somministrato", GS.hero_by_id(hero_id).name)

# =============================================================================
# Roster e memoriale
# =============================================================================

func _card_grid(columns: int = 2) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	return grid

func _build_roster(body: VBoxContainer) -> void:
	var alive := GS.get_alive_heroes()
	alive.sort_custom(func(a, b): return int(a.current_rarity) * 1000 + int(a.level) > int(b.current_rarity) * 1000 + int(b.level))
	var counts := {}
	for hero in alive:
		var a := GS.hero_activity(hero)
		counts[a] = int(counts.get(a, 0)) + 1
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(stat_tile("Squadra", "%d/5" % GS.get_party().filter(func(h): return not h.is_empty()).size(), UIKit.GOLD))
	tiles.add_child(stat_tile("Allenamento", str(counts.get("training", 0)), UIKit.TEAL))
	tiles.add_child(stat_tile("Riposo", str(counts.get("resting", 0)), UIKit.SKY))
	body.add_child(tiles)
	body.add_child(UIKit.button("Apri il roster completo", main.open_roster, "primary", 0))
	body.add_child(UIKit.para("Tocca una carta per aprire la scheda dell'eroe.", 15))
	var grid := _card_grid(2)
	for i in mini(alive.size(), roster_limit):
		var hero: Dictionary = alive[i]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var card: HeroCard = HeroCardScript.new()
		card.setup(hero, 222.0)
		card.pressed.connect(main.open_hero)
		cell.add_child(card)
		var meta := HBoxContainer.new()
		meta.add_theme_constant_override("separation", 6)
		var lv := UIKit.label("%s · Lv.%d" % [GS.role_label(hero.role), int(hero.level)], 14, UIKit.INK_SOFT, UIKit.body_bold())
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta.add_child(lv)
		meta.add_child(activity_pill(hero))
		cell.add_child(meta)
		grid.add_child(cell)
	body.add_child(grid)
	if alive.size() > roster_limit:
		body.add_child(UIKit.button("Mostra altri %d eroi" % (alive.size() - roster_limit), _more_roster, "ghost", 0))
	if not GS.data.memorial.is_empty():
		body.add_child(section("Memoriale", "%d caduti" % GS.data.memorial.size()))
		var memorial := _card_grid(3)
		for record in GS.data.memorial.slice(0, 30):
			memorial.add_child(_memorial_card(record, 144.0))
		body.add_child(memorial)

# =============================================================================
# Roster completo (schermata a griglia densa con filtri)
# =============================================================================

var roster_role := ""
var roster_stars := 0
var roster_state := ""
var roster_sort := "rarity"
var _roster_screen: VBoxContainer

func chip(text: String, selected: bool, callback: Callable) -> Button:
	var b := UIKit.button(text, callback, "primary" if selected else "ghost", 0)
	b.custom_minimum_size.y = 34
	b.add_theme_font_size_override("font_size", 14)
	return b

func build_roster_screen(content: VBoxContainer) -> void:
	_roster_screen = content
	content.add_theme_constant_override("separation", 10)
	var alive := GS.get_alive_heroes()
	var filters := GridContainer.new()
	filters.columns = 2
	filters.add_theme_constant_override("h_separation", 12)
	filters.add_theme_constant_override("v_separation", 6)
	var roles := [["", "Tutti"]]
	for role in GS.ROLES: roles.append([role, GS.role_label(role)])
	var stars := [[0, "Tutte"]]
	for r in range(1, 8): stars.append([r, "%d★" % r])
	var states := [["", "Tutti"], ["idle", "Liberi"], ["party", "In squadra"], ["training", "Allenamento"], ["resting", "Riposo"], ["injured", "Feriti"]]
	var sorts := [["rarity", "Rarità"], ["level", "Livello"], ["power", "Potenza"], ["name", "Nome"]]
	for group in [["RUOLO", roles, roster_role, "role"], ["STELLE", stars, roster_stars, "stars"], ["STATO", states, roster_state, "state"], ["ORDINA", sorts, roster_sort, "sort"]]:
		filters.add_child(UIKit.eyebrow(group[0]))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option in group[1]:
			row.add_child(chip(option[1], option[0] == group[2], _set_roster_filter.bind(group[3], option[0])))
		filters.add_child(row)
	content.add_child(filters)
	var shown := alive.filter(func(h):
		if not roster_role.is_empty() and str(h.role) != roster_role: return false
		if roster_stars > 0 and int(h.current_rarity) != roster_stars: return false
		if not roster_state.is_empty() and GS.hero_activity(h) != roster_state: return false
		return true)
	match roster_sort:
		"level": shown.sort_custom(func(a, b): return int(a.level) > int(b.level))
		"power": shown.sort_custom(func(a, b): return GS.hero_power(a) > GS.hero_power(b))
		"name": shown.sort_custom(func(a, b): return str(a.name) < str(b.name))
		_: shown.sort_custom(func(a, b): return int(a.current_rarity) * 1000 + int(a.level) > int(b.current_rarity) * 1000 + int(b.level))
	content.add_child(UIKit.label("%d eroi su %d" % [shown.size(), alive.size()], 14, UIKit.INK_SOFT, UIKit.body_bold()))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	for hero in shown:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var card: HeroCard = HeroCardScript.new()
		card.setup(hero, 158.0)
		card.pressed.connect(main.open_hero)
		cell.add_child(card)
		var lv := UIKit.label("%s · Lv.%d" % [GS.role_label(hero.role), int(hero.level)], 13, UIKit.INK_SOFT, UIKit.body_bold())
		cell.add_child(lv)
		cell.add_child(activity_pill(hero))
		grid.add_child(cell)
	content.add_child(grid)
	if shown.is_empty(): content.add_child(UIKit.para("Nessun eroe con questi filtri.", 16))

func _set_roster_filter(key: String, value) -> void:
	match key:
		"role": roster_role = value
		"stars": roster_stars = value
		"state": roster_state = value
		"sort": roster_sort = value
	refresh_roster_screen()

func refresh_roster_screen() -> void:
	if not is_instance_valid(_roster_screen): return
	UIKit.clear(_roster_screen)
	build_roster_screen(_roster_screen)

func _memorial_card(record: Dictionary, width: float) -> HeroCard:
	var hero := GS.hero_by_id(str(record.id))
	if hero.is_empty(): hero = {"id": record.id, "name": record.name, "role": record.role, "current_rarity": record.get("rarity", 1), "state": "DEAD"}
	var card: HeroCard = HeroCardScript.new()
	card.setup(hero, width, "Caduto al\nPiano %d" % int(record.floor))
	card.tooltip_text = "%s — %s" % [record.name, record.cause]
	return card

func _more_roster() -> void:
	roster_limit += ROSTER_PAGE * 2
	main._render_panel()

# =============================================================================
# Scheda eroe
# =============================================================================

func build_dossier(content: VBoxContainer, hero: Dictionary, modal_ref: Array) -> void:
	if hero.is_empty():
		content.add_child(UIKit.para("Eroe non più disponibile.", 16))
		return
	content.add_theme_constant_override("separation", 14)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	var card: HeroCard = HeroCardScript.new()
	var caption := ""
	if hero.state != "ALIVE":
		for record in GS.data.memorial:
			if str(record.id) == str(hero.id): caption = "Caduto al\nPiano %d" % int(record.floor)
	card.setup(hero, 250.0, caption)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(card)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 6)
	pills.add_child(UIKit.pill(GS.RARITY_NAMES[int(hero.current_rarity)], UIKit.rarity_color(int(hero.current_rarity))))
	pills.add_child(activity_pill(hero))
	right.add_child(pills)
	right.add_child(UIKit.title("%s · Livello %d / %d" % [GS.role_label(hero.role), int(hero.level), GS.level_cap(hero)], 21, UIKit.INK))
	right.add_child(UIKit.label("%s · ex %s" % [hero.origin, str(hero.profession).to_lower()], 15, UIKit.INK_SOFT, UIKit.body_bold()))
	right.add_child(bars(hero, true))
	right.add_child(UIKit.label("Potenza %s · Missioni %d · Vittorie %d · Abbattimenti %d" % [GS.format_number(GS.hero_power(hero)), int(hero.missions), int(hero.victories), int(hero.kills)], 14, UIKit.MUTED, UIKit.body_bold()))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(stat_tile("Forza", str(hero.stats.str), UIKit.ROSE))
	grid.add_child(stat_tile("Intelletto", str(hero.stats.int), UIKit.VIOLET))
	grid.add_child(stat_tile("Stamina", str(hero.stats.sta), UIKit.TEAL))
	grid.add_child(stat_tile("Agilità", str(hero.stats.agi), UIKit.SKY))
	right.add_child(grid)
	if hero.state == "ALIVE":
		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 8)
		actions.add_theme_constant_override("v_separation", 8)
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
		right.add_child(actions)
	top.add_child(right)
	content.add_child(top)
	var d := GS.derived_stats(hero)
	var derived := PanelContainer.new()
	derived.add_theme_stylebox_override("panel", UIKit.ornate("card", 14.0))
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	dv.add_child(UIKit.label("COMBATTIMENTO", 16, UIKit.GOLD, UIKit.head_font()))
	dv.add_child(UIKit.para("Vita %d · Attacco %.0f · Magia %.0f · Difesa %.0f · Precisione %.0f%% · Schivata %.0f%% · Critico %.0f%%%s" % [d.max_hp, d.attack, d.magic, d.defense, d.accuracy, d.evasion, d.crit, (" · Parata %d" % int(d.block)) if int(d.block) > 0 else (" · Frecce %d" % int(d.ammo)) if int(d.ammo) > 0 else ""], 15, UIKit.INK))
	var eq: Dictionary = hero.equipment
	var accessory: Dictionary = eq.get("accessory", {})
	dv.add_child(UIKit.para("Arma: %s [%s] · Secondaria: %s · Armatura: %s [%s]%s" % [eq.main.get("name", "—"), eq.main.get("grade", "-"), eq.sub.get("name", "—"), eq.armor.get("name", "—"), eq.armor.get("grade", "-"), (" · Amuleto: " + str(accessory.get("name", ""))) if not accessory.is_empty() else ""], 15, UIKit.INK_SOFT))
	var skills := []
	for skill in hero.skills: skills.append("%s Lv.%d" % [GS.skill_label(str(skill.name)), int(skill.level)])
	dv.add_child(UIKit.para("Abilità: " + " · ".join(skills) + "   ·   Tratti: " + ", ".join(hero.traits), 15, UIKit.INK_SOFT))
	if not hero.injuries.is_empty():
		var inj := []
		for injury in hero.injuries: inj.append("%s (%d min di riposo)" % [injury.name, ceili(float(injury.minutes))])
		dv.add_child(UIKit.para("Ferite: " + ", ".join(inj), 15, UIKit.ROSE))
	derived.add_child(dv)
	content.add_child(derived)
	if hero.state == "ALIVE":
		var bonds: Array = GS.hero_bonds(str(hero.id), 4)
		if not bonds.is_empty():
			var bond_panel := PanelContainer.new()
			bond_panel.add_theme_stylebox_override("panel", UIKit.ornate("card", 14.0))
			var bv := VBoxContainer.new()
			bv.add_theme_constant_override("separation", 6)
			bv.add_child(UIKit.label("LEGAMI", 16, UIKit.GOLD, UIKit.head_font()))
			for row in bonds:
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 10)
				var who := UIKit.label(str(row.name), 15, UIKit.INK, UIKit.body_bold())
				who.custom_minimum_size.x = 190
				line.add_child(who)
				var value := int(row.value)
				var tone: Color = UIKit.TEAL if value >= RiftwardState.BOND_FRIEND else UIKit.ROSE if value <= RiftwardState.BOND_RIVAL else UIKit.SKY
				var bar := UIKit.bar(float(value + 100), 200.0, tone, 10.0)
				bar.custom_minimum_size.x = 160
				bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				line.add_child(bar)
				line.add_child(UIKit.label(str(row.label), 14, tone, UIKit.body_bold()))
				bv.add_child(line)
			bv.add_child(UIKit.para("I legami crescono combattendo, allenandosi e riposando insieme. In squadra un amico fidato dà forza e coraggio; perderlo pesa sul morale.", 13, UIKit.MUTED))
			bond_panel.add_child(bv)
			content.add_child(bond_panel)
	var notes := PanelContainer.new()
	notes.add_theme_stylebox_override("panel", UIKit.ornate("system", 16.0))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 4)
	nv.add_child(UIKit.label("VALUTAZIONE DEL SISTEMA", 15, UIKit.LILAC, UIKit.head_font()))
	for line in hero.assessment: nv.add_child(UIKit.para("◆ " + str(line), 15, UIKit.INK))
	for memory in hero.memories.slice(0, 3): nv.add_child(UIKit.para("“%s”" % memory, 15, UIKit.INK_SOFT))
	notes.add_child(nv)
	content.add_child(notes)
	if bool(GS.data.dev.get("reveal_hidden", false)):
		var p: Dictionary = hero.personality
		content.add_child(info_card("Sviluppo · Potenziale %d/100 · Crescita %.2f · Coraggio %d · Disciplina %d · Aggressività %d · Altruismo %d · Compostezza %d · Lealtà %d" % [int(hero.potential), float(hero.growth), int(p.courage), int(p.discipline), int(p.aggression), int(p.altruism), int(p.composure), int(p.loyalty)], "warn"))

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
# Diario, scorte, impostazioni
# =============================================================================

func build_journal(content: VBoxContainer) -> void:
	content.add_theme_constant_override("separation", 8)
	if GS.data.events.is_empty(): content.add_child(UIKit.para("Nessun rapporto per ora.", 16))
	for event in GS.data.events.slice(0, 60):
		var card := PanelContainer.new()
		var color := UIKit.tone_color(str(event.get("tone", "info")))
		card.add_theme_stylebox_override("panel", UIKit.tinted(color, 12.0))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var row := HBoxContainer.new()
		var t := UIKit.label(str(event.title), 17, UIKit.INK, UIKit.head_font())
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		row.add_child(t)
		row.add_child(UIKit.label(_category_label(str(event.category)), 12, color.lightened(0.2), UIKit.head_medium()))
		v.add_child(row)
		v.add_child(UIKit.para(str(event.text), 15))
		card.add_child(v)
		content.add_child(card)
	if not GS.data.memorial.is_empty():
		content.add_child(section("Memoriale", "%d caduti" % GS.data.memorial.size()))
		var grid := _card_grid(5)
		for record in GS.data.memorial.slice(0, 20): grid.add_child(_memorial_card(record, 136.0))
		content.add_child(grid)

func _category_label(category: String) -> String:
	return {"DEATH": "CADUTA", "TRAINING": "ADDESTRAMENTO", "DORMITORIO": "RIPOSO", "SUMMON": "EVOCAZIONE", "MERGE": "FUSIONE", "MISSION": "MISSIONE", "REPORT": "RAPPORTO", "HERO": "EROE", "BASE": "BASE", "SYSTEM": "SISTEMA", "DEV": "SVILUPPO"}.get(category, category)

func build_materials(content: VBoxContainer, columns: int = 3) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for key in GS.MATERIALS:
		var info: Dictionary = GS.MATERIALS[key]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.ornate("card", 12.0))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(UIKit.icon(key, 26))
		head.add_child(UIKit.label(str(info.name).to_upper(), 15, UIKit.GOLD, UIKit.head_font()))
		v.add_child(head)
		v.add_child(UIKit.label("%s / %d" % [GS.display_resource(key), GS.material_cap()], 21, UIKit.INK, UIKit.head_font()))
		v.add_child(UIKit.bar(float(GS.resource_amount(key)), float(GS.material_cap()), UIKit.TEAL, 8))
		card.add_child(v)
		grid.add_child(card)
	content.add_child(grid)
	content.add_child(UIKit.para("I materiali si trovano completando i piani della Torre.", 15))

# --- Negozio -------------------------------------------------------------------

func build_shop(content: VBoxContainer) -> void:
	_shop_screen = content
	content.add_theme_constant_override("separation", 14)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	for key in ["gold", "gems", "stones"]:
		var pill := HBoxContainer.new()
		pill.add_theme_constant_override("separation", 6)
		pill.add_child(UIKit.icon(key, 22))
		pill.add_child(UIKit.label(GS.display_resource(key), 18, UIKit.INK, UIKit.head_font()))
		top.add_child(pill)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var left := GS.shop_refresh_in()
	top.add_child(UIKit.label("NUOVE OFFERTE TRA %dH %02dM" % [left / 3600, (left % 3600) / 60], 13, UIKit.CYAN, UIKit.head_medium()))
	content.add_child(top)
	content.add_child(tabs(GS.SHOP_TABS, shop_tab, _set_shop_tab))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	for offer_id in GS.SHOP_OFFERS:
		if GS.SHOP_OFFERS[offer_id].tab == shop_tab: grid.add_child(_shop_card(offer_id))
	content.add_child(grid)
	content.add_child(UIKit.para("Solo valute di gioco, prezzi e quantità sempre visibili. Nessun oggetto riporta in vita un eroe o protegge dalla morte permanente.", 14, UIKit.MUTED))

func _shop_card(offer_id: String) -> PanelContainer:
	var offer: Dictionary = GS.SHOP_OFFERS[offer_id]
	var color := Color(str(offer.color))
	var remaining := GS.shop_remaining(offer_id)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIKit.tinted(color, 14.0))
	if remaining <= 0: card.modulate = Color(1, 1, 1, 0.55)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var halo := Control.new()
	halo.custom_minimum_size = Vector2(0, 96)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paint := func():
		var c := halo.size * 0.5
		for i in 5: halo.draw_circle(c, 46.0 - i * 5.0, Color(color, 0.05))
		halo.draw_circle(c, 32.0, Color(color, 0.16))
		halo.draw_arc(c, 32.0, 0, TAU, 48, color, 2.0, true)
	halo.draw.connect(paint)
	var icon_center := CenterContainer.new()
	icon_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(UIKit.icon(str(offer.icon), 40))
	halo.add_child(icon_center)
	v.add_child(halo)
	var name_label := UIKit.label(str(offer.name).to_upper(), 15, UIKit.INK, UIKit.head_font())
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)
	var parts := []
	for key in offer.items:
		var label: String = {"gold": "Oro", "gems": "Gemme", "stones": "Pietre"}.get(key, GS.MATERIALS.get(key, {}).get("name", key))
		parts.append("%s ×%s" % [label, GS.format_number(offer.items[key])])
	var items := UIKit.label(" · ".join(parts), 14, color.lightened(0.2), UIKit.body_bold())
	items.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	items.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(items)
	var limit := UIKit.label("Oggi %d/%d" % [remaining, int(offer.limit)], 13, UIKit.MUTED, UIKit.head_medium())
	limit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(limit)
	var price_key: String = offer.price.keys()[0]
	var buy := UIKit.button(("%s %s" % [GS.format_number(offer.price[price_key]), {"gold": "Oro", "gems": "Gemme"}.get(price_key, price_key)]) if remaining > 0 else "Esaurito", _shop_buy.bind(offer_id), "gold" if price_key == "gold" else "violet", 0)
	buy.disabled = remaining <= 0 or not GS.can_afford(offer.price)
	if remaining > 0 and not GS.can_afford(offer.price): buy.tooltip_text = "Non hai abbastanza " + GS.cost_text(offer.price)
	v.add_child(buy)
	card.add_child(v)
	return card

func _set_shop_tab(tab: String) -> void:
	shop_tab = tab
	refresh_shop_screen()

func _shop_buy(offer_id: String) -> void:
	main.report(GS.shop_buy(offer_id), "Acquistato", str(GS.SHOP_OFFERS[offer_id].name))

func refresh_shop_screen() -> void:
	if not is_instance_valid(_shop_screen): return
	UIKit.clear(_shop_screen)
	build_shop(_shop_screen)

func build_settings(content: VBoxContainer) -> void:
	content.add_theme_constant_override("separation", 10)
	content.add_child(UIKit.para("Il salvataggio è locale e si aggiorna da solo, con una copia di sicurezza. Il tempo della base scorre anche a gioco chiuso, fino a 8 ore.", 16))
	content.add_child(section("Luce della base"))
	var lights := HBoxContainer.new()
	lights.add_theme_constant_override("separation", 8)
	for option in [["dusk", "Crepuscolo"], ["day", "Giorno"], ["night", "Notte"]]:
		var lb := UIKit.button(option[1], GS.set_light.bind(option[0]), "primary" if GS.light_preset() == option[0] else "ghost", 0)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lights.add_child(lb)
	content.add_child(lights)
	content.add_child(section("Qualità grafica"))
	var qualities := HBoxContainer.new()
	qualities.add_theme_constant_override("separation", 8)
	for option in [["high", "Alta"], ["medium", "Media"], ["low", "Bassa"]]:
		var qb := UIKit.button(option[1], GS.set_quality.bind(option[0]), "primary" if GS.quality() == option[0] else "ghost", 0)
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qualities.add_child(qb)
	content.add_child(qualities)
	content.add_child(UIKit.para("Alta: ombre morbide, occlusione e luce rimbalzata. Media o Bassa se il gioco rallenta.", 14, UIKit.MUTED))
	var dev_on := bool(GS.data.dev.get("enabled", false))
	content.add_child(section("Modalità sviluppo", "attiva" if dev_on else "spenta"))
	content.add_child(UIKit.para("Risorse infinite e valori nascosti visibili, per provare il gioco velocemente e vedere fin dove arriva. Spegnila per giocare con l'economia reale.", 15))
	content.add_child(UIKit.button("Spegni la modalità sviluppo" if dev_on else "Attiva la modalità sviluppo", GS.set_dev_mode.bind(not dev_on), "ghost" if dev_on else "navy", 0))
	if dev_on:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for entry in [
			["Sblocca tutti i piani (1–100)", GS.dev_unlock_all], ["Completa tutti i piani", GS.dev_clear_all_floors],
			["Base e strutture al massimo", GS.dev_max_base], ["Eroi al livello massimo", GS.dev_max_heroes],
			["Genera eroe 5★", GS.dev_spawn_hero.bind(5)], ["Genera eroe 6★", GS.dev_spawn_hero.bind(6)],
			["Genera eroe 7★", GS.dev_spawn_hero.bind(7)], ["Ripristina il roster", GS.dev_restore_roster],
			["Avanza il tempo di 30 min", _dev_time], ["Avanza il tempo di 8 ore", _dev_time.bind(480)],
		]:
			var b := UIKit.button(entry[0], entry[1], "navy", 0)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(b)
		content.add_child(grid)
	content.add_child(section("Nuovo mondo"))
	content.add_child(UIKit.para("Ricomincia da zero con un nuovo seme. Il salvataggio attuale verrà cancellato.", 15))
	content.add_child(UIKit.button("Crea un nuovo mondo", _confirm_reset, "danger", 0))

func _dev_time(minutes: int = 30) -> void:
	for i in minutes: GS.advance_time(60.0)
	GS.save_and_notify()

func _confirm_reset() -> void:
	main.confirm("Nuovo mondo", "Perderai eroi, base e progressi attuali. Continuare?", "Ricomincia", main.reset_world, "danger")
