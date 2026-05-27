extends Node2D

# Animates a yellow dot traveling from sender to receiver over `delay` seconds.
# One pulse spawns per `message_dispatched` signal; the tween's completion
# callback frees the node, so cleanup is automatic. High z_index keeps the
# pulse above BaseLevel's BackgroundTexture (this is an autoload Node2D, so
# without explicit z it can render behind level geometry).

const PULSE_RADIUS := 10.0
const PULSE_COLOR := Color.YELLOW
const PULSE_Z_INDEX := 100
const PULSE_SEGMENTS := 20


func _ready() -> void:
	GameEvents.message_dispatched.connect(_on_dispatched)
	z_index = PULSE_Z_INDEX


func _on_dispatched(from_unit: Node, to_unit: Node, delay: float) -> void:
	var pulse := _make_pulse()
	pulse.global_position = from_unit.global_position
	add_child(pulse)
	var tween := create_tween()
	tween.tween_property(pulse, "global_position", to_unit.global_position, delay)
	tween.tween_callback(pulse.queue_free)


func _make_pulse() -> Polygon2D:
	var p := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(PULSE_SEGMENTS):
		var angle: float = i * TAU / PULSE_SEGMENTS
		pts.append(Vector2(cos(angle), sin(angle)) * PULSE_RADIUS)
	p.polygon = pts
	p.color = PULSE_COLOR
	p.z_index = PULSE_Z_INDEX
	return p
