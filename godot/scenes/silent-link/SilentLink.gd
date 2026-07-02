extends Sandbox

# Silent Link Mode Controller - Event-driven state machine matching TutorialController structure

const SILENT_LINK_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const SILENT_LINK_HINT := preload("res://scenes/ui/HintPopup.tscn")
const TRANSCEIVER_DEF := preload("res://data/units/transceiver.tres")
const UNIT_SCRIPT := preload("res://scenes/core/Unit.gd")
const SLOT_VISUAL_SCENE := preload("res://scenes/silent-link/SilentLinkSlotVisual.tscn")

const MAX_LEVEL := 5

enum Step { WELCOME, PLANNING, SIMULATING, COMPLETE }

var _step: Step = Step.WELCOME
var _intro_popup_open := false
var _start_time: float = 0.0
var _completion_time: float = 0.0
var _timer_label: Label = null
var _hud: Node = null
var _current_level: int = 1
var _last_hint_time: float = -10.0

var _link_established := false
var _player_detected := false
var _jammed := false
var _simulation_over := false
var _terrain_blocked := false
var _link_success_from_sim := false

# Gameplay entities
var _player_units: Array = []
var _enemy_units: Array = []
var _transceivers: Array = []
var _allowed_units: Array[StringName] = []

# Fixed-slot transceiver workflow
var _placement_slots: Array[Node2D] = []
var _player_transceivers: Array = []
var _slot_to_tx: Dictionary = {}  # Node2D -> Node2D
var _pending_place_index: int = 0
var _slot_visuals: Dictionary = {} # marker -> visual


func add_to_groups_recursive(node: Node) -> void:
	for c in node.get_children():
		if c.name.begins_with("Friendly"):
			c.add_to_group("transceivers")
		elif c.name.begins_with("Enemy"):
			c.add_to_group("enemy_units")
		add_to_groups_recursive(c)


func _ready() -> void:
	super._ready()

	# Extract scene level from scene name
	var level_name := get_tree().current_scene.scene_file_path
	var file_name := level_name.get_file().get_basename()
	var parts := file_name.split("-")
	_current_level = int(parts[1]) if parts.size() > 1 else 1

	add_to_groups_recursive(self)

	GameEvents.simulation_requested.connect(_on_simulation_requested)
	GameEvents.simulation_complete.connect(_on_simulation_complete)

	_hud = find_child("HUD", true, false)

	if is_instance_valid(_hud):
		if _hud.has_method("set_spectrum_enabled"):
			_hud.set_spectrum_enabled(true)

		var hints_toggle = _hud.find_child("DetectionHintsToggle", true, false)
		if hints_toggle and "button_pressed" in hints_toggle:
			hints_toggle.button_pressed = true

	_transceivers = get_tree().get_nodes_in_group("transceivers")
	_enemy_units = get_tree().get_nodes_in_group("enemy_units")

	_setup_level_restrictions()

	# Collect fixed slot markers + snap player transceivers to slots + lock movement
	_collect_slots()
	_collect_player_transceivers()

	set_process(true)
	_start()


func get_game_mode_name() -> String:
	return "silent-link"


func _exit_tree() -> void:
	if GameEvents.simulation_requested.is_connected(_on_simulation_requested):
		GameEvents.simulation_requested.disconnect(_on_simulation_requested)
	if GameEvents.simulation_complete.is_connected(_on_simulation_complete):
		GameEvents.simulation_complete.disconnect(_on_simulation_complete)


func _process(_delta: float) -> void:
	if _step == Step.PLANNING and _timer_label:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed


func _start() -> void:
	if _intro_popup_open:
		return
	_intro_popup_open = true

	var popup := SILENT_LINK_INTRO_POPUP.instantiate()
	var level_content := _get_level_intro_content(_current_level)

	popup.title_string = level_content["title"]
	popup.body_string = level_content["body"]
	popup.button_string = "Continue"

	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(popup)

	if popup.has_signal("continued"):
		popup.continued.connect(_on_intro_closed)


func _on_intro_closed() -> void:
	_intro_popup_open = false
	_advance()


func _advance() -> void:
	match _step:
		Step.WELCOME:
			_step = Step.PLANNING
			_start_time = Time.get_ticks_msec() / 1000.0
			_show_timer()
			_apply_card_restrictions()
			_show_hint("Transceivers are fixed. Tune attributes to avoid detection and jamming.")

		Step.PLANNING:
			pass

		Step.SIMULATING:
			pass

		Step.COMPLETE:
			_show_scoreboard()


func _setup_level_restrictions() -> void:
	match _current_level:
		1, 2, 3:
			_allowed_units = [&"transceiver"]
		4, 5:
			_allowed_units = [&"transceiver", &"sensor"]
		_:
			_allowed_units = [&"transceiver", &"sensor"]


func _apply_card_restrictions() -> void:
	var sidebar := get_tree().get_first_node_in_group("ui") as Sidebar
	if not sidebar:
		sidebar = get_tree().root.find_child("Sidebar", true, false) as Sidebar
	if not sidebar:
		return

	var entity_types: Array[Dictionary] = [
		{"type": Sidebar.EntityType.TRANSCEIVER, "id": StringName("transceiver")},
		{"type": Sidebar.EntityType.JAMMER, "id": StringName("jammer")},
		{"type": Sidebar.EntityType.SENSOR, "id": StringName("sensor")}
	]

	for entity: Dictionary in entity_types:
		var card = sidebar._entity_cards.get(entity["type"])
		if not card:
			continue

		var id: StringName = entity["id"] as StringName
		var is_allowed: bool = id in _allowed_units

		card.modulate.a = 1.0 if is_allowed else 0.3
		card.set_process_input(is_allowed)
		card.mouse_filter = Control.MOUSE_FILTER_STOP if is_allowed else Control.MOUSE_FILTER_IGNORE

		for child in card.get_children():
			child.mouse_filter = (
				Control.MOUSE_FILTER_PASS if is_allowed else Control.MOUSE_FILTER_IGNORE
			)


# Slot discovery (create Marker2D/Node2D points in scene in group "silent_link_slots")
func _collect_slots() -> void:
	_placement_slots.clear()
	_slot_to_tx.clear()
	var nodes := get_tree().get_nodes_in_group("silent_link_slots")
	for n in nodes:
		if n is Node2D:
			_placement_slots.append(n)
	_placement_slots.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.name < b.name)

	for s in _placement_slots:
		_update_slot_visual(s, false)

	_spawn_slot_visuals()


# Player transceivers = transceivers not starting with Friendly
func _collect_player_transceivers() -> void:
	_player_transceivers.clear()
	for t in get_tree().get_nodes_in_group("transceivers"):
		if not t.name.begins_with("Friendly"):
			_player_transceivers.append(t as Node2D)

	_player_transceivers.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)


func _ensure_player_transceivers_for_slots() -> void:
	# Spawn until we have one transceiver per slot (up to 2 for current design)
	var needed: int = mini(2, _placement_slots.size())
	while _player_transceivers.size() < needed:
		var idx := _player_transceivers.size()
		var tx := Node2D.new()
		tx.name = "PlayerTransceiver%d" % (idx + 1)
		tx.set_script(UNIT_SCRIPT)
		tx.set("definition", TRANSCEIVER_DEF)
		tx.set("is_immovable", true)  # fixed placement
		tx.set("is_removable", false)
		tx.set("attribute_overrides", {&"frequency": 600.0})
		add_child(tx)
		tx.add_to_group("transceivers")
		_player_transceivers.append(tx)


# Enforce predetermined positions
func _assign_transceivers_to_slots() -> void:
	var count: int = mini(_placement_slots.size(), _player_transceivers.size())
	for i in range(count):
		var slot: Node2D = _placement_slots[i] as Node2D
		var tx: Node2D = _player_transceivers[i] as Node2D
		if slot == null or tx == null:
			continue
		tx.global_position = slot.global_position


# Prevent moving fixed transceivers while still allowing attribute edits
func _lock_transceiver_movement() -> void:
	for tx in _player_transceivers:
		if tx.has_method("set_movable"):
			tx.set_movable(false)
		if tx.has_method("set_draggable"):
			tx.set_draggable(false)
		if tx.has_meta("movable"):
			tx.set_meta("movable", false)


func _has_minimum_setup() -> bool:
	return _placement_slots.size() >= 2 and _slot_to_tx.size() >= 2


func _show_hint_debounced(text: String, cooldown: float = 1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hint_time < cooldown:
		return
	_last_hint_time = now
	_show_hint(text)


func _on_simulation_requested() -> void:
	if _step != Step.PLANNING and _step != Step.COMPLETE:
		return

	if not _has_minimum_setup():
		_step = Step.PLANNING
		_show_hint_debounced(
			"Level setup incomplete: need at least 2 fixed slots and 2 player transceivers."
		)
		return

	_assign_transceivers_to_slots()

	_player_units.clear()
	for u in get_tree().get_nodes_in_group("transceivers"):
		if not u.name.begins_with("Friendly"):
			_player_units.append(u)

	_player_detected = false
	_jammed = false
	_link_established = false
	_terrain_blocked = false
	_simulation_over = false
	_step = Step.SIMULATING


func _on_simulation_complete(link_results: Array, _detect_results: Array) -> void:
	if _step != Step.SIMULATING or _simulation_over:
		return

	if not _has_minimum_setup():
		return

	_player_detected = false
	_jammed = false
	_terrain_blocked = false
	_link_established = false
	_simulation_over = false
	_link_success_from_sim = false

	# Parse authoritative simulation outcomes
	for result in link_results:
		if not (result is Dictionary):
			continue

		var state: int = result.get("state", -1)

		if state == SimulationManager.LinkState.SUCCESS:
			_link_success_from_sim = true
		elif state == SimulationManager.LinkState.TERRAIN_BLOCKED:
			_terrain_blocked = true
		elif state == SimulationManager.LinkState.FAILED_JAMMED:
			_jammed = true

	_check_jamming()
	_check_detection()

	if _terrain_blocked:
		_step = Step.PLANNING
		_show_hint_debounced("Link blocked by terrain! Tune frequency/power and try again.")
		return

	if not _link_success_from_sim:
		_step = Step.PLANNING
		_show_hint_debounced("Link not established - tune transceiver attributes.")
		return

	if _jammed:
		_step = Step.PLANNING
		_show_hint_debounced("Signal jammed! Tune attributes to reduce jammer vulnerability.")
		return

	if _player_detected:
		_step = Step.PLANNING
		_show_hint_debounced("Detected by enemy! Tune for stealth and retry.")
		return

	_link_established = true
	_finish(true)


func _parse_sim_results_for_flags(link_results: Array, detect_results: Array) -> void:
	for result in link_results:
		if not result is Dictionary:
			continue

		var state: int = result.get("state", 0)

		if state == SimulationManager.LinkState.TERRAIN_BLOCKED:
			_terrain_blocked = true
		elif state == SimulationManager.LinkState.FAILED_JAMMED:
			_jammed = true

	for detect_result in detect_results:
		if detect_result is Dictionary:
			pass


func _finish(success: bool) -> void:
	if _simulation_over:
		return

	_simulation_over = true
	_completion_time = Time.get_ticks_msec() / 1000.0 - _start_time

	if success:
		_step = Step.COMPLETE
	else:
		_step = Step.PLANNING

	_advance()


func _show_timer() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 500
	add_child(canvas)

	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)

	_timer_label = Label.new()
	_timer_label.text = "Time: 0.0s"
	_timer_label.add_theme_font_size_override("font_size", 24)

	_timer_label.anchor_left = 1.0
	_timer_label.anchor_top = 1.0
	_timer_label.anchor_right = 1.0
	_timer_label.anchor_bottom = 1.0
	_timer_label.offset_left = -220
	_timer_label.offset_top = -90
	_timer_label.offset_right = -20
	_timer_label.offset_bottom = -50

	ui.add_child(_timer_label)


func _show_hint(text: String) -> void:
	var popup := SILENT_LINK_HINT.instantiate()
	popup.hint_text = text

	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(popup)


func _check_link_possible() -> bool:
	var total_transceivers: Array = _player_units.duplicate()
	for t in _transceivers:
		if t not in total_transceivers:
			total_transceivers.append(t)

	if total_transceivers.size() < 2:
		return false

	var tx1: Node2D = total_transceivers[0] as Node2D
	var tx2: Node2D = total_transceivers[1] as Node2D
	if tx1 == null or tx2 == null:
		return false

	if tx1.global_position.distance_to(tx2.global_position) < 10.0:
		return false

	var distance: float = tx1.global_position.distance_to(tx2.global_position)
	if distance > 500.0:
		return false

	var freq1: float = float(tx1.get("frequency"))
	var freq2: float = float(tx2.get("frequency"))
	var freq_diff: float = abs(freq1 - freq2)
	if freq_diff > 100.0:
		return false

	return true


func _check_detection() -> void:
	for unit in _player_units:
		for enemy in _enemy_units:
			if _unit_in_detection_zone(unit, enemy):
				_player_detected = true
				return


func _unit_in_detection_zone(unit: Node, enemy: Node) -> bool:
	var dist: float = unit.global_position.distance_to(enemy.global_position)
	var detection_radius: float = 100.0
	if enemy.has_method("detection_radius"):
		detection_radius = float(enemy.detection_radius())
	return dist < detection_radius


func _check_jamming() -> void:
	for unit in _player_units:
		for enemy in _enemy_units:
			if enemy.has_method("is_jammer") and enemy.is_jammer():
				var dist: float = unit.global_position.distance_to(enemy.global_position)
				var jam_radius: float = 70.0
				if enemy.has_method("jam_radius"):
					jam_radius = float(enemy.jam_radius())
				if dist < jam_radius:
					_jammed = true
					return


func register_player_unit(unit: Node) -> void:
	if not _player_units.has(unit):
		_player_units.append(unit)


func unregister_player_unit(unit: Node) -> void:
	if _player_units.has(unit):
		_player_units.erase(unit)


func _show_scoreboard() -> void:
	var score := _calculate_score()
	var minutes := int(_completion_time) / 60
	var seconds := int(_completion_time) % 60

	var popup := SILENT_LINK_INTRO_POPUP.instantiate()
	popup.title_string = "Mission Successful!"
	popup.body_string = (
		"[i]Link established![/i]\n\n"
		+ "[b]Time:[/b] %d:%02d\n" % [minutes, seconds]
		+ "[b]Score:[/b] %d\n" % score
	)

	if _current_level < MAX_LEVEL:
		popup.button_string = "Next Level"
	else:
		popup.button_string = "Finish"

	var cl := CanvasLayer.new()
	cl.layer = 101
	add_child(cl)
	cl.add_child(popup)

	popup.continue_button.pressed.connect(_on_next_level_pressed)


func _calculate_score() -> int:
	var time_penalty := int(_completion_time)
	var frequency_penalty := 0
	var stealth_bonus := 0

	for unit in _player_units:
		var freq: float = float(unit.get("frequency"))
		frequency_penalty += int(abs(freq - 2.0) * 200.0)

	if not _player_detected:
		stealth_bonus += 1000
	if not _jammed:
		stealth_bonus += 500

	return max(1000, 10000 - time_penalty * 100 - frequency_penalty + stealth_bonus)


func _on_next_level_pressed() -> void:
	_current_level += 1

	set_process(false)
	set_physics_process(false)

	# Disconnect signals before scene change to prevent stale callbacks
	if GameEvents.simulation_requested.is_connected(_on_simulation_requested):
		GameEvents.simulation_requested.disconnect(_on_simulation_requested)
	if GameEvents.simulation_complete.is_connected(_on_simulation_complete):
		GameEvents.simulation_complete.disconnect(_on_simulation_complete)

	if _current_level > MAX_LEVEL:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return

	get_tree().change_scene_to_file("res://scenes/silent-link/level-%d.tscn" % _current_level)


func _get_level_intro_content(level: int) -> Dictionary:
	match level:
		1:
			return {
				"title": "Silent Link Mode - Level 1",
				"body":
				(
					"Transceiver positions are fixed in this mode.\n\n"
					+ "[i]Tune your transceiver attributes to establish a link\n"
					+ "while avoiding detection and jamming.\n\n"
					+ "• Adjust frequency carefully\n"
					+ "• Balance speed vs stealth\n"
					+ "• Simulate and iterate[/i]"
				)
			}
		2:
			return {
				"title": "Silent Link Mode - Level 2",
				"body":
				(
					"More enemy pressure, same fixed transceiver slots.\n\n"
					+ "[i]You must optimize attributes to stay hidden.\n"
					+ "• Tune frequency against detection risk\n"
					+ "• Avoid jammer influence zones[/i]"
				)
			}
		3:
			return {
				"title": "Silent Link Mode - Level 3",
				"body":
				(
					"Advanced enemy coverage detected.\n\n"
					+ "[i]With fixed placement, attribute tuning is everything.\n"
					+ "• Fine-tune frequency\n"
					+ "• Minimize exposure windows[/i]"
				)
			}
		4:
			return {
				"title": "Silent Link Mode - Level 4",
				"body":
				(
					"Hidden jammers are active.\n\n"
					+ "[i]Use sensors and tune attributes precisely.\n"
					+ "• Sensor colors indicate jammer proximity\n"
					+ "• Red = close threat, blue = clear[/i]"
				)
			}
		5:
			return {
				"title": "Silent Link Mode - Level 5",
				"body":
				(
					"Final challenge: fixed slots, maximum enemy pressure.\n\n"
					+ "[i]Master stealth tuning to complete the mission.[/i]"
				)
			}
		_:
			return {"title": "Silent Link Mode", "body": "Unknown level"}


func _generate_terrain(w: int, h: int, seed: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = 1
	noise.frequency = 0.025
	noise.fractal_octaves = 3

	var g: Array = []
	for x in range(w):
		g.append([])
		for y in range(h):
			var n := noise.get_noise_2d(float(x), float(y))
			var h_m := (n + 1.0) * 0.5 * 500.0
			g[x].append(h_m)
	return g


func _unhandled_input(event: InputEvent) -> void:
	if _step != Step.PLANNING:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_slot := _get_clicked_slot(event.position)
		if clicked_slot != null:
			_place_or_select_slot(clicked_slot)
			get_viewport().set_input_as_handled()


func _get_clicked_slot(mouse_pos: Vector2) -> Node2D:
	for slot in _placement_slots:
		var radius := 80.0
		if slot.global_position.distance_to(mouse_pos) <= radius:
			return slot
	return null


func _place_or_select_slot(slot: Node2D) -> void:
	if _slot_to_tx.has(slot):
		_show_hint_debounced("Slot already occupied. Tune that transceiver's attributes.", 0.4)
		return

	var tx := _spawn_player_transceiver()
	tx.global_position = slot.global_position
	_slot_to_tx[slot] = tx
	if not _player_transceivers.has(tx):
		_player_transceivers.append(tx)

	_update_slot_visual(slot, true)
	_show_hint_debounced("Transceiver placed. Adjust frequency/power, then simulate.", 0.4)


func _spawn_player_transceiver() -> Node2D:
	var tx := Node2D.new()
	tx.name = "PlayerTransceiver%d" % (_player_transceivers.size() + 1)
	tx.set_script(UNIT_SCRIPT)
	tx.set("definition", TRANSCEIVER_DEF)
	tx.set("is_immovable", true)
	tx.set("is_removable", false)
	tx.set("attribute_overrides", {&"frequency": 600.0})
	add_child(tx)
	tx.add_to_group("transceivers")
	return tx


func _update_slot_visual(slot: Node2D, occupied: bool) -> void:
	var visual = _slot_visuals.get(slot, null)
	if visual and visual.has_method("set_occupied"):
		visual.set_occupied(occupied)


func _spawn_slot_visuals() -> void:
	for v in _slot_visuals.values():
		if is_instance_valid(v):
			v.queue_free()
	_slot_visuals.clear()

	for slot in _placement_slots:
		var visual := SLOT_VISUAL_SCENE.instantiate()
		add_child(visual)
		visual.top_level = true
		visual.global_position = slot.global_position
		visual.z_index = 200
		if visual.has_method("set_occupied"):
			visual.set_occupied(false)
		_slot_visuals[slot] = visual
