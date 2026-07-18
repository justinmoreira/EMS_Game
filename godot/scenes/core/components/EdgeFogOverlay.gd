class_name EdgeFogOverlay
extends ColorRect

## Fog-of-war veil past the map border (EdgeFog.gdshader)
##
## Sits above the MGRS grid overlay and below units, so the grid lines and
## the fake terrain both fade into the haze. Separate from MapGridOverlay so
## toggling the grid off keeps the fog. BaseLevel.update_shader pushes camera
## state here, mirroring MapGridOverlay.sync.
##
## While a unit is dragged — from the sidebar (gui drag notifications) or on
## the map (GameEvents.unit_drag_started/ended) — the shader fades in keepout
## hatching outside the AO

const FOG_SHADER := preload("res://shaders/EdgeFog.gdshader")
const KEEPOUT_FADE_SEC := 0.2

var _level = null  # intentionally untyped (BaseLevel)
var _keepout_tween: Tween = null


func setup(level: Control) -> void:
	_level = level
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The shader writes COLOR outright; the rect's own color never shows
	color = Color(0, 0, 0, 0)
	var mat := ShaderMaterial.new()
	mat.shader = FOG_SHADER
	# Seed the uniform so the fade tween always has a float to start from
	mat.set_shader_parameter("keepout", 0.0)
	material = mat
	GameEvents.unit_drag_started.connect(_on_unit_drag_started)
	GameEvents.unit_drag_ended.connect(_on_unit_drag_ended)
	sync()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and (data as Dictionary).has("scene_path"):
			_fade_keepout(1.0)
	elif what == NOTIFICATION_DRAG_END:
		_fade_keepout(0.0)


func _on_unit_drag_started(_unit: Node) -> void:
	_fade_keepout(1.0)


func _on_unit_drag_ended(_unit: Node) -> void:
	_fade_keepout(0.0)


func _fade_keepout(target: float) -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	if _keepout_tween:
		_keepout_tween.kill()
	_keepout_tween = create_tween()
	_keepout_tween.tween_property(mat, "shader_parameter/keepout", target, KEEPOUT_FADE_SEC)


## Track the map viewport and pass camera state to the fog shader
func sync() -> void:
	if _level == null:
		return
	position = Vector2(_level.sidebar_width, 0)
	size = _level.get_map_size()
	var map: Vector2 = _level.get_map_size()
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("zoom", _level.zoom)
	mat.set_shader_parameter("offset", _level.offset)
	mat.set_shader_parameter("aspect_ratio", map.x / map.y)
