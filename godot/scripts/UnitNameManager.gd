extends Node

# Counters for each unit type
var transceiver_count: int = 0
var jammer_count: int = 0
var sensor_count: int = 0


func get_next_name(unit_type: String) -> String:
	match unit_type.to_lower():
		"transceiver":
			transceiver_count += 1
			return "Transceiver %d" % transceiver_count
		"jammer":
			jammer_count += 1
			return "Jammer %d" % jammer_count
		"sensor":
			sensor_count += 1
			return "Sensor %d" % sensor_count
	return ""


func peek_next_name(unit_type: String) -> String:
	match unit_type.to_lower():
		"transceiver":
			return "Transceiver %d" % (transceiver_count + 1)
		"jammer":
			return "Jammer %d" % (jammer_count + 1)
		"sensor":
			return "Sensor %d" % (sensor_count + 1)
	return ""


func reset() -> void:
	transceiver_count = 0
	jammer_count = 0
	sensor_count = 0
