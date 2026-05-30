class_name BaseLevel
extends Control

# Unit attribute controls
const TOGGLE_UNIT_ATTRIBUTES_KEY := KEY_H
const ATTRIBUTE_LABEL_SCRIPT := preload("res://scenes/ui/UnitAttributesLabel.gd")

# definition.id → unit scene to instantiate when reconstructing the level
# from a snapshot. Lookup table for serialize/deserialize_units below.
const _UNIT_SCENES := {
	&"transceiver": preload("res://scenes/core/units/TransceiverUnit.tscn"),
	&"jammer": preload("res://scenes/core/units/JammerUnit.tscn"),
	&"sensor": preload("res://scenes/core/units/SensorUnit.tscn"),
}

# Camera / Viewport State
var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO

# Sidebar layout — populated via signal, no global find_child reach.
# Width is the live x-size of the sidebar; 0 if no sidebar in this scene.
var sidebar_width: float = 0.0

# Selection visual cache — the *previous* selected unit, so we know which to
# unhighlight when selection changes. Source of truth lives on GameEvents.
var _last_highlighted: Unit = null
var unit_attributes_visible: bool = false

@onready var background := $BackgroundTexture

# --- Initialization ---

var _opponent_board_cb: Variant = null


func _ready():
	get_tree().get_root().size_changed.connect(_on_window_resized)
	GameEvents.selection_changed.connect(_on_selection_changed)
	GameEvents.simulation_requested.connect(SimulationManager.simulate)
	GameEvents.reset_requested.connect(_on_reset_requested)
	GameEvents.delete_requested.connect(_on_delete_requested)
	GameEvents.sidebar_resized.connect(_on_sidebar_resized)
	GameEvents.mp_submit_requested.connect(_on_mp_submit_requested)
	_register_mp_receive_hook()
	_on_window_resized()


# Exposes window.godotApplyOpponentBoard so MultiplayerMatch.tsx (which
# subscribes to match_actions INSERTs) can push the opponent's snapshot
# straight into the scene. Stored on `self` to keep the Callable alive —
# JavaScriptBridge.create_callback returns a ref that's GC'd if dropped.
func _register_mp_receive_hook() -> void:
	if not OS.has_feature("web"):
		return
	var window: Variant = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	_opponent_board_cb = JavaScriptBridge.create_callback(_on_js_apply_opponent_board)
	window.godotApplyOpponentBoard = _opponent_board_cb


# JS bridge entry: receives (board_json_string, owner_player_id_string).
func _on_js_apply_opponent_board(args: Array) -> void:
	if args.size() < 2:
		push_warning(
			"[BaseLevel] godotApplyOpponentBoard called with %d args (need 2)" % args.size()
		)
		return
	var json := str(args[0])
	var owner_id := str(args[1])
	if json.is_empty() or owner_id.is_empty():
		return
	var snapshot: Variant = JSON.parse_string(json)
	if not (snapshot is Array):
		push_warning("[BaseLevel] opponent board parse failed or not Array")
		return
	print(
		"[BaseLevel] applying opponent board: ",
		(snapshot as Array).size(),
		" units, owner=",
		owner_id.substr(0, 8)
	)
	apply_opponent_board(snapshot as Array, owner_id)


# Additively applies a remote player's snapshot. Existing units owned by
# the SAME remote player are wiped first (so each opponent submit
# replaces their previous state rather than stacking), but your own
# units (no owner_player_id) are left alone. The unit-color scaffolding
# in Unit._resolve_circle_color reads physical_state.owner_player_id
# and inverts RGB when it doesn't match window.MULTIPLAYER_PLAYER_ID.
func apply_opponent_board(snapshot: Array, owner_id: String) -> void:
	for child in get_children():
		if not (child is Unit):
			continue
		var existing_owner: Variant = (child as Unit).physical_state.get(&"owner_player_id", null)
		if existing_owner is String and (existing_owner as String) == owner_id:
			child.queue_free()
	await get_tree().process_frame

	for entry in snapshot:
		if not (entry is Dictionary):
			continue
		var type_id := StringName(String((entry as Dictionary).get("type", "")))
		var scene: PackedScene = _UNIT_SCENES.get(type_id)
		if scene == null:
			continue
		var state: Dictionary = (entry as Dictionary).get("state", {})
		var world_uv := Vector2.ZERO
		var uv_raw: Variant = state.get("world_uv", null)
		if uv_raw is Dictionary:
			world_uv = Vector2(
				float((uv_raw as Dictionary).get("x", 0.0)),
				float((uv_raw as Dictionary).get("y", 0.0))
			)

		var unit: Unit = scene.instantiate()
		unit.owner = null
		# Seed owner_player_id into physical_state BEFORE add_child so
		# Unit._ready → _spawn_visual → _resolve_circle_color sees the
		# tag on the very first draw and inverts the color. Unit._set
		# only writes pre-existing keys; physical_state is a plain Dict
		# at this stage so direct assignment is the way in.
		unit.physical_state[&"owner_player_id"] = owner_id
		for k in state:
			if String(k) == "world_uv":
				continue
			unit.set(k, state[k])
		add_child(unit)
		unit.set_value(&"world_uv", world_uv)
		unit.global_position = world_uv_to_screen(world_uv)


# Multiplayer SUBMIT: snapshot the current unit layout and ship it to JS,
# which forwards to MultiplayerMatch.tsx's submitMpAction (inserts a row
# in match_actions for the current turn). serialize_units already returns
# the same JSON-friendly shape ScenePersister uses for sandbox autosaves.
func _on_mp_submit_requested() -> void:
	if not OS.has_feature("web"):
		return
	var snapshot := serialize_units()
	# Double-stringify: inner produces the snapshot JSON; outer wraps it
	# as a JS string literal so the eval'd source carries it intact.
	var snapshot_json := JSON.stringify(snapshot)
	var js_arg := JSON.stringify(snapshot_json)
	print(
		"[BaseLevel] MP submit: serialized ",
		snapshot.size(),
		" units, ",
		snapshot_json.length(),
		" bytes"
	)
	JavaScriptBridge.eval("window.mpSubmitBoard(" + js_arg + ")")


func _on_sidebar_resized(width: float) -> void:
	sidebar_width = width
	_on_window_resized()


func _on_window_resized() -> void:
	self.size = get_viewport_rect().size
	if background:
		background.offset_left = sidebar_width
	update_shader()


# --- Coordinate Space Math ---


# Single source of truth: the rectangle the background shader actually renders
# over. Overlays (units, labels) derive their screen positions from the SAME
# rect, so they can never move at a different scale than the terrain.
# `background` is a Control; .position/.size already account for the sidebar
# offset_left set in _on_window_resized.
func _map_origin() -> Vector2:
	return background.position if background else Vector2(sidebar_width, 0)


func get_map_size() -> Vector2:
	return background.size if background else Vector2(size.x - sidebar_width, size.y)


func screen_to_world_uv(screen_pos: Vector2) -> Vector2:
	var map = get_map_size()
	var aspect = map.x / map.y
	var uv = (screen_pos - _map_origin()) / map - Vector2(0.5, 0.5)
	if aspect > 1.0:
		uv.x *= aspect
	else:
		uv.y *= 1.0 / aspect
	return uv * zoom + Vector2(0.5, 0.5) + offset


func world_uv_to_screen(world_uv: Vector2) -> Vector2:
	var map = get_map_size()
	var aspect = map.x / map.y
	var uv = (world_uv - Vector2(0.5, 0.5) - offset) / zoom
	if aspect > 1.0:
		uv.x /= aspect
	else:
		uv.y *= aspect
	return (uv + Vector2(0.5, 0.5)) * map + _map_origin()


# --- Visual Updates ---


func update_shader() -> void:
	if background and background.material:
		var map = get_map_size()
		var aspect = map.x / map.y
		background.material.set_shader_parameter("zoom", zoom)
		background.material.set_shader_parameter("offset", offset)
		background.material.set_shader_parameter("aspect_ratio", aspect)
	_reposition_units()


func toggle_shader(enabled: bool) -> void:
	if background and background.material:
		background.material.set_shader_parameter("sensitivity", 1.0 if enabled else 0.0)


func _reposition_units() -> void:
	var unit_scale = 1.0 / zoom
	for child in get_children():
		if child is Unit and child.get_value(&"world_uv") != null:
			child.position = world_uv_to_screen(child.get_value(&"world_uv"))
			child.scale = Vector2(unit_scale, unit_scale)


func _clamp_offset() -> void:
	var margin := (1.0 - zoom) / 2.0
	offset.x = clamp(offset.x, -margin, margin)
	offset.y = clamp(offset.y, -margin, margin)


# --- Drag and Drop Logic ---


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("scene_path")):
		return false
	if at_position.x < sidebar_width:
		return false
	# The map is world_uv ∈ [0,1]; outside that is the shader's void border.
	# Reject drops there so units can't be placed off the map.
	var world_uv := screen_to_world_uv(at_position)
	if world_uv.x < 0.0 or world_uv.x > 1.0 or world_uv.y < 0.0 or world_uv.y > 1.0:
		return false
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var scene := load(data["scene_path"]) as PackedScene
	if scene == null:
		return

	var unit := scene.instantiate()

	if unit == null:
		return

	# Set position and scale based on current camera zoom/offset
	unit.set_value(&"world_uv", screen_to_world_uv(at_position))
	unit.position = at_position
	unit.scale = Vector2(1.0 / zoom, 1.0 / zoom)
	# Mark this unit as not saved to the scene file (instantiated at runtime).
	unit.owner = null

	# Apply pending attributes BEFORE add_child so the unit's _ready sees the
	# user-typed unit_name and skips its UnitNameManager.get_next_name call.
	# Pending attributes ride along in the drag payload — Sidebar attaches the
	# snapshot via EntityCard. No reach into Sidebar from here.
	var override: Dictionary = data.get("attributes_override", {})
	for attr_name in override:
		unit.set(attr_name, override[attr_name])

	add_child(unit)

	# Auto-sim on place (preserves main's #61 UX via round-8's event-bus pattern).
	GameEvents.simulation_requested.emit()
	_on_unit_placed(unit)
	# Newly-placed unit is treated as selected so its panel opens.
	GameEvents.select(unit)


func _on_unit_placed(unit: Unit) -> void:
	var label = _get_or_create_attribute_label(unit)
	if label:
		label.visible = unit_attributes_visible


# --- Selection Logic (visual highlight only — state lives on GameEvents) ---


func _on_selection_changed(unit: Node) -> void:
	# Single-shot handler covers both new selection and re-selection. Since
	# `selected_unit` is the source of truth, just diff with our last paint.
	if _last_highlighted and _last_highlighted != unit:
		_set_unit_selected_visual(_last_highlighted, false)
	_last_highlighted = unit if unit is Unit else null
	if _last_highlighted:
		_set_unit_selected_visual(_last_highlighted, true)


func _set_unit_selected_visual(unit: Unit, selected: bool) -> void:
	if unit and unit.unit_visual:
		unit.unit_visual.set_selected(selected)


# --- Sidebar button handlers ---


func _on_reset_requested() -> void:
	# LinkRenderer also subscribes to reset_requested and clears its own visuals.
	UnitNameManager.reset()
	for group in [&"transceivers", &"jammers", &"sensors"]:
		for unit in get_tree().get_nodes_in_group(group):
			unit.queue_free()
	GameEvents.clear_selection()


func _on_delete_requested(unit: Node) -> void:
	# LinkRenderer's per-frame purge will drop links involving this unit
	# once is_instance_valid returns false post-queue_free.
	if unit:
		unit.queue_free()
	GameEvents.clear_selection()


# --- Inputs (Camera Control) ---


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.position.x < sidebar_width:
			return

		# Zooming in/out toward the mouse position
		if event.pressed:
			var old_zoom = zoom
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom = clamp(zoom * 0.9, 0.1, 1.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clamp(zoom * 1.1, 0.1, 1.0)
			else:
				return  # Not a zoom event

			# Adjust offset so we zoom toward the mouse position
			var map = get_map_size()
			var mouse_uv = (event.position - Vector2(sidebar_width, 0)) / map - Vector2(0.5, 0.5)
			offset += mouse_uv * (old_zoom - zoom)
			_clamp_offset()
			update_shader()
	return


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return

		if event.keycode == TOGGLE_UNIT_ATTRIBUTES_KEY:
			_toggle_unit_attributes()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.x < sidebar_width:
			return

		if event.pressed:
			# Click on empty map (not on a unit) → deselect.
			if event.position.x > sidebar_width:
				var mouse_pos = get_global_mouse_position()
				var clicked_unit := false
				for child in get_children():
					if (
						child is Unit
						and child.global_position.distance_to(mouse_pos) < Unit.SELECTION_RADIUS
					):
						clicked_unit = true
						break
				# Clicking on a unit hands off to the unit's own drag handler —
				# don't engage map pan or the two thrash each other.
				if clicked_unit:
					return

				GameEvents.clear_selection()
				get_tree().root.set_input_as_handled()

			dragging = true
			last_mouse_pos = event.position

		else:
			dragging = false

	elif event is InputEventMouseMotion and dragging:
		# Map panning
		var delta = (event.position - last_mouse_pos) / get_map_size()
		offset -= delta * zoom
		_clamp_offset()
		last_mouse_pos = event.position
		update_shader()


func toggle_unit_details(enabled: bool) -> void:
	unit_attributes_visible = enabled
	_apply_unit_attribute_visibility()


#show unit attribute helper function
func _toggle_unit_attributes() -> void:
	unit_attributes_visible = not unit_attributes_visible
	_apply_unit_attribute_visibility()


func _apply_unit_attribute_visibility() -> void:
	for child in get_children():
		if child is Unit:
			var label = _get_or_create_attribute_label(child)
			if label:
				label.visible = unit_attributes_visible


func _get_or_create_attribute_label(unit: Unit) -> UnitAttributesLabel:
	var existing = unit.get_node_or_null("UnitAttributesLabel")
	if existing:
		return existing as UnitAttributesLabel
	if unit == null or unit.definition == null:
		return null

	var label := ATTRIBUTE_LABEL_SCRIPT.new()
	label.name = "UnitAttributesLabel"
	unit.add_child(label)
	# Pre-merge, attribute label took (wrapper, component); now they're the same node.
	label.setup(unit, unit)
	label.visible = unit_attributes_visible
	return label


# --- Unit serialization (pure utilities) ---------------------------------
#
# These produce / consume a JSON-friendly snapshot of the level's units.
# They have NO side effects beyond the unit tree itself — no auto-saving,
# no event emission besides the explicit simulation_requested at the end of
# deserialize_units. A persister Node (e.g., ScenePersister.gd) decides
# when/where to call these for any given level.
#
# Snapshot shape:  Array of { "type": StringName id, "state": Dictionary }
# `state` is the unit's physical_state.duplicate(), with any Vector2 entries
# (currently just world_uv) split into {"x", "y"} for JSON friendliness.


func serialize_units() -> Array:
	var out: Array = []
	for child in get_children():
		if not (child is Unit and child.definition):
			continue
		var state: Dictionary = child.physical_state.duplicate()
		var uv = state.get(&"world_uv", null)
		if uv is Vector2:
			state[&"world_uv"] = {"x": uv.x, "y": uv.y}
		out.append({"type": String(child.definition.id), "state": state})
	return out


func deserialize_units(snapshot: Array) -> void:
	# Wipe the current scene before instantiating from the snapshot. queue_free
	# is deferred so we wait a frame before adding the replacements; otherwise
	# the new units race with the doomed ones and units_changed double-fires.
	for group in [&"transceivers", &"jammers", &"sensors"]:
		for u in get_tree().get_nodes_in_group(group):
			u.queue_free()
	await get_tree().process_frame

	for entry in snapshot:
		if not (entry is Dictionary):
			continue
		var type_id := StringName(String(entry.get("type", "")))
		var scene: PackedScene = _UNIT_SCENES.get(type_id)
		if scene == null:
			continue
		var state: Dictionary = entry.get("state", {})
		var world_uv := Vector2.ZERO
		var uv_raw = state.get("world_uv", null)
		if uv_raw is Dictionary:
			world_uv = Vector2(float(uv_raw.get("x", 0.0)), float(uv_raw.get("y", 0.0)))

		var unit: Unit = scene.instantiate()
		unit.owner = null
		# Seed physical_state BEFORE add_child so _ready sees the user's saved
		# values and skips the auto-name fallback.
		for k in state:
			if String(k) == "world_uv":
				continue
			unit.set(k, state[k])
		add_child(unit)
		unit.set_value(&"world_uv", world_uv)
		unit.global_position = world_uv_to_screen(world_uv)

	GameEvents.simulation_requested.emit()
