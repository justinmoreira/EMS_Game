class_name Unit extends Node2D

# A press+release that moves the cursor less than this counts as a click,
# not a drag. Above it, the unit is considered dragged.
const CLICK_DRAG_THRESHOLD_PX := 5.0
const SELECTION_RADIUS := 32.0

@export var attribute_overrides: Dictionary = {}
@export var definition: UnitDefinition
@export var is_immovable: bool = false  # If true, this unit cannot be dragged
@export var is_removable: bool = true  # If false, this unit cannot be removed
var physical_state: Dictionary = {}
var _attributes_unlocked_override: bool = false
var _selectable_override: bool = true

var _unit_visual: UnitVisual

# Public accessor — used by BaseLevel for selection highlight.
var unit_visual: UnitVisual:
	get:
		return _unit_visual

# Multiplayer fog-of-war: a concealed unit hides its visual (body, ownership
# glow, range rings, label) but stays in the scene and the simulation, so the
# win check and detection still operate on it. BaseLevel toggles this.
var _concealed: bool = false


func set_concealed(value: bool) -> void:
	_concealed = value
	if _unit_visual:
		_unit_visual.visible = not value


func is_concealed() -> bool:
	return _concealed
	

func set_attributes_unlocked_override(value: bool) -> void:
	_attributes_unlocked_override = value


func attributes_unlocked_override() -> bool:
	return _attributes_unlocked_override


func set_selectable(value: bool) -> void:
	_selectable_override = value


func is_selectable() -> bool:
	return _selectable_override


# Viewer-relative team (UnitVisual.Owner.MINE / ENEMY / NONE), used to suppress
# link lines between opposing units — your relays never carry signal through an
# enemy transceiver, so a cross-team line is just visual noise. NONE outside a
# multiplayer match, so this never changes single-player link rendering.
func owner_kind() -> int:
	if _unit_visual:
		return _unit_visual.owner_kind
	return _owner_kind()


var _selection_area: Area2D
var _is_being_dragged: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO  # mouse position at press
var _drag_start_unit_pos: Vector2 = Vector2.ZERO  # unit position at press (for cancel)
var _drag_distance: float = 0.0
# Tracks whether we've fired links_clear_requested this drag. Press alone
# shouldn't clear — only actual movement past CLICK_DRAG_THRESHOLD_PX. A pure
# click leaves the existing link visuals untouched.
var _drag_links_cleared: bool = false


func _ready() -> void:
	if definition == null:
		push_error("Unit %s has no definition resource" % name)
		return

	add_to_group(definition.group)
	_init_default_values()

	if get_value(&"unit_name", "") == "":
		set_value(&"unit_name", UnitNameManager.get_next_name(definition.id))

	GameEvents.units_changed.emit()
	_spawn_visual()
	_setup_selection_area()


func _exit_tree() -> void:
	GameEvents.units_changed.emit.call_deferred()


# ── Domain (definition / physical_state) ─────────────────────────────


# Returns the value for an attribute id, or fallback if unset.
func get_value(id: StringName, fallback = null):
	return physical_state.get(id, fallback)


# Writes a value and propagates to the visual when the change is observable.
func set_value(id: StringName, v) -> void:
	physical_state[id] = v
	if _unit_visual and id == &"unit_name":
		_unit_visual.unit_name = v
		_unit_visual.queue_redraw()


# Backwards-compatibility shim: existing callers (PhysicsEngine, Sidebar's
# pending_attributes apply) use Node.get/set with property names. Route
# those through physical_state so unit.power / unit.set("power", v) keep
# working without sprinkling get_value everywhere.
func _get(property: StringName):
	if physical_state.has(property):
		return physical_state[property]
	return null


func _set(property: StringName, value) -> bool:
	if definition and _has_attribute(property):
		set_value(property, value)
		return true
	return false


func _has_attribute(id: StringName) -> bool:
	for spec in definition.attributes:
		if spec.id == id:
			return true
	return false


func _init_default_values() -> void:
	for spec in definition.attributes:
		if not physical_state.has(spec.id):
			if attribute_overrides.has(spec.id):
				physical_state[spec.id] = attribute_overrides[spec.id]
			else:
				physical_state[spec.id] = spec.default_value


func _spawn_visual() -> void:
	_unit_visual = UnitVisual.new()
	_unit_visual.unit_label = definition.letter
	_unit_visual.circle_color = definition.color
	_unit_visual.sprite_sheet_path = definition.animated_sprite_path
	_unit_visual.unit_name = get_value(&"unit_name", "")
	_unit_visual.owner_kind = _owner_kind()
	add_child(_unit_visual)


# Ownership for the multiplayer glow: your units glow blue, the opponent's
# glow red. The body keeps its TYPE color either way — the glow is the only
# thing that encodes WHO owns the unit. Outside a multiplayer match (no
# MULTIPLAYER_PLAYER_ID) there's no owner, so no glow.
func _owner_kind() -> int:
	# Immutable objective units carry an explicit, viewer-relative glow hint
	# (glow_kind) set by the level. They have no owner_player_id on purpose —
	# that would make apply_opponent_board treat them as a player's units and
	# wipe them — so honor the hint directly.
	var forced: Variant = physical_state.get(&"glow_kind", null)
	if forced != null:
		return int(forced)
	var local_id := _local_mp_player_id()
	if local_id == "":
		return UnitVisual.Owner.NONE
	var owner_v: Variant = physical_state.get(&"owner_player_id", null)
	if owner_v is String and (owner_v as String) != local_id:
		return UnitVisual.Owner.ENEMY
	return UnitVisual.Owner.MINE


# MultiplayerMatch.tsx publishes window.MULTIPLAYER_PLAYER_ID = auth.uid()
# as soon as the session resolves. Returns "" on desktop, in sandbox, or
# before the global is set — all cases where there's no ownership glow.
func _local_mp_player_id() -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("window.MULTIPLAYER_PLAYER_ID || ''")
	if v is String:
		return v as String
	return ""


func update_ranges() -> void:
	if _unit_visual == null:
		return

	var is_transceiver = is_in_group("transceivers")
	var is_jammer = is_in_group("jammers")
	var is_sensor = is_in_group("sensors")
	var power: float = get_value(&"power", 0.0)
	var height: float = get_value(&"height", 0.0)
	var frequency: float = get_value(&"frequency", 1000.0)

	var ground_h: float = 0.0
	var terrain = get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.has_method("get_ground_height_at_pos"):
		ground_h = terrain.get_ground_height_at_pos(global_position)

	if is_transceiver:
		var max_range = PhysicsEngine.calculate_signal_range(
			power,
			ground_h + height,
			ground_h + height,
			frequency,
			0.5,
			PhysicsEngine.TRANSCEIVER_BALANCE_RATIO
		)
		_unit_visual.set_ring("max_range", max_range, "MAX RANGE")

		var bw_idx: int = get_value(&"transceiver_bandwidth", 0)
		var bw_power: float = PhysicsEngine.BANDWIDTH_POWER[bw_idx]
		var bw_penalty: float = PhysicsEngine.bandwidth_penalty(bw_idx)
		if bw_penalty > 0.0:
			var strong_range = PhysicsEngine.calculate_signal_range(
				power,
				ground_h + height,
				ground_h + height,
				frequency,
				PhysicsEngine.NOISE_FLOOR / bw_power,
				PhysicsEngine.TRANSCEIVER_BALANCE_RATIO
			)
			_unit_visual.set_ring("strong_range", min(strong_range, max_range), "STRONG SIGNAL")
		else:
			_unit_visual.remove_ring("strong_range")

	elif is_jammer:
		var bw_idx: int = get_value(&"jammer_bandwidth", 0)
		var bw_power: float = PhysicsEngine.BANDWIDTH_POWER[bw_idx]
		var max_range := PhysicsEngine.calculate_signal_range(
			power,
			ground_h + height,
			ground_h + height,
			frequency,
			PhysicsEngine.NOISE_FLOOR,
			bw_power * PhysicsEngine.JAMMER_BALANCE_RATIO
		)
		_unit_visual.set_ring("max_range", max_range, "JAM RANGE")
		_unit_visual.remove_ring("strong_range")

	elif is_sensor:
		var sensitivity: float = get_value(&"sensitivity", 3.0)
		var tuning_frequency: float = get_value(&"tuning_frequency", 1000.0)
		var bw_idx: int = get_value(&"sensor_bandwidth", 1)
		var threshold := (
			lerpf(3.0, PhysicsEngine.NOISE_FLOOR, sensitivity / 10.0)
			+ PhysicsEngine.bandwidth_penalty(bw_idx)
		)

		var detection_range := PhysicsEngine.calculate_signal_range(
			5.0,
			ground_h + height,
			ground_h + height,
			tuning_frequency,
			threshold,
			PhysicsEngine.SENSOR_BALANCE_RATIO
		)
		_unit_visual.set_ring("detection", detection_range, "DETECTION RANGE")


# ── Interaction (drag / click select) ────────────────────────────────


func _setup_selection_area() -> void:
	_selection_area = Area2D.new()
	_selection_area.name = "SelectionArea"
	_selection_area.input_pickable = true

	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = SELECTION_RADIUS
	collision.shape = circle
	_selection_area.add_child(collision)
	add_child(_selection_area)
	# Click detection via Area2D picking — Godot only fires this on the unit
	# under the cursor, so click cost is O(1) instead of O(N) per event.
	_selection_area.input_event.connect(_on_selection_input)


func is_immutable() -> bool:
	return bool(physical_state.get(&"immutable", false))


# Cannot be moved / edited / deleted by the local player. True for the immutable
# objective, for pieces this player has already submitted (the `locked` flag),
# and — in a match — for the opponent's pieces. Nothing is locked in
# sandbox / singleplayer (no local player id).
func is_locked() -> bool:
	if is_immutable():
		return true
	# main's design-time "can't be moved" flag (e.g. enemy-hunter targets).
	if is_immovable:
		return true
	if bool(physical_state.get(&"locked", false)):
		return true
	var local := _local_mp_player_id()
	if local == "":
		return false
	var owner_v: Variant = physical_state.get(&"owner_player_id", null)
	return not (owner_v is String and String(owner_v) == local)


func _on_selection_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Only the initial press starts a drag here. Release and motion live in
	# _input so they keep working when the cursor leaves the shape mid-drag.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Locked pieces (objective, already-submitted, opponent's, or a unit
		# main flags immovable) can be inspected but never moved — select for
		# the read-only panel and stop.
		if not is_selectable():
			get_tree().root.set_input_as_handled()
			return
			
		if is_locked():
			GameEvents.select(self)
			get_tree().root.set_input_as_handled()
			return

		# Preserve main #61's UX: clear stale link visuals on drag-press.
		_is_being_dragged = true
		_drag_start_pos = get_global_mouse_position()
		_drag_start_unit_pos = global_position
		_drag_distance = 0.0
		_drag_links_cleared = false
		get_tree().root.set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _is_being_dragged or is_immovable:
		return

	# Right-click during a drag → cancel: snap back, leave links untouched
	# (re-sim only if motion already cleared them so visuals get rebuilt).
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		global_position = _drag_start_unit_pos
		var bl = get_parent()
		if bl and bl.has_method("screen_to_world_uv"):
			set_value(&"world_uv", bl.screen_to_world_uv(_drag_start_unit_pos))
		_is_being_dragged = false
		if _drag_links_cleared:
			GameEvents.simulation_requested.emit()
		get_tree().root.set_input_as_handled()
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		# A drag (moved past threshold) re-sims so links reflect the new geometry.
		# Either way, end with this unit selected so its panel shows what you
		# just clicked / placed / moved.
		if _drag_links_cleared:
			GameEvents.simulation_requested.emit()
			GameEvents.units_changed.emit()
		GameEvents.select(self)
		_is_being_dragged = false
		get_tree().root.set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var base_level = get_parent()
		if not (base_level and base_level.has_method("screen_to_world_uv")):
			return

		# Clamp in SCREEN space (sidebar's right edge → viewport right edge).
		# Clamping in world-UV [0,1] cuts off the rectangular map's left/right
		# strips, since UV [0,1] is the SQUARE subregion of a widescreen map.
		# sidebar_width is published live via GameEvents.
		var mouse_pos = get_global_mouse_position()
		var screen_rect = get_viewport().get_visible_rect()
		mouse_pos.x = clamp(
			mouse_pos.x,
			screen_rect.position.x + base_level.sidebar_width,
			screen_rect.position.x + screen_rect.size.x
		)
		mouse_pos.y = clamp(
			mouse_pos.y, screen_rect.position.y, screen_rect.position.y + screen_rect.size.y
		)

		var world_uv: Vector2 = base_level.screen_to_world_uv(mouse_pos)

		if world_uv.x >= 0.0 and world_uv.x <= 1.0 and world_uv.y >= 0.0 and world_uv.y <= 1.0:
			set_value(&"world_uv", world_uv)
			global_position = mouse_pos
		_drag_distance = _drag_start_pos.distance_to(global_position)

		# Fire-once: clear stale link visuals as soon as we know this is a real
		# drag (not a click). Pure clicks never reach the threshold, so their
		# existing visuals stay intact.
		if not _drag_links_cleared and _drag_distance >= CLICK_DRAG_THRESHOLD_PX:
			GameEvents.links_clear_requested.emit()
			_drag_links_cleared = true

		get_tree().root.set_input_as_handled()


func _process(_delta: float) -> void:
	# Defensive drag-end if we miss the release event (e.g., focus loss).
	if _is_being_dragged and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_being_dragged = false
