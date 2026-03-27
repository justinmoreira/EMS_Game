extends BaseLevel

const MAP_SIZE := 512
const PIXELS_PER_KM := 100.0
const MAP_SIZE_KM := MAP_SIZE / PIXELS_PER_KM
const GRID_CELL_UV := 1.0 / MAP_SIZE_KM

var height_data: Image
var grid_overlay: ColorRect


func _ready():
	super._ready()
	_generate_heightmap()
	_setup_grid_overlay()
	update_shader()


func _generate_heightmap():
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = -3
	noise.frequency = 0.008

	height_data = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)

	var center := Vector2(MAP_SIZE / 2.0, MAP_SIZE / 2.0)
	var mountain_radius := MAP_SIZE * 0.25

	for x in MAP_SIZE:
		for y in MAP_SIZE:
			var noise_val = (noise.get_noise_2d(x, y) + 1.0) / 2.0

			var dist = Vector2(x, y).distance_to(center)
			var mountain_val = 0.0
			if dist < mountain_radius:
				mountain_val = 1.0 - (dist / mountain_radius)

			var height = max(noise_val, mountain_val)
			var c = clamp(height, 0.0, 1.0)
			height_data.set_pixel(x, y, Color(c, c, c))

	var tex = ImageTexture.create_from_image(height_data)
	background.texture = tex


func _setup_grid_overlay():
	var grid_layer = CanvasLayer.new()
	grid_layer.name = "GridOverlay"
	grid_layer.layer = 5
	add_child(grid_layer)

	grid_overlay = ColorRect.new()
	grid_overlay.name = "GridRect"
	grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_overlay.color = Color(0, 0, 0, 0)

	var shader = load("res://shaders/GridOverlay.gdshader")
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("grid_cell_uv", GRID_CELL_UV)
	grid_overlay.material = mat

	grid_layer.add_child(grid_overlay)
	_resize_grid()


func _resize_grid():
	if grid_overlay:
		var vp = get_viewport_rect().size
		grid_overlay.position = Vector2(sidebar_width, 0)
		grid_overlay.size = Vector2(vp.x - sidebar_width, vp.y)


func get_height_at(world_pos: Vector2) -> float:
	var uv_x = world_pos.x / (MAP_SIZE_KM * PIXELS_PER_KM)
	var uv_y = world_pos.y / (MAP_SIZE_KM * PIXELS_PER_KM)
	var px = clamp(int(uv_x * MAP_SIZE), 0, MAP_SIZE - 1)
	var py = clamp(int(uv_y * MAP_SIZE), 0, MAP_SIZE - 1)
	return height_data.get_pixel(px, py).r


func update_shader():
	super.update_shader()
	_resize_grid()
	if grid_overlay and grid_overlay.material:
		var map = get_map_size()
		var aspect = map.x / map.y
		grid_overlay.material.set_shader_parameter("zoom", zoom)
		grid_overlay.material.set_shader_parameter("offset", offset)
		grid_overlay.material.set_shader_parameter("aspect_ratio", aspect)


func toggle_grid(enabled: bool):
	var grid_layer = get_node_or_null("GridOverlay")
	if grid_layer:
		grid_layer.visible = enabled
