extends Node2D

enum LinkState { CONNECTING, SUCCESS, FAILED_OUT_OF_RANGE, FAILED_JAMMED }

const C_SUCCESS := Color.GREEN
const C_CONNECTING := Color.YELLOW
const C_OUT_OF_RANGE := Color.RED
const C_JAMMED := Color.DARK_ORANGE

const LINE_WIDTH := 4.0
const ARROW_SIZE := 14.0
const LINE_OFFSET := 12.0
const NODE_PADDING := 22.0

# purely visual delay for yellow -> final color
const VISUAL_TRANSITION_DELAY := 0.12

var active_links: Dictionary = {}

# kept for TimerTests.gd compatibility
var timer: Timer

# global show/hide toggle for all links
var links_visible: bool = true


func _ready() -> void:
	setup_timer()
	print("SimulationManager ready")


func _exit_tree() -> void:
	clear_all_links()


func _process(_delta: float) -> void:
	var keys_to_remove: Array[String] = []

	for key in active_links.keys():
		var link_data: Dictionary = active_links[key]
		var source_unit: Node2D = link_data.source
		var target_unit: Node2D = link_data.target

		if not is_instance_valid(source_unit) or not is_instance_valid(target_unit):
			_free_link_nodes(link_data)
			keys_to_remove.append(key)
			continue

		_update_link_geometry(key)
		_apply_visibility_for_key(key)

	for key in keys_to_remove:
		active_links.erase(key)


func setup_timer() -> void:
	if timer != null and is_instance_valid(timer):
		return

	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


func set_transmission_speed(frequency: float) -> void:
	setup_timer()
	timer.wait_time = _frequency_to_delay(frequency)


func send_message(source_unit: Node2D, target_unit: Node2D) -> void:
	print("send_message called")

	if source_unit == null or target_unit == null:
		push_warning("send_message: source_unit or target_unit is null")
		return

	setup_timer()

	timer.start()

	var key := _make_link_key(source_unit, target_unit)
	var version := 1

	if active_links.has(key):
		version = int(active_links[key].get("version", 0)) + 1
	else:
		_create_link(source_unit, target_unit, key)

	var final_state := _evaluate_link_state(source_unit, target_unit)

	active_links[key].source = source_unit
	active_links[key].target = target_unit
	active_links[key].state = LinkState.CONNECTING
	active_links[key].final_state = final_state
	active_links[key].version = version

	_set_link_visual_state(key, LinkState.CONNECTING)
	_update_link_geometry(key)
	_apply_visibility_for_key(key)

	_resolve_link_visual_after_delay(key, version)


func simulate_link(source_unit: Node2D, target_unit: Node2D) -> void:
	send_message(source_unit, target_unit)


func reset_link(source_unit: Node2D, target_unit: Node2D) -> void:
	if source_unit == null or target_unit == null:
		return

	var key := _make_link_key(source_unit, target_unit)
	if not active_links.has(key):
		return

	var link_data: Dictionary = active_links[key]
	_free_link_nodes(link_data)
	active_links.erase(key)


func reset_links_for_unit(unit: Node) -> void:
	if unit == null:
		return

	var keys_to_remove: Array[String] = []

	for key in active_links.keys():
		var link_data: Dictionary = active_links[key]
		if link_data.source == unit or link_data.target == unit:
			_free_link_nodes(link_data)
			keys_to_remove.append(key)

	for key in keys_to_remove:
		active_links.erase(key)


func clear_all_links() -> void:
	for key in active_links.keys():
		_free_link_nodes(active_links[key])
	active_links.clear()


func toggle_all_links() -> void:
	links_visible = !links_visible

	for key in active_links.keys():
		_apply_visibility_for_key(key)

	print("All links visible: ", links_visible)


func set_links_visible(enabled: bool) -> void:
	links_visible = enabled

	for key in active_links.keys():
		_apply_visibility_for_key(key)

	print("All links visible: ", links_visible)


func are_links_visible() -> bool:
	return links_visible


func _create_link(source_unit: Node2D, target_unit: Node2D, key: String) -> void:
	var line := Line2D.new()
	line.width = LINE_WIDTH
	line.default_color = C_CONNECTING
	line.antialiased = true
	line.z_index = 100

	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array(
		[
			Vector2(ARROW_SIZE, 0),
			Vector2(-ARROW_SIZE * 0.65, ARROW_SIZE * 0.45),
			Vector2(-ARROW_SIZE * 0.65, -ARROW_SIZE * 0.45)
		]
	)
	arrow.color = C_CONNECTING
	arrow.z_index = 101

	add_child(line)
	add_child(arrow)

	active_links[key] = {
		"source": source_unit,
		"target": target_unit,
		"line": line,
		"arrow": arrow,
		"state": LinkState.CONNECTING,
		"final_state": LinkState.CONNECTING,
		"version": 1
	}


func _resolve_link_visual_after_delay(key: String, version: int) -> void:
	await get_tree().create_timer(VISUAL_TRANSITION_DELAY).timeout

	if not active_links.has(key):
		return

	var link_data: Dictionary = active_links[key]
	if int(link_data.get("version", -1)) != version:
		return

	_set_link_visual_state(key, int(link_data.final_state))
	_apply_visibility_for_key(key)


func _set_link_visual_state(key: String, state: LinkState) -> void:
	if not active_links.has(key):
		return

	var link_data: Dictionary = active_links[key]
	var line: Line2D = link_data.line
	var arrow: Polygon2D = link_data.arrow

	var color := C_CONNECTING
	match state:
		LinkState.SUCCESS:
			color = C_SUCCESS
		LinkState.FAILED_OUT_OF_RANGE:
			color = C_OUT_OF_RANGE
		LinkState.FAILED_JAMMED:
			color = C_JAMMED
		_:
			color = C_CONNECTING

	if is_instance_valid(line):
		line.default_color = color
	if is_instance_valid(arrow):
		arrow.color = color

	link_data.state = state
	active_links[key] = link_data


func _update_link_geometry(key: String) -> void:
	if not active_links.has(key):
		return

	var link_data: Dictionary = active_links[key]
	var source_unit: Node2D = link_data.source
	var target_unit: Node2D = link_data.target
	var line: Line2D = link_data.line
	var arrow: Polygon2D = link_data.arrow

	if not is_instance_valid(source_unit) or not is_instance_valid(target_unit):
		return
	if not is_instance_valid(line) or not is_instance_valid(arrow):
		return

	var start: Vector2 = source_unit.global_position
	var finish: Vector2 = target_unit.global_position
	var delta: Vector2 = finish - start

	if delta.length() <= 0.001:
		line.points = PackedVector2Array([start, finish])
		arrow.global_position = finish
		return

	var dir: Vector2 = delta.normalized()
	var normal := Vector2(-dir.y, dir.x)

	var line_start := start + dir * NODE_PADDING + normal * LINE_OFFSET
	var line_end := finish - dir * NODE_PADDING + normal * LINE_OFFSET

	line.points = PackedVector2Array([line_start, line_end])

	arrow.global_position = line_end - dir * (ARROW_SIZE * 0.35)
	arrow.rotation = dir.angle()


func _apply_visibility_for_key(key: String) -> void:
	if not active_links.has(key):
		return

	var link_data: Dictionary = active_links[key]
	var line: Line2D = link_data.line
	var arrow: Polygon2D = link_data.arrow

	if is_instance_valid(line):
		line.visible = links_visible
	if is_instance_valid(arrow):
		arrow.visible = links_visible


func _evaluate_link_state(source_unit: Node2D, target_unit: Node2D) -> LinkState:
	if source_unit == null or target_unit == null:
		return LinkState.FAILED_OUT_OF_RANGE

	var tx_power := _get_number(source_unit, ["power", "tx_power", "transmit_power"], 10.0)
	var tx_height := _get_number(source_unit, ["height", "antenna_height"], 1.0)
	var rx_height := _get_number(target_unit, ["height", "antenna_height"], 1.0)
	var frequency := _get_number(source_unit, ["frequency", "freq_mhz"], 300.0)
	var terrain_loss := _get_number(target_unit, ["terrain_loss"], 1.0)

	var distance := PhysicsEngine.calculate_distance(
		source_unit.global_position, target_unit.global_position
	)

	var received_power := PhysicsEngine.calculate_received_power(
		tx_power, tx_height, rx_height, frequency, distance, terrain_loss
	)

	if not PhysicsEngine.range_check(received_power):
		return LinkState.FAILED_OUT_OF_RANGE

	var interference_power := PhysicsEngine.calculate_interference(
		frequency, rx_height, target_unit.global_position, _gather_jammers()
	)

	if not PhysicsEngine.jamming_check(received_power, interference_power):
		return LinkState.FAILED_JAMMED

	return LinkState.SUCCESS


func _gather_jammers() -> Array:
	var jammers: Array = []

	if get_tree() == null:
		return jammers

	for node in get_tree().get_nodes_in_group("jammers"):
		if node is Node2D:
			jammers.append(
				{
					"position": node.global_position,
					"power": _get_number(node, ["power", "tx_power", "jam_power"], 10.0),
					"frequency": _get_number(node, ["frequency", "freq_mhz"], 300.0),
					"bandwidth": _get_string(node, ["bandwidth"], "Wide"),
					"height": _get_number(node, ["height", "antenna_height"], 1.0)
				}
			)

	return jammers


func _get_number(obj: Object, property_names: Array[String], default_value: float) -> float:
	for property_name in property_names:
		var value = obj.get(property_name)
		if value is int or value is float:
			return float(value)
	return default_value


func _get_string(obj: Object, property_names: Array[String], default_value: String) -> String:
	for property_name in property_names:
		var value = obj.get(property_name)
		if value is String and value != "":
			return value
	return default_value


func _make_link_key(source_unit: Node, target_unit: Node) -> String:
	return "%s_to_%s" % [str(source_unit.get_instance_id()), str(target_unit.get_instance_id())]


func _frequency_to_delay(frequency: float) -> float:
	var clamped_frequency := clampf(frequency, 30.0, 3000.0)
	return remap(clamped_frequency, 30.0, 3000.0, 10.0, 0.1)


func _free_link_nodes(link_data: Dictionary) -> void:
	var line: Line2D = link_data.get("line")
	var arrow: Polygon2D = link_data.get("arrow")

	if is_instance_valid(line):
		line.queue_free()
	if is_instance_valid(arrow):
		arrow.queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		toggle_all_links()


func _on_timer_timeout() -> void:
	pass
