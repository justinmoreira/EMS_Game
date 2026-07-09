class_name SpectrumAnalyzer extends Control

signal scan_started(lo: float, hi: float)
signal scan_complete

const FREQ_MIN := 30.0
const FREQ_MAX := 3000.0

const SECONDS_PER_MHZ := 0.01
const SCAN_MIN_DURATION := 0.4

# ---------------------------------------------------------------------------
# Layout: this widget is instantiated/freed on the fly and floats above (or
# below, if there's no room above) a selected sensor, so it has to fit its
# controls into a fixed 500x100 strip rather than the old fixed-panel HUD
# layout. Frequency now runs along the X axis (left = low, right = high,
# standard spectrum-analyzer convention) and power runs vertically (peaks go
# up). The header (status/buttons) and the bottom frequency-label strip each
# get their own reserved rows — the plot sits between them and doesn't
# overlap either.
# ---------------------------------------------------------------------------
const DEFAULT_WIDTH := 500.0
const DEFAULT_HEIGHT := 100.0

const HEADER_H := 22.0
const BOTTOM_LABEL_H := 16.0
const SIDE_MARGIN := 20.0

const TRACE_SAMPLES := 512
const SIGMA_BASE_MHZ := 25.0
const SIGMA_POWER := 5.0
const MAX_POWER := 8.0

const HANDLE_GRAB_PX := 10.0

const C_BG := Color(0.0, 0.0, 0.0, 0.0)
const C_PLOT := Color(0.08, 0.08, 0.08, 1.0)
const C_GRID := Color(0.30, 0.30, 0.30, 0.6)
const C_SCAN_RANGE := Color(0.20, 0.40, 0.80, 0.2)
const C_TRACE := Color(0.15, 0.60, 1.00, 0.9)
const C_SWEEP := Color(0.80, 0.80, 0.80, 0.6)
const C_HANDLE := Color(0.50, 0.50, 0.50, 0.8)
const C_HANDLE_HOT := Color(0.80, 0.80, 0.80, 1.0)
const C_LABEL := Color(1.0, 1.0, 1.0, 1.0)
const C_HEADER_BG := Color(0.0, 0.0, 0.0, 0.45)
const C_BORDER := Color(0.45, 0.45, 0.45, 0.9)
const C_BOTTOM_BG := Color(0.0, 0.0, 0.0, 0.85)
const BORDER_WIDTH := 1.5

const C_BTN := Color(0.15, 0.15, 0.15, 1.0)
const C_BTN_HOT := Color(0.25, 0.25, 0.25, 1.0)
const C_BTN_ACTIVE := Color(0.10, 0.30, 0.60, 1.0)
const C_BTN_TEXT := Color(0.90, 0.90, 0.90, 1.0)
const C_BTN_DISABLED := Color(0.10, 0.10, 0.10, 0.5)
const C_TXT_DISABLED := Color(0.40, 0.40, 0.40, 0.8)

enum SensorState { IDLE, SCANNING, COMPLETE, PAUSED }

var scan_lo: float = FREQ_MIN
var scan_hi: float = FREQ_MAX

var _sensor: Node = null
var _state: SensorState = SensorState.IDLE
var _elapsed: float = 0.0
var _duration: float = 0.0
var _progress: float = 0.0

var _spectrum := PackedFloat32Array()
var _sources: Array = []
var _jammers_rx: Array = []
var _noise_t := 0.0

var _drag_lo: bool = false
var _drag_hi: bool = false
var _hover_lo: bool = false
var _hover_hi: bool = false

var _btn_hover_left: bool = false
var _btn_down_left: bool = false
var _btn_hover_right: bool = false
var _btn_down_right: bool = false

var _font: Font


func _ready() -> void:
	GameEvents.confirm_pressed.connect(_on_settings_confirmed)
	_font = ThemeDB.fallback_font
	_spectrum.resize(TRACE_SAMPLES)
	_spectrum.fill(0.0)

	custom_minimum_size = Vector2(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	size = Vector2(DEFAULT_WIDTH, DEFAULT_HEIGHT)

	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

	if _sensor != null:
		_rebuild_sources()


func _exit_tree() -> void:
	# Persist scan progress
	_save_current_state()


func _process(delta: float) -> void:
	_noise_t += delta

	if _state == SensorState.SCANNING:
		_elapsed += delta
		var new_prog := clampf(_elapsed / _duration, 0.0, 1.0)
		var old_s := int(_progress * TRACE_SAMPLES)
		var new_s := int(new_prog * TRACE_SAMPLES)

		for s in range(old_s, new_s):
			var t := float(s) / float(TRACE_SAMPLES - 1)
			var freq := scan_lo + t * (scan_hi - scan_lo)

			_spectrum[s] = _sample_at(freq) + _noise_at(freq)

		_progress = new_prog
		if _progress >= 1.0:
			_state = SensorState.COMPLETE
			scan_complete.emit()

	queue_redraw()


func _on_settings_confirmed(unit: Node) -> void:
	if unit == _sensor:
		_rebuild_sources()


func configure(sensor: Node) -> void:
	if _sensor == sensor:
		return

	_save_current_state()

	_sensor = sensor
	if _sensor != null:
		_load_current_state()
		_rebuild_sources()
	else:
		_reset_scan()

	queue_redraw()


func _save_current_state() -> void:
	if _sensor != null and is_instance_valid(_sensor):
		_sensor.set_meta(
			"analyzer_state",
			{
				"state": _state,
				"elapsed": _elapsed,
				"progress": _progress,
				"spectrum": _spectrum.duplicate(),
				"scan_lo": scan_lo,
				"scan_hi": scan_hi,
				"duration": _duration
			}
		)


func _load_current_state() -> void:
	if _sensor.has_meta("analyzer_state"):
		var data = _sensor.get_meta("analyzer_state")
		_state = data.state
		_elapsed = data.elapsed
		_progress = data.progress
		_spectrum = data.spectrum.duplicate()
		scan_lo = data.scan_lo
		scan_hi = data.scan_hi
		_duration = data.duration
	else:
		_reset_scan()


func start_scan() -> void:
	if _state == SensorState.SCANNING or _sensor == null:
		return

	_rebuild_sources()
	_reset_scan()
	_duration = maxf(SCAN_MIN_DURATION, (scan_hi - scan_lo) * SECONDS_PER_MHZ)
	_state = SensorState.SCANNING
	scan_started.emit(scan_lo, scan_hi)


func _reset_scan() -> void:
	_state = SensorState.IDLE
	_elapsed = 0.0
	_progress = 0.0
	_spectrum.fill(0.0)


func _safe_get(obj: Object, prop: String, default_val: float) -> float:
	if obj == null:
		return default_val
	var val = obj.get(prop)
	if val != null:
		return float(val)
	return default_val


func _get_unit_spatial_data(unit: Node, terrain: Node) -> Dictionary:
	var px: Vector2 = (
		unit.get("global_position") if unit.get("global_position") != null else Vector2.ZERO
	)
	var z: float = _safe_get(unit, "height", 0.0)

	if terrain != null:
		var uv: Vector2
		if unit.has_meta("world_uv"):
			uv = unit.get_meta("world_uv")
		elif terrain.has_method("screen_to_world_uv"):
			uv = terrain.screen_to_world_uv(px)

		if terrain.has_method("world_uv_to_terrain_px"):
			px = terrain.world_uv_to_terrain_px(uv)
		if terrain.has_method("get_unit_total_height"):
			z = terrain.get_unit_total_height(unit)

	return {"px": px, "z": z}


func _rebuild_sources() -> void:
	_sources.clear()
	_jammers_rx.clear()

	if _sensor == null or not is_inside_tree():
		return

	var terrain = get_tree().get_first_node_in_group("terrain")
	var height_grid: Array = terrain.get("height_grid") if terrain else []
	if height_grid == null:
		height_grid = []
	var map_origin: Vector2 = terrain.get("map_origin") if terrain else Vector2.ZERO
	var map_scale: Vector2 = terrain.get("map_scale") if terrain else Vector2.ZERO

	var srx_data = _get_unit_spatial_data(_sensor, terrain)
	var srx_px: Vector2 = srx_data.px
	var z_rx: float = srx_data.z

	var sens = _safe_get(_sensor, "sensitivity", -75.0)
	var remap = remap(sens, -80.0, -70.0, 0.0, 10.0)
	var sens_norm = clampf(remap / 10.0, 0.0, 1.0)

	# 0.1x -> 25x gain
	var gain_multiplier = lerpf(0.1, 25.0, pow(sens_norm, 2.0))

	for tx in get_tree().get_nodes_in_group("transceivers"):
		var tx_data = _get_unit_spatial_data(tx, terrain)
		var tx_px = tx_data.px
		var z_tx = tx_data.z

		var freq = _safe_get(tx, "frequency", 1000.0)
		var power = _safe_get(tx, "power", 0.0)

		var dist = PhysicsEngine.calculate_distance(tx_px, srx_px)
		var terrain_loss := 1.0

		if terrain != null and height_grid.size() > 0:
			terrain_loss = PhysicsEngine.compute_terrain_loss(
				tx_px, srx_px, z_tx, z_rx, height_grid, map_origin, map_scale
			)

		var base_rx_power = (
			PhysicsEngine.TRANSCEIVER_BALANCE_RATIO
			* PhysicsEngine.calculate_received_power(power, z_tx, z_rx, freq, dist, terrain_loss)
		)

		# Apply the gain
		var rx_power = base_rx_power * gain_multiplier

		if rx_power >= 0.01:
			# As received power spikes, width expands exponentially
			var blowout_factor = pow(rx_power, 1.5)
			var sigma: float = SIGMA_BASE_MHZ + blowout_factor * SIGMA_POWER

			# Max sigma
			sigma = minf(sigma, 4000.0)

			_sources.append(
				{
					"freq": freq,
					"rx": rx_power,
					"two_s2": 2.0 * sigma * sigma,
					"blowout": blowout_factor
				}
			)

	for jammer in get_tree().get_nodes_in_group("jammers"):
		var j_data = _get_unit_spatial_data(jammer, terrain)
		var j_px = j_data.px
		var z_j = j_data.z

		var freq = _safe_get(jammer, "frequency", 1000.0)
		var power = _safe_get(jammer, "power", 0.0)

		var max_bw_idx = PhysicsEngine.BANDWIDTH_POWER.size() - 1
		var bw_idx = clampi(int(_safe_get(jammer, "jammer_bandwidth", 0.0)), 0, max_bw_idx)

		var dist = PhysicsEngine.calculate_distance(j_px, srx_px)
		var terrain_loss := 1.0
		if terrain != null and height_grid.size() > 0:
			terrain_loss = PhysicsEngine.compute_terrain_loss(
				j_px, srx_px, z_j, z_rx, height_grid, map_origin, map_scale
			)

		var base_rx_power = PhysicsEngine.calculate_received_power(
			power, z_j, z_rx, freq, dist, terrain_loss
		)

		var jammer_power_at_rx = (
			PhysicsEngine.JAMMER_BALANCE_RATIO
			* base_rx_power
			* PhysicsEngine.BANDWIDTH_POWER[bw_idx]
		)

		jammer_power_at_rx *= gain_multiplier

		if jammer_power_at_rx >= 0.01:
			var raw_amplified_power = (
				PhysicsEngine.JAMMER_BALANCE_RATIO * base_rx_power * gain_multiplier
			)
			var blowout_factor = pow(raw_amplified_power, 1.5)

			var bw_half = PhysicsEngine.BANDWIDTH_MHZ[bw_idx] / 2.0
			var jammer_width_scaler := 6.0
			var base_j_sigma = maxf(10.0, bw_half * jammer_width_scaler)

			var j_sigma = base_j_sigma + blowout_factor * SIGMA_POWER
			j_sigma = minf(j_sigma, 4000.0)

			_jammers_rx.append(
				{
					"freq": freq,
					"power": jammer_power_at_rx,
					"two_s2": 2.0 * j_sigma * j_sigma,
					"blowout": blowout_factor
				}
			)


func _sample_at(freq: float) -> float:
	var sum := 0.0
	for src in _sources:
		var d: float = freq - src.freq
		var power_mult := 1.0

		# Apply chaotic distortion if the signal is blowing out
		if src.blowout > 5.0:
			var dist_factor = minf(src.blowout, 100.0)

			var warp = sin(_noise_t * 25.0 + freq * 0.15) * (dist_factor * 0.8)
			var warp2 = cos(_noise_t * 12.0 - freq * 0.05) * (dist_factor * 0.4)
			d += warp + warp2

			power_mult = randf_range(0.6, 1.4)

		var curve = exp(-(d * d) / src.two_s2)
		sum += (src.rx * power_mult) * curve

	return sum


func _noise_at(freq: float) -> float:
	var sens = _safe_get(_sensor, "sensitivity", -75.0)
	var remap = remap(sens, -80.0, -70.0, 0.0, 10.0)
	var sens_norm = clampf(remap / 10.0, 0.0, 1.0)

	var noise_floor_base = lerpf(3.0, 0.1, sens_norm)
	var drift := sin(_noise_t * 5.0 + freq * 0.01) * 0.05
	var base_noise = maxf(0.01, noise_floor_base + drift)
	var floor_jitter := randf_range(0.5, 1.0)
	var final_baseline = base_noise * floor_jitter

	var jammer_noise := 0.0
	for j in _jammers_rx:
		var d: float = freq - j.freq
		var power_mult := 1.0

		# Chaotic distortion
		if j.blowout > 5.0:
			var dist_factor = minf(j.blowout, 100.0)

			var warp = sin(_noise_t * 25.0 + freq * 0.15) * (dist_factor * 0.8)
			var warp2 = cos(_noise_t * 12.0 - freq * 0.05) * (dist_factor * 0.4)
			d += warp + warp2

			power_mult = randf_range(0.6, 1.4)

		var curve = exp(-(d * d) / j.two_s2)
		jammer_noise += (j.power * power_mult * curve)

	return final_baseline + jammer_noise


func _plot_rect() -> Rect2:
	return Rect2(
		SIDE_MARGIN, HEADER_H, size.x - SIDE_MARGIN * 2.0, size.y - HEADER_H - BOTTOM_LABEL_H
	)


func _freq_to_x(f: float) -> float:
	var pr = _plot_rect()
	var t = (f - FREQ_MIN) / (FREQ_MAX - FREQ_MIN)
	return pr.position.x + t * pr.size.x


func _x_to_freq(x: float) -> float:
	var pr = _plot_rect()
	var t = (x - pr.position.x) / pr.size.x
	return clampf(FREQ_MIN + t * (FREQ_MAX - FREQ_MIN), FREQ_MIN, FREQ_MAX)


func _sweep_x() -> float:
	return lerpf(_freq_to_x(scan_lo), _freq_to_x(scan_hi), _progress)


func _draw() -> void:
	var pr := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)

	var middle_section := Rect2(0.0, HEADER_H, size.x, size.y - HEADER_H - BOTTOM_LABEL_H)
	draw_rect(middle_section, C_BOTTOM_BG)

	_draw_scan_range_bg(pr)
	_draw_grid(pr)
	_draw_spectrum(pr)
	_draw_sweep_cursor(pr)
	_draw_handles(pr)
	_draw_header()
	_draw_border()


func _draw_border() -> void:
	var outer := Rect2(0.0, 0.0, size.x, size.y)
	draw_rect(outer, C_BORDER, false, BORDER_WIDTH)


func _draw_scan_range_bg(pr: Rect2) -> void:
	var x_lo := clampf(_freq_to_x(scan_lo), pr.position.x, pr.position.x + pr.size.x)
	var x_hi := clampf(_freq_to_x(scan_hi), pr.position.x, pr.position.x + pr.size.x)
	draw_rect(Rect2(x_lo, pr.position.y, x_hi - x_lo, pr.size.y), C_SCAN_RANGE)


func _draw_grid(pr: Rect2) -> void:
	# Coarse horizontal reference lines (power divisions).
	for i in 4:
		var y := pr.position.y + pr.size.y * float(i) / 3.0
		draw_line(Vector2(pr.position.x, y), Vector2(pr.position.x + pr.size.x, y), C_GRID)

	# Backing bar behind the frequency-axis label strip, expanded to full width
	var label_y := pr.position.y + pr.size.y
	draw_rect(Rect2(0.0, label_y, size.x, BOTTOM_LABEL_H), C_BOTTOM_BG)

	# Vertical frequency gridlines + labels along the bottom.
	var step := _nice_step((FREQ_MAX - FREQ_MIN) / 6.0)
	var f: float = ceil(FREQ_MIN / step) * step
	while f <= FREQ_MAX:
		var x := _freq_to_x(f)
		draw_line(Vector2(x, pr.position.y), Vector2(x, pr.position.y + pr.size.y), C_GRID)

		var text := "%.0f" % f
		var text_pos := Vector2(x - 20.0, label_y + 13.0)

		draw_string_outline(
			_font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11, 2, Color.BLACK
		)

		draw_string(_font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11, C_LABEL)
		f += step


func _draw_spectrum(pr: Rect2) -> void:
	if _state == SensorState.IDLE:
		return
	var revealed := int(_progress * TRACE_SAMPLES)
	if revealed < 2:
		return

	var trace := PackedVector2Array()
	var x_start := _freq_to_x(scan_lo)
	var x_end := _freq_to_x(scan_hi)
	var x_span := x_end - x_start

	for s in revealed:
		var norm := clampf(_spectrum[s] / MAX_POWER, 0.0, 1.0)
		var x := x_start + float(s) / float(TRACE_SAMPLES - 1) * x_span
		var y := pr.position.y + pr.size.y - (norm * pr.size.y)
		trace.append(Vector2(x, y))

	for i in range(trace.size() - 1):
		draw_line(trace[i], trace[i + 1], C_TRACE, 1.5)


func _draw_sweep_cursor(pr: Rect2) -> void:
	if _state not in [SensorState.SCANNING, SensorState.PAUSED]:
		return
	var sx := _sweep_x()
	draw_line(Vector2(sx, pr.position.y), Vector2(sx, pr.position.y + pr.size.y), C_SWEEP, 2.0)


func _draw_handles(pr: Rect2) -> void:
	var top := pr.position.y
	var bottom := pr.position.y + pr.size.y
	_draw_one_handle(_freq_to_x(scan_lo), top, bottom, true, _hover_lo or _drag_lo)
	_draw_one_handle(_freq_to_x(scan_hi), top, bottom, false, _hover_hi or _drag_hi)


func _draw_one_handle(x: float, top: float, bottom: float, is_lo: bool, hot: bool) -> void:
	var col := C_HANDLE_HOT if hot else C_HANDLE
	draw_line(Vector2(x, top), Vector2(x, bottom), col, 1.5)

	var dir := 1.0 if is_lo else -1.0
	draw_polygon(
		PackedVector2Array(
			[
				Vector2(x, top + 5.0),
				Vector2(x + dir * 9.0, top + 13.0),
				Vector2(x, top + 21.0),
			]
		),
		PackedColorArray([col])
	)


func _get_btn_left_rect() -> Rect2:
	return Rect2(size.x - 136.0, 2.0, 62.0, HEADER_H - 4.0)


func _get_btn_right_rect() -> Rect2:
	return Rect2(size.x - 68.0, 2.0, 62.0, HEADER_H - 4.0)


func _draw_header() -> void:
	var can_scan := _sensor != null

	draw_rect(Rect2(0.0, 0.0, size.x, HEADER_H), C_BOTTOM_BG)

	var status_text := "STATUS: NO SENSOR"
	if can_scan:
		match _state:
			SensorState.IDLE:
				status_text = "STATUS: READY"
			SensorState.SCANNING:
				status_text = "SCANNING: %d%%" % int(_progress * 100.0)
			SensorState.PAUSED:
				status_text = "PAUSED: %d%%" % int(_progress * 100.0)
			SensorState.COMPLETE:
				status_text = "STATUS: COMPLETE"

	draw_string(
		_font,
		Vector2(8.0, HEADER_H - 6.0),
		status_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		280.0,
		11,
		Color.WHITE
	)

	if not can_scan:
		return

	var btn_1_rect := _get_btn_left_rect()
	var btn_2_rect := _get_btn_right_rect()

	if _state == SensorState.IDLE:
		_draw_button(btn_1_rect, "START", true, _btn_hover_left, _btn_down_left, false)

	elif _state == SensorState.SCANNING:
		_draw_button(btn_1_rect, "PAUSE", true, _btn_hover_left, _btn_down_left, false)
		_draw_button(btn_2_rect, "CANCEL", true, _btn_hover_right, _btn_down_right, false)

	elif _state == SensorState.PAUSED:
		_draw_button(btn_1_rect, "RESUME", true, _btn_hover_left, _btn_down_left, true)
		_draw_button(btn_2_rect, "CANCEL", true, _btn_hover_right, _btn_down_right, false)

	elif _state == SensorState.COMPLETE:
		_draw_button(btn_1_rect, "RESTART", true, _btn_hover_left, _btn_down_left, false)


func _draw_button(
	rect: Rect2,
	text: String,
	enabled: bool,
	hover: bool,
	pressed: bool,
	active: bool,
	font_size: int = 10
) -> void:
	var btn_col: Color
	var text_col: Color

	if not enabled:
		btn_col = C_BTN_DISABLED
		text_col = C_TXT_DISABLED
	elif pressed:
		btn_col = C_BTN_ACTIVE.lerp(Color.BLACK, 0.3)
		text_col = C_BTN_TEXT
	elif active:
		btn_col = C_BTN_ACTIVE
		text_col = C_BTN_TEXT
	elif hover:
		btn_col = C_BTN_HOT
		text_col = C_BTN_TEXT
	else:
		btn_col = C_BTN
		text_col = C_BTN_TEXT

	draw_rect(rect, btn_col)

	var str_size = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var tx = rect.position.x + (rect.size.x - str_size.x) / 2.0
	var ty = rect.position.y + (rect.size.y + str_size.y) / 2.0 - 2.0
	draw_string(_font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)


func _gui_input(event: InputEvent) -> void:
	var pr := _plot_rect()
	var lo_x := _freq_to_x(scan_lo)
	var hi_x := _freq_to_x(scan_hi)

	var btn_rect_1 := _get_btn_left_rect()
	var btn_rect_2 := _get_btn_right_rect()

	if event is InputEventMouseMotion:
		var mx: float = event.position.x
		var in_plot := pr.has_point(event.position)

		_hover_lo = in_plot and abs(mx - lo_x) <= HANDLE_GRAB_PX and not _drag_hi
		_hover_hi = in_plot and abs(mx - hi_x) <= HANDLE_GRAB_PX and not _drag_lo

		var hover_left = _btn_hover_left
		var hover_right = _btn_hover_right

		_btn_hover_left = btn_rect_1.has_point(event.position)
		_btn_hover_right = btn_rect_2.has_point(event.position)

		if hover_left != _btn_hover_left or hover_right != _btn_hover_right or in_plot:
			queue_redraw()

		if _drag_lo:
			scan_lo = clampf(_x_to_freq(mx), FREQ_MIN, scan_hi - 10.0)
			if _state != SensorState.IDLE:
				_reset_scan()
			accept_event()
		elif _drag_hi:
			scan_hi = clampf(_x_to_freq(mx), scan_lo + 10.0, FREQ_MAX)
			if _state != SensorState.IDLE:
				_reset_scan()
			accept_event()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if btn_rect_1.has_point(event.position) and _sensor != null:
				_btn_down_left = true
				if _state == SensorState.SCANNING:
					_state = SensorState.PAUSED
				elif _state == SensorState.PAUSED:
					_state = SensorState.SCANNING
				elif _state in [SensorState.IDLE, SensorState.COMPLETE]:
					start_scan()
				queue_redraw()
				accept_event()

			elif btn_rect_2.has_point(event.position) and _sensor != null:
				_btn_down_right = true
				if _state in [SensorState.SCANNING, SensorState.PAUSED]:
					_reset_scan()
				elif _state == SensorState.COMPLETE:
					start_scan()
				queue_redraw()
				accept_event()

			elif pr.has_point(event.position):
				var mx: float = event.position.x
				if abs(mx - lo_x) <= HANDLE_GRAB_PX and not _drag_hi:
					_drag_lo = true
					accept_event()
				elif abs(mx - hi_x) <= HANDLE_GRAB_PX and not _drag_lo:
					_drag_hi = true
					accept_event()
		else:
			_btn_down_left = false
			_btn_down_right = false
			_drag_lo = false
			_drag_hi = false
			queue_redraw()


func _nice_step(rough: float) -> float:
	if rough <= 0.0:
		return 1.0
	var mag := pow(10.0, floor(log(rough) / log(10.0)))
	var ratio := rough / mag
	if ratio < 2.0:
		return mag
	if ratio < 5.0:
		return 2.0 * mag
	return 5.0 * mag
