class_name ContourGen
extends BaseLevel

# ── Labelling knobs ───────────────────────────────────────────────────────────
## Minimum grid-cell radius between any two labels of the same type.
## Raise this if labels are still crowding each other.
const SUPPRESS_RADIUS_PEAK := 18  # cells
const SUPPRESS_RADIUS_VALLEY := 14  # cells

## A candidate is only a peak/valley if it is the strict extremum within this
## radius.  Larger = fewer, more prominent labels.
const LOCAL_WINDOW := 12  # cells (half-width of the dominance window)

## Height thresholds
const PEAK_MINOR_THRESH := 280.0  # m  →  small gold label
const VALLEY_MINOR_THRESH := 160.0  # m  →  small aqua label

## Pixel distance below which two labels are considered overlapping.
const OVERLAP_MARGIN := 40.0  # px

var grid_w: int = 150
var grid_h: int = 150
var cell_size: int = 8
var height_grid: Array = []

@onready var contour_rect: TextureRect = $BackgroundTexture
@onready var map_container = $BackgroundTexture


func _ready() -> void:
	if not contour_rect or not contour_rect.material:
		push_error("Ensure ContourOverlay exists and has a ShaderMaterial!")
		return

	height_grid = _generate_terrain(grid_w, grid_h)
	SimulationManager.set_terrain_data(
		height_grid, map_container.global_position, map_container.size
	)

	var tex := _create_height_texture(height_grid, grid_w, grid_h)
	contour_rect.material.set_shader_parameter("height_map", tex)

	# Terrain colors
	contour_rect.material.set_shader_parameter("color_low", Color(0.10, 0.60, 0.20, 1.0))  # green
	contour_rect.material.set_shader_parameter("color_mid", Color(0.76, 0.70, 0.50, 1.0))  # tan
	contour_rect.material.set_shader_parameter("color_high", Color(1.00, 1.00, 1.00, 1.0))  # snow

	# Water
	contour_rect.material.set_shader_parameter("water_color", Color(0.10, 0.30, 0.85, 1.0))
	contour_rect.material.set_shader_parameter("sea_level", 100.0)

	# Height scaling
	contour_rect.material.set_shader_parameter("max_height", 500.0)
	contour_rect.material.set_shader_parameter("mid_point", 0.6)

	_label_tactical_points(height_grid, grid_w, grid_h)


# ── Terrain generation ────────────────────────────────────────────────────────


func _generate_terrain(w: int, h: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.025
	noise.fractal_octaves = 3

	var g: Array = []
	for x in range(w):
		g.append([])
		for y in range(h):
			var n := noise.get_noise_2d(float(x), float(y))
			var h_m := (n + 1.0) * 0.5 * 500.0 # 0 – 500 m
			g[x].append(h_m)
	return g


# ── Main labelling entry point ────────────────────────────────────────────────


func _label_tactical_points(grid: Array, w: int, h: int) -> void:
	# Step 1 – collect raw candidates
	var peak_candidates: Array[Dictionary] = []
	var valley_candidates: Array[Dictionary] = []

	var half := LOCAL_WINDOW
	for x in range(half, w - half):
		for y in range(half, h - half):
			var val: float = grid[x][y]
			var is_peak := true
			var is_valley := true

			for dx in range(-half, half + 1):
				if not (is_peak or is_valley):
					break
				for dy in range(-half, half + 1):
					if dx == 0 and dy == 0:
						continue
					var nb: float = grid[x + dx][y + dy]
					if nb >= val:
						is_peak = false
					if nb <= val:
						is_valley = false

			if is_peak and val >= PEAK_MINOR_THRESH:
				peak_candidates.append({"x": x, "y": y, "val": val})
			elif is_valley and val <= VALLEY_MINOR_THRESH:
				valley_candidates.append({"x": x, "y": y, "val": val})

	# Step 2 – non-maximum suppression: keep only the strongest within radius
	var peaks := _suppress(peak_candidates, SUPPRESS_RADIUS_PEAK, true)
	var valleys := _suppress(valley_candidates, SUPPRESS_RADIUS_VALLEY, false)

	# Step 3 – convert grid positions to pixel positions
	var container_size: Vector2 = map_container.size
	var sx: float = container_size.x / float(w)
	var sy: float = container_size.y / float(h)

	# Collect label descriptors before spawning so we can deconflict
	var label_descs: Array[Dictionary] = []

	for p in peaks:
		(
			label_descs
			. append(
				{
					"px_pos": Vector2(p["x"] * sx, p["y"] * sy),
					"val": p["val"],
					"color": Color.WHITE,
					"font_size": 20,
					"val_h": p["val"],
				}
			)
		)

	for v in valleys:
		(
			label_descs
			. append(
				{
					"px_pos": Vector2(v["x"] * sx, v["y"] * sy),
					"val": v["val"],
					"color": Color.WHITE,
					"font_size": 20,
					"val_h": v["val"],
				}
			)
		)

	# Step 4 – pixel-space deconfliction (drop weaker overlapping labels)
	var kept := _deconflict(label_descs)

	# Step 5 – spawn
	await get_tree().process_frame
	for desc in kept:
		_spawn_label(desc)


# ── Non-maximum suppression ───────────────────────────────────────────────────
## Sorts candidates by value (strongest first for peaks, lowest for valleys),
## then greedily accepts each candidate only if no already-accepted candidate
## lies within `radius` grid cells.

func _suppress(
	candidates: Array[Dictionary], radius: int, higher_is_better: bool
) -> Array[Dictionary]:
	# Sort so the "best" candidate comes first
	candidates.sort_custom(
		func(a, b): return a["val"] > b["val"] if higher_is_better else a["val"] < b["val"]
	)
	var accepted: Array[Dictionary] = []
	var r2 := radius * radius
	for cand in candidates:
		var cx: int = cand["x"]
		var cy: int = cand["y"]
		var too_close := false
		for acc in accepted:
			var ddx: int = cx - int(acc["x"])
			var ddy: int = cy - int(acc["y"])
			if ddx * ddx + ddy * ddy < r2:
				too_close = true
				break
		if not too_close:
			accepted.append(cand)
	return accepted


# ── Pixel-space deconfliction ─────────────────────────────────────────────────
## After suppression the labels are well-spaced in grid space, but scaled
## pixel positions can still collide (especially at low resolutions).
## Drop the lower-significance label when two are within OVERLAP_MARGIN px.

func _deconflict(descs: Array[Dictionary]) -> Array[Dictionary]:
	# Sort by height descending so major labels win ties
	descs.sort_custom(func(a, b): return a["val"] > b["val"])

	var kept: Array[Dictionary] = []
	for desc in descs:
		var pos: Vector2 = desc["px_pos"]
		var blocked := false
		for k in kept:
			if pos.distance_to(k["px_pos"]) < OVERLAP_MARGIN:
				blocked = true
				break
		if not blocked:
			kept.append(desc)
	return kept


# ── Label spawning ────────────────────────────────────────────────────────────


func _spawn_label(desc: Dictionary) -> void:
	var lbl := Label.new()
	lbl.text = "%dm" % [int(desc["val_h"])]

	lbl.add_theme_color_override("font_color", desc["color"])
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_font_size_override("font_size", desc["font_size"])

	var font_sz: int = desc["font_size"]
	var sz := lbl.get_theme_font("font").get_string_size(
		lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz
	)
	lbl.size = sz

	var px: Vector2 = desc["px_pos"]
	var screen_pos: Vector2 = map_container.global_position + px
	lbl.set_meta("world_uv", screen_to_world_uv(screen_pos))
	lbl.set_meta("half_size", sz * 0.5)

	add_child(lbl)

	lbl.position = world_uv_to_screen(lbl.get_meta("world_uv")) - sz * 0.5


# ── Texture creation ──────────────────────────────────────────────


func update_shader() -> void:
	# override for label/unit positions
	super.update_shader()

	var map := get_map_size()
	var aspect := map.x / map.y
	var shader_offset := offset

	if aspect > 1.0:
		shader_offset.x /= aspect
	else:
		shader_offset.y /= aspect

	contour_rect.material.set_shader_parameter("offset", shader_offset)
	_reposition_labels()


func _reposition_labels() -> void:
	# Labels are children of BaseLevel (same as units), so world_uv_to_screen
	# gives positions directly in our local coordinate space.
	for child in get_children():
		if child is Label and child.has_meta("world_uv"):
			child.position = (
				world_uv_to_screen(child.get_meta("world_uv")) - child.get_meta("half_size")
			)


# ── Texture creation ──────────────────────────────────────────────────────────


func _create_height_texture(grid: Array, w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, Color(grid[x][y], 0, 0, 1.0))
	return ImageTexture.create_from_image(img)


# ── Shader / grid toggles ─────────────────────────────────────────────────────


func toggle_shader(enabled: bool) -> void:
	if not enabled:
		contour_rect.material.set_shader_parameter("gray_mode", true)
		contour_rect.material.set_shader_parameter("gray_mode_color", Color(0.5, 0.5, 0.5, 1.0))
	else:
		contour_rect.material.set_shader_parameter("gray_mode", false)
		contour_rect.material.set_shader_parameter("color_low", Color(0.10, 0.60, 0.20, 1.0))
		contour_rect.material.set_shader_parameter("color_mid", Color(0.76, 0.70, 0.50, 1.0))
		contour_rect.material.set_shader_parameter("color_high", Color(1.00, 1.00, 1.00, 1.0))
		contour_rect.material.set_shader_parameter("water_color", Color(0.10, 0.30, 0.85, 1.0))

	for child in get_children():
		if child is Label:
			child.visible = enabled


func toggle_grid(enabled: bool) -> void:
	contour_rect.material.set_shader_parameter("line_thickness", 1.0 if enabled else 0.0)
	for child in get_children():
		if child is Label:
			child.visible = enabled
