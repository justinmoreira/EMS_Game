class_name Sandbox
extends BaseLevel

const SANDBOX_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")

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

var map_scale: Vector2
var map_origin: Vector2
var grid_w: int = 150
var grid_h: int = 150
var cell_size: int = 8
var height_grid: Array = []
var _terrain_seed: int = 0

var _sandbox_popup_open := false

@onready var contour_rect: TextureRect = $BackgroundTexture
@onready var map_container = $BackgroundTexture


func _ready() -> void:
	if not contour_rect or not contour_rect.material:
		push_error("Ensure ContourOverlay exists and has a ShaderMaterial!")
		return

	# Runs BaseLevel init: offsets the background past the sidebar, hooks window
	# resize, and pushes initial shader params. Safe now that overlay/terrain
	# coordinate math shares one source of truth (background rect) — the sway
	# this used to cause was the aspect desync, now fixed.
	add_to_group("terrain")

	super._ready()
	
	_init_terrain()

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

	if get_script() == Sandbox:
		open_popup()


func _init_terrain() -> void:
	if _terrain_seed == 0:
		_terrain_seed = randi()
	_regenerate_terrain()


func _regenerate_terrain() -> void:
	height_grid = _generate_terrain(grid_w, grid_h, _terrain_seed)
	set_terrain_data(height_grid)

	_update_terrain_transform()

	var tex := _create_height_texture(height_grid, grid_w, grid_h)
	contour_rect.material.set_shader_parameter("height_map", tex)

	call_deferred("_label_tactical_points", height_grid, grid_w, grid_h)


func get_terrain_seed() -> int:
	return _terrain_seed

func set_terrain_seed(value: int) -> void:
	_terrain_seed = value
	_regenerate_terrain()
	

func open_popup() -> void:
	if _sandbox_popup_open:
		return
	_sandbox_popup_open = true

	var popup := SANDBOX_INTRO_POPUP.instantiate()
	popup.title_string = "Sandbox Mode"
	popup.body_string = (
		"Welcome to Sandbox Mode.\n\n"
		+ "Sandbox Mode is a free-play environment where you can experiment "
		+ "with electromagnetic warfare systems.\n\n"
		+ "Place transceivers, jammers, and sensors anywhere on the map and "
		+ "adjust their settings to see how they interact.\n\n"
		+ "Game Units:\n"
		+ "[i]• Transceivers - Send/receive signals\n"
		+ "• Jammers - Disrupt signals\n"
		+ "• Sensors - Detect signals\n\n[/i]"
		+ "Goal: Experiment and learn how different settings affect "
		+ "communication, interference, and detection."
	)
	popup.button_string = "Continue"

	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(popup)

	if popup.has_signal("continued"):
		popup.continued.connect(_on_sandbox_popup_closed)


func _on_sandbox_popup_closed() -> void:
	_sandbox_popup_open = false


# ── Terrain generation ────────────────────────────────────────────────────────


func _generate_terrain(w: int, h: int, seed: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.025
	noise.fractal_octaves = 3

	var g: Array = []
	for x in range(w):
		g.append([])
		for y in range(h):
			var n := noise.get_noise_2d(float(x), float(y))
			var h_m := (n + 1.0) * 0.5 * 500.0  # 0 – 500 m
			g[x].append(h_m)
	return g


# ── Main labelling entry point ────────────────────────────────────────────────


func _label_tactical_points(grid: Array, w: int, h: int) -> void:
	_clear_labels()
	
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

	# Step 3 – describe each label.
	# px_pos: container-space pixels, used only for overlap deconfliction below.
	# grid_uv: the heightmap sample coordinate (0..1). This is exactly what the
	#   shader samples, so world_uv_to_screen(grid_uv) lands the label on the
	#   rendered feature through any zoom/pan/aspect change.
	var container_size: Vector2 = map_container.size
	var sx: float = container_size.x / float(w)
	var sy: float = container_size.y / float(h)
	var inv_w := 1.0 / float(w)
	var inv_h := 1.0 / float(h)

	# Collect label descriptors before spawning so we can deconflict
	var label_descs: Array[Dictionary] = []

	for p in peaks:
		(
			label_descs
			. append(
				{
					"px_pos": Vector2(p["x"] * sx, p["y"] * sy),
					"grid_uv": Vector2(p["x"] * inv_w, p["y"] * inv_h),
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
					"grid_uv": Vector2(v["x"] * inv_w, v["y"] * inv_h),
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
	for desc in kept:
		_spawn_label(desc)


func _clear_labels() -> void:
	for child in get_children():
		if child is Label:
			child.queue_free()
			
			
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

	lbl.set_meta("world_uv", desc["grid_uv"])
	lbl.set_meta("half_size", sz * 0.5)

	add_child(lbl)

	lbl.position = world_uv_to_screen(lbl.get_meta("world_uv")) - sz * 0.5


# ── Texture creation ──────────────────────────────────────────────


func update_shader() -> void:
	# super pushes zoom/offset/aspect_ratio to the contour shader (same node as
	# `background`). The shader now contains the aspect-contain math, so the
	# manual offset/aspect compensation here is no longer needed — and was the
	# source of zoom-drift between units and terrain.
	super.update_shader()
	_update_terrain_transform()
	_reposition_labels()


func _update_terrain_transform() -> void:
	if grid_w == 0 or grid_h == 0:
		return
	map_origin = world_uv_to_terrain_px(Vector2.ZERO)
	var far_corner: Vector2 = world_uv_to_terrain_px(Vector2.ONE)
	map_scale = (far_corner - map_origin) / Vector2(float(grid_w), float(grid_h))


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
	if contour_rect == null or not is_instance_valid(contour_rect):
		push_warning("toggle_shader skipped: contour_rect is missing.")
		return

	if contour_rect.material == null:
		push_warning("toggle_shader skipped: contour_rect has no material.")
		return

	if not contour_rect.material is ShaderMaterial:
		push_warning("toggle_shader skipped: contour_rect material is not a ShaderMaterial.")
		return

	var shader_material := contour_rect.material as ShaderMaterial

	if not enabled:
		shader_material.set_shader_parameter("gray_mode", true)
		shader_material.set_shader_parameter("gray_mode_color", Color(0.5, 0.5, 0.5, 1.0))
	else:
		shader_material.set_shader_parameter("gray_mode", false)
		shader_material.set_shader_parameter("color_low", Color(0.10, 0.60, 0.20, 1.0))
		shader_material.set_shader_parameter("color_mid", Color(0.76, 0.70, 0.50, 1.0))
		shader_material.set_shader_parameter("color_high", Color(1.00, 1.00, 1.00, 1.0))
		shader_material.set_shader_parameter("water_color", Color(0.10, 0.30, 0.85, 1.0))

	for child in get_children():
		if child.has_method("set_shader_enabled"):
			child.set_shader_enabled(enabled)


func toggle_grid(enabled: bool) -> void:
	if contour_rect == null or not is_instance_valid(contour_rect):
		push_warning("toggle_grid skipped: contour_rect is missing.")
		return

	if contour_rect.material == null:
		push_warning("toggle_grid skipped: contour_rect has no material.")
		return

	if not contour_rect.material is ShaderMaterial:
		push_warning("toggle_grid skipped: contour_rect material is not a ShaderMaterial.")
		return

	var shader_material := contour_rect.material as ShaderMaterial
	shader_material.set_shader_parameter("line_thickness", 1.0 if enabled else 0.0)

	for child in get_children():
		if child is Label:
			child.visible = enabled


# Terrain helper wrappers
# TODO: put these in separate Terrain.gd file?
func world_pos_to_grid(world_pos: Vector2) -> Vector2:
	"""Convert a world pixel position to grid indices (x, y), clamped to the grid.
	Returns a Vector2 with integer components.
	"""
	var uv: Vector2 = screen_to_world_uv(world_pos)  # BaseLevel's live transform
	var xi: int = clamp(int(uv.x * float(grid_w)), 0, grid_w - 1)
	var yi: int = clamp(int(uv.y * float(grid_h)), 0, grid_h - 1)
	return Vector2(xi, yi)


func get_ground_height_at_pos(world_pos: Vector2) -> float:
	"""Return terrain elevation (meters) at the given world pixel position.
	If terrain not initialized, returns 0.0.
	"""
	if grid_w == 0 or grid_h == 0:
		return 0.0
	var idx = world_pos_to_grid(world_pos)
	return float(height_grid[int(idx.x)][int(idx.y)])


func get_unit_total_height(unit: Node) -> float:
	"""Return ground height + unit antenna height for a unit node.
	Assumes the unit node exposes `height` property and `global_position`.
	"""
	if unit == null:
		return 0.0

	var ground := 0.0

	var uv = unit.get_value(&"world_uv", null) if unit.has_method("get_value") else null

	if uv != null:
		var gx: int = clamp(int(uv.x * float(grid_w)), 0, grid_w - 1)
		var gy: int = clamp(int(uv.y * float(grid_h)), 0, grid_h - 1)
		ground = float(height_grid[gx][gy])
	else:
		var terrain_px: Vector2 = unit.global_position
		ground = get_ground_height_at_pos(terrain_px)

	var antenna_h := float(unit.get("height"))
	return ground + antenna_h


func set_terrain_data(grid: Array) -> void:
	height_grid = grid
	grid_w = grid.size()
	grid_h = grid.size() if grid.size() > 0 else 0
