extends RefCounted
class_name SystemAdvisor

## Consigliere del Sistema: guarda lo stato del gioco e propone consigli.
## Non si chatta: il Sistema osserva e parla da solo (richiesta del proprietario,
## 2026-11-12, #17). Legge soltanto: non cambia mai lo stato del gioco, tranne
## apply_recommended_party(), che il giocatore chiama con un pulsante.
##
## Ogni consiglio è un dizionario:
##   id        chiave stabile (serve per "Nascondi")
##   priority  0–100, più alto = più urgente
##   tone      "danger", "warn", "good" o "info"
##   title     riga breve
##   text      spiegazione con i numeri veri
##   action    dove porta il pulsante: "panel:<struttura>", "squad", "tower",
##             "roster", "journal", "shop", "" (nessun pulsante)
##   button    testo del pulsante

## Suggerimenti generali, mostrati uno alla volta quando non c'è niente di urgente.
const TIPS := [
	"La morte è definitiva: un eroe caduto non torna. Se una battaglia va male, usa l'ordine di ritirata prima di perdere qualcuno.",
	"La stanchezza pesa davvero: da Stanco l'eroe colpisce meno, da Sfinito non può partire. Il Dormitorio la fa scendere nel tempo.",
	"Ogni 5 piani c'è la Prova del Guardiano: regole speciali, campioni d'élite e un guardiano che si infuria a metà vita. Preparati prima di salire.",
	"Guardiani e Avanguardie davanti, Lancieri e Supporti al centro, Ranger o Maghi dietro: fuori ruolo un eroe rende meno.",
	"I Popolani 1★–2★ ti dicono da soli quale classe si adatta a loro: di solito conviene ascoltarli, il morale sale.",
	"Tre eroi della stessa rarità (fino a 4★) si fondono nel Centro di Fusione: il primo sale di una stella e tiene parte delle statistiche degli altri.",
	"Al livello massimo della sua rarità un eroe smette di crescere: serve una promozione con le Pietre.",
	"Ripetere un piano dà meno oro ed esperienza ogni volta: serve per allenarsi, non per arricchirsi.",
	"Le Gemme arrivano a ogni piano vinto, molte di più al primo completamento e alle Prove del Guardiano.",
	"Il Giuramento Astrale garantisce un 5★ entro 100 evocazioni, e dalla 70ª le probabilità salgono.",
	"Nell'Armeria la forgia a mano decide il grado dell'arma: più preciso sei, più alto è il grado (da F a S).",
	"Gli eroi feriti guariscono nel tempo; il Centro Alchemico distilla tonici che accelerano la guarigione.",
	"Il Magazzino alza il limite dei materiali: se le scorte sono piene, i materiali trovati in missione vanno persi.",
	"Il morale conta in battaglia: vittorie, riposo e la classe giusta lo alzano, i compagni caduti lo abbassano.",
	"Nell'Addestramento gli eroi guadagnano esperienza anche quando il gioco è chiuso, fino a 8 ore.",
]

static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")

## Tutti i consigli validi adesso, dal più urgente.
static func advice(gs: Node = null) -> Array:
	if gs == null: gs = _gs()
	var out := []
	_party_advice(gs, out)
	_tower_advice(gs, out)
	_hero_advice(gs, out)
	_base_advice(gs, out)
	_economy_advice(gs, out)
	out.sort_custom(func(a, b): return int(a.priority) > int(b.priority))
	return out

static func _add(out: Array, id: String, priority: int, tone: String, title: String, text: String, action: String = "", button: String = "") -> void:
	out.append({"id": id, "priority": priority, "tone": tone, "title": title, "text": text, "action": action, "button": button})

## Desinenza giusta: un eroe (maschile o femminile) o più eroi ("o"/"a"/"i").
static func _end(heroes: Array, male: String = "o", female: String = "a", plural: String = "i") -> String:
	if heroes.size() != 1: return plural
	return female if RiftwardState.is_feminine(heroes[0]) else male

static func _names(heroes: Array, limit: int = 3) -> String:
	var names := []
	for i in mini(heroes.size(), limit): names.append(str(heroes[i].name))
	var text := ", ".join(names)
	if heroes.size() > limit: text += " e altri %d" % (heroes.size() - limit)
	return text

# -----------------------------------------------------------------------------
# Squadra
# -----------------------------------------------------------------------------

static func _party_advice(gs: Node, out: Array) -> void:
	var party: Array = gs.get_party()
	var members := party.filter(func(h): return not h.is_empty())
	if gs.get_alive_heroes().size() < gs.PARTY_SIZE:
		var status: Dictionary = gs.emergency_recruit_status()
		if bool(status.ok): _add(out, "emergency", 95, "danger", "Servono altri eroi", "Hai meno di 5 eroi vivi. Il Nexus può richiamare gratis una recluta: vai al Cristallo.", "panel:crystal", "Al Cristallo")
		else: _add(out, "emergency_wait", 70, "warn", "Pochi eroi", "Hai meno di 5 eroi vivi. %s, oppure evoca dal Cristallo." % str(status.message), "panel:crystal", "Al Cristallo")
	if members.size() < gs.PARTY_SIZE and gs.get_alive_heroes().size() >= gs.PARTY_SIZE:
		_add(out, "party_incomplete", 85, "warn", "Squadra incompleta", "Ci sono %d posti vuoti su %d. Con «Formazione consigliata» il Sistema sceglie gli eroi migliori per ogni linea." % [gs.PARTY_SIZE - members.size(), gs.PARTY_SIZE], "squad", "Squadra")
	var spent := members.filter(func(h): return float(h.fatigue) >= gs.FATIGUE_NO_DEPLOY)
	if not spent.is_empty():
		_add(out, "party_spent", 92, "danger", "Squadra bloccata", "%s %s sfinit%s e non può partire. Mandal%s al Dormitorio e metti qualcuno di riposato al suo posto." % [_names(spent), "è" if spent.size() == 1 else "sono", _end(spent), _end(spent)], "squad", "Squadra")
	var tired := members.filter(func(h): return float(h.fatigue) >= 40 and float(h.fatigue) < gs.FATIGUE_NO_DEPLOY)
	if not tired.is_empty():
		_add(out, "party_tired", 62, "warn", "Squadra stanca", "%s: %s. Un po' di Dormitorio prima di salire li rimette in forma." % [_names(tired), str(gs.fatigue_penalty_text(tired[0])).to_lower()], "panel:dormitory", "Dormitorio")
	var hurt := members.filter(func(h): return not h.injuries.is_empty())
	if not hurt.is_empty():
		_add(out, "party_injured", 66, "warn", "Feriti in squadra", "%s %s ferit%s: in battaglia rende%s il 15%% in meno e rischia%s di più." % [_names(hurt), "è" if hurt.size() == 1 else "sono", _end(hurt), "" if hurt.size() == 1 else "no", "" if hurt.size() == 1 else "no"], "panel:dormitory", "Dormitorio")
	var wrong := []
	for i in party.size():
		var hero: Dictionary = party[i]
		if hero.is_empty(): continue
		if str(gs.ROLES[hero.role].line) != str(gs.FORMATION_LINES[i]): wrong.append(hero)
	if not wrong.is_empty():
		_add(out, "party_roles", 48, "info", "Eroi fuori ruolo", "%s non %s nella linea giusta. La formazione consigliata li rimette al loro posto." % [_names(wrong), "è" if wrong.size() == 1 else "sono"], "squad", "Squadra")
	# la squadra consigliata è molto più forte di quella attuale?
	var current := 0
	for hero in members: current += int(gs.hero_power(hero))
	var best: Dictionary = recommended_party(gs)
	if members.size() == gs.PARTY_SIZE and int(best.power) > current * 1.15 and spent.is_empty():
		_add(out, "party_better", 55, "info", "Squadra migliore disponibile", "Con gli eroi che hai, la formazione consigliata arriva a forza %d contro %d di adesso (+%d%%)." % [int(best.power), current, roundi((float(best.power) / maxf(1.0, current) - 1.0) * 100.0)], "squad", "Squadra")

## Formazione consigliata: per ogni posto l'eroe più forte della linea giusta,
## lasciando fuori feriti, sfiniti e (se possibile) chi è molto stanco.
static func recommended_party(gs: Node = null) -> Dictionary:
	if gs == null: gs = _gs()
	var pool: Array = gs.get_alive_heroes().filter(func(h): return float(h.fatigue) < gs.FATIGUE_NO_DEPLOY)
	pool.sort_custom(func(a, b): return _fitness(gs, a) > _fitness(gs, b))
	var chosen: Array[String] = []
	var power := 0
	for i in gs.PARTY_SIZE:
		var line := str(gs.FORMATION_LINES[i])
		var pick := {}
		for hero in pool:
			if chosen.has(str(hero.id)): continue
			if str(gs.ROLES[hero.role].line) == line:
				pick = hero
				break
		if pick.is_empty():
			for hero in pool:
				if not chosen.has(str(hero.id)):
					pick = hero
					break
		chosen.append("" if pick.is_empty() else str(pick.id))
		if not pick.is_empty(): power += int(gs.hero_power(pick))
	return {"ids": chosen, "power": power}

## Forza utile per partire: feriti e stanchi valgono meno.
static func _fitness(gs: Node, hero: Dictionary) -> float:
	var value := float(gs.hero_power(hero))
	if not hero.injuries.is_empty(): value *= 0.6
	if float(hero.fatigue) >= 70: value *= 0.7
	return value

static func apply_recommended_party(gs: Node = null) -> Dictionary:
	if gs == null: gs = _gs()
	var best := recommended_party(gs)
	for i in gs.PARTY_SIZE: gs.data.party[i] = best.ids[i] if i < best.ids.size() else ""
	gs.save_and_notify()
	return best

# -----------------------------------------------------------------------------
# Torre
# -----------------------------------------------------------------------------

static func _tower_advice(gs: Node, out: Array) -> void:
	var next_floor := int(gs.data.world.max_floor)
	var record: Dictionary = gs.data.stages.get(str(next_floor), {})
	var cleared := bool(record.get("cleared", false))
	if cleared: return
	var attempts := int(record.get("attempts", 0))
	if gs.is_trial_floor(next_floor):
		# solo se il piano è già stato preparato: leggere non deve creare dati nuovi
		var trial: Dictionary = record.get("descriptor", {}).get("trial", {})
		var rules := []
		for rule in trial.get("rules", []):
			var info: Dictionary = gs.TOWER_TRIALS.get(str(rule), {})
			if not info.is_empty(): rules.append("%s (%s)" % [info.name, info.text])
		var text := "Il Piano %d è una Prova del Guardiano." % next_floor
		if not rules.is_empty(): text += " Regole: " + "; ".join(rules) + "."
		text += " Porta la squadra al completo, riposata e con l'equipaggiamento migliore."
		_add(out, "trial_%d" % next_floor, 60, "warn", "Prova del Guardiano in arrivo", text, "tower", "Torre")
	if attempts >= 2:
		_add(out, "stuck_%d" % next_floor, 72, "warn", "Bloccati al Piano %d" % next_floor, "%d tentativi senza vittoria. Prima di riprovare: allena gli eroi, forgia armi migliori nell'Armeria, oppure ripeti un piano già vinto per fare esperienza." % attempts, "panel:training", "Addestramento")

# -----------------------------------------------------------------------------
# Eroi
# -----------------------------------------------------------------------------

static func _hero_advice(gs: Node, out: Array) -> void:
	var alive: Array = gs.get_alive_heroes()
	var idle := alive.filter(func(h): return gs.hero_activity(h) == "idle")
	# popolani senza classe
	var classless := alive.filter(func(h): return gs.needs_class(h))
	if not classless.is_empty():
		_add(out, "classless", 58, "info", "Popolani senza classe", "%s aspetta%s che tu scelga la classe: finché non ce l'ha%s combatte%s con gli attrezzi del mestiere." % [_names(classless), "" if classless.size() == 1 else "no", "" if classless.size() == 1 else "nno", "" if classless.size() == 1 else "no"], "roster", "Eroi")
	# stanchi che non riposano
	var free_beds: int = gs.dormitory_slots() - gs.assigned_to("dormitory").size()
	# chi è sfinito in squadra ha già il suo avviso ("Squadra bloccata")
	var weary := alive.filter(func(h): return float(h.fatigue) >= 70 and gs.hero_activity(h) in ["idle", "injured", "party"] and not (gs.data.party.has(h.id) and float(h.fatigue) >= gs.FATIGUE_NO_DEPLOY))
	if not weary.is_empty() and free_beds > 0:
		_add(out, "weary", 64, "warn", "Eroi esausti", "%s %s esaust%s e il Dormitorio ha %d %s liber%s." % [_names(weary), "è" if weary.size() == 1 else "sono", _end(weary), free_beds, "letto" if free_beds == 1 else "letti", "o" if free_beds == 1 else "i"], "panel:dormitory", "Dormitorio")
	# feriti fuori dal Dormitorio
	var hurt := alive.filter(func(h): return gs.hero_activity(h) == "injured")
	if not hurt.is_empty() and free_beds > 0 and weary.is_empty():
		_add(out, "injured_rest", 46, "info", "Feriti da curare", "%s guarir%s prima a riposo nel Dormitorio." % [_names(hurt), "à" if hurt.size() == 1 else "anno"], "panel:dormitory", "Dormitorio")
	# addestramento libero
	var free_training: int = gs.training_slots() - gs.assigned_to("training").size()
	var trainable := idle.filter(func(h): return int(h.level) < gs.level_cap(h) and h.injuries.is_empty() and float(h.fatigue) < 60)
	if free_training > 0 and not trainable.is_empty():
		_add(out, "training_free", 52, "good", "Posti liberi in Addestramento", "%d %s liber%s e %s senza niente da fare (%s). Si allena anche a gioco chiuso." % [free_training, "posto" if free_training == 1 else "posti", "o" if free_training == 1 else "i", "un eroe" if trainable.size() == 1 else "%d eroi" % trainable.size(), _names(trainable, 2)], "panel:training", "Addestramento")
	# promozioni pronte
	var promotable := alive.filter(func(h): return bool(gs.promotion_requirements(h).ok))
	if not promotable.is_empty():
		_add(out, "promotion", 68, "good", "Promozione pronta", "%s %s al livello massimo e hai le Pietre per promuover%s di una stella." % [_names(promotable), "è" if promotable.size() == 1 else "sono", "l" + _end(promotable)], "panel:merging", "Fusione")
	else:
		var capped := alive.filter(func(h): return int(h.level) >= gs.level_cap(h) and int(h.current_rarity) < gs.PROMOTION_MAX_RARITY)
		if not capped.is_empty():
			var need: Dictionary = gs.promotion_requirements(capped[0])
			_add(out, "capped", 40, "info", "Eroi al livello massimo", "%s non cresce%s più: per la promozione %s." % [_names(capped), "" if capped.size() == 1 else "no", str(need.message).to_lower()], "panel:merging", "Fusione")
	# fusioni possibili: tre eroi della stessa rarità fuori squadra
	var by_rarity := {}
	for hero in alive:
		if gs.data.party.has(hero.id) or int(hero.current_rarity) >= 5: continue
		var r := int(hero.current_rarity)
		by_rarity[r] = int(by_rarity.get(r, 0)) + 1
	for r in [4, 3, 2, 1]:
		if int(by_rarity.get(r, 0)) >= 3:
			_add(out, "merge_%d" % r, 44, "good", "Fusione possibile", "Hai %d eroi %s fuori squadra: tre di loro possono diventare un %s." % [int(by_rarity[r]), gs.stars(r), gs.stars(r + 1)], "panel:merging", "Fusione")
			break

# -----------------------------------------------------------------------------
# Base
# -----------------------------------------------------------------------------

static func _base_advice(gs: Node, out: Array) -> void:
	if bool(gs.can_upgrade_base().ok):
		var next: Dictionary = gs.next_base_level()
		var island: Dictionary = gs.next_island()
		var extra := " Arriva anche %s (%s)." % [island.name, island.bonus] if not island.is_empty() else ""
		_add(out, "base_up", 74, "good", "Puoi espandere la base", "Hai i requisiti per la Base Lv.%d (%s Oro): le strutture potranno salire di livello.%s" % [int(next.level), gs.format_number(float(next.gold)), extra], "panel:crystal", "Al Cristallo")
	for id in gs.FACILITY_ORDER:
		if gs.facility_available(id) and gs.can_afford({"gold": int(gs.FACILITIES[id].build_cost)}):
			_add(out, "build_" + id, 63, "good", "Nuovo cantiere", "Puoi costruire %s per %s Oro. %s" % [gs.FACILITIES[id].name, gs.format_number(float(gs.FACILITIES[id].build_cost)), gs.FACILITIES[id].description], "panel:" + id, "Vai")
			break
	# il potenziamento più economico che puoi pagare
	var cheapest := ""
	var cheapest_cost := INF
	for id in gs.FACILITY_ORDER:
		if not bool(gs.can_upgrade_facility(id).ok): continue
		var cost := float(gs.facility_upgrade_cost(id).gold)
		if cost < cheapest_cost:
			cheapest_cost = cost
			cheapest = id
	if not cheapest.is_empty():
		_add(out, "upgrade_" + cheapest, 42, "info", "Struttura da potenziare", "%s può salire al Lv.%d per %s Oro: %s" % [gs.FACILITIES[cheapest].name, gs.facility_level(cheapest) + 1, gs.format_number(cheapest_cost), _upgrade_effect(gs, cheapest)], "panel:" + cheapest, "Vai")

static func _upgrade_effect(gs: Node, id: String) -> String:
	match id:
		"training": return "un posto in più e allenamento più veloce."
		"dormitory": return "due letti in più."
		"merging": return "le fusioni conservano più statistiche."
		"warehouse": return "più spazio per i materiali."
		"armory": return "forgia migliore."
	return "la struttura rende di più."

# -----------------------------------------------------------------------------
# Risorse
# -----------------------------------------------------------------------------

static func _economy_advice(gs: Node, out: Array) -> void:
	if gs.is_dev_unlimited(): return
	var high: Dictionary = gs.SUMMON_POOLS.high
	var pity := int(gs.data.pity.get("high", 0))
	var gems := int(gs.resource_amount("gems"))
	if pity >= gs.HIGH_SOFT_PITY and gems >= int(high.cost):
		_add(out, "pity", 57, "good", "Il 5★ è vicino", "Sei a %d evocazioni dal 5★ garantito del Giuramento Astrale e le probabilità sono già più alte." % (gs.HIGH_HARD_PITY - pity), "panel:crystal", "Al Cristallo")
	elif gems >= int(high.cost) * 10:
		_add(out, "gems", 38, "info", "Gemme per un'evocazione x10", "Hai %s Gemme: bastano per 10 evocazioni del Giuramento Astrale (3★–5★)." % gs.format_number(float(gems)), "panel:crystal", "Al Cristallo")
	var cap: int = gs.material_cap()
	var full := []
	for key in gs.MATERIALS:
		if int(gs.resource_amount(key)) >= cap * 0.9: full.append(str(gs.MATERIALS[key].name))
	if not full.is_empty():
		var where := "panel:warehouse" if gs.facility_built("warehouse") else "panel:armory" if gs.facility_built("armory") else ""
		_add(out, "materials_full", 50, "warn", "Scorte quasi piene", "%s %s quasi al limite (%d). Usali nella forgia o alza il Magazzino, altrimenti quelli trovati in missione vanno persi." % [", ".join(full), "è" if full.size() == 1 else "sono", cap], where, "Vai" if not where.is_empty() else "")
	var daily_left := 0
	var shop: Dictionary = gs.data.get("shop", {})
	var bought: Dictionary = shop.get("bought", {}) if int(shop.get("day", -1)) == gs.shop_day() else {}
	for offer_id in gs.SHOP_OFFERS:
		var offer: Dictionary = gs.SHOP_OFFERS[offer_id]
		if str(offer.tab) == "daily" and int(bought.get(offer_id, 0)) < int(offer.limit) and gs.can_afford(offer.price): daily_left += 1
	if daily_left >= 3:
		_add(out, "shop_daily", 24, "info", "Offerte del giorno", "Nel Negozio ci sono %d offerte del giorno ancora disponibili: si rinnovano a mezzanotte." % daily_left, "shop", "Negozio")
	var unread: int = gs.unread_events()
	if unread >= 8:
		_add(out, "journal", 20, "info", "Novità nel Diario", "%d eventi da leggere nel Diario della base." % unread, "journal", "Diario")

## Un suggerimento generale, diverso a seconda dell'ora (cambia da solo).
static func tip(offset: int = 0) -> Dictionary:
	var index := (int(Time.get_unix_time_from_system() / 300.0) + offset) % TIPS.size()
	return {"id": "tip_%d" % index, "priority": 0, "tone": "info", "title": "Lo sapevi?", "text": TIPS[index], "action": "", "button": ""}
