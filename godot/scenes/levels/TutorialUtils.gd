class_name TutorialUtils
extends RefCounted

static func is_transceiver(unit: Node) -> bool:
	return unit_matches(unit, "transceiver", "transceivers")

static func is_sensor(unit: Node) -> bool:
	return unit_matches(unit, "sensor", "sensors")

static func is_jammer(unit: Node) -> bool:
	return unit_matches(unit, "jammer", "jammers")

static func unit_matches(unit: Node, name_text: String, group_name: String) -> bool:
	if unit == null:
		return false
	if unit.is_in_group(group_name) or unit.name.to_lower().contains(name_text):
		return true
	if unit.get("definition"):
		if str(unit.get("definition").id).to_lower().contains(name_text):
			return true
	for child in unit.get_children():
		if child.name.to_lower().contains(name_text):
			return true
	return false

static func read_number_from_unit(unit: Node, possible_names: Array, fallback: float) -> float:
	if unit == null or not is_instance_valid(unit):
		return fallback
	if unit.has_method("get_value"):
		for property_name in possible_names:
			var value = unit.get_value(StringName(str(property_name)), null)
			if value != null:
				return variant_to_float(value, fallback)
	for property_name in possible_names:
		var direct_value = unit.get(property_name)
		if direct_value != null:
			return variant_to_float(direct_value, fallback)
	for child in unit.get_children():
		for property_name in possible_names:
			var child_value = child.get(property_name)
			if child_value != null:
				return variant_to_float(child_value, fallback)
	return fallback

static func variant_to_float(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	if value is int or value is float:
		return float(value)
	var text := str(value)
	return text.to_float() if text.is_valid_float() else fallback

static func set_number_on_unit(unit: Node, possible_names: Array, new_value: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit.has_method("set_value"):
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

static func find_node_by_name(root: Node, wanted_name: String) -> Node:
	if root == null:
		return null
	if root.name == wanted_name:
		return root
	for child in root.get_children():
		var found := find_node_by_name(child, wanted_name)
		if found != null:
			return found
	return null

static func remove_sandbox_intro_popups(tree: SceneTree) -> void:
	if tree != null:
		remove_sandbox_intro_popups_recursive(tree.root)

static func remove_sandbox_intro_popups_recursive(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		remove_sandbox_intro_popups_recursive(child)
		if is_sandbox_intro_popup(child):
			child.queue_free()

static func is_sandbox_intro_popup(node: Node) -> bool:
	if node == null:
		return false
	var node_name := node.name.to_lower()
	var scene_path := str(node.scene_file_path).to_lower()
	if node_name.contains("sandbox") and node_name.contains("intro"):
		return true
	if scene_path.contains("sandboxintropopup") or scene_path.contains("sandbox_intro_popup"):
		return true
	var script = node.get_script()
	if script is Resource:
		var script_path := str(script.resource_path).to_lower()
		return script_path.contains("sandbox") and script_path.contains("intro")
	return false

static func get_unit_position(unit: Node) -> Vector2:
	if unit is Node2D or unit is Control:
		return unit.global_position
	var raw_position = unit.get("global_position")
	if raw_position is Vector2:
		return raw_position
	return Vector2(-999999.0, -999999.0)
