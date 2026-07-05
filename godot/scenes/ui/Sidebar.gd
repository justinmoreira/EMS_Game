class_name Sidebar
extends PanelContainer

# ─────────────────────────────────────────────
#  Sidebar.gd — EMS Simulation
# ─────────────────────────────────────────────

enum EntityType { NONE, TRANSCEIVER, JAMMER, SENSOR }

const TRANSCEIVER_DEF: UnitDefinition = preload("res://data/units/transceiver.tres")
const JAMMER_DEF: UnitDefinition = preload("res://data/units/jammer.tres")
const SENSOR_DEF: UnitDefinition = preload("res://data/units/sensor.tres")

# Fixed design width reported to the map layout. The panel's content can grow a
# few px when the attribute rows populate; reporting a constant keeps the map
# from reflowing/recentering every time the panel changes. The sidebar is
# opaque on a CanvasLayer above the map, so any minor overhang is hidden.
const SIDEBAR_WIDTH := 300.0

# Fixed height of the ATTRIBUTES title row. Tall enough for the DELETE/CONFIRM
# buttons so the row (and everything below it) doesn't shift when they toggle
# on selecting a placed unit.
const ATTR_HEADER_ROW_HEIGHT := 34.0

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
const C_PURPLE := Color("e099ff")

# ── State ─────────────────────────────────────
var selected_entity: EntityType = EntityType.NONE
var selected_entity_name: String = ""
var selected_node: Node = null
var pending_attributes: Dictionary = {}
var pending_entity_type: EntityType = EntityType.NONE
var _reset_btn: Button = null
var _delete_btn: Button = null
var _confirm_btn: Button = null

# ── Node refs ─────────────────────────────────
# Slots come from Sidebar.tscn — script populates them on _ready.
@onready var _header_slot: PanelContainer = $Layout/Header
@onready var _tray_slot: PanelContainer = $Layout/Tray
@onready var _divider_slot: HSeparator = $Layout/Divider
@onready var _attr_section: PanelContainer = $Layout/AttrSection

var _attr_header: Label
var _attr_body: VBoxContainer
var _attr_placeholder: Label
var _entity_cards: Dictionary = {}  # EntityType -> Control
var _attr_content: VBoxContainer
var _tutorial_active: bool = false
var _placement_locked: bool = false
var _tutorial_allowed_ids: Array = []
var _tutorial_allowed_attributes: Array = []


func _ready() -> void:
	GameEvents.units_changed.connect(_update_reset_button)
	GameEvents.tutorial_filter_sidebar.connect(_on_tutorial_filter)
	GameEvents.mp_placement_locked.connect(_on_mp_placement_locked)
	GameEvents.tutorial_filter_attributes.connect(_on_tutorial_filter_attributes)
	GameEvents.selection_changed.connect(_on_selection_changed)
	resized.connect(func(): GameEvents.sidebar_resized.emit(SIDEBAR_WIDTH))
	_build_sidebar()
	_refresh_attribute_panel()

	# Publish initial size so listeners (BaseLevel) get a value before any resize.
	GameEvents.sidebar_resized.emit.call_deferred(size.x)
	_refresh_attribute_panel()

	# Publish the fixed design width to listeners (BaseLevel). Constant, not the
	# live size.x, so attribute-panel growth doesn't recenter the map.
	GameEvents.sidebar_resized.emit.call_deferred(SIDEBAR_WIDTH)


func _on_selection_changed(unit: Node) -> void:
	if unit is Unit and unit.definition:
		var t := _entity_type_for_def_id(unit.definition.id)
		select_entity(t, unit.definition.display_name, unit)
	else:
		select_entity(EntityType.NONE)


func _entity_type_for_def_id(id: StringName) -> EntityType:
	match id:
		&"transceiver":
			return EntityType.TRANSCEIVER
		&"jammer":
			return EntityType.JAMMER
		&"sensor":
			return EntityType.SENSOR
	return EntityType.NONE


func select_entity(type: EntityType, display_name: String = "", node: Node = null) -> void:
	# In tutorial mode, only block sidebar card selection for disallowed types.
	# Do not block already placed units. The attribute panel must still refresh
	# when the user clicks a placed unit on the map.
	if _tutorial_active and node == null and type != EntityType.NONE:
		if not _is_entity_type_allowed(type):
			return

	if type != EntityType.NONE and type != pending_entity_type:
		pending_attributes.clear()

	selected_entity = type
	selected_entity_name = display_name
	selected_node = node

	if node == null and type != EntityType.NONE:
		pending_entity_type = type
	else:
		pending_entity_type = EntityType.NONE
		pending_attributes.clear()

	_refresh_attribute_panel()
	_update_reset_button()


# ════════════════════════════════════════════
#  BUILD
# ════════════════════════════════════════════


func _build_sidebar() -> void:
	# Root layout (VBoxContainer "Layout") + named section slots (Header/Tray/
	# Divider/AttrSection) come from Sidebar.tscn. Styling + dynamic content
	# still live in script for now (B4 skeleton extraction; theme migration TBD).
	_apply_style(self, C_BG_DARK, C_BORDER, 0, 0, 0, 1)
	_populate_header(_header_slot)
	_populate_tray(_tray_slot)
	_style_divider(_divider_slot)
	_populate_attr_section(_attr_section)


func _populate_header(panel: PanelContainer) -> void:
	_apply_style(panel, C_BG_MID, C_GREEN, 0, 2, 0, 0)
	panel.add_theme_stylebox_override("panel", _flat_style(C_BG_MID, 12))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)

	# GEMS branding lives only in the HTML navbar now (NavBar.astro) — the green
	# pulsing dot + wordmark moved there so the canvas isn't a second branding.
	# This header keeps just the action buttons.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Multiplayer pages set `window.GAME_MODE = "multiplayer"` before the
	# engine boots, which we read here to relabel the header buttons:
	# SAVES → SUBMIT and RESET → UNDO. The click handlers stay the same
	# for now; only the labels swap.
	var is_mp := _get_game_mode() == "multiplayer"

	var level := get_tree().current_scene
	var is_sb: bool = level.get_game_mode_name() == "sandbox"

	# SAVES / SUBMIT — only meaningful on web export (where JS bridge exists).
	if OS.has_feature("web") and (is_mp or is_sb):
		var saves_btn := Button.new()
		saves_btn.text = "SUBMIT" if is_mp else "SAVES"
		saves_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		saves_btn.add_theme_font_size_override("font_size", 13)
		saves_btn.add_theme_color_override("font_color", C_BG_DARK)
		saves_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var saves_style := StyleBoxFlat.new()
		saves_style.bg_color = C_BLUE
		saves_style.corner_radius_top_left = 3
		saves_style.corner_radius_top_right = 3
		saves_style.corner_radius_bottom_left = 3
		saves_style.corner_radius_bottom_right = 3
		saves_style.set_content_margin_all(8)
		saves_btn.add_theme_stylebox_override("normal", saves_style)
		saves_btn.pressed.connect(_on_saves_pressed)
		hbox.add_child(saves_btn)

	var reset_btn := Button.new()
	reset_btn.text = "UNDO" if is_mp else "RESET"
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

	_update_reset_button()


func _on_saves_pressed() -> void:
	# Same button, two behaviors based on the page that booted us:
	#   • Sandbox → opens the SavesPicker Preact island (window.openSavesPicker)
	#   • Multiplayer → emit mp_submit_requested; BaseLevel handles the
	#     serialize-and-bridge (it owns the unit list, Sidebar doesn't).
	if not OS.has_feature("web"):
		return
	var mode := _get_game_mode()
	print("[Sidebar] header button pressed (mode=", mode, ")")
	if mode == "multiplayer":
		GameEvents.mp_submit_requested.emit()
	else:
		JavaScriptBridge.eval("window.openSavesPicker && window.openSavesPicker()")


# Mirrors the JS-side `window.GAME_MODE` set by each game page (sandbox.astro,
# multiplayer/play.astro) before the engine boots. Defaults to "sandbox" so
# non-web builds and any page that forgets to set the flag behave like the
# single-player path.
func _get_game_mode() -> String:
	if not OS.has_feature("web"):
		return "sandbox"
	var v: Variant = JavaScriptBridge.eval("window.GAME_MODE")
	if v is String and (v as String).length() > 0:
		return v as String
	return "sandbox"


func _populate_tray(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", _flat_style(C_BG_MID, 14))
	# Hug content height so the tray only takes what the cards + hint need; the
	# attribute panel below gets the freed vertical space.
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(_make_label("ENTITIES", C_DIM, 15))

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	vbox.add_child(stack)

	var tx_card := _build_entity_card(
		"Transceiver",
		"T",
		C_BLUE,
		EntityType.TRANSCEIVER,
		"res://scenes/core/units/TransceiverUnit.tscn",
		"res://assets/sprites/transceiver.png"
	)
	stack.add_child(tx_card)
	_entity_cards[EntityType.TRANSCEIVER] = tx_card

	var jm_card := _build_entity_card(
		"Jammer",
		"J",
		C_RED,
		EntityType.JAMMER,
		"res://scenes/core/units/JammerUnit.tscn",
		"res://assets/sprites/jammer.png"
	)
	stack.add_child(jm_card)
	_entity_cards[EntityType.JAMMER] = jm_card

	var sn_card := _build_entity_card(
		"Sensor",
		"S",
		C_PURPLE,
		EntityType.SENSOR,
		"res://scenes/core/units/SensorUnit.tscn",
		"res://assets/sprites/sensor.png"
	)
	stack.add_child(sn_card)
	_entity_cards[EntityType.SENSOR] = sn_card

	var hint := _make_label("drag entities onto the scene", C_DIM, 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)


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
	# Drag payload picks up the user's pending attribute tweaks.
	card.pending_provider = func(): return pending_attributes.duplicate()
	card.pressed.connect(
		func():
			# Drop any prior unit selection so the highlight clears with the panel.
			GameEvents.clear_selection()
			select_entity(type, label, null)
	)
	return card


func _populate_attr_section(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", _flat_style(C_BG_MID, 14))

	_attr_content = VBoxContainer.new()
	_attr_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_attr_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attr_content.add_theme_constant_override("separation", 12)
	panel.add_child(_attr_content)

	var attr_header_row := HBoxContainer.new()
	attr_header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Reserve the DELETE/CONFIRM button height always, so the row doesn't grow
	# (and shove "ATTRIBUTES"/the panel down) when those buttons toggle on
	# selecting a live unit.
	attr_header_row.custom_minimum_size.y = ATTR_HEADER_ROW_HEIGHT
	attr_header_row.add_theme_constant_override("separation", 8)
	_attr_content.add_child(attr_header_row)

	var attr_title := _make_label("ATTRIBUTES", C_DIM, 15)
	attr_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	attr_header_row.add_child(attr_title)

	# Spacer pushes action buttons to the right of the title row so the
	# layout is stable whether or not those buttons are visible — no
	# separate row appears/disappears on selection change.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attr_header_row.add_child(spacer)

	var delete_btn := Button.new()
	delete_btn.text = "DELETE"
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
	delete_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	delete_btn.pressed.connect(_on_delete_pressed)
	delete_btn.visible = false

	attr_header_row.add_child(delete_btn)
	_delete_btn = delete_btn

	var confirm_btn := Button.new()
	confirm_btn.text = "CONFIRM"
	confirm_btn.add_theme_font_size_override("font_size", 12)
	confirm_btn.add_theme_color_override("font_color", C_BG_DARK)
	confirm_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var cfm_style := StyleBoxFlat.new()
	cfm_style.bg_color = C_GREEN
	cfm_style.corner_radius_top_left = 3
	cfm_style.corner_radius_top_right = 3
	cfm_style.corner_radius_bottom_left = 3
	cfm_style.corner_radius_bottom_right = 3
	cfm_style.set_content_margin_all(8)
	confirm_btn.add_theme_stylebox_override("normal", cfm_style)
	confirm_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	confirm_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	confirm_btn.pressed.connect(_on_confirm_pressed)
	confirm_btn.visible = false

	attr_header_row.add_child(confirm_btn)
	_confirm_btn = confirm_btn

	_attr_header = _make_label("", C_TEXT, 20)
	_attr_content.add_child(_attr_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_attr_content.add_child(scroll)

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
	# Attach the placeholder OUTSIDE _attr_content so toggling its visibility
	# doesn't reflow the attribute panel layout when a unit gets selected.
	panel.add_child(_attr_placeholder)


func _style_divider(sep: HSeparator) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = C_BORDER
	sep.add_theme_stylebox_override("separator", s)


func _refresh_attribute_panel() -> void:
	for child in _attr_body.get_children():
		child.queue_free()

	if _delete_btn:
		_delete_btn.visible = selected_entity != EntityType.NONE and selected_node != null

	if _confirm_btn:
		_confirm_btn.visible = selected_entity != EntityType.NONE and selected_node != null

	if selected_entity == EntityType.NONE:
		_attr_header.visible = false
		_attr_placeholder.visible = true
		return

	_attr_placeholder.visible = false
	_attr_header.visible = true

	# Locked pieces (the objective, already-submitted pieces, the opponent's)
	# are inspectable but not editable: hide the action buttons, disable inputs.
	var is_locked := (
		selected_node is Unit
		and (selected_node as Unit).has_method("is_locked")
		and (selected_node as Unit).is_locked()
	)
	if _delete_btn:
		_delete_btn.visible = _delete_btn.visible and not is_locked
	if _confirm_btn:
		_confirm_btn.visible = _confirm_btn.visible and not is_locked

	var def := _definition_for(selected_entity)
	if def == null:
		return

	_attr_header.text = def.display_name
	_attr_header.add_theme_color_override("font_color", def.color)
	_add_accent_bar(def.color)

	for spec in def.attributes:
		_add_attribute_input(spec, def)

	# Transceivers get a "Send Message" button that visualizes frequency-
	# dependent transmission delay. Only meaningful for placed, editable units.
	if selected_node is Unit and def.id == &"transceiver" and not is_locked:
		_add_send_message_button(def.color)

	# Lock the attribute inputs when the piece can't be edited: my is_locked
	# (objective / submitted / opponent's / immovable) OR main's non-removable
	# flag.
	var lock_inputs := is_locked
	if selected_node and "is_removable" in selected_node and not selected_node.is_removable:
		lock_inputs = true
	if selected_node and selected_node.has_method("attributes_unlocked_override") and selected_node.attributes_unlocked_override():
		lock_inputs = false
	_attr_body.modulate.a = 0.7 if lock_inputs else 1.0
	_lock_all_attributes(lock_inputs)

	# Reapply the stored tutorial filter after every row rebuild.
	# queue_free() is deferred, so we defer this too to run after the
	# new rows are fully added to the scene tree.
	if not _tutorial_allowed_attributes.is_empty():
		call_deferred("_reapply_current_tutorial_attribute_filter")


func _add_send_message_button(accent: Color) -> void:
	var btn := Button.new()
	btn.text = "SEND MESSAGE"
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", C_BG_DARK)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	btn.pressed.connect(func(): GameEvents.message_send_requested.emit(selected_node))
	_attr_body.add_child(btn)


func _reapply_current_tutorial_attribute_filter() -> void:
	_on_tutorial_filter_attributes(_tutorial_allowed_attributes.duplicate())


func _definition_for(t: EntityType) -> UnitDefinition:
	match t:
		EntityType.TRANSCEIVER:
			return TRANSCEIVER_DEF
		EntityType.JAMMER:
			return JAMMER_DEF
		EntityType.SENSOR:
			return SENSOR_DEF
	return null


func _add_attribute_input(spec: AttributeSpec, def: UnitDefinition) -> void:
	var accent := def.color
	var current = _read_attribute(spec, def)
	var attribute_key := String(spec.id)

	match spec.kind:
		AttributeSpec.Kind.INT:
			_add_slider(
				spec.display_name,
				spec.min_value,
				spec.max_value,
				float(current),
				spec.unit,
				accent,
				func(v): _write_attribute(spec.id, int(v)),
				true,
				attribute_key
			)
		AttributeSpec.Kind.FLOAT:
			_add_slider(
				spec.display_name,
				spec.min_value,
				spec.max_value,
				float(current),
				spec.unit,
				accent,
				func(v): _write_attribute(spec.id, v),
				false,
				attribute_key
			)
		AttributeSpec.Kind.ENUM:
			_add_dropdown(
				spec.display_name,
				Array(spec.enum_options),
				int(current),
				accent,
				func(v): _write_attribute(spec.id, v),
				attribute_key
			)
		AttributeSpec.Kind.BOOL:
			_add_toggle(
				spec.display_name,
				bool(current),
				accent,
				func(v): _write_attribute(spec.id, v),
				attribute_key
			)
		AttributeSpec.Kind.STRING:
			_add_text_input(
				spec.display_name,
				str(current),
				accent,
				func(v): _write_attribute(spec.id, v),
				attribute_key
			)


func _read_attribute(spec: AttributeSpec, def: UnitDefinition):
	if selected_node and selected_node is Unit:
		return selected_node.get_value(spec.id, spec.default_value)
	if pending_attributes.has(spec.id):
		return pending_attributes[spec.id]
	# Special case: name placeholder shows the next auto-name.
	if spec.id == &"unit_name":
		return UnitNameManager.peek_next_name(def.id)
	return spec.default_value


func _write_attribute(id: StringName, value) -> void:
	if selected_node and selected_node is Unit:
		selected_node.set_value(id, value)
	else:
		pending_attributes[id] = value


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
	integers: bool = false,
	attribute_key: String = ""
) -> void:
	var vbox := _make_row_container(attribute_key)

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
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Min keeps the +/− arrows usable; otherwise scales with row width.
	spin.custom_minimum_size = Vector2(70, 0)
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
	label: String,
	options: Array,
	current_idx: int,
	accent: Color,
	on_change: Callable,
	attribute_key: String = ""
) -> void:
	var vbox := _make_row_container(attribute_key)
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)
	hbox.add_child(_make_label(label, C_DIM, 13, true))

	var dd := OptionButton.new()
	dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dd.custom_minimum_size = Vector2(70, 0)
	dd.add_theme_font_size_override("font_size", 13)
	dd.add_theme_color_override("font_color", accent)

	for opt in options:
		dd.add_item(opt)

	dd.select(current_idx)
	dd.item_selected.connect(func(idx): on_change.call(idx))
	hbox.add_child(dd)


func _add_toggle(
	label: String, current: bool, accent: Color, on_change: Callable, attribute_key: String = ""
) -> void:
	var vbox := _make_row_container(attribute_key)
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


func _make_row_container(attribute_key: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()

	if attribute_key != "":
		panel.name = attribute_key

	panel.add_theme_stylebox_override("panel", _flat_style(C_BG_LIGHT, 10))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attr_body.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	return vbox


func _on_reset_pressed() -> void:
	# In multiplayer this button is "UNDO": pull back the current turn's
	# unsubmitted placement immediately — no confirmation dialog.
	if _get_game_mode() == "multiplayer":
		GameEvents.reset_requested.emit()
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset Scene"
	dialog.dialog_text = "Remove all units from the scene?"
	dialog.ok_button_text = "Reset"
	dialog.cancel_button_text = "Cancel"
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

	dialog.confirmed.connect(
		func():
			GameEvents.reset_requested.emit()
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

	var to_delete = selected_node
	dialog.confirmed.connect(
		func():
			GameEvents.delete_requested.emit(to_delete)
			dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())


func _on_confirm_pressed() -> void:
	if not selected_node:
		return

	# Drop any LineEdit focus so its focus_exited fires (flushes the typed
	# value through _write_attribute) and the keyboard isn't trapped after
	# the user commits. Selection stays — Confirm is "apply + sim", not
	# "apply + close" (that was the older qol-bugs behavior — see commit
	# history if you want to revert).
	get_viewport().gui_release_focus()

	# _write_attribute writes through to selected_node.set_value when a Unit
	# is selected, so pending is normally empty here; flush stragglers just
	# in case.
	if selected_node is Unit:
		for id in pending_attributes:
			selected_node.set_value(id, pending_attributes[id])
	pending_attributes.clear()

	GameEvents.confirm_pressed.emit(selected_node)
	GameEvents.units_changed.emit()
	GameEvents.simulation_requested.emit()


func _update_reset_button() -> void:
	if not is_inside_tree():
		return

	var tree := get_tree()
	if tree == null:
		return

	var has_units = (
		get_tree().get_nodes_in_group("transceivers").size() > 0
		or get_tree().get_nodes_in_group("jammers").size() > 0
		or get_tree().get_nodes_in_group("sensors").size() > 0
	)

	if _reset_btn:
		_reset_btn.disabled = not has_units
		_reset_btn.mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if has_units else Control.CURSOR_ARROW
		)


func _on_simulate_pressed() -> void:
	GameEvents.simulation_requested.emit()


func _add_text_input(
	label: String, current: String, accent: Color, on_change: Callable, attribute_key: String = ""
) -> void:
	var vbox := _make_row_container(attribute_key)
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)
	hbox.add_child(_make_label(label, C_DIM, 13, true))

	var input := LineEdit.new()
	input.text = current
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(60, 0)
	input.add_theme_font_size_override("font_size", 13)
	input.add_theme_color_override("font_color", accent)
	input.text_submitted.connect(func(v): on_change.call(v))
	input.focus_exited.connect(func(): on_change.call(input.text))
	hbox.add_child(input)


# ════════════════════════════════════════════
#  STYLE HELPERS
# ════════════════════════════════════════════


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


## Shorthand label factory. No fixed minimum width — text intrinsic-sizes itself
## so rows stay narrower than the sidebar's content area. Set `expand=true` for
## row labels that should grab leftover horizontal space.
func _make_label(text: String, color: Color, txt_size: int, expand: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", txt_size)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _on_tutorial_filter(allowed_ids: Array) -> void:
	# Supports the newer UnitDefinition ids, such as &"transceiver", while also
	# accepting the older EntityType enum values from EMS-183 if TutorialLevel
	# still emits those.
	_tutorial_allowed_ids = allowed_ids
	_tutorial_active = not allowed_ids.is_empty()

	for type in _entity_cards:
		var card = _entity_cards[type]
		_set_card_enabled(card, not _tutorial_active or _is_entity_type_allowed(type))


# Multiplayer one-per-turn cap: grey the whole entity tray while the player
# has already placed their unit for this turn (re-enabled on turn advance).
func _on_mp_placement_locked(locked: bool) -> void:
	_placement_locked = locked
	for type in _entity_cards:
		_set_card_enabled(_entity_cards[type], not locked)


# Shared card enable/disable — used by both the tutorial filter and the MP
# placement cap, with the full input gating main applied inline.
func _set_card_enabled(card, enabled: bool) -> void:
	card.modulate.a = 1.0 if enabled else 0.3
	card.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	card.set_process_input(enabled)
	card.set_process_unhandled_input(enabled)
	card.set_process_unhandled_key_input(enabled)
	for child in card.get_children():
		if child is Control:
			child.mouse_filter = (
				Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
			)


func _is_entity_type_allowed(type: EntityType) -> bool:
	if _tutorial_allowed_ids.is_empty():
		return true

	var def := _definition_for(type)
	if def and def.id in _tutorial_allowed_ids:
		return true
	if def and String(def.id) in _tutorial_allowed_ids:
		return true
	if type in _tutorial_allowed_ids:
		return true

	return false


func _on_tutorial_filter_attributes(allowed_attributes: Array) -> void:
	_tutorial_allowed_attributes = allowed_attributes

	if _attr_body == null:
		return

	var lock_all := false
	for allowed_attribute in allowed_attributes:
		var allowed_text := str(allowed_attribute).to_lower()
		if allowed_text == "__lock_all__":
			lock_all = true
			break

	var lock_attributes := lock_all or not allowed_attributes.is_empty()

	for row in _attr_body.get_children():
		if not row is Control:
			continue

		var row_name := row.name.to_lower()
		var enabled := not lock_attributes

		if lock_all:
			enabled = false
		else:
			for allowed_attribute in allowed_attributes:
				var allowed_text := str(allowed_attribute).to_lower()

				if row_name == allowed_text or row_name.contains(allowed_text):
					enabled = true
					break

		row.modulate.a = 1.0 if enabled else 0.35
		_set_interactivity(row, enabled)


func _lock_all_attributes(is_locked: bool) -> void:
	_attr_content.modulate.a = 0.3 if is_locked else 1.0
	_set_interactivity(_attr_content, not is_locked)
	_attr_content.mouse_default_cursor_shape = (
		Control.CURSOR_FORBIDDEN if is_locked else Control.CURSOR_ARROW
	)


func _set_interactivity(node: Control, enabled: bool) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

	for child in node.get_children():
		if child is Control:
			_set_interactivity(child, enabled)
