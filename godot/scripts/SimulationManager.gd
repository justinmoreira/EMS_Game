extends Node2D

enum LinkState {
	CONNECTING, SUCCESS, FAILED_OUT_OF_RANGE, FAILED_JAMMED, FREQUENCY_DIFF, BANDWIDTH_PENALTY
}

# Visual Constants
const C_SUCCESS := Color.GREEN
const C_CONNECTING := Color.YELLOW
const C_OUT_OF_RANGE := Color.DARK_ORANGE
const C_JAMMED := Color.RED
const C_FREQUENCY_DIFF := Color.CYAN
const C_BANDWIDTH_PENALTY := Color.MAGENTA

const LINE_WIDTH := 4.0
const ARROW_SIZE := 14.0
const LINE_OFFSET := 12.0
const NODE_PADDING := 22.0
const VISUAL_TRANSITION_DELAY := 0.12

const STATUS_VISUAL_SCRIPT := preload("res://scripts/UnitStatusVisual.gd")
const STATUS_VISUAL_NODE_NAME := "UnitStatusVisual"

#Data Storage
var active_links: Dictionary = {}
# link_results: Array of {"source": Transceiver, "target": Transceiver, "state": int}
# detect_results: Array of {"sensor": Sensor, "transceiver": Transceiver, "detected": bool}
var link_results: Array[Dictionary] = []
var detect_results: Array[Dictionary] = []
var links_visible: bool = true


func _ready() -> void:
	call_deferred("simulate")


func _exit_tree() -> void:
	clear_all_links()


func _process(_delta: float) -> void:
	_update_active_link_visuals()


func simulate() -> void:
	link_results.clear()
	detect_results.clear()

	var transceivers = get_tree().get_nodes_in_group("transceivers")
	var jammers = get_tree().get_nodes_in_group("jammers")
	var sensors = get_tree().get_nodes_in_group("sensors")

	for i in range(transceivers.size()):
		var unit_a = transceivers[i] as Transceiver
		for j in range(transceivers.size()):
			if i == j:
				continue
			var unit_b = transceivers[j] as Transceiver
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

	_draw_links_from_results()
	_update_unit_status_visuals(transceivers)


# tx is the transmitter, rx is the receiver — asymmetric by design.
# Different power/height/bandwidth on each side means A->B != B->A.
func calculate_link(tx: Transceiver, rx: Transceiver, jammers: Array) -> int:
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


func calculate_detection(srx: Sensor, tx: Transceiver) -> bool:
	var dist = PhysicsEngine.calculate_distance(srx.global_position, tx.global_position)
	return PhysicsEngine.is_detected(tx, srx, dist)


# Renders one arrow per link_results entry; purges arrows for stale pairs.
func _draw_links_from_results() -> void:
	var current_sim_keys: Dictionary = {}  # set semantics

	for r in link_results:
		var key := _vis_key(r.source, r.target)
		current_sim_keys[key] = true
		_draw_directional_link(r.source, r.target, r.state)

	for active_key in active_links.keys():
		if not current_sim_keys.has(active_key):
			_free_link_nodes(active_links[active_key])
			active_links.erase(active_key)


#Creates or updates the arrow for a single directed link
func _draw_directional_link(source: Transceiver, target: Transceiver, final_state: int) -> void:
	var key = _vis_key(source, target)
	var version = 1

	if active_links.has(key):
		version = int(active_links[key].get("version", 0)) + 1
	else:
		_create_link_nodes(source, target, key)

	var data = active_links[key]
	data["final_state"] = final_state
	data["version"] = version

	_set_link_visual_state(key, LinkState.CONNECTING)
	_update_link_geometry(key)
	_apply_visibility_for_key(key)
	_resolve_link_visual_after_delay(key, version)


# Instantiates the Line2D and arrowhead Polygon2D for a new link entry.
func _create_link_nodes(source: Transceiver, target: Transceiver, key: String) -> void:
	var scene = get_tree().current_scene
	var line = Line2D.new()
	line.width = LINE_WIDTH
	line.antialiased = true
	line.z_index = 100
	scene.add_child(line)

	var arrow = Polygon2D.new()
	arrow.polygon = PackedVector2Array(
		[
			Vector2(ARROW_SIZE, 0),
			Vector2(-ARROW_SIZE * 0.65, ARROW_SIZE * 0.45),
			Vector2(-ARROW_SIZE * 0.65, -ARROW_SIZE * 0.45)
		]
	)
	arrow.z_index = 101
	scene.add_child(arrow)

	active_links[key] = {
		"source": source,
		"target": target,
		"line": line,
		"arrow": arrow,
		"state": LinkState.CONNECTING,
		"version": 1
	}


#Recalculates the screen-space positions of a link's line and arrowhead.
func _update_link_geometry(key: String) -> void:
	var data = active_links[key]
	if not is_instance_valid(data.source) or not is_instance_valid(data.target):
		return

	var start: Vector2 = data.source.global_position
	var end: Vector2 = data.target.global_position
	var delta = end - start
	if delta.length() < 0.1:
		return

	var dir = delta.normalized()
	var normal = Vector2(-dir.y, dir.x)

	var l_start = start + (dir * NODE_PADDING) + (normal * LINE_OFFSET)
	var l_end = end - (dir * NODE_PADDING) + (normal * LINE_OFFSET)

	data.line.points = PackedVector2Array([l_start, l_end])
	data.arrow.global_position = l_end - dir * (ARROW_SIZE * 0.3)
	data.arrow.rotation = dir.angle()


# Applies the color for a given LinkState to a link's line and arrowhead.
func _set_link_visual_state(key: String, state: int) -> void:
	if not active_links.has(key):
		return
	var data = active_links[key]
	var color = C_CONNECTING
	match state:
		LinkState.SUCCESS:
			color = C_SUCCESS
		LinkState.FAILED_OUT_OF_RANGE:
			color = C_OUT_OF_RANGE
		LinkState.FAILED_JAMMED:
			color = C_JAMMED
		LinkState.FREQUENCY_DIFF:
			color = C_FREQUENCY_DIFF
		LinkState.BANDWIDTH_PENALTY:
			color = C_BANDWIDTH_PENALTY
	if is_instance_valid(data.line):
		data.line.default_color = color
	if is_instance_valid(data.arrow):
		data.arrow.color = color
	data["state"] = state


func _resolve_link_visual_after_delay(key: String, version: int) -> void:
	await get_tree().create_timer(VISUAL_TRANSITION_DELAY).timeout
	if active_links.has(key) and active_links[key].version == version:
		_set_link_visual_state(key, active_links[key].final_state)


# Called every frame. Updates geometry for all active links
func _update_active_link_visuals() -> void:
	var dead_keys = []
	for key in active_links.keys():
		var data = active_links[key]
		if not is_instance_valid(data.source) or not is_instance_valid(data.target):
			dead_keys.append(key)
			continue
		_update_link_geometry(key)
	for k in dead_keys:
		_free_link_nodes(active_links[k])
		active_links.erase(k)


func _update_unit_status_visuals(transceivers: Array) -> void:
	for tx in transceivers:
		if !is_instance_valid(tx):
			continue

		var visual := _get_or_create_status_visual(tx)
		var status := _compute_status_for_transceiver(tx)
		visual.set_status(status)


func _get_or_create_status_visual(unit: Node) -> UnitStatusVisual:
	var existing = unit.get_node_or_null(STATUS_VISUAL_NODE_NAME)
	if existing != null:
		return existing as UnitStatusVisual

	var visual := STATUS_VISUAL_SCRIPT.new() as UnitStatusVisual
	visual.name = STATUS_VISUAL_NODE_NAME
	unit.add_child(visual)
	return visual


func _compute_status_for_transceiver(tx: Transceiver) -> int:
	var has_out_of_range := false

	# Jammed/out-of-range applies only to the RECEIVER of a failed link.
	for r in link_results:
		if r.target != tx:
			continue
		if r.state == LinkState.FAILED_JAMMED:
			return UnitStatusVisual.Status.JAMMED
		if r.state == LinkState.FAILED_OUT_OF_RANGE:
			has_out_of_range = true

	for d in detect_results:
		if d.transceiver == tx and d.detected:
			return UnitStatusVisual.Status.DETECTED

	if has_out_of_range:
		return UnitStatusVisual.Status.OUT_OF_RANGE

	return UnitStatusVisual.Status.NONE


func _vis_key(a: Transceiver, b: Transceiver) -> String:
	return str(a.get_instance_id()) + "_to_" + str(b.get_instance_id())


func _free_link_nodes(data: Dictionary) -> void:
	if is_instance_valid(data.get("line")):
		data.line.queue_free()
	if is_instance_valid(data.get("arrow")):
		data.arrow.queue_free()


func clear_all_links() -> void:
	for key in active_links:
		_free_link_nodes(active_links[key])
	active_links.clear()


func _apply_visibility_for_key(key: String) -> void:
	var data = active_links[key]
	if is_instance_valid(data.line):
		data.line.visible = links_visible
	if is_instance_valid(data.arrow):
		data.arrow.visible = links_visible


func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		links_visible = !links_visible
		for k in active_links:
			_apply_visibility_for_key(k)
