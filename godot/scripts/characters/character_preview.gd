extends Control

const Generator := preload("res://scripts/characters/character_generator.gd")
const Portrait := preload("res://scripts/characters/character_portrait.gd")
var grid: GridContainer
var round_index := 0

func _ready() -> void:
    var bg := ColorRect.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.color = Color("#171a27")
    add_child(bg)

    var layout := VBoxContainer.new()
    layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layout.add_theme_constant_override("separation", 12)
    add_child(layout)
    var header := HBoxContainer.new()
    layout.add_child(header)
    var title := Label.new()
    title.text = "RIFTWARD // 16 CATEGORIE - GENERATORE PERSONAGGI"
    title.add_theme_font_size_override("font_size", 21)
    header.add_child(title)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(spacer)
    var reroll := Button.new()
    reroll.text = "GENERA NUOVI 16"
    reroll.pressed.connect(_populate)
    header.add_child(reroll)
    var desc := Label.new()
    desc.text = "Aspetto indipendente da statistiche e rarita. Occhi rossi: 0,001% (1/100.000)."
    desc.add_theme_font_size_override("font_size", 14)
    layout.add_child(desc)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layout.add_child(scroll)
    grid = GridContainer.new()
    grid.columns = 4
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 12)
    scroll.add_child(grid)
    _populate()

func _populate() -> void:
    if grid == null: return
    for child in grid.get_children():
        child.queue_free()
    round_index += 1
    for category in Generator.CATEGORIES:
        var appearance: Dictionary = Generator.generate("preview_%s_%d" % [category, round_index], str(category))
        var panel := PanelContainer.new()
        panel.custom_minimum_size = Vector2(257, 334)
        grid.add_child(panel)
        var box := VBoxContainer.new()
        panel.add_child(box)
        var heading := Label.new()
        heading.text = str(category).to_upper()
        heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        heading.add_theme_font_size_override("font_size", 16)
        box.add_child(heading)
        var portrait := Portrait.new()
        portrait.custom_minimum_size = Vector2(240, 240)
        portrait.set_appearance(appearance)
        box.add_child(portrait)
        var line := Label.new()
        line.text = "%s / %s / %s" % [appearance.face_style, appearance.body_type, appearance.hair_style]
        line.add_theme_font_size_override("font_size", 11)
        line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        box.add_child(line)
        var eyes := Label.new()
        eyes.text = "Capelli: %s   Occhi: %s" % [appearance.hair_color, appearance.eye_color]
        eyes.add_theme_font_size_override("font_size", 12)
        eyes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        box.add_child(eyes)
