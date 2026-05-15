extends Node

const _LS_KEY := "unit_counters"
const _DISPLAY := {"transceiver": "Transceiver", "jammer": "Jammer", "sensor": "Sensor"}

var _counters: Dictionary = {"transceiver": 0, "jammer": 0, "sensor": 0}


func _ready() -> void:
	_load()


func get_next_name(unit_type: String) -> String:
	var key := unit_type.to_lower()
	if not _counters.has(key):
		return ""
	_counters[key] += 1
	_save()
	return "%s %d" % [_DISPLAY[key], _counters[key]]


func peek_next_name(unit_type: String) -> String:
	var key := unit_type.to_lower()
	if not _counters.has(key):
		return ""
	return "%s %d" % [_DISPLAY[key], _counters[key] + 1]


func reset() -> void:
	for k in _counters:
		_counters[k] = 0
	_save()


# Local-only persistence so reload doesn't collide names with prior session.
# Doesn't go through Supabase — cross-device counter sync would need a schema
# migration and isn't worth it; local "no immediate dup" is the actual goal.
func _save() -> void:
	if not OS.has_feature("web"):
		return
	var json := JSON.stringify(_counters)
	JavaScriptBridge.eval("localStorage.setItem('%s', `%s`)" % [_LS_KEY, json])


func _load() -> void:
	if not OS.has_feature("web"):
		return
	var raw = JavaScriptBridge.eval("localStorage.getItem('%s') || ''" % _LS_KEY)
	if not raw is String or raw == "":
		return
	var data = JSON.parse_string(raw)
	if not data is Dictionary:
		return
	for k in _counters:
		if data.has(k):
			_counters[k] = int(data[k])
