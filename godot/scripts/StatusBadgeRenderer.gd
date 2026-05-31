extends Node

# Owns the per-unit UnitStatusVisual lifecycle. Reacts to simulation_complete,
# computes status (jammed/detected/out-of-range), drives the badge.

const STATUS_VISUAL_SCRIPT := preload("res://scripts/UnitStatusVisual.gd")
const STATUS_VISUAL_NODE_NAME := "UnitStatusVisual"


func _ready() -> void:
	GameEvents.simulation_complete.connect(_on_simulation_complete)


func _on_simulation_complete(link_results: Array, detect_results: Array) -> void:
	for tx in get_tree().get_nodes_in_group("transceivers"):
		if not is_instance_valid(tx):
			continue
		var visual := _get_or_create_status_visual(tx)
		visual.set_status(_compute_status(tx, link_results, detect_results))


func _get_or_create_status_visual(unit: Node) -> UnitStatusVisual:
	var existing = unit.get_node_or_null(STATUS_VISUAL_NODE_NAME)
	if existing != null:
		return existing as UnitStatusVisual

	var visual := STATUS_VISUAL_SCRIPT.new() as UnitStatusVisual
	visual.name = STATUS_VISUAL_NODE_NAME
	unit.add_child(visual)
	return visual


func _compute_status(tx: Unit, link_results: Array, detect_results: Array) -> int:
	var has_out_of_range := false
	# Jammed/out-of-range applies only to the RECEIVER of a failed link.
	for r in link_results:
		if r.target != tx:
			continue
		if r.state == SimulationManager.LinkState.FAILED_JAMMED:
			return UnitStatusVisual.Status.JAMMED
		if r.state == SimulationManager.LinkState.FAILED_OUT_OF_RANGE:
			has_out_of_range = true

	for d in detect_results:
		if d.transceiver == tx and d.detected:
			return UnitStatusVisual.Status.DETECTED

	if has_out_of_range:
		return UnitStatusVisual.Status.OUT_OF_RANGE

	return UnitStatusVisual.Status.NONE
