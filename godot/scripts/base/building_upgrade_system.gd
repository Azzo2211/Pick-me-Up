extends RefCounted
class_name BuildingUpgradeSystem

func cost_for(data: BaseBuildingData) -> int:
	return data.upgrade_cost * maxi(1, data.level)

func can_upgrade(data: BaseBuildingData) -> bool:
	return data.is_unlocked and not data.state_key.is_empty() and data.level < data.max_level

func upgrade(data: BaseBuildingData) -> Dictionary:
	if not can_upgrade(data):
		return {"ok": false, "message": "Livello massimo o struttura bloccata."}
	var cost := cost_for(data)
	if not GameState._pay("gold", cost, "Upgrade " + data.display_name, "base_upgrade"):
		return {"ok": false, "message": "Oro insufficiente."}
	data.level += 1
	GameState.data.facilities[data.state_key] = data.level
	GameState.add_event("BASE", data.display_name + " potenziato", "La struttura ha raggiunto il livello %d." % data.level, "good")
	GameState.save_game()
	GameState.state_changed.emit()
	return {"ok": true, "level": data.level, "cost": cost}
