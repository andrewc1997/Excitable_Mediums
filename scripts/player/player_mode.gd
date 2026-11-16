extends Node2D

# ============================================================
# EXCITABLE MEDIUMS - CLEAN STANDALONE PLAYER MODE
# Godot 4.3
#
# Scene hierarchy (create manually):
#   PlayerMode (Node2D, this script)
#
# The working Builder scene is instanced internally to reuse its
# level importer, grid, connections, nodes and pulse simulation.
# All editor UI and the playtest toolbar remain hidden.
# There is deliberately NO in-game top bar.
#
# Controls:
#   Click a Begin node: launch from that start
#   Space / Escape: pause or resume
#   R: retry the same start
#   Backspace: choose a different Begin node
#
# Future Blender companion can use another CanvasLayer.
# ============================================================

@export_category("Level Setup")
@export_file("*.tscn") var builder_scene_path: String = "res://scenes/builder/builder.tscn"
@export_file("*.json") var level_file_path: String = "res://levels/level_001.json"
@export_file("*.json") var next_level_path: String = "res://levels/level_002_loop.json"

const LEVEL_002_PATH: String = "res://levels/level_002_loop.json"

@export_category("Screen Framing")
@export_range(0.0, 200.0, 1.0) var screen_margin: float = 44.0
@export_range(0.0, 250.0, 1.0) var world_padding: float = 50.0
@export_range(0.1, 5.0, 0.05) var maximum_zoom: float = 2.5

var builder: Node2D
var test_level: Node2D
var level_tools: Node
var puzzle_grid: PuzzleGridBase

var ready_to_play: bool = false
var result_was_shown: bool = false

var pause_layer: CanvasLayer
var result_layer: CanvasLayer
var result_heading: Label
var result_description: Label
var result_next_button: Button
var result_retry_button: Button
var result_reset_button: Button


# ============================================================
# STARTUP
# ============================================================

func _ready() -> void:
	_create_pause_overlay()
	_create_result_overlay()
	get_viewport().size_changed.connect(_request_level_fit)
	call_deferred("_boot")


func _boot() -> void:
	if not ResourceLoader.exists(builder_scene_path):
		_show_setup_error("Builder scene not found:\n" + builder_scene_path)
		return

	var scene: PackedScene = load(builder_scene_path) as PackedScene
	if scene == null:
		_show_setup_error("Could not open Builder scene:\n" + builder_scene_path)
		return

	builder = scene.instantiate() as Node2D
	if builder == null:
		_show_setup_error("The Builder scene needs a Node2D root.")
		return

	builder.hide()
	add_child(builder)

	# The existing Builder UI, LevelTools and TestLevel initialise
	# with call_deferred(), so let them finish before importing data.
	var systems_ready: bool = false
	for _attempt in range(30):
		await get_tree().process_frame
		if not is_instance_valid(builder):
			return

		level_tools = builder.get_node_or_null("LevelTools")
		test_level = builder.get_node_or_null("TestLevel") as Node2D
		puzzle_grid = builder.get_node_or_null("Grid") as PuzzleGridBase
		if level_tools == null or test_level == null or puzzle_grid == null:
			continue
		if level_tools.get("overlay") != null and test_level.get("test_bar") != null:
			systems_ready = true
			break

	if not systems_ready:
		_show_setup_error("Builder LevelTools or TestLevel failed to initialise.")
		return

	_load_level(level_file_path)


func _process(_delta: float) -> void:
	if not ready_to_play or not is_instance_valid(test_level):
		return

	var finished: bool = bool(test_level.get("finished"))
	var running: bool = bool(test_level.get("running"))
	var paused: bool = bool(test_level.get("paused"))

	if finished:
		pause_layer.hide()
		if not result_was_shown:
			_show_final_result()
	else:
		# Unlike the old HUD, this appears only when actually paused.
		if running and paused:
			pause_layer.show()
		else:
			pause_layer.hide()


# ============================================================
# LOAD A LEVEL INTO THE SAME PUZZLE ENGINE
# ============================================================

func _load_level(path: String) -> bool:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty():
		_show_setup_error("No level file was specified.")
		return false

	if not FileAccess.file_exists(clean_path):
		_show_setup_error(
			"Level file not found:\n" + clean_path
			+ "\n\nCopy the JSON level into your project's levels folder."
		)
		return false

	var file: FileAccess = FileAccess.open(clean_path, FileAccess.READ)
	if file == null:
		_show_setup_error("Cannot read level file:\n" + clean_path)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_show_setup_error("Invalid JSON level:\n" + clean_path)
		return false

	var data: Dictionary = parsed
	var validation_error: String = level_tools.validate_level(data)
	if not validation_error.is_empty():
		_show_setup_error(
			"Level validation failed for " + clean_path + ":\n" + validation_error
		)
		return false

	ready_to_play = false
	result_was_shown = false
	pause_layer.hide()
	result_layer.hide()
	builder.hide()

	if bool(test_level.get("test_mode")):
		test_level.exit_test_mode()

	level_tools.apply_level_data(data)
	test_level.enter_test_mode()

	if not bool(test_level.get("test_mode")):
		_show_setup_error("The puzzle simulation did not enter test mode.")
		return false

	# PlayerMode handles clicks, not the editor's TestLevel._input().
	# The simulation's _process() and visuals remain active.
	test_level.set_process_input(false)

	var editor_test_bar: Control = test_level.get("test_bar") as Control
	if editor_test_bar != null:
		editor_test_bar.hide()

	level_file_path = clean_path
	builder.show()
	ready_to_play = true
	call_deferred("_fit_level_to_screen")
	print("PlayerMode: loaded ", clean_path)
	return true


func _level_name(path: String) -> String:
	if path.get_file() == "level_001.json":
		return "LEVEL 001 - First Connection"
	if path.get_file() == "level_002_loop.json":
		return "LEVEL 002 - The Second Lap"
	return path.get_file().get_basename().replace("_", " ").capitalize()


# ============================================================
# LEVEL PROGRESSION
# ============================================================

func _get_next_level_path() -> String:
	# Inspector override first. If the field was left empty when the
	# scene was created manually, still progress from Level 001 to 002.
	var configured: String = next_level_path.strip_edges()
	if not configured.is_empty() and configured != level_file_path:
		return configured

	if level_file_path.get_file() == "level_001.json":
		return LEVEL_002_PATH

	return ""


func _next_level() -> void:
	var next_path: String = _get_next_level_path()
	if next_path.is_empty():
		result_description.text += "\n\nNo next level has been configured."
		return

	if not FileAccess.file_exists(next_path):
		result_description.text = (
			"The next level is missing:\n" + next_path
			+ "\n\nPut level_002_loop.json in your project's res://levels/ folder."
		)
		return

	# Loading also resets the result screen, Begin selection,
	# simulation state, and camera framing.
	if _load_level(next_path):
		# The prototype has two levels. Later this can be a campaign list.
		next_level_path = ""


# ============================================================
# FIT THE ACTUAL NETWORK TO THE ENTIRE WINDOW
# ============================================================

func _request_level_fit() -> void:
	if ready_to_play:
		# LevelTools may also fit the editor camera on resize.
		# Run ours deferred so the player-specific fit wins.
		call_deferred("_fit_level_to_screen")


func _fit_level_to_screen() -> void:
	if not ready_to_play or not is_instance_valid(builder):
		return
	if not is_instance_valid(puzzle_grid):
		return

	var camera: Camera2D = builder.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return

	# Only used nodes and paths are included in the bounds.
	# Empty honeycomb edges are not included.
	var points: Array[Vector2] = []
	for value in builder.nodes_by_id.values():
		var node: PuzzleNode = value as PuzzleNode
		if is_instance_valid(node):
			points.append(node.global_position)

	for connection in builder.connection_layer.connections:
		for cell in connection.get("path", []):
			var lattice_cell: Vector2i = cell
			points.append(
				puzzle_grid.to_global(puzzle_grid.cell_to_local(lattice_cell))
			)

	if points.is_empty():
		return

	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)

	var board_center: Vector2 = (minimum + maximum) * 0.5
	var padded_size: Vector2 = maximum - minimum
	padded_size += Vector2.ONE * world_padding * 2.0

	# No top bar, so all four screen margins can be equal.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var usable_size: Vector2 = viewport_size - Vector2.ONE * screen_margin * 2.0
	if usable_size.x <= 80.0 or usable_size.y <= 80.0:
		return

	var desired_zoom: float = minf(
		usable_size.x / maxf(padded_size.x, 1.0),
		usable_size.y / maxf(padded_size.y, 1.0)
	)
	var zoom_value: float = clampf(desired_zoom, 0.01, maximum_zoom)

	camera.position_smoothing_enabled = false
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * zoom_value
	camera.global_position = board_center
	camera.make_current()
	camera.reset_smoothing()


# ============================================================
# BEGIN NODE INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if not ready_to_play or not is_instance_valid(test_level):
		return

	if event is InputEventKey:
		if not event.pressed or event.echo:
			return

		match event.keycode:
			KEY_SPACE, KEY_ESCAPE:
				if not result_layer.visible:
					_toggle_pause()
					get_viewport().set_input_as_handled()
			KEY_R:
				_retry()
				get_viewport().set_input_as_handled()
			KEY_BACKSPACE:
				_reset_to_begin_selection()
				get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if result_layer.visible or pause_layer.visible:
		return

	# A run is already in progress. Retry/Choose Start resets this.
	if not str(test_level.get("selected_start_id")).is_empty():
		return

	# Compare the click against the actual onscreen node centres,
	# not a rounded honeycomb coordinate.
	var closest_uid: String = ""
	var closest_distance: float = INF
	var camera: Camera2D = builder.get_node_or_null("Camera2D") as Camera2D
	var camera_zoom: float = camera.zoom.x if camera != null else 1.0
	var click_radius: float = maxf(26.0, 23.0 * camera_zoom)

	for key in builder.nodes_by_id.keys():
		var node: PuzzleNode = builder.nodes_by_id[key] as PuzzleNode
		if not is_instance_valid(node) or node.kind != PuzzleNode.Kind.BEGIN:
			continue
		var screen_position: Vector2 = node.get_global_transform_with_canvas().origin
		var distance: float = event.position.distance_to(screen_position)
		if distance <= click_radius and distance < closest_distance:
			closest_uid = str(key)
			closest_distance = distance

	if closest_uid.is_empty():
		return

	test_level._start_from(closest_uid)
	get_viewport().set_input_as_handled()


# ============================================================
# PLAYER ACTIONS
# ============================================================

func _toggle_pause() -> void:
	if not ready_to_play or result_layer.visible:
		return
	if str(test_level.get("selected_start_id")).is_empty():
		return
	if bool(test_level.get("finished")):
		return
	test_level._toggle_pause()
	if bool(test_level.get("paused")):
		pause_layer.show()
	else:
		pause_layer.hide()


func _retry() -> void:
	if not ready_to_play:
		return
	pause_layer.hide()
	result_layer.hide()
	result_was_shown = false
	if str(test_level.get("selected_start_id")).is_empty():
		_reset_to_begin_selection()
		return
	test_level._replay()


func _reset_to_begin_selection() -> void:
	if not ready_to_play:
		return
	pause_layer.hide()
	result_layer.hide()
	result_was_shown = false
	test_level._reset_run_state()
	test_level.selected_start_id = ""


# ============================================================
# COMPLETION SCREEN
# ============================================================

func _show_final_result() -> void:
	if not ready_to_play:
		return
	result_was_shown = true

	# The existing EM9 test engine records its outcome in this label:
	# "SUCCESS at tick ..." or "FAILED at tick ...".
	var engine_status: String = ""
	var internal_status: Label = test_level.get("status_label") as Label
	if internal_status != null:
		engine_status = internal_status.text

	var success: bool = engine_status.begins_with("SUCCESS")
	var tick: int = int(test_level.get("current_tick"))
	var reason: String = str(test_level.get("failure_reason"))

	if success:
		result_heading.text = "PUZZLE COMPLETED"
		result_description.text = (
			_level_name(level_file_path)
			+ "\nCompleted at tick %d.\n%s" % [tick, reason]
		)
	else:
		result_heading.text = "TRY AGAIN"
		result_description.text = (
			"Run ended at tick %d.\n%s" % [tick, reason]
		)

	var next_path: String = _get_next_level_path()
	var next_exists: bool = (
		success
		and not next_path.is_empty()
		and FileAccess.file_exists(next_path)
	)
	result_next_button.visible = next_exists

	# Don't silently hide the next-level option if its JSON is missing.
	if success and not next_path.is_empty() and not next_exists:
		result_description.text += (
			"\n\nNEXT LEVEL FILE MISSING:\n" + next_path
			+ "\nCopy its JSON file into res://levels/."
		)
		push_warning("PlayerMode: next level missing: " + next_path)

	result_retry_button.show()
	result_reset_button.show()
	result_layer.show()


func _show_setup_error(message: String) -> void:
	push_error("PlayerMode: " + message)
	ready_to_play = false
	pause_layer.hide()
	result_heading.text = "COULD NOT LOAD LEVEL"
	result_description.text = message
	result_next_button.hide()
	result_retry_button.hide()
	result_reset_button.hide()
	result_layer.show()


# ============================================================
# UI - ONLY MODAL PAUSE AND RESULTS; NO TOP BAR
# ============================================================

func _make_button(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _create_pause_overlay() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.name = "PauseOverlay"
	pause_layer.layer = 150
	add_child(pause_layer)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.13, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.add_child(shade)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	pause_layer.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360.0, 160.0)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = "PAUSED"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	_make_button(row, "Resume", _toggle_pause)
	_make_button(row, "Retry", _retry)
	_make_button(row, "Choose Start", _reset_to_begin_selection)
	pause_layer.hide()


func _create_result_overlay() -> void:
	result_layer = CanvasLayer.new()
	result_layer.name = "ResultOverlay"
	result_layer.layer = 200
	add_child(result_layer)

	var dim := ColorRect.new()
	dim.name = "Dimmer"
	dim.color = Color(0.02, 0.07, 0.15, 0.67)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	result_layer.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.name = "CentreDialog"
	result_layer.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520.0, 230.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	margin.add_child(column)

	result_heading = Label.new()
	result_heading.text = "RESULT"
	result_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_heading.add_theme_font_size_override("font_size", 27)
	column.add_child(result_heading)

	result_description = Label.new()
	result_description.text = ""
	result_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(result_description)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	result_next_button = _make_button(row, "Next Level", _next_level)
	result_retry_button = _make_button(row, "Retry Same Start", _retry)
	result_reset_button = _make_button(row, "Choose Other Start", _reset_to_begin_selection)
	result_layer.hide()
