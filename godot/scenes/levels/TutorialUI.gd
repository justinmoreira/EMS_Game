class_name TutorialUI
extends RefCounted

const TUTORIAL_HINT_POPUP := preload("res://scenes/ui/HintPopup.tscn")
const TUTORIAL_COMPLETION_POPUP := preload("res://scenes/ui/TutorialCompletionPopup.tscn")

var level: Node
var popup_history: Array[Dictionary] = []
var popup_history_index := -1
var repeat_instruction_button: Button = null
var completion_popup: Control = null
var placement_marker: Control = null
var placement_marker_world_uv := Vector2.ZERO

func _init(p_level: Node) -> void:
	level = p_level

func create_repeat_instruction_button() -> void:
	if repeat_instruction_button != null and is_instance_valid(repeat_instruction_button):
		return
	if not level.has_node("CanvasLayer"):
		return

	var button := Button.new()
	button.name = "RepeatInstructionButton"
	button.text = "Show Instruction"
	button.tooltip_text = "Show the current tutorial instruction again."
	button.custom_minimum_size = Vector2(180, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP

	button.anchor_left = 1.0
	button.anchor_top = 0.0
	button.anchor_right = 1.0
	button.anchor_bottom = 0.0
	button.offset_left = -210.0
	button.offset_top = 75.0
	button.offset_right = -16.0
	button.offset_bottom = 117.0

	button.pressed.connect(_on_repeat_instruction_button_pressed)
	level.get_node("CanvasLayer").add_child(button)
	repeat_instruction_button = button
	update_repeat_instruction_button_visibility()

func update_repeat_instruction_button_visibility() -> void:
	if repeat_instruction_button == null or not is_instance_valid(repeat_instruction_button):
		return

	var has_instruction : bool = not level._current_instruction_text.strip_edges().is_empty()
	var tutorial_finished : bool = level._tutorial_step == level.TUTORIAL_STEP.COMPLETE
	repeat_instruction_button.visible = (
		has_instruction and not level.intro_popup_open and not tutorial_finished
	)

func _on_repeat_instruction_button_pressed() -> void:
	if level.intro_popup_open:
		return

	var text : String = level._current_instruction_text.strip_edges()
	if text.is_empty():
		var data : Dictionary = level._step_data(level._tutorial_step)
		text = str(data.get("text", "")).strip_edges()

	if text.is_empty():
		return

	show_repeat_instruction_popup(text)

func show_repeat_instruction_popup(text: String) -> void:
	TutorialUtils.remove_sandbox_intro_popups(level.get_tree())
	if level.intro_popup_open:
		return
	if not level.has_node("CanvasLayer"):
		return

	var popup := TUTORIAL_HINT_POPUP.instantiate()
	popup.name = "TutorialRepeatInstructionPopup"
	popup.set("hint_text", "Current instruction:\n\n" + text)

	level.intro_popup_open = true
	update_repeat_instruction_button_visibility()
	level.get_node("CanvasLayer").add_child(popup)

	popup.tree_exited.connect(
		func():
			if not has_tutorial_popup_open():
				level.intro_popup_open = false
			update_repeat_instruction_button_visibility()
	)

func show_popup(text: String, next_step: int = -1) -> void:
	TutorialUtils.remove_sandbox_intro_popups(level.get_tree())
	if level.intro_popup_open:
		return
	popup_history.append({"text": text, "next_step": next_step})
	popup_history_index = popup_history.size() - 1
	display_popup_history_entry()

func display_popup_history_entry() -> void:
	TutorialUtils.remove_sandbox_intro_popups(level.get_tree())
	update_repeat_instruction_button_visibility()
	if popup_history_index < 0 or popup_history_index >= popup_history.size():
		return
	var entry: Dictionary = popup_history[popup_history_index]
	var popup := TUTORIAL_HINT_POPUP.instantiate()
	popup.name = "TutorialHintPopup"
	popup.set("hint_text", str(entry.get("text", "")))
	popup.set("show_previous", popup_history_index > 0)
	popup.set("show_next", true)
	level.intro_popup_open = true
	update_repeat_instruction_button_visibility()
	level.get_node("CanvasLayer").add_child(popup)
	if popup.has_signal("previous_requested"):
		popup.previous_requested.connect(_on_popup_previous_requested)
	if popup.has_signal("continued"):
		popup.continued.connect(_on_popup_next_requested)
	popup.tree_exited.connect(
		func():
			if not has_tutorial_popup_open():
				level.intro_popup_open = false
			update_repeat_instruction_button_visibility()
	)

func _on_popup_previous_requested() -> void:
	level.intro_popup_open = false
	if popup_history_index <= 0:
		return
	popup_history_index -= 1
	call_deferred("display_popup_history_entry")

func _on_popup_next_requested() -> void:
	level.intro_popup_open = false
	if level._wrong_placement_popup_open:
		return
	if popup_history_index < popup_history.size() - 1:
		popup_history_index += 1
		call_deferred("display_popup_history_entry")
		return
	var entry: Dictionary = popup_history[popup_history_index]
	var next_step := int(entry.get("next_step", -1))

	if next_step != -1:
		level.call_deferred("_enter_step", next_step)
		return

	if not level._attributes_for_current_step().is_empty():
		level.call_deferred("_restore_current_edit_state")

func has_tutorial_popup_open() -> bool:
	if not level.has_node("CanvasLayer"):
		return false
	for child in level.get_node("CanvasLayer").get_children():
		var child_name := child.name.to_lower()
		if child_name.contains("tutorial") and child_name.contains("popup"):
			return true
	return false

func show_completion_popup() -> void:
	TutorialUtils.remove_sandbox_intro_popups(level.get_tree())
	update_repeat_instruction_button_visibility()
	if completion_popup != null and is_instance_valid(completion_popup):
		return
	level.intro_popup_open = true
	completion_popup = TUTORIAL_COMPLETION_POPUP.instantiate()
	completion_popup.name = "TutorialCompletionPopup"
	level.get_node("CanvasLayer").add_child(completion_popup)
	completion_popup.tree_exited.connect(
		func():
			level.intro_popup_open = false
			update_repeat_instruction_button_visibility()
	)

func show_placement_marker(world_uv: Vector2, label_text: String) -> void:
	clear_placement_marker()
	var marker := PanelContainer.new()
	marker.name = "TutorialPlacementMarker"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.custom_minimum_size = Vector2(100, 70)
	marker.z_index = 50
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.85, 0.1, 0.25)
	style.border_color = Color(1.0, 0.85, 0.1, 1.0)
	style.set_border_width_all(3)
	marker.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	marker.add_child(label)
	level.map_container.add_child(marker)
	placement_marker = marker
	placement_marker_world_uv = world_uv
	position_placement_marker()

func position_placement_marker() -> void:
	if placement_marker == null or not is_instance_valid(placement_marker):
		return
	var global_pos: Vector2 = level.global_position + level.world_uv_to_screen(placement_marker_world_uv)
	var container_local: Vector2 = global_pos - level.map_container.global_position
	placement_marker.position = container_local - placement_marker.custom_minimum_size * 0.5

func clear_placement_marker() -> void:
	if placement_marker != null and is_instance_valid(placement_marker):
		placement_marker.queue_free()
	placement_marker = null

func show_wrong_placement_popup() -> void:
	if level._wrong_placement_popup_open:
		return
	level._wrong_placement_popup_open = true
	show_popup(level.TUTORIAL_TEXT.wrong_placement_text())
