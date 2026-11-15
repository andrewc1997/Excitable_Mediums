

extends Node

# EM4 grouped palette and inspector. Godot 4.3.
var builder: Node2D
var ui_layer: CanvasLayer
var palette_panel: PanelContainer
var inspector_panel: PanelContainer
var selected_uid: String = ""
var updating_controls: bool = false
var category_buttons: Dictionary = {}
var template_row: HBoxContainer
var active_category: String = "Routing"
var selected_label: Label
var node_type_option: OptionButton
var cap_container: VBoxContainer
var refractory_container: VBoxContainer
var splitter_fields: VBoxContainer
var blocker_amount_fields: VBoxContainer
var gate_amount_fields: VBoxContainer
var direction_fields: VBoxContainer
var direction_option: OptionButton
var channel_fields: VBoxContainer
var delay_fields: VBoxContainer
var repeater_fields: VBoxContainer
var cap_spin: SpinBox
var refractory_spin: SpinBox
var inputs_spin: SpinBox
var outputs_spin: SpinBox
var blocker_hits_spin: SpinBox
var gate_passes_spin: SpinBox
var delay_spin: SpinBox
var repeat_count_spin: SpinBox
var repeat_interval_spin: SpinBox
var channel_option: OptionButton

func _ready() -> void:
	call_deferred("_initialize_ui")

func _initialize_ui() -> void:
	builder = get_parent() as Node2D
	ui_layer = builder.get_node("CanvasLayer") as CanvasLayer
	create_palette()
	create_inspector()
	show_selected_node("")

func create_palette() -> void:
	palette_panel = PanelContainer.new()
	palette_panel.name = "NodePalette"
	ui_layer.add_child(palette_panel)
	palette_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	palette_panel.offset_left = 12.0
	palette_panel.offset_right = -12.0
	palette_panel.offset_top = -145.0
	palette_panel.offset_bottom = -8.0
	var column := VBoxContainer.new()
	palette_panel.add_child(column)
	var heading := Label.new()
	heading.text = "NODE LIBRARY — Drag a template onto the grid"
	column.add_child(heading)
	var categories := HBoxContainer.new()
	column.add_child(categories)
	for category_name in ["Routing", "Processing", "Blockers", "Gates", "Targets"]:
		var button := Button.new()
		button.text = category_name
		button.toggle_mode = true
		button.pressed.connect(_select_category.bind(category_name))
		categories.add_child(button)
		category_buttons[category_name] = button
	template_row = HBoxContainer.new()
	template_row.add_theme_constant_override("separation", 12)
	column.add_child(template_row)
	_select_category("Routing")

func _select_category(category_name: String) -> void:
	active_category = category_name
	for key in category_buttons.keys():
		var button: Button = category_buttons[key]
		button.set_pressed_no_signal(str(key) == category_name)
	for child in template_row.get_children():
		template_row.remove_child(child)
		child.queue_free()
	match category_name:
		"Routing":
			add_template("▶ Begin", PuzzleNode.Kind.BEGIN)
			add_template("● Neutral", PuzzleNode.Kind.NORMAL)
			add_template("A Alternating", PuzzleNode.Kind.ALTERNATING)
			add_template("↶ Bounce", PuzzleNode.Kind.BOUNCE)
		"Processing":
			add_template("1<2 Splitter", PuzzleNode.Kind.SPLITTER)
			add_template("◷ Delay", PuzzleNode.Kind.DELAY)
			add_template("••• Repeater", PuzzleNode.Kind.REPEATER)
		"Blockers":
			add_template("Single Blocker", PuzzleNode.Kind.BLOCKER_SINGLE)
			add_template("Amount Blocker", PuzzleNode.Kind.BLOCKER_AMOUNT)
			add_template("Target Blocker", PuzzleNode.Kind.BLOCKER_TARGET)
		"Gates":
			add_template("Amount Gate", PuzzleNode.Kind.GATE_AMOUNT)
			add_template("➜ One-Way Gate", PuzzleNode.Kind.ONE_WAY_GATE)
		"Targets":
			add_template("T Goal Target", PuzzleNode.Kind.TARGET)
			add_template("T Trigger Target", PuzzleNode.Kind.TRIGGER_TARGET)
			
		"Routing":
			add_template("▶ Begin", PuzzleNode.Kind.BEGIN)
			add_template("● Neutral", PuzzleNode.Kind.NORMAL)
			add_template("A Alternating", PuzzleNode.Kind.ALTERNATING)
			add_template("↶ Bounce", PuzzleNode.Kind.BOUNCE)


func add_template(title: String, kind: int) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(145,45)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.gui_input.connect(_on_template_input.bind(kind))
	template_row.add_child(button)

func _on_template_input(event: InputEvent, kind: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			builder.begin_palette_drag(kind)

func create_inspector() -> void:
	inspector_panel = PanelContainer.new()
	inspector_panel.name = "NodeInspector"
	ui_layer.add_child(inspector_panel)
	inspector_panel.anchor_left = 1.0
	inspector_panel.anchor_right = 1.0
	inspector_panel.anchor_top = 0.0
	inspector_panel.anchor_bottom = 1.0
	inspector_panel.offset_left = -265.0
	inspector_panel.offset_right = -12.0
	inspector_panel.offset_top = 215.0
	inspector_panel.offset_bottom = -155.0
	var scroll := ScrollContainer.new()
	inspector_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 215.0
	scroll.add_child(column)
	var title := Label.new()
	title.text = "NODE PROPERTIES"
	title.add_theme_font_size_override("font_size", 19)
	column.add_child(title)
	selected_label = Label.new()
	column.add_child(selected_label)
	add_field_label(column, "Node Type")
	node_type_option = OptionButton.new()
	var names: Array[String] = [
		"Neutral", "Splitter", "Alternating", "Goal Target",
		"Single Blocker", "Amount Blocker", "Target Blocker",
		"Amount Gate", "Trigger Target", "Delay", "Repeater", "Bounce", "One-Way Gate","Begin"
	]
	for i in range(names.size()):
		node_type_option.add_item(names[i], i)
	column.add_child(node_type_option)
	node_type_option.item_selected.connect(_on_kind_changed)
	cap_container = VBoxContainer.new()
	column.add_child(cap_container)
	add_field_label(cap_container, "Activation Cap / Required Target Hits")
	cap_spin = create_spin(cap_container, 1, 100)
	cap_spin.value_changed.connect(_on_number_changed.bind("cap"))
	refractory_container = VBoxContainer.new()
	column.add_child(refractory_container)
	add_field_label(refractory_container, "Refractory Ticks")
	refractory_spin = create_spin(refractory_container, 0, 100)
	refractory_spin.value_changed.connect(_on_number_changed.bind("refractory"))
	splitter_fields = VBoxContainer.new()
	column.add_child(splitter_fields)
	add_field_label(splitter_fields, "Required Inputs")
	inputs_spin = create_spin(splitter_fields, 1, 6)
	inputs_spin.value_changed.connect(_on_number_changed.bind("inputs"))
	add_field_label(splitter_fields, "Output Signals")
	outputs_spin = create_spin(splitter_fields, 1, 6)
	outputs_spin.value_changed.connect(_on_number_changed.bind("outputs"))
	blocker_amount_fields = VBoxContainer.new()
	column.add_child(blocker_amount_fields)
	add_field_label(blocker_amount_fields, "Signals Blocked Before Opening")
	blocker_hits_spin = create_spin(blocker_amount_fields, 1, 100)
	blocker_hits_spin.value_changed.connect(_on_number_changed.bind("blocker_hits"))
	gate_amount_fields = VBoxContainer.new()
	column.add_child(gate_amount_fields)
	add_field_label(gate_amount_fields, "Signals Allowed Before Closing")
	gate_passes_spin = create_spin(gate_amount_fields, 1, 100)
	gate_passes_spin.value_changed.connect(_on_number_changed.bind("gate_passes"))
	channel_fields = VBoxContainer.new()
	column.add_child(channel_fields)
	add_field_label(channel_fields, "Trigger Channel")
	channel_option = OptionButton.new()
	channel_option.add_item("Purple", PuzzleNode.Channel.PURPLE)
	channel_option.add_item("Blue", PuzzleNode.Channel.BLUE)
	channel_option.add_item("Green", PuzzleNode.Channel.GREEN)
	channel_option.add_item("Red", PuzzleNode.Channel.RED)
	channel_fields.add_child(channel_option)
	channel_option.item_selected.connect(_on_channel_changed)
	delay_fields = VBoxContainer.new()
	column.add_child(delay_fields)
	add_field_label(delay_fields, "Delay Duration (Ticks)")
	delay_spin = create_spin(delay_fields, 1, 100)
	delay_spin.value_changed.connect(_on_number_changed.bind("delay_ticks"))
	repeater_fields = VBoxContainer.new()
	column.add_child(repeater_fields)
	add_field_label(repeater_fields, "Repeater: Number of Pulses")
	repeat_count_spin = create_spin(repeater_fields, 1, 100)
	repeat_count_spin.value_changed.connect(_on_number_changed.bind("repeat_count"))
	add_field_label(repeater_fields, "Repeater: Interval (Ticks)")
	repeat_interval_spin = create_spin(repeater_fields, 1, 100)
	repeat_interval_spin.value_changed.connect(_on_number_changed.bind("repeat_interval"))

	direction_fields = VBoxContainer.new()
	column.add_child(direction_fields)
	add_field_label(direction_fields, "Allowed Travel Direction")
	direction_option = OptionButton.new()
	for text_dir in ["North ↑", "East →", "South ↓", "West ←"]:
		direction_option.add_item(text_dir)
	direction_fields.add_child(direction_option)
	direction_option.item_selected.connect(_on_direction_changed)

func add_field_label(parent: Node, title: String) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
func create_spin(parent: Node, minimum: int, maximum: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1.0
	spin.rounded = true
	parent.add_child(spin)
	return spin

func show_selected_node(uid: String) -> void:
	selected_uid = uid
	if inspector_panel == null: return
	var valid: bool = not uid.is_empty() and builder.nodes_by_id.has(uid)
	selected_label.text = "Selected: " + uid if valid else "No node selected"
	node_type_option.disabled = not valid
	for section in [cap_container, refractory_container, splitter_fields, blocker_amount_fields, gate_amount_fields, channel_fields, delay_fields, repeater_fields, direction_fields]:
		section.hide()
	if not valid: return
	var node: PuzzleNode = builder.nodes_by_id[uid]
	updating_controls = true
	selected_label.text = "%s | Cell (%d, %d)" % [node.node_uid, node.grid_cell.x, node.grid_cell.y]
	node_type_option.select(int(node.kind))
	cap_spin.set_value_no_signal(node.activation_cap)
	refractory_spin.set_value_no_signal(node.refractory_ticks)
	inputs_spin.set_value_no_signal(node.required_inputs)
	outputs_spin.set_value_no_signal(node.output_count)
	blocker_hits_spin.set_value_no_signal(node.blocker_hits)
	gate_passes_spin.set_value_no_signal(node.gate_passes)
	channel_option.select(int(node.channel))
	delay_spin.set_value_no_signal(node.delay_ticks)
	repeat_count_spin.set_value_no_signal(node.repeat_count)
	repeat_interval_spin.set_value_no_signal(node.repeat_interval)
	direction_option.select(int(node.one_way_direction))
	match node.kind:
		PuzzleNode.Kind.SPLITTER:
			cap_container.show()
			refractory_container.show()
			splitter_fields.show()
		PuzzleNode.Kind.ALTERNATING:
			cap_container.show()
			refractory_container.show()
		PuzzleNode.Kind.TARGET: cap_container.show()
		PuzzleNode.Kind.BLOCKER_AMOUNT: blocker_amount_fields.show()
		PuzzleNode.Kind.BLOCKER_TARGET: channel_fields.show()
		PuzzleNode.Kind.GATE_AMOUNT: gate_amount_fields.show()
		PuzzleNode.Kind.TRIGGER_TARGET:
			cap_container.show()
			channel_fields.show()
		PuzzleNode.Kind.DELAY: delay_fields.show()
		PuzzleNode.Kind.REPEATER: repeater_fields.show()
		PuzzleNode.Kind.ONE_WAY_GATE: direction_fields.show()
	updating_controls = false


func _on_kind_changed(index: int) -> void:
	if updating_controls:
		return

	if not builder.nodes_by_id.has(selected_uid):
		return

	var node: PuzzleNode = builder.nodes_by_id[selected_uid]

	if index == PuzzleNode.Kind.BEGIN:
		for uid in builder.nodes_by_id.keys():
			if uid == selected_uid:
				continue

			var other: PuzzleNode = builder.nodes_by_id[uid]

			if other.kind == PuzzleNode.Kind.BEGIN:
				show_selected_node(selected_uid)
				return

		for connection in builder.connection_layer.connections:
			if str(connection["to_uid"]) == selected_uid:
				show_selected_node(selected_uid)
				return

	node.kind = index
	node.refresh_visuals()
	show_selected_node(selected_uid)

func _on_channel_changed(index: int) -> void:
	if updating_controls or not builder.nodes_by_id.has(selected_uid): return
	var node: PuzzleNode = builder.nodes_by_id[selected_uid]
	node.channel = index
	node.refresh_visuals()
func _on_direction_changed(index: int) -> void:
	if updating_controls or not builder.nodes_by_id.has(selected_uid): return
	var node: PuzzleNode = builder.nodes_by_id[selected_uid]
	node.one_way_direction = index
	node.refresh_visuals()

func _on_number_changed(value: float, property_name: String) -> void:
	if updating_controls or not builder.nodes_by_id.has(selected_uid): return
	var node: PuzzleNode = builder.nodes_by_id[selected_uid]
	match property_name:
		"cap": node.activation_cap = int(value)
		"refractory": node.refractory_ticks = int(value)
		"inputs": node.required_inputs = int(value)
		"outputs": node.output_count = int(value)
		"blocker_hits": node.blocker_hits = int(value)
		"gate_passes": node.gate_passes = int(value)
		"delay_ticks": node.delay_ticks = int(value)
		"repeat_count": node.repeat_count = int(value)
		"repeat_interval": node.repeat_interval = int(value)
	node.refresh_visuals()
func is_pointer_over_ui(screen_position: Vector2) -> bool:
	if palette_panel == null: return false
	if palette_panel.get_global_rect().has_point(screen_position): return true
	if inspector_panel != null and inspector_panel.visible and inspector_panel.get_global_rect().has_point(screen_position): return true
	if screen_position.y < 205.0: return true
	return false
func _process(_delta: float) -> void:
	if not selected_uid.is_empty() and not builder.nodes_by_id.has(selected_uid):
		show_selected_node("")
