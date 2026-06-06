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

var focus_mode: bool = false
var bidirectional_mode: bool = false
var _focused_unit: Unit = null
var _hovered_unit: Unit = null


func _ready() -> void:
	GameEvents.simulation_complete.connect(_on_simulation_complete)
	GameEvents.reset_requested.connect(clear_all)
	GameEvents.links_clear_requested.connect(clear_all)


func _exit_tree() -> void:
	clear_all()


func _process(delta: float) -> void:
	_update_active_link_visuals()
	# Animate the moving-dashed pattern (CONNECTING links scroll their dashes).
	for key in active_links:
		var data = active_links[key]
		if is_instance_valid(data.get("line")):
			data.line.advance_dash(delta)


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
	# PatternedLinkLine draws solid/dashed/moving-dashed/zigzag per link state
	# (via LinkVisuals) instead of a plain Line2D.
	var line = PatternedLinkLine.new()
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

	data.line.set_points(l_start, l_end)
	data.arrow.global_position = l_end - dir * (ARROW_SIZE * 0.3)
	data.arrow.rotation = dir.angle()


func _set_link_visual_state(key: String, state: int) -> void:
	if not active_links.has(key):
		return
	var data = active_links[key]
	# Each state maps to a color AND a line pattern (LinkVisuals): success is a
	# solid green line, connecting scrolls a moving dash, failures use static
	# dashes, and a jam zigzags.
	var color = LinkVisuals.C_CONNECTING
	var pattern = LinkVisuals.LINE_PATTERN_MOVING_DASHED
	match state:
		SimulationManager.LinkState.SUCCESS:
			color = LinkVisuals.C_SUCCESS
			pattern = LinkVisuals.LINE_PATTERN_SOLID
		SimulationManager.LinkState.FAILED_OUT_OF_RANGE:
			color = LinkVisuals.C_OUT_OF_RANGE
			pattern = LinkVisuals.LINE_PATTERN_DASHED
		SimulationManager.LinkState.FAILED_JAMMED:
			color = LinkVisuals.C_JAMMED
			pattern = LinkVisuals.LINE_PATTERN_ZIGZAG
		SimulationManager.LinkState.FREQUENCY_DIFF:
			color = LinkVisuals.C_FREQUENCY_DIFF
			pattern = LinkVisuals.LINE_PATTERN_DASHED
		SimulationManager.LinkState.BANDWIDTH_PENALTY:
			color = LinkVisuals.C_BANDWIDTH_PENALTY
			pattern = LinkVisuals.LINE_PATTERN_DASHED
	if is_instance_valid(data.line):
		data.line.set_visual(color, pattern)
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


func set_focused_unit(unit: Unit) -> void:
	_focused_unit = unit
	_refresh_all_visibility()


func set_hovered_unit(unit: Unit) -> void:
	_hovered_unit = unit
	_refresh_all_visibility()


func _refresh_all_visibility() -> void:
	for key in active_links:
		_apply_visibility_for_key(key)


# Replace the existing _apply_visibility_for_key entirely
func _apply_visibility_for_key(key: String) -> void:
	var data = active_links[key]
	var should_show: bool
	var is_hover_preview := false

	if not links_visible:
		should_show = false
	elif focus_mode:
		var selected = (
			is_instance_valid(_focused_unit)
			and (data.source == _focused_unit or data.target == _focused_unit)
		)
		var hovered = (
			is_instance_valid(_hovered_unit)
			and (data.source == _hovered_unit or data.target == _hovered_unit)
		)
		should_show = selected or hovered
		is_hover_preview = hovered and not selected
	else:
		should_show = true

	var alpha := 0.35 if is_hover_preview else 1.0

	if is_instance_valid(data.line):
		data.line.visible = should_show
		data.line.modulate.a = alpha
	if is_instance_valid(data.arrow):
		data.arrow.visible = should_show
		data.arrow.modulate.a = alpha
