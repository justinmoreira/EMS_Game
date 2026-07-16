class_name MapGridOverlay
extends Control

## MGRS-style hierarchical grid overlay
##   spacing_km     cell size
##   width_px       on-screen line width
##   strength       peak line opacity
##   fade_start/end zoom where the level starts/finishes fading in
##                  (fade_start <= fade_end means always fully shown)
##   min_alpha      opacity floor while zoomed out (0 = hidden)
##   designators    draw square designator text at cell centers
const LEVELS: Array[Dictionary] = [
	{
		"spacing_km": 5.0,
		"width_px": 1.8,
		"strength": 0.8,
		"fade_start": 0.0,
		"fade_end": 0.0,
		"min_alpha": 0.8,
		"designators": true,
	},
	{
		"spacing_km": 1.0,
		"width_px": 1.2,
		"strength": 0.6,
		"fade_start": 0.85,
		"fade_end": 0.5,
		"min_alpha": 0.15,
		"designators": true,
	},
	{
		"spacing_km": 0.1,
		"width_px": 0.8,
		"strength": 0.4,
		"fade_start": 0.3,
		"fade_end": 0.12,
		"min_alpha": 0.0,
		"designators": true,
	},
]

const MAX_LEVELS := 8

const EDGE_LABEL_LEVEL := 1
const DESIGNATOR_ALPHA := 0.35
const MIN_DESIGNATOR_CELL_PX := 40.0
const LABEL_FONT_SIZE := 13
const LABEL_OUTLINE_SIZE := 4
const LABEL_MARGIN := 4.0

const GRID_SHADER := preload("res://shaders/GridOverlay.gdshader")

var labels_enabled := true

var _level = null  # intentionally untyped
var _grid_rect: ColorRect
var _label_layer: Control


func setup(level: Control) -> void:
	_level = level
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_grid_rect = ColorRect.new()
	_grid_rect.name = "GridShaderRect"
	_grid_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_rect.color = Color(0, 0, 0, 0)
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	_grid_rect.material = mat
	add_child(_grid_rect)

	_label_layer = Control.new()
	_label_layer.name = "GridLabels"
	_label_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label_layer.visible = labels_enabled
	_label_layer.draw.connect(_draw_labels)
	add_child(_label_layer)

	sync()


func set_labels_enabled(enabled: bool) -> void:
	labels_enabled = enabled
	if _label_layer:
		_label_layer.visible = enabled


## Pass camera state and level alphas to the shader
func sync() -> void:
	if _level == null or _grid_rect == null:
		return

	_grid_rect.position = Vector2(_level.sidebar_width, 0)
	_grid_rect.size = _level.get_map_size()

	var map: Vector2 = _level.get_map_size()
	var zoom: float = _level.zoom
	var map_km: float = _level.MAP_SIZE_KM
	var count := mini(LEVELS.size(), MAX_LEVELS)
	var cells := PackedFloat32Array()
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	cells.resize(MAX_LEVELS)
	widths.resize(MAX_LEVELS)
	alphas.resize(MAX_LEVELS)
	for i in count:
		cells[i] = LEVELS[i].spacing_km / map_km
		widths[i] = LEVELS[i].width_px
		alphas[i] = level_alpha(LEVELS[i], zoom)

	var mat := _grid_rect.material as ShaderMaterial
	mat.set_shader_parameter("zoom", zoom)
	mat.set_shader_parameter("offset", _level.offset)
	mat.set_shader_parameter("aspect_ratio", map.x / map.y)
	mat.set_shader_parameter("level_count", count)
	mat.set_shader_parameter("level_cell_uv", cells)
	mat.set_shader_parameter("level_width_px", widths)
	mat.set_shader_parameter("level_alpha", alphas)

	_label_layer.queue_redraw()


## Fade-in progress [0..1] for a level at the given zoom
static func level_fade(lv: Dictionary, zoom: float) -> float:
	if lv.fade_start <= lv.fade_end:
		return 1.0
	return 1.0 - smoothstep(lv.fade_end, lv.fade_start, zoom)


## Line opacity for a level at the given zoom
static func level_alpha(lv: Dictionary, zoom: float) -> float:
	return lerpf(lv.min_alpha, 1.0, level_fade(lv, zoom)) * lv.strength


func _draw_labels() -> void:
	if _level == null:
		return
	var font := get_theme_default_font()
	if font == null:
		return
	_draw_edge_numbers(font)
	_draw_designators(font)


# Line numbers along the top and left edges of the map
func _draw_edge_numbers(font: Font) -> void:
	var idx := mini(EDGE_LABEL_LEVEL, LEVELS.size() - 1)
	var lv := LEVELS[idx]
	var map_km: float = _level.MAP_SIZE_KM
	var lines := int(roundf(map_km / lv.spacing_km))
	var major := int(roundf(LEVELS[0].spacing_km / lv.spacing_km)) if idx > 0 else 1
	var minor_alpha := level_fade(lv, _level.zoom) if idx > 0 else 1.0
	var map_left: float = _level.sidebar_width
	var view := size
	var ascent := font.get_ascent(LABEL_FONT_SIZE)

	for i in lines + 1:
		var a := 1.0 if i % major == 0 else minor_alpha
		if a < 0.05:
			continue
		var t := float(i) / float(lines)
		var text := "%02d" % i

		var top := _level.world_uv_to_screen(Vector2(t, 0.0)) as Vector2
		var bottom := _level.world_uv_to_screen(Vector2(t, 1.0)) as Vector2
		if top.x >= map_left and top.x <= view.x and bottom.y >= 0.0 and top.y <= view.y:
			var pos := Vector2(top.x + LABEL_MARGIN, maxf(top.y, 0.0) + LABEL_MARGIN + ascent)
			_draw_text(font, pos, text, LABEL_FONT_SIZE, LABEL_OUTLINE_SIZE, a)

		var left := _level.world_uv_to_screen(Vector2(0.0, t)) as Vector2
		var right := _level.world_uv_to_screen(Vector2(1.0, t)) as Vector2
		if left.y >= 0.0 and left.y <= view.y and right.x >= map_left and left.x <= view.x:
			var pos := Vector2(
				maxf(left.x, map_left) + LABEL_MARGIN, left.y + LABEL_MARGIN + ascent
			)
			_draw_text(font, pos, text, LABEL_FONT_SIZE, LABEL_OUTLINE_SIZE, a)


# Faint square designators at the centers of on-screen cells
func _draw_designators(font: Font) -> void:
	var map_km: float = _level.MAP_SIZE_KM
	var zoom: float = _level.zoom
	var map: Vector2 = _level.get_map_size()
	var px_per_uv := minf(map.x, map.y) / zoom
	var uv_a: Vector2 = _level.screen_to_world_uv(Vector2(_level.sidebar_width, 0.0))
	var uv_b: Vector2 = _level.screen_to_world_uv(Vector2(size.x, size.y))

	for li in LEVELS.size():
		var lv := LEVELS[li]
		if not lv.designators:
			continue
		var a := DESIGNATOR_ALPHA * _designator_fade(li, zoom)
		if a < 0.03:
			continue
		var spacing_uv: float = lv.spacing_km / map_km
		var cell_px := spacing_uv * px_per_uv
		if cell_px < MIN_DESIGNATOR_CELL_PX:
			continue
		var count := int(roundf(map_km / lv.spacing_km))
		var fsize := clampi(int(cell_px * 0.2), 9, 72)
		var x0 := maxi(0, int(floorf(maxf(uv_a.x, 0.0) / spacing_uv)))
		var x1 := mini(count - 1, int(floorf(minf(uv_b.x, 1.0) / spacing_uv)))
		var y0 := maxi(0, int(floorf(maxf(uv_a.y, 0.0) / spacing_uv)))
		var y1 := mini(count - 1, int(floorf(minf(uv_b.y, 1.0) / spacing_uv)))
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var center := (
					_level.world_uv_to_screen(
						Vector2((cx + 0.5) * spacing_uv, (cy + 0.5) * spacing_uv)
					)
					as Vector2
				)
				var text := _designator(li, cx, cy)
				var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
				var pos := Vector2(
					center.x - sz.x * 0.5, center.y + font.get_ascent(fsize) - sz.y * 0.5
				)
				_draw_text(font, pos, text, fsize, maxi(2, int(fsize / 8.0)), a)


# Designators cross-fade between levels
func _designator_fade(li: int, zoom: float) -> float:
	var fade := level_fade(LEVELS[li], zoom)
	for j in range(li + 1, LEVELS.size()):
		if LEVELS[j].designators:
			return fade * (1.0 - level_fade(LEVELS[j], zoom))
	return fade


# MGRS-style designators: top-level cells get letter pairs ("AA".."CC")...
# deeper cells append zero-padded easting/northing digits within their
# top-level square (e.g. "AB 32" at 1 km, "AB 1707" at 100 m)
func _designator(li: int, cx: int, cy: int) -> String:
	var per := int(roundf(LEVELS[0].spacing_km / LEVELS[li].spacing_km))
	var letters := char(65 + int(cx / float(per))) + char(65 + int(cy / float(per)))
	if li == 0:
		return letters
	var digits := str(per - 1).length()
	var easting := str(cx % per).pad_zeros(digits)
	var northing := str(cy % per).pad_zeros(digits)
	return "%s %s%s" % [letters, easting, northing]


func _draw_text(
	font: Font, pos: Vector2, text: String, fsize: int, outline: int, alpha: float
) -> void:
	_label_layer.draw_string_outline(
		font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, alpha)
	)
	_label_layer.draw_string(
		font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, alpha)
	)
