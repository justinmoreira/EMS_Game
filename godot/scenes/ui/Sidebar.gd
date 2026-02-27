extends PanelContainer

# ─────────────────────────────────────────────
#  Sidebar.gd — EMS Simulation
# ─────────────────────────────────────────────

enum EntityType { NONE, TRANSCEIVER, JAMMER, SENSOR }

# ── Colors ────────────────────────────────────
const C_BG_DARK := Color("0d0f14")
const C_BG_MID := Color("13161e")
const C_BG_LIGHT := Color("1c2030")
const C_BORDER := Color("2a3045")
const C_GREEN := Color("00ff9c")
const C_AMBER := Color("ffb347")
const C_BLUE := Color("4fc3f7")
const C_RED := Color("ff5c5c")
const C_TEXT := Color("e8eaf0")
const C_DIM := Color("6b7594")

# ── State ─────────────────────────────────────
var selected_entity: EntityType = EntityType.NONE
var selected_entity_name: String = ""
var selected_node: Node = null

# ── Node refs ─────────────────────────────────
var _attr_header: Label
var _attr_body: VBoxContainer
var _attr_placeholder: Label


# ════════════════════════════════════════════
func _ready() -> void:
	_build_sidebar()
	_refresh_attribute_panel()


# ════════════════════════════════════════════
#  PUBLIC API
# ════════════════════════════════════════════


func select_entity(type: EntityType, display_name: String = "", node: Node = null) -> void:
	selected_entity = type
	selected_entity_name = display_name
	selected_node = node
	_refresh_attribute_panel()


# ════════════════════════════════════════════
#  BUILD
# ════════════════════════════════════════════


func _build_sidebar() -> void:
	_apply_style(self, C_BG_DARK, C_BORDER, 0, 0, 0, 1)
	custom_minimum_size = Vector2(300, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	vbox.add_child(_build_header())
	vbox.add_child(_build_tray())
	vbox.add_child(_build_divider())
	vbox.add_child(_build_attr_section())


func _build_header() -> PanelContainer:
	var panel := PanelContainer.new()
	_apply_style(panel, C_BG_MID, C_GREEN, 0, 2, 0, 0)
	panel.add_theme_stylebox_override("panel", _flat_style(C_BG_MID, 12))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	var dot := ColorRect.new()
	dot.color = C_GREEN
	dot.custom_minimum_size = Vector2(15, 15)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(dot)
	_animate_blink(dot)

	hbox.add_child(_make_label("GEMS", C_GREEN, 25))
	return panel


func _build_tray() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(C_BG_MID, 14))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(_make_label("ENTITIES", C_DIM, 15))

	var stack := VBoxContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	vbox.add_child(stack)
	stack.add_child(_build_entity_card("Transceiver", C_BLUE, EntityType.TRANSCEIVER))
	stack.add_child(_build_entity_card("Jammer", C_AMBER, EntityType.JAMMER))
	stack.add_child(_build_entity_card("Sensor", C_RED, EntityType.SENSOR))

	var hint := _make_label("drag entities onto the scene", C_DIM, 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	return panel


func _build_entity_card(label: String, accent: Color, type: EntityType) -> Button:
	var card := Button.new()
	card.text = label
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_theme_font_size_override("font_size", 22)
	card.add_theme_color_override("font_color", accent)
	card.add_theme_color_override("font_hover_color", accent.lightened(0.2))
	card.add_theme_color_override("font_pressed_color", accent.darkened(0.2))

	var s := _flat_style(C_BG_LIGHT, 6)
	s.set_border_color(accent)
	s.set_border_width_all(0)
	s.border_width_top = 2
	card.add_theme_stylebox_override("normal", s)

	var sh := _flat_style(C_BG_LIGHT.lightened(0.08), 6)
	sh.set_border_color(accent)
	sh.set_border_width_all(0)
	sh.border_width_top = 2
	card.add_theme_stylebox_override("hover", sh)

	var sp := _flat_style(accent.darkened(0.6), 6)
	sp.set_border_color(accent)
	sp.set_border_width_all(0)
	sp.border_width_top = 2
	card.add_theme_stylebox_override("pressed", sp)

	card.pressed.connect(func(): select_entity(type, label, null))
	return card


func _build_attr_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(C_BG_MID, 14))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	content.add_child(_make_label("ATTRIBUTES", C_DIM, 15))

	_attr_header = _make_label("", C_TEXT, 20)
	content.add_child(_attr_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_attr_body = VBoxContainer.new()
	_attr_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attr_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_attr_body)

	# Placeholder lives outside the scroll so it can center properly
	_attr_placeholder = _make_label("— select a unit to configure —", C_DIM, 15)
	_attr_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attr_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_attr_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attr_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_attr_placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_attr_placeholder)

	return panel


func _build_divider() -> HSeparator:
	var sep := HSeparator.new()
	var s := StyleBoxFlat.new()
	s.bg_color = C_BORDER
	sep.add_theme_stylebox_override("separator", s)
	return sep


# ════════════════════════════════════════════
#  REFRESH
# ════════════════════════════════════════════


func _refresh_attribute_panel() -> void:
	for child in _attr_body.get_children():
		child.queue_free()

	if selected_entity == EntityType.NONE:
		_attr_header.visible = false
		_attr_placeholder.visible = true
		return

	_attr_placeholder.visible = false
	_attr_header.visible = true

	match selected_entity:
		EntityType.TRANSCEIVER:
			_attr_header.text = "Transceiver"
			_attr_header.add_theme_color_override("font_color", C_BLUE)
			_add_accent_bar(C_BLUE)
			_add_slider(
				"Tx Power",
				0.0,
				10.0,
				_prop_float("power", 5.0),
				"dBm",
				C_BLUE,
				func(v): _write("power", int(v)),
				true
			)
			_add_slider(
				"Frequency",
				30.0,
				3000.0,
				_prop_float("frequency", 1000.0),
				"MHz",
				C_BLUE,
				func(v): _write("frequency", v),
				true
			)
			_add_slider(
				"Height",
				0.0,
				10.0,
				_node_int("height", 5),
				"m",
				C_BLUE,
				func(v): _write_node("height", int(v)),
				true
			)

		EntityType.JAMMER:
			_attr_header.text = "Jammer"
			_attr_header.add_theme_color_override("font_color", C_AMBER)
			_add_accent_bar(C_AMBER)
			_add_slider(
				"Power",
				0.0,
				10.0,
				_prop_float("power", 5.0),
				"dBm",
				C_AMBER,
				func(v): _write("power", int(v)),
				true
			)
			_add_slider(
				"Frequency",
				30.0,
				3000.0,
				_prop_float("frequency", 1000.0),
				"MHz",
				C_AMBER,
				func(v): _write("frequency", v),
				true
			)
			_add_dropdown(
				"Bandwidth",
				["Narrow", "Medium", "Wide"],
				_prop_int("jammer_bandwidth", 1),
				C_AMBER,
				func(v): _write("jammer_bandwidth", v)
			)
			_add_slider(
				"Height",
				0.0,
				10.0,
				_node_int("height", 5),
				"m",
				C_AMBER,
				func(v): _write_node("height", int(v)),
				true
			)

		EntityType.SENSOR:
			_attr_header.text = "Sensor"
			_attr_header.add_theme_color_override("font_color", C_RED)
			_add_accent_bar(C_RED)
			_add_slider(
				"Sensitivity",
				0.0,
				10.0,
				_prop_float("sensitivity", 3.0),
				"dBm",
				C_RED,
				func(v): _write("sensitivity", int(v)),
				true
			)
			_add_dropdown(
				"Bandwidth",
				["Narrow", "Medium", "Wide"],
				_prop_int("sensor_bandwidth", 1),
				C_RED,
				func(v): _write("sensor_bandwidth", v)
			)
			_add_slider(
				"Height",
				0.0,
				10.0,
				_node_int("height", 5),
				"m",
				C_RED,
				func(v): _write_node("height", int(v)),
				true
			)
			_add_toggle(
				"Scanning",
				_prop_bool("is_scanning", true),
				C_RED,
				func(v): _write("is_scanning", v)
			)


# ════════════════════════════════════════════
#  CONTROL BUILDERS
# ════════════════════════════════════════════


func _add_accent_bar(accent: Color) -> void:
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(0, 2)
	_attr_body.add_child(bar)


func _add_slider(
	label: String,
	min_v: float,
	max_v: float,
	current: float,
	unit: String,
	accent: Color,
	on_change: Callable,
	integers: bool = false
) -> void:
	var vbox := _make_row_container()

	# Top row: label + spinbox
	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)
	top.add_child(_make_label(label, C_DIM, 13, true))

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = current
	spin.step = 1.0 if integers else 0.1
	spin.rounded = integers
	spin.suffix = unit
	spin.size_flags_horizontal = Control.SIZE_SHRINK_END
	spin.custom_minimum_size = Vector2(140, 0)
	spin.add_theme_font_size_override("font_size", 13)
	spin.add_theme_color_override("font_color", accent)
	top.add_child(spin)

	# Bottom row: full-width slider
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.value = current
	slider.step = 1.0 if integers else 0.1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 20)
	slider.add_theme_color_override("grabber_color", accent)

	var track := StyleBoxFlat.new()
	track.bg_color = Color("ffffff")
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	slider.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	slider.add_theme_stylebox_override("grabber_area", fill)
	vbox.add_child(slider)

	slider.value_changed.connect(
		func(v):
			spin.set_value_no_signal(v)
			on_change.call(v)
	)
	spin.value_changed.connect(
		func(v):
			slider.set_value_no_signal(v)
			on_change.call(v)
	)


func _add_dropdown(
	label: String, options: Array, current_idx: int, accent: Color, on_change: Callable
) -> void:
	var vbox := _make_row_container()
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)
	hbox.add_child(_make_label(label, C_DIM, 13, true))

	var dd := OptionButton.new()
	dd.size_flags_horizontal = Control.SIZE_SHRINK_END
	dd.custom_minimum_size = Vector2(110, 0)
	dd.add_theme_font_size_override("font_size", 13)
	dd.add_theme_color_override("font_color", accent)
	for opt in options:
		dd.add_item(opt)
	dd.select(current_idx)
	dd.item_selected.connect(func(idx): on_change.call(idx))
	hbox.add_child(dd)


func _add_toggle(label: String, current: bool, accent: Color, on_change: Callable) -> void:
	var vbox := _make_row_container()
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)
	hbox.add_child(_make_label(label, C_DIM, 13, true))

	var toggle := CheckButton.new()
	toggle.button_pressed = current
	toggle.add_theme_color_override("font_color", accent)
	toggle.toggled.connect(func(v): on_change.call(v))
	hbox.add_child(toggle)


## Creates a styled card container, adds it to _attr_body, returns inner VBoxContainer
func _make_row_container() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(C_BG_LIGHT, 10))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attr_body.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	return vbox


# ════════════════════════════════════════════
#  NODE PROPERTY HELPERS
# ════════════════════════════════════════════


func _component() -> Node:
	if not selected_node:
		return null
	match selected_entity:
		EntityType.TRANSCEIVER:
			return selected_node.find_child("Transceiver")
		EntityType.JAMMER:
			return selected_node.find_child("Jammer")
		EntityType.SENSOR:
			return selected_node.find_child("Sensor")
	return null


func _prop_float(p: String, fallback: float) -> float:
	var c := _component()
	return float(c.get(p)) if c and p in c else fallback


func _prop_int(p: String, fallback: int) -> int:
	var c := _component()
	return int(c.get(p)) if c and p in c else fallback


func _prop_bool(p: String, fallback: bool) -> bool:
	var c := _component()
	return bool(c.get(p)) if c and p in c else fallback


func _write(p: String, value) -> void:
	var c := _component()
	if c and p in c:
		c.set(p, value)


## Read/write directly on the EMSUnit node (not the component child)
func _node_int(p: String, fallback: int) -> int:
	return int(selected_node.get(p)) if selected_node and p in selected_node else fallback


func _write_node(p: String, value) -> void:
	if selected_node and p in selected_node:
		selected_node.set(p, value)


# ════════════════════════════════════════════
#  STYLE HELPERS
# ════════════════════════════════════════════


## Shorthand for a basic StyleBoxFlat with bg color and uniform padding
func _flat_style(bg: Color, padding: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.set_content_margin_all(padding)
	return s


## Apply border styling directly to a control's panel stylebox
func _apply_style(
	control: Control, bg: Color, border: Color, top: int, bottom: int, left: int, right: int
) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_color(border)
	s.border_width_top = top
	s.border_width_bottom = bottom
	s.border_width_left = left
	s.border_width_right = right
	control.add_theme_stylebox_override("panel", s)


## Shorthand label factory
func _make_label(text: String, color: Color, size: int, expand: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _animate_blink(node: ColorRect) -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(node, "modulate:a", 0.1, 0.8)
	tween.tween_property(node, "modulate:a", 1.0, 0.4)
