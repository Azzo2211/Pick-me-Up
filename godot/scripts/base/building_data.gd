extends Resource
class_name BaseBuildingData

@export var id := ""
@export var building_type := ""
@export var state_key := ""
@export var display_name := ""
@export_multiline var description := ""
@export var level := 1
@export var max_level := 4
@export var world_position := Vector2.ZERO
@export var is_unlocked := true
@export var interaction_type := ""
@export var secondary_interaction_type := ""
@export var secondary_label := ""
@export var upgrade_cost := 0
@export var upgrade_time := 0.0
@export var visual_variant := "default"
@export var activity_slots: Array[Vector2] = []
@export var navigation_path: Array[Vector2] = []
@export var footprint := Vector2(230, 170)

static func create(config: Dictionary) -> BaseBuildingData:
	var data := BaseBuildingData.new()
	data.id = str(config.get("id", "building"))
	data.building_type = str(config.get("building_type", data.id))
	data.state_key = str(config.get("state_key", ""))
	data.display_name = str(config.get("display_name", data.id.capitalize()))
	data.description = str(config.get("description", ""))
	data.level = int(config.get("level", 1))
	data.max_level = int(config.get("max_level", 4))
	data.world_position = config.get("world_position", Vector2.ZERO)
	data.is_unlocked = bool(config.get("is_unlocked", true))
	data.interaction_type = str(config.get("interaction_type", ""))
	data.secondary_interaction_type = str(config.get("secondary_interaction_type", ""))
	data.secondary_label = str(config.get("secondary_label", ""))
	data.upgrade_cost = int(config.get("upgrade_cost", 5000))
	data.upgrade_time = float(config.get("upgrade_time", 0.0))
	data.visual_variant = str(config.get("visual_variant", "default"))
	data.activity_slots.clear()
	for slot in config.get("activity_slots", []):
		data.activity_slots.append(Vector2(slot))
	data.navigation_path.clear()
	for waypoint in config.get("navigation_path", []):
		data.navigation_path.append(Vector2(waypoint))
	data.footprint = config.get("footprint", Vector2(230, 170))
	return data
