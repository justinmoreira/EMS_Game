class_name UnitVisual
extends Node2D

const RADIUS := 32.0
const FONT_SIZE := 25
const NAME_FONT_SIZE := 12  # Smaller font for name
const SIGNAL_RANGE_FONT_SIZE := 14

# Set these in the Inspector per unit type
@export var unit_label: String = "T"  # "T", "J", or "S"
@export var circle_color: Color = Color("4fc3f7")  # match sidebar accent
@export var sprite_sheet_path: String = ""  # Path to sprite sheet
@export var frame_width: int = 974  # 3896 / 4 columns
@export var frame_height: int = 970  # 2910 / 3 rows
@export var animation_speed: float = 12.0  # Frames per second
var unit_name: String = ""  # Unit name

@export var is_selected: bool = false
@export var is_hovered: bool = false
var _animated_sprite: AnimatedSprite2D

var signal_rings: Dictionary = {}
var show_range: bool = true


func _ready() -> void:
	name = "Visual"
	if sprite_sheet_path and ResourceLoader.exists(sprite_sheet_path):
		_setup_animated_sprite()
	else:
		_setup_fallback_circle()


func set_hovered(hovered: bool) -> void:
	is_hovered = hovered
	queue_redraw()


func _setup_animated_sprite() -> void:
	_animated_sprite = AnimatedSprite2D.new()
	_animated_sprite.position = Vector2.ZERO
	add_child(_animated_sprite)

	# Load the sprite sheet
	var texture = load(sprite_sheet_path)

	# Create an animation
	var sprite_frames = SpriteFrames.new()
	sprite_frames.add_animation("idle")

	# Add all 12 frames (4 columns x 3 rows)
	for row in range(3):
		for col in range(4):
			var atlas_texture = AtlasTexture.new()
			atlas_texture.atlas = texture
			atlas_texture.region = Rect2(
				col * frame_width, row * frame_height, frame_width, frame_height
			)
			sprite_frames.add_frame("idle", atlas_texture)

	# Set animation speed
	sprite_frames.set_animation_loop("idle", true)
	_animated_sprite.sprite_frames = sprite_frames
	_animated_sprite.animation = "idle"
	_animated_sprite.speed_scale = animation_speed / 6.0
	_animated_sprite.play()

	# Center and scale
	_animated_sprite.centered = true
	_animated_sprite.scale = Vector2(0.05, 0.05)


func _setup_fallback_circle() -> void:
	queue_redraw()


func set_selected(selected: bool) -> void:
	is_selected = selected
	queue_redraw()


func set_signal_rings(kv: Dictionary) -> void:
	signal_rings = kv.duplicate()
	queue_redraw()


func set_ring(key: String, radius_km: float, label: String = "") -> void:
	signal_rings[key] = {"radius_km": radius_km, "label": label}
	queue_redraw()


func update_ring_value(key: String, radius_km: float) -> void:
	if signal_rings.has(key):
		signal_rings[key]["radius_km"] = radius_km
		queue_redraw()


func remove_ring(key: String) -> void:
	if signal_rings.has(key):
		signal_rings.erase(key)
		queue_redraw()


func clear_rings() -> void:
	# Remove all rings
	signal_rings.clear()
	queue_redraw()


func set_show_range(enabled: bool) -> void:
	show_range = enabled
	queue_redraw()


func _sort_keys_by_radius_desc(a, b) -> int:
	var ra = signal_rings[a].get("radius_km", 0.0)
	var rb = signal_rings[b].get("radius_km", 0.0)
	if ra == rb:
		return 0
	return -1 if ra > rb else 1


func _draw() -> void:
	var font := ThemeDB.fallback_font

	# Draw selection corners if selected
	if is_selected or is_hovered:
		var corner_length := 12.0
		var offset := RADIUS
		var color := Color(1, 1, 0, 0.8 if is_selected else 0.5)
		var thickness := 1.0

		# Top-left corner
		draw_line(
			Vector2(-offset, -offset),
			Vector2(-offset + corner_length, -offset),
			color,
			thickness,
			true
		)
		draw_line(
			Vector2(-offset, -offset),
			Vector2(-offset, -offset + corner_length),
			color,
			thickness,
			true
		)

		# Top-right corner
		draw_line(
			Vector2(offset, -offset),
			Vector2(offset - corner_length, -offset),
			color,
			thickness,
			true
		)
		draw_line(
			Vector2(offset, -offset),
			Vector2(offset, -offset + corner_length),
			color,
			thickness,
			true
		)

		# Bottom-left corner
		draw_line(
			Vector2(-offset, offset),
			Vector2(-offset + corner_length, offset),
			color,
			thickness,
			true
		)
		draw_line(
			Vector2(-offset, offset),
			Vector2(-offset, offset - corner_length),
			color,
			thickness,
			true
		)

		# Bottom-right corner
		draw_line(
			Vector2(offset, offset), Vector2(offset - corner_length, offset), color, thickness, true
		)
		draw_line(
			Vector2(offset, offset), Vector2(offset, offset - corner_length), color, thickness, true
		)

		if show_range and signal_rings.size() > 0:
			var keys = signal_rings.keys()
			keys.sort_custom(Callable(self, "_sort_keys_by_radius_desc"))

			for key in keys:
				var ring = signal_rings[key]
				var radius_km = ring.get("radius_km", 0.0)
				if radius_km <= 0.0:
					continue

				var rendered_radius = radius_km * PhysicsEngine.PIXELS_PER_UNIT
				var range_fill := Color(0.8, 0.8, 0.8, 0.15 if is_selected else 0.05)
				var range_stroke := Color(0.8, 0.8, 0.8, 0.5 if is_selected else 0.35)
				var stroke_w := 4 if is_selected else 2

				draw_circle(Vector2.ZERO, rendered_radius, range_fill, true)
				draw_arc(Vector2.ZERO, rendered_radius, 0, TAU, 64, range_stroke, stroke_w, true)

				if is_selected:
					var label_text = ring.get("label", "")
					if label_text == "":
						label_text = str(key)

					# Walks down from km to m, and eventually snaps to nearest 25m for close ranges
					if radius_km >= 3.0:
						label_text += ": " + str(int(radius_km)) + " km"
					elif radius_km >= 1.0:
						label_text += ": " + str(snapped(radius_km * 1000, 100.0)) + " m"
					else:
						label_text += ": " + str(snapped(radius_km * 1000, 25.0)) + " m"

					var label_size := font.get_string_size(
						label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIGNAL_RANGE_FONT_SIZE
					)
					var label_pos := Vector2(
						-label_size.x / 2.0, -rendered_radius - label_size.y + 12.0
					)
					var text_color := Color(1, 1, 1, 1.0)
					draw_string(
						font,
						label_pos,
						label_text,
						HORIZONTAL_ALIGNMENT_LEFT,
						-1,
						SIGNAL_RANGE_FONT_SIZE,
						text_color
					)

	if not _animated_sprite:
		draw_circle(Vector2.ZERO, RADIUS, Color(circle_color, 0.8))
		draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, circle_color, 1.5)
		var text_size := font.get_string_size(unit_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var offset := Vector2(-text_size.x / 2.0, text_size.y / 4.0)
		draw_string(font, offset, unit_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)

	# Draw unit name above the unit
	if unit_name != "":
		var name_text_size := font.get_string_size(
			unit_name, HORIZONTAL_ALIGNMENT_CENTER, -1, NAME_FONT_SIZE
		)
		var name_offset := Vector2(-name_text_size.x / 2.0, -RADIUS - 5)
		draw_string(
			font,
			name_offset,
			unit_name,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			NAME_FONT_SIZE,
			Color.WHITE
		)
