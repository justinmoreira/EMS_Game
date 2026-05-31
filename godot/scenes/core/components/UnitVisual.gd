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
var show_terrain_heatmap: bool = false
var show_range: bool = false


func _ready() -> void:
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


func set_show_terrain_heatmap(enabled: bool) -> void:
	show_terrain_heatmap = enabled
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

		#! BUG: Heatmap covers other units placed before
		if show_terrain_heatmap and is_selected and signal_rings.has("max_range"):
			var max_range_km = float(signal_rings["max_range"].get("radius_km", 0.0))
			if max_range_km > 0.0:
				_draw_terrain_heatmap(max_range_km)

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


func _draw_terrain_heatmap(max_range_km: float) -> void:
	var origin_world_position := global_position

	var max_cell_offset := int(ceil(max_range_km))
	var sample_grid := {}
	var parent_unit = get_parent()
	var z_tx = 0.0

	var terrain = get_tree().get_first_node_in_group("terrain") as ContourGen
	if parent_unit:
		z_tx = terrain.get_unit_total_height(parent_unit)
	else:
		z_tx = terrain.get_ground_height_at_pos(global_position)

	# TODO: what if we used polar coordinates, and just sampled along rays instead of a grid? not
	# TODO: for a visual reason but maybe we could reuse the same samples for range checks and
	# TODO: reduce redundant loss calcs? just a thought...
	for cx in range(-max_cell_offset, max_cell_offset + 1):
		for cy in range(-max_cell_offset, max_cell_offset + 1):
			var world_position = (
				origin_world_position + Vector2(cx, cy) * PhysicsEngine.PIXELS_PER_UNIT
			)
			# TODO: built heatmap first with TIF in mind instead of loss attenuation. They are
			# TODO: inverses but as a result this entire thing needs to be reworked to avoid
			# TODO: redundant calculations
			var tif = 1.0
			if (
				terrain.height_grid.size() > 0
				and terrain.map_scale.x != 0
				and terrain.grid_w > 0
				and terrain.grid_h > 0
			):
				# TODO: This is expensive (sorta)... we should cache this when units move/adjacent
				# TODO: units with similar properties overlap.
				var z_gnd = terrain.get_ground_height_at_pos(world_position)
				var z_rx = z_gnd + 1.0
				var loss = PhysicsEngine.compute_terrain_loss(
					global_position,
					world_position,
					z_tx,
					z_rx,
					terrain.height_grid,
					terrain.map_origin,
					terrain.map_scale
				)
				if loss >= 1e6:
					tif = 0.0
				else:
					tif = clamp(1.0 / loss, 0.0, 1.0)
			var strength = clamp(tif, 0.0, 1.0)
			sample_grid["%d,%d" % [cx, cy]] = strength

	# Normalize sample values
	var s_min := 1.0
	var s_max := 0.0
	for k in sample_grid.keys():
		var sample_value = sample_grid[k]
		s_min = min(s_min, sample_value)
		s_max = max(s_max, sample_value)

	if s_max <= s_min:
		s_min = 0.0
		s_max = 1.0

	var rndr_rad_px = max_range_km * PhysicsEngine.PIXELS_PER_UNIT
	var samples_per_km = 10
	var px_step = PhysicsEngine.PIXELS_PER_UNIT / float(samples_per_km)
	var rndr_half = rndr_rad_px
	var base_a = 0.55 if is_selected else 0.35
	var cell_diag_half = px_step * 0.70710678

	var px_step_cnt = int(max(1.0, px_step))
	for px_x in range(int(-rndr_half), int(rndr_half), px_step_cnt):
		for px_y in range(int(-rndr_half), int(rndr_half), px_step_cnt):
			var c_ctr_offset = Vector2(px_x + px_step * 0.5, px_y + px_step * 0.5)
			if c_ctr_offset.length() > rndr_rad_px + cell_diag_half:
				continue

			var grid_x0 = int(floor(c_ctr_offset.x / PhysicsEngine.PIXELS_PER_UNIT))
			var grid_y0 = int(floor(c_ctr_offset.y / PhysicsEngine.PIXELS_PER_UNIT))
			var grid_x1 = grid_x0 + 1
			var grid_y1 = grid_y0 + 1
			var offset_x = (c_ctr_offset.x / PhysicsEngine.PIXELS_PER_UNIT) - grid_x0
			var offset_y = (c_ctr_offset.y / PhysicsEngine.PIXELS_PER_UNIT) - grid_y0
			var key_x0_y0 = "%d,%d" % [grid_x0, grid_y0]
			var key_x1_y0 = "%d,%d" % [grid_x1, grid_y0]
			var key_x0_y1 = "%d,%d" % [grid_x0, grid_y1]
			var key_x1_y1 = "%d,%d" % [grid_x1, grid_y1]
			var sample_x0_y0 = 1.0
			var sample_value_x1_y0 = 1.0
			var sample_value_x0_y1 = 1.0
			var sample_value_x1_y1 = 1.0
			if sample_grid.has(key_x0_y0):
				sample_x0_y0 = sample_grid[key_x0_y0]
			else:
				var x = clamp(grid_x0, -max_cell_offset, max_cell_offset)
				var y = clamp(grid_y0, -max_cell_offset, max_cell_offset)
				var k = "%d,%d" % [x, y]
				if sample_grid.has(k):
					sample_x0_y0 = sample_grid[k]
			if sample_grid.has(key_x1_y0):
				sample_value_x1_y0 = sample_grid[key_x1_y0]
			else:
				var x = clamp(grid_x1, -max_cell_offset, max_cell_offset)
				var y = clamp(grid_y0, -max_cell_offset, max_cell_offset)
				var k = "%d,%d" % [x, y]
				if sample_grid.has(k):
					sample_value_x1_y0 = sample_grid[k]
			if sample_grid.has(key_x0_y1):
				sample_value_x0_y1 = sample_grid[key_x0_y1]
			else:
				var x = clamp(grid_x0, -max_cell_offset, max_cell_offset)
				var y = clamp(grid_y1, -max_cell_offset, max_cell_offset)
				var k = "%d,%d" % [x, y]
				if sample_grid.has(k):
					sample_value_x0_y1 = sample_grid[k]
			if sample_grid.has(key_x1_y1):
				sample_value_x1_y1 = sample_grid[key_x1_y1]
			else:
				var x = clamp(grid_x1, -max_cell_offset, max_cell_offset)
				var y = clamp(grid_y1, -max_cell_offset, max_cell_offset)
				var k = "%d,%d" % [x, y]
				if sample_grid.has(k):
					sample_value_x1_y1 = sample_grid[k]

			var interp_x0 = sample_x0_y0 + (sample_value_x1_y0 - sample_x0_y0) * offset_x
			var interp_x1 = (
				sample_value_x0_y1 + (sample_value_x1_y1 - sample_value_x0_y1) * offset_x
			)
			var interpolated_sample = interp_x0 + (interp_x1 - interp_x0) * offset_y
			var normalized_value = (interpolated_sample - s_min) / (s_max - s_min)
			var hue_value = clamp(normalized_value, 0.0, 1.0) * 0.3333333

			var draw_a = base_a
			var dist_ctr = c_ctr_offset.length()
			if dist_ctr > rndr_rad_px + cell_diag_half:
				continue

			var coverage = 1.0
			if dist_ctr > rndr_rad_px - cell_diag_half:
				# supersample edge cells to reduce aliasing artifacts
				# TODO: Use a mask
				var mask_samples = 5
				var inside_count = 0
				var inv_mask = 1.0 / float(mask_samples)
				for mask_x in range(mask_samples):
					for mask_y in range(mask_samples):
						var sample_point_x = (
							c_ctr_offset.x - px_step * 0.5 + (mask_x + 0.5) * (px_step * inv_mask)
						)
						var sample_point_y = (
							c_ctr_offset.y - px_step * 0.5 + (mask_y + 0.5) * (px_step * inv_mask)
						)
						if Vector2(sample_point_x, sample_point_y).length() <= rndr_rad_px:
							inside_count += 1
				coverage = float(inside_count) / float(mask_samples * mask_samples)

			if coverage <= 0.01:
				continue

			var hsv = Color.from_hsv(hue_value, 1.0, 1.0, draw_a * coverage)
			var blocked = Color(0.5, 0.02, 0.02, draw_a * coverage)
			var blend = clamp(normalized_value, 0.0, 1.0)
			var draw_color = Color(
				blocked.r + (hsv.r - blocked.r) * blend,
				blocked.g + (hsv.g - blocked.g) * blend,
				blocked.b + (hsv.b - blocked.b) * blend,
				blocked.a + (hsv.a - blocked.a) * blend,
			)

			# TODO: Turn this into a shader...
			draw_rect(
				Rect2(
					c_ctr_offset - Vector2(px_step * 0.5, px_step * 0.5), Vector2(px_step, px_step)
				),
				draw_color,
				true
			)
