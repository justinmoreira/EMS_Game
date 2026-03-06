extends BaseLevel


func update_shader():
	if background and background.material:
		var screen_size = get_viewport_rect().size
		var aspect = screen_size.x / screen_size.y
		background.material.set_shader_parameter("zoom", zoom)
		background.material.set_shader_parameter("offset", offset)
		background.material.set_shader_parameter("aspect_ratio", aspect)
