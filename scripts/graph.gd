
class_name ExcitableGraph
extends Node2D

signal node_clicked(node_id: int)


# ==================================================
# NODE TYPE SHORTCUTS
# ==================================================

const NORMAL = ExcitableNodeData.NodeType.NORMAL
const SPLITTER = ExcitableNodeData.NodeType.SPLITTER
const ALTERNATING = ExcitableNodeData.NodeType.ALTERNATING
const STRAIGHT = ExcitableNodeData.NodeType.STRAIGHT_THROUGH
const FIXED = ExcitableNodeData.NodeType.FIXED_SWITCH


# ==================================================
# LEVEL DATA
# ==================================================

const NODE_DATA = [
	{
		"id": 0,
		"pos": Vector2(145, 330),
		"target": false,
		"cap": 1,
		"type": NORMAL
	},
	{
		"id": 1,
		"pos": Vector2(330, 210),
		"target": false,
		"cap": 1,
		"type": NORMAL
	},
	{
		"id": 2,
		"pos": Vector2(330, 450),
		"target": false,
		"cap": 3,
		"type": ALTERNATING
	},
	{
		"id": 3,
		"pos": Vector2(535, 210),
		"target": false,
		"cap": 1,
		"type": NORMAL
	},
	{
		"id": 4,
		"pos": Vector2(535, 450),
		"target": false,
		"cap": 1,
		"type": NORMAL
	},
	{
		"id": 5,
		"pos": Vector2(735, 330),
		"target": false,
		"cap": 1,
		"type": SPLITTER,
		"required_inputs": 1,
		"output_count": 2
	},
	{
		"id": 6,
		"pos": Vector2(920, 220),
		"target": true,
		"cap": 1,
		"type": NORMAL
	},
	{
		"id": 7,
		"pos": Vector2(920, 445),
		"target": true,
		"cap": 1,
		"type": NORMAL
	}
]


# ==================================================
# CONNECTIONS
# ==================================================

const EDGE_DATA = [
	[5, 6],
	[5, 7],
	[0, 1],
	[0, 2],
	[1, 3],
	[2, 4],
	[3, 5],
	[4, 5]
]


# ==================================================
# COLOURS
# ==================================================

const NODE_RADIUS: float = 22.0
const PULSE_RADIUS: float = 7.0

const COLOR_NORMAL = Color("#64748b")
const COLOR_SPLITTER = Color("#d97706")
const COLOR_ALTERNATING = Color("#0e7490")
const COLOR_STRAIGHT = Color("#15803d")
const COLOR_FIXED = Color("#7c3aed")

const COLOR_EXCITED = Color("#22d3ee")
const COLOR_REFRACTORY = Color("#a855f7")
const COLOR_TARGET = Color("#eab308")
const COLOR_EXHAUSTED = Color("#334155")

const COLOR_BROKEN = Color("#991b1b")
const COLOR_BROKEN_BORDER = Color("#f87171")

const COLOR_EDGE = Color("#64748b")
const COLOR_PULSE = Color.WHITE


# ==================================================
# STATE
# ==================================================

var nodes: Dictionary = {}
var edges: Array[Vector2i] = []

var current_tick: int = 0
var refractory_ticks: int = 2

var pulse_visuals: Array[Dictionary] = []
var pulse_progress: float = 0.0


# ==================================================
# SETUP
# ==================================================

func _ready() -> void:
	build_graph()


func build_graph() -> void:

	nodes.clear()
	edges.clear()

	for data in NODE_DATA:

		var inputs: int = int(
			data.get("required_inputs", 1)
		)

		var outputs: int = int(
			data.get("output_count", 2)
		)

		var node_data = ExcitableNodeData.new(
			data["id"],
			data["pos"],
			data["target"],
			data["cap"],
			data["type"],
			inputs,
			outputs
		)

		nodes[node_data.node_id] = node_data

	for edge in EDGE_DATA:

		edges.append(
			Vector2i(edge[0], edge[1])
		)

	queue_redraw()


# ==================================================
# CONNECTIONS
# ==================================================

func get_neighbors(node_id: int) -> Array[int]:

	var neighbors: Array[int] = []

	for edge in edges:

		if edge.x == node_id:
			neighbors.append(edge.y)

		elif edge.y == node_id:
			neighbors.append(edge.x)

	return neighbors


# ==================================================
# TARGETS
# ==================================================

func all_targets_reached() -> bool:

	var target_count: int = 0

	for node in nodes.values():

		if node.is_target:

			target_count += 1

			if not node.has_reached_target():
				return false

	return target_count > 0


# ==================================================
# RESET
# ==================================================

func reset_nodes() -> void:

	for node in nodes.values():
		node.reset()

	current_tick = 0

	pulse_visuals.clear()
	pulse_progress = 0.0

	queue_redraw()


# ==================================================
# PULSE VISUALS
# ==================================================

func set_pulse_visuals(
	new_pulses: Array[Dictionary],
	progress: float
) -> void:

	pulse_visuals = new_pulses
	pulse_progress = clampf(progress, 0.0, 1.0)

	queue_redraw()


# ==================================================
# PLAYER INPUT
# ==================================================

func _unhandled_input(event: InputEvent) -> void:

	if event is InputEventMouseButton:

		if event.button_index != MOUSE_BUTTON_LEFT:
			return

		if not event.pressed:
			return

		var mouse_position: Vector2 = (
			get_local_mouse_position()
		)

		for node_id in nodes:

			var node: ExcitableNodeData = nodes[node_id]

			if mouse_position.distance_to(
				node.position
			) <= NODE_RADIUS:

				node_clicked.emit(node_id)

				get_viewport().set_input_as_handled()
				return


# ==================================================
# DRAWING
# ==================================================

func _draw() -> void:

	draw_edges()
	draw_pulses()
	draw_nodes()


func draw_edges() -> void:

	for edge in edges:

		var from_node: ExcitableNodeData = nodes[edge.x]
		var to_node: ExcitableNodeData = nodes[edge.y]

		draw_line(
			from_node.position,
			to_node.position,
			COLOR_EDGE,
			3.0,
			true
		)


func draw_pulses() -> void:

	for pulse in pulse_visuals:

		var from_node: ExcitableNodeData = (
			nodes[pulse["from"]]
		)

		var to_node: ExcitableNodeData = (
			nodes[pulse["to"]]
		)

		var pulse_position: Vector2 = (
			from_node.position.lerp(
				to_node.position,
				pulse_progress
			)
		)

		draw_circle(
			pulse_position,
			PULSE_RADIUS,
			COLOR_PULSE
		)


func draw_nodes() -> void:

	for node_id in nodes:

		var node: ExcitableNodeData = nodes[node_id]

		var node_color: Color = get_node_color(node)
		var border_color: Color = get_type_color(node)

		if node.is_broken:
			border_color = COLOR_BROKEN_BORDER

		draw_circle(
			node.position,
			NODE_RADIUS,
			node_color
		)

		draw_arc(
			node.position,
			NODE_RADIUS,
			0.0,
			TAU,
			48,
			border_color,
			3.0,
			true
		)

		if node.is_target:

			draw_arc(
				node.position,
				NODE_RADIUS + 6.0,
				0.0,
				TAU,
				48,
				COLOR_TARGET,
				3.0,
				true
			)

		if node.is_broken:
			draw_broken_symbol(node.position)
		else:
			draw_node_symbol(node)

		# Node number below the circle.
		draw_centered_text(
			node.position + Vector2(0, 42),
			str(node_id),
			15,
			40
		)


# ==================================================
# SYMBOLS
# ==================================================

func draw_node_symbol(node: ExcitableNodeData) -> void:

	var center: Vector2 = node.position

	match node.node_type:

		ExcitableNodeData.NodeType.NORMAL:

			draw_circle(
				center,
				5.0,
				Color.WHITE
			)


		ExcitableNodeData.NodeType.SPLITTER:

			var notation: String = (
				"%d<%d" % [
					node.required_inputs,
					node.output_count
				]
			)

			draw_centered_text(
				center + Vector2(0, 6),
				notation,
				17,
				43
			)


		ExcitableNodeData.NodeType.ALTERNATING:

			draw_centered_text(
				center + Vector2(0, 7),
				"A",
				21,
				35
			)


		ExcitableNodeData.NodeType.STRAIGHT_THROUGH:

			draw_centered_text(
				center + Vector2(0, 7),
				"S",
				21,
				35
			)


		ExcitableNodeData.NodeType.FIXED_SWITCH:

			draw_centered_text(
				center + Vector2(0, 7),
				"F",
				21,
				35
			)


func draw_broken_symbol(center: Vector2) -> void:

	# Jagged crack across the node.
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(-10, -15),
		center + Vector2(1, -5),
		center + Vector2(-5, 4),
		center + Vector2(10, 16)
	])

	draw_polyline(
		points,
		Color("#fecaca"),
		3.0,
		true
	)


func draw_centered_text(
	center: Vector2,
	value: String,
	font_size: int,
	text_width: float
) -> void:

	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-text_width / 2.0, 0),
		value,
		HORIZONTAL_ALIGNMENT_CENTER,
		text_width,
		font_size,
		Color.WHITE
	)


# ==================================================
# COLOURS
# ==================================================

func get_type_color(
	node: ExcitableNodeData
) -> Color:

	match node.node_type:

		ExcitableNodeData.NodeType.SPLITTER:
			return COLOR_SPLITTER

		ExcitableNodeData.NodeType.ALTERNATING:
			return COLOR_ALTERNATING

		ExcitableNodeData.NodeType.STRAIGHT_THROUGH:
			return COLOR_STRAIGHT

		ExcitableNodeData.NodeType.FIXED_SWITCH:
			return COLOR_FIXED

	return Color.WHITE


func get_node_color(
	node: ExcitableNodeData
) -> Color:

	if node.is_broken:
		return COLOR_BROKEN

	if node.activation_count > 0:

		var ticks_since: int = (
			current_tick - node.last_activation_tick
		)

		if ticks_since == 0:
			return COLOR_EXCITED

		if ticks_since <= refractory_ticks:
			return COLOR_REFRACTORY

		if node.activation_count >= node.activation_cap:
			return COLOR_EXHAUSTED

	if node.is_target:
		return COLOR_TARGET

	match node.node_type:

		ExcitableNodeData.NodeType.SPLITTER:
			return COLOR_SPLITTER

		ExcitableNodeData.NodeType.ALTERNATING:
			return COLOR_ALTERNATING

		ExcitableNodeData.NodeType.STRAIGHT_THROUGH:
			return COLOR_STRAIGHT

		ExcitableNodeData.NodeType.FIXED_SWITCH:
			return COLOR_FIXED

	return COLOR_NORMAL
