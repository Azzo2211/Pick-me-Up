extends SceneTree

## Foto delle carte di alcuni eroi (studio fotografico vero), salvate in una cartella:
## xvfb-run godot --path godot --rendering-driver opengl3 -s res://tests/card_preview_runner.gd -- --test-mode --out DIR [--only guard,villager]

const LookScript := preload("res://scripts/characters/hero_look.gd")
const GeneratorScript := preload("res://scripts/characters/character_generator.gd")
const StudioScript := preload("res://scripts/ui/portrait_studio.gd")
const JOBS := {"guard": "Guardia cittadina", "merchant": "Mercante", "scholar": "Archivista", "villager": "Contadino"}
const ROLES := {"guard": "Guardian", "merchant": "", "scholar": "Mage", "villager": ""}

var state: RiftwardState
var out_dir := "res://tests/captures/cards"
var pending := 0

func _initialize() -> void:
	call_deferred("_run")

func _hero(archetype: String, face: int, hair: String, fem: bool, tag: String) -> Dictionary:
	var job: String = JOBS[archetype]
	var h := state.generate_hero("card-%s-%s" % [archetype, tag], 1)
	h.job = job
	h.commoner = true
	h.class_chosen = false
	h.appearance = GeneratorScript.generate(str(h.id) + ":appearance", str(state.COMMONER_JOBS[job].category))
	h.look = LookScript.generate(str(h.id), archetype, fem, 3, h.appearance)
	h.look.face = face
	h.look.hair = hair
	h.look.age = 22 if face == 0 else (56 if face == 2 and archetype == "scholar" else 31)
	return h

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var oi := args.find("--out")
	if oi >= 0 and oi + 1 < args.size(): out_dir = args[oi + 1]
	var only := []
	var oa := args.find("--only")
	if oa >= 0 and oa + 1 < args.size(): only = args[oa + 1].split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	state = root.get_node("GameState")
	var studio := StudioScript.instance()
	await process_frame
	var list := []
	for archetype in ["guard", "merchant", "scholar", "villager"]:
		if not only.is_empty() and not archetype in only: continue
		var arch: Dictionary = LookScript.ARCHETYPES[archetype]
		for face in 3: list.append([archetype + "_face%d" % face, _hero(archetype, face, str(arch.hair_m[face]), false, "f%d" % face)])
		list.append([archetype + "_hair3", _hero(archetype, 1, str(arch.hair_m[3]), false, "h3")])
		for i in 4: list.append([archetype + "_fem%d" % i, _hero(archetype, i % 3, str(arch.hair_f[i]), true, "w%d" % i)])
	for item in list:
		var hero: Dictionary = item[1]
		var name: String = item[0]
		pending += 1
		var tex = studio.request(hero, func(t): _save(name, t))
		if tex != null: _save(name, tex)
	while pending > 0: await process_frame
	quit()

func _save(name: String, tex: Texture2D) -> void:
	if tex != null: tex.get_image().save_png(out_dir.path_join(name + ".png"))
	pending -= 1
