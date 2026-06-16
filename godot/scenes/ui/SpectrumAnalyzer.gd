class_name SpectrumAnalyzer extends Control
## Vertical, barebones spectrum analyzer panel for sensor units.
## Computes actual physical received power and jammer interference.

signal scan_started(lo: float, hi: float)
signal scan_complete

# ── Frequency axis ─────────────────────────────────────────────────────────
const FREQ_MIN := 30.0
const FREQ_MAX := 3000.0

# ── Scan timing ────────────────────────────────────────────────────────────
const SECONDS_PER_MHZ := 0.01
const SCAN_MIN_DURATION := 0.4

# ── Layout ─────────────────────────────────────────────────────────────────
const HEADER_H := 40.0
const FOOTER_H := 10.0
const LEFT_MARGIN := 45.0

# ── Signal rendering ───────────────────────────────────────────────────────
const TRACE_SAMPLES := 512
const SIGMA_BASE_MHZ := 25.0
const SIGMA_POWER := 5.0
const MAX_POWER := 8.0

# ── Handle interaction ─────────────────────────────────────────────────────
const HANDLE_GRAB_PX := 12.0

# ── Palette ────────────────────────────────────────────────────────────────
const C_BG := Color(0.05, 0.05, 0.05, 0.95)
const C_PLOT := Color(0.08, 0.08, 0.08, 1.0)
const C_GRID := Color(0.30, 0.30, 0.30, 0.4)
const C_SCAN_RANGE := Color(0.20, 0.40, 0.80, 0.1)
const C_TRACE := Color(0.15, 0.60, 1.00, 0.9)
const C_SWEEP := Color(0.80, 0.80, 0.80, 0.6)
const C_HANDLE := Color(0.50, 0.50, 0.50, 0.8)
const C_HANDLE_HOT := Color(0.80, 0.80, 0.80, 1.0)
const C_LABEL := Color(0.60, 0.60, 0.60, 1.0)

# Button Colors
const C_BTN := Color(0.15, 0.15, 0.15, 1.0)
const C_BTN_HOT := Color(0.25, 0.25, 0.25, 1.0)
const C_BTN_ACTIVE := Color(0.10, 0.30, 0.60, 1.0)
const C_BTN_TEXT := Color(0.90, 0.90, 0.90, 1.0)
const C_BTN_DISABLED := Color(0.10, 0.10, 0.10, 0.5)
const C_TXT_DISABLED := Color(0.40, 0.40, 0.40, 0.8)

enum _State { IDLE, SCANNING, COMPLETE }

var scan_lo: float = FREQ_MIN
var scan_hi: float = FREQ_MAX

var _sensor: Node = null
var _state: _State = _State.IDLE
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

# Visual button states
var _btn_hover: bool = false
var _btn_down: bool = false

var _font: Font

# ==========================================================================
# Lifecycle
# ==========================================================================


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_spectrum.resize(TRACE_SAMPLES)
	_spectrum.fill(0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

	if _sensor != null:
		_rebuild_sources()


func _process(delta: float) -> void:
	_noise_t += delta

	if _state == _State.SCANNING:
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
			_state = _State.COMPLETE
			scan_complete.emit()

	queue_redraw()


# ==========================================================================
# Public API
# ==========================================================================


func configure(sensor: Node) -> void:
	# CRITICAL FIX: If the main game loop calls this every frame,
	# it won't interrupt an ongoing scan anymore.
	if _sensor == sensor:
		return

	_sensor = sensor
	_reset_scan()
	if is_inside_tree() and _sensor != null:
		_rebuild_sources()
	queue_redraw()


func start_scan() -> void:
	if _state == _State.SCANNING or _sensor == null:
		return

	_rebuild_sources()
	_reset_scan()
	_duration = maxf(SCAN_MIN_DURATION, (scan_hi - scan_lo) * SECONDS_PER_MHZ)
	_state = _State.SCANNING
	scan_started.emit(scan_lo, scan_hi)


# ==========================================================================
# Signal Math & Physics Engine Integration
# ==========================================================================


func _reset_scan() -> void:
	_state = _State.IDLE
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
	# Safely access terrain properties
	var height_grid: Array = terrain.get("height_grid") if terrain else []
	if height_grid == null:
		height_grid = []
	var map_origin: Vector2 = terrain.get("map_origin") if terrain else Vector2.ZERO
	var map_scale: Vector2 = terrain.get("map_scale") if terrain else Vector2.ZERO

	var srx_data = _get_unit_spatial_data(_sensor, terrain)
	var srx_px: Vector2 = srx_data.px
	var z_rx: float = srx_data.z

	# 1. Transceivers
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

		var rx_power = (
			PhysicsEngine.SENSOR_BALANCE_RATIO
			* PhysicsEngine.calculate_received_power(power, z_tx, z_rx, freq, dist, terrain_loss)
		)

		if rx_power >= 0.01:
			var sigma: float = SIGMA_BASE_MHZ + rx_power * SIGMA_POWER
			_sources.append({"freq": freq, "rx": rx_power, "two_s2": 2.0 * sigma * sigma})

	# 2. Jammers
	for jammer in get_tree().get_nodes_in_group("jammers"):
		var j_data = _get_unit_spatial_data(jammer, terrain)
		var j_px = j_data.px
		var z_j = j_data.z

		var freq = _safe_get(jammer, "frequency", 1000.0)
		var power = _safe_get(jammer, "power", 0.0)

		# CRITICAL FIX: Clamp array index so physics bounds won't crash the scanner loop
		var max_bw_idx = PhysicsEngine.BANDWIDTH_POWER.size() - 1
		var bw_idx = clampi(int(_safe_get(jammer, "jammer_bandwidth", 0.0)), 0, max_bw_idx)

		var dist = PhysicsEngine.calculate_distance(j_px, srx_px)
		var terrain_loss := 1.0
		if terrain != null and height_grid.size() > 0:
			terrain_loss = PhysicsEngine.compute_terrain_loss(
				j_px, srx_px, z_j, z_rx, height_grid, map_origin, map_scale
			)

		var rx_power = PhysicsEngine.calculate_received_power(
			power, z_j, z_rx, freq, dist, terrain_loss
		)
		var jammer_power_at_rx = (
			PhysicsEngine.JAMMER_BALANCE_RATIO * rx_power * PhysicsEngine.BANDWIDTH_POWER[bw_idx]
		)

		if jammer_power_at_rx >= 0.01:
			_jammers_rx.append(
				{
					"freq": freq,
					"bw_half": PhysicsEngine.BANDWIDTH_MHZ[bw_idx] / 2.0,
					"power": jammer_power_at_rx
				}
			)


func _sample_at(freq: float) -> float:
	var sum := 0.0
	for src in _sources:
		var d: float = freq - src.freq
		sum += src.rx * exp(-(d * d) / src.two_s2)
	return sum


func _noise_at(freq: float) -> float:
	var sens = _safe_get(_sensor, "sensitivity", 5.0)
	var base_threshold = lerpf(3.0, PhysicsEngine.NOISE_FLOOR, sens / 10.0)
	var drift := sin(_noise_t * 5.0 + freq * 0.01) * 0.05
	var base_noise = maxf(0.01, (base_threshold * 0.15) + drift)

	var jammer_noise := 0.0
	for j in _jammers_rx:
		if abs(freq - j.freq) <= j.bw_half:
			jammer_noise += j.power

	var total_noise = base_noise + jammer_noise
	var static_jitter := randf_range(0.2, 1.0)
	return total_noise * static_jitter


# ==========================================================================
# Coordinate mapping
# ==========================================================================


func _get_btn_rect() -> Rect2:
	# Single source of truth for the button boundary
	return Rect2(5.0, 5.0, maxf(10.0, size.x - 10.0), HEADER_H - 10.0)


func _plot_rect() -> Rect2:
	return Rect2(LEFT_MARGIN, HEADER_H, size.x - LEFT_MARGIN, size.y - HEADER_H - FOOTER_H)


func _freq_to_y(f: float) -> float:
	var pr = _plot_rect()
	var t = (f - FREQ_MIN) / (FREQ_MAX - FREQ_MIN)
	return pr.position.y + pr.size.y - (t * pr.size.y)


func _y_to_freq(y: float) -> float:
	var pr = _plot_rect()
	var t = (pr.position.y + pr.size.y - y) / pr.size.y
	return clampf(FREQ_MIN + t * (FREQ_MAX - FREQ_MIN), FREQ_MIN, FREQ_MAX)


func _sweep_y() -> float:
	return lerpf(_freq_to_y(scan_lo), _freq_to_y(scan_hi), _progress)


# ==========================================================================
# Drawing
# ==========================================================================


func _draw() -> void:
	var pr := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	draw_rect(pr, C_PLOT)

	_draw_scan_range_bg(pr)
	_draw_grid(pr)
	_draw_spectrum(pr)
	_draw_sweep_cursor(pr)
	_draw_handles(pr)
	_draw_header()


func _draw_scan_range_bg(pr: Rect2) -> void:
	var y_hi := clampf(_freq_to_y(scan_hi), pr.position.y, pr.position.y + pr.size.y)
	var y_lo := clampf(_freq_to_y(scan_lo), pr.position.y, pr.position.y + pr.size.y)
	draw_rect(Rect2(pr.position.x, y_hi, pr.size.x, y_lo - y_hi), C_SCAN_RANGE)


func _draw_grid(pr: Rect2) -> void:
	for i in 4:
		var x := pr.position.x + pr.size.x * float(i) / 3.0
		draw_line(Vector2(x, pr.position.y), Vector2(x, pr.position.y + pr.size.y), C_GRID)

	var step := _nice_step((FREQ_MAX - FREQ_MIN) / 10.0)
	var f: float = ceil(FREQ_MIN / step) * step
	while f <= FREQ_MAX:
		var y := _freq_to_y(f)
		draw_line(Vector2(pr.position.x, y), Vector2(size.x, y), C_GRID)
		draw_string(
			_font, Vector2(5.0, y + 4.0), "%.0f" % f, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_LABEL
		)
		f += step


func _draw_spectrum(pr: Rect2) -> void:
	if _state == _State.IDLE:
		return
	var revealed := int(_progress * TRACE_SAMPLES)
	if revealed < 2:
		return

	var trace := PackedVector2Array()
	var y_start := _freq_to_y(scan_lo)
	var y_end := _freq_to_y(scan_hi)
	var y_span := y_end - y_start

	for s in revealed:
		var norm := clampf(_spectrum[s] / MAX_POWER, 0.0, 1.0)
		var y := y_start + float(s) / float(TRACE_SAMPLES - 1) * y_span
		var x := pr.position.x + (norm * pr.size.x)
		trace.append(Vector2(x, y))

	for i in range(trace.size() - 1):
		draw_line(trace[i], trace[i + 1], C_TRACE, 1.5)


func _draw_sweep_cursor(pr: Rect2) -> void:
	if _state != _State.SCANNING:
		return
	var sy := _sweep_y()
	draw_line(Vector2(pr.position.x, sy), Vector2(pr.position.x + pr.size.x, sy), C_SWEEP, 2.0)


func _draw_handles(pr: Rect2) -> void:
	var left := pr.position.x
	var right := pr.position.x + pr.size.x
	_draw_one_handle(_freq_to_y(scan_lo), left, right, true, _hover_lo or _drag_lo)
	_draw_one_handle(_freq_to_y(scan_hi), left, right, false, _hover_hi or _drag_hi)


func _draw_one_handle(y: float, left: float, right: float, is_lo: bool, hot: bool) -> void:
	var col := C_HANDLE_HOT if hot else C_HANDLE
	draw_line(Vector2(left, y), Vector2(right, y), col, 1.5)

	var dir := -1.0 if is_lo else 1.0
	draw_polygon(
		PackedVector2Array(
			[
				Vector2(left + 5.0, y),
				Vector2(left + 13.0, y + dir * 9.0),
				Vector2(left + 21.0, y),
			]
		),
		PackedColorArray([col])
	)


func _draw_header() -> void:
	var btn_rect = _get_btn_rect()
	var can_scan := _sensor != null
	var scanning := _state == _State.SCANNING

	var btn_col: Color
	var text_col: Color
	var text: String

	if not can_scan:
		btn_col = C_BTN_DISABLED
		text_col = C_TXT_DISABLED
		text = "START SCAN"
	elif scanning:
		btn_col = C_BTN_ACTIVE
		text_col = C_BTN_TEXT
		text = "SCANNING... %d%%" % int(_progress * 100.0)  # Feedback!
	elif _btn_down:
		btn_col = C_BTN_ACTIVE.lerp(Color.BLACK, 0.3)
		text_col = C_BTN_TEXT
		text = "START SCAN"
	else:
		btn_col = C_BTN_HOT if _btn_hover else C_BTN
		text_col = C_BTN_TEXT
		text = "START SCAN"

	draw_rect(btn_rect, btn_col)
	draw_string(
		_font,
		Vector2(btn_rect.position.x + 10.0, btn_rect.position.y + 18.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		text_col
	)


# ==========================================================================
# Input
# ==========================================================================


func _gui_input(event: InputEvent) -> void:
	var pr := _plot_rect()
	var lo_y := _freq_to_y(scan_lo)
	var hi_y := _freq_to_y(scan_hi)

	if event is InputEventMouseMotion:
		var my: float = event.position.y
		var in_plot := pr.has_point(event.position)

		_hover_lo = in_plot and abs(my - lo_y) <= HANDLE_GRAB_PX and not _drag_hi
		_hover_hi = in_plot and abs(my - hi_y) <= HANDLE_GRAB_PX and not _drag_lo

		var was_hover = _btn_hover
		_btn_hover = _get_btn_rect().has_point(event.position)

		# Redraw if hover states shift
		if was_hover != _btn_hover or in_plot:
			queue_redraw()

		if _drag_lo:
			scan_lo = clampf(_y_to_freq(my), FREQ_MIN, scan_hi - 10.0)
			if _state != _State.IDLE:
				_reset_scan()
			accept_event()
		elif _drag_hi:
			scan_hi = clampf(_y_to_freq(my), scan_lo + 10.0, FREQ_MAX)
			if _state != _State.IDLE:
				_reset_scan()
			accept_event()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _get_btn_rect().has_point(event.position):
				_btn_down = true
				queue_redraw()
				if _sensor != null:
					start_scan()
				accept_event()
			elif pr.has_point(event.position):
				var my: float = event.position.y
				if abs(my - lo_y) <= HANDLE_GRAB_PX and not _drag_hi:
					_drag_lo = true
					accept_event()
				elif abs(my - hi_y) <= HANDLE_GRAB_PX and not _drag_lo:
					_drag_hi = true
					accept_event()
		else:
			if _btn_down:
				_btn_down = false
				queue_redraw()
			_drag_lo = false
			_drag_hi = false


# ==========================================================================
# Utilities
# ==========================================================================


func _nice_step(rough: float) -> float:
	if rough <= 0.0:
		return 1.0
	var mag := pow(10.0, floor(log(rough) / log(10.0)))
	var ratio := rough / mag
	if ratio < 2.0:
		return mag
	elif ratio < 5.0:
		return 2.0 * mag
	else:
		return 5.0 * mag
