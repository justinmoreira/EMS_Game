extends ContourDemo

# Silent Link Mode Controller – Event-driven state machine for
# "create a link without being detected/jammed"

const SILENT_LINK_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const SILENT_LINK_HINT := preload("res://scenes/ui/HintPopup.tscn")

const MAX_LEVEL := 5

enum Step { WELCOME, PLANNING, SIMULATING, COMPLETE }

var _step: Step = Step.WELCOME
var _intro_popup_open := false
var _start_time: float = 0.0
var _completion_time: float = 0.0
var _timer_label: Label = null
var _hud: Node = null

var _current_level: int = 1
var _link_established := false
var _player_detected := false
var _jammed := false
var _simulation_over := false

# Gameplay entities
var _player_units: Array = []
var _enemy_units: Array = []
var _transceivers: Array = []
var _scene_ready := false


func add_to_groups_recursive(node):
	for c in node.get_children():
		if c.name.begins_with("Friendly"):
			c.add_to_group("transceivers")
		elif c.name.begins_with("Enemy"):
			c.add_to_group("enemy_units")
		add_to_groups_recursive(c)


func _ready() -> void:
	super._ready()
	GameEvents.simulation_requested.connect(_begin_simulation)
	set_process(true)

	add_to_groups_recursive(self)

	# Extract scene level from scene name
	var level_name := get_tree().current_scene.scene_file_path
	var file_name := level_name.get_file().get_basename()
	var parts := file_name.split("-")

	_current_level = int(parts[1]) if parts.size() > 1 else 1

	var hud_nodes = get_tree().get_nodes_in_group("hud")
	if hud_nodes.size() > 0:
		_hud = hud_nodes[0]

	# Locate (preplaced) transceivers and enemy units
	_transceivers = get_tree().get_nodes_in_group("transceivers")
	_enemy_units = get_tree().get_nodes_in_group("enemy_units")

	_scene_ready = true
	_start()


func _start() -> void:
	if _intro_popup_open:
		return
	_intro_popup_open = true

	var popup := SILENT_LINK_INTRO_POPUP.instantiate()
	popup.title_string = "Silent Link Mode - Level %d" % _current_level
	popup.body_string = (
		"Establish a connection between the two friendly transceivers\n"
		+ "without being detected or jammed by the enemy!\n\n"
		+ "[i]• Place your units and link carefully\n"
		+ "• Avoid detection zones & jammers\n"
		+ "• Adjust frequency: high for fast, low for stealth\n\n"
		+ "Complete all 5 levels for a full spectrum of tactical challenges![/i]"
	)
	popup.button_string = "Begin"

	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(popup)

	if popup.has_signal("continued"):
		popup.continued.connect(_on_intro_closed)


func _on_intro_closed() -> void:
	_intro_popup_open = false
	_step = Step.PLANNING
	_start_time = Time.get_ticks_msec() / 1000.0
	_show_timer()


func register_player_unit(unit: Node) -> void:
	if not _player_units.has(unit):
		_player_units.append(unit)


func unregister_player_unit(unit: Node) -> void:
	if _player_units.has(unit):
		_player_units.erase(unit)


func _begin_simulation() -> void:
	_player_units = []
	for u in get_tree().get_nodes_in_group("transceivers"):
		if not u.name.begins_with("Friendly"):
			_player_units.append(u)
	if _step != Step.PLANNING and _step != Step.COMPLETE:
		return
	_step = Step.SIMULATING
	_simulation_over = false
	_link_established = false
	_player_detected = false
	_jammed = false
	_simulate_link()


func _process(_delta: float) -> void:
	if _timer_label:
		var elapsed = Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed

	if _step == Step.SIMULATING and not _simulation_over:
		_check_detection()
		_check_jamming()
		if _link_established and not (_player_detected or _jammed):
			_finish(true)
		elif _player_detected or _jammed:
			_finish(false)


func _finish(success: bool) -> void:
	if _simulation_over:
		return
	set_process(false)
	_simulation_over = true
	_completion_time = Time.get_ticks_msec() / 1000.0 - _start_time
	if success:
		_step = Step.COMPLETE
		_show_scoreboard(success)
	else:
		_step = Step.PLANNING  # allow player to retry


func _simulate_link() -> void:
	if not _check_link_possible():
		_show_hint("Link not possible - check your placements and retry!")
		_finish(false)
		return

	# Always run these to update detection and jamming for this frame
	_check_detection()
	_check_jamming()

	if _player_detected:
		_show_hint("Detected by enemy! Try again.")
		_finish(false)
		return
	elif _jammed:
		_show_hint("Signal jammed! Try again.")
		_finish(false)
		return

	# Only succeed if not jammed OR detected
	_link_established = true
	_finish(true)


func _advance() -> void:
	match _step:
		Step.WELCOME:
			_show_timer()
			_step = Step.PLANNING
		Step.PLANNING:
			_start_time = Time.get_ticks_msec() / 1000.0
		Step.SIMULATING:
			# Start simulation, check detection/jamming every frame
			_simulate_link()
		Step.COMPLETE:
			_show_scoreboard()


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


func _unit_is_jammed(unit: Node) -> bool:
	for enemy in _enemy_units:
		if enemy.has_method("is_jammer") and enemy.is_jammer():
			var dist = unit.global_position.distance_to(enemy.global_position)
			var jam_radius = 70
			if enemy.has_method("jam_radius"):
				jam_radius = enemy.jam_radius()
			if dist < jam_radius:
				return true
	return false


func _check_link_possible() -> bool:
	# For level 1: One preplaced, one player. Both must exist.
	var total_transceivers = _player_units.duplicate()
	for t in _transceivers:
		if t not in total_transceivers:
			total_transceivers.append(t)
	if total_transceivers.size() < 2:
		return false

	# For each transceiver, check if link is possible (not in detection/jam)
	for u in total_transceivers:
		for e in _enemy_units:
			if _unit_in_detection_zone(u, e):
				return false
		if _unit_is_jammed(u):
			return false
	return true


func _check_detection() -> void:
	for unit in _player_units:
		for enemy in _enemy_units:
			if _unit_in_detection_zone(unit, enemy):
				_player_detected = true
				return


func _unit_in_detection_zone(unit: Node, enemy: Node) -> bool:
	var dist = unit.global_position.distance_to(enemy.global_position)
	var detection_radius = 100
	if enemy.has_method("detection_radius"):
		detection_radius = enemy.detection_radius()
	return dist < detection_radius


func _check_jamming() -> void:
	for unit in _player_units:
		for enemy in _enemy_units:
			if enemy.has_method("is_jammer") and enemy.is_jammer():
				var dist = unit.global_position.distance_to(enemy.global_position)
				var jam_radius = 70
				if enemy.has_method("jam_radius"):
					jam_radius = enemy.jam_radius()
				if dist < jam_radius:
					_jammed = true
					return


func _show_scoreboard(success: bool = true) -> void:
	var score = _calculate_score(success)
	var minutes = int(_completion_time) / 60
	var seconds = int(_completion_time) % 60

	var popup = SILENT_LINK_INTRO_POPUP.instantiate()
	if success:
		popup.title_string = "Mission Successful!"
		popup.body_string = (
			"[i]Link established![/i]\n\n"
			+ "[b]Time:[/b] %d:%02d\n" % [minutes, seconds]
			+ "[b]Score:[/b] %d\n" % score
		)

	if success and _current_level < MAX_LEVEL:
		popup.button_string = "Next Level"
	else:
		popup.button_string = "Finish"

	var cl := CanvasLayer.new()
	cl.layer = 101
	add_child(cl)
	cl.add_child(popup)

	if _current_level < MAX_LEVEL:
		popup.continue_button.pressed.connect(_on_next_level_pressed)
	else:
		popup.continue_button.pressed.connect(_on_finish_pressed)


func _calculate_score(success: bool = true) -> int:
	if not success:
		return 0

	var time_penalty = int(_completion_time)
	var frequency_penalty = 0
	var stealth_bonus = 0

	for unit in _player_units:
		var freq = unit.frequency
		# figure out distance penalty
		if freq < 2:
			frequency_penalty += 200
		elif freq > 2:
			frequency_penalty += 200

	if not _player_detected:
		stealth_bonus += 1000

	if not _jammed:
		stealth_bonus += 500

	return max(1000, 10000 - time_penalty * 100 - frequency_penalty + stealth_bonus)


func _on_next_level_pressed() -> void:
	_current_level += 1
	set_process(false)
	set_physics_process(false)

	if _current_level > MAX_LEVEL:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return

	get_tree().change_scene_to_file("res://scenes/silent-link/level-%d.tscn" % _current_level)


func _on_finish_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
