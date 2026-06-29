extends Control

const TARGET_BAR_PX := 200.0
const SEGMENTS := 4

const SIDE_PAD := 20.0
const TOP_PAD := 8.0
const BOT_PAD := 8.0
const BAR_H := 8.0
const LABEL_GAP := 4.0
const FONT_SIZE := 11
const EDGE_MARGIN := 16.0

var _bar_px := TARGET_BAR_PX
var _label := "1 km"
var _mid_label := ""
var _mid_frac := 0.5


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	get_tree().get_root().size_changed.connect(_reposition)
	_reposition()


func _reposition() -> void:
	var panel_w := 2.0 * SIDE_PAD + _bar_px
	var panel_h := TOP_PAD + BAR_H + LABEL_GAP + FONT_SIZE + BOT_PAD
	offset_right = -EDGE_MARGIN
	offset_bottom = -EDGE_MARGIN
	offset_left = -EDGE_MARGIN - panel_w
	offset_top = -EDGE_MARGIN - panel_h


func _process(_delta: float) -> void:
	_update_scale()


func _update_scale() -> void:
	var level := get_tree().current_scene
	if not level:
		return

	var zoom: float = level.get("zoom") if level.get("zoom") != null else 1.0
	var map_km: float = level.get("map_size_km") if level.get("map_size_km") else 5.12

	var map_size: Vector2
	if level.has_method("get_map_size"):
		map_size = level.get_map_size()
	else:
		map_size = get_viewport_rect().size

	var px_per_km := minf(map_size.x, map_size.y) / (zoom * map_km)
	var raw_km := TARGET_BAR_PX / px_per_km
	var nice_km := _nearest_nice(raw_km)
	var bar_px := nice_km * px_per_km
	var lbl := _format_km(nice_km)
	var mid_nice := _nearest_nice(nice_km * 0.5)
	var mid_lbl := _format_km(mid_nice) if abs(mid_nice - nice_km * 0.5) < nice_km * 0.005 else ""

	if abs(bar_px - _bar_px) > 0.5 or lbl != _label or mid_lbl != _mid_label:
		_bar_px = bar_px
		_label = lbl
		_mid_label = mid_lbl
		_mid_frac = 0.5
		_reposition()
		queue_redraw()


func _nearest_nice(km: float) -> float:
	if km <= 0.0:
		return 0.001
	var magnitude := pow(10.0, floor(log(km) / log(10.0)))
	var normalized := km / magnitude
	var best := 1.0
	for n: float in [1.0, 2.0, 2.5, 3.0, 4.0, 5.0]:
		if abs(n - normalized) < abs(best - normalized):
			best = n
	return best * magnitude


func _format_km(km: float) -> String:
	if km < 1.0:
		return "%d m" % int(round(km * 1000.0))
	if abs(km - round(km)) < 0.01:
		return "%d km" % int(round(km))
	return "%.1f km" % km


func _draw() -> void:
	var w := size.x
	var h := size.y
	var bar_x := SIDE_PAD
	var bar_top := TOP_PAD
	var font := ThemeDB.fallback_font
	var seg_w := _bar_px / float(SEGMENTS)

	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.04, 0.04, 0.06, 0.72))
	draw_rect(Rect2(0.0, 0.0, w, h), Color(1.0, 1.0, 1.0, 0.12), false, 1.0)

	var colors := [Color(0.1, 0.1, 0.1, 1.0), Color(0.92, 0.92, 0.92, 1.0)]
	for i in SEGMENTS:
		draw_rect(Rect2(bar_x + i * seg_w, bar_top, seg_w, BAR_H), colors[i % 2])

	draw_rect(Rect2(bar_x, bar_top, _bar_px, BAR_H), Color(1.0, 1.0, 1.0, 0.75), false, 1.0)
	for i in range(1, SEGMENTS):
		var dx := bar_x + i * seg_w
		draw_line(
			Vector2(dx, bar_top), Vector2(dx, bar_top + BAR_H), Color(1.0, 1.0, 1.0, 0.35), 1.0
		)

	var mid_x := bar_x + _mid_frac * _bar_px
	if _mid_label != "":
		draw_line(
			Vector2(mid_x, bar_top + BAR_H),
			Vector2(mid_x, bar_top + BAR_H + LABEL_GAP),
			Color(1.0, 1.0, 1.0, 0.7),
			1.0
		)

	var label_y := bar_top + BAR_H + LABEL_GAP + FONT_SIZE
	var shadow_c := Color(0.0, 0.0, 0.0, 0.75)
	var text_c := Color(1.0, 1.0, 1.0, 0.95)

	var zero_w := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var lbl_w := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(
		font,
		Vector2(bar_x - zero_w * 0.5 + 1.0, label_y + 1.0),
		"0",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		shadow_c
	)
	draw_string(
		font,
		Vector2(bar_x - zero_w * 0.5, label_y),
		"0",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_c
	)
	draw_string(
		font,
		Vector2(bar_x + _bar_px - lbl_w * 0.5 + 1.0, label_y + 1.0),
		_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		shadow_c
	)
	draw_string(
		font,
		Vector2(bar_x + _bar_px - lbl_w * 0.5, label_y),
		_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_c
	)

	if _mid_label != "":
		var mid_w := font.get_string_size(_mid_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var mid_lbl_x := mid_x - mid_w * 0.5
		draw_string(
			font,
			Vector2(mid_lbl_x + 1.0, label_y + 1.0),
			_mid_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE,
			shadow_c
		)
		draw_string(
			font,
			Vector2(mid_lbl_x, label_y),
			_mid_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE,
			text_c
		)
