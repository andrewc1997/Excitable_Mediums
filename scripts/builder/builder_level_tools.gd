
extends Node

# ============================================================
# EXCITABLE MEDIUMS - BUILDER LEVEL TOOLS
# Godot 4.3
# Version: EM6
#
# Features:
# - Square grid resizing
# - Clear level
# - Local save/load
# - Offline share codes
# - Import EM1 through EM6
# - Begin Node validation
# - One-Way Gate settings
# - Repeater settings
# - Existing node configuration
#
# EM6:
# - Supports Begin Nodes (Kind 13)
# - Maximum one Begin Node per level
# - Connections cannot enter Begin Nodes
# - Older levels remain importable
# ============================================================


# ============================================================
# CONSTANTS
# ============================================================

const NODE_SCENE: PackedScene = preload(
	"res://scenes/nodes/puzzle_node.tscn"
)

const FORMAT_VERSION: int = 6

const SAVE_PATH: String = "user://excitable_level.json"

const MAX_GRID_SIZE: int = 40
const MAX_NODES: int = 1600
const MAX_CONNECTIONS: int = 3200

const MAX_CODE_LENGTH: int = 30000
const MAX_DECOMPRESSED_SIZE: int = 500000

const PRESETS: Array[int] = [
	3, 4, 6, 8, 12, 16
]


# ============================================================
# REFERENCES
# ============================================================

var builder: Node2D
var grid: PuzzleGridBase
var ui_layer: CanvasLayer


# ============================================================
# GRID UI
# ============================================================


# ============================================================
# GRID UI
# ============================================================

# Grid type dropdown
var grid_type_selector: OptionButton
var selected_grid_type: String = "square"

# Grid size controls
var grid_size_label: Label
var decrease_size_button: Button
var increase_size_button: Button

var current_size: int = 12

var status_label: Label


# ============================================================
# CODE DIALOG UI
# ============================================================

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

var clear_confirmation: ConfirmationDialog


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	call_deferred("_initialize_level_tools")


func _initialize_level_tools() -> void:

	builder = get_parent() as Node2D

	grid = builder.get_node("Grid") as PuzzleGridBase

	ui_layer = (
		builder.get_node("CanvasLayer") as CanvasLayer
	)

	create_toolbar()
	create_code_dialog()
	create_clear_confirmation()

	apply_grid_size(12)

	status_label.text = "Ready to build."


# ============================================================
# CREATE TOOLBAR
# ============================================================

func create_toolbar() -> void:

	var panel := PanelContainer.new()

	panel.name = "LevelToolbar"

	ui_layer.add_child(panel)

	panel.anchor_left = 0.0
	panel.anchor_right = 1.0

	panel.offset_left = 16.0
	panel.offset_right = -16.0

	panel.offset_top = 120.0
	panel.offset_bottom = 200.0

	var column := VBoxContainer.new()

	panel.add_child(column)

	var row := HBoxContainer.new()

	row.add_theme_constant_override(
		"separation",
		10
	)

	column.add_child(row)

	# --------------------------------------------
	# GRID TYPE
	# --------------------------------------------


	# ====================================================
	# GRID TYPE SELECTOR
	# ====================================================

	grid_type_selector = OptionButton.new()
	grid_type_selector.name = "GridTypeSelector"

	grid_type_selector.custom_minimum_size = Vector2(190, 35)

	grid_type_selector.add_item("Square Grid", 0)
	grid_type_selector.add_item("Horizontal Rhombus", 1)
	grid_type_selector.add_item("Honeycomb Grid", 2)

	grid_type_selector.select(0)

	grid_type_selector.item_selected.connect(
		_on_grid_type_selected
	)

	row.add_child(grid_type_selector)

	# --------------------------------------------
	# DECREASE GRID
	# --------------------------------------------

	decrease_size_button = Button.new()

	decrease_size_button.text = "◀"

	decrease_size_button.custom_minimum_size = (
		Vector2(44, 35)
	)

	decrease_size_button.pressed.connect(
		_on_decrease_grid_pressed
	)

	row.add_child(decrease_size_button)

	# --------------------------------------------
	# GRID SIZE LABEL
	# --------------------------------------------

	grid_size_label = Label.new()

	grid_size_label.custom_minimum_size = (
		Vector2(85, 35)
	)

	grid_size_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	grid_size_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	grid_size_label.add_theme_font_size_override(
		"font_size",
		23
	)

	row.add_child(grid_size_label)

	# --------------------------------------------
	# INCREASE GRID
	# --------------------------------------------

	increase_size_button = Button.new()

	increase_size_button.text = "▶"

	increase_size_button.custom_minimum_size = (
		Vector2(44, 35)
	)

	increase_size_button.pressed.connect(
		_on_increase_grid_pressed
	)

	row.add_child(increase_size_button)

	# --------------------------------------------
	# TOOLBAR BUTTONS
	# --------------------------------------------

	add_toolbar_button(
		row,
		"Clear",
		_on_clear_pressed
	)

	add_toolbar_button(
		row,
		"Save",
		_on_save_pressed
	)

	add_toolbar_button(
		row,
		"Load",
		_on_load_pressed
	)

	add_toolbar_button(
		row,
		"Share Code",
		_on_export_pressed
	)

	add_toolbar_button(
		row,
		"Import Code",
		_on_import_pressed
	)

	# --------------------------------------------
	# STATUS
	# --------------------------------------------

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
# GRID SIZE CONTROLS
# ============================================================

func _on_decrease_grid_pressed() -> void:

	var index: int = PRESETS.find(current_size)

	if index > 0:
		apply_grid_size(PRESETS[index - 1])


func _on_increase_grid_pressed() -> void:

	var index: int = PRESETS.find(current_size)

	if (
		index >= 0
		and index < PRESETS.size() - 1
	):
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


# ============================================================
# APPLY GRID SIZE
# ============================================================

func apply_grid_size(size: int) -> void:

	if not PRESETS.has(size):

		if status_label != null:
			status_label.text = "Unsupported grid size."

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

	# --------------------------------------------
	# CHECK EXISTING NODES
	# --------------------------------------------

	for uid in builder.nodes_by_id.keys():

		var node: PuzzleNode = builder.nodes_by_id[uid]

		if (
			node.grid_cell.x >= size
			or node.grid_cell.y >= size
		):

			status_label.text = (
				"Cannot shrink: a node is outside the grid."
			)

			return

	# --------------------------------------------
	# APPLY DIMENSIONS
	# --------------------------------------------

	grid.grid_columns = size
	grid.grid_rows = size

	var new_paths: Array[Dictionary] = []

	var valid: bool = builder.build_connection_paths(
		builder.cells_to_ids,
		{},
		builder.connection_layer.connections,
		new_paths
	)

	if not valid:

		grid.grid_columns = old_columns
		grid.grid_rows = old_rows

		grid.queue_redraw()

		status_label.text = (
			"Cannot resize: connections cannot fit."
		)

		return

	builder.connection_layer.connections = new_paths

	builder.connection_layer.refresh_connections()

	grid.queue_redraw()

	update_grid_size_label()
	centre_grid_camera()

	status_label.text = (
		"Grid resized to %dx%d."
		% [size, size]
	)


# ============================================================
# CENTRE GRID CAMERA
# ============================================================

func centre_grid_camera() -> void:

	var camera: Camera2D = (
		builder.get_node("Camera2D") as Camera2D
	)

	var grid_width: float = (
		float(grid.grid_columns - 1)
		* grid.cell_size
	)

	var grid_height: float = (
		float(grid.grid_rows - 1)
		* grid.cell_size
	)

	var centre := Vector2(
		grid_width / 2.0,
		grid_height / 2.0
	)

	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)

	var zoom_x: float = (
		viewport_size.x * 0.85
		/ maxf(grid_width, 1.0)
	)

	var zoom_y: float = (
		viewport_size.y * 0.55
		/ maxf(grid_height, 1.0)
	)

	var zoom_value: float = clampf(
		minf(zoom_x, zoom_y),
		0.3,
		2.5
	)

	camera.zoom = Vector2.ONE * zoom_value

	camera.global_position = (
		grid.to_global(centre)
		- Vector2(0.0, 70.0 / zoom_value)
	)


# ============================================================
# CLEAR LEVEL CONFIRMATION
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


# ============================================================
# CLEAR LEVEL
# ============================================================

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
# CREATE SHARE / IMPORT DIALOG
# ============================================================

func create_code_dialog() -> void:

	overlay = ColorRect.new()

	overlay.name = "CodeOverlay"

	overlay.color = Color(
		0.0,
		0.0,
		0.0,
		0.78
	)

	overlay.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)

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

	# --------------------------------------------
	# MARGINS
	# --------------------------------------------

	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		20
	)

	margin.add_theme_constant_override(
		"margin_right",
		20
	)

	margin.add_theme_constant_override(
		"margin_top",
		18
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		18
	)

	dialog_panel.add_child(margin)

	var column := VBoxContainer.new()

	column.add_theme_constant_override(
		"separation",
		12
	)

	margin.add_child(column)

	# --------------------------------------------
	# TITLE
	# --------------------------------------------

	var title_row := HBoxContainer.new()

	column.add_child(title_row)

	dialog_title = Label.new()

	dialog_title.text = "Share Level Code"

	dialog_title.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	dialog_title.add_theme_font_size_override(
		"font_size",
		22
	)

	title_row.add_child(dialog_title)

	var title_close := Button.new()

	title_close.text = "✕"

	title_close.pressed.connect(
		_close_dialog
	)

	title_row.add_child(title_close)

	# --------------------------------------------
	# DESCRIPTION
	# --------------------------------------------

	var description := Label.new()

	description.text = (
		"Offline level password — no internet required."
	)

	column.add_child(description)

	# --------------------------------------------
	# CODE FIELD
	# --------------------------------------------

	code_field = TextEdit.new()

	code_field.custom_minimum_size = (
		Vector2(620, 240)
	)

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

	# --------------------------------------------
	# STATUS MESSAGE
	# --------------------------------------------

	dialog_note = Label.new()

	dialog_note.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	column.add_child(dialog_note)

	# --------------------------------------------
	# BUTTON ROW
	# --------------------------------------------

	var button_row := HBoxContainer.new()

	button_row.alignment = (
		BoxContainer.ALIGNMENT_END
	)

	button_row.add_theme_constant_override(
		"separation",
		10
	)

	column.add_child(button_row)

	copy_button = Button.new()

	copy_button.text = "Copy Code"

	copy_button.custom_minimum_size.x = 115.0

	copy_button.pressed.connect(
		_copy_code
	)

	button_row.add_child(copy_button)

	paste_button = Button.new()

	paste_button.text = "Paste Code"

	paste_button.custom_minimum_size.x = 115.0

	paste_button.pressed.connect(
		_paste_code
	)

	button_row.add_child(paste_button)

	apply_button = Button.new()

	apply_button.text = "Import Level"

	apply_button.custom_minimum_size.x = 115.0

	apply_button.pressed.connect(
		_apply_import
	)

	button_row.add_child(apply_button)

	close_button = Button.new()

	close_button.text = "Close"

	close_button.custom_minimum_size.x = 100.0

	close_button.pressed.connect(
		_close_dialog
	)

	button_row.add_child(close_button)

	overlay.hide()


# ============================================================
# OPEN CODE DIALOG
# ============================================================

func open_code_dialog(
	mode: String,
	export_code: String = ""
) -> void:

	dialog_mode = mode
	dialog_note.text = ""

	if mode == "export":

		dialog_title.text = (
			"Share Level Code — EM6"
		)

		code_field.editable = false
		code_field.text = export_code

		copy_button.show()

		paste_button.hide()
		apply_button.hide()

		dialog_note.text = (
			"Copy this password to share the level."
		)

	else:

		dialog_title.text = (
			"Import Level Code — EM1 through EM6"
		)

		code_field.editable = true
		code_field.text = ""

		copy_button.hide()

		paste_button.show()
		apply_button.show()

		dialog_note.text = (
			"Paste a password and select Import Level."
		)

	overlay.move_to_front()
	overlay.show()

	dialog_center.queue_sort()

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


# ============================================================
# COPY / PASTE
# ============================================================

func _copy_code() -> void:

	if code_field.text.is_empty():

		dialog_note.text = "No code to copy."

		return

	DisplayServer.clipboard_set(
		code_field.text
	)

	dialog_note.text = "Level password copied."


func _paste_code() -> void:

	if dialog_mode != "import":
		return

	code_field.text = (
		DisplayServer.clipboard_get().strip_edges()
	)

	dialog_note.text = "Password pasted."


# ============================================================
# EXPORT LEVEL DATA
# ============================================================

func export_level_data() -> Dictionary:

	var level_nodes: Array = []
	var level_connections: Array = []

	var ids: Array = builder.nodes_by_id.keys()

	ids.sort()

	# --------------------------------------------
	# EXPORT NODES
	# --------------------------------------------

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
			"one_way_direction": int(node.one_way_direction)
		})

	# --------------------------------------------
	# EXPORT CONNECTIONS
	# --------------------------------------------

	for connection in builder.connection_layer.connections:

		var path_data: Array = []

		for cell in connection["path"]:

			path_data.append([
				cell.x,
				cell.y
			])

		level_connections.append({
			"from": str(connection["from_uid"]),
			"to": str(connection["to_uid"]),
			"from_port": connection["from_port"],
			"to_port": connection["to_port"],
			"path": path_data
		})

	return {
		"version": FORMAT_VERSION,
		"grid_type": "square",
		"columns": grid.grid_columns,
		"rows": grid.grid_rows,
		"nodes": level_nodes,
		"connections": level_connections
	}


# ============================================================
# ENCODE LEVEL
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
		version,
		checksum,
		payload
	]


# ============================================================
# DECODE LEVEL
# ============================================================

func decode_level(code: String) -> Dictionary:

	var clean: String = code.strip_edges()

	for whitespace in [
		" ",
		"\n",
		"\r",
		"\t"
	]:

		clean = clean.replace(whitespace, "")

	if clean.length() > MAX_CODE_LENGTH:
		return {
			"error": "Password is too long."
		}

	var parts: PackedStringArray = (
		clean.split("-", false, 2)
	)

	if parts.size() != 3:
		return {
			"error": "Invalid password format."
		}

	# --------------------------------------------
	# VERSION
	# --------------------------------------------

	var version: int = -1

	match parts[0]:

		"EM1":
			version = 1

		"EM2":
			version = 2

		"EM3":
			version = 3

		"EM4":
			version = 4

		"EM5":
			version = 5

		"EM6":
			version = 6

		_:
			return {
				"error": "Unsupported password version."
			}

	var payload: String = parts[2]

	if (
		parts[1].length() != 10
		or payload.is_empty()
	):
		return {
			"error": "Invalid password data."
		}

	# --------------------------------------------
	# CHECKSUM
	# --------------------------------------------

	if (
		payload.sha256_text()
		.substr(0, 10)
		.to_upper()
		!= parts[1].to_upper()
	):

		return {
			"error": "Incorrect password checksum."
		}

	# --------------------------------------------
	# BASE64 RESTORATION
	# --------------------------------------------

	var base64: String = (
		payload.replace("-", "+").replace("_", "/")
	)

	while base64.length() % 4 != 0:
		base64 += "="

	var compressed: PackedByteArray = (
		Marshalls.base64_to_raw(base64)
	)

	if compressed.is_empty():
		return {
			"error": "Invalid encoded data."
		}

	# --------------------------------------------
	# DECOMPRESS
	# --------------------------------------------

	var decoded: PackedByteArray = (
		compressed.decompress_dynamic(
			MAX_DECOMPRESSED_SIZE,
			FileAccess.COMPRESSION_DEFLATE
		)
	)

	if decoded.is_empty():
		return {
			"error": "Cannot decompress level."
		}

	# --------------------------------------------
	# PARSE JSON
	# --------------------------------------------

	var parser := JSON.new()

	if parser.parse(
		decoded.get_string_from_utf8()
	) != OK:

		return {
			"error": "Invalid level JSON."
		}

	if not (parser.data is Dictionary):
		return {
			"error": "Invalid level structure."
		}

	var data: Dictionary = parser.data

	if int(data.get("version", -1)) != version:

		return {
			"error": "Password version mismatch."
		}

	var validation_error: String = (
		validate_level(data)
	)

	if not validation_error.is_empty():

		return {
			"error": validation_error
		}

	return {
		"data": data
	}


# ============================================================
# VALIDATION HELPERS
# ============================================================

func _valid_int(
	value: Variant,
	minimum: int,
	maximum: int
) -> bool:

	if not (
		value is int
		or value is float
	):
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
	rows: int
) -> bool:

	if not (value is Array):
		return false

	if value.size() != 2:
		return false

	return (
		_valid_int(value[0], 0, columns - 1)
		and _valid_int(value[1], 0, rows - 1)
	)


# ============================================================
# VALIDATE LEVEL
# ============================================================

func validate_level(data: Dictionary) -> String:

	# --------------------------------------------
	# FORMAT VERSION
	# --------------------------------------------

	if not _valid_int(
		data.get("version", -1),
		1,
		FORMAT_VERSION
	):

		return "Unsupported level format."

	var version: int = int(data["version"])

	# --------------------------------------------
	# GRID
	# --------------------------------------------

	if data.get("grid_type", "") != "square":

		return "Only square grids are supported."

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

	# --------------------------------------------
	# NODE / CONNECTION ARRAYS
	# --------------------------------------------

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

	var begin_count: int = 0
	var begin_ids: Dictionary = {}

	# --------------------------------------------
	# VALIDATE ALL NODES
	# --------------------------------------------

	for entry in nodes_data:

		if not (entry is Dictionary):
			return "Invalid node record."

		var uid_value: Variant = (
			entry.get("id", null)
		)

		if not (uid_value is String):
			return "Invalid node ID."

		var uid: String = str(uid_value)

		if uid.is_empty() or ids.has(uid):
			return "Duplicate or missing node ID."

		if not _valid_cell_data(
			entry.get("cell", null),
			columns,
			rows
		):

			return "Invalid node coordinates."

		var cell := Vector2i(
			int(entry["cell"][0]),
			int(entry["cell"][1])
		)

		if occupied.has(cell):

			return (
				"Two nodes occupy the same cell."
			)

		# ----------------------------------------
		# ALLOWED NODE TYPES PER VERSION
		# ----------------------------------------

		var max_kind: int = 3

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

		# ----------------------------------------
		# COMMON CONFIGURATION
		# ----------------------------------------

		if not _valid_int(
			entry.get("cap", null),
			1,
			100
		):

			return "Invalid activation cap."

		if not _valid_int(
			entry.get("refractory", null),
			0,
			100
		):

			return "Invalid refractory period."

		if not _valid_int(
			entry.get("inputs", null),
			1,
			6
		):

			return "Invalid splitter input count."

		if not _valid_int(
			entry.get("outputs", null),
			1,
			6
		):

			return "Invalid splitter output count."

		# ----------------------------------------
		# EM2 SETTINGS
		# ----------------------------------------

		if version >= 2:

			if not _valid_int(
				entry.get("blocker_hits", null),
				1,
				100
			):

				return "Invalid blocker amount."

			if not _valid_int(
				entry.get("gate_passes", null),
				1,
				100
			):

				return "Invalid gate allowance."

			if not _valid_int(
				entry.get("channel", null),
				0,
				3
			):

				return "Invalid colour channel."

		# ----------------------------------------
		# EM3 SETTINGS
		# ----------------------------------------

		if version >= 3:

			if not _valid_int(
				entry.get("delay_ticks", null),
				1,
				100
			):

				return "Invalid Delay duration."

		# ----------------------------------------
		# EM4 SETTINGS
		# ----------------------------------------

		if version >= 4:

			if not _valid_int(
				entry.get("repeat_count", null),
				1,
				100
			):

				return "Invalid Repeater pulse count."

			if not _valid_int(
				entry.get("repeat_interval", null),
				1,
				100
			):

				return "Invalid Repeater interval."

		# ----------------------------------------
		# EM5 SETTINGS
		# ----------------------------------------

		if version >= 5:

			if not _valid_int(
				entry.get("one_way_direction", null),
				0,
				3
			):

				return (
					"Invalid One-Way Gate direction."
				)

		# ----------------------------------------
		# EM6 BEGIN NODE VALIDATION
		# ----------------------------------------

		if int(entry["kind"]) == PuzzleNode.Kind.BEGIN:

			begin_count += 1
			begin_ids[uid] = true

			if begin_count > 1:

				return (
					"A level may contain only one Begin Node."
				)

		# ----------------------------------------
		# REGISTER NODE
		# ----------------------------------------

		ids[uid] = cell
		occupied[cell] = uid

	# Important:
	# Existing builder levels without Begin remain
	# valid for editing and importing.
	#
	# TestLevel enforces exactly one Begin when
	# launching a simulation.

	# --------------------------------------------
	# CONNECTION VALIDATION
	# --------------------------------------------

	var seen_edges: Dictionary = {}
	var reserved: Dictionary = {}

	for entry in connections_data:

		if not (entry is Dictionary):
			return "Invalid connection record."

		var from_value: Variant = (
			entry.get("from", null)
		)

		var to_value: Variant = (
			entry.get("to", null)
		)

		if not (
			from_value is String
			and to_value is String
		):

			return "Invalid connection node IDs."

		var from_id: String = str(from_value)
		var to_id: String = str(to_value)

		if (
			not ids.has(from_id)
			or not ids.has(to_id)
		):

			return (
				"Connection references a missing node."
			)

		if from_id == to_id:

			return "Self-connections are not allowed."

		# ========================================
		# EM6 BEGIN CONNECTION RULE
		#
		# This check belongs inside validate_level.
		#
		# A Begin Node may send signals outward,
		# but no connection may terminate at Begin.
		# ========================================

		if begin_ids.has(to_id):

			return (
				"Begin Nodes cannot have incoming connections."
			)

		# ----------------------------------------
		# DUPLICATE CONNECTIONS
		# ----------------------------------------

		var edge_ids: Array = [
			from_id,
			to_id
		]

		edge_ids.sort()

		var edge_key: String = "%s|%s" % [
			edge_ids[0],
			edge_ids[1]
		]

		if seen_edges.has(edge_key):

			return "Duplicate connection."

		seen_edges[edge_key] = true

		# ----------------------------------------
		# PATH DATA
		# ----------------------------------------

		var path_data: Variant = (
			entry.get("path", null)
		)

		if not (path_data is Array):

			return "Missing connection path."

		if (
			path_data.size() < 2
			or path_data.size() > columns * rows
		):

			return "Unsupported connection path."

		var path: Array[Vector2i] = []

		for point in path_data:

			if not _valid_cell_data(
				point,
				columns,
				rows
			):

				return "Invalid path coordinate."

			path.append(
				Vector2i(
					int(point[0]),
					int(point[1])
				)
			)

		# ----------------------------------------
		# ENDPOINTS
		# ----------------------------------------

		if path[0] != ids[from_id]:

			return (
				"Connection start does not match node."
			)

		if path[path.size() - 1] != ids[to_id]:

			return (
				"Connection end does not match node."
			)

		# ----------------------------------------
		# CHECK EACH PATH SEGMENT
		# ----------------------------------------

		var path_cells: Dictionary = {}

		for segment_index in range(
			path.size() - 1
		):

			var start_cell: Vector2i = (
				path[segment_index]
			)

			var end_cell: Vector2i = (
				path[segment_index + 1]
			)

			var difference: Vector2i = (
				end_cell - start_cell
			)

			# Square-grid routing is orthogonal.
			if (
				difference.x != 0
				and difference.y != 0
			):

				return "Diagonal connection detected."

			var distance: int = maxi(
				absi(difference.x),
				absi(difference.y)
			)

			if distance == 0:

				return (
					"Zero-length connection segment."
				)

			var direction := Vector2i(
				signi(difference.x),
				signi(difference.y)
			)

			# ------------------------------------
			# CHECK ALL CELLS IN SEGMENT
			# ------------------------------------

			for step in range(distance + 1):

				var cell: Vector2i = (
					start_cell
					+ direction * step
				)

				if (
					segment_index > 0
					and step == 0
				):

					continue

				if path_cells.has(cell):

					return "Connection crosses itself."

				path_cells[cell] = true

				if (
					cell == path[0]
					or cell == path[path.size() - 1]
				):

					continue

				if occupied.has(cell):

					return (
						"Connection passes through a node."
					)

				if reserved.has(cell):

					return (
						"Connections overlap or cross."
					)

		# ----------------------------------------
		# RESERVE CONNECTION CELLS
		# ----------------------------------------

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

	# --------------------------------------------
	# GRID SIZE
	# --------------------------------------------

	grid.grid_columns = int(data["columns"])
	grid.grid_rows = int(data["rows"])

	grid.queue_redraw()

	# --------------------------------------------
	# RECREATE NODES
	# --------------------------------------------

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

		node.activation_cap = int(
			entry["cap"]
		)

		node.refractory_ticks = int(
			entry["refractory"]
		)

		node.required_inputs = int(
			entry["inputs"]
		)

		node.output_count = int(
			entry["outputs"]
		)

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

		node.linked_target_uid = ""

		# ----------------------------------------
		# ADD TO SCENE
		# ----------------------------------------

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

	# --------------------------------------------
	# RECREATE CONNECTIONS
	# --------------------------------------------

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
				path[0],
				path[1]
			),
			"to_port": grid.get_port_direction(
				path[last],
				path[last - 1]
			),
			"path": path
		})

	# --------------------------------------------
	# RESTORE NODE ID COUNTER
	# --------------------------------------------

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

	# --------------------------------------------
	# REFRESH BUILDER
	# --------------------------------------------

	builder.connection_layer.refresh_connections()

	update_grid_size_label()
	centre_grid_camera()

	if builder.builder_ui != null:

		builder.builder_ui.show_selected_node("")


# ============================================================
# SAVE LEVEL LOCALLY
# ============================================================

func _on_save_pressed() -> void:

	var data: Dictionary = export_level_data()

	var error: String = validate_level(data)

	if not error.is_empty():

		status_label.text = (
			"Save failed: " + error
		)

		return

	var file: FileAccess = FileAccess.open(
		SAVE_PATH,
		FileAccess.WRITE
	)

	if file == null:

		status_label.text = (
			"Could not open save file."
		)

		return

	file.store_string(
		JSON.stringify(data)
	)

	file.close()

	status_label.text = (
		"EM6 level saved locally."
	)


# ============================================================
# LOAD LEVEL LOCALLY
# ============================================================

func _on_load_pressed() -> void:

	if not FileAccess.file_exists(SAVE_PATH):

		status_label.text = (
			"No saved level found."
		)

		return

	var file: FileAccess = FileAccess.open(
		SAVE_PATH,
		FileAccess.READ
	)

	if file == null:

		status_label.text = (
			"Could not read save file."
		)

		return

	if file.get_length() > MAX_DECOMPRESSED_SIZE:

		file.close()

		status_label.text = (
			"Save file is too large."
		)

		return

	var text_data: String = file.get_as_text()

	file.close()

	var parser := JSON.new()

	if (
		parser.parse(text_data) != OK
		or not (parser.data is Dictionary)
	):

		status_label.text = (
			"Invalid save file."
		)

		return

	var data: Dictionary = parser.data

	var error: String = validate_level(data)

	if not error.is_empty():

		status_label.text = (
			"Load failed: " + error
		)

		return

	apply_level_data(data)

	status_label.text = (
		"Level loaded successfully."
	)


# ============================================================
# SHARE LEVEL CODE
# ============================================================

func _on_export_pressed() -> void:

	var data: Dictionary = export_level_data()

	var error: String = validate_level(data)

	if not error.is_empty():

		status_label.text = (
			"Export failed: " + error
		)

		return

	var code: String = encode_level(data)

	if code.length() > MAX_CODE_LENGTH:

		status_label.text = (
			"Level exceeds share-code limit."
		)

		return

	open_code_dialog("export", code)


# ============================================================
# IMPORT LEVEL CODE
# ============================================================

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
		"Offline level password imported successfully!"
	)

func _on_grid_type_selected(index: int) -> void:

	match index:

		0:
			selected_grid_type = "square"

		1:
			selected_grid_type = "rhombus"

		2:
			selected_grid_type = "hex"

		_:
			return

	status_label.text = (
		"Selected grid: %s. Geometry integration pending."
		% grid_type_selector.get_item_text(index)
	)
