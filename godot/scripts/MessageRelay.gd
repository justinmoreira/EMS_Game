extends Node

# Listens for Sidebar's send_message intent on a transceiver, computes per-receiver
# arrival delay from the sender's frequency (higher freq → faster), and emits
# `message_dispatched` for each potential receiver. The renderer animates the
# pulse; physical reception (range/jamming gating) is out of scope for this
# educational demo — every other transceiver "hears" the message at the freq-
# determined delay.

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
	for to_unit in get_tree().get_nodes_in_group(&"transceivers"):
		if to_unit == from_unit:
			continue
		GameEvents.message_dispatched.emit(from_unit, to_unit, delay)
