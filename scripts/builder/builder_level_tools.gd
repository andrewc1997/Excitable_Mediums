extends Node

# ============================================================
# EXCITABLE MEDIUMS - EM9 LEVEL TOOLS
# Godot 4.3
#
# Square and X-stretched Rhombus
# Real left-side rhombus terminal
# Save / Load / Offline Share Codes
# EM1-EM6 import compatibility
# ============================================================

const NODE_SCENE: PackedScene = preload(
	"res://scenes/nodes/puzzle_node.tscn"
)

const DESIGN_VALIDATOR = preload("res://scripts/builder/test/level_design_validator.gd")

const FORMAT_VERSION: int = 6
const SAVE_PATH: String = "user://excitable_level.json"

const MAX_GRID_SIZE: int = 40
const MAX_NODES: int = 1600
const MAX_CONNECTIONS: int = 3200
const MAX_CODE_LENGTH: int = 30000
const MAX_DECOMPRESSED_SIZE: int = 500000

const PRESETS: Array[int] = [3, 4, 6, 8, 12, 16]

var builder: Node2D
var grid: PuzzleGridBase
var ui_layer: CanvasLayer

var grid_type_selector: OptionButton
var selected_grid_type: String = "square"

var grid_size_label: Label
var decrease_size_button: Button
var increase_size_button: Button
var current_size: int = 12
var status_label: Label

var overlay: ColorRect
var dialog_center: CenterContainer
var dialog_panel: PanelContainer
var code_field: TextEdit
var dialog_title: Label
var dialog_note: Label

var copy_button: Button
var paste_button: Button
var apply_button: Button
var close_button: Button

var dialog_mode: String = ""
var validation_dialog: AcceptDialog
var clear_confirmation: ConfirmationDialog

# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:
	call_deferred("_initialize_level_tools")


func _initialize_level_tools() -> void:

	builder = get_parent() as Node2D
	grid = builder.get_node("Grid") as PuzzleGridBase
	ui_layer = builder.get_node("CanvasLayer") as CanvasLayer

	create_toolbar()
	create_code_dialog()
	create_clear_confirmation()
	create_validation_dialog()

	var live_grid := grid as SquarePuzzleGrid

	if live_grid != null:

		selected_grid_type = (
			"rhombus" if live_grid.is_rhombus()
			else "square"
		)

		grid_type_selector.select(
			1 if live_grid.is_rhombus() else 0
		)

	apply_grid_size(12)

	get_viewport().size_changed.connect(
		centre_grid_camera
	)

	status_label.text = "Ready to build."


# ============================================================
# TOOLBAR
# ============================================================

func create_toolbar() -> void:

	var panel := PanelContainer.new()
	panel.name = "LevelToolbar"
	ui_layer.add_child(panel)

	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 16.0
	panel.offset_right = -16.0
	panel.offset_top = 20.0
	panel.offset_bottom = 105.0

	var column := VBoxContainer.new()
	panel.add_child(column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	grid_type_selector = OptionButton.new()
	grid_type_selector.name = "GridTypeSelector"
	grid_type_selector.custom_minimum_size = Vector2(190, 35)

	grid_type_selector.add_item("Square Grid", 0)
	grid_type_selector.add_item("Horizontal Rhombus", 1)
	grid_type_selector.add_item("Honeycomb Grid", 2)
	grid_type_selector.set_item_disabled(2, true)

	grid_type_selector.select(0)
	grid_type_selector.item_selected.connect(
		_on_grid_type_selected
	)

	row.add_child(grid_type_selector)

	decrease_size_button = Button.new()
	decrease_size_button.text = "◀"
	decrease_size_button.custom_minimum_size = Vector2(44, 35)
	decrease_size_button.pressed.connect(
		_on_decrease_grid_pressed
	)
	row.add_child(decrease_size_button)

	grid_size_label = Label.new()
	grid_size_label.custom_minimum_size = Vector2(85, 35)
	grid_size_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	grid_size_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	grid_size_label.add_theme_font_size_override(
		"font_size", 23
	)
	row.add_child(grid_size_label)

	increase_size_button = Button.new()
	increase_size_button.text = "▶"
	increase_size_button.custom_minimum_size = Vector2(44, 35)
	increase_size_button.pressed.connect(
		_on_increase_grid_pressed
	)
	row.add_child(increase_size_button)

	add_toolbar_button(row, "Validate", _on_validate_pressed)
	add_toolbar_button(row, "Clear", _on_clear_pressed)
	add_toolbar_button(row, "Save", _on_save_pressed)
	add_toolbar_button(row, "Load", _on_load_pressed)
	add_toolbar_button(row, "Share Code", _on_export_pressed)
	add_toolbar_button(row, "Import Code", _on_import_pressed)

	status_label = Label.new()
	status_label.text = "Ready."
	column.add_child(status_label)

	update_grid_size_label()


func add_toolbar_button(
	row: HBoxContainer,
	title: String,
	callback: Callable
) -> void:

	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	row.add_child(button)


# ============================================================
# GRID TYPE
# ============================================================

func _on_grid_type_selected(index: int) -> void:

	var live_grid := grid as SquarePuzzleGrid

	if live_grid == null:
		status_label.text = "Incorrect Grid script."
		return

	if index < 0 or index > 1:

		grid_type_selector.select(live_grid.grid_type)
		status_label.text = "Honeycomb not implemented."
		return

	if index == live_grid.grid_type:
		return

	if (
		not builder.nodes_by_id.is_empty()
		or not builder.connection_layer.connections.is_empty()
	):

		grid_type_selector.select(live_grid.grid_type)

		status_label.text = (
			"Clear the level before changing grid type."
		)
		return

	live_grid.set_grid_type(index)

	selected_grid_type = (
		"rhombus" if index == 1 else "square"
	)

	live_grid.queue_redraw()
	builder.connection_layer.refresh_connections()

	centre_grid_camera()

	status_label.text = (
		"Grid changed to %s."
		% grid_type_selector.get_item_text(index)
	)


# ============================================================
# GRID RESIZING
# ============================================================

func _on_decrease_grid_pressed() -> void:

	var index: int = PRESETS.find(current_size)

	if index > 0:
		apply_grid_size(PRESETS[index - 1])


func _on_increase_grid_pressed() -> void:

	var index: int = PRESETS.find(current_size)

	if index >= 0 and index < PRESETS.size() - 1:
		apply_grid_size(PRESETS[index + 1])


func update_grid_size_label() -> void:

	if grid_size_label == null:
		return

	grid_size_label.text = "%dx%d" % [
		grid.grid_columns,
		grid.grid_rows
	]

	current_size = grid.grid_columns

	var index: int = PRESETS.find(current_size)

	decrease_size_button.disabled = index <= 0

	increase_size_button.disabled = (
		index < 0
		or index >= PRESETS.size() - 1
	)


func apply_grid_size(size: int) -> void:

	if not PRESETS.has(size):

		if status_label != null:
			status_label.text = "Unsupported grid size."

		return

	# The rhombus terminal depends on the grid height.
	# Keep the condition simple for Godot 4.3 parser compatibility.
	var live_grid: SquarePuzzleGrid = grid as SquarePuzzleGrid
	var is_rhombus: bool = false
	if live_grid != null:
		is_rhombus = live_grid.is_rhombus()
	var has_nodes: bool = not builder.nodes_by_id.is_empty()
	var size_changed: bool = size != grid.grid_columns or size != grid.grid_rows
	if is_rhombus and has_nodes and size_changed:
		status_label.text = "Clear the rhombus before resizing."
		return

	var old_columns: int = grid.grid_columns
	var old_rows: int = grid.grid_rows

	if (
		size == old_columns
		and size == old_rows
	):

		update_grid_size_label()
		centre_grid_camera()
		return

	for uid in builder.nodes_by_id.keys():

		var node: PuzzleNode = builder.nodes_by_id[uid]

		if (
			node.grid_cell.x >= size
			or node.grid_cell.y >= size
		):

			status_label.text = (
				"A node is outside the requested grid."
			)
			return

	grid.grid_columns = size
	grid.grid_rows = size

	var proposed_paths: Array[Dictionary] = []

	var valid: bool = builder.build_connection_paths(
		builder.cells_to_ids,
		{},
		builder.connection_layer.connections,
		proposed_paths
	)

	if not valid:

		grid.grid_columns = old_columns
		grid.grid_rows = old_rows
		grid.queue_redraw()

		status_label.text = (
			"Connections cannot fit this grid."
		)
		return

	builder.connection_layer.connections = proposed_paths
	builder.connection_layer.refresh_connections()

	grid.queue_redraw()

	update_grid_size_label()
	centre_grid_camera()

	status_label.text = (
		"Grid resized to %dx%d." % [size, size]
	)


# ============================================================
# CAMERA FRAMING
# ============================================================

func centre_grid_camera() -> void:

	if builder == null or grid == null:
		return

	var camera := (
		builder.get_node_or_null("Camera2D")
		as Camera2D
	)

	if camera == null:
		return

	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)

	for x in range(grid.grid_columns):
		for y in range(grid.grid_rows):

			var cell := Vector2i(x, y)

			if not grid.is_valid_cell(cell):
				continue

			var point: Vector2 = (
				grid.cell_to_local(cell)
			)

			minimum.x = minf(minimum.x, point.x)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x)
			maximum.y = maxf(maximum.y, point.y)

	# Include the real rhombus terminal.
	var live_grid := grid as SquarePuzzleGrid

	if (
		live_grid != null
		and live_grid.is_rhombus()
	):

		var terminal_position: Vector2 = (
			live_grid.cell_to_local(
				live_grid.get_left_terminal()
			)
		)

		minimum.x = minf(
			minimum.x, terminal_position.x
		)

		minimum.y = minf(
			minimum.y, terminal_position.y
		)

		maximum.x = maxf(
			maximum.x, terminal_position.x
		)

		maximum.y = maxf(
			maximum.y, terminal_position.y
		)

	if minimum.x == INF:
		return

	var grid_size: Vector2 = maximum - minimum

	var grid_centre: Vector2 = (
		minimum + maximum
	) * 0.5

	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	var left_edge: float = 45.0
	var top_edge: float = 135.0
	var right_edge: float = viewport_size.x - 290.0
	var bottom_edge: float = viewport_size.y - 150.0

	var available_width: float = maxf(
		100.0, right_edge - left_edge
	)

	var available_height: float = maxf(
		100.0, bottom_edge - top_edge
	)

	var padding: float = 55.0

	var zoom_x: float = (
		available_width
		/ maxf(grid_size.x + padding * 2.0, 1.0)
	)

	var zoom_y: float = (
		available_height
		/ maxf(grid_size.y + padding * 2.0, 1.0)
	)

	var zoom_value: float = clampf(
		minf(zoom_x, zoom_y), 0.1, 2.5
	)

	camera.zoom = Vector2.ONE * zoom_value

	var target_screen_position := Vector2(
		left_edge + available_width * 0.5,
		top_edge
			+ padding * zoom_value
			+ grid_size.y * zoom_value * 0.5
	)

	var viewport_centre: Vector2 = (
		viewport_size * 0.5
	)

	camera.global_position = (
		grid.to_global(grid_centre)
		+ (
			viewport_centre - target_screen_position
		) / zoom_value
	)

	camera.make_current()
	camera.reset_smoothing()

	grid.queue_redraw()
	builder.connection_layer.refresh_connections()


# ============================================================
# CLEAR LEVEL
# ============================================================

func create_clear_confirmation() -> void:

	clear_confirmation = ConfirmationDialog.new()
	clear_confirmation.title = "Clear Level"

	clear_confirmation.dialog_text = (
		"Delete all nodes and connections?\n"
		+ "This cannot be undone."
	)

	add_child(clear_confirmation)

	clear_confirmation.confirmed.connect(
		_confirm_clear_level
	)


func _on_clear_pressed() -> void:
	clear_confirmation.popup_centered()


func _confirm_clear_level() -> void:

	clear_level()
	status_label.text = "Level cleared."


func clear_level() -> void:

	builder.connection_start_id = ""
	builder.dragging_node_id = ""
	builder.cancel_palette_drag()

	builder.connection_layer.connections.clear()
	builder.connection_layer.refresh_connections()

	for node in builder.placed_nodes.get_children():

		builder.placed_nodes.remove_child(node)
		node.queue_free()

	builder.nodes_by_id.clear()
	builder.cells_to_ids.clear()

	builder.next_node_number = 1
	builder.selected_node_id = ""

	if builder.builder_ui != null:
		builder.builder_ui.show_selected_node("")

	builder.update_tool_label()


# ============================================================
# CODE DIALOG
# ============================================================

func create_code_dialog() -> void:

	overlay = ColorRect.new()
	overlay.name = "CodeOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.78)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100

	ui_layer.add_child(overlay)

	overlay.set_anchors_preset(
		Control.PRESET_FULL_RECT
	)

	dialog_center = CenterContainer.new()
	dialog_center.name = "DialogCenter"

	overlay.add_child(dialog_center)

	dialog_center.set_anchors_preset(
		Control.PRESET_FULL_RECT
	)

	dialog_panel = PanelContainer.new()
	dialog_panel.name = "LevelCodePanel"

	dialog_panel.custom_minimum_size = (
		Vector2(700, 405)
	)

	dialog_center.add_child(dialog_panel)

	var margin := MarginContainer.new()

	for side in [
		"margin_left",
		"margin_right",
		"margin_top",
		"margin_bottom"
	]:

		margin.add_theme_constant_override(
			side, 20
		)

	dialog_panel.add_child(margin)

	var column := VBoxContainer.new()

	column.add_theme_constant_override(
		"separation", 12
	)

	margin.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)

	dialog_title = Label.new()
	dialog_title.text = "Share Level Code"

	dialog_title.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	dialog_title.add_theme_font_size_override(
		"font_size", 22
	)

	title_row.add_child(dialog_title)

	var title_close := Button.new()
	title_close.text = "✕"
	title_close.pressed.connect(_close_dialog)
	title_row.add_child(title_close)

	var description := Label.new()
	description.text = "Offline code — no internet required."
	column.add_child(description)

	code_field = TextEdit.new()
	code_field.custom_minimum_size = Vector2(620, 240)

	code_field.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	code_field.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)

	code_field.wrap_mode = (
		TextEdit.LINE_WRAPPING_BOUNDARY
	)

	column.add_child(code_field)

	dialog_note = Label.new()

	dialog_note.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	column.add_child(dialog_note)

	var button_row := HBoxContainer.new()

	button_row.alignment = (
		BoxContainer.ALIGNMENT_END
	)

	column.add_child(button_row)

	copy_button = Button.new()
	copy_button.text = "Copy Code"
	copy_button.pressed.connect(_copy_code)
	button_row.add_child(copy_button)

	paste_button = Button.new()
	paste_button.text = "Paste Code"
	paste_button.pressed.connect(_paste_code)
	button_row.add_child(paste_button)

	apply_button = Button.new()
	apply_button.text = "Import Level"
	apply_button.pressed.connect(_apply_import)
	button_row.add_child(apply_button)

	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_close_dialog)
	button_row.add_child(close_button)

	overlay.hide()


func open_code_dialog(
	mode: String,
	export_code: String = ""
) -> void:

	dialog_mode = mode
	dialog_note.text = ""

	if mode == "export":

		dialog_title.text = "Share Level Code — EM6"
		code_field.editable = false
		code_field.text = export_code

		copy_button.show()
		paste_button.hide()
		apply_button.hide()

	else:

		dialog_title.text = (
			"Import Level Code — EM1 through EM6"
		)

		code_field.editable = true
		code_field.text = ""

		copy_button.hide()
		paste_button.show()
		apply_button.show()

	overlay.move_to_front()
	overlay.show()

	if mode == "import":
		code_field.grab_focus()
	else:
		copy_button.grab_focus()


func _close_dialog() -> void:

	overlay.hide()
	dialog_mode = ""
	code_field.release_focus()

	status_label.text = "Builder Ready."


func _unhandled_key_input(event: InputEvent) -> void:

	if overlay == null or not overlay.visible:
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):

		_close_dialog()
		get_viewport().set_input_as_handled()


func _copy_code() -> void:

	if code_field.text.is_empty():
		dialog_note.text = "No code to copy."
		return

	DisplayServer.clipboard_set(code_field.text)
	dialog_note.text = "Level code copied."


func _paste_code() -> void:

	if dialog_mode != "import":
		return

	code_field.text = (
		DisplayServer.clipboard_get().strip_edges()
	)

	dialog_note.text = "Code pasted."


# ============================================================
# EXPORT
# ============================================================

func export_level_data() -> Dictionary:

	var level_nodes: Array = []
	var level_connections: Array = []

	var ids: Array = builder.nodes_by_id.keys()
	ids.sort()

	for uid in ids:

		var node: PuzzleNode = builder.nodes_by_id[uid]

		level_nodes.append({
			"id": node.node_uid,
			"kind": int(node.kind),
			"cell": [
				node.grid_cell.x,
				node.grid_cell.y
			],
			"cap": node.activation_cap,
			"refractory": node.refractory_ticks,
			"inputs": node.required_inputs,
			"outputs": node.output_count,
			"blocker_hits": node.blocker_hits,
			"gate_passes": node.gate_passes,
			"channel": int(node.channel),
			"delay_ticks": node.delay_ticks,
			"repeat_count": node.repeat_count,
			"repeat_interval": node.repeat_interval,
			"one_way_direction": int(node.one_way_direction),
			"alternating_first_branch": int(node.alternating_first_branch)
		})

	for connection in builder.connection_layer.connections:

		var path_data: Array = []

		for cell in connection["path"]:
			path_data.append([cell.x, cell.y])

		level_connections.append({
			"from": str(connection["from_uid"]),
			"to": str(connection["to_uid"]),
			"from_port": connection["from_port"],
			"to_port": connection["to_port"],
			"path": path_data
		})

	return {
		"version": FORMAT_VERSION,
		"grid_type": selected_grid_type,
		"columns": grid.grid_columns,
		"rows": grid.grid_rows,
		"nodes": level_nodes,
		"connections": level_connections
	}


# ============================================================
# OFFLINE CODE
# ============================================================

func encode_level(data: Dictionary) -> String:

	var version: int = int(
		data.get("version", FORMAT_VERSION)
	)

	var raw: PackedByteArray = (
		JSON.stringify(data).to_utf8_buffer()
	)

	var compressed: PackedByteArray = raw.compress(
		FileAccess.COMPRESSION_DEFLATE
	)

	var payload: String = (
		Marshalls.raw_to_base64(compressed)
	)

	payload = payload.replace("+", "-")
	payload = payload.replace("/", "_")
	payload = payload.replace("=", "")

	var checksum: String = (
		payload.sha256_text()
		.substr(0, 10)
		.to_upper()
	)

	return "EM%d-%s-%s" % [
		version, checksum, payload
	]


func decode_level(code: String) -> Dictionary:

	var clean: String = code.strip_edges()

	for whitespace in [" ", "\n", "\r", "\t"]:
		clean = clean.replace(whitespace, "")

	if clean.length() > MAX_CODE_LENGTH:
		return {"error": "Code too long."}

	var parts: PackedStringArray = (
		clean.split("-", false, 2)
	)

	if parts.size() != 3:
		return {"error": "Invalid code format."}

	var version: int = -1

	match parts[0]:
		"EM1": version = 1
		"EM2": version = 2
		"EM3": version = 3
		"EM4": version = 4
		"EM5": version = 5
		"EM6": version = 6
		_:
			return {"error": "Unsupported code version."}

	var payload: String = parts[2]

	if parts[1].length() != 10 or payload.is_empty():
		return {"error": "Invalid code data."}

	var checksum: String = (
		payload.sha256_text()
		.substr(0, 10)
		.to_upper()
	)

	if checksum != parts[1].to_upper():
		return {"error": "Incorrect code checksum."}

	var base64: String = (
		payload.replace("-", "+").replace("_", "/")
	)

	while base64.length() % 4 != 0:
		base64 += "="

	var compressed: PackedByteArray = (
		Marshalls.base64_to_raw(base64)
	)

	if compressed.is_empty():
		return {"error": "Invalid encoded data."}

	var decoded: PackedByteArray = (
		compressed.decompress_dynamic(
			MAX_DECOMPRESSED_SIZE,
			FileAccess.COMPRESSION_DEFLATE
		)
	)

	if decoded.is_empty():
		return {"error": "Cannot decompress level."}

	var parser := JSON.new()

	if parser.parse(
		decoded.get_string_from_utf8()
	) != OK:

		return {"error": "Invalid level JSON."}

	if not (parser.data is Dictionary):
		return {"error": "Invalid level structure."}

	var data: Dictionary = parser.data

	if int(data.get("version", -1)) != version:
		return {"error": "Code version mismatch."}

	var validation_error: String = validate_level(data)

	if not validation_error.is_empty():
		return {"error": validation_error}

	return {"data": data}


# ============================================================
# VALIDATION HELPERS
# ============================================================

func _valid_int(
	value: Variant,
	minimum: int,
	maximum: int
) -> bool:

	if not (value is int or value is float):
		return false

	var number: float = float(value)

	return (
		is_finite(number)
		and floorf(number) == number
		and number >= float(minimum)
		and number <= float(maximum)
	)


func _valid_cell_data(
	value: Variant,
	columns: int,
	rows: int,
	grid_name: String = "square"
) -> bool:

	if not (value is Array):
		return false

	if value.size() != 2:
		return false

	if not _valid_int(value[0], -1, columns - 1):
		return false

	if not _valid_int(value[1], 0, rows - 1):
		return false

	var x: int = int(value[0])
	var y: int = int(value[1])

	if grid_name == "rhombus" and x == -1:
		return y == rows - 1

	return x >= 0 and x < columns


# ============================================================
# VALIDATE LEVEL
# ============================================================

func validate_level(data: Dictionary) -> String:

	if not _valid_int(
		data.get("version", -1),
		1,
		FORMAT_VERSION
	):
		return "Unsupported level version."

	var version: int = int(data["version"])

	var saved_type: String = str(
		data.get("grid_type", "square")
	)

	if (
		saved_type != "square"
		and saved_type != "rhombus"
	):
		return "Unsupported grid type."

	if not _valid_int(
		data.get("columns", null),
		3,
		MAX_GRID_SIZE
	):
		return "Invalid grid width."

	if not _valid_int(
		data.get("rows", null),
		3,
		MAX_GRID_SIZE
	):
		return "Invalid grid height."

	var columns: int = int(data["columns"])
	var rows: int = int(data["rows"])

	var nodes_data: Variant = (
		data.get("nodes", null)
	)

	var connections_data: Variant = (
		data.get("connections", null)
	)

	if not (nodes_data is Array):
		return "Missing node data."

	if not (connections_data is Array):
		return "Missing connection data."

	if nodes_data.size() > MAX_NODES:
		return "Too many nodes."

	if connections_data.size() > MAX_CONNECTIONS:
		return "Too many connections."

	var ids: Dictionary = {}
	var occupied: Dictionary = {}
	var begin_ids: Dictionary = {}

	var begin_count: int = 0

	# ----------------------------------------------------
	# NODES
	# ----------------------------------------------------

	for entry in nodes_data:

		if not (entry is Dictionary):
			return "Invalid node record."

		var uid_value: Variant = entry.get("id", null)

		if not (uid_value is String):
			return "Invalid node ID."

		var uid: String = str(uid_value)

		if uid.is_empty() or ids.has(uid):
			return "Duplicate or missing node ID."

		if not _valid_cell_data(
			entry.get("cell", null),
			columns,
			rows,
			saved_type
		):
			return "Invalid node position."

		var cell := Vector2i(
			int(entry["cell"][0]),
			int(entry["cell"][1])
		)

		if occupied.has(cell):
			return "Two nodes share the same cell."

		var max_kind: int = (
			PuzzleNode.Kind.TARGET
		)

		match version:

			1:
				max_kind = PuzzleNode.Kind.TARGET

			2:
				max_kind = PuzzleNode.Kind.TRIGGER_TARGET

			3:
				max_kind = PuzzleNode.Kind.DELAY

			4:
				max_kind = PuzzleNode.Kind.BOUNCE

			5:
				max_kind = PuzzleNode.Kind.ONE_WAY_GATE

			6:
				max_kind = PuzzleNode.Kind.BEGIN

		if not _valid_int(
			entry.get("kind", null),
			0,
			max_kind
		):
			return "Unknown node type."

		if not _valid_int(
			entry.get("cap", null), 1, 100
		):
			return "Invalid activation cap."

		if not _valid_int(
			entry.get("refractory", null), 0, 100
		):
			return "Invalid refractory period."

		if not _valid_int(
			entry.get("inputs", null), 1, 6
		):
			return "Invalid splitter input count."

		if not _valid_int(
			entry.get("outputs", null), 1, 6
		):
			return "Invalid splitter output count."

		if version >= 2:

			if not _valid_int(
				entry.get("blocker_hits", null),
				1, 100
			):
				return "Invalid blocker amount."

			if not _valid_int(
				entry.get("gate_passes", null),
				1, 100
			):
				return "Invalid gate allowance."

			if not _valid_int(
				entry.get("channel", null),
				0, 3
			):
				return "Invalid colour channel."

		if version >= 3:

			if not _valid_int(
				entry.get("delay_ticks", null),
				1, 100
			):
				return "Invalid Delay duration."

		if version >= 4:

			if not _valid_int(
				entry.get("repeat_count", null),
				1, 100
			):
				return "Invalid Repeater count."

			if not _valid_int(
				entry.get("repeat_interval", null),
				1, 100
			):
				return "Invalid Repeater interval."

		if version >= 5:

			if not _valid_int(
				entry.get("one_way_direction", null),
				0, 3
			):
				return "Invalid One-Way direction."

		# Optional in EM6 for compatibility with existing codes.
		# Older EM6 levels default to Upper / North-East first.
		if entry.has("alternating_first_branch"):
			if not _valid_int(entry["alternating_first_branch"], 0, 1):
				return "Invalid Alternating starting branch."

		if int(entry["kind"]) == PuzzleNode.Kind.BEGIN:

			begin_count += 1
			begin_ids[uid] = true

			if begin_count > 1:
				return "Only one Begin Node is permitted."

		ids[uid] = cell
		occupied[cell] = uid

	# ----------------------------------------------------
	# CONNECTIONS
	# ----------------------------------------------------

	var seen_edges: Dictionary = {}
	var reserved: Dictionary = {}

	for entry in connections_data:

		if not (entry is Dictionary):
			return "Invalid connection record."

		var from_value: Variant = entry.get("from", null)
		var to_value: Variant = entry.get("to", null)

		if not (
			from_value is String
			and to_value is String
		):
			return "Invalid connection IDs."

		var from_id: String = str(from_value)
		var to_id: String = str(to_value)

		if (
			not ids.has(from_id)
			or not ids.has(to_id)
		):
			return "Connection references a missing node."

		if from_id == to_id:
			return "Self-connections are not permitted."

		if begin_ids.has(to_id):
			return "Cannot connect into a Begin Node."

		var pair: Array = [from_id, to_id]
		pair.sort()

		var edge_key: String = (
			"%s|%s" % [pair[0], pair[1]]
		)

		if seen_edges.has(edge_key):
			return "Duplicate connection."

		seen_edges[edge_key] = true

		var path_data: Variant = entry.get(
			"path", null
		)

		if not (path_data is Array):
			return "Missing connection path."

		if (
			path_data.size() < 2
			or path_data.size() > columns * rows + 1
		):
			return "Invalid connection path length."

		var path: Array[Vector2i] = []

		for point in path_data:

			if not _valid_cell_data(
				point,
				columns,
				rows,
				saved_type
			):
				return "Invalid path coordinate."

			path.append(
				Vector2i(
					int(point[0]),
					int(point[1])
				)
			)

		if path[0] != ids[from_id]:
			return "Connection start does not match node."

		if path[path.size() - 1] != ids[to_id]:
			return "Connection end does not match node."

		var path_cells: Dictionary = {}

		for index in range(path.size() - 1):

			var start_cell: Vector2i = path[index]
			var end_cell: Vector2i = path[index + 1]

			var difference: Vector2i = (
				end_cell - start_cell
			)

			# One logical lattice direction per
			# segment, no hidden diagonal jumps.
			if (
				difference.x != 0
				and difference.y != 0
			):
				return "Path leaves the visible lattice."

			var distance: int = maxi(
				absi(difference.x),
				absi(difference.y)
			)

			if distance == 0:
				return "Zero-length path segment."

			# Terminal can only connect to anchor.
			if saved_type == "rhombus":

				var terminal := Vector2i(-1, rows - 1)
				var anchor := Vector2i(0, rows - 1)

				if (
					start_cell == terminal
					or end_cell == terminal
				):

					if not (
						(
							start_cell == terminal
							and end_cell == anchor
						)
						or (
							start_cell == anchor
							and end_cell == terminal
						)
					):
						return "Invalid rhombus terminal path."

			var direction := Vector2i(
				signi(difference.x),
				signi(difference.y)
			)

			for step in range(distance + 1):

				var cell: Vector2i = (
					start_cell + direction * step
				)

				if index > 0 and step == 0:
					continue

				if not _valid_cell_data(
					[cell.x, cell.y],
					columns,
					rows,
					saved_type
				):
					return "Path leaves the grid."

				if path_cells.has(cell):
					return "Connection crosses itself."

				path_cells[cell] = true

				if (
					cell == path[0]
					or cell == path[path.size() - 1]
				):
					continue

				if occupied.has(cell):
					return "Connection crosses a node."

				if reserved.has(cell):
					return "Connections overlap."

		for cell in path_cells.keys():

			if (
				cell == path[0]
				or cell == path[path.size() - 1]
			):
				continue

			reserved[cell] = true

	return ""


# ============================================================
# APPLY LEVEL DATA
# ============================================================

func apply_level_data(data: Dictionary) -> void:

	clear_level()

	var saved_type: String = str(
		data.get("grid_type", "square")
	)

	var live_grid := grid as SquarePuzzleGrid

	if live_grid != null:

		if saved_type == "rhombus":
			live_grid.set_grid_type(1)
			grid_type_selector.select(1)

		else:
			live_grid.set_grid_type(0)
			grid_type_selector.select(0)

	selected_grid_type = saved_type

	grid.grid_columns = int(data["columns"])
	grid.grid_rows = int(data["rows"])
	grid.queue_redraw()

	for entry in data["nodes"]:

		var node: PuzzleNode = (
			NODE_SCENE.instantiate() as PuzzleNode
		)

		var cell := Vector2i(
			int(entry["cell"][0]),
			int(entry["cell"][1])
		)

		node.node_uid = str(entry["id"])
		node.grid_cell = cell
		node.kind = int(entry["kind"])

		node.activation_cap = int(entry["cap"])
		node.refractory_ticks = int(
			entry["refractory"]
		)
		node.required_inputs = int(entry["inputs"])
		node.output_count = int(entry["outputs"])

		node.blocker_hits = int(
			entry.get("blocker_hits", 2)
		)

		node.gate_passes = int(
			entry.get("gate_passes", 2)
		)

		node.channel = int(
			entry.get(
				"channel",
				PuzzleNode.Channel.PURPLE
			)
		)

		node.delay_ticks = int(
			entry.get("delay_ticks", 3)
		)

		node.repeat_count = int(
			entry.get("repeat_count", 3)
		)

		node.repeat_interval = int(
			entry.get("repeat_interval", 2)
		)

		node.one_way_direction = int(
			entry.get(
				"one_way_direction",
				PuzzleNode.Direction.EAST
			)
		)

		node.alternating_first_branch = int(
			entry.get("alternating_first_branch", 0)
		)
		node.linked_target_uid = ""

		builder.placed_nodes.add_child(node)

		node.position = (
			builder.placed_nodes.to_local(
				grid.to_global(
					grid.cell_to_local(cell)
				)
			)
		)

		builder.nodes_by_id[node.node_uid] = node
		builder.cells_to_ids[cell] = node.node_uid

		node.refresh_visuals()

	for entry in data["connections"]:

		var path: Array[Vector2i] = []

		for point in entry["path"]:

			path.append(
				Vector2i(
					int(point[0]),
					int(point[1])
				)
			)

		var last: int = path.size() - 1

		builder.connection_layer.connections.append({
			"from_uid": str(entry["from"]),
			"to_uid": str(entry["to"]),
			"from_port": grid.get_port_direction(
				path[0], path[1]
			),
			"to_port": grid.get_port_direction(
				path[last],
				path[last - 1]
			),
			"path": path
		})

	var next_number: int = 1

	for uid in builder.nodes_by_id.keys():

		var text_uid: String = str(uid)

		if text_uid.begins_with("node_"):

			var suffix: String = (
				text_uid.substr(5)
			)

			if suffix.is_valid_int():

				next_number = maxi(
					next_number,
					int(suffix) + 1
				)

	builder.next_node_number = next_number

	builder.connection_layer.refresh_connections()

	update_grid_size_label()
	centre_grid_camera()

	if builder.builder_ui != null:
		builder.builder_ui.show_selected_node("")


# ============================================================
# PUZZLE DESIGN VALIDATION
# ============================================================

func create_validation_dialog() -> void:
	validation_dialog = AcceptDialog.new()
	validation_dialog.title = "Puzzle Validation"
	validation_dialog.dialog_text = ""
	validation_dialog.min_size = Vector2i(560, 300)
	ui_layer.add_child(validation_dialog)


func _on_validate_pressed() -> void:
	var data: Dictionary = export_level_data()
	var structural_error: String = validate_level(data)
	if not structural_error.is_empty():
		status_label.text = "Level format error: " + structural_error
		validation_dialog.dialog_text = "Level format error:\n" + structural_error
		validation_dialog.popup_centered()
		return

	var report: Dictionary = DESIGN_VALIDATOR.inspect(data)
	var errors: Array[String] = report["errors"]
	var warnings: Array[String] = report["warnings"]
	var lines: Array[String] = []

	lines.append("Nodes: %d  |  Connections: %d  |  Goals: %d" % [
		report["node_count"], report["connection_count"], report["goal_count"]
	])
	lines.append("")

	if errors.is_empty():
		lines.append("PASS: Basic puzzle structure is valid.")
		status_label.text = "Validation: structure OK (%d warning(s))." % warnings.size()
	else:
		lines.append("FAIL: %d issue(s) must be fixed:" % errors.size())
		for issue in errors:
			lines.append("  - " + issue)
		status_label.text = "Validation: %d issue(s), %d warning(s)." % [errors.size(), warnings.size()]

	if not warnings.is_empty():
		lines.append("")
		lines.append("Warnings (%d):" % warnings.size())
		for warning in warnings:
			lines.append("  - " + warning)

	lines.append("")
	lines.append("This checks structure and graph connectivity only.")
	lines.append("It does NOT prove the pulse simulation can solve the level.")
	validation_dialog.dialog_text = "\n".join(lines)
	validation_dialog.popup_centered()


# ============================================================
# LOCAL SAVE
# ============================================================

func _on_save_pressed() -> void:

	var data: Dictionary = export_level_data()
	var error: String = validate_level(data)

	if not error.is_empty():
		status_label.text = "Save failed: " + error
		return

	var file: FileAccess = FileAccess.open(
		SAVE_PATH, FileAccess.WRITE
	)

	if file == null:
		status_label.text = "Could not open save file."
		return

	file.store_string(JSON.stringify(data))
	file.close()

	status_label.text = "EM6 level saved."


# ============================================================
# LOCAL LOAD
# ============================================================

func _on_load_pressed() -> void:

	if not FileAccess.file_exists(SAVE_PATH):
		status_label.text = "No saved level found."
		return

	var file: FileAccess = FileAccess.open(
		SAVE_PATH, FileAccess.READ
	)

	if file == null:
		status_label.text = "Could not read save file."
		return

	if file.get_length() > MAX_DECOMPRESSED_SIZE:

		file.close()
		status_label.text = "Save file too large."
		return

	var raw_text: String = file.get_as_text()
	file.close()

	var parser := JSON.new()

	if parser.parse(raw_text) != OK:
		status_label.text = "Invalid save JSON."
		return

	if not (parser.data is Dictionary):
		status_label.text = "Invalid save structure."
		return

	var data: Dictionary = parser.data
	var error: String = validate_level(data)

	if not error.is_empty():
		status_label.text = "Load failed: " + error
		return

	apply_level_data(data)

	status_label.text = "Level loaded successfully."


# ============================================================
# SHARE CODE
# ============================================================

func _on_export_pressed() -> void:

	var data: Dictionary = export_level_data()
	var error: String = validate_level(data)

	if not error.is_empty():
		status_label.text = "Export failed: " + error
		return

	var code: String = encode_level(data)

	if code.length() > MAX_CODE_LENGTH:
		status_label.text = "Level exceeds code limit."
		return

	open_code_dialog("export", code)


func _on_import_pressed() -> void:
	open_code_dialog("import")


func _apply_import() -> void:

	if dialog_mode != "import":
		return

	var result: Dictionary = decode_level(
		code_field.text
	)

	if result.has("error"):

		dialog_note.text = str(result["error"])
		return

	apply_level_data(result["data"])

	overlay.hide()
	dialog_mode = ""
	code_field.release_focus()

	status_label.text = (
		"Level code imported successfully."
	)
