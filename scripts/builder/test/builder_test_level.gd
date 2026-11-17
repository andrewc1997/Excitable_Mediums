extends Node2D

const PortRules = preload("res://scripts/puzzle_node/puzzle_port_rules.gd")

# Legacy levels keep the directed rules. New levels may opt into
# returning along authored bridges, without duplicating any geometry.
var allow_reverse_connections: bool = false
# Per-bridge travel rule. 0 normal, 1 authored direction only,
# 2 reverse direction only, 3 one crossing then die, 4 closed,
# 5 player-drop blocker slot.
var bridge_modes: Dictionary = {}
var reserved_one_shots: Dictionary = {}
var spent_one_shots: Dictionary = {}
var player_blocked_bridges: Dictionary = {}

# ============================================================
# EXCITABLE MEDIUMS - EM9 PLAYTEST
# Godot 4.3
#
# - Begin-only launching
# - Configurable N-input / M-output splitters
# - Node failures do not stop other branches
# - Final result after all activity resolves
# - Delay and Repeater scheduling
# - Bounce along exact incoming route
# - One-Way Gate
# - Timeline, stepping, pause, playback speed
# - Rounded-path pulse animation and trails
# ============================================================

@export_category("Simulation Speed")

@export_range(0.08, 0.80, 0.01)
var tick_seconds: float = 0.22

const MAX_TICKS: int = 2000
const MAX_ACTIVE_PULSES: int = 5000

@export_category("Playtest Appearance")
@export var show_node_state_rings: bool = false

const PULSE_COLOR: Color = Color("#49d9ed")
const SECOND_PULSE_COLOR: Color = Color("#b4efff")
const TARGET_REACHED_COLOR: Color = Color("#49db86")
const REFRACTORY_COLOR: Color = Color("#9763c7")

@export_category("Overlapping Signals")

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
# REFERENCES AND STATE
# ============================================================

var builder: Node2D
var grid: PuzzleGridBase
var ui_layer: CanvasLayer
var level_tools: Node
var connection_layer: BuilderConnections

var gate_rules: PulseGateRules = PulseGateRules.new()

var test_mode: bool = false
var running: bool = false
var finished: bool = false
var paused: bool = false

var current_tick: int = 0
var tick_accumulator: float = 0.0
var playback_speed: float = 1.0

var selected_start_id: String = ""
var failure_reason: String = ""

var node_failures: Array[String] = []

var pulses: Array[Dictionary] = []
var links: Array[Dictionary] = []
var node_states: Dictionary = {}
var delayed_pulses: Array[Dictionary] = []
var repeater_jobs: Array[Dictionary] = []
# One-tick virtual transfer: never traverses a drawn bridge.
var wormhole_jobs: Array[Dictionary] = []

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

var pause_button: Button
var step_back_button: Button
var step_forward_button: Button
var speed_selector: OptionButton
var timeline_slider: HSlider
var timeline_label: Label

var previous_ui_visibility: Dictionary = {}
var previous_grid_visibility: bool = true

var timeline: Array[Dictionary] = []
var timeline_cursor: int = -1
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
		builder.get_node("Connections")
		as BuilderConnections
	)

	var toolbar := (
		ui_layer.get_node_or_null("LevelToolbar")
		as PanelContainer
	)

	if toolbar == null:
		push_error("TestLevel: LevelToolbar not found.")
		return

	var toolbar_column := (
		toolbar.get_child(0) as VBoxContainer
	)

	var toolbar_row := (
		toolbar_column.get_child(0) as HBoxContainer
	)

	test_button = Button.new()
	test_button.text = "▶ Test Level"
	test_button.pressed.connect(enter_test_mode)
	toolbar_row.add_child(test_button)

	test_bar = PanelContainer.new()
	test_bar.name = "TestLevelBar"

	ui_layer.add_child(test_bar)

	test_bar.set_anchors_preset(
		Control.PRESET_TOP_WIDE
	)

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
	status_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
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
		"Click Begin | Space: Pause | "
		+ "Left/Right: Step | Esc: Return"
	)
	column.add_child(instructions)

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

	for label in ["0.5×", "1×", "2×", "4×"]:
		speed_selector.add_item(label)

	speed_selector.select(1)
	speed_selector.item_selected.connect(_on_speed_selected)
	controls.add_child(speed_selector)

	timeline_slider = HSlider.new()
	timeline_slider.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	timeline_slider.min_value = 0.0
	timeline_slider.max_value = 1.0
	timeline_slider.step = 1.0
	timeline_slider.value_changed.connect(
		_on_timeline_changed
	)
	controls.add_child(timeline_slider)

	timeline_label = Label.new()
	timeline_label.custom_minimum_size.x = 92.0
	timeline_label.text = "0 / 0"
	controls.add_child(timeline_label)

	_refresh_timeline_ui()
	test_bar.hide()


# ============================================================
# TEST MODE
# ============================================================

func enter_test_mode() -> void:
	if level_tools != null:
		allow_reverse_connections = bool(level_tools.get("allow_reverse_travel"))
		bridge_modes = level_tools.get("bridge_modes").duplicate(true)

	if test_mode or test_bar == null:
		return

	if (
		level_tools.overlay != null
		and level_tools.overlay.visible
	):
		return

	builder.cancel_palette_drag()

	builder.dragging_node_id = ""
	builder.connection_start_id = ""
	builder.is_panning = false
	builder.select_node("")

	previous_ui_visibility.clear()

	# The grid shows every possible honeycomb edge during editing.
	# In playtest we only draw actual BuilderConnections.
	# Hiding Grid does not disable its coordinate/routing methods.
	previous_grid_visibility = grid.visible
	grid.hide()

	for name in [
		"LevelToolbar",
		"NodePalette",
		"NodeInspector",
		"UI"
	]:

		var item := (
			ui_layer.get_node_or_null(name)
			as Control
		)

		if item != null:
			previous_ui_visibility[name] = item.visible
			item.hide()

	links = (
		builder.connection_layer.connections.duplicate(true)
	)

	test_mode = true
	visible = true
	test_bar.show()

	selected_start_id = ""
	_reset_run_state()

	if builder.nodes_by_id.is_empty():
		_set_status("No nodes placed.")
	elif not _has_begin_nodes():
		_set_status("Place at least one Begin Node.")
	elif targets_total == 0:
		_set_status("Add at least one Goal Target.")
	else:
		_set_status("Click any Begin Node to launch from that start.")


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

	# Restore the Builder's full grid when editing resumes.
	grid.visible = previous_grid_visibility

	for name in previous_ui_visibility.keys():

		var item := (
			ui_layer.get_node_or_null(str(name))
			as Control
		)

		if item != null:
			item.visible = bool(
				previous_ui_visibility[name]
			)

	previous_ui_visibility.clear()
	builder.update_tool_label()


# ============================================================
# GATE SETUP
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
			node.set_blocker_open(
				gate_rules.is_open(uid)
			)


# ============================================================
# RESET
# ============================================================

func _reset_run_state() -> void:

	running = false
	finished = false
	paused = false

	failure_reason = ""
	node_failures.clear()

	current_tick = 0
	tick_accumulator = 0.0

	timeline.clear()
	timeline_cursor = -1

	pulses.clear()
	reserved_one_shots.clear()
	spent_one_shots.clear()
	player_blocked_bridges.clear()
	_refresh_bridge_visuals()
	delayed_pulses.clear()
	repeater_jobs.clear()
	wormhole_jobs.clear()
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
				"incoming_heading": Vector2.ZERO,
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
		_set_status("Click a Begin Node to choose your starting point.")


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:

	if not test_mode:
		return

	if event is InputEventKey:

		if not event.pressed or event.echo:
			return

		match event.keycode:

			KEY_ESCAPE:
				exit_test_mode()
				get_viewport().set_input_as_handled()

			KEY_SPACE:
				if not selected_start_id.is_empty():
					_toggle_pause()
					get_viewport().set_input_as_handled()

			KEY_LEFT:
				if paused:
					_step_back()
					get_viewport().set_input_as_handled()

			KEY_RIGHT:
				if paused:
					_step_forward()
					get_viewport().set_input_as_handled()

		return

	if event is InputEventMouseButton:

		if (
			not event.pressed
			or event.button_index != MOUSE_BUTTON_LEFT
		):
			return

		if event.position.y < 145.0:
			return

		if running or targets_total == 0:
			return

		var cell: Vector2i = grid.local_to_cell(
			grid.to_local(
				get_global_mouse_position()
			)
		)

		if not grid.is_valid_cell(cell):
			return

		var uid: String = builder.get_id_at_cell(cell)

		if _is_begin_node_id(uid):
			_start_from(uid)
			get_viewport().set_input_as_handled()


# ============================================================
# BEGIN NODE
# ============================================================

func _has_begin_nodes() -> bool:
	for key in builder.nodes_by_id.keys():
		if _is_begin_node_id(str(key)):
			return true
	return false


func _is_begin_node_id(uid: String) -> bool:
	if uid.is_empty() or not builder.nodes_by_id.has(uid):
		return false
	var node: PuzzleNode = builder.nodes_by_id[uid]
	return node.kind == PuzzleNode.Kind.BEGIN


func _start_from(uid: String) -> void:

	if not _is_begin_node_id(uid):
		_set_status("Only Begin can launch signals.")
		return

	# Keep player-placed blockers when Begin is first launched.
	# Retry and Reset still clear them via _reset_run_state().
	var preplaced_blockers: Dictionary = player_blocked_bridges.duplicate(true)
	_reset_run_state()
	player_blocked_bridges = preplaced_blockers
	_refresh_bridge_visuals()
	selected_start_id = uid

	if targets_total == 0 or not node_states.has(uid):
		return

	running = true

	_activate_arrivals(uid, [{
		"from": "",
		"to": uid,
		"path": [],
		"returning": false
	}])

	if running:
		_check_completion()

	_save_snapshot()
	queue_redraw()


# ============================================================
# PROCESS AND TICKS
# ============================================================

func _process(delta: float) -> void:

	if not test_mode:
		return

	if running and not paused:

		tick_accumulator += (
			delta * playback_speed
		)

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

			# A one-shot bridge disappears only AFTER the travelling
			# signal arrives at its destination.
			_on_pulse_arrived_over_bridge(pulse)
			var uid: String = str(pulse["to"])

			if not arriving.has(uid):
				arriving[uid] = []

			arriving[uid].append(pulse)

		else:
			travelling.append(pulse)

	pulses = travelling

	# All simultaneous arrivals are grouped
	# before any nodes are processed.
	var destinations: Array = arriving.keys()
	destinations.sort()

	for uid in destinations:

		if not running:
			break

		_activate_arrivals(
			str(uid),
			arriving[uid]
		)

	if running:
		_release_due_wormholes()

	if running:
		_release_due_delays()

	if running:
		_run_repeaters()

	_update_delay_visuals()

	if running:
		_check_completion()

	if running:
		var message: String = (
			"Running | Goals %d/%d | Pulses %d | Held %d | Repeaters %d | Issues %d"
			% [
				targets_reached,
				targets_total,
				pulses.size(),
				_count_held_signals(),
				repeater_jobs.size(),
				node_failures.size()
			]
		)
		_set_status(message)

	_save_snapshot()


# ============================================================
# NODE ACTIVATION
# ============================================================


func _activate_wormhole(
	uid: String, node: PuzzleNode, state: Dictionary, arrivals: Array
) -> void:
	var partner_uid: String = node.wormhole_pair_uid
	if (partner_uid.is_empty() or partner_uid == uid
		or not builder.nodes_by_id.has(partner_uid)):
		_record_node_failure(uid, "Wormhole partner is missing")
		return
	var partner: PuzzleNode = builder.nodes_by_id[partner_uid]
	if partner.kind != PuzzleNode.Kind.WORMHOLE or partner.wormhole_pair_uid != uid:
		_record_node_failure(uid, "Wormhole partner must link back")
		return
	state["activations"] = int(state["activations"]) + arrivals.size()
	state["last_tick"] = current_tick
	node.set_test_display(true, int(state["activations"]), false)
	node.flash_wormhole()
	for arrival in arrivals:
		# Keep the entrance direction so a multi-exit partner favours
		# continuing forward, not a random connection order.
		var heading: Vector2 = _get_incoming_heading([arrival])
		wormhole_jobs.append({
			"from": uid,
			"to": partner_uid,
			"heading": heading,
			"due_tick": current_tick + 1
		})


func _release_due_wormholes() -> void:
	var pending: Array[Dictionary] = []
	var due: Array[Dictionary] = []
	for job in wormhole_jobs:
		if int(job["due_tick"]) <= current_tick:
			due.append(job)
		else:
			pending.append(job)
	wormhole_jobs = pending
	for job in due:
		if not running:
			return
		var destination: String = str(job["to"])
		if not builder.nodes_by_id.has(destination) or not node_states.has(destination):
			_finish(false, "Wormhole exit is missing")
			return
		var node: PuzzleNode = builder.nodes_by_id[destination]
		var state: Dictionary = node_states[destination]
		if bool(state.get("broken", false)):
			continue
		state["activations"] = int(state["activations"]) + 1
		state["last_tick"] = current_tick
		state["incoming_from"] = str(job["from"])
		state["incoming_heading"] = job["heading"]
		node.set_test_display(true, int(state["activations"]), false)
		node.flash_wormhole()
		# Each entrance pulse produces exactly one exit pulse. All
		# ordinary bridge rules (directional, single-use, blocked) apply.
		var options: Array[Dictionary] = _prefer_forward_links(
			destination, job["heading"]
		)
		if options.is_empty():
			_record_node_failure(destination, "Wormhole exit has no open bridge")
			continue
		_dispatch_pulse(destination, options[0])


func _activate_arrivals(
	uid: String,
	arrivals: Array
) -> void:

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
	# Used to avoid accidental U-turns at ordinary junctions.
	state["incoming_from"] = (
		str(arrivals[0].get("from", "")) if count == 1 else ""
	)

	var arrival_heading: Vector2 = (
		_get_incoming_heading(arrivals)
	)

	if arrival_heading.length_squared() > 0.001:
		state["incoming_heading"] = arrival_heading

	if bool(state.get("broken", false)):
		return

	# Wormholes schedule a one-tick virtual transfer to their partner.
	# Arrival at the partner is an EXIT, not another wormhole entry.
	if node.kind == PuzzleNode.Kind.WORMHOLE:
		_activate_wormhole(uid, node, state, arrivals)
		return

	# Alternators process each pulse independently, including
	# arrivals at different ticks or several on the same tick.
	# Do this before generic cap/refractory logic.
	if node.kind == PuzzleNode.Kind.ALTERNATING:
		_activate_alternating(uid, node, state, arrivals)
		return

	# ====================================================
	# BEGIN
	# ====================================================

	if node.kind == PuzzleNode.Kind.BEGIN:

		var initial: bool = (
			uid == selected_start_id
			and current_tick == 0
			and count == 1
			and str(
				arrivals[0].get("from", "")
			).is_empty()
		)

		if not initial:
			return

		state["activations"] = 1
		state["last_tick"] = current_tick

		node.set_test_display(true, 1, false)

		var exits: Array[Dictionary] = (
			_outgoing_links(uid)
		)

		if exits.is_empty():
			_record_node_failure(
				uid,
				"Begin has no outgoing connection"
			)
			return

		_dispatch_pulse(uid, exits[0])
		return

	# ====================================================
	# DELAY
	# ====================================================

	if node.kind == PuzzleNode.Kind.DELAY:

		_store_delayed_pulses(
			uid,
			node,
			state,
			count
		)
		return

	# ====================================================
	# REPEATER
	# ====================================================

	if node.kind == PuzzleNode.Kind.REPEATER:

		_start_repeater(uid, node, state)
		return

	# ====================================================
	# ONE-WAY GATE
	# ====================================================

	if node.kind == PuzzleNode.Kind.ONE_WAY_GATE:

		_activate_one_way_gate(
			uid,
			node,
			state,
			arrivals
		)
		return

	# ====================================================
	# BOUNCE
	# ====================================================

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
				or str(
					arrival.get("from", "")
				).is_empty()
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

	# ====================================================
	# GOAL TARGET
	# ====================================================

	if node.kind == PuzzleNode.Kind.TARGET:

		var new_hits: int = (
			int(state["activations"]) + count
		)

		if new_hits > node.activation_cap:

			if bool(state["reached"]):

				state["reached"] = false

				targets_reached = maxi(
					0,
					targets_reached - 1
				)

			_record_node_failure(
				uid,
				"Goal Target overloaded: %d/%d hits"
				% [new_hits, node.activation_cap]
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

		node.set_test_display(
			true,
			new_hits,
			false
		)

		return

	# ====================================================
	# BLOCKERS AND GATES
	# ====================================================

	if _is_gate_rule_node(node):

		_activate_gate_rule_node(
			uid,
			node,
			state,
			count
		)
		return

	# ====================================================
	# SPLITTER INPUT REQUIREMENTS
	# ====================================================

	if node.kind == PuzzleNode.Kind.SPLITTER:

		if node.player_editable and allow_reverse_connections:
			var input_rotor: Dictionary = PortRules.get_rotor(
				uid, links, builder.nodes_by_id, grid,
				int(node.port_rotation_steps), true
			)
			if bool(input_rotor.get("valid", false)):
				var permitted_source: String = str(input_rotor["input"]["to"])
				for pulse in arrivals:
					if str(pulse.get("from", "")) != permitted_source:
						_record_node_failure(uid, "Splitter received signal at its output port")
						return

		if count != node.required_inputs:

			_record_node_failure(
				uid,
				"Splitter requires %d inputs, received %d"
				% [node.required_inputs, count]
			)
			return


	# ====================================================
	# ACTIVATION CAP AND REFRACTORY
	# ====================================================

	if not node.has_unlimited_activations():

		if (
			int(state["activations"])
			>= node.activation_cap
		):

			_record_node_failure(
				uid,
				"Activation cap exceeded"
			)
			return

		if (
			int(state["activations"]) > 0
			and current_tick - int(state["last_tick"])
				<= node.refractory_ticks
		):

			_record_node_failure(
				uid,
				"Node still refractory"
			)
			return

	# ====================================================
	# ACTIVATE
	# ====================================================

	state["activations"] = (
		int(state["activations"]) + 1
	)

	state["last_tick"] = current_tick

	node.set_test_display(
		true,
		int(state["activations"]),
		false
	)

	# ====================================================
	# SELECT OUTPUT OPTIONS
	#
	# Alternating nodes must have a fixed ordering.
	# Ordinary nodes still favour continuing forward.
	# ====================================================

	var options: Array[Dictionary] = []

	if node.kind == PuzzleNode.Kind.ALTERNATING:

		options = _outgoing_links(uid)

	else:

		options = _prefer_forward_links(
			uid,
			arrival_heading
		)

	# A player-rotated Splitter chooses the other two *physical*
	# bridges, including reverse directions when two-way is enabled.
	if node.kind == PuzzleNode.Kind.SPLITTER and allow_reverse_connections and node.player_editable:
		var rotor_outputs: Dictionary = PortRules.get_rotor(
			uid, links, builder.nodes_by_id, grid,
			int(node.port_rotation_steps), true
		)
		if not bool(rotor_outputs.get("valid", false)):
			_record_node_failure(uid, "Rotating Splitter needs at least three attached bridges")
			return
		options.clear()
		for choice in rotor_outputs["outputs"]:
			options.append(choice)

	# ====================================================
	# FILTER RETURNING BOUNCE SIGNALS
	# ====================================================

	if _all_returning_from_same_node(arrivals):

		var came_from: String = str(
			arrivals[0].get("from", "")
		)

		var filtered: Array[Dictionary] = []

		for option in options:

			if str(option["to"]) != came_from:
				filtered.append(option)

		options = filtered

	# ====================================================
	# NO EXITS
	# ====================================================

	if options.is_empty():

		if node.kind == PuzzleNode.Kind.NORMAL:
			return

		_record_node_failure(
			uid,
			"No outgoing connection"
		)
		return

	# ====================================================
	# SPLITTER
	# ====================================================

	if node.kind == PuzzleNode.Kind.SPLITTER:

		if options.size() < node.output_count:

			_record_node_failure(
				uid,
				"Splitter needs %d exits, has %d"
				% [
					node.output_count,
					options.size()
				]
			)
			return

		for index in range(node.output_count):

			if not _bridge_can_traverse(uid, str(options[index]["to"])):
				_record_node_failure(uid, "Splitter output is blocked by bridge rule")
				return
			_dispatch_pulse(
				uid,
				options[index]
			)

			if not running:
				return

		return

	# ====================================================
	# ALTERNATING
	#
	# One arriving pulse = one output.
	#
	# First arrival: exit 0
	# Second arrival: exit 1
	# Third arrival: exit 0
	#
	# Two simultaneous arrivals advance twice.
	# ====================================================

	if node.kind == PuzzleNode.Kind.ALTERNATING:

		var cursor: int = int(state["cursor"])

		for arrival_index in range(count):

			var exit_index: int = (
				cursor % options.size()
			)

			_dispatch_pulse(
				uid,
				options[exit_index]
			)

			if not running:
				return

			cursor += 1

		state["cursor"] = cursor
		return

	# ====================================================
	# NORMAL NODE
	# ====================================================

	_dispatch_pulse(uid, options[0])


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

		var delta: Vector2i = (
			path[path.size() - 1]
			- path[path.size() - 2]
		)

		var direction := Vector2i(
			signi(delta.x),
			signi(delta.y)
		)

		if direction == forward:
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

		var delta: Vector2i = path[1] - path[0]

		var direction := Vector2i(
			signi(delta.x),
			signi(delta.y)
		)

		if direction != forward:
			continue

		for i in range(accepted):

			_dispatch_pulse(uid, option)

			if not running:
				return

		return

	# No forward exit means absorption.


func _all_returning_from_same_node(
	arrivals: Array
) -> bool:

	if arrivals.is_empty():
		return false

	var source: String = str(
		arrivals[0].get("from", "")
	)

	if source.is_empty():
		return false

	for item in arrivals:

		if (
			not bool(item.get("returning", false))
			or str(item.get("from", "")) != source
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

	var heading: Vector2 = state.get("incoming_heading", Vector2.ZERO)
	var options: Array[Dictionary] = _prefer_forward_links(uid, heading)

	if options.is_empty():

		_record_node_failure(
			uid,
			"Repeater has no outgoing connection"
		)
		return

	repeater_jobs.append({
		"uid": uid,
		"remaining": node.repeat_count,
		"interval": node.repeat_interval,
		"next_tick": current_tick + node.repeat_interval
	})

	state["activations"] = (
		int(state["activations"]) + 1
	)

	node.set_test_display(
		true,
		int(state["activations"]),
		false
	)

	node.set_repeater_display(
		true,
		node.repeat_count
	)


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

			var state: Dictionary = node_states[uid]
			var heading: Vector2 = state.get("incoming_heading", Vector2.ZERO)
			var options: Array[Dictionary] = _prefer_forward_links(uid, heading)

			if options.is_empty():

				_record_node_failure(
					uid,
					"Repeater has no outgoing connection"
				)
				continue

			_dispatch_pulse(uid, options[0])

			if not running:
				return

			node.play_activation_animation()

			job["remaining"] = (
				int(job["remaining"]) - 1
			)

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
# DELAY
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
		_finish(false, "Too many signals.")
		return

	var found: bool = false

	for index in range(delayed_pulses.size()):

		var batch: Dictionary = delayed_pulses[index]

		if str(batch["uid"]) != uid:
			continue

		batch["count"] = (
			int(batch["count"]) + arrival_count
		)

		delayed_pulses[index] = batch

		found = true
		break

	if not found:

		delayed_pulses.append({
			"uid": uid,
			"count": arrival_count,
			"release_tick": current_tick
				+ node.delay_ticks
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
				int(batch["release_tick"])
				- current_tick == 1
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

		var state: Dictionary = node_states[uid]
		var heading: Vector2 = state.get("incoming_heading", Vector2.ZERO)
		var options: Array[Dictionary] = _prefer_forward_links(uid, heading)

		if options.is_empty():

			_record_node_failure(
				uid,
				"Delay has no outgoing connection"
			)
			continue

		node.play_delay_release_animation()

		for index in range(int(batch["count"])):

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

		var remaining_ticks: int = (
			maxi(0, nearest - current_tick)
			if held > 0 else 0
		)

		node.set_delay_display(
			held,
			remaining_ticks
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

			_record_node_failure(
				uid,
				"Trigger Target received too many pulses"
			)
			return

	var result: Dictionary = (
		gate_rules.process_arrivals(
			uid,
			arrival_count
		)
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

	node.set_test_display(
		true,
		visual_count,
		false
	)

	node.set_blocker_open(
		gate_rules.is_open(uid)
	)

	if passed <= 0:
		return

	var heading: Vector2 = state.get("incoming_heading", Vector2.ZERO)
	var options: Array[Dictionary] = _prefer_forward_links(uid, heading)

	if options.is_empty():

		_record_node_failure(
			uid,
			"Gate passed signals but has no exit"
		)
		return

	for index in range(passed):

		_dispatch_pulse(uid, options[0])

		if not running:
			return


# ============================================================
# NONFATAL NODE FAILURE
#
# This is the key EM9 change:
# one broken branch does not stop the simulation.
# ============================================================

func _record_node_failure(
	uid: String,
	detail: String
) -> void:

	if not node_states.has(uid):
		return

	if bool(node_states[uid].get("broken", false)):
		return

	_mark_node_broken(uid)

	var message: String = (
		"Tick %d - %s: %s"
		% [current_tick, uid, detail]
	)

	node_failures.append(message)

	_set_status(
		"Issue: %s | Other signals still running"
		% message
	)


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
# OUTPUT CONNECTIONS
# ============================================================



# ============================================================
# OUTPUT CONNECTIONS
#
# Normal nodes:
#   Keep a consistent connection ordering.
#
# Alternating nodes:
#   Prefer the turning branch first.
#   Keep the same ordering for later arrivals.
#
# The actual alternating sequence is controlled
# by state["cursor"] in _activate_arrivals().
# ============================================================

# Called by PlayerMode when a draggable blocker is dropped into an
# author-defined slot. Already-travelling pulses are not cancelled.
func place_player_bridge_blocker(bridge_id: String) -> bool:
	if not test_mode or finished or player_blocked_bridges.has(bridge_id):
		return false
	if int(bridge_modes.get(bridge_id, 0)) != 5:
		return false
	player_blocked_bridges[bridge_id] = true
	_refresh_bridge_visuals()
	# Record this placement in the timeline when the simulation is running.
	if running:
		_save_snapshot()
	return true


func _bridge_record(from_uid: String, to_uid: String) -> Dictionary:
	for record in links:
		if (str(record["from_uid"]) == from_uid and str(record["to_uid"]) == to_uid) or (str(record["from_uid"]) == to_uid and str(record["to_uid"]) == from_uid):
			return record
	return {}


func _bridge_can_traverse(from_uid: String, to_uid: String) -> bool:
	var record: Dictionary = _bridge_record(from_uid, to_uid)
	if record.is_empty():
		return false
	var key: String = PortRules.bridge_key(from_uid, to_uid)
	var mode: int = int(bridge_modes.get(key, 0))
	match mode:
		1:
			return str(record["from_uid"]) == from_uid
		2:
			return str(record["to_uid"]) == from_uid
		3:
			return not reserved_one_shots.has(key) and not spent_one_shots.has(key)
		4:
			return false
		5:
			return not player_blocked_bridges.has(key)
	return true


func _on_pulse_arrived_over_bridge(pulse: Dictionary) -> void:
	var from_uid: String = str(pulse.get("from", ""))
	var to_uid: String = str(pulse.get("to", ""))
	if from_uid.is_empty() or to_uid.is_empty():
		return
	var key: String = PortRules.bridge_key(from_uid, to_uid)
	if int(bridge_modes.get(key, 0)) == 3:
		spent_one_shots[key] = true
		_refresh_bridge_visuals()


func _refresh_bridge_visuals() -> void:
	if connection_layer != null and connection_layer.has_method("set_bridge_rules"):
		connection_layer.set_bridge_rules(bridge_modes, spent_one_shots)
		if connection_layer.has_method("set_player_blocked"):
			connection_layer.set_player_blocked(player_blocked_bridges)


func _outgoing_links(
	uid: String
) -> Array[Dictionary]:

	var choices: Array[Dictionary] = PortRules.incident_links(
		uid, links, builder.nodes_by_id, allow_reverse_connections
	)

	# These rules are constraints on each bridge, independent of
	# the level-wide reversible flag or the orientation of a rotor.
	var permitted: Array[Dictionary] = []
	for choice in choices:
		if _bridge_can_traverse(uid, str(choice["to"])):
			permitted.append(choice)
	choices = permitted

	# ====================================================
	# CHECK FOR ALTERNATING NODE
	# ====================================================

	var is_alternating: bool = false

	if builder.nodes_by_id.has(uid):

		var node: PuzzleNode = builder.nodes_by_id[uid]

		is_alternating = (
			node.kind == PuzzleNode.Kind.ALTERNATING
		)

	# ====================================================
	# ALTERNATING: TURN-FIRST ORDERING
	# ====================================================

	if is_alternating and node_states.has(uid):

		var state: Dictionary = node_states[uid]

		# Remember the direction of the first signal.
		if not state.has("alternating_reference_heading"):

			state["alternating_reference_heading"] = (
				state.get(
					"incoming_heading",
					Vector2.ZERO
				)
			)

		var heading: Vector2 = state.get(
			"alternating_reference_heading",
			Vector2.ZERO
		)

		if heading.length_squared() > 0.001:

			choices.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:

					var a_path: Array = a["path"]
					var b_path: Array = b["path"]

					var a_exit: Vector2 = (
						grid.cell_to_local(a_path[1])
						- grid.cell_to_local(a_path[0])
					).normalized()

					var b_exit: Vector2 = (
						grid.cell_to_local(b_path[1])
						- grid.cell_to_local(b_path[0])
					).normalized()

					var a_score: float = (
						heading.dot(a_exit)
					)

					var b_score: float = (
						heading.dot(b_exit)
					)

					# The smaller score is the larger
					# turn, so it comes first.
					if absf(a_score - b_score) > 0.0001:
						return a_score < b_score

					# If both turns are equally large,
					# favour the visually higher exit.
					if absf(a_exit.y - b_exit.y) > 0.0001:
						return a_exit.y < b_exit.y

					# Consistent final tie-breaker.
					return str(a["to"]) < str(b["to"])
			)

			return choices

	# ====================================================
	# DEFAULT CONNECTION ORDERING
	# ====================================================

	choices.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:

			var a_path: Array = a["path"]
			var b_path: Array = b["path"]

			var a_direction: Vector2i = (
				a_path[1] - a_path[0]
			)

			var b_direction: Vector2i = (
				b_path[1] - b_path[0]
			)

			var a_rank: int = (
				_direction_rank(a_direction)
			)

			var b_rank: int = (
				_direction_rank(b_direction)
			)

			if a_rank == b_rank:
				return str(a["to"]) < str(b["to"])

			return a_rank < b_rank
	)

	return choices



# ============================================================
# INCOMING SIGNAL DIRECTION
#
# Uses actual grid positions, so it works for
# both Square and X-stretched Rhombus.
# ============================================================

func _get_incoming_heading(
	arrivals: Array
) -> Vector2:

	var heading := Vector2.ZERO

	for arrival in arrivals:

		var path: Array = arrival.get("path", [])

		if path.size() < 2:
			continue

		var previous_cell: Vector2i = path[
			path.size() - 2
		]

		var final_cell: Vector2i = path[
			path.size() - 1
		]

		var direction: Vector2 = (
			grid.cell_to_local(final_cell)
			- grid.cell_to_local(previous_cell)
		)

		if direction.length_squared() > 0.001:
			heading += direction.normalized()

	if heading.length_squared() < 0.001:
		return Vector2.ZERO

	return heading.normalized()


# ============================================================
# PREFER FORWARD OUTGOING CONNECTIONS
#
# Score = 1.0  : straight ahead
# Score = 0.0  : perpendicular
# Score = -1.0 : reverse
#
# The best matching direction comes first.
# ============================================================

func _prefer_forward_links(
	uid: String,
	incoming_heading: Vector2
) -> Array[Dictionary]:

	var options: Array[Dictionary] = (
		_outgoing_links(uid)
	)

	if allow_reverse_connections and node_states.has(uid):
		var source_uid: String = str(node_states[uid].get("incoming_from", ""))
		if not source_uid.is_empty():
			var forward_only: Array[Dictionary] = []
			for option in options:
				if str(option["to"]) != source_uid:
					forward_only.append(option)
			options = forward_only

	if incoming_heading.length_squared() < 0.001:
		return options

	options.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:

			var a_path: Array = a["path"]
			var b_path: Array = b["path"]

			var a_heading: Vector2 = (
				grid.cell_to_local(a_path[1])
				- grid.cell_to_local(a_path[0])
			).normalized()

			var b_heading: Vector2 = (
				grid.cell_to_local(b_path[1])
				- grid.cell_to_local(b_path[0])
			).normalized()

			var a_score: float = (
				incoming_heading.dot(a_heading)
			)

			var b_score: float = (
				incoming_heading.dot(b_heading)
			)

			if absf(a_score - b_score) < 0.0001:
				return str(a["to"]) < str(b["to"])

			return a_score > b_score
	)

	return options



func _direction_rank(direction: Vector2i) -> int:

	if direction.y < 0:
		return 0

	if direction.x > 0:
		return 1

	if direction.y > 0:
		return 2

	return 3


# ============================================================
# DISPATCH SIGNAL
# ============================================================


func _dispatch_pulse(
	from_uid: String,
	choice: Dictionary
) -> void:
	# Alternating display changes are handled by
	# _activate_alternating(), AFTER its cursor advances.
	# All other node types retain their normal dispatch.
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
	if not _bridge_can_traverse(from_uid, to_uid):
		# The bridge diode, closed blocker or a spent single-use
		# segment absorbs this attempted departure.
		return

	var length: int = _path_length(path)
	if length <= 0:
		_finish(false, "Invalid pulse route.")
		return
	if (
		pulses.size() + _count_held_signals()
		+ _pending_repeater_emissions() + wormhole_jobs.size() >= MAX_ACTIVE_PULSES
	):
		_finish(false, "Too many active pulses.")
		return

	var key: String = PortRules.bridge_key(from_uid, to_uid)
	if int(bridge_modes.get(key, 0)) == 3:
		# Reserve immediately to stop a second pulse entering while
		# the first is in flight; visibly burn only on arrival.
		reserved_one_shots[key] = true

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

	for index in range(path.size() - 1):

		var difference: Vector2i = (
			path[index + 1] - path[index]
		)

		length += maxi(
			absi(difference.x),
			absi(difference.y)
		)

	return length


# ============================================================
# COMPLETION
#
# Wait for all activity before reporting outcome.
# ============================================================

func _check_completion() -> void:

	if (
		not pulses.is_empty()
		or not delayed_pulses.is_empty()
		or not repeater_jobs.is_empty()
		or not wormhole_jobs.is_empty()
	):
		return

	if not node_failures.is_empty():

		_finish(
			false,
			"%d node issue(s), Goals %d/%d. First: %s"
			% [
				node_failures.size(),
				targets_reached,
				targets_total,
				node_failures[0]
			]
		)

	elif (
		targets_total > 0
		and targets_reached == targets_total
	):

		_finish(
			true,
			"All Goal Targets filled; all signals resolved."
		)

	else:

		_finish(
			false,
			"No signals remaining. Goals %d/%d."
			% [targets_reached, targets_total]
		)


func _finish(
	success: bool,
	reason: String
) -> void:

	running = false
	finished = true
	failure_reason = reason

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
# DRAWING
# ============================================================

func _draw() -> void:

	if not test_mode or grid == null:
		return

	if show_node_state_rings:
		_draw_node_rings()

	_draw_pulses()


func _draw_node_rings() -> void:

	for uid in node_states.keys():

		if not builder.nodes_by_id.has(uid):
			continue

		var node: PuzzleNode = builder.nodes_by_id[uid]
		var state: Dictionary = node_states[uid]
		var centre: Vector2 = to_local(node.global_position)

		# In Player Mode, nodes live inside a scaled wrapper.
		# In the Builder, their parent has scale 1.0.
		# This keeps activation/reached rings matched to each node.
		var visual_scale: float = 1.0
		var parent_2d: Node2D = node.get_parent() as Node2D
		if parent_2d != null and parent_2d.has_meta("em_player_visual_wrapper"):
			visual_scale = parent_2d.scale.x

		if bool(state["broken"]):
			draw_arc(
				centre, 29.0 * visual_scale, 0.0, TAU, 40,
				Color("#ff4545"), 4.0 * visual_scale, true
			)

		elif bool(state["reached"]):
			var color: Color = (
				node.get_channel_color()
				if node.kind == PuzzleNode.Kind.TRIGGER_TARGET
				else TARGET_REACHED_COLOR
			)
			draw_arc(
				centre, 29.0 * visual_scale, 0.0, TAU, 40,
				color, 4.0 * visual_scale, true
			)

		elif (
			_is_gate_rule_node(node)
			or node.kind == PuzzleNode.Kind.DELAY
			or node.kind == PuzzleNode.Kind.REPEATER
			or node.kind == PuzzleNode.Kind.BOUNCE
			or node.kind == PuzzleNode.Kind.ALTERNATING
		):
			continue

		elif int(state["activations"]) > 0:
			var elapsed: int = current_tick - int(state["last_tick"])
			var color: Color = (
				PULSE_COLOR if elapsed <= 0 else REFRACTORY_COLOR
			)
			if node.has_unlimited_activations() or elapsed > node.refractory_ticks:
				color = Color("#64748b")
			draw_arc(
				centre, 28.0 * visual_scale, 0.0, TAU, 40,
				color, 3.0 * visual_scale, true
			)


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

		var group_size: int = int(
			overlap_counts.get(key, 1)
		)

		var lane: int = int(
			drawn_counts.get(key, 0)
		)

		drawn_counts[key] = lane + 1

		var elapsed: float = (
			float(
				current_tick - int(pulse["start_tick"])
			)
			+ fractional_tick
		)

		var distance: float = clampf(
			elapsed,
			0.0,
			float(pulse["duration"])
		)

		# Fading pulse trail.
		if (
			trail_length_cells > 0.0
			and trail_opacity > 0.0
		):

			for sample in range(
				trail_samples, 0, -1
			):

				var behind: float = (
					trail_length_cells
					* float(sample)
					/ float(trail_samples)
				)

				var trail_distance: float = (
					distance - behind
				)

				if trail_distance < 0.0:
					continue

				var trail: Dictionary = (
					_pulse_visual_data(
						pulse,
						trail_distance,
						elapsed - behind,
						lane,
						group_size
					)
				)

				var color: Color = trail["color"]

				var strength: float = (
					1.0
					- float(sample)
					/ float(trail_samples + 1)
				)

				color.a = (
					trail_opacity
					* strength
					* strength
				)

				var radius: float = (
					float(trail["radius"])
					* (0.2 + 0.65 * strength)
				)

				var centre: Vector2 = to_local(
					grid.to_global(
						trail["position"]
					)
				)

				draw_circle(
					centre,
					radius,
					color
				)

		var visual: Dictionary = (
			_pulse_visual_data(
				pulse,
				distance,
				elapsed,
				lane,
				group_size
			)
		)

		var centre: Vector2 = to_local(
			grid.to_global(visual["position"])
		)

		var radius: float = float(
			visual["radius"]
		)

		draw_circle(
			centre,
			radius,
			visual["color"]
		)

		draw_arc(
			centre,
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
		connection_layer.get_visual_point(
			path,
			distance
		)
	)

	var color: Color = PULSE_COLOR
	var radius: float = base_pulse_radius

	if group_size > 1:

		var phase: float = (
			TAU * distance
				/ maxf(wavelength_cells, 0.01)
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
			.orthogonal()
			.normalized()
		)

		var fraction: float = clampf(
			distance
				/ maxf(float(pulse["duration"]), 1.0),
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
				+ cos(orbit_angle)
				* size_variation
				* fade
		)

		if lane % 2 == 1:
			color = SECOND_PULSE_COLOR

	return {
		"position": position,
		"color": color,
		"radius": radius
	}


func _pulse_overlap_key(
	pulse: Dictionary
) -> String:

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

	var p0: Vector2 = (
		connection_layer.get_visual_point(
			path, before
		)
	)

	var p1: Vector2 = (
		connection_layer.get_visual_point(
			path, after
		)
	)

	var direction: Vector2 = p1 - p0

	if direction.length_squared() > 0.0001:
		return direction.normalized()

	return Vector2.RIGHT


# ============================================================
# TIMELINE CONTROLS
# ============================================================

func _on_speed_selected(index: int) -> void:

	match index:
		0: playback_speed = 0.5
		1: playback_speed = 1.0
		2: playback_speed = 2.0
		3: playback_speed = 4.0


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

	step_back_button.disabled = (
		timeline_cursor <= 0
	)

	step_forward_button.disabled = (
		selected_start_id.is_empty()
		or (
			finished
			and timeline_cursor >= timeline.size() - 1
		)
	)


# ============================================================
# SNAPSHOTS
# ============================================================

func _save_snapshot() -> void:

	if timeline_cursor + 1 < timeline.size():
		timeline.resize(timeline_cursor + 1)

	var snapshot: Dictionary = {
		"tick": current_tick,
		"running": running,
		"finished": finished,
		"failure_reason": failure_reason,
		"node_failures": node_failures.duplicate(),
		"status": (
			status_label.text
			if status_label != null
			else ""
		),
		"pulses": pulses.duplicate(true),
		"reserved_one_shots": reserved_one_shots.duplicate(true),
		"spent_one_shots": spent_one_shots.duplicate(true),
		"player_blocked_bridges": player_blocked_bridges.duplicate(true),
		"delayed_pulses": delayed_pulses.duplicate(true),
		"repeater_jobs": repeater_jobs.duplicate(true),
		"wormhole_jobs": wormhole_jobs.duplicate(true),
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

	node_failures.assign(
		snapshot.get("node_failures", [])
	)

	pulses.assign(
		snapshot["pulses"].duplicate(true)
	)
	reserved_one_shots = snapshot.get("reserved_one_shots", {}).duplicate(true)
	spent_one_shots = snapshot.get("spent_one_shots", {}).duplicate(true)
	player_blocked_bridges = snapshot.get("player_blocked_bridges", {}).duplicate(true)
	_refresh_bridge_visuals()

	delayed_pulses.assign(
		snapshot["delayed_pulses"].duplicate(true)
	)

	repeater_jobs.assign(
		snapshot["repeater_jobs"].duplicate(true)
	)
	wormhole_jobs.assign(snapshot.get("wormhole_jobs", []).duplicate(true))

	node_states = (
		snapshot["node_states"].duplicate(true)
	)

	targets_reached = int(
		snapshot["targets_reached"]
	)

	gate_rules.states = (
		snapshot["gate_states"].duplicate(true)
	)

	gate_rules.unlocked_channels = (
		snapshot["gate_channels"].duplicate(true)
	)

	timeline_cursor = index
	paused = true
	tick_accumulator = 0.0

	tick_label.text = (
		"Tick: %d" % current_tick
	)

	_set_status(str(snapshot["status"]))

	_refresh_snapshot_node_visuals()
	_refresh_timeline_ui()
	queue_redraw()



func _refresh_snapshot_node_visuals() -> void:

	for key in builder.nodes_by_id.keys():

		var uid: String = str(key)
		var node: PuzzleNode = builder.nodes_by_id[uid]
		var state: Dictionary = node_states[uid]

		node.clear_test_display()
		node.runtime_wormhole_flash = 0.0

		node.set_test_display(
			true,
			int(state["activations"]),
			bool(state["broken"])
		)

		node.pop_time_remaining = 0.0
		node.scale = Vector2.ONE
		node.rotation = node.resting_rotation

		if node.kind == PuzzleNode.Kind.ALTERNATING:

			node.set_alternating_display(
				int(
					state.get(
						"alternating_last_exit",
						-1
					)
				)
			)

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




# ============================================================
# ALTERNATING NODE ACTIVATION
#
# - Each signal is processed independently
# - Signals may arrive on different ticks
# - Initial branch is configurable
# - Direction changes after each accepted signal
# - Activation cap counts individual signals
# - Refractory timing does not block alternation
# ============================================================

func _activate_alternating(
	uid: String,
	node: PuzzleNode,
	state: Dictionary,
	arrivals: Array
) -> void:
	if bool(state.get("broken", false)):
		return

	var live_grid: SquarePuzzleGrid = grid as SquarePuzzleGrid
	var honeycomb_rotor: bool = (
		allow_reverse_connections
		and live_grid != null
		and live_grid.is_honeycomb()
	)
	var ports: Array[Dictionary] = []
	if honeycomb_rotor:
		ports = PortRules.three_way_ports(
			uid, links, builder.nodes_by_id, grid
		)
		if ports.size() != 3:
			honeycomb_rotor = false

	# NEW: Three-port rotor has one CLOSED arm (red) and two OPEN
	# arms (white). A signal entering an open arm exits the other one.
	# The red arm rotates clockwise after each accepted signal.
	if honeycomb_rotor:
		var cursor: int = int(state.get("cursor", 0))
		var used: int = int(state.get("activations", 0))
		for arrival in arrivals:
			var blocked_index: int = posmod(int(node.port_rotation_steps) + cursor, 3)
			var from_uid: String = str(arrival.get("from", ""))
			var incoming_index: int = -1
			for i in range(3):
				if str(ports[i]["to"]) == from_uid:
					incoming_index = i
					break

			# Red port cannot receive or send. Blocked arrivals are absorbed
			# without turning the rotor or consuming an activation.
			if incoming_index == blocked_index:
				continue
			if used >= node.activation_cap:
				_record_node_failure(uid, "Alternating Node capacity exceeded")
				return
			if incoming_index < 0:
				_record_node_failure(uid, "Alternating Node arrival is not on an attached port")
				return

			var exit_index: int = -1
			for i in range(3):
				if i != blocked_index and i != incoming_index:
					exit_index = i
					break
			if exit_index < 0:
				return
			var option: Dictionary = ports[exit_index]
			if not _bridge_can_traverse(uid, str(option["to"])):
				# An external diode or player bridge blocker may prevent
				# departure; the pulse is absorbed without a second path.
				continue
			_dispatch_pulse(uid, option)
			if not running:
				return
			used += 1
			cursor += 1
			state["activations"] = used
			state["cursor"] = cursor
			state["last_tick"] = current_tick
			var next_closed: int = posmod(int(node.port_rotation_steps) + cursor, 3)
			state["alternating_last_exit"] = next_closed
			node.set_test_display(true, used, false)
			node.set_alternating_display(next_closed)
		return

	# The original two-position logic is unchanged for Square,
	# Rhombus, and older directed Honeycomb puzzles.
	var options: Array[Dictionary] = _outgoing_links(uid)
	if allow_reverse_connections:
		var authored: Array[Dictionary] = []
		for option in options:
			if not bool(option.get("reversed", false)):
				authored.append(option)
		options = authored
	options.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ap: Array = a["path"]
			var bp: Array = b["path"]
			var da: Vector2 = (grid.cell_to_local(ap[1]) - grid.cell_to_local(ap[0])).normalized()
			var db: Vector2 = (grid.cell_to_local(bp[1]) - grid.cell_to_local(bp[0])).normalized()
			if absf(da.y - db.y) > 0.0001:
				return da.y < db.y
			return str(a["to"]) < str(b["to"])
	)
	if options.is_empty():
		_record_node_failure(uid, "Alternating Node has no exit")
		return
	var legacy_cursor: int = int(state.get("legacy_cursor", 0))
	var legacy_used: int = int(state.get("activations", 0))
	for _arrival in arrivals:
		if legacy_used >= node.activation_cap:
			_record_node_failure(uid, "Alternating Node capacity exceeded")
			return
		var selected: int = posmod(int(node.alternating_first_branch) + legacy_cursor, options.size())
		var chosen: Dictionary = options[selected]
		if not _bridge_can_traverse(uid, str(chosen["to"])):
			_record_node_failure(uid, "Selected Alternating port is blocked")
			return
		_dispatch_pulse(uid, chosen)
		if not running:
			return
		legacy_used += 1
		legacy_cursor += 1
		state["activations"] = legacy_used
		state["legacy_cursor"] = legacy_cursor
		state["last_tick"] = current_tick
		var next_index: int = posmod(int(node.alternating_first_branch) + legacy_cursor, options.size())
		state["alternating_last_exit"] = next_index
		node.set_test_display(true, legacy_used, false)
		node.set_alternating_display(next_index)
