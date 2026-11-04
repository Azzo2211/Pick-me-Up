extends RefCounted

## Clip del pacchetto "Riftward Original Motions" (40 animazioni, rig a 19 ossa)
## adattati allo scheletro procedurale di CharacterModel.
## Le ossa del GLB hanno riposo senza rotazione e braccia lungo i fianchi, come
## le articolazioni di CharacterModel: le rotazioni si copiano quasi così come sono.
## Il manichino guarda verso -Z, i nostri personaggi verso +Z: le pose vengono
## specchiate sul piano XY, così la mano destra del clip resta quella che impugna l'arma.

const SOURCE := "res://assets/animations/riftward_original_motions.glb"
const SOURCE_HIP_HEIGHT := 1.08

## Articolazione di CharacterModel → ossa del GLB da comporre (dal genitore al figlio).
const JOINTS := {
	"hips": ["Hips"],
	"spine": ["Spine", "Chest"],
	"head": ["Neck", "Head"],
	"arm_l": ["LeftShoulder", "LeftUpperArm"], "fore_l": ["LeftLowerArm"], "hand_l": ["LeftHand"],
	"arm_r": ["RightShoulder", "RightUpperArm"], "fore_r": ["RightLowerArm"], "hand_r": ["RightHand"],
	"leg_l": ["LeftUpperLeg"], "shin_l": ["LeftLowerLeg"],
	"leg_r": ["RightUpperLeg"], "shin_r": ["RightLowerLeg"],
}
const UPPER := ["spine", "head", "arm_l", "fore_l", "hand_l", "arm_r", "fore_r", "hand_r"]
const LOWER := ["hips", "leg_l", "shin_l", "leg_r", "shin_r"]

static var _loaded := false
static var _anims: Dictionary = {}
static var _tracks: Dictionary = {}

## Carica i clip una sola volta. Falso se il GLB manca: i personaggi usano le pose procedurali.
static func ensure() -> bool:
	if _loaded: return not _anims.is_empty()
	_loaded = true
	var scene: PackedScene = load(SOURCE) as PackedScene if ResourceLoader.exists(SOURCE) else null
	var root: Node = scene.instantiate() if scene != null else _read_gltf()
	if root == null: return false
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player := players[0] as AnimationPlayer
		for clip in player.get_animation_list():
			var animation := player.get_animation(clip)
			var tracks := {}
			for i in animation.get_track_count():
				var bone := str(animation.track_get_path(i)).get_slice(":", 1)
				var type := animation.track_get_type(i)
				if type == Animation.TYPE_ROTATION_3D: tracks[bone] = i
				elif type == Animation.TYPE_POSITION_3D and bone == "Hips": tracks["@hips"] = i
			_anims[str(clip)] = animation
			_tracks[str(clip)] = tracks
	root.free()
	return not _anims.is_empty()

## GLB non ancora importato da Godot (git pull senza aprire l'editor): lo si legge direttamente.
static func _read_gltf() -> Node:
	if not FileAccess.file_exists(SOURCE): return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(SOURCE, state) != OK: return null
	return doc.generate_scene(state)

static func has(clip: String) -> bool:
	return _anims.has(clip)

static func length(clip: String) -> float:
	return (_anims[clip] as Animation).length if _anims.has(clip) else 1.0

static func clip_names() -> Array:
	return _anims.keys()

## Posa del clip al tempo `time`, nello spazio di CharacterModel.
## Restituisce {articolazione: Quaternion} più "@hips": spostamento del bacino in metri del GLB.
static func sample(clip: String, time: float, loop: bool = true) -> Dictionary:
	var pose := {}
	if not _anims.has(clip): return pose
	var animation: Animation = _anims[clip]
	var tracks: Dictionary = _tracks[clip]
	var t := fposmod(time, animation.length) if loop else clampf(time, 0.0, animation.length)
	for joint in JOINTS:
		var q := Quaternion.IDENTITY
		for bone in JOINTS[joint]:
			if tracks.has(bone): q = q * animation.rotation_track_interpolate(tracks[bone], t)
		pose[joint] = Quaternion(-q.x, -q.y, q.z, q.w)
	var offset := Vector3.ZERO
	if tracks.has("@hips"):
		var p := animation.position_track_interpolate(tracks["@hips"], t)
		offset = Vector3(p.x, p.y - SOURCE_HIP_HEIGHT, -p.z)
	pose["@hips"] = offset
	return pose

## Fonde due pose (0 = a, 1 = b).
static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	if a.is_empty() or weight >= 1.0: return b
	if b.is_empty() or weight <= 0.0: return a
	var out := {}
	for key in b:
		if not a.has(key): out[key] = b[key]
		elif key == "@hips": out[key] = (a[key] as Vector3).lerp(b[key], weight)
		else: out[key] = (a[key] as Quaternion).slerp(b[key], weight)
	return out
