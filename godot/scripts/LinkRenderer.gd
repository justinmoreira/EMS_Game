extends Node2D

# Renders Line2D + arrowhead between transceivers based on simulation results.
# Owns its own visual cache (active_links) — drained on reset, auto-purges
# dead refs every frame.

const LINE_WIDTH := 4.0
const ARROW_SIZE := 14.0
const LINE_OFFSET := 12.0
const NODE_PADDING := 22.0
const VISUAL_TRANSITION_DELAY := 0.12

const C_SUCCESS := Color.GREEN
const C_CONNECTING := Color.YELLOW
const C_OUT_OF_RANGE := Color.DARK_ORANGE
const C_JAMMED := Color.RED
const C_FREQUENCY_DIFF := Color.CYAN
const C_BANDWIDTH_PENALTY := Color.MAGENTA

var active_links: Dictionary = {}
var links_visible: bool = true


func _ready() -> void:
	GameEvents.simulation_complete.connect(_on_simulation_complete)
	GameEvents.reset_requested.connect(clear_all)


func _exit_tree() -> void:
	clear_all()


func _process(_delta: float) -> void:
	_update_active_link_visuals()


func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		links_visible = !links_visible
		for k in active_links:
			_apply_visibility_for_key(k)


func _on_simulation_complete(link_results: Array, _detect_results: Array) -> void:
	var current_keys: Dictionary = {}
	for r in link_results:
		var key := _vis_key(r.source, r.target)
		current_keys[key] = true
		_draw_directional_link(r.source, r.target, r.state)
	for active_key in active_links.keys():
		if not current_keys.has(active_key):
			_free_link_nodes(active_links[active_key])
			active_links.erase(active_key)


func clear_all() -> void:
	for key in active_links:
		_free_link_nodes(active_links[key])
	active_links.clear()


func _draw_directional_link(source: Unit, target: Unit, final_state: int) -> void:
	var key = _vis_key(source, target)
	var version = 1

	if active_links.has(key):
		version = int(active_links[key].get("version", 0)) + 1
	else:
		_create_link_nodes(source, target, key)

	var data = active_links[key]
	data["final_state"] = final_state
	data["version"] = version

	_set_link_visual_state(key, SimulationManager.LinkState.CONNECTING)
	_update_link_geometry(key)
	_apply_visibility_for_key(key)
	_resolve_link_visual_after_delay(key, version)


func _create_link_nodes(source: Unit, target: Unit, key: String) -> void:
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
		"state": SimulationManager.LinkState.CONNECTING,
		"version": 1
	}


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


func _set_link_visual_state(key: String, state: int) -> void:
	if not active_links.has(key):
		return
	var data = active_links[key]
	var color = C_CONNECTING
	match state:
		SimulationManager.LinkState.SUCCESS:
			color = C_SUCCESS
		SimulationManager.LinkState.FAILED_OUT_OF_RANGE:
			color = C_OUT_OF_RANGE
		SimulationManager.LinkState.FAILED_JAMMED:
			color = C_JAMMED
		SimulationManager.LinkState.FREQUENCY_DIFF:
			color = C_FREQUENCY_DIFF
		SimulationManager.LinkState.BANDWIDTH_PENALTY:
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


func _vis_key(a: Unit, b: Unit) -> String:
	return str(a.get_instance_id()) + "_to_" + str(b.get_instance_id())


func _free_link_nodes(data: Dictionary) -> void:
	if is_instance_valid(data.get("line")):
		data.line.queue_free()
	if is_instance_valid(data.get("arrow")):
		data.arrow.queue_free()


func _apply_visibility_for_key(key: String) -> void:
	var data = active_links[key]
	if is_instance_valid(data.line):
		data.line.visible = links_visible
	if is_instance_valid(data.arrow):
		data.arrow.visible = links_visible
