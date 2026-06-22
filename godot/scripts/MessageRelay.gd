extends Node

# Listens for Sidebar's send_message intent on a transceiver, computes per-receiver
# arrival delay from the sender's frequency (higher freq → faster), and emits
# `message_dispatched` for each receiver the sender can actually reach. Receivers
# whose link from the sender isn't SUCCESS (out of range, jammed, frequency/
# bandwidth mismatch) are skipped — a message can't traverse a failed link.

const MIN_FREQUENCY := 30.0  # MHz — slowest delivery
const MAX_FREQUENCY := 3000.0  # MHz — fastest delivery
const MAX_DELAY := 10.0  # seconds at MIN_FREQUENCY
const MIN_DELAY := 0.1  # seconds at MAX_FREQUENCY


func _ready() -> void:
	GameEvents.message_send_requested.connect(_on_send_requested)


func _on_send_requested(from_unit: Node) -> void:
	if not (from_unit is Unit):
		return
	var freq: float = float(from_unit.get_value(&"frequency", MIN_FREQUENCY))
	var delay := remap(freq, MIN_FREQUENCY, MAX_FREQUENCY, MAX_DELAY, MIN_DELAY)
	var jammers := get_tree().get_nodes_in_group(&"jammers")
	for to_unit in get_tree().get_nodes_in_group(&"transceivers"):
		if to_unit == from_unit:
			continue
		# Only deliver over a working link (sender → receiver). Out-of-range,
		# jammed, or frequency/bandwidth-mismatched receivers get nothing.
		if (
			SimulationManager.calculate_link(from_unit, to_unit, jammers)
			!= SimulationManager.LinkState.SUCCESS
		):
			continue
		GameEvents.message_dispatched.emit(from_unit, to_unit, delay)
