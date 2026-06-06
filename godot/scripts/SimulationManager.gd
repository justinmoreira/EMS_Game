extends Node2D

enum LinkState {
	CONNECTING, SUCCESS, FAILED_OUT_OF_RANGE, FAILED_JAMMED, FREQUENCY_DIFF, BANDWIDTH_PENALTY
}

# link_results: Array of {"source": Unit, "target": Unit, "state": int}
# detect_results: Array of {"sensor": Unit, "transceiver": Unit, "detected": bool}
var link_results: Array[Dictionary] = []
var detect_results: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("simulate")


# func _exit_tree() -> void:
# 	clear_all_links()

# func _process(_delta: float) -> void:
# 	_update_active_link_visuals()


func simulate() -> void:
	link_results.clear()
	detect_results.clear()

	_update_all_unit_ranges()

	var transceivers = get_tree().get_nodes_in_group("transceivers")
	var jammers = get_tree().get_nodes_in_group("jammers")
	var sensors = get_tree().get_nodes_in_group("sensors")

	for i in range(transceivers.size()):
		var unit_a = transceivers[i] as Unit
		for j in range(transceivers.size()):
			if i == j:
				continue
			var unit_b = transceivers[j] as Unit
			link_results.append(
				{
					"source": unit_a,
					"target": unit_b,
					"state": calculate_link(unit_a, unit_b, jammers)
				}
			)

	for sensor in sensors:
		for tx in transceivers:
			detect_results.append(
				{"sensor": sensor, "transceiver": tx, "detected": calculate_detection(sensor, tx)}
			)

	GameEvents.simulation_complete.emit(link_results, detect_results)


# tx is the transmitter, rx is the receiver — asymmetric by design.
# Different power/height/bandwidth on each side means A->B != B->A.
func calculate_link(tx: Unit, rx: Unit, jammers: Array) -> int:
	var frequency_diff = abs(tx.frequency - rx.frequency)
	var bw_idx: int = rx.transceiver_bandwidth
	var bandwidth_half = PhysicsEngine.BANDWIDTH_MHZ[bw_idx] / 2.0

	if frequency_diff > bandwidth_half:
		return LinkState.FREQUENCY_DIFF

	var terrain = get_tree().get_first_node_in_group("terrain") as ContourGen
	var tx_uv = terrain.screen_to_world_uv(tx.global_position)
	var rx_uv = terrain.screen_to_world_uv(rx.global_position)
	var tx_px = terrain.world_uv_to_terrain_px(tx_uv)
	var rx_px = terrain.world_uv_to_terrain_px(rx_uv)

	var dist = PhysicsEngine.calculate_distance(tx_px, rx_px)

	var z_tx = terrain.get_unit_total_height(tx)
	var z_rx = terrain.get_unit_total_height(rx)

	# Is the unit out of max possible range?
	# TODO: calculate max range for every unit on sim() and store it
	var tx_max_range = PhysicsEngine.calculate_signal_range(tx.power, z_tx, z_rx, tx.frequency)
	if dist > tx_max_range:
		return LinkState.FAILED_OUT_OF_RANGE

	var terrain_loss = PhysicsEngine.compute_terrain_loss(
		tx_px, rx_px, z_tx, z_rx, terrain.height_grid, terrain.map_origin, terrain.map_scale
	)

	var received_power = PhysicsEngine.calculate_received_power(
		tx.power, z_tx, z_rx, tx.frequency, dist, terrain_loss
	)

	var jammer_descs: Array = []
	for jammer_node in jammers:
		var jam_uv = terrain.screen_to_world_uv(jammer_node.global_position)
		(
			jammer_descs
			. append(
				{
					"terrain_px": terrain.world_uv_to_terrain_px(jam_uv),
					"power": jammer_node.get("power"),
					"frequency": jammer_node.get("frequency"),
					"jammer_bandwidth": jammer_node.get("jammer_bandwidth"),
					"height": jammer_node.get("height"),
				}
			)
		)

	var interference = PhysicsEngine.calculate_interference(
		rx.frequency,
		z_rx,
		rx_px,
		jammer_descs,
		terrain.height_grid,
		terrain.map_origin,
		terrain.map_scale
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
		for unit in get_tree().get_nodes_in_group(group):
			unit.update_ranges()
