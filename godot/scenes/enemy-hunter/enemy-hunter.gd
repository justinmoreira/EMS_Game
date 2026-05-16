extends ContourDemo

# Enemy Hunter Mode Controller - Event-driven state machine matching TutorialController structure

const ENEMY_HUNTER_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const ENEMY_HUNTER_HINT := preload("res://scenes/ui/HintPopup.tscn")

# Range-hint noise: ± this many pixels so the ring isn't perfectly accurate
const RANGE_HINT_NOISE_PX := 40.0
const MAX_LEVEL := 5

enum Step { WELCOME, HUNTING, COMPLETE }

var _step: Step = Step.WELCOME
var _intro_popup_open := false
var _detected_transceivers: Array[int] = []  # fully revealed
var _hinted_transceivers: Array[int] = []  # hints revealed
var _jammed_transceivers: Array[int] = []
var _start_time: float = 0.0
var _completion_time: float = 0.0
var _timer_label: Label = null
var _total_transceivers: int = 0
var _hud: Node = null
var _reveal_button: Button = null
var _current_level: int = 1

# Overlay node that draws direction arrows and range rings
var _hint_overlay: _DetectionHintOverlay = null


# Draws all active detection hints via _draw()
class _DetectionHintOverlay:
	extends Node2D

	# Each entry: { sensor_pos, transceiver_pos, tier }
	# tier: "wide" | "medium"  (narrow entries are never stored, they reveal directly)
	var hints: Array[Dictionary] = []

	func add_hint(sensor_pos: Vector2, transceiver_pos: Vector2, tier: String) -> void:
		# Avoid duplicate hints for the same transceiver position
		for h in hints:
			if h.transceiver_pos.distance_to(transceiver_pos) < 4.0:
				# Upgrade tier if there is a better reading
				if tier == "medium" and h.tier == "wide":
					h.tier = "medium"
					queue_redraw()
				return
		hints.append({"sensor_pos": sensor_pos, "transceiver_pos": transceiver_pos, "tier": tier})
		queue_redraw()

	func remove_hints_for(transceiver_pos: Vector2) -> void:
		hints = hints.filter(func(h): return h.transceiver_pos.distance_to(transceiver_pos) >= 4.0)
		queue_redraw()

	func _draw() -> void:
		for h in hints:
			var s: Vector2 = h.sensor_pos
			var t: Vector2 = h.transceiver_pos
			var dir := (t - s).normalized()
			var dist := s.distance_to(t)

			match h.tier:
				"wide":
					_draw_direction_arrow(s, dir)
				"medium":
					_draw_direction_arrow(s, dir)
					_draw_range_ring(s, dist)

	# Dashed arrow pointing from sensor toward transceiver
	func _draw_direction_arrow(origin: Vector2, dir: Vector2) -> void:
		var arrow_len := 80.0
		var tip := origin + dir * arrow_len
		var color := Color(1.0, 0.85, 0.1, 0.85)  # golden yellow

		# Dashed line
		var dash_len := 10.0
		var gap_len := 6.0
		var travelled := 0.0
		var drawing := true
		while travelled < arrow_len - 12.0:
			var seg: float = min(dash_len if drawing else gap_len, arrow_len - 12.0 - travelled)
			if drawing:
				draw_line(origin + dir * travelled, origin + dir * (travelled + seg), color, 2.5)
			travelled += seg
			drawing = not drawing

		# Arrow
		var perp := Vector2(-dir.y, dir.x)
		draw_line(tip, tip - dir * 12.0 + perp * 6.0, color, 2.5)
		draw_line(tip, tip - dir * 12.0 - perp * 6.0, color, 2.5)

	# Circle ring at approximate range from sensor
	func _draw_range_ring(center: Vector2, radius: float) -> void:
		# Add noise so the ring isn't a perfect giveaway
		var noisy_r := radius + randf_range(-RANGE_HINT_NOISE_PX, RANGE_HINT_NOISE_PX)
		noisy_r = max(noisy_r, 20.0)

		var color := Color(0.3, 0.85, 1.0, 0.55)
		var segments := 48
		var dash_segs := 3
		var pattern := [true, true, true, false, false]

		for i in range(segments):
			if not pattern[i % pattern.size()]:
				continue
			var a0 := (float(i) / segments) * TAU
			var a1 := (float(i + 1) / segments) * TAU
			draw_line(
				center + Vector2(cos(a0), sin(a0)) * noisy_r,
				center + Vector2(cos(a1), sin(a1)) * noisy_r,
				color,
				2.0
			)


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
	_hint_overlay = _DetectionHintOverlay.new()
	add_child(_hint_overlay)

	_count_transceivers()
	_start()


func _process(_delta: float) -> void:
	if _step == Step.HUNTING and _timer_label:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed


func _count_transceivers() -> void:
	_total_transceivers = get_tree().get_nodes_in_group("transceivers").size()
	print("Enemy Hunter: Found %d transceivers to hunt" % _total_transceivers)


func _start() -> void:
	if _intro_popup_open:
		return
	_intro_popup_open = true

	var popup := ENEMY_HUNTER_INTRO_POPUP.instantiate()
	popup.title_string = "Enemy Hunter Mode - Level %d" % _current_level
	popup.body_string = (
		"Find and jam all hidden transceivers on the map.\n\n"
		+ "[i]• Wide-band sweep -> direction hint\n"
		+ "• Mid-band sweep -> direction + range ring\n"
		+ "• Narrow-band tune -> full reveal\n\n"
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
	match _step:
		Step.WELCOME:
			_step = Step.HUNTING
			_start_time = Time.get_ticks_msec() / 1000.0
			_show_timer_and_reveal()
			_show_hint(
				(
					"Hunt down all %d transceivers!\n" % _total_transceivers
					+ "Use wide/medium band to locate them,\nthen narrow band to reveal and jam."
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

		if tx_id not in _detected_transceivers:
			_detected_transceivers.append(tx_id)

		_hint_overlay.remove_hints_for(transceiver.global_position)

		_reveal_transceiver(transceiver)

	# Disable button after use
	if _reveal_button:
		_reveal_button.disabled = true
		_reveal_button.text = "Revealed"


func _check_victory() -> void:
	if _step != Step.HUNTING:
		return

	if (
		_detected_transceivers.size() == _total_transceivers
		and _jammed_transceivers.size() == _total_transceivers
	):
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
		print("Campaign complete!")
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return

	get_tree().change_scene_to_file("res://scenes/enemy-hunter/level-%d.tscn" % _current_level)


func _on_simulation_complete(link_results: Array, detect_results: Array) -> void:
	# Prevent link lines from presenting on simulate
	_clear_link_visuals()

	for r in link_results:
		print(r)
	if _step != Step.HUNTING:
		return

	for detect_result in detect_results:
		if not detect_result is Dictionary:
			continue

		var sensor = detect_result.get("sensor")
		var transceiver = detect_result.get("transceiver")
		var detected: bool = detect_result.get("detected", false)

		if not detected or not sensor or not transceiver:
			continue

		var tx_id: int = transceiver.get_instance_id()

		# Already revealed
		if tx_id in _detected_transceivers:
			continue

		# Determine detection tier from sensor bandwidth enum (0=narrow, 1=medium, 2=wide)
		var bw = sensor.get("sensor_bandwidth")
		var sensor_bw_enum: int = int(bw) if bw != null else 0
		var tier := _detection_tier_from_enum(sensor_bw_enum)

		match tier:
			"wide":
				_apply_wide_hint(sensor, transceiver, tx_id)

			"medium":
				_apply_medium_hint(sensor, transceiver, tx_id)

			"narrow":
				_apply_narrow_reveal(transceiver, tx_id)

	# Check for jammed transceivers
	# Process jamming results
	for result in link_results:
		if not result is Dictionary:
			continue

		var state: int = result.get("state", 0)

		# Not jammed
		if state != 3:
			continue

		var source = result.get("source")
		var target = result.get("target")

		for tx in [source, target]:
			if tx == null:
				continue

			var tx_id: int = tx.get_instance_id()

			if tx_id not in _jammed_transceivers:
				_jammed_transceivers.append(tx_id)

				print(
					(
						"Enemy Hunter: Transceiver jammed! (%d/%d)"
						% [_jammed_transceivers.size(), _total_transceivers]
					)
				)

	# Final win check
	_check_victory()


func _detection_tier_from_enum(bw_enum: int) -> String:
	match bw_enum:
		2:
			return "wide"  # direction hint only
		1:
			return "medium"  # direction + range ring
		_:
			return "narrow"  # full reveal


func _apply_wide_hint(sensor: Node, transceiver: Node, tx_id: int) -> void:
	if tx_id in _hinted_transceivers:
		return
	_hinted_transceivers.append(tx_id)

	var sensor_pos: Vector2 = sensor.global_position
	var transceiver_pos: Vector2 = transceiver.global_position
	_hint_overlay.add_hint(sensor_pos, transceiver_pos, "wide")


func _apply_medium_hint(sensor: Node, transceiver: Node, tx_id: int) -> void:
	var sensor_pos: Vector2 = sensor.global_position
	var transceiver_pos: Vector2 = transceiver.global_position
	_hint_overlay.add_hint(sensor_pos, transceiver_pos, "medium")

	if tx_id not in _hinted_transceivers:
		_hinted_transceivers.append(tx_id)


func _apply_narrow_reveal(transceiver: Node, tx_id: int) -> void:
	_detected_transceivers.append(tx_id)

	# Remove hints
	_hint_overlay.remove_hints_for(transceiver.global_position)

	_reveal_transceiver(transceiver)


func _check_jammed() -> void:
	for transceiver in get_tree().get_nodes_in_group("transceivers"):
		var tx_id: int = transceiver.get_instance_id()
		if (
			tx_id in _detected_transceivers
			and tx_id not in _jammed_transceivers
			and transceiver.has_method("is_jammed")
			and transceiver.is_jammed()
		):
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


func _reveal_transceiver(transceiver: Node) -> void:
	if transceiver.has_method("reveal"):
		transceiver.reveal()
		return
	transceiver.show()
	transceiver.modulate.a = 1.0
	if transceiver.has_node("Sprite2D"):
		var sprite := transceiver.get_node("Sprite2D")
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
