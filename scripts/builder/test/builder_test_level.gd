
extends Node2D

# Excitable Mediums EM6 playtest, Godot 4.3.
# Includes timeline, snapshots, pause, step controls and speed.
# Preserves Bounce, Repeater, Delay, One-Way Gate and pulse trails.

@export_category("Simulation Speed")
@export_range(0.08, 0.80, 0.01)
var tick_seconds: float = 0.22

const MAX_TICKS: int = 2000
const MAX_ACTIVE_PULSES: int = 5000

const PULSE_COLOR: Color = Color("#49d9ed")
const SECOND_PULSE_COLOR: Color = Color("#b4efff")
const TARGET_REACHED_COLOR: Color = Color("#49db86")
const REFRACTORY_COLOR: Color = Color("#9763c7")

@export_category("Overlapping Signal Animation")
@export_range(0.0, 30.0, 0.5)
var wave_amplitude: float = 11.0

@export_range(0.5, 10.0, 0.1)
var wavelength_cells: float = 2.0

@export_range(0.0, 3.0, 0.05)
var rotation_speed: float = 0.25

@export_range(0.0, 6.0, 0.25)
var size_variation: float = 3.0

@export_range(3.0, 12.0, 0.5)
var base_pulse_radius: float = 7.0

@export_category("Signal Trails")
@export_range(0.0, 1.5, 0.05)
var trail_length_cells: float = 0.65

@export_range(2, 16, 1)
var trail_samples: int = 7

@export_range(0.0, 1.0, 0.05)
var trail_opacity: float = 0.55

# ============================================================
# REFERENCES
# ============================================================

var builder: Node2D
var grid: PuzzleGridBase
var ui_layer: CanvasLayer
var level_tools: Node
var connection_layer: BuilderConnections

var gate_rules: PulseGateRules = PulseGateRules.new()

# ============================================================
# SIMULATION
# ============================================================

var test_mode: bool = false
var running: bool = false
var finished: bool = false

var current_tick: int = 0
var tick_accumulator: float = 0.0

var selected_start_id: String = ""
var failure_reason: String = ""

var pulses: Array[Dictionary] = []
var links: Array[Dictionary] = []
var node_states: Dictionary = {}
var delayed_pulses: Array[Dictionary] = []

# {"uid", "next_tick", "interval", "remaining"}
var repeater_jobs: Array[Dictionary] = []

var targets_total: int = 0
var targets_reached: int = 0

# ============================================================
# UI
# ============================================================

var test_button: Button
var test_bar: PanelContainer
var status_label: Label
var tick_label: Label
var replay_button: Button
var exit_button: Button

var previous_ui_visibility: Dictionary = {}

# ============================================================
# EM6 TIMELINE
# ============================================================

var paused: bool = false

var timeline: Array[Dictionary] = []
var timeline_cursor: int = -1

var pause_button: Button
var step_back_button: Button
var step_forward_button: Button
var speed_selector: OptionButton
var timeline_slider: HSlider
var timeline_label: Label

var playback_speed: float = 1.0
var updating_timeline_ui: bool = false

# ============================================================
# READY
# ============================================================

func _ready() -> void:
	visible = false
	call_deferred("_setup_test_ui")


func _setup_test_ui() -> void:

	builder = get_parent() as Node2D
	grid = builder.get_node("Grid") as PuzzleGridBase
	ui_layer = builder.get_node("CanvasLayer") as CanvasLayer
	level_tools = builder.get_node("LevelTools")

	connection_layer = (
		builder.get_node("Connections") as BuilderConnections
	)

	var toolbar := (
		ui_layer.get_node_or_null("LevelToolbar") as PanelContainer
	)

	if toolbar == null:
		push_error("TestLevel: LevelToolbar not found")
		return

	var toolbar_column := toolbar.get_child(0) as VBoxContainer
	var toolbar_row := toolbar_column.get_child(0) as HBoxContainer

	test_button = Button.new()
	test_button.text = "▶ Test Level"
	test_button.pressed.connect(enter_test_mode)
	toolbar_row.add_child(test_button)

	test_bar = PanelContainer.new()
	test_bar.name = "TestLevelBar"
	ui_layer.add_child(test_bar)

	test_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	test_bar.offset_left = 12.0
	test_bar.offset_right = -12.0
	test_bar.offset_top = 10.0
	test_bar.offset_bottom = 125.0
	test_bar.z_index = 90

	var column := VBoxContainer.new()
	test_bar.add_child(column)

	var row := HBoxContainer.new()
	column.add_child(row)

	var heading := Label.new()
	heading.text = "TEST LEVEL"
	row.add_child(heading)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status_label)

	tick_label = Label.new()
	tick_label.text = "Tick: 0"
	row.add_child(tick_label)

	replay_button = Button.new()
	replay_button.text = "Replay"
	replay_button.pressed.connect(_replay)
	row.add_child(replay_button)

	exit_button = Button.new()
	exit_button.text = "Return to Builder"
	exit_button.pressed.connect(exit_test_mode)
	row.add_child(exit_button)

	var instructions := Label.new()
	instructions.text = (
		"Click a start node | Space: Pause | "
		+ "Left/Right: Step | Esc: Return"
	)
	column.add_child(instructions)

	# EM6 controls
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	column.add_child(controls)

	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.pressed.connect(_toggle_pause)
	controls.add_child(pause_button)

	step_back_button = Button.new()
	step_back_button.text = "◀ Step"
	step_back_button.pressed.connect(_step_back)
	controls.add_child(step_back_button)

	step_forward_button = Button.new()
	step_forward_button.text = "Step ▶"
	step_forward_button.pressed.connect(_step_forward)
	controls.add_child(step_forward_button)

	speed_selector = OptionButton.new()

	for speed_label in ["0.5×", "1×", "2×", "4×"]:
		speed_selector.add_item(speed_label)

	speed_selector.select(1)
	speed_selector.item_selected.connect(_on_speed_selected)
	controls.add_child(speed_selector)

	timeline_slider = HSlider.new()
	timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_slider.min_value = 0.0
	timeline_slider.max_value = 1.0
	timeline_slider.step = 1.0
	timeline_slider.value_changed.connect(_on_timeline_changed)
	controls.add_child(timeline_slider)

	timeline_label = Label.new()
	timeline_label.custom_minimum_size.x = 92.0
	timeline_label.text = "0 / 0"
	controls.add_child(timeline_label)

	_refresh_timeline_ui()
	test_bar.hide()

# ============================================================
# ENTER / EXIT
# ============================================================

func enter_test_mode() -> void:

	if test_mode or test_bar == null:
		return

	if level_tools.overlay != null and level_tools.overlay.visible:
		return

	builder.cancel_palette_drag()
	builder.dragging_node_id = ""
	builder.connection_start_id = ""
	builder.is_panning = false
	builder.select_node("")

	previous_ui_visibility.clear()

	for name in ["LevelToolbar", "NodePalette", "NodeInspector", "UI"]:

		var item := ui_layer.get_node_or_null(name) as Control

		if item != null:
			previous_ui_visibility[name] = item.visible
			item.hide()

	links = builder.connection_layer.connections.duplicate(true)

	test_mode = true
	visible = true
	test_bar.show()

	selected_start_id = ""
	_reset_run_state()


	if builder.nodes_by_id.is_empty():
		_set_status("No nodes placed.")
	elif _get_begin_node_id().is_empty():
		_set_status("A puzzle requires exactly one Begin Node.")
	elif targets_total == 0:
		_set_status("Add at least one Goal Target.")
	else:
		_set_status("Click the green Begin Node to launch.")


func exit_test_mode() -> void:

	if not test_mode:
		return

	_reset_run_state()

	for uid in builder.nodes_by_id.keys():
		var node: PuzzleNode = builder.nodes_by_id[uid]

		if is_instance_valid(node):
			node.clear_test_display()

	test_mode = false
	visible = false
	test_bar.hide()

	for name in previous_ui_visibility.keys():

		var item := (
			ui_layer.get_node_or_null(str(name)) as Control
		)

		if item != null:
			item.visible = bool(previous_ui_visibility[name])

	previous_ui_visibility.clear()
	builder.update_tool_label()

# ============================================================
# REGISTER GATES
# ============================================================

func _register_gate_nodes() -> void:

	gate_rules.configurations.clear()
	gate_rules.states.clear()
	gate_rules.unlocked_channels.clear()

	for key in builder.nodes_by_id.keys():

		var uid: String = str(key)
		var node: PuzzleNode = builder.nodes_by_id[uid]

		match node.kind:

			PuzzleNode.Kind.BLOCKER_SINGLE:
				gate_rules.register_node(
					uid,
					PulseGateRules.Mechanic.SINGLE_BLOCKER
				)

			PuzzleNode.Kind.BLOCKER_AMOUNT:
				gate_rules.register_node(
					uid,
					PulseGateRules.Mechanic.AMOUNT_BLOCKER,
					node.blocker_hits
				)

			PuzzleNode.Kind.BLOCKER_TARGET:
				gate_rules.register_node(
					uid,
					PulseGateRules.Mechanic.TARGET_BLOCKER,
					1,
					int(node.channel)
				)

			PuzzleNode.Kind.GATE_AMOUNT:
				gate_rules.register_node(
					uid,
					PulseGateRules.Mechanic.AMOUNT_GATE,
					node.gate_passes
				)

			PuzzleNode.Kind.TRIGGER_TARGET:
				gate_rules.register_node(
					uid,
					PulseGateRules.Mechanic.TRIGGER_TARGET,
					node.activation_cap,
					int(node.channel)
				)

	gate_rules.reset()
	gate_rules.begin_tick()


func _is_gate_rule_node(node: PuzzleNode) -> bool:

	return (
		node.kind == PuzzleNode.Kind.BLOCKER_SINGLE
		or node.kind == PuzzleNode.Kind.BLOCKER_AMOUNT
		or node.kind == PuzzleNode.Kind.BLOCKER_TARGET
		or node.kind == PuzzleNode.Kind.GATE_AMOUNT
		or node.kind == PuzzleNode.Kind.TRIGGER_TARGET
	)


func _sync_gate_visuals() -> void:

	for key in gate_rules.configurations.keys():

		var uid: String = str(key)

		if not builder.nodes_by_id.has(uid):
			continue

		var node: PuzzleNode = builder.nodes_by_id[uid]

		if node.kind != PuzzleNode.Kind.TRIGGER_TARGET:
			node.set_blocker_open(gate_rules.is_open(uid))

# ============================================================
# RESET AND REPLAY
# ============================================================

func _reset_run_state() -> void:

	running = false
	finished = false
	failure_reason = ""

	current_tick = 0
	tick_accumulator = 0.0

	paused = false
	timeline.clear()
	timeline_cursor = -1

	pulses.clear()
	delayed_pulses.clear()
	repeater_jobs.clear()
	node_states.clear()

	targets_total = 0
	targets_reached = 0

	if builder != null:

		for key in builder.nodes_by_id.keys():

			var uid: String = str(key)
			var node: PuzzleNode = builder.nodes_by_id[uid]

			if node.kind == PuzzleNode.Kind.TARGET:
				targets_total += 1

			node_states[uid] = {
				"activations": 0,
				"last_tick": -1000000,
				"reached": false,
				"cursor": 0,
				"broken": false
			}

			node.clear_test_display()
			node.set_test_display(true, 0, false)

		_register_gate_nodes()
		_sync_gate_visuals()

	if tick_label != null:
		tick_label.text = "Tick: 0"

	_refresh_timeline_ui()
	queue_redraw()


func _replay() -> void:

	if not test_mode:
		return

	var start_id: String = selected_start_id
	_reset_run_state()

	if (
		not start_id.is_empty()
		and builder.nodes_by_id.has(start_id)
		and targets_total > 0
	):
		_start_from(start_id)
	else:
		_set_status("Choose a starting node.")

# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:

	if not test_mode:
		return

	if event is InputEventKey:

		if event.pressed and not event.echo:

			if event.keycode == KEY_ESCAPE:
				exit_test_mode()
				get_viewport().set_input_as_handled()

			elif (
				event.keycode == KEY_SPACE
				and not selected_start_id.is_empty()
			):
				_toggle_pause()
				get_viewport().set_input_as_handled()

			elif event.keycode == KEY_LEFT and paused:
				_step_back()
				get_viewport().set_input_as_handled()

			elif event.keycode == KEY_RIGHT and paused:
				_step_forward()
				get_viewport().set_input_as_handled()

		return

	if event is InputEventMouseButton:

		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return

		if (
			event.position.y < 145.0
			or running
			or targets_total == 0
		):
			return

		var cell: Vector2i = grid.local_to_cell(
			grid.to_local(get_global_mouse_position())
		)

		if not grid.is_valid_cell(cell):
			return

		var uid: String = builder.get_id_at_cell(cell)

		if not uid.is_empty():
			_start_from(uid)
			get_viewport().set_input_as_handled()

# ============================================================
# START
# ============================================================


func _start_from(uid: String) -> void:

	if not test_mode:
		return

	var begin_id: String = _get_begin_node_id()

	if begin_id.is_empty() or uid != begin_id:
		_set_status("Signals can only start from Begin.")
		return

	if not builder.nodes_by_id.has(uid):
		return

	if targets_total == 0:
		_set_status("Add at least one Goal Target.")
		return

	_reset_run_state()
	selected_start_id = uid
	running = true

	# Begin receives one synthetic start event at tick 0.
	_activate_arrivals(uid, [
		{
			"from": "",
			"to": uid,
			"path": [],
			"returning": false
		}
	])

	if running:
		_check_completion()

	_save_snapshot()
	queue_redraw()

func _process(delta: float) -> void:

	if not test_mode:
		return

	if running and not paused:

		tick_accumulator += delta * playback_speed

		while (
			running
			and not paused
			and tick_accumulator >= tick_seconds
		):
			tick_accumulator -= tick_seconds
			_advance_tick()

		if running:
			_update_delay_charging()

	queue_redraw()


func _advance_tick() -> void:

	current_tick += 1
	tick_label.text = "Tick: %d" % current_tick

	if current_tick > MAX_TICKS:
		_finish(false, "Maximum duration reached.")
		_save_snapshot()
		return

	gate_rules.begin_tick()
	_sync_gate_visuals()

	var arriving: Dictionary = {}
	var travelling: Array[Dictionary] = []

	for pulse in pulses:

		if int(pulse["arrival_tick"]) <= current_tick:

			var uid: String = str(pulse["to"])

			if not arriving.has(uid):
				arriving[uid] = []

			arriving[uid].append(pulse)

		else:
			travelling.append(pulse)

	pulses = travelling

	var destinations: Array = arriving.keys()
	destinations.sort()

	for uid in destinations:

		if not running:
			break

		_activate_arrivals(str(uid), arriving[uid])

	if running:
		_release_due_delays()

	if running:
		_run_repeaters()

	_update_delay_visuals()

	if running:
		_check_completion()

	if running:
		_set_status(
			"Running | Goals %d/%d | Travelling %d | Held %d | Repeaters %d"
			% [
				targets_reached,
				targets_total,
				pulses.size(),
				_count_held_signals(),
				repeater_jobs.size()
			]
		)

	_save_snapshot()

# ============================================================
# NODE ACTIVATION
# ============================================================

func _activate_arrivals(uid: String, arrivals: Array) -> void:

	if (
		not builder.nodes_by_id.has(uid)
		or not node_states.has(uid)
	):
		_finish(false, "Pulse reached missing node.")
		return

	var count: int = arrivals.size()

	if count <= 0:
		return

	var node: PuzzleNode = builder.nodes_by_id[uid]
	var state: Dictionary = node_states[uid]

	# ====================================================
	# BEGIN NODE
	#
	# Only the synthetic tick-zero event may activate it.
	# Any pulse arriving later is absorbed.
	# ====================================================

	if node.kind == PuzzleNode.Kind.BEGIN:

		var is_initial_start: bool = (
			current_tick == 0
			and uid == selected_start_id
			and count == 1
			and str(arrivals[0].get("from", "")).is_empty()
		)

		if not is_initial_start:
			# Returning signals do not restart Begin.
			return

		state["activations"] = 1
		state["last_tick"] = current_tick

		node.set_test_display(true, 1, false)

		var options: Array[Dictionary] = _outgoing_links(uid)

		if options.is_empty():
			_finish(
				false,
				"Begin Node has no outgoing connection."
			)
			return

		# Exactly one initial signal.
		_dispatch_pulse(uid, options[0])
		return


	# DELAY
	if node.kind == PuzzleNode.Kind.DELAY:
		_store_delayed_pulses(uid, node, state, count)
		return

	# REPEATER
	if node.kind == PuzzleNode.Kind.REPEATER:
		_start_repeater(uid, node, state)
		return

	# ONE-WAY GATE
	if node.kind == PuzzleNode.Kind.ONE_WAY_GATE:
		_activate_one_way_gate(uid, node, state, arrivals)
		return

	# BOUNCE
	if node.kind == PuzzleNode.Kind.BOUNCE:

		state["activations"] = (
			int(state["activations"]) + count
		)
		state["last_tick"] = current_tick

		node.set_test_display(
			true,
			int(state["activations"]),
			false
		)

		for arrival in arrivals:

			var inbound_path: Array[Vector2i] = []

			for cell in arrival.get("path", []):
				inbound_path.append(cell)

			if (
				inbound_path.size() < 2
				or str(arrival.get("from", "")).is_empty()
			):
				continue

			inbound_path.reverse()

			_dispatch_path(
				uid,
				str(arrival["from"]),
				inbound_path,
				true
			)

			if not running:
				return

		return

	# GOAL TARGET
	if node.kind == PuzzleNode.Kind.TARGET:

		var new_hits: int = (
			int(state["activations"]) + count
		)

		if new_hits > node.activation_cap:

			_mark_node_broken(uid)
			_finish(
				false,
				"Goal Target %s overloaded: %d/%d hits."
				% [uid, new_hits, node.activation_cap]
			)
			return

		state["activations"] = new_hits
		state["last_tick"] = current_tick

		if (
			new_hits == node.activation_cap
			and not bool(state["reached"])
		):
			state["reached"] = true
			targets_reached += 1

		node.set_test_display(true, new_hits, false)
		return

	# BLOCKERS / GATES / TRIGGERS
	if _is_gate_rule_node(node):
		_activate_gate_rule_node(uid, node, state, count)
		return

	# SPLITTER
	if (
		node.kind == PuzzleNode.Kind.SPLITTER
		and count != node.required_inputs
	):

		_mark_node_broken(uid)
		_finish(
			false,
			"Splitter %s requires %d inputs, got %d."
			% [uid, node.required_inputs, count]
		)
		return

	# ACTIVATION LIMITS
	if not node.has_unlimited_activations():

		if int(state["activations"]) >= node.activation_cap:

			_mark_node_broken(uid)
			_finish(
				false,
				"Node %s exceeded its activation cap." % uid
			)
			return

		if (
			int(state["activations"]) > 0
			and current_tick - int(state["last_tick"])
				<= node.refractory_ticks
		):
			_mark_node_broken(uid)
			_finish(
				false,
				"Node %s is still refractory." % uid
			)
			return

	state["activations"] = int(state["activations"]) + 1
	state["last_tick"] = current_tick

	node.set_test_display(
		true,
		int(state["activations"]),
		false
	)

	var options: Array[Dictionary] = _outgoing_links(uid)

	if _all_returning_from_same_node(arrivals):

		var came_from: String = str(
			arrivals[0].get("from", "")
		)

		var filtered: Array[Dictionary] = []

		for option in options:
			if str(option["to"]) != came_from:
				filtered.append(option)

		options = filtered

	# Neutral dead end simply absorbs signal.
	if options.is_empty():

		if node.kind == PuzzleNode.Kind.NORMAL:
			return

		_finish(
			false,
			"Node %s has no outgoing connection." % uid
		)
		return

	if node.kind == PuzzleNode.Kind.SPLITTER:

		if options.size() < node.output_count:

			_finish(
				false,
				"Splitter %s needs %d exits, has %d."
				% [
					uid,
					node.output_count,
					options.size()
				]
			)
			return

		for index in range(node.output_count):

			_dispatch_pulse(uid, options[index])

			if not running:
				return

	elif node.kind == PuzzleNode.Kind.ALTERNATING:

		var cursor: int = int(state["cursor"])

		_dispatch_pulse(
			uid,
			options[cursor % options.size()]
		)

		state["cursor"] = cursor + 1

	else:
		_dispatch_pulse(uid, options[0])

# ============================================================
# ONE-WAY GATE
# ============================================================

func _gate_direction_vector(direction: int) -> Vector2i:

	match direction:

		PuzzleNode.Direction.NORTH:
			return Vector2i.UP

		PuzzleNode.Direction.EAST:
			return Vector2i.RIGHT

		PuzzleNode.Direction.SOUTH:
			return Vector2i.DOWN

		PuzzleNode.Direction.WEST:
			return Vector2i.LEFT

	return Vector2i.RIGHT


func _activate_one_way_gate(
	uid: String,
	node: PuzzleNode,
	state: Dictionary,
	arrivals: Array
) -> void:

	var forward: Vector2i = _gate_direction_vector(
		int(node.one_way_direction)
	)

	var accepted: int = 0

	for arrival in arrivals:

		var path: Array = arrival.get("path", [])

		if path.size() < 2:
			continue

		var difference: Vector2i = (
			path[path.size() - 1] - path[path.size() - 2]
		)

		var travel := Vector2i(
			signi(difference.x),
			signi(difference.y)
		)

		if travel == forward:
			accepted += 1

	if accepted <= 0:
		return

	state["activations"] = (
		int(state["activations"]) + accepted
	)

	state["last_tick"] = current_tick

	node.set_test_display(
		true,
		int(state["activations"]),
		false
	)

	for option in _outgoing_links(uid):

		var path: Array = option["path"]

		if path.size() < 2:
			continue

		var difference: Vector2i = (
			path[1] - path[0]
		)

		var travel := Vector2i(
			signi(difference.x),
			signi(difference.y)
		)

		if travel != forward:
			continue

		for i in range(accepted):

			_dispatch_pulse(uid, option)

			if not running:
				return

		return

	# No permitted forward exit: absorb safely.


func _all_returning_from_same_node(arrivals: Array) -> bool:

	if arrivals.is_empty():
		return false

	var incoming_uid: String = str(
		arrivals[0].get("from", "")
	)

	if incoming_uid.is_empty():
		return false

	for item in arrivals:

		if (
			not bool(item.get("returning", false))
			or str(item.get("from", "")) != incoming_uid
		):
			return false

	return true

# ============================================================
# REPEATER
# ============================================================

func _start_repeater(
	uid: String,
	node: PuzzleNode,
	state: Dictionary
) -> void:

	state["last_tick"] = current_tick

	if _find_repeater_job(uid) >= 0:
		return

	var options: Array[Dictionary] = _outgoing_links(uid)

	if options.is_empty():
		_finish(
			false,
			"Repeater %s has no outgoing connection." % uid
		)
		return

	repeater_jobs.append({
		"uid": uid,
		"remaining": node.repeat_count,
		"interval": node.repeat_interval,
		"next_tick": current_tick + node.repeat_interval
	})

	state["activations"] = int(state["activations"]) + 1

	node.set_test_display(
		true,
		int(state["activations"]),
		false
	)

	node.set_repeater_display(true, node.repeat_count)


func _find_repeater_job(uid: String) -> int:

	for i in range(repeater_jobs.size()):

		if str(repeater_jobs[i]["uid"]) == uid:
			return i

	return -1


func _run_repeaters() -> void:

	var remaining_jobs: Array[Dictionary] = []

	for job in repeater_jobs:

		if not running:
			return

		var uid: String = str(job["uid"])

		if not builder.nodes_by_id.has(uid):
			_finish(false, "Repeater no longer exists.")
			return

		var node: PuzzleNode = builder.nodes_by_id[uid]

		if int(job["next_tick"]) <= current_tick:

			var options: Array[Dictionary] = _outgoing_links(uid)

			if options.is_empty():

				_finish(
					false,
					"Repeater %s has no outgoing connection." % uid
				)
				return

			_dispatch_pulse(uid, options[0])

			if not running:
				return

			node.play_activation_animation()

			job["remaining"] = int(job["remaining"]) - 1

			job["next_tick"] = (
				current_tick + int(job["interval"])
			)

		if int(job["remaining"]) > 0:

			remaining_jobs.append(job)

			node.set_repeater_display(
				true,
				int(job["remaining"])
			)

		else:
			node.set_repeater_display(false, 0)

	repeater_jobs = remaining_jobs

# ============================================================
# DELAY COLLECTOR
# ============================================================

func _store_delayed_pulses(
	uid: String,
	node: PuzzleNode,
	state: Dictionary,
	arrival_count: int
) -> void:

	if (
		_count_held_signals()
		+ pulses.size()
		+ arrival_count
		> MAX_ACTIVE_PULSES
	):
		_finish(false, "Too many signals in simulation.")
		return

	var found: bool = false

	for i in range(delayed_pulses.size()):

		var batch: Dictionary = delayed_pulses[i]

		if str(batch["uid"]) != uid:
			continue

		batch["count"] = (
			int(batch["count"]) + arrival_count
		)

		delayed_pulses[i] = batch
		found = true
		break

	if not found:

		delayed_pulses.append({
			"uid": uid,
			"count": arrival_count,
			"release_tick": current_tick + node.delay_ticks
		})

	state["activations"] = (
		int(state["activations"]) + arrival_count
	)

	state["last_tick"] = current_tick

	node.set_test_display(
		true,
		int(state["activations"]),
		false
	)

	_update_delay_visuals()
	_update_delay_charging()


func _update_delay_charging() -> void:

	if not running:
		return

	for key in builder.nodes_by_id.keys():

		var uid: String = str(key)
		var node: PuzzleNode = builder.nodes_by_id[uid]

		if node.kind != PuzzleNode.Kind.DELAY:
			continue

		var progress: float = 0.0

		for batch in delayed_pulses:

			if str(batch["uid"]) != uid:
				continue

			if (
				int(batch["release_tick"]) - current_tick == 1
			):
				progress = clampf(
					tick_accumulator / tick_seconds,
					0.0,
					1.0
				)

			break

		node.set_delay_charge_progress(progress)


func _release_due_delays() -> void:

	var waiting: Array[Dictionary] = []
	var due: Array[Dictionary] = []

	for batch in delayed_pulses:

		if int(batch["release_tick"]) <= current_tick:
			due.append(batch)
		else:
			waiting.append(batch)

	delayed_pulses = waiting

	for batch in due:

		if not running:
			return

		var uid: String = str(batch["uid"])

		if not builder.nodes_by_id.has(uid):
			_finish(false, "Delay Node no longer exists.")
			return

		var node: PuzzleNode = builder.nodes_by_id[uid]
		var options: Array[Dictionary] = _outgoing_links(uid)

		if options.is_empty():

			_finish(
				false,
				"Delay Node %s has no outgoing connection." % uid
			)
			return

		node.play_delay_release_animation()

		for i in range(int(batch["count"])):

			_dispatch_pulse(uid, options[0])

			if not running:
				return


func _count_held_signals() -> int:

	var total: int = 0

	for batch in delayed_pulses:
		total += int(batch["count"])

	return total


func _update_delay_visuals() -> void:

	if builder == null:
		return

	for key in builder.nodes_by_id.keys():

		var uid: String = str(key)
		var node: PuzzleNode = builder.nodes_by_id[uid]

		if node.kind != PuzzleNode.Kind.DELAY:
			continue

		var held: int = 0
		var nearest: int = MAX_TICKS + 1000

		for batch in delayed_pulses:

			if str(batch["uid"]) != uid:
				continue

			held += int(batch["count"])
			nearest = mini(
				nearest,
				int(batch["release_tick"])
			)

		node.set_delay_display(
			held,
			maxi(0, nearest - current_tick) if held > 0 else 0
		)

# ============================================================
# BLOCKERS / GATES / TRIGGERS
# ============================================================

func _activate_gate_rule_node(
	uid: String,
	node: PuzzleNode,
	state: Dictionary,
	arrival_count: int
) -> void:

	if node.kind == PuzzleNode.Kind.TRIGGER_TARGET:

		if (
			gate_rules.get_count(uid) + arrival_count
			> node.activation_cap
		):
			_mark_node_broken(uid)

			_finish(
				false,
				"Trigger Target %s received too many pulses." % uid
			)
			return

	var result: Dictionary = gate_rules.process_arrivals(
		uid,
		arrival_count
	)

	var passed: int = int(result["passed"])
	var visual_count: int = gate_rules.get_count(uid)

	if node.kind == PuzzleNode.Kind.BLOCKER_TARGET:
		visual_count = (
			int(state["activations"]) + arrival_count
		)

	state["activations"] = visual_count
	state["last_tick"] = current_tick

	if node.kind == PuzzleNode.Kind.TRIGGER_TARGET:

		if bool(result["completed"]):
			state["reached"] = true

		node.set_test_display(
			true,
			visual_count,
			false
		)
		return

	node.set_test_display(true, visual_count, false)
	node.set_blocker_open(gate_rules.is_open(uid))

	if passed <= 0:
		return

	var options: Array[Dictionary] = _outgoing_links(uid)

	if options.is_empty():

		_finish(
			false,
			"%s passed pulses but has no outgoing connection." % uid
		)
		return

	for i in range(passed):

		_dispatch_pulse(uid, options[0])

		if not running:
			return


func _mark_node_broken(uid: String) -> void:

	if not node_states.has(uid):
		return

	var state: Dictionary = node_states[uid]
	state["broken"] = true

	var node: PuzzleNode = builder.nodes_by_id[uid]

	node.set_test_display(
		true,
		int(state["activations"]),
		true
	)

# ============================================================
# CONNECTION ROUTING
# ============================================================

func _outgoing_links(uid: String) -> Array[Dictionary]:

	var choices: Array[Dictionary] = []

	for connection in links:

		if str(connection["from_uid"]) != uid:
			continue

		var path: Array[Vector2i] = []

		for cell in connection["path"]:
			path.append(cell)

		if path.size() < 2:
			continue

		choices.append({
			"to": str(connection["to_uid"]),
			"path": path
		})

	choices.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:

			var ap: Array = a["path"]
			var bp: Array = b["path"]

			var ar: int = _direction_rank(ap[1] - ap[0])
			var br: int = _direction_rank(bp[1] - bp[0])

			return (
				str(a["to"]) < str(b["to"])
				if ar == br else ar < br
			)
	)

	return choices


func _direction_rank(direction: Vector2i) -> int:

	if direction.y < 0:
		return 0

	if direction.x > 0:
		return 1

	if direction.y > 0:
		return 2

	return 3


func _dispatch_pulse(
	from_uid: String,
	choice: Dictionary
) -> void:

	var path: Array[Vector2i] = choice["path"]

	_dispatch_path(
		from_uid,
		str(choice["to"]),
		path,
		false
	)


func _dispatch_path(
	from_uid: String,
	to_uid: String,
	path: Array[Vector2i],
	is_returning: bool
) -> void:

	if not running:
		return

	var length: int = _path_length(path)

	if length <= 0:

		_finish(false, "Invalid pulse route.")
		return

	if (
		pulses.size()
		+ _count_held_signals()
		+ _pending_repeater_emissions()
		>= MAX_ACTIVE_PULSES
	):
		_finish(false, "Too many active pulses.")
		return

	pulses.append({
		"from": from_uid,
		"to": to_uid,
		"path": path,
		"start_tick": current_tick,
		"arrival_tick": current_tick + length,
		"duration": length,
		"returning": is_returning
	})


func _pending_repeater_emissions() -> int:

	var total: int = 0

	for job in repeater_jobs:
		total += int(job["remaining"])

	return total


func _path_length(path: Array[Vector2i]) -> int:

	var length: int = 0

	for i in range(path.size() - 1):

		var difference: Vector2i = (
			path[i + 1] - path[i]
		)

		length += maxi(
			absi(difference.x),
			absi(difference.y)
		)

	return length

# ============================================================
# COMPLETION
# ============================================================

func _check_completion() -> void:

	if (
		not pulses.is_empty()
		or not delayed_pulses.is_empty()
		or not repeater_jobs.is_empty()
	):
		return

	if (
		targets_total > 0
		and targets_reached == targets_total
	):
		_finish(
			true,
			"All Goal Targets filled and all pulses resolved."
		)

	else:
		_finish(
			false,
			"No pulses remaining. Goal Targets: %d/%d."
			% [targets_reached, targets_total]
		)


func _finish(success: bool, reason: String) -> void:

	running = false
	finished = true
	failure_reason = reason

	# Keep final signals and node state available for timeline.

	if success:

		_set_status(
			"SUCCESS at tick %d! %s"
			% [current_tick, reason]
		)

	else:

		_set_status(
			"FAILED at tick %d: %s"
			% [current_tick, reason]
		)

	queue_redraw()


func _set_status(message: String) -> void:

	if status_label != null:
		status_label.text = message

# ============================================================
# DRAW
# ============================================================

func _draw() -> void:

	if not test_mode or grid == null:
		return

	_draw_node_rings()
	_draw_pulses()


func _draw_node_rings() -> void:

	for uid in node_states.keys():

		if not builder.nodes_by_id.has(uid):
			continue

		var node: PuzzleNode = builder.nodes_by_id[uid]
		var state: Dictionary = node_states[uid]
		var center: Vector2 = to_local(node.global_position)

		if bool(state["broken"]):

			draw_arc(
				center, 29.0, 0.0, TAU, 40,
				Color("#ff4545"), 4.0, true
			)

		elif bool(state["reached"]):

			var color: Color = (
				node.get_channel_color()
				if node.kind == PuzzleNode.Kind.TRIGGER_TARGET
				else TARGET_REACHED_COLOR
			)

			draw_arc(
				center, 29.0, 0.0, TAU, 40,
				color, 4.0, true
			)

		elif (
			_is_gate_rule_node(node)
			or node.kind == PuzzleNode.Kind.DELAY
			or node.kind == PuzzleNode.Kind.REPEATER
			or node.kind == PuzzleNode.Kind.BOUNCE
		):
			continue

		elif int(state["activations"]) > 0:

			var elapsed: int = (
				current_tick - int(state["last_tick"])
			)

			var color: Color = (
				PULSE_COLOR
				if elapsed <= 0
				else REFRACTORY_COLOR
			)

			if (
				node.has_unlimited_activations()
				or elapsed > node.refractory_ticks
			):
				color = Color("#64748b")

			draw_arc(
				center, 28.0, 0.0, TAU, 40,
				color, 3.0, true
			)

# ============================================================
# SIGNAL TRAILS
# ============================================================

func _draw_pulses() -> void:

	var fractional_tick: float = (
		tick_accumulator / tick_seconds
		if running and not paused
		else 0.0
	)

	var overlap_counts: Dictionary = {}

	for pulse in pulses:

		var key: String = _pulse_overlap_key(pulse)

		overlap_counts[key] = (
			int(overlap_counts.get(key, 0)) + 1
		)

	var drawn_counts: Dictionary = {}

	for pulse in pulses:

		var key: String = _pulse_overlap_key(pulse)
		var group_size: int = int(overlap_counts.get(key, 1))
		var lane: int = int(drawn_counts.get(key, 0))

		drawn_counts[key] = lane + 1

		var elapsed: float = (
			float(current_tick - int(pulse["start_tick"]))
			+ fractional_tick
		)

		var distance: float = clampf(
			elapsed,
			0.0,
			float(pulse["duration"])
		)

		if (
			trail_length_cells > 0.0
			and trail_opacity > 0.0
		):

			for sample in range(trail_samples, 0, -1):

				var behind: float = (
					trail_length_cells
					* float(sample)
					/ float(trail_samples)
				)

				var distance_behind: float = (
					distance - behind
				)

				if distance_behind < 0.0:
					continue

				var trail_visual: Dictionary = (
					_pulse_visual_data(
						pulse,
						distance_behind,
						elapsed - behind,
						lane,
						group_size
					)
				)

				var trail_color: Color = (
					trail_visual["color"]
				)

				var strength: float = (
					1.0
					- float(sample)
					/ float(trail_samples + 1)
				)

				trail_color.a = (
					trail_opacity * strength * strength
				)

				var trail_radius: float = (
					float(trail_visual["radius"])
					* (0.2 + 0.65 * strength)
				)

				var trail_center: Vector2 = to_local(
					grid.to_global(trail_visual["position"])
				)

				draw_circle(
					trail_center,
					trail_radius,
					trail_color
				)

		var visual: Dictionary = _pulse_visual_data(
			pulse,
			distance,
			elapsed,
			lane,
			group_size
		)

		var center: Vector2 = to_local(
			grid.to_global(visual["position"])
		)

		var radius: float = float(visual["radius"])

		draw_circle(center, radius, visual["color"])

		draw_arc(
			center,
			radius + 2.0,
			0.0,
			TAU,
			24,
			Color.WHITE,
			1.4,
			true
		)


func _pulse_visual_data(
	pulse: Dictionary,
	distance: float,
	elapsed: float,
	lane: int,
	group_size: int
) -> Dictionary:

	var path: Array[Vector2i] = pulse["path"]

	var position: Vector2 = (
		connection_layer.get_visual_point(path, distance)
	)

	var color: Color = PULSE_COLOR
	var radius: float = base_pulse_radius

	if group_size > 1:

		var phase: float = (
			TAU * distance / maxf(wavelength_cells, 0.01)
			+ TAU * elapsed * rotation_speed
		)

		var pair_index: int = lane / 2

		var orbit_angle: float = (
			phase
			+ float(lane % 2) * PI
			+ float(pair_index) * PI / 4.0
		)

		var normal: Vector2 = (
			_tangent_on_path(path, distance)
			.orthogonal().normalized()
		)

		var fraction: float = clampf(
			distance / maxf(float(pulse["duration"]), 1.0),
			0.0,
			1.0
		)

		var fade: float = sin(PI * fraction)

		position += (
			normal
			* sin(orbit_angle)
			* wave_amplitude
			* fade
		)

		radius = maxf(
			2.5,
			base_pulse_radius
			+ cos(orbit_angle) * size_variation * fade
		)

		if lane % 2 == 1:
			color = SECOND_PULSE_COLOR

	return {
		"position": position,
		"color": color,
		"radius": radius
	}


func _pulse_overlap_key(pulse: Dictionary) -> String:

	return "%s|%s|%d|%s" % [
		str(pulse["from"]),
		str(pulse["to"]),
		int(pulse["start_tick"]),
		str(pulse.get("returning", false))
	]


func _tangent_on_path(
	path: Array[Vector2i],
	distance_cells: float
) -> Vector2:

	var total: float = float(_path_length(path))

	var before: float = maxf(
		0.0,
		distance_cells - 0.04
	)

	var after: float = minf(
		total,
		distance_cells + 0.04
	)

	var p0: Vector2 = connection_layer.get_visual_point(
		path,
		before
	)

	var p1: Vector2 = connection_layer.get_visual_point(
		path,
		after
	)

	var direction: Vector2 = p1 - p0

	return (
		direction.normalized()
		if direction.length_squared() > 0.0001
		else Vector2.RIGHT
	)

# ============================================================
# EM6 SIMULATION CONTROLS
# ============================================================

func _on_speed_selected(index: int) -> void:

	match index:

		0:
			playback_speed = 0.5

		1:
			playback_speed = 1.0

		2:
			playback_speed = 2.0

		3:
			playback_speed = 4.0


func _toggle_pause() -> void:

	if selected_start_id.is_empty() or not test_mode:
		return

	if (
		finished
		and timeline_cursor == timeline.size() - 1
	):
		return

	paused = not paused
	tick_accumulator = 0.0

	_refresh_timeline_ui()


func _step_back() -> void:

	if timeline_cursor <= 0:
		return

	_restore_snapshot(timeline_cursor - 1)


func _step_forward() -> void:

	if selected_start_id.is_empty():
		return

	paused = true
	tick_accumulator = 0.0

	if timeline_cursor + 1 < timeline.size():

		_restore_snapshot(timeline_cursor + 1)

	elif running and not finished:

		_advance_tick()

	_refresh_timeline_ui()


func _on_timeline_changed(value: float) -> void:

	if updating_timeline_ui or timeline.is_empty():
		return

	_restore_snapshot(int(round(value)))


func _refresh_timeline_ui() -> void:

	if timeline_slider == null:
		return

	updating_timeline_ui = true

	timeline_slider.max_value = float(
		maxi(1, timeline.size() - 1)
	)

	timeline_slider.value = float(
		maxi(0, timeline_cursor)
	)

	updating_timeline_ui = false

	timeline_label.text = "%d / %d" % [
		maxi(0, timeline_cursor),
		maxi(0, timeline.size() - 1)
	]

	pause_button.text = (
		"Resume" if paused else "Pause"
	)

	pause_button.disabled = (
		selected_start_id.is_empty()
		or (
			finished
			and timeline_cursor == timeline.size() - 1
		)
	)

	step_back_button.disabled = timeline_cursor <= 0

	step_forward_button.disabled = (
		selected_start_id.is_empty()
		or (
			finished
			and timeline_cursor >= timeline.size() - 1
		)
	)

# ============================================================
# TIMELINE SNAPSHOTS
# ============================================================

func _save_snapshot() -> void:

	if timeline_cursor + 1 < timeline.size():
		timeline.resize(timeline_cursor + 1)

	var snapshot: Dictionary = {
		"tick": current_tick,
		"running": running,
		"finished": finished,
		"failure_reason": failure_reason,
		"status": (
			status_label.text
			if status_label != null
			else ""
		),
		"pulses": pulses.duplicate(true),
		"delayed_pulses": delayed_pulses.duplicate(true),
		"repeater_jobs": repeater_jobs.duplicate(true),
		"node_states": node_states.duplicate(true),
		"targets_reached": targets_reached,
		"gate_states": gate_rules.states.duplicate(true),
		"gate_channels": (
			gate_rules.unlocked_channels.duplicate(true)
		)
	}

	timeline.append(snapshot)
	timeline_cursor = timeline.size() - 1

	_refresh_timeline_ui()


func _restore_snapshot(index: int) -> void:

	if index < 0 or index >= timeline.size():
		return

	var snapshot: Dictionary = timeline[index]

	current_tick = int(snapshot["tick"])
	running = bool(snapshot["running"])
	finished = bool(snapshot["finished"])
	failure_reason = str(snapshot["failure_reason"])

	pulses.assign(
		snapshot["pulses"].duplicate(true)
	)

	delayed_pulses.assign(
		snapshot["delayed_pulses"].duplicate(true)
	)

	repeater_jobs.assign(
		snapshot["repeater_jobs"].duplicate(true)
	)

	node_states = snapshot["node_states"].duplicate(true)

	targets_reached = int(snapshot["targets_reached"])

	gate_rules.states = (
		snapshot["gate_states"].duplicate(true)
	)

	gate_rules.unlocked_channels = (
		snapshot["gate_channels"].duplicate(true)
	)

	timeline_cursor = index
	paused = true
	tick_accumulator = 0.0

	tick_label.text = "Tick: %d" % current_tick
	_set_status(str(snapshot["status"]))

	_refresh_snapshot_node_visuals()
	_refresh_timeline_ui()
	queue_redraw()


func _refresh_snapshot_node_visuals() -> void:

	for key in builder.nodes_by_id.keys():

		var uid: String = str(key)
		var node: PuzzleNode = builder.nodes_by_id[uid]
		var state: Dictionary = node_states[uid]

		# Restore counter state without activation wobble.
		node.clear_test_display()

		node.set_test_display(
			true,
			int(state["activations"]),
			bool(state["broken"])
		)

		node.pop_time_remaining = 0.0
		node.scale = Vector2.ONE
		node.rotation = node.resting_rotation

		if node.kind == PuzzleNode.Kind.REPEATER:

			var remaining: int = 0

			for job in repeater_jobs:

				if str(job["uid"]) == uid:
					remaining = int(job["remaining"])
					break

			node.set_repeater_display(
				remaining > 0,
				remaining
			)

	_sync_gate_visuals()
	_update_delay_visuals()



func _get_begin_node_id() -> String:
	var begin_id: String = ""

	for key in builder.nodes_by_id.keys():
		var node: PuzzleNode = builder.nodes_by_id[key]

		if node.kind != PuzzleNode.Kind.BEGIN:
			continue

		if not begin_id.is_empty():
			return ""

		begin_id = str(key)

	return begin_id
