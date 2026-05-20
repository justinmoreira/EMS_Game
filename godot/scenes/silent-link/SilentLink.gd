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

# Gameplay entities
var _player_units: Array = []
var _enemy_units: Array = []
var _transceivers: Array = []
var _scene_ready := false


func _ready() -> void:
	super._ready()
	# Extract scene level from scene name
	var level_name := get_tree().current_scene.scene_file_path
	var file_name := level_name.get_file().get_basename()
	var parts := file_name.split("-")
	if parts.size() > 1:
		_current_level = int(parts[1])
	else:
		_current_level = 1

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
	popup.button_string = "Start Planning"

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
			_show_timer()
			_show_hint(
				"Drag and place your units to establish a silent link between the transceivers."
			)
		Step.PLANNING:
			# Wait for player to finish unit placement (linked to your placement UI)
			pass
		Step.SIMULATING:
			# Start simulation, check detection/jamming every frame
			_start_time = Time.get_ticks_msec() / 1000.0
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


func _begin_simulation() -> void:
	if _step != Step.PLANNING:
		return
	_step = Step.SIMULATING
	_advance()


# Call this from your placement UI
func on_player_units_placed(player_units: Array) -> void:
	_player_units = player_units
	_show_hint("When ready, press 'Begin Link' to attempt the connection.")
	# Show "Begin Link" button in your interface that triggers _begin_simulation()


func _process(_delta: float) -> void:
	if _step == Step.SIMULATING and _timer_label:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed
		_check_detection()
		_check_jamming()
		if _link_established:
			_finish(true)
		elif _player_detected or _jammed:
			_finish(false)


func _simulate_link() -> void:
	if _check_link_possible():
		# Link is possible, wait for process/detection checks to finish the round
		pass
	else:
		_show_hint("Link not possible - check your placements!")
		_finish(false)


func _check_link_possible() -> bool:
	# Placeholder: return true if player placed at least 2 units and not overlapping enemies
	if _player_units.size() < 2:
		return false
	for unit in _player_units:
		for enemy in _enemy_units:
			if _unit_in_detection_zone(unit, enemy):
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


func _finish(success: bool) -> void:
	_completion_time = Time.get_ticks_msec() / 1000.0 - _start_time
	_step = Step.COMPLETE
	_show_scoreboard(success)


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
	else:
		popup.title_string = "Link Interrupted"
		popup.body_string = (
			"[i]Your link was detected or jammed.[/i]\n\n"
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
		if unit.has("frequency") and unit.has("target_pos"):
			var freq = unit.frequency
			var dist = unit.global_position.distance_to(unit.target_pos)
			if dist < 100 and freq < 2:
				frequency_penalty += 200
			elif dist > 400 and freq > 2:
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
