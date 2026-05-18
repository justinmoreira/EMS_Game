extends ContourDemo

# Enemy Hunter Mode Controller - Event-driven state machine matching TutorialController structure

const ENEMY_HUNTER_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const ENEMY_HUNTER_HINT := preload("res://scenes/ui/HintPopup.tscn")

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

	var hints: Array[Dictionary] = []
	const PRESENCE_RADIUS1 := 18.0
	const PRESENCE_RADIUS2 := 60.0
	const PULSE_AMPLITUDE := 5.0
	const PULSE_SPEED := 3.5
	const RIPPLE_TRAVEL := 40.0
	const RIPPLE_COUNT := 3
	const RIPPLE_INTERVAL := 0.9
	const CIRCLE_WIDTH := 3.5
	const SEGMENTS := 48
	
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func set_hint(sensor_pos: Vector2, transceiver_pos: Vector2, tier: String, tx_id: int) -> void:
		for h in hints:
			if h.tx_id == tx_id:
				h.sensor_pos = sensor_pos
				h.transceiver_pos = transceiver_pos
				# Only upgrade tier, never downgrade
				if tier == "medium" and h.tier == "wide":
					h.tier = "medium"
				queue_redraw()
				return
		hints.append({
			"tx_id": tx_id,
			"sensor_pos": sensor_pos,
			"transceiver_pos": transceiver_pos,
			"tier": tier,
		})
		queue_redraw()
 
	func retain_only(detected_tx_ids: Array[int]) -> void:
		var before := hints.size()
		hints = hints.filter(func(h): return h.tx_id in detected_tx_ids)
		if hints.size() != before:
			queue_redraw()

	func remove_hints_for(transceiver_pos: Vector2) -> void:
		hints = hints.filter(func(h): return h.transceiver_pos.distance_to(transceiver_pos) >= 4.0)
		queue_redraw()

	func _draw() -> void:
		for h in hints:
			# Full pulsing circle (signal detected)
			var pulse := sin(_time * PULSE_SPEED) * PULSE_AMPLITUDE
			var blue_r := PRESENCE_RADIUS1 + pulse
			var blue_c := Color(0.30, 0.70, 1.00, 1.00)
			_draw_ring(h.sensor_pos, blue_r, blue_c, CIRCLE_WIDTH)
			_draw_ripples(h.sensor_pos, PRESENCE_RADIUS1, blue_c)
 
			# 30° pulsing arc per detected transceiver (directional)
			if h.tier == "medium":
				var dir :Vector2= (h.transceiver_pos - h.sensor_pos).normalized()
				var orange_c := Color(1.0, 0.55, 0.05, 1.0)
				_draw_directional_ripples(h.sensor_pos, dir, orange_c, h.tx_id)
 
	# Solid full circle ring
	func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
		for i in range(SEGMENTS):
			var a0 := (float(i) / SEGMENTS) * TAU
			var a1 := (float(i + 1) / SEGMENTS) * TAU
			draw_line(
				center + Vector2(cos(a0), sin(a0)) * radius,
				center + Vector2(cos(a1), sin(a1)) * radius,
				color, width
			)
 
	# Solid arc spanning ±half_span_rad around base_angle
	func _draw_arc(
		center: Vector2, radius: float, base_angle: float,
		half_span: float, color: Color, width: float
	) -> void:
		var steps := int(SEGMENTS * (half_span * 2.0 / TAU)) + 2
		steps = max(steps, 4)
		for i in range(steps):
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var a0 := base_angle - half_span + t0 * half_span * 2.0
			var a1 := base_angle - half_span + t1 * half_span * 2.0
			draw_line(
				center + Vector2(cos(a0), sin(a0)) * radius,
				center + Vector2(cos(a1), sin(a1)) * radius,
				color, width
			)
 

	func _draw_directional_ripples(
		center: Vector2, dir: Vector2, color: Color, tx_id: int
	) -> void:
		var base_angle := dir.angle()
		var half_span := deg_to_rad(15.0)   # ±15° = 30° total cone
		var base_radius := PRESENCE_RADIUS2
 
		for i in range(RIPPLE_COUNT):
			# Stagger each ring by RIPPLE_INTERVAL; use tx_id to desync
			# multiple arcs so two transceivers don't pulse identically
			var offset := i * RIPPLE_INTERVAL + float(tx_id % 7) * 0.13
			var phase := fmod(_time + offset, RIPPLE_COUNT * RIPPLE_INTERVAL)
			var t := phase / (RIPPLE_COUNT * RIPPLE_INTERVAL)   # 0 → 1
			var r := base_radius + t * RIPPLE_TRAVEL
			var alpha := (1.0 - t) * 0.80
			var width := lerpf(CIRCLE_WIDTH, 0.8, t)
			var arc_c := Color(color.r, color.g, color.b, 1.0)
			_draw_arc(center, r, base_angle, half_span, arc_c, width)
 
	# Staggered full-circle ripples
	func _draw_ripples(center: Vector2, base_radius: float, color: Color) -> void:
		for i in range(RIPPLE_COUNT):
			var phase := fmod(_time + i * RIPPLE_INTERVAL, RIPPLE_COUNT * RIPPLE_INTERVAL)
			var t := phase / (RIPPLE_COUNT * RIPPLE_INTERVAL)
			var r := base_radius + t * RIPPLE_TRAVEL
			var alpha := (1.0 - t) * 0.55
			var ripple_c := Color(color.r, color.g, color.b, 1.0)
			var width := lerpf(CIRCLE_WIDTH * 0.9, 0.5, t)
			_draw_ring(center, r, ripple_c, width)


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
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return

	get_tree().change_scene_to_file("res://scenes/enemy-hunter/level-%d.tscn" % _current_level)


func _on_simulation_complete(link_results: Array, detect_results: Array) -> void:
	_clear_link_visuals()
 
	if _step != Step.HUNTING:
		return
 
	# Collect which transceiver ids get a hint this simulation pass.
	# Any hint not refreshed means the sensor moved out of range — remove it.
	var hinted_this_sim: Array[int] = []
 
	for detect_result in detect_results:
		if not detect_result is Dictionary:
			continue
 
		var sensor      = detect_result.get("sensor")
		var transceiver = detect_result.get("transceiver")
		var detected: bool = detect_result.get("detected", false)
 
		if not detected or not sensor or not transceiver:
			continue
 
		var tx_id: int = transceiver.get_instance_id()
 
		if tx_id in _detected_transceivers:
			continue
 
		var bw = sensor.get("sensor_bandwidth")
		var bw_enum: int = int(bw) if bw != null else 0
		var tier := _detection_tier_from_enum(bw_enum)
 
		match tier:
			"wide":
				_apply_wide_hint(sensor, transceiver, tx_id)
				hinted_this_sim.append(tx_id)
			"medium":
				_apply_medium_hint(sensor, transceiver, tx_id)
				hinted_this_sim.append(tx_id)
			"narrow":
				_apply_narrow_reveal(transceiver, tx_id)
 
	# Drop any hints whose transceiver wasn't detected this round
	_hint_overlay.retain_only(hinted_this_sim)
 
	# Process jamming from link results
	for result in link_results:
		if not result is Dictionary:
			continue
 
		var state: int = result.get("state", 0)
		if state != 3:  # 3 = FAILED_JAMMED
			continue
 
		for tx in [result.get("source"), result.get("target")]:
			if tx == null:
				continue
			var tx_id: int = tx.get_instance_id()
			if tx_id not in _jammed_transceivers:
				_jammed_transceivers.append(tx_id)
 
	_check_victory()


func _detection_tier_from_enum(bw_enum: int) -> String:
	match bw_enum:
		2:
			return "wide"  # signal detected hint
		1:
			return "medium"  # signal detected + direction hint
		_:
			return "narrow"  # full reveal


func _apply_wide_hint(sensor: Node, transceiver: Node, tx_id: int) -> void:
	_hint_overlay.set_hint(sensor.global_position, transceiver.global_position, "wide", tx_id)
	if tx_id not in _hinted_transceivers:
		_hinted_transceivers.append(tx_id)
 
 
func _apply_medium_hint(sensor: Node, transceiver: Node, tx_id: int) -> void:
	_hint_overlay.set_hint(sensor.global_position, transceiver.global_position, "medium", tx_id)
	if tx_id not in _hinted_transceivers:
		_hinted_transceivers.append(tx_id)
 
 
func _apply_narrow_reveal(transceiver: Node, tx_id: int) -> void:
	_detected_transceivers.append(tx_id)
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
