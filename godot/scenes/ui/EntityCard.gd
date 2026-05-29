extends PanelContainer

signal pressed

const ICON_RADIUS := 20.0
const ICON_FONT_SIZE := 18
const PREVIEW_RADIUS := 32.0
const PREVIEW_FONT_SIZE := 25

var entity_type: int
var entity_label: String  # "T", "J", "S"
var accent_color: Color
var scene_path: String
var display_name: String
var _sprite_path: String = ""

# Optional callable; returns Dictionary of attributes to apply on drop.
# Set by Sidebar so the drag payload carries pending attributes without
# BaseLevel having to reach into Sidebar.
var pending_provider: Callable

# Style colors (matched from Sidebar)
var _bg_normal: Color
var _bg_hover: Color


func setup(
	p_type: int,
	p_label: String,
	p_accent: Color,
	p_scene_path: String,
	p_display_name: String,
	bg_normal: Color,
	bg_hover: Color,
	p_sprite_path: String = ""
) -> void:
	entity_type = p_type
	entity_label = p_label
	accent_color = p_accent
	scene_path = p_scene_path
	display_name = p_display_name
	_bg_normal = bg_normal
	_bg_hover = bg_hover
	_sprite_path = p_sprite_path


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_normal_style()

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	var icon := _IconDraw.new()
	icon.radius = ICON_RADIUS
	icon.font_size = ICON_FONT_SIZE
	icon.label = entity_label
	icon.color = accent_color
	icon.custom_minimum_size = Vector2(ICON_RADIUS * 2, ICON_RADIUS * 2)
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.sprite_path = _sprite_path
	hbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", accent_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(name_label)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit()


func mouse_entered_handler() -> void:
	_apply_hover_style()


func mouse_exited_handler() -> void:
	_apply_normal_style()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_apply_hover_style()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_apply_normal_style()


func _apply_normal_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = _bg_normal
	s.set_border_color(accent_color)
	s.set_border_width_all(0)
	s.border_width_top = 2
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.set_content_margin_all(6)
	add_theme_stylebox_override("panel", s)


func _apply_hover_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = _bg_hover
	s.set_border_color(accent_color)
	s.set_border_width_all(0)
	s.border_width_top = 2
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.set_content_margin_all(6)
	add_theme_stylebox_override("panel", s)


# ── Drag-and-drop ──────────────────────────


func _get_drag_data(_at_position: Variant) -> Variant:
	var icon := _IconDraw.new()
	icon.radius = PREVIEW_RADIUS
	icon.font_size = PREVIEW_FONT_SIZE
	icon.label = entity_label
	icon.color = accent_color
	icon.modulate.a = 0.5
	icon.position = Vector2(-PREVIEW_RADIUS, -PREVIEW_RADIUS)
	icon.custom_minimum_size = Vector2(PREVIEW_RADIUS * 2, PREVIEW_RADIUS * 2)
	icon.sprite_path = _sprite_path

	var preview := Control.new()
	preview.add_child(icon)
	set_drag_preview(preview)

	var override: Dictionary = pending_provider.call() if pending_provider else {}
	return {"type": entity_type, "scene_path": scene_path, "attributes_override": override}


# ── Inner class: draws a circle + letter ───


class _IconDraw:
	extends TextureRect
	var radius := 20.0
	var font_size := 18
	var label := "T"
	var color := Color.WHITE
	var sprite_path := ""

	func _ready() -> void:
		if sprite_path and ResourceLoader.exists(sprite_path):
			texture = load(sprite_path)
			expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			stretch_mode = TextureRect.STRETCH_SCALE
		else:
			# Use a custom drawing control for fallback
			pass

	func _draw() -> void:
		if not texture:
			# Fallback to circle with letter
			var center := Vector2(radius, radius)
			draw_circle(center, radius, Color(color, 0.8))
			draw_arc(center, radius, 0, TAU, 32, color, 1.5)

			var font := ThemeDB.fallback_font
			var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var offset := center + Vector2(-text_size.x / 2.0, text_size.y / 4.0)
			draw_string(font, offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
