class_name UnitVisual
extends Node2D

const RADIUS := 32.0
const FONT_SIZE := 25

# Set these in the Inspector per unit type
@export var unit_label: String = "T"  # "T", "J", or "S"
@export var circle_color: Color = Color("4fc3f7")  # match sidebar accent
@export var sprite_sheet_path: String = ""  # Path to sprite sheet
@export var frame_width: int = 974  # 3896 / 4 columns
@export var frame_height: int = 970  # 2910 / 3 rows
@export var animation_speed: float = 12.0  # Frames per second

var is_selected: bool = false
var _animated_sprite: AnimatedSprite2D


func _ready() -> void:
	name = "Visual"
	if sprite_sheet_path and ResourceLoader.exists(sprite_sheet_path):
		_setup_animated_sprite()
	else:
		_setup_fallback_circle()


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


func _draw() -> void:
	# Draw selection corners if selected
	if is_selected:
		var corner_length := 8.0
		var offset := RADIUS
		var color := Color.YELLOW
		var thickness := 2.0
		
		# Top-left corner
		draw_line(Vector2(-offset, -offset), Vector2(-offset + corner_length, -offset), color, thickness)
		draw_line(Vector2(-offset, -offset), Vector2(-offset, -offset + corner_length), color, thickness)
		
		# Top-right corner
		draw_line(Vector2(offset, -offset), Vector2(offset - corner_length, -offset), color, thickness)
		draw_line(Vector2(offset, -offset), Vector2(offset, -offset + corner_length), color, thickness)
		
		# Bottom-left corner
		draw_line(Vector2(-offset, offset), Vector2(-offset + corner_length, offset), color, thickness)
		draw_line(Vector2(-offset, offset), Vector2(-offset, offset - corner_length), color, thickness)
		
		# Bottom-right corner
		draw_line(Vector2(offset, offset), Vector2(offset - corner_length, offset), color, thickness)
		draw_line(Vector2(offset, offset), Vector2(offset, offset - corner_length), color, thickness)

	if not _animated_sprite:
		draw_circle(Vector2.ZERO, RADIUS, Color(circle_color, 0.8))
		draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, circle_color, 1.5)
		var font := ThemeDB.fallback_font
		var text_size := font.get_string_size(unit_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var offset := Vector2(-text_size.x / 2.0, text_size.y / 4.0)
		draw_string(font, offset, unit_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)
