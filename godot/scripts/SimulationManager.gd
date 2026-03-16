extends Node

var timer: Timer
var link_results = {}
var detect_results = {}


func _ready():
	setup_timer()
	call_deferred("simulate")


func simulate():
	var transceivers = get_tree().get_nodes_in_group("transceivers")
	var jammers = get_tree().get_nodes_in_group("jammers")
	var sensors = get_tree().get_nodes_in_group("sensors")

	for i in range(transceivers.size()):
		var unit_a = transceivers[i] as Transceiver

		for j in range(i + 1, transceivers.size()):
			var unit_b = transceivers[j] as Transceiver

			var link_a_to_b = calculate_link(unit_a, unit_b, jammers)
			var link_b_to_a = calculate_link(unit_b, unit_a, jammers)

			link_results[unit_a.name + "_to_" + unit_b.name] = link_a_to_b
			link_results[unit_b.name + "_to_" + unit_a.name] = link_b_to_a

	for sensor in sensors:
		for tx in transceivers:
			var detected = calculate_detection(sensor, tx)
			detect_results[sensor.name + "_detects_" + tx.name] = detected


func calculate_link(tx: Transceiver, rx: Transceiver, jammers) -> bool:
	var frequency_diff = abs(tx.frequency - rx.frequency)
	var bw_key = PhysicsEngine.BW_LOOKUP[rx.transceiver_bandwidth]
	var bandwidth_half = PhysicsEngine.BANDWIDTH_VALUES.get(bw_key, 1.0) / 2.0

	if frequency_diff < bandwidth_half:
		var received_power = PhysicsEngine.calculate_received_power(
			tx.power,
			tx.height,
			rx.height,
			tx.frequency,
			PhysicsEngine.calculate_distance(tx.global_position, rx.global_position)
		)
		var interference = PhysicsEngine.calculate_interference(
			rx.frequency, rx.height, rx.global_position, jammers
		)
		var bandwidth_penalty = PhysicsEngine.BANDWIDTH_POWER.get(bw_key, 1.0)
		return PhysicsEngine.jamming_check(received_power * bandwidth_penalty, interference)
	return false


func calculate_detection(sensor, tx) -> bool:
	return PhysicsEngine.is_detected(
		tx.frequency,
		sensor.sensor_bandwidth,
		sensor.sensitivity,
		tx.power,
		tx.height,
		sensor.height,
		PhysicsEngine.calculate_distance(sensor.global_position, tx.global_position)
	)


func setup_timer():
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


func set_transmission_speed(frequency: float) -> void:
	var delay = remap(frequency, 30, 3000, 10.0, 0.1)
	timer.wait_time = delay


func send_message():
	timer.start()


func _on_timer_timeout():
	pass
