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


func _live_group(group_name: String) -> Array:
	return get_tree().get_nodes_in_group(group_name).filter(
		func(node): return is_instance_valid(node) and not node.is_queued_for_deletion()
	)


func simulate() -> void:
	link_results.clear()
	detect_results.clear()

	_update_all_unit_ranges()

	var transceivers = _live_group("transceivers")
	var jammers = _live_group("jammers")
	var sensors = _live_group("sensors")
	var terrain = get_tree().get_first_node_in_group("terrain") as ContourGen

	var jammer_descs: Array = []
	for jammer_node in jammers:
		var jammer_px: Vector2
		if terrain != null:
			var jam_uv: Vector2 = (
				jammer_node.get_meta("world_uv")
				if jammer_node.has_meta("world_uv")
				else terrain.screen_to_world_uv(jammer_node.global_position)
			)
			jammer_px = terrain.world_uv_to_terrain_px(jam_uv)
		else:
			jammer_px = jammer_node.global_position
		(
			jammer_descs
			. append(
				{
					"terrain_px": jammer_px,
					"power": jammer_node.get("power"),
					"frequency": jammer_node.get("frequency"),
					"jammer_bandwidth": jammer_node.get("jammer_bandwidth"),
					"height": jammer_node.get("height"),
				}
			)
		)

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
					"state": calculate_link(unit_a, unit_b, jammer_descs)
				}
			)

	for sensor in sensors:
		for tx in transceivers:
			var result = calculate_detection(sensor, tx, jammer_descs)
			detect_results.append(
				{
					"sensor": sensor,
					"target": tx,
					"target_type": "transceiver",
					"detected": result.detected,
					"sensor_jammed": result.jammed
				}
			)
		for tx in jammers:
			var result = calculate_detection(sensor, tx, jammer_descs)
			detect_results.append(
				{
					"sensor": sensor,
					"target": tx,
					"target_type": "jammer",
					"detected": result.detected,
					"sensor_jammed": result.jammed
				}
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
	var tx_px: Vector2
	var rx_px: Vector2
	var z_tx: float
	var z_rx: float
	var tx_uv: Vector2
	var rx_uv: Vector2

	if terrain != null:
		tx_uv = (
			tx.get_meta("world_uv")
			if tx.has_meta("world_uv")
			else terrain.screen_to_world_uv(tx.global_position)
		)
		rx_uv = (
			rx.get_meta("world_uv")
			if rx.has_meta("world_uv")
			else terrain.screen_to_world_uv(rx.global_position)
		)
		tx_px = terrain.world_uv_to_terrain_px(tx_uv)
		rx_px = terrain.world_uv_to_terrain_px(rx_uv)
		z_tx = terrain.get_unit_total_height(tx)
		z_rx = terrain.get_unit_total_height(rx)

	else:
		tx_px = tx.global_position
		rx_px = rx.global_position
		var raw_z_tx = tx.get("height")
		var raw_z_rx = rx.get("height")
		z_tx = float(raw_z_tx if raw_z_tx != null else 0.0)
		z_rx = float(raw_z_rx if raw_z_rx != null else 0.0)

	var dist = PhysicsEngine.calculate_distance(tx_px, rx_px)

	# Is the unit out of max possible range?
	# TODO: calculate max range for every unit on sim() and store it
	var tx_max_range = PhysicsEngine.calculate_signal_range(tx.power, z_tx, z_rx, tx.frequency)
	if dist > tx_max_range:
		return LinkState.FAILED_OUT_OF_RANGE

	var terrain_loss := 1.0
	if terrain != null:
		terrain_loss = PhysicsEngine.compute_terrain_loss(
			tx_px, rx_px, z_tx, z_rx, terrain.height_grid, terrain.map_origin, terrain.map_scale
		)

	var received_power = (
		PhysicsEngine.TRANSCEIVER_BALANCE_RATIO
		* PhysicsEngine.calculate_received_power(
			tx.power, z_tx, z_rx, tx.frequency, dist, terrain_loss
		)
	)

	var interference = PhysicsEngine.calculate_interference(
		rx.frequency,
		z_rx,
		rx_px,
		jammers,
		terrain.height_grid if terrain != null else [],
		terrain.map_origin if terrain != null else Vector2(),
		terrain.map_scale if terrain != null else Vector2()
	)

	var bandwidth_penalty = PhysicsEngine.BANDWIDTH_POWER[bw_idx]

	if !PhysicsEngine.range_check(received_power):
		return LinkState.FAILED_OUT_OF_RANGE
	if PhysicsEngine.bandwidth_penalty_check(received_power, bandwidth_penalty):
		return LinkState.BANDWIDTH_PENALTY
	if !PhysicsEngine.jamming_check(received_power, interference):
		return LinkState.FAILED_JAMMED
	return LinkState.SUCCESS


func calculate_detection(srx: Unit, tx: Unit, jammers: Array) -> Dictionary:
	var terrain = get_tree().get_first_node_in_group("terrain") as ContourGen
	var tx_px: Vector2
	var srx_px: Vector2
	var z_tx: float
	var z_rx: float
	var tx_uv: Vector2
	var srx_uv: Vector2

	if terrain != null:
		tx_uv = (
			tx.get_meta("world_uv")
			if tx.has_meta("world_uv")
			else terrain.screen_to_world_uv(tx.global_position)
		)
		srx_uv = (
			srx.get_meta("world_uv")
			if srx.has_meta("world_uv")
			else terrain.screen_to_world_uv(srx.global_position)
		)
		tx_px = terrain.world_uv_to_terrain_px(tx_uv)
		srx_px = terrain.world_uv_to_terrain_px(srx_uv)
		z_tx = terrain.get_unit_total_height(tx)
		z_rx = terrain.get_unit_total_height(srx)

	else:
		tx_px = tx.global_position
		srx_px = srx.global_position
		var raw_z_tx = tx.get("height")
		var raw_z_rx = srx.get("height")
		z_tx = float(raw_z_tx if raw_z_tx != null else 0.0)
		z_rx = float(raw_z_rx if raw_z_rx != null else 0.0)

	var dist = PhysicsEngine.calculate_distance(srx_px, tx_px)
	var terrain_loss := 1.0
	if terrain != null:
		terrain_loss = PhysicsEngine.compute_terrain_loss(
			tx_px, srx_px, z_tx, z_rx, terrain.height_grid, terrain.map_origin, terrain.map_scale
		)

	var interference = PhysicsEngine.calculate_interference(
		srx.tuning_frequency,
		z_rx,
		srx_px,
		jammers,
		terrain.height_grid if terrain != null else [],
		terrain.map_origin if terrain != null else Vector2(),
		terrain.map_scale if terrain != null else Vector2()
	)

	var is_detected = PhysicsEngine.is_detected(
		tx, srx, dist, terrain_loss, z_tx, z_rx, interference
	)
	var is_jammed = interference > PhysicsEngine.NOISE_FLOOR

	if srx.is_in_group("sensors"):
		print(is_jammed)

	return {"detected": is_detected, "jammed": is_jammed}


func _update_all_unit_ranges() -> void:
	for group in [&"transceivers", &"jammers", &"sensors"]:
		for unit in _live_group(group):
			unit.update_ranges()
