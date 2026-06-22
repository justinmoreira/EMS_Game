extends ContourGen

# Enemy Hunter Mode Controller - Event-driven state machine matching TutorialController structure

const ENEMY_HUNTER_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const ENEMY_HUNTER_HINT := preload("res://scenes/ui/HintPopup.tscn")

const MAX_LEVEL := 5

enum Step { WELCOME, HUNTING, COMPLETE }

var _step: Step = Step.WELCOME
var _intro_popup_open := false
var _detected_emitters: Array[int] = []  # fully revealed
var _hinted_transceivers: Array[int] = []  # hints revealed
var _jammed_transceivers: Array[int] = []
var _start_time: float = 0.0
var _completion_time: float = 0.0
var _timer_label: Label = null
var _total_transceivers: int = 0
var _total_jammers: int = 0
var _hud: Node = null
var _reveal_button: Button = null
var _current_level: int = 1

# Overlay node that draws direction arrows and range rings
var _hint_overlay: DetectionVisual = null


func _ready() -> void:
	super._ready()

	# Extract scene level from scene name
	var level_name := get_tree().current_scene.scene_file_path
	_current_level = level_name.get_file().get_basename().split("-")[1].to_int()

	GameEvents.simulation_complete.connect(_on_simulation_complete)

	var hud_nodes = get_tree().get_nodes_in_group("hud")
	if hud_nodes.size() > 0:
		_hud = hud_nodes[0]

	# Create the hint overlay and add it above the game world
	_hint_overlay = DetectionVisual.new()
	add_child(_hint_overlay)

	_count_units()
	_start()


func _process(_delta: float) -> void:
	if _step == Step.HUNTING and _timer_label:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed


func _count_units() -> void:
	_total_transceivers = get_tree().get_nodes_in_group("transceivers").size()
	_total_jammers = get_tree().get_nodes_in_group("jammers").size()


func _start() -> void:
	if _intro_popup_open:
		return
	_intro_popup_open = true

	var popup := ENEMY_HUNTER_INTRO_POPUP.instantiate()
	popup.title_string = "Enemy Hunter Mode - Level %d" % _current_level
	popup.body_string = (
		"Find and jam all hidden transceivers on the map.\n\n"
		+ "[i]• Utilize the frequency spectrum analyzer to detect signals above the noise floor\n"
		+ "• Direction hints point toward emitters\n"
		+ "• Fully detect transceivers to reveal them\n\n"
		+ "Jam every transceiver as fast as you can![/i]"
	)
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
	var jammers_script = ""
	if _total_jammers == 1:
		jammers_script = "Avoid the spoof emission from a jammer,\n"
	elif _total_jammers > 0:
		jammers_script = "Avoid all spoof emissions from %d jammers,\n" % _total_jammers

	match _step:
		Step.WELCOME:
			_step = Step.HUNTING
			_start_time = Time.get_ticks_msec() / 1000.0
			_show_timer_and_reveal()
			_show_hint(
				(
					"Hunt down all %d transceivers!\n" % _total_transceivers
					+ jammers_script
					+ "Detect signals above the noise floor,\n"
					+ "reveal the transmitters, then jam them."
				)
			)

		Step.HUNTING:
			pass

		Step.COMPLETE:
			_show_scoreboard()


func _show_timer_and_reveal() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 500
	add_child(canvas)

	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

	canvas.add_child(ui)

	# Timer
	_timer_label = Label.new()
	_timer_label.text = "Time: 0.0s"
	_timer_label.add_theme_font_size_override("font_size", 24)

	# Bottom right
	_timer_label.anchor_left = 1.0
	_timer_label.anchor_top = 1.0
	_timer_label.anchor_right = 1.0
	_timer_label.anchor_bottom = 1.0

	_timer_label.offset_left = -220
	_timer_label.offset_top = -90
	_timer_label.offset_right = -20
	_timer_label.offset_bottom = -50

	ui.add_child(_timer_label)

	# Reveal button
	_reveal_button = Button.new()
	_reveal_button.text = "Reveal"
	_reveal_button.custom_minimum_size = Vector2(140, 42)

	_reveal_button.mouse_filter = Control.MOUSE_FILTER_STOP

	# Bottom right below timer
	_reveal_button.anchor_left = 1.0
	_reveal_button.anchor_top = 1.0
	_reveal_button.anchor_right = 1.0
	_reveal_button.anchor_bottom = 1.0

	_reveal_button.offset_left = -160
	_reveal_button.offset_top = -45
	_reveal_button.offset_right = -20
	_reveal_button.offset_bottom = -5

	_reveal_button.pressed.connect(_on_reveal_pressed)

	ui.add_child(_reveal_button)


func _on_reveal_pressed() -> void:
	for transceiver in get_tree().get_nodes_in_group("transceivers"):
		var tx_id: int = transceiver.get_instance_id()

		if tx_id not in _detected_emitters:
			_detected_emitters.append(tx_id)

		_hint_overlay.remove_hints_for(transceiver.global_position)

		_reveal_unit(transceiver)

	for jammer in get_tree().get_nodes_in_group("jammers"):
		var tx_id: int = jammer.get_instance_id()

		if tx_id not in _detected_emitters:
			_detected_emitters.append(tx_id)

		_hint_overlay.remove_hints_for(jammer.global_position)

		_reveal_unit(jammer)

	# Disable button after use
	if _reveal_button:
		_reveal_button.disabled = true
		_reveal_button.text = "Revealed"


func _check_victory() -> void:
	if _step != Step.HUNTING:
		return

	if _jammed_transceivers.size() == _total_transceivers:
		_completion_time = Time.get_ticks_msec() / 1000.0 - _start_time

		# Stop timer updates
		_step = Step.COMPLETE

		_advance()


func _show_hint(text: String) -> void:
	var popup := ENEMY_HUNTER_HINT.instantiate()
	popup.hint_text = text
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(popup)


func _show_scoreboard() -> void:
	var score := _calculate_score()
	var minutes := int(_completion_time) / 60
	var seconds := int(_completion_time) % 60

	var popup := ENEMY_HUNTER_INTRO_POPUP.instantiate()
	if _current_level < MAX_LEVEL:
		popup.button_string = "Next Level"
	else:
		popup.button_string = "Finish"
	popup.title_string = "Mission Complete!"
	popup.body_string = (
		"[i]All %d transceivers jammed![/i]\n\n" % _total_transceivers
		+ "[b]Time:[/b] %d:%02d\n" % [minutes, seconds]
		+ "[b]Score:[/b] %d\n" % score
	)

	var cl := CanvasLayer.new()
	cl.layer = 101
	add_child(cl)
	cl.add_child(popup)

	if _current_level < MAX_LEVEL:
		popup.button_string = "Next Level"
	else:
		popup.button_string = "Finish"

	popup.continue_button.pressed.connect(_on_next_level_pressed)


func _on_next_level_pressed() -> void:
	_current_level += 1

	set_process(false)
	set_physics_process(false)

	if _current_level > MAX_LEVEL:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return

	get_tree().change_scene_to_file("res://scenes/enemy-hunter/level-%d.tscn" % _current_level)


func _on_simulation_complete(link_results: Array, detect_results: Array) -> void:
	_clear_link_visuals()

	if _step != Step.HUNTING:
		return

	var hinted_this_sim: Array[int] = []

	# ── Detection Processing ───────────────────────────────
	for detect_result in detect_results:
		if not detect_result is Dictionary:
			continue

		var sensor = detect_result.get("sensor")
		var target = detect_result.get("target")
		var target_type = detect_result.get("target_type")

		if not sensor or not target:
			continue

		var tx_id: int = target.get_instance_id()

		# Signal exists above noise floor
		var detected: bool = detect_result.get("detected", false)

		if detected:
			_hint_overlay.set_hint(sensor.global_position, target.global_position, tx_id)

			hinted_this_sim.append(tx_id)

			if tx_id not in _hinted_transceivers:
				_hinted_transceivers.append(tx_id)

		# Fully resolved transceiver
		var fully_detected: bool = detect_result.get("fully_detected", false)

		if fully_detected:
			_detected_emitters.append(tx_id)

			_hint_overlay.remove_hints_for(target.global_position)

			_reveal_unit(target)

	# Remove stale hints
	_hint_overlay.retain_only(hinted_this_sim)

	# ── Jamming Processing ────────────────────────────────
	for result in link_results:
		if not result is Dictionary:
			continue

		var state: int = result.get("state", 0)

		if state != 3:  # FAILED_JAMMED
			continue

		for tx in [result.get("source"), result.get("target")]:
			if tx == null:
				continue

			var tx_id: int = tx.get_instance_id()

			if tx_id not in _jammed_transceivers:
				_jammed_transceivers.append(tx_id)

	_check_victory()


## Returns the node's global position, falling back to Vector2.ZERO if unavailable.
func _world_pos(node: Node) -> Vector2:
	if node is Node2D:
		return node.global_position
	return Vector2.ZERO


func _calculate_score() -> int:
	var time_penalty := int(_completion_time)
	return max(1000, 10000 - time_penalty * 100)


func _reveal_unit(unit: Node) -> void:
	if unit.has_method("reveal"):
		unit.reveal()
		return
	unit.show()
	unit.modulate.a = 1.0
	if unit.has_node("Sprite2D"):
		var sprite := unit.get_node("Sprite2D")
		sprite.show()
		sprite.modulate.a = 1.0


func _clear_link_visuals() -> void:
	if LinkRenderer.has_method("clear_all"):
		LinkRenderer.clear_all()


func _generate_terrain(w: int, h: int) -> Array:
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
