class_name Unit extends Node2D

# A press+release that moves the cursor less than this counts as a click,
# not a drag. Above it, the unit is considered dragged.
const CLICK_DRAG_THRESHOLD_PX := 5.0
const SELECTION_RADIUS := 32.0

@export var definition: UnitDefinition
var physical_state: Dictionary = {}

var _unit_visual: UnitVisual

# Public accessor — used by BaseLevel for selection highlight.
var unit_visual: UnitVisual:
	get:
		return _unit_visual

var _selection_area: Area2D
var _is_being_dragged: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0


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
			physical_state[spec.id] = spec.default_value


func _spawn_visual() -> void:
	_unit_visual = UnitVisual.new()
	_unit_visual.unit_label = definition.letter
	_unit_visual.circle_color = definition.color
	_unit_visual.sprite_sheet_path = definition.animated_sprite_path
	_unit_visual.unit_name = get_value(&"unit_name", "")
	add_child(_unit_visual)


func update_ranges() -> void:
	if _unit_visual == null:
		return

	var is_transceiver = is_in_group("transceivers")
	var is_jammer = is_in_group("jammers")
	var is_sensor = is_in_group("sensors")
	var height: float = get_value(&"height", 0.0)

	if is_transceiver:
		var power: float = get_value(&"power", 0.0)
		var frequency: float = get_value(&"frequency", 1000.0)
		var max_range = PhysicsEngine.calculate_signal_range(power, height, height, frequency)
		_unit_visual.set_ring("max_range", max_range, "MAX RANGE")

		var bw_idx: int = get_value(&"transceiver_bandwidth", 0)
		var bw_power: float = PhysicsEngine.BANDWIDTH_POWER[bw_idx]
		var bw_penalty: float = PhysicsEngine.bandwidth_penalty(bw_idx)
		if bw_penalty > 0.0:
			var strong_range = PhysicsEngine.calculate_signal_range(
				power, height, height, frequency, PhysicsEngine.NOISE_FLOOR / bw_power
			)
			_unit_visual.set_ring("strong_range", min(strong_range, max_range), "STRONG SIGNAL")
		else:
			_unit_visual.remove_ring("strong_range")

	elif is_jammer:
		# Jamming range = where received_power * BANDWIDTH_POWER[bw] > NOISE_FLOOR
		# Rearranged: received_power > NOISE_FLOOR / BANDWIDTH_POWER[bw]
		# Narrower bandwidth = larger scale = longer range but tighter frequency window
		var power: float = get_value(&"power", 0.0)
		var frequency: float = get_value(&"frequency", 1000.0)
		var bw_idx: int = get_value(&"jammer_bandwidth", 1)
		var bw_scale: float = PhysicsEngine.BANDWIDTH_POWER[bw_idx]
		var effective_target := PhysicsEngine.NOISE_FLOOR / bw_scale

		var jam_range := PhysicsEngine.calculate_signal_range(
			power, height, 5.0, frequency, effective_target
		)
		_unit_visual.set_ring("jamming", jam_range, "JAM RANGE")

	elif is_sensor:
		var sensitivity: float = get_value(&"sensitivity", 3.0)
		var tuning_frequency: float = get_value(&"tuning_frequency", 1000.0)
		var bw_idx: int = get_value(&"sensor_bandwidth", 1)
		var threshold := (
			lerpf(3.0, PhysicsEngine.NOISE_FLOOR, sensitivity / 10.0)
			+ PhysicsEngine.bandwidth_penalty(bw_idx)
		)

		# Use defaults matching the transceiver attribute spec (power=5, height=5)
		# and tuning_frequency to match is_detected's frequency check
		var detection_range := PhysicsEngine.calculate_signal_range(
			5.0, 5.0, height, tuning_frequency, threshold
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


func _on_selection_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Only the initial press starts a drag here. Release and motion live in
	# _input so they keep working when the cursor leaves the shape mid-drag.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Preserve main #61's UX: clear stale link visuals on drag-press.
		GameEvents.links_clear_requested.emit()
		_is_being_dragged = true
		_drag_start_pos = get_global_mouse_position()
		_drag_distance = 0.0
		get_tree().root.set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _is_being_dragged:
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		# Preserve main #61's UX: re-sim on drag-release so links reflect
		# the new geometry. Signal-based to match round-7's bus pattern.
		if _drag_distance < CLICK_DRAG_THRESHOLD_PX:
			GameEvents.select(self)
		else:
			GameEvents.simulation_requested.emit()
		_is_being_dragged = false
		get_tree().root.set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		# Clamp by converting through the level's UV space — which already
		# accounts for sidebar/playable-area exclusion. No direct sidebar reach.
		var base_level = get_parent()
		if not (base_level and base_level.has_method("screen_to_world_uv")):
			return

		var mouse_pos = get_global_mouse_position()
		var world_uv = base_level.screen_to_world_uv(mouse_pos)
		var clamped := Vector2(clamp(world_uv.x, 0.0, 1.0), clamp(world_uv.y, 0.0, 1.0))

		if has_meta("world_uv"):
			set_meta("world_uv", clamped)

		global_position = base_level.world_uv_to_screen(clamped)
		_drag_distance = _drag_start_pos.distance_to(global_position)
		get_tree().root.set_input_as_handled()


func _process(_delta: float) -> void:
	# Defensive drag-end if we miss the release event (e.g., focus loss).
	if _is_being_dragged and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_being_dragged = false
