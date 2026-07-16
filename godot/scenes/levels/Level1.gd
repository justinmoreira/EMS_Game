extends BaseLevel

const HEIGHTMAP_SIZE := 512
const PIXELS_PER_KM := 100.0
const MAP_SIZE_KM := HEIGHTMAP_SIZE / PIXELS_PER_KM

var height_data: Image


func _ready():
	super._ready()
	_generate_heightmap()
	update_shader()


func _generate_heightmap():
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = -3
	noise.frequency = 0.008

	height_data = Image.create(HEIGHTMAP_SIZE, HEIGHTMAP_SIZE, false, Image.FORMAT_RGB8)

	var center := Vector2(HEIGHTMAP_SIZE / 2.0, HEIGHTMAP_SIZE / 2.0)
	var mountain_radius := HEIGHTMAP_SIZE * 0.25

	for x in HEIGHTMAP_SIZE:
		for y in HEIGHTMAP_SIZE:
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


func get_height_at(world_pos: Vector2) -> float:
	var uv_x = world_pos.x / (MAP_SIZE_KM * PIXELS_PER_KM)
	var uv_y = world_pos.y / (MAP_SIZE_KM * PIXELS_PER_KM)
	var px = clamp(int(uv_x * HEIGHTMAP_SIZE), 0, HEIGHTMAP_SIZE - 1)
	var py = clamp(int(uv_y * HEIGHTMAP_SIZE), 0, HEIGHTMAP_SIZE - 1)
	return height_data.get_pixel(px, py).r
