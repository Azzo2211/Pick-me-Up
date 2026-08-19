extends RefCounted
class_name BaseNotificationSystem

var states: Dictionary = {}

func refresh_from_game() -> void:
	states.clear()
	states["portal"] = {"active": true, "text": "MISSIONE DISPONIBILE", "tone": "system"}
	states["forge"] = {"active": true, "text": "CRAFTING PRONTO", "tone": "reward"}
	states["alchemy"] = {"active": true, "text": "RICERCA COMPLETATA", "tone": "meta"}
	var tired := GameState.get_alive_heroes().filter(func(hero): return int(hero.fatigue) >= 45).size()
	states["lodgings"] = {"active": tired > 0, "text": "%d EROI DA RECUPERARE" % tired, "tone": "danger"}
	states["training"] = {"active": false, "text": "", "tone": "system"}

func get_state(building_id: String) -> Dictionary:
	return states.get(building_id, {"active": false, "text": "", "tone": "system"})
