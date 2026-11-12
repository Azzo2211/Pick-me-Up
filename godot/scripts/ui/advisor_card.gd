extends PanelContainer
class_name AdvisorCard

## Riquadro "Sistema" nella base: mostra un consiglio alla volta (il più urgente
## per primo), con un pulsante che porta dove serve. Si può scorrere, nascondere
## un consiglio o chiudere il riquadro a icona. I consigli li calcola SystemAdvisor.

signal action_requested(action: String)

const WIDTH := 430.0

var items: Array = []
var index := 0
var collapsed := false
## Consigli nascosti dal giocatore: id -> testo. Tornano se il testo cambia.
var dismissed: Dictionary = {}
var _signature := ""
var _body: VBoxContainer
var _pulse := 0.0

func _ready() -> void:
	add_theme_stylebox_override("panel", UIKit.ornate("system", 10.0))
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)

## Ricalcola i consigli; ricostruisce il riquadro solo se qualcosa è cambiato.
func refresh() -> void:
	var list := []
	for item in SystemAdvisor.advice():
		if dismissed.get(item.id, "") == item.text: continue
		list.append(item)
	list.append(SystemAdvisor.tip())
	var signature := ""
	for item in list: signature += str(item.id) + "|" + str(item.text) + ";"
	if signature == _signature: return
	var old_first := "" if items.is_empty() else str(items[0].id)
	var shown_id := "" if items.is_empty() else str(items[clampi(index, 0, items.size() - 1)].id)
	_signature = signature
	items = list
	# resta sul consiglio che stavi leggendo; se ne arriva uno nuovo più urgente, salta a quello
	index = 0
	if str(items[0].id) == old_first:
		for i in items.size():
			if str(items[i].id) == shown_id: index = i
	elif int(items[0].priority) >= 80 and str(items[0].id) != old_first:
		collapsed = false
		_pulse = 1.0
	_build()

func _urgent_count() -> int:
	return items.filter(func(item): return int(item.priority) > 0).size()

func _build() -> void:
	UIKit.clear(_body)
	if items.is_empty(): return
	var item: Dictionary = items[index]
	var tone_color := UIKit.tone_color(str(item.tone)) if int(item.priority) > 0 else UIKit.CYAN
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var eyebrow := UIKit.eyebrow("Sistema · " + ("%d consigli" % _urgent_count() if _urgent_count() != 1 else "1 consiglio") if collapsed else "Sistema · %d/%d" % [index + 1, items.size()], tone_color)
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(eyebrow)
	var toggle := UIKit.button("▸" if collapsed else "–", _toggle, "ghost", 34)
	toggle.custom_minimum_size.y = 26
	toggle.tooltip_text = "Apri i consigli" if collapsed else "Riduci"
	head.add_child(toggle)
	_body.add_child(head)
	custom_minimum_size.x = 230.0 if collapsed else WIDTH
	if collapsed:
		size = Vector2.ZERO
		return
	_body.add_child(UIKit.label(str(item.title), 20, UIKit.INK, UIKit.head_font()))
	var text := UIKit.para(str(item.text), 16, UIKit.INK_SOFT)
	text.custom_minimum_size.x = WIDTH - 24.0
	_body.add_child(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if not str(item.action).is_empty():
		var go := UIKit.button(str(item.button) if not str(item.button).is_empty() else "Vai", _go.bind(str(item.action)), "primary", 0)
		go.custom_minimum_size.y = 32
		row.add_child(go)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if int(item.priority) > 0:
		var hide_button := UIKit.button("Nascondi", _dismiss, "ghost", 0)
		hide_button.custom_minimum_size.y = 32
		row.add_child(hide_button)
	if items.size() > 1:
		for step in [-1, 1]:
			var b := UIKit.button("‹" if step < 0 else "›", _step.bind(step), "ghost", 34)
			b.custom_minimum_size.y = 32
			row.add_child(b)
	_body.add_child(row)
	size = Vector2.ZERO

func _process(delta: float) -> void:
	if _pulse <= 0.0: return
	_pulse = maxf(0.0, _pulse - delta * 0.6)
	modulate = Color.WHITE.lerp(Color(1.35, 1.2, 1.2), sin(_pulse * TAU * 2.0) * 0.5 + 0.5) if _pulse > 0.0 else Color.WHITE

func _toggle() -> void:
	collapsed = not collapsed
	_build()

func _step(direction: int) -> void:
	index = posmod(index + direction, items.size())
	_build()

func _dismiss() -> void:
	var item: Dictionary = items[index]
	dismissed[item.id] = item.text
	_signature = ""
	refresh()

func _go(action: String) -> void:
	action_requested.emit(action)
