extends Node2D

enum LinkState {
	CONNECTING, SUCCESS, FAILED_OUT_OF_RANGE, FAILED_JAMMED, FREQUENCY_DIFF, BANDWIDTH_PENALTY
}

# link_results: Array of {"source": Unit, "target": Unit, "state": int}
# detect_results: Array of {"sensor": Unit, "transceiver": Unit, "detected": bool}
var link_results: Array[Dictionary] = []
var detect_results: Array[Dictionary] = []

# These are needed by the newest HUD.gd from main.
# Without these, HUD.gd will crash when toggling link lines or unit ranges.
var links_visible: bool = true
var unit_ranges_visible: bool = true

# Some versions of main store drawn link visuals here.
# Keeping this here makes the tutorial branch compatible with HUD.gd.
var active_links: Dictionary = {}


func _ready() -> void:
	call_deferred("simulate")


func simulate() -> void:
	link_results.clear()
	detect_results.clear()

	_update_all_unit_ranges()

	var transceivers = get_tree().get_nodes_in_group("transceivers")
	var jammers = get_tree().get_nodes_in_group("jammers")
	var sensors = get_tree().get_nodes_in_group("sensors")

	for i in range(transceivers.size()):
		var unit_a = transceivers[i] as Unit

		if unit_a == null:
			continue

		for j in range(transceivers.size()):
			if i == j:
				continue

			var unit_b = transceivers[j] as Unit

			if unit_b == null:
				continue

			link_results.append(
				{
					"source": unit_a,
					"target": unit_b,
					"state": calculate_link(unit_a, unit_b, jammers)
				}
			)

	for sensor_node in sensors:
		var sensor = sensor_node as Unit

		if sensor == null:
			continue

		for tx_node in transceivers:
			var tx = tx_node as Unit

			if tx == null:
				continue

			detect_results.append(
				{"sensor": sensor, "transceiver": tx, "detected": calculate_detection(sensor, tx)}
			)

	_apply_link_visibility()
	_apply_unit_range_visibility()

	GameEvents.simulation_complete.emit(link_results, detect_results)


# tx is the transmitter, rx is the receiver — asymmetric by design.
# Different power/height/bandwidth on each side means A->B != B->A.
func calculate_link(tx: Unit, rx: Unit, jammers: Array) -> int:
	var frequency_diff = abs(tx.frequency - rx.frequency)
	var bw_idx: int = rx.transceiver_bandwidth
	var bandwidth_half = PhysicsEngine.BANDWIDTH_MHZ[bw_idx] / 2.0

	if frequency_diff > bandwidth_half:
		return LinkState.FREQUENCY_DIFF

	var dist = PhysicsEngine.calculate_distance(tx.global_position, rx.global_position)

	var received_power = PhysicsEngine.calculate_received_power(
		tx.power, tx.height, rx.height, tx.frequency, dist
	)

	# Interference is evaluated at the receiver's location and height.
	var interference = PhysicsEngine.calculate_interference(
		rx.frequency, rx.height, rx.global_position, jammers
	)

	var bandwidth_penalty = PhysicsEngine.BANDWIDTH_POWER[bw_idx]

	if !PhysicsEngine.range_check(received_power):
		return LinkState.FAILED_OUT_OF_RANGE

	if PhysicsEngine.bandwidth_penalty_check(received_power, bandwidth_penalty):
		return LinkState.BANDWIDTH_PENALTY

	if !PhysicsEngine.jamming_check(received_power * bandwidth_penalty, interference):
		return LinkState.FAILED_JAMMED

	return LinkState.SUCCESS


func calculate_detection(srx: Unit, tx: Unit) -> bool:
	var dist = PhysicsEngine.calculate_distance(srx.global_position, tx.global_position)
	return PhysicsEngine.is_detected(tx, srx, dist)


func _update_all_unit_ranges() -> void:
	for group in [&"transceivers", &"jammers"]:
		for unit_node in get_tree().get_nodes_in_group(group):
			var unit = unit_node as Unit

			if unit == null:
				continue

			if unit.has_method("update_ranges"):
				unit.update_ranges()


# Called by HUD.gd when the user toggles link lines.
func set_links_visible(value: bool) -> void:
	links_visible = value
	_apply_link_visibility()


# Called by HUD.gd when the user toggles unit ranges.
func set_unit_ranges_visible(value: bool) -> void:
	unit_ranges_visible = value
	_apply_unit_range_visibility()


func _apply_link_visibility() -> void:
	for key in active_links.keys():
		var data = active_links[key]

		if typeof(data) != TYPE_DICTIONARY:
			continue

		var line = data.get("line")
		var arrow = data.get("arrow")

		if is_instance_valid(line):
			line.visible = links_visible

		if is_instance_valid(arrow):
			arrow.visible = links_visible


func _apply_unit_range_visibility() -> void:
	for group in [&"transceivers", &"jammers"]:
		for unit_node in get_tree().get_nodes_in_group(group):
			var unit = unit_node as Unit

			if unit == null:
				continue

			if unit.has_method("update_ranges"):
				unit.update_ranges()

			_set_range_visuals_visible(unit, unit_ranges_visible)


func _set_range_visuals_visible(unit: Unit, visible_value: bool) -> void:
	var possible_range_nodes = [
		"Range",
		"RangeCircle",
		"RangeVisual",
		"RangeArea",
		"DetectionRange",
		"JammingRange",
		"CommunicationRange",
		"LinkRange"
	]

	for node_name in possible_range_nodes:
		var range_node = unit.get_node_or_null(node_name)

		if range_node != null and range_node is CanvasItem:
			range_node.visible = visible_value
