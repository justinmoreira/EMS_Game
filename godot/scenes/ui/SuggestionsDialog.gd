extends PanelContainer

const SUGGESTIONS := {
	SimulationManager.LinkState.FAILED_OUT_OF_RANGE: "Move units closer or add a relay.",
	SimulationManager.LinkState.FAILED_JAMMED: "Change frequency or reposition away from jammer.",
	SimulationManager.LinkState.FREQUENCY_DIFF: "Align both units to the same frequency band.",
	SimulationManager.LinkState.BANDWIDTH_PENALTY: "Reduce concurrent links or upgrade bandwidth.",
}

const STATE_LABELS := {
	SimulationManager.LinkState.SUCCESS: "Connected",
	SimulationManager.LinkState.FAILED_OUT_OF_RANGE: "Out of range",
	SimulationManager.LinkState.FAILED_JAMMED: "Jammed",
	SimulationManager.LinkState.FREQUENCY_DIFF: "Frequency mismatch",
	SimulationManager.LinkState.BANDWIDTH_PENALTY: "Bandwidth limited",
}

@onready var title_label: Label = $VBox/TitleLabel
@onready var content_label: Label = $VBox/ContentLabel

var suggestions_toggled: bool = false
var _selected_unit: Unit = null


func _ready() -> void:
	GameEvents.selection_changed.connect(_on_selection_changed)
	GameEvents.simulation_complete.connect(_refresh)
	hide()


func _process(_delta: float) -> void:
	_reposition()


func _on_selection_changed(unit: Node) -> void:
	if unit == null:
		_selected_unit = null
		hide()
		return
	_selected_unit = unit
	_rebuild()
	show()


func _refresh(_link_results = null, _detect = null) -> void:
	if _selected_unit:
		_rebuild()


func _rebuild() -> void:
	title_label.text = _selected_unit.get_value(&"unit_name", "?")

	var links = LinkRenderer.get_links_for_unit(_selected_unit)
	if links.is_empty():
		content_label.text = "No active links."
		return

	var lines := []
	for data in links:
		if data.source != _selected_unit:
			continue

		var other: Node = data.target
		var state: int = data.get("final_state", data.state)
		var name: String = other.get_value(&"unit_name", "?")
		var status: String = STATE_LABELS.get(state, "Unknown")
		var line := "→ %s: %s" % [name, status]
		if SUGGESTIONS.has(state):
			line += "\n" + SUGGESTIONS[state]
		lines.append(line)

	content_label.text = "\n\n".join(lines)


func _reposition() -> void:
	if not _selected_unit:
		return
	var vp := get_viewport()
	var vp_pos := vp.get_canvas_transform() * _selected_unit.global_position
	position = vp_pos + Vector2(40, -20)
	position.x = clamp(position.x, 8, vp.size.x - size.x - 8)
	position.y = clamp(position.y, 8, vp.size.y - size.y - 8)
