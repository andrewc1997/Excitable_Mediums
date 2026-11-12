
class_name ExcitableSimulationManager
extends Node


signal status_changed(message: String)
signal tick_changed(tick: int)
signal simulation_finished(won: bool)


# ==================================================
# SETTINGS
# ==================================================

@export var tick_duration: float = 0.65
@export var refractory_ticks: int = 2


# ==================================================
# REFERENCES
# ==================================================

var graph: ExcitableGraph
var tick_timer: Timer


# ==================================================
# STATE
# ==================================================

var running: bool = false
var current_tick: int = 0
var last_start_id: int = -1

var pulses: Array[Dictionary] = []

var failure_reason: String = ""


# ==================================================
# SETUP
# ==================================================

func _ready() -> void:

	tick_timer = Timer.new()
	tick_timer.one_shot = true

	add_child(tick_timer)

	tick_timer.timeout.connect(
		_on_tick_timer_timeout
	)


func setup(p_graph: ExcitableGraph) -> void:

	graph = p_graph
	graph.refractory_ticks = refractory_ticks

	reset_simulation()


# ==================================================
# START SIMULATION
# ==================================================

func start_from_node(node_id: int) -> void:

	if running:
		return

	if not graph.nodes.has(node_id):
		return

	reset_simulation()

	last_start_id = node_id
	running = true

	var node: ExcitableNodeData = graph.nodes[node_id]

	# Selecting a starting node injects one signal.
	if not node.accepts_input_count(1):

		fail_simulation(
			"Node %d requires %d input signals." % [
				node_id,
				node.required_inputs
			],
			node_id
		)
		return

	if not node.try_activate(
		current_tick,
		refractory_ticks
	):

		fail_simulation(
			"Starting node could not activate.",
			node_id
		)
		return

	tick_changed.emit(current_tick)

	if node.is_target:
		check_simulation_end()
		return

	pulses = create_outgoing_pulses(
		node_id,
		{}
	)

	if not validate_output_count(node_id, pulses):
		return

	graph.set_pulse_visuals(pulses, 0.0)

	status_changed.emit(
		"Simulation started at Node %d" % node_id
	)

	if pulses.is_empty():
		check_simulation_end()
		return

	tick_timer.start(tick_duration)


# ==================================================
# ROUTING
# ==================================================

func create_outgoing_pulses(
	node_id: int,
	incoming_sources: Dictionary
) -> Array[Dictionary]:

	var outgoing: Array[Dictionary] = []

	var node: ExcitableNodeData = graph.nodes[node_id]

	var neighbors: Array[int] = (
		graph.get_neighbors(node_id)
	)

	var destinations: Array[int] = (
		node.get_outgoing_neighbors(
			neighbors,
			incoming_sources
		)
	)

	for destination_id in destinations:

		outgoing.append({
			"from": node_id,
			"to": destination_id
		})

	return outgoing


# ==================================================
# OUTPUT VALIDATION
# ==================================================

func validate_output_count(
	node_id: int,
	outgoing: Array[Dictionary]
) -> bool:

	var node: ExcitableNodeData = graph.nodes[node_id]

	if node.node_type == ExcitableNodeData.NodeType.SPLITTER:

		if outgoing.size() != node.output_count:

			fail_simulation(
				"Splitter %d requires %d exits, but has %d." % [
					node_id,
					node.output_count,
					outgoing.size()
				],
				node_id
			)
			return false

	elif outgoing.is_empty():

		fail_simulation(
			"Signal stranded at Node %d." % node_id,
			node_id
		)
		return false

	return true


# ==================================================
# ANIMATION
# ==================================================

func _process(_delta: float) -> void:

	if not running:
		return

	if tick_timer.is_stopped():
		return

	var progress: float = (
		1.0 - tick_timer.time_left / tick_duration
	)

	graph.set_pulse_visuals(
		pulses,
		progress
	)


# ==================================================
# TIMER
# ==================================================

func _on_tick_timer_timeout() -> void:

	if running:
		advance_tick()


# ==================================================
# ADVANCE TICK
# ==================================================

func advance_tick() -> void:

	current_tick += 1
	graph.current_tick = current_tick

	# ==============================================
	# COLLECT EVERY PULSE
	# ==============================================

	var arrivals: Dictionary = {}

	for pulse in pulses:

		var target_id: int = pulse["to"]

		if not arrivals.has(target_id):
			arrivals[target_id] = []

		var node_arrivals: Array = arrivals[target_id]
		node_arrivals.append(pulse)

	# ==============================================
	# PROCESS ARRIVALS
	# ==============================================

	var next_pulses: Array[Dictionary] = []

	for target_id in arrivals.keys():

		var node_id: int = int(target_id)
		var node: ExcitableNodeData = graph.nodes[node_id]

		var incoming: Array = arrivals[target_id]
		var incoming_count: int = incoming.size()

		# Collect the connections signals came from.
		var incoming_sources: Dictionary = {}

		for pulse in incoming:
			var source_id: int = pulse["from"]
			incoming_sources[source_id] = true

		# ==========================================
		# TARGETS ABSORB ONE SIGNAL
		# ==========================================

		if node.is_target:

			if incoming_count != 1:

				fail_simulation(
					"Target %d received %d signals." % [
						node_id,
						incoming_count
					],
					node_id
				)
				return

			if not node.try_activate(
				current_tick,
				refractory_ticks
			):

				fail_simulation(
					"Extra signal reached Target %d." % node_id,
					node_id
				)
				return

			# Targets absorb signals.
			# They never emit outgoing pulses.
			continue

		# ==========================================
		# SPLITTER OVERLOAD
		# ==========================================

		if node.node_type == ExcitableNodeData.NodeType.SPLITTER:

			if not node.accepts_input_count(incoming_count):

				var reason: String = (
					"Splitter %d received %d signals; requires %d." % [
						node_id,
						incoming_count,
						node.required_inputs
					]
				)

				fail_simulation(
					reason,
					node_id
				)
				return

		# ==========================================
		# ACTIVATE NODE
		# ==========================================

		if not node.try_activate(
			current_tick,
			refractory_ticks
		):

			fail_simulation(
				"Signal rejected at Node %d." % node_id,
				node_id
			)
			return

		# ==========================================
		# CREATE OUTPUT SIGNALS
		# ==========================================

		var outgoing: Array[Dictionary] = (
			create_outgoing_pulses(
				node_id,
				incoming_sources
			)
		)

		if not validate_output_count(
			node_id,
			outgoing
		):
			return

		next_pulses.append_array(outgoing)

	# ==============================================
	# COMMIT NEXT PULSES
	# ==============================================

	pulses = next_pulses

	graph.set_pulse_visuals(pulses, 0.0)

	tick_changed.emit(current_tick)

	# ==============================================
	# CHECK END CONDITIONS
	# ==============================================

	if pulses.is_empty():

		check_simulation_end()
		return

	if graph.all_targets_reached():

		status_changed.emit(
			"Targets reached - resolving remaining signals..."
		)

	else:

		status_changed.emit(
			"Propagation in progress..."
		)

	tick_timer.start(tick_duration)


# ==================================================
# END CHECK
# ==================================================

func check_simulation_end() -> void:

	# Never finish while signals remain.
	if not pulses.is_empty():
		return

	if graph.all_targets_reached():

		finish_simulation(
			true,
			"SUCCESS! All signals resolved."
		)

	else:

		finish_simulation(
			false,
			"FAILED! Some targets were not reached."
		)


# ==================================================
# FAILURE
# ==================================================

func fail_simulation(
	reason: String,
	broken_node_id: int = -1
) -> void:

	failure_reason = reason

	if broken_node_id >= 0:

		if graph.nodes.has(broken_node_id):

			var node: ExcitableNodeData = (
				graph.nodes[broken_node_id]
			)

			node.break_node()

	finish_simulation(
		false,
		"FAILED! " + reason
	)


# ==================================================
# FINISH
# ==================================================

func finish_simulation(
	won: bool,
	message: String
) -> void:

	running = false

	tick_timer.stop()

	pulses.clear()

	graph.set_pulse_visuals(pulses, 0.0)

	status_changed.emit(message)
	tick_changed.emit(current_tick)

	simulation_finished.emit(won)


# ==================================================
# RESET
# ==================================================

func reset_simulation() -> void:

	running = false

	if tick_timer != null:
		tick_timer.stop()

	current_tick = 0
	pulses.clear()

	failure_reason = ""

	if graph != null:

		graph.reset_nodes()
		graph.refractory_ticks = refractory_ticks

	tick_changed.emit(current_tick)

	status_changed.emit(
		"Click any node to begin."
	)


# ==================================================
# REPLAY
# ==================================================

func replay_last() -> void:

	if last_start_id < 0:
		return

	if running:
		reset_simulation()

	start_from_node(last_start_id)
