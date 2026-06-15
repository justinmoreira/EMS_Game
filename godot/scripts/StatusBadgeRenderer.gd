extends Node

# Owns the per-unit UnitStatusVisual lifecycle. Reacts to simulation_complete,
# computes status (jammed/detected), drives the badge.

const STATUS_VISUAL_SCRIPT := preload("res://scripts/UnitStatusVisual.gd")
const STATUS_VISUAL_NODE_NAME := "UnitStatusVisual"


func _ready() -> void:
	GameEvents.simulation_complete.connect(_on_simulation_complete)


func _on_simulation_complete(link_results: Array, detect_results: Array) -> void:
	for group in ["transceivers", "jammers", "sensors"]:
		for unit in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(unit):
				continue
			var visual := _get_or_create_status_visual(unit)
			visual.set_status(_compute_status(unit, link_results, detect_results))


func _get_or_create_status_visual(unit: Node) -> UnitStatusVisual:
	var existing = unit.get_node_or_null(STATUS_VISUAL_NODE_NAME)
	if existing != null:
		return existing as UnitStatusVisual

	var visual := STATUS_VISUAL_SCRIPT.new() as UnitStatusVisual
	visual.name = STATUS_VISUAL_NODE_NAME
	unit.add_child(visual)
	return visual


func _compute_status(unit: Unit, link_results: Array, detect_results: Array) -> int:
	for d in detect_results:
		if d.target == unit and d.detected:
			return UnitStatusVisual.Status.DETECTED

	for r in link_results:
		if r.target == unit and r.state == SimulationManager.LinkState.FAILED_JAMMED:
			return UnitStatusVisual.Status.JAMMED

	if unit.is_in_group("sensors"):
		var is_jammed = false
		var detected_something = false

		for d in detect_results:
			if d.sensor == unit:
				if d.detected and !d.target_type == "jammer":
					detected_something = true
				if d.get("sensor_jammed", false):
					is_jammed = true
					
		if is_jammed and not detected_something:
			return UnitStatusVisual.Status.JAMMED

	return UnitStatusVisual.Status.NONE
