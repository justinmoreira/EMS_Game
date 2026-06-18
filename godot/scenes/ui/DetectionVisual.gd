extends Node2D
class_name DetectionVisual

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

func _ready():
	var hud = get_tree().get_root().find_child("HUD", true, false)

	if hud and hud.has_method("set_spectrum_enabled"):
		hud.set_spectrum_enabled(true)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
		for h in hints:
			var pulse := sin(_time * PULSE_SPEED) * PULSE_AMPLITUDE

			var blue_r := PRESENCE_RADIUS1 + pulse
			var blue_c := Color(0.30, 0.70, 1.00, 1.00)

			_draw_ring(h.sensor_pos, blue_r, blue_c, CIRCLE_WIDTH)
			_draw_ripples(h.sensor_pos, PRESENCE_RADIUS1, blue_c)

			# Always directional now
			var dir: Vector2 = (h.transceiver_pos - h.sensor_pos).normalized()

			var orange_c := Color(1.0, 0.55, 0.05, 1.0)

			_draw_directional_ripples(
				h.sensor_pos,
				dir,
				orange_c,
				h.tx_id
			)

func set_hint(sensor_pos: Vector2, transceiver_pos: Vector2, tx_id: int) -> void:
	for h in hints:
		if h.tx_id == tx_id:
			h.sensor_pos = sensor_pos
			h.transceiver_pos = transceiver_pos
			queue_redraw()
			return

	hints.append(
		{
			"tx_id": tx_id,
			"sensor_pos": sensor_pos,
			"transceiver_pos": transceiver_pos,
		}
	)

	queue_redraw()

func retain_only(detected_tx_ids: Array[int]) -> void:
	var before := hints.size()
	hints = hints.filter(func(h): return h.tx_id in detected_tx_ids)
	if hints.size() != before:
		queue_redraw()

func remove_hints_for(transceiver_pos: Vector2) -> void:
	hints = hints.filter(func(h): return h.transceiver_pos.distance_to(transceiver_pos) >= 4.0)
	queue_redraw()

# Solid full circle ring
func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	for i in range(SEGMENTS):
		var a0 := (float(i) / SEGMENTS) * TAU
		var a1 := (float(i + 1) / SEGMENTS) * TAU
		draw_line(
			center + Vector2(cos(a0), sin(a0)) * radius,
			center + Vector2(cos(a1), sin(a1)) * radius,
			color,
			width
		)

# Solid arc spanning ±half_span_rad around base_angle
func _draw_arc(
	center: Vector2,
	radius: float,
	base_angle: float,
	half_span: float,
	color: Color,
	width: float
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
			color,
			width
		)

func _draw_directional_ripples(center: Vector2, dir: Vector2, color: Color, tx_id: int) -> void:
	var base_angle := dir.angle()
	var half_span := deg_to_rad(15.0)  # ±15° = 30° total cone
	var base_radius := PRESENCE_RADIUS2

	for i in range(RIPPLE_COUNT):
		# Stagger each ring by RIPPLE_INTERVAL; use tx_id to desync
		# multiple arcs so two transceivers don't pulse identically
		var offset := i * RIPPLE_INTERVAL + float(tx_id % 7) * 0.13
		var phase := fmod(_time + offset, RIPPLE_COUNT * RIPPLE_INTERVAL)
		var t := phase / (RIPPLE_COUNT * RIPPLE_INTERVAL)  # 0 → 1
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
