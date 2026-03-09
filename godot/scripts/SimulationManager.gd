extends Node

var timer: Timer


func _ready():
	setup_timer()


func simulate():
	var scene = "HeightMapDemo"
	var path = "/root/%s/Units" % scene

	var transceivers = get_node("%s/Transceivers" % path).get_children()
	var jammers = get_node("%s/Jammers" % path).get_children()
	var sensors = get_node("%s/Sensors" % path).get_children()

	for i in range(transceivers.size()):
		var unit_a = transceivers[i] as Transceiver

		for j in range(i + 1, transceivers.size()):
			var unit_b = transceivers[j] as Transceiver

			var link_a_to_b = calculate_link(unit_a, unit_b, jammers)
			var link_b_to_a = calculate_link(unit_b, unit_a, jammers)


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
