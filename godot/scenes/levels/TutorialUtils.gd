class_name TutorialUtils
extends Node


static func _is_tutorial_map_unit(unit: Node) -> bool:
	return _is_transceiver(unit) or _is_sensor(unit) or _is_jammer(unit)


static func _is_transceiver(unit: Node) -> bool:
	return _unit_matches(unit, "transceiver", "transceivers")


static func _is_sensor(unit: Node) -> bool:
	return _unit_matches(unit, "sensor", "sensors")


static func _is_jammer(unit: Node) -> bool:
	return _unit_matches(unit, "jammer", "jammers")


static func _unit_matches(unit: Node, name_text: String, group_name: String) -> bool:
	if unit == null:
		return false
	if unit.is_in_group(group_name) or unit.name.to_lower().contains(name_text):
		return true
	if unit is Unit and unit.definition:
		if str(unit.definition.id).to_lower().contains(name_text):
			return true
	for child in unit.get_children():
		if child.name.to_lower().contains(name_text):
			return true
	return false


static func _outside_match_range(value: float) -> bool:
	return abs(value - Tutorial.TUTORIAL_FREQUENCY) > Tutorial.FREQUENCY_TOLERANCE


static func _inside_match_range(value: float) -> bool:
	return abs(value - Tutorial.TUTORIAL_FREQUENCY) <= Tutorial.FREQUENCY_TOLERANCE


static func _get_unit_position(unit: Node) -> Vector2:
	if unit is Node2D or unit is Control:
		return unit.global_position
	var raw_position = unit.get("global_position")
	if raw_position is Vector2:
		return raw_position
	return Vector2(-999999.0, -999999.0)


static func _join_text(parts: Array) -> String:
	var text := ""
	for part in parts:
		text += str(part)
	return text


static func _unit_at_index(units: Array, idx: int) -> Node:
	if idx >= 0 and idx < units.size():
		return units[idx]
	return null


static func _find_node_by_name(root: Node, wanted_name: String) -> Node:
	if root == null:
		return null
	if root.name == wanted_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, wanted_name)
		if found != null:
			return found
	return null


static func _set_number_on_unit(unit: Node, possible_names: Array, new_value: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit is Unit:
		for property_name in possible_names:
			var id := StringName(str(property_name))
			var existing = unit.get_value(id, null)
			if existing != null:
				unit.set_value(id, new_value)
				return
	for property_name in possible_names:
		if unit.get(property_name) != null:
			unit.set(property_name, new_value)
			return
	for child in unit.get_children():
		for property_name in possible_names:
			if child.get(property_name) != null:
				child.set(property_name, new_value)
				return


static func _read_number_from_unit(unit: Node, possible_names: Array, fallback: float) -> float:
	if unit == null or not is_instance_valid(unit):
		return fallback
	if unit is Unit:
		for property_name in possible_names:
			var value = unit.get_value(StringName(str(property_name)), null)
			if value != null:
				return _variant_to_float(value, fallback)
	for property_name in possible_names:
		var direct_value = unit.get(property_name)
		if direct_value != null:
			return _variant_to_float(direct_value, fallback)
	for child in unit.get_children():
		for property_name in possible_names:
			var child_value = child.get(property_name)
			if child_value != null:
				return _variant_to_float(child_value, fallback)
	return fallback


static func _variant_to_float(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	if value is int or value is float:
		return float(value)
	var text := str(value)
	return text.to_float() if text.is_valid_float() else fallback
