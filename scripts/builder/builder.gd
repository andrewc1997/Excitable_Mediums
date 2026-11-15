
extends Node2D

# ============================================================
# EXCITABLE MEDIUMS - LEVEL BUILDER
# Godot 4.3
#
# Palette drag: Place node
# Left drag between nodes: Create connection
# Shift + left drag: Move node
# Right-click node: Delete node
# Right-click line: Delete connection
# Middle drag: Pan
# Mouse wheel: Zoom
#
# Supports Square and X-stretched Rhombus.
# ============================================================

const NODE_SCENE: PackedScene = preload(
	"res://scenes/nodes/puzzle_node.tscn"
)

const CONNECTION_DELETE_RADIUS_PX: float = 12.0
const NODE_CLICK_RADIUS: float = 23.0

# ============================================================
# NODE REFERENCES
# ============================================================

@onready var grid: PuzzleGridBase = $Grid
@onready var connection_layer: BuilderConnections = $Connections
@onready var placed_nodes: Node2D = $PlacedNodes
@onready var camera: Camera2D = $Camera2D

@onready var tool_label: Label = (
	get_node_or_null("CanvasLayer/UI/ToolLabel") as Label
)

@onready var help_label: Label = (
	get_node_or_null("CanvasLayer/UI/HelpLabel") as Label
)

@onready var builder_ui: Node = $BuilderUI
@onready var level_tools: Node = $LevelTools
@onready var test_level: Node2D = $TestLevel

# ============================================================
# EDITOR STATE
# ============================================================

var connection_start_id: String = ""
var dragging_node_id: String = ""
var selected_node_id: String = ""

var is_panning: bool = false

var palette_drag_kind: int = -1
var palette_preview: PuzzleNode

# ============================================================
# LEVEL DATA
# ============================================================

var nodes_by_id: Dictionary = {}
var cells_to_ids: Dictionary = {}

var next_node_number: int = 1

# ============================================================
# READY
# ============================================================

func _ready() -> void:

	camera.make_current()
	connection_layer.setup(grid)

	if help_label != null:
		help_label.text = (
			"Drag templates | Shift+Drag: Move | "
			+ "Middle drag: Pan"
		)

	if tool_label != null:
		tool_label.text = "Builder Ready"

	update_tool_label()


# ============================================================
# CHECK EDITING STATE
# ============================================================

func is_editing_blocked() -> bool:

	if test_level != null:

		if test_level.get("test_mode") == true:
			return true

	if level_tools != null:

		var code_overlay: Variant = (
			level_tools.get("overlay")
		)

		if is_instance_valid(code_overlay):

			if code_overlay.visible:
				return true

	return false


# ============================================================
# CHECK POINTER OVER BUILDER UI
# ============================================================

func is_pointer_over_builder_ui(
	screen_position: Vector2
) -> bool:

	if builder_ui == null:
		return false

	return builder_ui.is_pointer_over_ui(
		screen_position
	)


# ============================================================
# PALETTE DRAG
# ============================================================

func begin_palette_drag(kind: int) -> void:

	if is_editing_blocked():
		return

	cancel_palette_drag()

	connection_start_id = ""
	dragging_node_id = ""

	palette_drag_kind = kind

	palette_preview = (
		NODE_SCENE.instantiate() as PuzzleNode
	)

	if palette_preview == null:

		palette_drag_kind = -1
		return

	palette_preview.kind = kind
	palette_preview.modulate.a = 0.65
	palette_preview.z_index = 20

	add_child(palette_preview)

	palette_preview.global_position = (
		get_global_mouse_position()
	)

	update_tool_label()


func cancel_palette_drag() -> void:

	palette_drag_kind = -1

	if is_instance_valid(palette_preview):
		palette_preview.queue_free()

	palette_preview = null


func _process(_delta: float) -> void:

	if palette_drag_kind < 0:
		return

	if is_instance_valid(palette_preview):

		palette_preview.global_position = (
			get_global_mouse_position()
		)


# ============================================================
# INPUT
#
# ALL MOUSE INPUT IS HANDLED HERE.
#
# Do not also process mouse buttons in
# _unhandled_input().
# ============================================================

func _input(event: InputEvent) -> void:

	if is_editing_blocked():
		return

	# ====================================================
	# KEYBOARD
	# ====================================================

	if event is InputEventKey:

		if not event.pressed or event.echo:
			return

		if event.keycode == KEY_ESCAPE:

			cancel_palette_drag()

			connection_start_id = ""
			dragging_node_id = ""
			is_panning = false

			update_tool_label()

			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_DELETE:

			if selected_node_id != "":
				delete_node(selected_node_id)

			get_viewport().set_input_as_handled()
			return

		return

	# ====================================================
	# MOUSE MOVEMENT
	# ====================================================

	if event is InputEventMouseMotion:

		# Panning takes priority.
		if is_panning:

			camera.position -= (
				event.relative
				/ maxf(camera.zoom.x, 0.01)
			)

			get_viewport().set_input_as_handled()
			return

		# Node relocation.
		if dragging_node_id != "":

			move_node_to_mouse(dragging_node_id)

			get_viewport().set_input_as_handled()
			return

		return

	# ====================================================
	# MOUSE BUTTONS
	# ====================================================

	if not (event is InputEventMouseButton):
		return

	# ====================================================
	# MIDDLE BUTTON: PAN
	# ====================================================

	if event.button_index == MOUSE_BUTTON_MIDDLE:

		if event.pressed:

			if not is_pointer_over_builder_ui(
				event.position
			):
				is_panning = true

		else:
			is_panning = false

		if is_panning:
			get_viewport().set_input_as_handled()

		return

	# ====================================================
	# MOUSE WHEEL: ZOOM
	# ====================================================

	if event.pressed:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:

			if not is_pointer_over_builder_ui(
				event.position
			):

				change_zoom(1.1)
				get_viewport().set_input_as_handled()

			return

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:

			if not is_pointer_over_builder_ui(
				event.position
			):

				change_zoom(1.0 / 1.1)
				get_viewport().set_input_as_handled()

			return

	# ====================================================
	# RIGHT CLICK: DELETE
	# ====================================================

	if event.button_index == MOUSE_BUTTON_RIGHT:

		if event.pressed:

			if not is_pointer_over_builder_ui(
				event.position
			):

				handle_right_click()
				get_viewport().set_input_as_handled()

		return

	# ====================================================
	# LEFT BUTTON ONLY BELOW THIS POINT
	# ====================================================

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	# ====================================================
	# LEFT PRESS
	# ====================================================

	if event.pressed:

		# Palette dragging begins in BuilderUI.
		# Never start a connection at the same time.
		if palette_drag_kind >= 0:
			return

		if is_panning:
			return

		if is_pointer_over_builder_ui(
			event.position
		):
			return

		handle_left_press(event.shift_pressed)

		# Only consume a press that actually selected
		# a node for movement or connection creation.
		if (
			connection_start_id != ""
			or dragging_node_id != ""
		):

			get_viewport().set_input_as_handled()

		return

	# ====================================================
	# LEFT RELEASE: DROP PALETTE NODE
	# ====================================================

	if palette_drag_kind >= 0:

		var kind: int = palette_drag_kind

		cancel_palette_drag()

		if not is_pointer_over_builder_ui(
			event.position
		):

			var cell: Vector2i = get_mouse_cell()

			if grid.is_valid_cell(cell):
				place_node(cell, kind)

		update_tool_label()

		get_viewport().set_input_as_handled()
		return

	# ====================================================
	# LEFT RELEASE: FINISH MOVING NODE
	# ====================================================

	if dragging_node_id != "":

		var moved_uid: String = dragging_node_id

		dragging_node_id = ""

		if nodes_by_id.has(moved_uid):
			select_node(moved_uid)

		update_tool_label()

		get_viewport().set_input_as_handled()
		return

	# ====================================================
	# LEFT RELEASE: FINISH CONNECTION
	# ====================================================

	if connection_start_id != "":

		var from_id: String = connection_start_id

		connection_start_id = ""

		if not is_pointer_over_builder_ui(
			event.position
		):

			var target_cell: Vector2i = (
				get_mouse_cell()
			)

			var to_id: String = (
				get_id_at_cell(target_cell)
			)

			if (
				to_id != ""
				and to_id != from_id
			):

				create_connection(from_id, to_id)

		update_tool_label()

		get_viewport().set_input_as_handled()
		return


# ============================================================
# GRID COORDINATES
# ============================================================

func get_mouse_cell() -> Vector2i:

	var world_position: Vector2 = (
		get_global_mouse_position()
	)

	return grid.local_to_cell(
		grid.to_local(world_position)
	)


func get_id_at_cell(cell: Vector2i) -> String:

	if cells_to_ids.has(cell):
		return str(cells_to_ids[cell])

	return ""


func get_node_cell(uid: String) -> Vector2i:

	var node: PuzzleNode = nodes_by_id[uid]
	return node.grid_cell


# ============================================================
# SELECT NODE
# ============================================================

func select_node(uid: String) -> void:

	if selected_node_id != "":

		if nodes_by_id.has(selected_node_id):

			var old_node: PuzzleNode = (
				nodes_by_id[selected_node_id]
			)

			old_node.selected = false
			old_node.queue_redraw()

	selected_node_id = uid

	if uid != "" and nodes_by_id.has(uid):

		var node: PuzzleNode = nodes_by_id[uid]

		node.selected = true
		node.queue_redraw()

	builder_ui.show_selected_node(uid)


# ============================================================
# LEFT PRESS: SELECT / CONNECT / MOVE
# ============================================================

func handle_left_press(
	shift_held: bool
) -> void:

	var cell: Vector2i = get_mouse_cell()

	if not grid.is_valid_cell(cell):

		select_node("")
		return

	var uid: String = get_id_at_cell(cell)

	if uid == "":

		select_node("")
		return

	select_node(uid)

	if shift_held:

		connection_start_id = ""
		dragging_node_id = uid

	else:

		dragging_node_id = ""
		connection_start_id = uid

	update_tool_label()


# ============================================================
# PLACE NODE
# ============================================================

func place_node(
	cell: Vector2i,
	kind: int
) -> void:

	if not grid.is_valid_cell(cell):
		return

	if cells_to_ids.has(cell):
		return

	# Only one Begin Node per level.
	if kind == PuzzleNode.Kind.BEGIN:

		for existing in nodes_by_id.values():

			var existing_node: PuzzleNode = existing

			if existing_node.kind == PuzzleNode.Kind.BEGIN:

				print("Only one Begin Node is permitted.")
				return

	var proposed_occupancy: Dictionary = (
		cells_to_ids.duplicate()
	)

	proposed_occupancy[cell] = "new_node"

	var proposed_paths: Array[Dictionary] = []

	if not build_connection_paths(
		proposed_occupancy,
		{},
		connection_layer.connections,
		proposed_paths
	):

		print("Cannot place node: connections blocked.")
		return

	var node: PuzzleNode = (
		NODE_SCENE.instantiate() as PuzzleNode
	)

	if node == null:
		return

	var uid: String = (
		"node_%04d" % next_node_number
	)

	while nodes_by_id.has(uid):

		next_node_number += 1

		uid = (
			"node_%04d" % next_node_number
		)

	next_node_number += 1

	node.node_uid = uid
	node.grid_cell = cell
	node.kind = kind

	placed_nodes.add_child(node)

	node.position = placed_nodes.to_local(
		grid.to_global(
			grid.cell_to_local(cell)
		)
	)

	nodes_by_id[uid] = node
	cells_to_ids[cell] = uid

	connection_layer.connections = proposed_paths
	connection_layer.refresh_connections()

	select_node(uid)


# ============================================================
# MOVE NODE
# ============================================================

func move_node_to_mouse(uid: String) -> void:

	if not nodes_by_id.has(uid):
		return

	var cell: Vector2i = get_mouse_cell()

	if not grid.is_valid_cell(cell):
		return

	var node: PuzzleNode = nodes_by_id[uid]

	if node.grid_cell == cell:
		return

	if cells_to_ids.has(cell):
		return

	var proposed_occupancy: Dictionary = (
		cells_to_ids.duplicate()
	)

	proposed_occupancy.erase(node.grid_cell)
	proposed_occupancy[cell] = uid

	var overrides: Dictionary = {
		uid: cell
	}

	var proposed_paths: Array[Dictionary] = []

	if not build_connection_paths(
		proposed_occupancy,
		overrides,
		connection_layer.connections,
		proposed_paths
	):
		return

	cells_to_ids.erase(node.grid_cell)

	node.grid_cell = cell

	node.position = placed_nodes.to_local(
		grid.to_global(
			grid.cell_to_local(cell)
		)
	)

	cells_to_ids[cell] = uid

	connection_layer.connections = proposed_paths
	connection_layer.refresh_connections()

	builder_ui.show_selected_node(uid)


# ============================================================
# RIGHT CLICK
# ============================================================

func handle_right_click() -> void:

	var node_uid: String = get_node_under_mouse()

	if node_uid != "":

		delete_node(node_uid)
		return

	var connection_index: int = (
		get_connection_under_mouse()
	)

	if connection_index >= 0:
		delete_connection(connection_index)


# ============================================================
# FIND NODE UNDER MOUSE
# ============================================================

func get_node_under_mouse() -> String:

	var mouse_world: Vector2 = (
		get_global_mouse_position()
	)

	var closest_uid: String = ""
	var closest_distance: float = NODE_CLICK_RADIUS

	for uid in nodes_by_id.keys():

		var node: PuzzleNode = nodes_by_id[uid]

		var distance: float = (
			mouse_world.distance_to(
				node.global_position
			)
		)

		if distance <= closest_distance:

			closest_distance = distance
			closest_uid = str(uid)

	return closest_uid


# ============================================================
# FIND CONNECTION UNDER MOUSE
# ============================================================

func get_connection_under_mouse() -> int:

	var mouse_world: Vector2 = (
		get_global_mouse_position()
	)

	var threshold: float = (
		CONNECTION_DELETE_RADIUS_PX
		/ maxf(camera.zoom.x, 0.01)
	)

	var closest_index: int = -1
	var closest_distance: float = threshold

	for connection_index in range(
		connection_layer.connections.size()
	):

		var connection: Dictionary = (
			connection_layer.connections[connection_index]
		)

		var path: Array[Vector2i] = []

		for cell in connection["path"]:
			path.append(cell)

		if path.size() < 2:
			continue

		for segment_index in range(
			path.size() - 1
		):

			var start_cell: Vector2i = (
				path[segment_index]
			)

			var end_cell: Vector2i = (
				path[segment_index + 1]
			)

			var start_world: Vector2 = (
				grid.to_global(
					grid.cell_to_local(start_cell)
				)
			)

			var end_world: Vector2 = (
				grid.to_global(
					grid.cell_to_local(end_cell)
				)
			)

			var nearest_point: Vector2 = (
				Geometry2D.get_closest_point_to_segment(
					mouse_world,
					start_world,
					end_world
				)
			)

			var distance: float = (
				mouse_world.distance_to(
					nearest_point
				)
			)

			if distance <= closest_distance:

				closest_distance = distance
				closest_index = connection_index

	return closest_index


# ============================================================
# DELETE CONNECTION
# ============================================================

func delete_connection(index: int) -> void:

	if index < 0:
		return

	if index >= connection_layer.connections.size():
		return

	var connection: Dictionary = (
		connection_layer.connections[index]
	)

	var from_id: String = str(
		connection["from_uid"]
	)

	var to_id: String = str(
		connection["to_uid"]
	)

	connection_layer.connections.remove_at(index)
	connection_layer.refresh_connections()

	connection_start_id = ""
	update_tool_label()

	if is_instance_valid(tool_label):

		tool_label.text = (
			"Removed connection: %s -> %s"
			% [from_id, to_id]
		)


# ============================================================
# DELETE NODE
# ============================================================

func handle_delete_click() -> void:
	handle_right_click()


func delete_node(uid: String) -> void:

	if not nodes_by_id.has(uid):
		return

	var node: PuzzleNode = nodes_by_id[uid]

	cells_to_ids.erase(node.grid_cell)

	for index in range(
		connection_layer.connections.size() - 1,
		-1,
		-1
	):

		var connection: Dictionary = (
			connection_layer.connections[index]
		)

		if (
			connection["from_uid"] == uid
			or connection["to_uid"] == uid
		):

			connection_layer.connections.remove_at(index)

	nodes_by_id.erase(uid)

	node.queue_free()

	if selected_node_id == uid:

		selected_node_id = ""
		builder_ui.show_selected_node("")

	if connection_start_id == uid:
		connection_start_id = ""

	if dragging_node_id == uid:
		dragging_node_id = ""

	# Preserve existing routing behaviour.
	var proposed_paths: Array[Dictionary] = []

	if build_connection_paths(
		cells_to_ids,
		{},
		connection_layer.connections,
		proposed_paths
	):

		connection_layer.connections = proposed_paths

	connection_layer.refresh_connections()
	update_tool_label()


# ============================================================
# CREATE DIRECTED CONNECTION
# ============================================================

func create_connection(
	from_id: String,
	to_id: String
) -> void:

	if not nodes_by_id.has(from_id):
		return

	if not nodes_by_id.has(to_id):
		return

	if from_id == to_id:
		return

	# Begin Nodes cannot receive incoming connections.
	var destination: PuzzleNode = nodes_by_id[to_id]

	if destination.kind == PuzzleNode.Kind.BEGIN:

		print("Cannot connect into a Begin Node.")
		return

	# Prevent duplicates in either direction.
	for connection in connection_layer.connections:

		var a: String = str(connection["from_uid"])
		var b: String = str(connection["to_uid"])

		if (
			(a == from_id and b == to_id)
			or (a == to_id and b == from_id)
		):
			return

	var proposed_connections: Array[Dictionary] = []

	proposed_connections.append_array(
		connection_layer.connections
	)

	proposed_connections.append({
		"from_uid": from_id,
		"to_uid": to_id
	})

	var proposed_paths: Array[Dictionary] = []

	if not build_connection_paths(
		cells_to_ids,
		{},
		proposed_connections,
		proposed_paths
	):

		print("No valid connection route.")
		return

	connection_layer.connections = proposed_paths
	connection_layer.refresh_connections()


# ============================================================
# MULTI-ATTEMPT CONNECTION ROUTING
# ============================================================

func build_connection_paths(
	occupancy: Dictionary,
	position_overrides: Dictionary,
	source_connections: Array[Dictionary],
	result: Array[Dictionary]
) -> bool:

	result.clear()

	if source_connections.is_empty():
		return true

	var attempt_count: int = (
		8 + mini(source_connections.size(), 6)
	)

	for mode in range(attempt_count):

		var order: Array[int] = _get_connection_order(
			source_connections,
			position_overrides,
			mode
		)

		var proposed_result: Array[Dictionary] = []

		if _try_connection_order(
			occupancy,
			position_overrides,
			source_connections,
			order,
			proposed_result
		):

			result.append_array(proposed_result)
			return true

	return false


# ============================================================
# GET CONNECTION ORDER
# ============================================================

func _get_connection_order(
	source_connections: Array[Dictionary],
	position_overrides: Dictionary,
	mode: int
) -> Array[int]:

	var order: Array[int] = []

	for index in range(source_connections.size()):
		order.append(index)

	var count: int = source_connections.size()

	order.sort_custom(
		func(a: int, b: int) -> bool:

			var priority_a: int = (
				_connection_route_priority(
					source_connections[a],
					position_overrides,
					mode,
					a,
					count
				)
			)

			var priority_b: int = (
				_connection_route_priority(
					source_connections[b],
					position_overrides,
					mode,
					b,
					count
				)
			)

			if priority_a == priority_b:
				return a < b

			return priority_a < priority_b
	)

	return order


# ============================================================
# ROUTING PRIORITIES
# ============================================================

func _connection_route_priority(
	connection: Dictionary,
	position_overrides: Dictionary,
	mode: int,
	index: int,
	count: int
) -> int:

	var from_id: String = str(
		connection["from_uid"]
	)

	var to_id: String = str(
		connection["to_uid"]
	)

	var from_cell: Vector2i = get_node_cell(from_id)
	var to_cell: Vector2i = get_node_cell(to_id)

	if position_overrides.has(from_id):
		from_cell = position_overrides[from_id]

	if position_overrides.has(to_id):
		to_cell = position_overrides[to_id]

	var is_straight: bool = (
		from_cell.x == to_cell.x
		or from_cell.y == to_cell.y
	)

	var touches_moved_node: bool = (
		position_overrides.has(from_id)
		or position_overrides.has(to_id)
	)

	var distance: int = (
		absi(to_cell.x - from_cell.x)
		+ absi(to_cell.y - from_cell.y)
	)

	match mode:

		0:
			return 0 if is_straight else 1

		1:
			return index

		2:
			return count - index

		3:
			return 0 if touches_moved_node else 1

		4:
			return 1 if touches_moved_node else 0

		5:
			return distance

		6:
			return -distance

		7:
			return 1 if is_straight else 0

		_:

			var offset: int = mode - 8

			return posmod(index - offset, count)


# ============================================================
# TRY ONE CONNECTION ROUTING ORDER
# ============================================================

func _try_connection_order(
	occupancy: Dictionary,
	position_overrides: Dictionary,
	source_connections: Array[Dictionary],
	order: Array[int],
	result: Array[Dictionary]
) -> bool:

	result.clear()

	var reserved_cells: Dictionary = {}

	for index in order:

		var connection: Dictionary = (
			source_connections[index]
		)

		var from_id: String = str(
			connection["from_uid"]
		)

		var to_id: String = str(
			connection["to_uid"]
		)

		if not nodes_by_id.has(from_id):
			return false

		if not nodes_by_id.has(to_id):
			return false

		var from_cell: Vector2i = (
			get_node_cell(from_id)
		)

		var to_cell: Vector2i = (
			get_node_cell(to_id)
		)

		if position_overrides.has(from_id):
			from_cell = position_overrides[from_id]

		if position_overrides.has(to_id):
			to_cell = position_overrides[to_id]

		var path: Array[Vector2i] = (
			grid.get_connection_path(
				from_cell,
				to_cell,
				occupancy,
				reserved_cells
			)
		)

		if path.size() < 2:
			return false

		reserve_path_cells(
			path,
			reserved_cells
		)

		result.append(
			make_connection_record(
				from_id,
				to_id,
				path
			)
		)

	return true


# ============================================================
# RESERVE INTERMEDIATE PATH CELLS
# ============================================================

func reserve_path_cells(
	path: Array[Vector2i],
	reserved_cells: Dictionary
) -> void:

	if path.size() < 2:
		return

	var first_cell: Vector2i = path[0]
	var last_cell: Vector2i = path[path.size() - 1]

	for index in range(path.size() - 1):

		var start_cell: Vector2i = path[index]
		var end_cell: Vector2i = path[index + 1]

		var difference: Vector2i = (
			end_cell - start_cell
		)

		var distance: int = maxi(
			absi(difference.x),
			absi(difference.y)
		)

		if distance == 0:
			continue

		var direction := Vector2i(
			signi(difference.x),
			signi(difference.y)
		)

		for step in range(distance + 1):

			var cell: Vector2i = (
				start_cell + direction * step
			)

			if cell == first_cell or cell == last_cell:
				continue

			reserved_cells[cell] = true


# ============================================================
# CREATE CONNECTION RECORD
# ============================================================

func make_connection_record(
	from_id: String,
	to_id: String,
	path: Array[Vector2i]
) -> Dictionary:

	var last_index: int = path.size() - 1

	return {
		"from_uid": from_id,
		"to_uid": to_id,
		"from_port": grid.get_port_direction(
			path[0],
			path[1]
		),
		"to_port": grid.get_port_direction(
			path[last_index],
			path[last_index - 1]
		),
		"path": path
	}


# ============================================================
# CAMERA ZOOM
# ============================================================

func change_zoom(factor: float) -> void:

	var next_zoom: float = clampf(
		camera.zoom.x * factor,
		0.4,
		2.5
	)

	camera.zoom = Vector2.ONE * next_zoom


# ============================================================
# OPTIONAL TOOL LABEL
# ============================================================

func update_tool_label() -> void:

	# The old UI node was removed.
	# Do not attempt to update missing labels.
	if not is_instance_valid(tool_label):
		return

	if palette_drag_kind >= 0:

		tool_label.text = "Drag template onto grid"

	elif dragging_node_id != "":

		tool_label.text = (
			"Moving node: %s" % dragging_node_id
		)

	elif connection_start_id != "":

		tool_label.text = (
			"Connecting from %s"
			% connection_start_id
		)

	else:

		tool_label.text = "Builder Ready"
