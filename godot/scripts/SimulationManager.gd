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
var link_results: Dictionary = {}
var detect_results: Dictionary = {}
var timer: Timer
var links_visible: bool = true
var height_grid: Array = []
var map_origin: Vector2
var map_scale: Vector2
var grid_cols: int
var grid_rows: int


func _ready() -> void:
	setup_timer()
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
			var result = calculate_link(unit_a, unit_b, jammers)
			# Instance ID key drives visuals (always unique)
			link_results[_vis_key(unit_a, unit_b)] = result

	for sensor in sensors:
		for tx in transceivers:
			var detected := calculate_detection(sensor, tx)
			var d_key := str(sensor.get_instance_id()) + "_detects_" + str(tx.get_instance_id())
			detect_results[d_key] = detected

	_draw_links_from_results(transceivers)
	_update_unit_status_visuals(transceivers)


# tx is the transmitter, rx is the receiver — asymmetric by design.
# Different power/height/bandwidth on each side means A->B != B->A.
func calculate_link(tx: Transceiver, rx: Transceiver, jammers: Array) -> int:
	var frequency_diff = abs(tx.frequency - rx.frequency)
	var bw_key = PhysicsEngine.BW_LOOKUP[rx.transceiver_bandwidth]
	var bandwidth_half = PhysicsEngine.BANDWIDTH_VALUES.get(bw_key, 1.0) / 2.0

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

	var bandwidth_penalty = PhysicsEngine.BANDWIDTH_POWER.get(bw_key, 1.0)

	print_max_height_along_link(tx, rx)

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


# Iterates all ordered transceiver pairs and draw arrow pair
func _draw_links_from_results(transceivers: Array) -> void:
	var current_sim_keys = []

	for src_tx in transceivers:
		for tgt_tx in transceivers:
			if src_tx == tgt_tx:
				continue
			var key = _vis_key(src_tx, tgt_tx)
			if link_results.has(key):
				current_sim_keys.append(key)
				_draw_directional_link(src_tx, tgt_tx, link_results[key])

	## Remove any arrows that belong to pairs no longer in the simulation
	var keys_to_purge = []
	for active_key in active_links.keys():
		if not active_key in current_sim_keys:
			keys_to_purge.append(active_key)
	for k in keys_to_purge:
		_free_link_nodes(active_links[k])
		active_links.erase(k)


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
	var tx_id := str(tx.get_instance_id())
	var tx_incoming_suffix := "_to_" + tx_id

	var has_out_of_range := false

	# Jammed/out-of-range should only apply to the RECEIVER of a failed link.
	for key in link_results.keys():
		if !key.ends_with(tx_incoming_suffix):
			continue

		var state: int = link_results[key]

		if state == LinkState.FAILED_JAMMED:
			return UnitStatusVisual.Status.JAMMED

		if state == LinkState.FAILED_OUT_OF_RANGE:
			has_out_of_range = true

	# Sensors detect emitters/transceivers.
	for d_key in detect_results.keys():
		if d_key.ends_with("_detects_" + tx_id) and detect_results[d_key]:
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


func setup_timer():
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


func set_transmission_speed(frequency: float) -> void:
	var delay = remap(frequency, 30.0, 3000.0, 10.0, 0.1)
	timer.wait_time = delay


func send_message():
	timer.start()


func _on_timer_timeout():
	pass


func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		links_visible = !links_visible
		for k in active_links:
			_apply_visibility_for_key(k)


func set_terrain_data(grid: Array, origin: Vector2, map_size: Vector2) -> void:
	height_grid = grid
	grid_cols = grid.size()
	grid_rows = grid[0].size() if grid.size() > 0 else 0
	map_origin = origin

	# Calculate the exact pixel size of each cell
	map_scale.x = map_size.x / float(grid_cols)
	map_scale.y = map_size.y / float(grid_rows)


func print_max_height_along_link(tx: Transceiver, rx: Transceiver) -> void:
	# grid is built as grid[x][y] (x = outer index) in the terrain script.
	if grid_cols == 0 or map_scale.x == 0 or map_scale.y == 0:
		return

	var tx_local = tx.global_position - map_origin
	var rx_local = rx.global_position - map_origin

	# Convert world position → grid cell index.
	# cell_size is in pixels-per-cell, so dividing world px by cell_size gives
	# the column/row index.
	var x0: int = int(tx_local.x / map_scale.x)
	var y0: int = int(tx_local.y / map_scale.y)
	var x1: int = int(rx_local.x / map_scale.x)
	var y1: int = int(rx_local.y / map_scale.y)

	var max_h: float = -INF

	# Bresenham line walk.
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	while true:
		# Bounds-check against the correct axis for each index.
		# grid[x][y]: x must be < grid_cols, y must be < grid_rows.
		if x0 >= 0 and x0 < grid_cols and y0 >= 0 and y0 < grid_rows:
			var h: float = height_grid[x0][y0]
			if h > max_h:
				max_h = h

		if x0 == x1 and y0 == y1:
			break

		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

	# value generated here will eventually be used for terrain interference via fresnel
	# print("Max height between %s -> %s: %.2f m" % [tx.name, rx.name, max_h])
