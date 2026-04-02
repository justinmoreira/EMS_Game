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
var _reset_btn: Button = null
var _simulate_btn: Button = null
var _delete_btn: Button = null

# ── Node refs ─────────────────────────────────
var _attr_header: Label
var _attr_body: VBoxContainer
var _attr_placeholder: Label


func _ready() -> void:
	GameEvents.units_changed.connect(_update_simulate_button)
	_build_sidebar()
	_refresh_attribute_panel()


func select_entity(type: EntityType, display_name: String = "", node: Node = null) -> void:
	selected_entity = type
	selected_entity_name = display_name
	selected_node = node
	_refresh_attribute_panel()
	_update_simulate_button()


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
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)

	var dot := ColorRect.new()
	dot.color = C_GREEN
	dot.custom_minimum_size = Vector2(15, 15)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(dot)
	_animate_blink(dot)

	hbox.add_child(_make_label("GEMS", C_GREEN, 25))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var reset_btn := Button.new()
	reset_btn.text = "RESET"
	reset_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset_btn.add_theme_font_size_override("font_size", 13)
	reset_btn.add_theme_color_override("font_color", C_BG_DARK)
	reset_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var reset_style := StyleBoxFlat.new()
	reset_style.bg_color = C_RED
	reset_style.corner_radius_top_left = 3
	reset_style.corner_radius_top_right = 3
	reset_style.corner_radius_bottom_left = 3
	reset_style.corner_radius_bottom_right = 3
	reset_style.set_content_margin_all(8)
	reset_btn.add_theme_stylebox_override("normal", reset_style)

	reset_btn.pressed.connect(_on_reset_pressed)
	hbox.add_child(reset_btn)
	_reset_btn = reset_btn

	var btn := Button.new()
	btn.text = "SIMULATE"
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", C_BG_DARK)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = C_GREEN
	btn_style.corner_radius_top_left = 3
	btn_style.corner_radius_top_right = 3
	btn_style.corner_radius_bottom_left = 3
	btn_style.corner_radius_bottom_right = 3
	btn_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_disabled_style := StyleBoxFlat.new()
	btn_disabled_style.bg_color = C_BORDER
	btn_disabled_style.corner_radius_top_left = 3
	btn_disabled_style.corner_radius_top_right = 3
	btn_disabled_style.corner_radius_bottom_left = 3
	btn_disabled_style.corner_radius_bottom_right = 3
	btn_disabled_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("disabled", btn_disabled_style)

	btn.pressed.connect(_on_simulate_pressed)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hbox.add_child(btn)

	_simulate_btn = btn
	_update_simulate_button()

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
	stack.add_child(
		_build_entity_card(
			"Transceiver",
			"T",
			C_BLUE,
			EntityType.TRANSCEIVER,
			"res://scenes/core/units/TransceiverUnit.tscn",
			"res://assets/sprites/transceiver.png"
		)
	)
	stack.add_child(
		_build_entity_card(
			"Jammer",
			"J",
			C_AMBER,
			EntityType.JAMMER,
			"res://scenes/core/units/JammerUnit.tscn",
			"res://assets/sprites/jammer.png"
		)
	)
	stack.add_child(
		_build_entity_card(
			"Sensor",
			"S",
			C_RED,
			EntityType.SENSOR,
			"res://scenes/core/units/SensorUnit.tscn",
			"res://assets/sprites/sensor.png"
		)
	)

	var hint := _make_label("drag entities onto the scene", C_DIM, 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	return panel


func _build_entity_card(
	label: String,
	icon_letter: String,
	accent: Color,
	type: EntityType,
	scene_path: String,
	sprite_path: String = ""
) -> PanelContainer:
	var EntityCard := load("res://scenes/ui/EntityCard.gd")
	var card = EntityCard.new()
	card.setup(
		type,
		icon_letter,
		accent,
		scene_path,
		label,
		C_BG_LIGHT,
		C_BG_LIGHT.lightened(0.08),
		sprite_path
	)
	card.pressed.connect(func(): select_entity(type, label, selected_node))
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

	var attr_header_row := HBoxContainer.new()
	attr_header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(attr_header_row)

	attr_header_row.add_child(_make_label("ATTRIBUTES", C_DIM, 15))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attr_header_row.add_child(spacer)

	var delete_btn := Button.new()
	delete_btn.text = "DELETE UNIT"
	delete_btn.add_theme_font_size_override("font_size", 12)
	delete_btn.add_theme_color_override("font_color", C_BG_DARK)
	delete_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var del_style := StyleBoxFlat.new()
	del_style.bg_color = C_RED
	del_style.corner_radius_top_left = 3
	del_style.corner_radius_top_right = 3
	del_style.corner_radius_bottom_left = 3
	del_style.corner_radius_bottom_right = 3
	del_style.set_content_margin_all(8)
	delete_btn.add_theme_stylebox_override("normal", del_style)
	delete_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	delete_btn.pressed.connect(_on_delete_pressed)
	delete_btn.visible = false

	attr_header_row.add_child(delete_btn)
	_delete_btn = delete_btn

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


func _refresh_attribute_panel() -> void:
	for child in _attr_body.get_children():
		child.queue_free()

	if _delete_btn:
		_delete_btn.visible = selected_entity != EntityType.NONE and selected_node != null

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
			_add_dropdown(
				"Bandwidth",
				["Narrow", "Medium", "Wide"],
				_prop_int("transceiver_bandwidth", 1),
				C_BLUE,
				func(v): _write("transceiver_bandwidth", v)
			)

		EntityType.JAMMER:
			_attr_header.text = "Jammer"
			_attr_header.add_theme_color_override("font_color", C_AMBER)
			_add_accent_bar(C_AMBER)
			_add_slider(
				"Power",
				0.0,
				10.0,
				_prop_int("power", 5),
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
				_prop_int("sensitivity", 3),
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


func _on_reset_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset Scene"
	dialog.dialog_text = "Remove all units from the scene?"
	dialog.ok_button_text = "Reset"
	dialog.cancel_button_text = "Cancel"
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	dialog.confirmed.connect(
		func():
			for unit in get_tree().get_nodes_in_group("transceivers"):
				unit.get_parent().queue_free()
			for unit in get_tree().get_nodes_in_group("sensors"):
				unit.get_parent().queue_free()
			for unit in get_tree().get_nodes_in_group("jammers"):
				unit.get_parent().queue_free()
			select_entity(EntityType.NONE)
			SimulationManager.clear_all_links()
			dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())


func _on_delete_pressed() -> void:
	if not selected_node:
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Unit"
	dialog.dialog_text = "Delete %s from the scene?" % selected_entity_name
	dialog.ok_button_text = "Delete"
	dialog.cancel_button_text = "Cancel"
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	dialog.confirmed.connect(
		func():
			selected_node.get_parent().queue_free()
			select_entity(EntityType.NONE)
			SimulationManager.clear_all_links()
			dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())


func _update_simulate_button() -> void:
	var has_units = (
		get_tree().get_nodes_in_group("transceivers").size() > 0
		or get_tree().get_nodes_in_group("jammers").size() > 0
		or get_tree().get_nodes_in_group("sensors").size() > 0
	)

	if _simulate_btn:
		_simulate_btn.disabled = not has_units
		_simulate_btn.mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if has_units else Control.CURSOR_ARROW
		)

	if _reset_btn:
		_reset_btn.disabled = not has_units
		_reset_btn.mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if has_units else Control.CURSOR_ARROW
		)


func _on_simulate_pressed() -> void:
	SimulationManager.simulate()


func _component() -> Node:
	return selected_node


func _prop_float(p: String, fallback: float) -> float:
	var c := _component()
	if c:
		var val = c.get(p)
		if val != null:
			return float(val)
	return fallback


func _prop_int(p: String, fallback: int) -> int:
	var c := _component()
	if c:
		var val = c.get(p)
		if val != null:
			return int(val)
	return fallback


func _prop_bool(p: String, fallback: bool) -> bool:
	var c := _component()
	return bool(c.get(p)) if c and p in c else fallback


func _write(p: String, value) -> void:
	var c := _component()
	if not c:
		return

	c.set(p, value)

	var unit = c.get_parent()
	if unit == null:
		return

	var scene_path = unit.scene_file_path
	if scene_path:
		var packed_scene := PackedScene.new()
		if packed_scene.pack(unit) == OK:
			ResourceSaver.save(packed_scene, scene_path)
		else:
			push_error("Failed to pack unit")


func _is_transceiver_unit(unit: Node) -> bool:
	if unit == null:
		return false

	for child in unit.get_children():
		if child.name == "Transceiver":
			return true

	return false


func _node_int(p: String, fallback: int) -> int:
	return int(selected_node.get(p)) if selected_node and p in selected_node else fallback


func _write_node(p: String, value) -> void:
	if selected_node and p in selected_node:
		selected_node.set(p, value)

		var scene_path = selected_node.scene_file_path
		if scene_path:
			var packed_scene := PackedScene.new()
			if packed_scene.pack(selected_node) == OK:
				ResourceSaver.save(packed_scene, scene_path)
			else:
				push_error("Failed to pack unit")


func _flat_style(bg: Color, padding: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.set_content_margin_all(padding)
	return s


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
