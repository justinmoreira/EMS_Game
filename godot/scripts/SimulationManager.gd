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


func simulate() -> void:
	link_results.clear()
	detect_results.clear()

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

	var dist = PhysicsEngine.calculate_distance(tx.global_position, rx.global_position)

	var received_power = PhysicsEngine.calculate_received_power(
		tx.power, tx.height, rx.height, tx.frequency, dist
	)

	# Interference is evaluated at the receiver's location and height
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
