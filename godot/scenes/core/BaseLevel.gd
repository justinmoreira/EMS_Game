class_name BaseLevel
extends Control

# Unit attribute controls
const TOGGLE_UNIT_ATTRIBUTES_KEY := KEY_H
const ATTRIBUTE_LABEL_SCRIPT := preload("res://scenes/ui/UnitAttributesLabel.gd")
const SUGGESTIONS_PANEL_SCENE := preload("res://scenes/ui/SuggestionsDialog.tscn")

const MAP_SIZE = Vector2(1080, 1080)
const MAP_ORIGIN = Vector2(570, 0)

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

# Selection State
var currently_selected_unit: Node = null
var currently_hovered_unit: Node = null
var suggestions_panel: Control = null

@export var base_hover_radius: float = 32.0
@export var show_signal_ranges: bool = false
@export var suggestions_enabled: bool = false
# Sidebar layout — populated via signal, no global find_child reach.
# Width is the live x-size of the sidebar; 0 if no sidebar in this scene.
var sidebar_width: float = 0.0

# Selection visual cache — the *previous* selected unit, so we know which to
# unhighlight when selection changes. Source of truth lives on GameEvents.
var _last_highlighted: Unit = null
var unit_attributes_visible: bool = false
var terrain_heatmap_enabled: bool = false

@onready var background := $BackgroundTexture

# --- Initialization ---

var _opponent_board_cb: Variant = null

# ── Multiplayer match state ──────────────────────────────────────────
# Only meaningful when window.GAME_MODE == "multiplayer". The immutable
# source/target are the shared objective; placement is capped at one unit
# per resolved turn; the win is evaluated each time the board merges.
const MP_MAX_PLACEMENTS_PER_TURN := 1
var _mp_active: bool = false
var _mp_finished: bool = false
var _mp_source: Unit = null
var _mp_target: Unit = null
var _mp_seed: int = 0
var _mp_current_turn: int = -1
var _turn_cb: Variant = null


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

	toggle_suggestions(suggestions_enabled)

	# Defer MP setup one frame so the terrain/layout from subclass _ready()
	# (ContourDemo) is in place before we position the seed-placed objective.
	_mp_setup.call_deferred()


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
# units and the neutral immutable seed units are left alone. Ownership
# (physical_state.owner_player_id) drives the blue/red glow.
func apply_opponent_board(snapshot: Array, owner_id: String) -> void:
	for child in get_children():
		if not (child is Unit):
			continue
		var existing_owner: Variant = (child as Unit).physical_state.get(&"owner_player_id", null)
		if existing_owner is String and (existing_owner as String) == owner_id:
			child.queue_free()
	await get_tree().process_frame

	for entry in snapshot:
		_spawn_unit_from_entry(entry, owner_id)

	# Opponent geometry changed — rerun the sim so link lines, detection, and
	# range rings reflect the merged board, then re-check the win condition.
	GameEvents.simulation_requested.emit()
	_evaluate_win_condition()


# Multiplayer SUBMIT: snapshot the current unit layout and ship it to JS,
# which forwards to MultiplayerMatch.tsx's submitMpAction (inserts a row
# in match_actions for the current turn). serialize_units already returns
# the same JSON-friendly shape ScenePersister uses for sandbox autosaves.
func _on_mp_submit_requested() -> void:
	if not OS.has_feature("web"):
		return
	var snapshot := serialize_units(true)
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


# Local player's multiplayer id (auth uid), mirrored to window by
# MultiplayerMatch.tsx. Empty on desktop, in sandbox, or before the match
# resolves — i.e. whenever there's no ownership to assign.
func _local_mp_player_id() -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("window.MULTIPLAYER_PLAYER_ID || ''")
	return (v as String) if v is String else ""


# ── Multiplayer match gameplay ───────────────────────────────────────


func _is_multiplayer() -> bool:
	if not OS.has_feature("web"):
		return false
	var v: Variant = JavaScriptBridge.eval("window.GAME_MODE")
	return v is String and (v as String) == "multiplayer"


func _mp_setup() -> void:
	if not _is_multiplayer():
		return
	_mp_active = true
	_mp_seed = _read_match_number("seed")
	_register_turn_hook()
	_spawn_immutable_objective()
	# Sync to the turn we joined on, then watch for advances via the JS hook.
	_mp_on_turn_advance(_read_match_number("current_turn"))


func _read_match_number(field: String) -> int:
	if not OS.has_feature("web"):
		return 0
	var v: Variant = JavaScriptBridge.eval(
		"window.MULTIPLAYER_MATCH ? (window.MULTIPLAYER_MATCH." + field + " || 0) : 0"
	)
	var t := typeof(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return int(v)
	return 0


func _read_match_string(field: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval(
		"window.MULTIPLAYER_MATCH ? (window.MULTIPLAYER_MATCH." + field + " || '') : ''"
	)
	return (v as String) if v is String else ""


func _opponent_id() -> String:
	var me := _local_mp_player_id()
	var host := _read_match_string("host_id")
	var guest := _read_match_string("guest_id")
	if me == host:
		return guest
	if me == guest:
		return host
	return ""


# Registers window.godotOnTurnAdvance(turn) so MultiplayerMatch.tsx can notify
# Godot when the shared turn counter ticks (both players submitted) — that's
# when the placement cap resets and the next placement is allowed.
func _register_turn_hook() -> void:
	if not OS.has_feature("web"):
		return
	var window: Variant = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	_turn_cb = JavaScriptBridge.create_callback(_on_js_turn_advance)
	window.godotOnTurnAdvance = _turn_cb


func _on_js_turn_advance(args: Array) -> void:
	var turn := 0
	if args.size() >= 1:
		turn = int(args[0])
	_mp_on_turn_advance(turn)


func _mp_on_turn_advance(turn: int) -> void:
	if turn == _mp_current_turn:
		return
	_mp_current_turn = turn
	# Fresh turn → one new placement is allowed again.
	_refresh_placement_lock()


# Number of own, non-immutable units placed during the current (unresolved)
# turn — what the one-per-turn cap counts. Units from earlier turns carry a
# lower placed_turn and don't count; the immutable objective never counts.
func _mp_pending_count() -> int:
	var me := _local_mp_player_id()
	var n := 0
	for child in get_children():
		if not (child is Unit):
			continue
		var ps: Dictionary = (child as Unit).physical_state
		if bool(ps.get(&"immutable", false)):
			continue
		var o: Variant = ps.get(&"owner_player_id", null)
		if not (o is String and String(o) == me):
			continue
		if int(ps.get(&"placed_turn", -1)) == _mp_current_turn:
			n += 1
	return n


func _refresh_placement_lock() -> void:
	if not _mp_active:
		return
	var locked := _mp_finished or _mp_pending_count() >= MP_MAX_PLACEMENTS_PER_TURN
	GameEvents.mp_placement_locked.emit(locked)


# Deterministic source(transmitter)/target(sensor) from the match seed so both
# clients place them identically. Immutable + neutral (no owner) — the shared
# objective each side races to bridge.
func _spawn_immutable_objective() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _mp_seed
	var src_y := 0.30 + rng.randf() * 0.40
	var tgt_y := 0.30 + rng.randf() * 0.40
	var freq := 1000.0
	_mp_source = _spawn_immutable_unit(
		&"transceiver",
		Vector2(0.16, src_y),
		{
			&"unit_name": "SOURCE",
			&"power": 9,
			&"frequency": freq,
			&"height": 10,
			&"transceiver_bandwidth": 2,
		}
	)
	_mp_target = _spawn_immutable_unit(
		&"sensor",
		Vector2(0.84, tgt_y),
		{
			&"unit_name": "TARGET",
			&"sensitivity": 8,
			&"tuning_frequency": freq,
			&"height": 10,
			&"sensor_bandwidth": 2,
			&"is_scanning": true,
		}
	)
	GameEvents.simulation_requested.emit()


func _spawn_immutable_unit(type_id: StringName, world_uv: Vector2, attrs: Dictionary) -> Unit:
	var scene: PackedScene = _UNIT_SCENES.get(type_id)
	if scene == null:
		return null
	var unit: Unit = scene.instantiate()
	unit.owner = null
	var state := {}
	for k in attrs:
		state[k] = attrs[k]
	state[&"immutable"] = true
	state[&"world_uv"] = world_uv
	unit.physical_state = state
	add_child(unit)
	unit.set_value(&"world_uv", world_uv)
	unit.global_position = world_uv_to_screen(world_uv)
	return unit


# Removes only the current player's still-uncommitted (this-turn) placement —
# the MP meaning of the relabelled UNDO button. Never touches the immutable
# objective or already-submitted units.
func _mp_undo_pending() -> void:
	var me := _local_mp_player_id()
	for child in get_children():
		if not (child is Unit):
			continue
		var ps: Dictionary = (child as Unit).physical_state
		if bool(ps.get(&"immutable", false)):
			continue
		var o: Variant = ps.get(&"owner_player_id", null)
		if o is String and String(o) == me and int(ps.get(&"placed_turn", -1)) == _mp_current_turn:
			child.queue_free()
	GameEvents.clear_selection()
	_refresh_placement_lock.call_deferred()


# Win check: run after every board merge. The match ends the first resolved
# turn where exactly one side holds a source→target connection. Both clients
# evaluate the same merged board, so they agree on the winner; finish_match()
# on the DB side is idempotent, so the duplicate report is harmless.
func _evaluate_win_condition() -> void:
	if not _mp_active or _mp_finished:
		return
	if not (is_instance_valid(_mp_source) and is_instance_valid(_mp_target)):
		return
	var me := _local_mp_player_id()
	var opp := _opponent_id()
	var txs := get_tree().get_nodes_in_group(&"transceivers")
	var jammers := get_tree().get_nodes_in_group(&"jammers")
	var outcome := WinEvaluator.evaluate(
		SimulationManager, _mp_source, _mp_target, txs, jammers, me, opp
	)
	if outcome == WinEvaluator.OUTCOME_NONE:
		return
	var winner_id := me if outcome == WinEvaluator.OUTCOME_MINE else opp
	_mp_finished = true
	_refresh_placement_lock()
	_report_winner(winner_id)


func _report_winner(winner_id: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"window.mpReportWinner && window.mpReportWinner(" + JSON.stringify(winner_id) + ")"
	)


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


#TODO: Fix to give accurate representation of map origin
func _map_origin() -> Vector2:
	return background.position if background else Vector2(sidebar_width, 0)


#TODO: Fix to give accurate representation of map size
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


func world_uv_to_terrain_px(world_uv: Vector2) -> Vector2:
	return world_uv * MAP_SIZE + MAP_ORIGIN


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


func _get_hover_radius_pixels() -> float:
	# TODO: Implement for selection too?
	return base_hover_radius * (1.0 / zoom)


# --- Drag and Drop Logic ---


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("scene_path")):
		return false
	if at_position.x < sidebar_width:
		return false

	# Multiplayer: one placement per turn, and nothing once the match is over.
	if _mp_active:
		if _mp_finished:
			return false
		if _mp_pending_count() >= MP_MAX_PLACEMENTS_PER_TURN:
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

	# In a multiplayer match, stamp the unit with the local player's id so
	# ownership is explicit and durable: it rides in serialize_units → the
	# match_actions board JSON → the DB. Sandbox/singleplayer leaves it unset.
	# placed_turn tags which turn it belongs to so the one-per-turn cap (and
	# UNDO) can tell this turn's placement from already-committed ones.
	var mp_id := _local_mp_player_id()
	if mp_id != "":
		unit.physical_state[&"owner_player_id"] = mp_id
	if _mp_active:
		unit.physical_state[&"placed_turn"] = _mp_current_turn

	add_child(unit)

	# Auto-sim on place (preserves main's #61 UX via round-8's event-bus pattern).
	GameEvents.simulation_requested.emit()

	# Apply current visual settings (show/hide ranges) from #74.
	_set_unit_show_range_visual(unit, show_signal_ranges)

	_on_unit_placed(unit)
	# Newly-placed unit is treated as selected so its panel opens.
	GameEvents.select(unit)

	# Hitting the per-turn cap greys the entity tray (mirrors the tutorial's
	# placement gating) until SUBMIT resolves the turn.
	if _mp_active:
		_refresh_placement_lock()


func _on_unit_placed(unit: Unit) -> void:
	currently_selected_unit = unit
	var label = _get_or_create_attribute_label(unit)
	if label:
		label.visible = unit_attributes_visible
	toggle_suggestions(suggestions_enabled)

	# Apply current visual settings (show/hide ranges)
	_set_unit_show_range_visual(unit, show_signal_ranges)
	_set_unit_show_terrain_heatmap(unit, terrain_heatmap_enabled)


# --- Selection Logic (visual highlight only — state lives on GameEvents) ---


func _on_selection_changed(unit: Node) -> void:
	var prev: Node = _last_highlighted
	if prev and prev != unit:
		_set_unit_selected_visual(prev, false)
		_set_unit_show_terrain_heatmap(prev, false)

	_last_highlighted = unit if unit is Unit else null
	if _last_highlighted:
		_set_unit_selected_visual(_last_highlighted, true)
		_set_unit_show_terrain_heatmap(_last_highlighted, terrain_heatmap_enabled)

	var focused: Unit = unit if unit is Unit else null
	LinkRenderer.set_focused_unit(focused)
	SimulationManager.simulate()


func _set_unit_selected_visual(unit: Unit, selected: bool) -> void:
	if unit and unit.unit_visual:
		unit.unit_visual.set_selected(selected)


# --- Sidebar button handlers ---


func _set_unit_hover_visual(unit: Node, hovered: bool) -> void:
	if unit == null:
		return
	for child in unit.get_children():
		if child is UnitVisual:
			child.set_hovered(hovered)
			break


func _set_unit_show_range_visual(unit: Node, enabled: bool) -> void:
	if unit == null:
		return
	for child in unit.get_children():
		if child is UnitVisual:
			child.set_show_range(enabled)
			break


func toggle_signal_ranges(enabled: bool) -> void:
	# Toggle display of signal ranges for all unit visuals
	show_signal_ranges = enabled
	for child in get_children():
		if child is Unit:
			_set_unit_show_range_visual(child, enabled)


func toggle_suggestions(enabled: bool) -> void:
	suggestions_enabled = enabled
	if enabled:
		if suggestions_panel == null:
			suggestions_panel = SUGGESTIONS_PANEL_SCENE.instantiate()
			add_child.call_deferred(suggestions_panel)
	else:
		if suggestions_panel:
			suggestions_panel.queue_free()
			suggestions_panel = null

	call_deferred("_refresh_suggestions_ui")


func _refresh_suggestions_ui() -> void:
	if suggestions_panel == null:
		return

	if currently_selected_unit == null:
		return

	suggestions_panel._on_selection_changed(currently_selected_unit)


func _set_unit_show_terrain_heatmap(unit: Node, enabled: bool) -> void:
	if unit == null:
		return
	for child in unit.get_children():
		if child is UnitVisual:
			child.set_show_terrain_heatmap(enabled)
			break


func toggle_terrain_heatmap(enabled: bool) -> void:
	terrain_heatmap_enabled = enabled
	for child in get_children():
		if child is Unit:
			_set_unit_show_terrain_heatmap(child, enabled)


func _get_unit_component(unit: Node) -> Node:
	if unit == null:
		return null
	# Check children for functional components
	for child in unit.get_children():
		if child.name in ["Transceiver", "Jammer", "Sensor"]:
			return child
	return null


func _on_reset_requested() -> void:
	# LinkRenderer also subscribes to reset_requested and clears its own visuals.
	# In MP, the relabelled UNDO only pulls back this turn's own placement; the
	# shared objective and committed units stay put.
	if _mp_active:
		_mp_undo_pending()
		return
	UnitNameManager.reset()
	for group in [&"transceivers", &"jammers", &"sensors"]:
		for unit in get_tree().get_nodes_in_group(group):
			if unit is Unit and bool((unit as Unit).physical_state.get(&"immutable", false)):
				continue
			unit.queue_free()
	GameEvents.clear_selection()


func _on_delete_requested(unit: Node) -> void:
	# Never delete the immutable objective.
	if unit is Unit and bool((unit as Unit).physical_state.get(&"immutable", false)):
		return
	# LinkRenderer's per-frame purge will drop links involving this unit
	# once is_instance_valid returns false post-queue_free.
	if unit:
		unit.queue_free()
	GameEvents.clear_selection()
	if _mp_active:
		_refresh_placement_lock.call_deferred()


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

	# Hover logic
	elif event is InputEventMouseMotion:
		if dragging or event.position.x < sidebar_width:
			return

		var mouse_pos = get_global_mouse_position()
		var new_hover: Node = null
		for child in get_children():
			if child is Unit:
				var distance = child.global_position.distance_to(mouse_pos)
				if distance < _get_hover_radius_pixels():  # hover radius (pixels)
					new_hover = child
					break

		if new_hover != currently_hovered_unit:
			if currently_hovered_unit:
				_set_unit_hover_visual(currently_hovered_unit, false)
			currently_hovered_unit = new_hover
			if currently_hovered_unit:
				_set_unit_hover_visual(currently_hovered_unit, true)
			LinkRenderer.set_hovered_unit(currently_hovered_unit)
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

				if not clicked_unit:
					GameEvents.clear_selection()
					get_tree().root.set_input_as_handled()
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


func serialize_units(own_only: bool = false) -> Array:
	var out: Array = []
	var local_id := _local_mp_player_id()
	for child in get_children():
		if not (child is Unit and child.definition):
			continue
		if own_only:
			# Immutable seed units (source/target) exist identically on both
			# clients — regenerated from the match seed — so a submit must never
			# carry them, or they'd duplicate and desync the board.
			if bool((child as Unit).physical_state.get(&"immutable", false)):
				continue
			# Skip units owned by the OPPONENT — a submit carries only this
			# player's own units, never echoes the opponent's back to them.
			var o: Variant = (child as Unit).physical_state.get(&"owner_player_id", null)
			if o is String and (o as String) != local_id:
				continue
		out.append({"type": String(child.definition.id), "state": _serialize_state(child)})
	return out


# JSON-friendly snapshot of a unit's FULL physical_state. Every key is
# preserved (attributes, owner_player_id, immutable, …) — earlier versions
# only round-tripped declared definition attributes, which silently dropped
# custom state and reset pre-placed units to defaults on reload (bug E). The
# round-trip itself lives in UnitSnapshot so it's unit-testable headlessly.
func _serialize_state(unit: Unit) -> Dictionary:
	return UnitSnapshot.state_to_json(unit.physical_state)


# Inverse of _serialize_state: rebuild a physical_state Dictionary (StringName
# keys, world_uv as Vector2) from a stored entry.
func _entry_to_state(entry: Dictionary) -> Dictionary:
	return UnitSnapshot.state_from_entry(entry)


# Instantiate one unit from a serialized entry, seed its full physical_state
# BEFORE add_child (so _ready's default/name fallback sees the restored
# values), add it, and position it. `forced_owner` stamps ownership when the
# caller knows it out-of-band (opponent snapshots). Returns the Unit (or null).
func _spawn_unit_from_entry(entry: Variant, forced_owner: String = "") -> Unit:
	if not (entry is Dictionary):
		return null
	var type_id := StringName(String((entry as Dictionary).get("type", "")))
	var scene: PackedScene = _UNIT_SCENES.get(type_id)
	if scene == null:
		return null
	var state := _entry_to_state(entry as Dictionary)
	if forced_owner != "":
		state[&"owner_player_id"] = forced_owner
	var unit: Unit = scene.instantiate()
	unit.owner = null
	unit.physical_state = state
	add_child(unit)
	var world_uv: Vector2 = state.get(&"world_uv", Vector2.ZERO)
	unit.set_value(&"world_uv", world_uv)
	unit.global_position = world_uv_to_screen(world_uv)
	return unit


func deserialize_units(snapshot: Array) -> void:
	# Wipe the current scene before instantiating from the snapshot. queue_free
	# is deferred so we wait a frame before adding the replacements; otherwise
	# the new units race with the doomed ones and units_changed double-fires.
	# Immutable seed units are preserved — they belong to the match, not the
	# saved layout (a sandbox snapshot never contains them anyway).
	for group in [&"transceivers", &"jammers", &"sensors"]:
		for u in get_tree().get_nodes_in_group(group):
			if u is Unit and bool((u as Unit).physical_state.get(&"immutable", false)):
				continue
			u.queue_free()
	await get_tree().process_frame

	for entry in snapshot:
		_spawn_unit_from_entry(entry)

	GameEvents.simulation_requested.emit()
